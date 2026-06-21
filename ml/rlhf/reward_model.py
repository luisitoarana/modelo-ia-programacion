"""6 Reward Models multi-criterio con encoder compartido.

Cada respuesta del modelo recibe 6 notas 0-10:

    SEG · Seguridad        (vulnerabilidades, OWASP, secrets)
    LEG · Legibilidad      (nombres, estructura, comentarios)
    ESC · Escalabilidad    (complejidad algorítmica, memoria)
    ARQ · Arquitectura     (separación, dependencias, patrones)
    REN · Rendimiento      (optimizaciones, sin redundancia)
    MAN · Mantenibilidad   (tests, error handling, docs)

Diseño técnico:

    Input ────► Encoder Transformer compartido ────► Pooled vector
                          (~30-50M params)                  │
                                                  ┌────────┼─────────┐
                                                  ▼        ▼         ▼
                                              Head SEG  Head LEG ... (6 heads)
                                                  │        │         │
                                              score 0-10 ...

Ventajas del encoder compartido:
    1. VRAM: 1 encoder + 6 heads pequeñas vs 6 modelos completos.
    2. Generalización: el encoder ve todas las dimensiones, evita overfit
       por dimensión.
    3. Inferencia rápida: un forward → 6 scores.

Loss disponibles:
    - MSE sobre scores absolutos (ground truth de los jueces LLM).
    - Ranking pairwise (chosen > rejected en una dimensión específica).
    - Multi-task: suma ponderada de pérdidas por dimensión.

Configuración recomendada:
    - Encoder: arquitectura V2 (RoPE + GQA + SwiGLU + RMSNorm) reducida.
    - Compartir embedding tokenizer con el LLM principal (16k vocab).
    - Tamaño: ~30-50M params total (cabe holgado en RTX 2050).
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Literal

import torch
import torch.nn as nn
import torch.nn.functional as F

from ml.data.schema import DIMENSIONES_PUNTUACION
from ml.model.transformer_v2 import (
    BloqueV2,
    ModelConfigV2,
    RMSNorm,
    precomputar_rope,
)


# ════════════════════════════════════════════════════════════════════
# Config del reward system
# ════════════════════════════════════════════════════════════════════

@dataclass(slots=True)
class RewardConfig:
    """Hiperparámetros del sistema de 6 reward models."""

    # Encoder (Transformer V2 con cabezas pequeñas)
    vocab_size: int = 16000
    block_size: int = 1024
    n_layer: int = 6                    # Encoder mediano (no necesita ser tan profundo como el LLM)
    n_head: int = 8
    n_kv_head: int = 2                  # GQA factor 4
    n_embd: int = 384                   # Sutil: encoder más pequeño que el LLM (~30M total)
    dropout: float = 0.1                # Regularización ayuda en regresión
    rope_theta: float = 10_000.0
    swiglu_mult: float = 8 / 3
    norm_eps: float = 1e-6

    # Heads
    n_heads_reward: int = 6             # SEG / LEG / ESC / ARQ / REN / MAN
    head_hidden: int = 256              # capa intermedia opcional (>0 = MLP, 0 = lineal directa)
    head_dropout: float = 0.1
    score_max: float = 10.0             # rango de salida 0..score_max

    # Pooling
    pooling: Literal["mean", "last", "attention"] = "mean"

    @property
    def head_dim(self) -> int:
        return self.n_embd // self.n_head


# ════════════════════════════════════════════════════════════════════
# Encoder compartido
# ════════════════════════════════════════════════════════════════════

class RewardEncoder(nn.Module):
    """Transformer V2 sin LM head. Devuelve estado oculto por token.

    Reutiliza `BloqueV2` (RoPE + GQA + SwiGLU + RMSNorm) del modelo
    principal — misma arquitectura, parámetros distintos.
    """

    def __init__(self, cfg: RewardConfig):
        super().__init__()
        # Construir un ModelConfigV2 compatible con BloqueV2 a partir de RewardConfig.
        modelo_cfg = ModelConfigV2(
            vocab_size=cfg.vocab_size,
            block_size=cfg.block_size,
            n_layer=cfg.n_layer,
            n_head=cfg.n_head,
            n_kv_head=cfg.n_kv_head,
            n_embd=cfg.n_embd,
            dropout=cfg.dropout,
            rope_theta=cfg.rope_theta,
            swiglu_mult=cfg.swiglu_mult,
            norm_eps=cfg.norm_eps,
            bias=False,
            tie_weights=False,
        )
        self.modelo_cfg = modelo_cfg

        self.tok_emb = nn.Embedding(cfg.vocab_size, cfg.n_embd)
        self.drop = nn.Dropout(cfg.dropout)
        self.bloques = nn.ModuleList([BloqueV2(modelo_cfg) for _ in range(cfg.n_layer)])
        self.norm_final = RMSNorm(cfg.n_embd, eps=cfg.norm_eps)

        # Precomputar RoPE
        cos, sin = precomputar_rope(modelo_cfg.head_dim, cfg.block_size, cfg.rope_theta)
        self.register_buffer("rope_cos", cos, persistent=False)
        self.register_buffer("rope_sin", sin, persistent=False)

        self.apply(self._init_pesos)

    @staticmethod
    def _init_pesos(modulo: nn.Module) -> None:
        if isinstance(modulo, nn.Linear):
            nn.init.normal_(modulo.weight, mean=0.0, std=0.02)
            if modulo.bias is not None:
                nn.init.zeros_(modulo.bias)
        elif isinstance(modulo, nn.Embedding):
            nn.init.normal_(modulo.weight, mean=0.0, std=0.02)

    def forward(self, idx: torch.Tensor, attention_mask: torch.Tensor | None = None) -> torch.Tensor:
        """idx: (B, T) → hidden: (B, T, n_embd).

        attention_mask: (B, T) opcional, 1 para tokens reales, 0 para padding.
        El pooling posterior lo usa para descartar padding.
        """
        B, T = idx.shape
        x = self.drop(self.tok_emb(idx))
        cos = self.rope_cos[:T].to(x.dtype)
        sin = self.rope_sin[:T].to(x.dtype)
        for bloque in self.bloques:
            x = bloque(x, cos, sin)
        x = self.norm_final(x)
        return x


# ════════════════════════════════════════════════════════════════════
# Pooling strategies
# ════════════════════════════════════════════════════════════════════

def _mean_pool(hidden: torch.Tensor, mask: torch.Tensor | None) -> torch.Tensor:
    """Promedio de los tokens, ignorando padding si hay mask."""
    if mask is None:
        return hidden.mean(dim=1)
    mask = mask.float().unsqueeze(-1)
    return (hidden * mask).sum(dim=1) / mask.sum(dim=1).clamp(min=1.0)


def _last_pool(hidden: torch.Tensor, mask: torch.Tensor | None) -> torch.Tensor:
    """Estado del último token real."""
    if mask is None:
        return hidden[:, -1]
    # Índice del último token no-padding por batch.
    lengths = mask.long().sum(dim=1) - 1
    return hidden[torch.arange(hidden.size(0)), lengths]


class AttentionPool(nn.Module):
    """Pooling por atención: una query aprendida atiende a todos los tokens."""

    def __init__(self, n_embd: int):
        super().__init__()
        self.q = nn.Parameter(torch.randn(1, 1, n_embd) * 0.02)
        self.scale = n_embd ** -0.5

    def forward(self, hidden: torch.Tensor, mask: torch.Tensor | None) -> torch.Tensor:
        # (B, 1, n_embd) @ (B, n_embd, T) → (B, 1, T)
        q = self.q.expand(hidden.size(0), 1, -1)
        att = (q @ hidden.transpose(-1, -2)) * self.scale
        if mask is not None:
            att = att.masked_fill(~mask.bool().unsqueeze(1), float("-inf"))
        w = F.softmax(att, dim=-1)
        return (w @ hidden).squeeze(1)  # (B, n_embd)


# ════════════════════════════════════════════════════════════════════
# Head de regresión por dimensión
# ════════════════════════════════════════════════════════════════════

class RewardHead(nn.Module):
    """Cabeza de regresión para UNA dimensión.

    Estructura:
        pooled (B, n_embd) → [MLP opcional] → sigmoid * score_max → (B,)
    """

    def __init__(self, n_embd: int, head_hidden: int, dropout: float,
                 score_max: float):
        super().__init__()
        self.score_max = score_max
        if head_hidden > 0:
            self.net = nn.Sequential(
                nn.Linear(n_embd, head_hidden),
                nn.GELU(),
                nn.Dropout(dropout),
                nn.Linear(head_hidden, 1),
            )
        else:
            self.net = nn.Linear(n_embd, 1)

    def forward(self, pooled: torch.Tensor) -> torch.Tensor:
        logit = self.net(pooled).squeeze(-1)
        return torch.sigmoid(logit) * self.score_max


# ════════════════════════════════════════════════════════════════════
# Sistema multi-criterio
# ════════════════════════════════════════════════════════════════════

class MultiCriteriaRewardModel(nn.Module):
    """6 reward models con encoder compartido. Inferencia rápida.

    Una sola pasada por el encoder produce los 6 scores. Las heads son
    chicas (~100k params c/u con head_hidden=256), así que el costo extra
    sobre el encoder es despreciable.
    """

    DIMENSIONES = DIMENSIONES_PUNTUACION  # ('SEG','LEG','ESC','ARQ','REN','MAN')

    def __init__(self, cfg: RewardConfig):
        super().__init__()
        assert cfg.n_heads_reward == len(self.DIMENSIONES), (
            f"n_heads_reward debe ser {len(self.DIMENSIONES)}"
        )
        self.cfg = cfg
        self.encoder = RewardEncoder(cfg)

        # Pooling
        if cfg.pooling == "attention":
            self.pool = AttentionPool(cfg.n_embd)
        else:
            self.pool = None  # se hace funcionalmente

        # 6 heads, una por dimensión
        self.heads = nn.ModuleDict({
            dim: RewardHead(cfg.n_embd, cfg.head_hidden, cfg.head_dropout, cfg.score_max)
            for dim in self.DIMENSIONES
        })

    def _aplicar_pool(self, hidden: torch.Tensor, mask: torch.Tensor | None) -> torch.Tensor:
        if self.cfg.pooling == "mean":
            return _mean_pool(hidden, mask)
        if self.cfg.pooling == "last":
            return _last_pool(hidden, mask)
        if self.cfg.pooling == "attention":
            return self.pool(hidden, mask)
        raise ValueError(f"pooling desconocido: {self.cfg.pooling}")

    def forward(self, input_ids: torch.Tensor,
                attention_mask: torch.Tensor | None = None,
                dimensiones: tuple[str, ...] | None = None
                ) -> dict[str, torch.Tensor]:
        """input_ids: (B, T). Devuelve {"SEG": (B,), "LEG": (B,), ...}.

        `dimensiones`: subset a calcular (útil cuando solo se entrena UNA).
        """
        dims = dimensiones or self.DIMENSIONES
        hidden = self.encoder(input_ids, attention_mask)
        pooled = self._aplicar_pool(hidden, attention_mask)
        return {dim: self.heads[dim](pooled) for dim in dims}

    def num_parametros(self, solo_entrenables: bool = True) -> int:
        params = self.parameters()
        if solo_entrenables:
            return sum(p.numel() for p in params if p.requires_grad)
        return sum(p.numel() for p in params)

    def num_parametros_por_componente(self) -> dict[str, int]:
        """Desglose útil para reporte de tesis."""
        partes = {
            "encoder.embedding": sum(p.numel() for p in self.encoder.tok_emb.parameters()),
            "encoder.bloques": sum(p.numel() for p in self.encoder.bloques.parameters()),
            "encoder.norm_final": sum(p.numel() for p in self.encoder.norm_final.parameters()),
        }
        if self.pool is not None:
            partes["pooling"] = sum(p.numel() for p in self.pool.parameters())
        for dim in self.DIMENSIONES:
            partes[f"head_{dim}"] = sum(p.numel() for p in self.heads[dim].parameters())
        return partes


# ════════════════════════════════════════════════════════════════════
# Loss functions
# ════════════════════════════════════════════════════════════════════

def loss_mse_multi(
    predichos: dict[str, torch.Tensor],
    targets: dict[str, torch.Tensor],
    pesos: dict[str, float] | None = None,
    score_max: float = 10.0,
) -> tuple[torch.Tensor, dict[str, float]]:
    """MSE por dimensión, suma ponderada.

    predichos: {"SEG": (B,), ...} con valores 0..score_max
    targets:   {"SEG": (B,), ...} con valores 0..score_max (de los jueces LLM)
    pesos: peso por dimensión (default 1.0 cada una).

    Devuelve (loss escalar, detalle por dimensión).
    """
    pesos = pesos or {d: 1.0 for d in predichos}
    losses_por_dim: dict[str, float] = {}
    loss_total: torch.Tensor | None = None

    for dim, pred in predichos.items():
        if dim not in targets:
            continue
        t = targets[dim].float() / score_max  # normalizar a [0,1]
        p = pred / score_max
        l = F.mse_loss(p, t)
        losses_por_dim[dim] = l.item()
        w = pesos.get(dim, 1.0)
        loss_total = (w * l) if loss_total is None else (loss_total + w * l)

    return (loss_total if loss_total is not None
            else torch.tensor(0.0, requires_grad=True)), losses_por_dim


def loss_ranking_multi(
    scores_chosen: dict[str, torch.Tensor],
    scores_rejected: dict[str, torch.Tensor],
    pesos: dict[str, float] | None = None,
) -> tuple[torch.Tensor, dict[str, float]]:
    """Pairwise ranking loss por dimensión.

    Para cada dimensión, queremos que score_chosen > score_rejected.
    Loss = -log(sigmoid(score_chosen - score_rejected))
    """
    pesos = pesos or {d: 1.0 for d in scores_chosen}
    losses_por_dim: dict[str, float] = {}
    loss_total: torch.Tensor | None = None
    accuracies: dict[str, float] = {}

    for dim, ch in scores_chosen.items():
        if dim not in scores_rejected:
            continue
        rj = scores_rejected[dim]
        diff = ch - rj
        l = -F.logsigmoid(diff).mean()
        losses_por_dim[dim] = l.item()
        accuracies[dim] = (diff > 0).float().mean().item()
        w = pesos.get(dim, 1.0)
        loss_total = (w * l) if loss_total is None else (loss_total + w * l)

    detalle = {f"loss_{d}": v for d, v in losses_por_dim.items()}
    detalle.update({f"acc_{d}": v for d, v in accuracies.items()})
    return (loss_total if loss_total is not None
            else torch.tensor(0.0, requires_grad=True)), detalle


def cargar_pesos_desde_archivo(ruta) -> dict[str, float]:
    """Lee un YAML/JSON con pesos por dimensión.

    Ejemplo:
        SEG: 1.5
        ARQ: 1.2
        MAN: 1.0
        LEG: 1.0
        ESC: 0.8
        REN: 0.8
    """
    from pathlib import Path
    ruta = Path(ruta)
    contenido = ruta.read_text(encoding="utf-8")
    if ruta.suffix == ".yaml" or ruta.suffix == ".yml":
        import yaml
        data = yaml.safe_load(contenido)
    else:
        import json as _json
        data = _json.loads(contenido)
    pesos = {d: float(data.get(d, 1.0)) for d in DIMENSIONES_PUNTUACION}
    return pesos


# ════════════════════════════════════════════════════════════════════
# Presets convenientes
# ════════════════════════════════════════════════════════════════════

def preset_rm_pequeno() -> RewardConfig:
    """~10M params. Para iterar rápido en RTX 2050."""
    return RewardConfig(
        vocab_size=16000, block_size=512,
        n_layer=4, n_head=6, n_kv_head=2, n_embd=288,
        head_hidden=128,
    )


def preset_rm_mediano() -> RewardConfig:
    """~30M params. Estándar de la tesis (cabe holgado en T4 16GB)."""
    return RewardConfig(
        vocab_size=16000, block_size=1024,
        n_layer=6, n_head=8, n_kv_head=2, n_embd=384,
        head_hidden=256,
    )


def preset_rm_grande() -> RewardConfig:
    """~80M params. Para si queremos más capacidad de discriminación."""
    return RewardConfig(
        vocab_size=16000, block_size=1024,
        n_layer=8, n_head=10, n_kv_head=2, n_embd=520,
        head_hidden=384,
    )


PRESETS_RM = {
    "pequeno": preset_rm_pequeno,
    "mediano": preset_rm_mediano,
    "grande": preset_rm_grande,
}
