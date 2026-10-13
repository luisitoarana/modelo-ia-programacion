"""Transformer decoder v2 — arquitectura SOTA (estado del arte 2024-2025).

Mejoras vs `transformer.py` v1:

    1. **RoPE** (Rotary Position Embeddings) en lugar de PositionalEncoding
       sinusoidal aditivo. Permite extender el contexto sin re-entrenar y
       generaliza mejor a posiciones largas. Usado por Llama 2/3, Qwen,
       DeepSeek, Mistral, Gemma.

    2. **GQA** (Grouped-Query Attention) con `n_kv_head <= n_head`. Cada
       grupo de heads de query comparte las mismas matrices K y V, lo que
       reduce el KV-cache 4-8× y acelera la inferencia con contextos
       largos. Llama 2 70B introdujo esta técnica.

    3. **SwiGLU** en el feed-forward (en lugar de GeLU en MLP de 2 capas).
       Usa 3 lineales con un gate sigmoide: `silu(W_gate(x)) * W_up(x)`.
       Aporta ~2-4% de calidad gratis con la misma cantidad de params.

    4. **RMSNorm** en lugar de LayerNorm. Solo normaliza por la raíz
       cuadrada media (sin centrar). Es ~7% más rápido y matemáticamente
       más simple. Estándar en Llama, Mistral.

    5. **FlashAttention v2** (vía `F.scaled_dot_product_attention`).
       PyTorch elige el kernel óptimo automáticamente (Flash en GPU,
       memoria eficiente en CPU). 3-10× más rápido y NO materializa la
       matriz N×N en memoria → habilita contextos largos sin OOM.

Compatibilidad de interfaz: la clase final `GPTEducativoV2` expone
exactamente los mismos métodos públicos que `GPTEducativo` (v1):
    - `forward(idx, targets=None) -> (logits, loss)`
    - `generar(idx, max_new_tokens, ...) -> tensor`
    - `num_parametros(solo_entrenables=True) -> int`
    - `configurar_optimizador(...) -> torch.optim.Optimizer`

Esto permite intercambiar v1 ↔ v2 sin tocar el resto del pipeline
(train.py, generate.py, model_inference_service.py).

Referencias:
    - RoPE: Su et al., "RoFormer", 2021.
    - GQA: Ainslie et al., "GQA", 2023.
    - SwiGLU: Shazeer, "GLU Variants Improve Transformer", 2020.
    - RMSNorm: Zhang & Sennrich, "Root Mean Square Layer Normalization", 2019.
    - FlashAttention: Dao et al., "FlashAttention", 2022.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import torch
import torch.nn as nn
import torch.nn.functional as F


# ════════════════════════════════════════════════════════════════════
# Config v2 — extiende ModelConfig con campos nuevos.
# ════════════════════════════════════════════════════════════════════

@dataclass(slots=True)
class ModelConfigV2:
    """Hiperparámetros del Transformer v2 (SOTA)."""

    vocab_size: int = 16000
    block_size: int = 512               # contexto en tokens
    n_layer: int = 8
    n_head: int = 8
    n_embd: int = 512
    dropout: float = 0.0                # SOTA usa 0 en pretraining

    # ── Nuevo en v2 ──
    n_kv_head: int = 2                  # GQA: heads que comparten K/V
    rope_theta: float = 10_000.0        # base de las frecuencias RoPE
    swiglu_mult: float = 8 / 3          # tamaño del hidden de SwiGLU (rel. a n_embd)
    norm_eps: float = 1e-6              # ε de RMSNorm
    bias: bool = False                  # SOTA típicamente sin bias en linears
    tie_weights: bool = True

    def __post_init__(self) -> None:
        if self.n_embd % self.n_head != 0:
            raise ValueError(
                f"n_embd ({self.n_embd}) debe ser múltiplo de n_head ({self.n_head})"
            )
        if self.n_head % self.n_kv_head != 0:
            raise ValueError(
                f"n_head ({self.n_head}) debe ser múltiplo de n_kv_head "
                f"({self.n_kv_head}) para GQA"
            )

    @property
    def head_dim(self) -> int:
        return self.n_embd // self.n_head

    @property
    def n_query_per_kv(self) -> int:
        """Heads de query que comparten cada par K/V (factor GQA)."""
        return self.n_head // self.n_kv_head


# ════════════════════════════════════════════════════════════════════
# RMSNorm — más simple y rápida que LayerNorm.
# ════════════════════════════════════════════════════════════════════

class RMSNorm(nn.Module):
    """Root Mean Square LayerNorm — sin centrar, solo escalar.

    Fórmula:
        y = x / sqrt(mean(x²) + ε) * g

    Donde `g` es un parámetro entrenable. No hay bias, no hay sustracción
    de media. ~7% más rápido que LayerNorm con resultados equivalentes.
    """

    def __init__(self, dim: int, eps: float = 1e-6) -> None:
        super().__init__()
        self.eps = eps
        self.peso = nn.Parameter(torch.ones(dim))

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # Calcular en fp32 para estabilidad numérica.
        original_dtype = x.dtype
        x = x.float()
        norm = x * torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + self.eps)
        return (self.peso * norm).to(original_dtype)


# ════════════════════════════════════════════════════════════════════
# RoPE — Rotary Position Embeddings.
# ════════════════════════════════════════════════════════════════════

def precomputar_rope(head_dim: int, max_seq_len: int, theta: float,
                     device: torch.device | None = None) -> tuple[torch.Tensor, torch.Tensor]:
    """Precomputa `cos` y `sin` para todas las posiciones hasta max_seq_len.

    RoPE divide cada vector de dimensión `head_dim` en pares (i, i+1) y
    los rota por un ángulo que depende de la posición y de la frecuencia
    asignada al par. Las frecuencias siguen una progresión geométrica:

        θ_i = theta ^ (-2i / head_dim)   para i ∈ [0, head_dim/2)

    Returns:
        cos: (max_seq_len, head_dim/2)
        sin: (max_seq_len, head_dim/2)
    """
    inv_freq = 1.0 / (theta ** (
        torch.arange(0, head_dim, 2, dtype=torch.float32, device=device) / head_dim
    ))
    pos = torch.arange(max_seq_len, dtype=torch.float32, device=device)
    freqs = torch.outer(pos, inv_freq)  # (max_seq_len, head_dim/2)
    return freqs.cos(), freqs.sin()


def aplicar_rope(q: torch.Tensor, k: torch.Tensor,
                 cos: torch.Tensor, sin: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
    """Aplica RoPE a Q y K: rota los pares (i, i+1) por el ángulo de cada posición.

    q, k: (B, n_head, T, head_dim)
    cos, sin: (T, head_dim/2) — pre-calculados para esta secuencia
    """
    # Reinterpretar la última dim como pares: (..., head_dim/2, 2)
    def _rotar(x: torch.Tensor) -> torch.Tensor:
        # Split en mitades: x[..., 0:head_dim/2] y x[..., head_dim/2:]
        # (es equivalente a pares pero más eficiente).
        x1, x2 = x.chunk(2, dim=-1)
        # cos y sin tienen shape (T, head_dim/2). Broadcasting con (B, h, T, head_dim/2)
        return torch.cat([x1 * cos - x2 * sin, x1 * sin + x2 * cos], dim=-1)

    return _rotar(q), _rotar(k)


# ════════════════════════════════════════════════════════════════════
# Atención causal con GQA + Flash.
# ════════════════════════════════════════════════════════════════════

class GroupedQueryAttention(nn.Module):
    """Atención multi-cabeza con `n_kv_head <= n_head` (GQA).

    En MHA estándar (n_kv_head = n_head): cada head tiene su propio K y V.
    En GQA: n_head heads de query comparten n_kv_head pares (K, V).

    Ventaja: el KV-cache durante inferencia es n_head/n_kv_head veces
    más chico. Para nuestro preset (n_head=8, n_kv_head=2) eso es 4× menos
    memoria, lo que habilita contextos más largos en VRAM limitada.

    Usa `F.scaled_dot_product_attention` que internamente elige
    FlashAttention v2 cuando es posible (GPU con CUDA + dtype float16/bfloat16).
    """

    def __init__(self, cfg: ModelConfigV2) -> None:
        super().__init__()
        self.n_head = cfg.n_head
        self.n_kv_head = cfg.n_kv_head
        self.head_dim = cfg.head_dim
        self.n_query_per_kv = cfg.n_query_per_kv

        # Q proyecta a (n_head * head_dim); K, V a (n_kv_head * head_dim)
        self.wq = nn.Linear(cfg.n_embd, cfg.n_head * cfg.head_dim, bias=cfg.bias)
        self.wk = nn.Linear(cfg.n_embd, cfg.n_kv_head * cfg.head_dim, bias=cfg.bias)
        self.wv = nn.Linear(cfg.n_embd, cfg.n_kv_head * cfg.head_dim, bias=cfg.bias)
        self.wo = nn.Linear(cfg.n_head * cfg.head_dim, cfg.n_embd, bias=cfg.bias)

        self.dropout_p = cfg.dropout

    def forward(self, x: torch.Tensor,
                cos: torch.Tensor, sin: torch.Tensor) -> torch.Tensor:
        B, T, C = x.shape

        # Proyecciones
        q = self.wq(x).view(B, T, self.n_head, self.head_dim).transpose(1, 2)
        k = self.wk(x).view(B, T, self.n_kv_head, self.head_dim).transpose(1, 2)
        v = self.wv(x).view(B, T, self.n_kv_head, self.head_dim).transpose(1, 2)
        # q: (B, n_head, T, head_dim)
        # k, v: (B, n_kv_head, T, head_dim)

        # Aplicar RoPE a Q y K (no a V — los values no rotan)
        q, k = aplicar_rope(q, k, cos[:T], sin[:T])

        # Expandir K y V para compartir entre los grupos de query.
        # (B, n_kv_head, T, hd) -> (B, n_head, T, hd) repitiendo cada head
        # `n_query_per_kv` veces. Esto es lo que cierra el "grouped".
        if self.n_query_per_kv > 1:
            k = k.repeat_interleave(self.n_query_per_kv, dim=1)
            v = v.repeat_interleave(self.n_query_per_kv, dim=1)

        # FlashAttention vía PyTorch (auto-selecciona el mejor kernel).
        # is_causal=True añade la máscara triangular automáticamente.
        y = F.scaled_dot_product_attention(
            q, k, v,
            attn_mask=None,
            dropout_p=self.dropout_p if self.training else 0.0,
            is_causal=True,
        )
        # y: (B, n_head, T, head_dim) -> (B, T, n_head * head_dim)
        y = y.transpose(1, 2).contiguous().view(B, T, self.n_head * self.head_dim)

        return self.wo(y)


# ════════════════════════════════════════════════════════════════════
# SwiGLU FeedForward — feed-forward con gating sigmoide.
# ════════════════════════════════════════════════════════════════════

class SwiGLU(nn.Module):
    """FFN con SwiGLU activation.

    Diseño:
        hidden = silu(W_gate(x)) * W_up(x)
        out    = W_down(hidden)

    Tres lineales en lugar de los dos clásicos. La SiLU (también
    llamada Swish) tiene mejor gradient flow que GeLU. El gating
    sigmoide actúa como filtro: deja pasar info útil, bloquea ruido.

    Llama, Mistral, Gemma, Qwen — todos usan SwiGLU.
    """

    def __init__(self, n_embd: int, mult: float = 8 / 3, bias: bool = False) -> None:
        super().__init__()
        # hidden = round_to_multiple_of_64(n_embd * mult)
        # Multiplexar a 64 ayuda al hardware (tensor cores).
        hidden = int(n_embd * mult)
        hidden = ((hidden + 63) // 64) * 64

        self.w_gate = nn.Linear(n_embd, hidden, bias=bias)
        self.w_up = nn.Linear(n_embd, hidden, bias=bias)
        self.w_down = nn.Linear(hidden, n_embd, bias=bias)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.w_down(F.silu(self.w_gate(x)) * self.w_up(x))


# ════════════════════════════════════════════════════════════════════
# Bloque Transformer v2 (pre-norm con RMSNorm).
# ════════════════════════════════════════════════════════════════════

class BloqueV2(nn.Module):
    """Bloque Transformer pre-norm con RMSNorm + GQA + SwiGLU."""

    def __init__(self, cfg: ModelConfigV2) -> None:
        super().__init__()
        self.norm1 = RMSNorm(cfg.n_embd, eps=cfg.norm_eps)
        self.attn = GroupedQueryAttention(cfg)
        self.norm2 = RMSNorm(cfg.n_embd, eps=cfg.norm_eps)
        self.ffn = SwiGLU(cfg.n_embd, mult=cfg.swiglu_mult, bias=cfg.bias)

    def forward(self, x: torch.Tensor,
                cos: torch.Tensor, sin: torch.Tensor) -> torch.Tensor:
        x = x + self.attn(self.norm1(x), cos, sin)
        x = x + self.ffn(self.norm2(x))
        return x


# ════════════════════════════════════════════════════════════════════
# Modelo final — interfaz idéntica al v1 para sustituirlo sin tocar nada.
# ════════════════════════════════════════════════════════════════════

class GPTEducativoV2(nn.Module):
    """GPT decoder-only con arquitectura SOTA 2024-2025."""

    def __init__(self, cfg: ModelConfigV2) -> None:
        super().__init__()
        self.cfg = cfg
        self._gradient_checkpointing = False

        # Embedding de tokens (RoPE no necesita embedding posicional aditivo).
        self.tok_emb = nn.Embedding(cfg.vocab_size, cfg.n_embd)
        self.drop = nn.Dropout(cfg.dropout)

        # Bloques apilados.
        self.bloques = nn.ModuleList([BloqueV2(cfg) for _ in range(cfg.n_layer)])

        # Norma final + LM head.
        self.norm_final = RMSNorm(cfg.n_embd, eps=cfg.norm_eps)
        self.lm_head = nn.Linear(cfg.n_embd, cfg.vocab_size, bias=False)

        # Weight tying: el embedding y el LM head comparten matriz.
        if cfg.tie_weights:
            self.lm_head.weight = self.tok_emb.weight

        # Pre-computar RoPE para el bloque máximo. Si en inferencia
        # alguien pasa una secuencia más larga, recomputamos al vuelo.
        cos, sin = precomputar_rope(
            cfg.head_dim, cfg.block_size, cfg.rope_theta,
        )
        self.register_buffer("rope_cos", cos, persistent=False)
        self.register_buffer("rope_sin", sin, persistent=False)

        # Inicialización (estilo GPT-2).
        self.apply(self._init_pesos)

    def gradient_checkpointing_enable(self) -> None:
        """Activa gradient checkpointing: recomputa activaciones en backward
        en lugar de almacenarlas. Reduce VRAM ~2-3× a costa de ~30% más tiempo.

        Clave para entrenar modelos B (120M) y C (350M) en RTX 2050 4GB."""
        self._gradient_checkpointing = True

    def gradient_checkpointing_disable(self) -> None:
        self._gradient_checkpointing = False

    @staticmethod
    def _init_pesos(modulo: nn.Module) -> None:
        if isinstance(modulo, nn.Linear):
            nn.init.normal_(modulo.weight, mean=0.0, std=0.02)
            if modulo.bias is not None:
                nn.init.zeros_(modulo.bias)
        elif isinstance(modulo, nn.Embedding):
            nn.init.normal_(modulo.weight, mean=0.0, std=0.02)

    def num_parametros(self, solo_entrenables: bool = True) -> int:
        if solo_entrenables:
            return sum(p.numel() for p in self.parameters() if p.requires_grad)
        return sum(p.numel() for p in self.parameters())

    def _rope_para_longitud(self, T: int, device: torch.device,
                            dtype: torch.dtype) -> tuple[torch.Tensor, torch.Tensor]:
        """Obtiene (cos, sin) para una secuencia de longitud T. Recomputa
        si T > block_size (útil para extrapolación)."""
        if T <= self.rope_cos.size(0):
            return self.rope_cos[:T].to(dtype), self.rope_sin[:T].to(dtype)
        # Caso raro: pedir más contexto del entrenado. Recomputamos.
        cos, sin = precomputar_rope(
            self.cfg.head_dim, T, self.cfg.rope_theta, device=device,
        )
        return cos.to(dtype), sin.to(dtype)

    def forward(self, idx: torch.Tensor,
                targets: torch.Tensor | None = None
                ) -> tuple[torch.Tensor, torch.Tensor | None]:
        B, T = idx.shape

        # Embedding + dropout
        x = self.drop(self.tok_emb(idx))

        # RoPE (compartido entre todos los bloques)
        cos, sin = self._rope_para_longitud(T, idx.device, x.dtype)

        # Pila de bloques (con gradient checkpointing opcional)
        if self._gradient_checkpointing and self.training:
            for bloque in self.bloques:
                x = torch.utils.checkpoint.checkpoint(
                    bloque, x, cos, sin, use_reentrant=False,
                )
        else:
            for bloque in self.bloques:
                x = bloque(x, cos, sin)

        x = self.norm_final(x)
        logits = self.lm_head(x)

        loss = None
        if targets is not None:
            loss = F.cross_entropy(
                logits.view(-1, logits.size(-1)),
                targets.view(-1),
                ignore_index=-100,
            )

        return logits, loss

    @torch.no_grad()
    def generar(self, idx: torch.Tensor, max_new_tokens: int,
                temperatura: float = 1.0,
                top_k: int | None = None,
                top_p: float | None = None,
                eos_token: int | None = None,
                repetition_penalty: float = 1.0) -> torch.Tensor:
        """Genera autoregresivamente tokens nuevos."""
        for _ in range(max_new_tokens):
            # Si la secuencia crece más allá del block_size, cortamos
            # el contexto a los últimos block_size tokens.
            idx_cond = idx if idx.size(1) <= self.cfg.block_size \
                else idx[:, -self.cfg.block_size:]
            logits, _ = self(idx_cond)
            logits = logits[:, -1, :]

            # Penalización de repetición para evitar bucles de alucinación
            if repetition_penalty != 1.0 and idx.size(1) > 0:
                tokens_previos = torch.unique(idx[0])
                for t in tokens_previos:
                    val = logits[0, t]
                    if val > 0:
                        logits[0, t] = val / repetition_penalty
                    else:
                        logits[0, t] = val * repetition_penalty

            logits = logits / max(temperatura, 1e-6)

            if top_k is not None:
                logits = self._filtrar_top_k(logits, top_k)
            if top_p is not None:
                logits = self._filtrar_top_p(logits, top_p)

            probs = F.softmax(logits, dim=-1)
            sig = torch.multinomial(probs, num_samples=1)
            idx = torch.cat([idx, sig], dim=1)
            if eos_token is not None and sig.item() == eos_token:
                break
        return idx

    @staticmethod
    def _filtrar_top_k(logits: torch.Tensor, top_k: int) -> torch.Tensor:
        if top_k is None or top_k <= 0:
            return logits
        v, _ = torch.topk(logits, top_k)
        logits[logits < v[:, [-1]]] = float("-inf")
        return logits

    @staticmethod
    def _filtrar_top_p(logits: torch.Tensor, top_p: float) -> torch.Tensor:
        if top_p is None or top_p >= 1.0:
            return logits
        sorted_logits, sorted_idx = torch.sort(logits, descending=True)
        cum = torch.cumsum(F.softmax(sorted_logits, dim=-1), dim=-1)
        eliminar = cum > top_p
        eliminar[..., 1:] = eliminar[..., :-1].clone()
        eliminar[..., 0] = False
        sorted_logits[eliminar] = float("-inf")
        return sorted_logits.gather(-1, sorted_idx.argsort(-1))

    def configurar_optimizador(
        self, weight_decay: float, learning_rate: float,
        betas: tuple[float, float] = (0.9, 0.95),
    ) -> torch.optim.Optimizer:
        """AdamW con weight decay separado: pesos con decay, sesgos/norms sin.

        Las normas y los sesgos NO deben tener weight decay según el paper
        original de AdamW. Las matrices grandes (embeddings, linears) sí.
        """
        decay, no_decay = [], []
        for nombre, param in self.named_parameters():
            if not param.requires_grad:
                continue
            if param.ndim >= 2:
                decay.append(param)
            else:
                no_decay.append(param)

        grupos = [
            {"params": decay, "weight_decay": weight_decay},
            {"params": no_decay, "weight_decay": 0.0},
        ]
        return torch.optim.AdamW(grupos, lr=learning_rate, betas=betas)
