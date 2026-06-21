"""Transformer decoder educativo, implementado desde cero en PyTorch.

Arquitectura tipo GPT (decoder-only, autoregresivo) construida a mano:
    - Embedding de tokens.
    - Positional Encoding sinusoidal.
    - Multi-Head Self-Attention causal (implementada explícitamente).
    - Feed-Forward Network (MLP con GELU).
    - Layer Normalization + conexiones residuales (arquitectura pre-LN).
    - Cabezal de lenguaje (LM head) con weight tying opcional.
    - Pérdida Cross-Entropy para entrenamiento autoregresivo.
    - Generación con temperatura, top-k y top-p.

No se usa nn.Transformer ni nn.MultiheadAttention: la atención se programa
desde cero para fines didácticos y de transparencia científica.
"""

from __future__ import annotations

import math

import torch
import torch.nn as nn
import torch.nn.functional as F

from ml.config import ModelConfig


class PositionalEncoding(nn.Module):
    """Codificación posicional sinusoidal (Vaswani et al., 2017).

    Inyecta información de orden sin parámetros entrenables, usando senos y
    cosenos de distintas frecuencias.
    """

    def __init__(self, n_embd: int, block_size: int) -> None:
        super().__init__()
        pe = torch.zeros(block_size, n_embd)
        posicion = torch.arange(0, block_size, dtype=torch.float).unsqueeze(1)
        div = torch.exp(
            torch.arange(0, n_embd, 2, dtype=torch.float)
            * (-math.log(10000.0) / n_embd)
        )
        pe[:, 0::2] = torch.sin(posicion * div)
        pe[:, 1::2] = torch.cos(posicion * div)
        self.register_buffer("pe", pe.unsqueeze(0), persistent=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: (B, T, C) -> suma la codificación de las primeras T posiciones
        return x + self.pe[:, : x.size(1)]


class CausalSelfAttention(nn.Module):
    """Atención multi-cabeza causal (enmascarada), desde cero."""

    def __init__(self, cfg: ModelConfig) -> None:
        super().__init__()
        self.n_head = cfg.n_head
        self.n_embd = cfg.n_embd
        self.head_dim = cfg.head_dim

        # Proyecciones Q, K, V en una sola matriz (eficiencia).
        self.qkv = nn.Linear(cfg.n_embd, 3 * cfg.n_embd, bias=cfg.bias)
        self.proj = nn.Linear(cfg.n_embd, cfg.n_embd, bias=cfg.bias)
        self.attn_dropout = nn.Dropout(cfg.dropout)
        self.resid_dropout = nn.Dropout(cfg.dropout)

        # Máscara causal triangular inferior (no mirar el futuro).
        mascara = torch.tril(torch.ones(cfg.block_size, cfg.block_size))
        self.register_buffer(
            "mascara", mascara.view(1, 1, cfg.block_size, cfg.block_size),
            persistent=False,
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        B, T, C = x.shape

        qkv = self.qkv(x)                       # (B, T, 3C)
        q, k, v = qkv.split(self.n_embd, dim=2)

        # (B, n_head, T, head_dim)
        q = q.view(B, T, self.n_head, self.head_dim).transpose(1, 2)
        k = k.view(B, T, self.n_head, self.head_dim).transpose(1, 2)
        v = v.view(B, T, self.n_head, self.head_dim).transpose(1, 2)

        # Scaled dot-product attention: softmax(QK^T / sqrt(d)) V
        att = (q @ k.transpose(-2, -1)) * (1.0 / math.sqrt(self.head_dim))
        att = att.masked_fill(self.mascara[:, :, :T, :T] == 0, float("-inf"))
        att = F.softmax(att, dim=-1)
        att = self.attn_dropout(att)

        y = att @ v                              # (B, n_head, T, head_dim)
        y = y.transpose(1, 2).contiguous().view(B, T, C)  # recombinar cabezas
        return self.resid_dropout(self.proj(y))


class FeedForward(nn.Module):
    """Red feed-forward posición a posición (expansión 4x + GELU)."""

    def __init__(self, cfg: ModelConfig) -> None:
        super().__init__()
        self.fc = nn.Linear(cfg.n_embd, 4 * cfg.n_embd, bias=cfg.bias)
        self.proj = nn.Linear(4 * cfg.n_embd, cfg.n_embd, bias=cfg.bias)
        self.dropout = nn.Dropout(cfg.dropout)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self.fc(x)
        x = F.gelu(x)
        x = self.proj(x)
        return self.dropout(x)


class Bloque(nn.Module):
    """Bloque Transformer pre-LN con conexiones residuales.

        x = x + Attn(LN(x))
        x = x + FFN(LN(x))
    """

    def __init__(self, cfg: ModelConfig) -> None:
        super().__init__()
        self.ln1 = nn.LayerNorm(cfg.n_embd, bias=cfg.bias)
        self.attn = CausalSelfAttention(cfg)
        self.ln2 = nn.LayerNorm(cfg.n_embd, bias=cfg.bias)
        self.ffn = FeedForward(cfg)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = x + self.attn(self.ln1(x))
        x = x + self.ffn(self.ln2(x))
        return x


class GPTEducativo(nn.Module):
    """Modelo de lenguaje decoder-only educativo (desde cero)."""

    def __init__(self, cfg: ModelConfig) -> None:
        super().__init__()
        self.cfg = cfg

        self.token_embedding = nn.Embedding(cfg.vocab_size, cfg.n_embd)
        self.pos_encoding = PositionalEncoding(cfg.n_embd, cfg.block_size)
        self.drop = nn.Dropout(cfg.dropout)
        self.bloques = nn.ModuleList([Bloque(cfg) for _ in range(cfg.n_layer)])
        self.ln_final = nn.LayerNorm(cfg.n_embd, bias=cfg.bias)
        self.lm_head = nn.Linear(cfg.n_embd, cfg.vocab_size, bias=False)

        if cfg.tie_weights:
            # Comparte pesos entre embedding y cabezal (reduce parámetros).
            self.lm_head.weight = self.token_embedding.weight

        self.apply(self._init_pesos)
        # Inicialización escalada para las proyecciones residuales (GPT-2).
        for nombre, p in self.named_parameters():
            if nombre.endswith("proj.weight"):
                nn.init.normal_(p, mean=0.0, std=0.02 / math.sqrt(2 * cfg.n_layer))

    @staticmethod
    def _init_pesos(modulo: nn.Module) -> None:
        if isinstance(modulo, nn.Linear):
            nn.init.normal_(modulo.weight, mean=0.0, std=0.02)
            if modulo.bias is not None:
                nn.init.zeros_(modulo.bias)
        elif isinstance(modulo, nn.Embedding):
            nn.init.normal_(modulo.weight, mean=0.0, std=0.02)

    def num_parametros(self, solo_entrenables: bool = True) -> int:
        params = self.parameters()
        if solo_entrenables:
            return sum(p.numel() for p in params if p.requires_grad)
        return sum(p.numel() for p in params)

    def forward(
        self,
        idx: torch.Tensor,
        targets: torch.Tensor | None = None,
    ) -> tuple[torch.Tensor, torch.Tensor | None]:
        B, T = idx.shape
        if T > self.cfg.block_size:
            raise ValueError(
                f"Secuencia de longitud {T} excede block_size={self.cfg.block_size}"
            )

        x = self.token_embedding(idx)        # (B, T, C)
        x = self.pos_encoding(x)
        x = self.drop(x)
        for bloque in self.bloques:
            x = bloque(x)
        x = self.ln_final(x)
        logits = self.lm_head(x)             # (B, T, vocab)

        loss: torch.Tensor | None = None
        if targets is not None:
            loss = F.cross_entropy(
                logits.view(-1, logits.size(-1)),
                targets.view(-1),
                ignore_index=-1,
            )
        return logits, loss

    @torch.no_grad()
    def generar(
        self,
        idx: torch.Tensor,
        max_nuevos_tokens: int,
        *,
        temperatura: float = 1.0,
        top_k: int | None = None,
        top_p: float | None = None,
        eos_token: int | None = None,
    ) -> torch.Tensor:
        """Genera tokens de forma autoregresiva.

        idx: (B, T) contexto inicial. Devuelve (B, T + n) con lo generado.
        """
        self.eval()
        for _ in range(max_nuevos_tokens):
            # Recortar el contexto a block_size.
            idx_cond = idx[:, -self.cfg.block_size :]
            logits, _ = self(idx_cond)
            logits = logits[:, -1, :]  # último paso temporal (B, vocab)

            if temperatura <= 0:
                # Greedy.
                siguiente = torch.argmax(logits, dim=-1, keepdim=True)
            else:
                logits = logits / temperatura
                logits = self._filtrar_top_k(logits, top_k)
                logits = self._filtrar_top_p(logits, top_p)
                probs = F.softmax(logits, dim=-1)
                siguiente = torch.multinomial(probs, num_samples=1)

            idx = torch.cat([idx, siguiente], dim=1)

            if eos_token is not None and bool((siguiente == eos_token).all()):
                break
        return idx

    @staticmethod
    def _filtrar_top_k(logits: torch.Tensor, top_k: int | None) -> torch.Tensor:
        if not top_k:
            return logits
        k = min(top_k, logits.size(-1))
        umbral = torch.topk(logits, k).values[..., -1, None]
        return logits.masked_fill(logits < umbral, float("-inf"))

    @staticmethod
    def _filtrar_top_p(logits: torch.Tensor, top_p: float | None) -> torch.Tensor:
        if not top_p or top_p >= 1.0:
            return logits
        ordenados, indices = torch.sort(logits, descending=True, dim=-1)
        probs_acum = torch.cumsum(F.softmax(ordenados, dim=-1), dim=-1)
        quitar = probs_acum > top_p
        # Mantener siempre al menos el token más probable.
        quitar[..., 1:] = quitar[..., :-1].clone()
        quitar[..., 0] = False
        quitar_orig = quitar.scatter(-1, indices, quitar)
        return logits.masked_fill(quitar_orig, float("-inf"))

    def configurar_optimizador(
        self,
        weight_decay: float,
        learning_rate: float,
        betas: tuple[float, float],
        device: str,
    ) -> torch.optim.Optimizer:
        """AdamW con weight decay selectivo (no decae bias ni LayerNorm)."""
        decay, no_decay = [], []
        for _, p in self.named_parameters():
            if not p.requires_grad:
                continue
            if p.dim() >= 2:
                decay.append(p)
            else:
                no_decay.append(p)
        grupos = [
            {"params": decay, "weight_decay": weight_decay},
            {"params": no_decay, "weight_decay": 0.0},
        ]
        fused = device == "cuda" and "fused" in torch.optim.AdamW.__init__.__code__.co_varnames
        extra = {"fused": True} if fused else {}
        return torch.optim.AdamW(grupos, lr=learning_rate, betas=betas, **extra)
