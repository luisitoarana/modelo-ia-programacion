"""ModeloMultimodal — LLM + ViT + Projector, todo propio.

Arquitectura (estilo LLaVA, pero 100% nuestra):

    ┌──────────┐    ┌─────────────┐    ┌─────────────┐
    │ Imagen   │ →  │ ViT propio  │ →  │ VisionProj  │ ─┐
    │ (B,3,H,W)│    │ (B,P,V_dim) │    │ (B,P,L_dim) │  │
    └──────────┘    └─────────────┘    └─────────────┘  │
                                                        ▼
                                              ┌─────────────────┐
    ┌──────────┐    ┌─────────────┐         │   concat:        │
    │ Texto    │ →  │ tok_emb     │  ────► │ [vis | texto]    │
    │ (B, T)   │    │ (B,T,L_dim) │         │ (B, P+T, L_dim)  │
    └──────────┘    └─────────────┘         └────────┬────────┘
                                                     │
                                                     ▼
                                          ┌──────────────────────┐
                                          │ Bloques LLM propios  │
                                          │ (RoPE+GQA+SwiGLU…)   │
                                          └──────────┬───────────┘
                                                     │
                                                     ▼
                                              ┌────────────┐
                                              │   logits   │
                                              └────────────┘

Ningún componente depende de modelos externos. El ViT, el Projector y el
LLM se entrenan desde cero. Las APIs externas (Gemini, DeepSeek) solo se
usan durante entrenamiento para destilar comportamiento — el modelo en
producción es 100% propio.

Entrenamiento por etapas (estándar LLaVA):
    Etapa A — Pre-train del projector solo:
        - ViT congelado, LLM congelado, Projector entrenable.
        - Dataset: pares (imagen, descripción corta).
        - Aprende la traducción visual→texto.

    Etapa B — Fine-tuning conjunto:
        - ViT entrenable (low LR), Projector entrenable, LLM entrenable.
        - Dataset: instrucciones multimodales con código Python.
        - Aprende a razonar sobre código en imágenes.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import torch
import torch.nn as nn
import torch.nn.functional as F

from ml.model.transformer_v2 import GPTEducativoV2, ModelConfigV2
from ml.model.vision.projector import VisionProjector
from ml.model.vision.vit_encoder import VisionTransformer, ViTConfig


@dataclass(slots=True)
class ConfigMultimodal:
    """Config conjunta del modelo multimodal."""

    vit: ViTConfig = field(default_factory=ViTConfig)
    llm: ModelConfigV2 = field(default_factory=ModelConfigV2)

    # Hidden del projector. None = usa llm.n_embd.
    projector_hidden: int | None = None
    projector_bias: bool = True

    # Si True, los patches del ViT incluyen el token CLS.
    # Para LLaVA estándar se descarta el CLS (solo se usan los patches).
    incluir_cls_en_llm: bool = False


class ModeloMultimodal(nn.Module):
    """Modelo Vision-Language end-to-end con componentes propios.

    Uso:
        cfg = ConfigMultimodal(
            vit=ViTConfig(image_size=224, patch_size=16, embed_dim=384, n_layer=6),
            llm=ModelConfigV2(vocab_size=16000, block_size=512, n_layer=8, n_embd=512),
        )
        modelo = ModeloMultimodal(cfg)

        # Entrenamiento etapa A (solo projector):
        modelo.congelar_vit()
        modelo.congelar_llm()

        # Forward:
        logits, loss = modelo(imagenes, idx_texto, targets)
    """

    def __init__(self, cfg: ConfigMultimodal) -> None:
        super().__init__()
        self.cfg = cfg

        # Componentes
        self.vit = VisionTransformer(cfg.vit)
        self.projector = VisionProjector(
            in_dim=cfg.vit.embed_dim,
            out_dim=cfg.llm.n_embd,
            hidden_dim=cfg.projector_hidden,
            bias=cfg.projector_bias,
        )
        self.llm = GPTEducativoV2(cfg.llm)

        # Cuántos tokens visuales se inyectan en la secuencia del LLM.
        self.num_visual_tokens = (
            cfg.vit.num_tokens if cfg.incluir_cls_en_llm else cfg.vit.num_patches
        )

    # ─────────────── Helpers de entreno por etapas ───────────────

    def congelar_vit(self) -> None:
        for p in self.vit.parameters():
            p.requires_grad = False

    def descongelar_vit(self) -> None:
        for p in self.vit.parameters():
            p.requires_grad = True

    def congelar_llm(self) -> None:
        for p in self.llm.parameters():
            p.requires_grad = False

    def descongelar_llm(self) -> None:
        for p in self.llm.parameters():
            p.requires_grad = True

    def num_parametros(self) -> dict[str, int]:
        return {
            "vit": sum(p.numel() for p in self.vit.parameters()),
            "projector": sum(p.numel() for p in self.projector.parameters()),
            "llm": sum(p.numel() for p in self.llm.parameters()),
            "total": sum(p.numel() for p in self.parameters()),
            "entrenables": sum(p.numel() for p in self.parameters() if p.requires_grad),
        }

    # ─────────────── Forward conjunto ───────────────

    def _tokens_visuales(self, imagenes: torch.Tensor) -> torch.Tensor:
        """Pasa la imagen por ViT + Projector → tokens listos para el LLM."""
        if self.cfg.incluir_cls_en_llm:
            vit_features = self.vit(imagenes)            # incluye CLS
        else:
            vit_features = self.vit.features_patches(imagenes)
        return self.projector(vit_features)              # (B, P, n_embd)

    def forward(
        self,
        imagenes: torch.Tensor,
        idx_texto: torch.Tensor,
        targets: torch.Tensor | None = None,
    ) -> tuple[torch.Tensor, torch.Tensor | None]:
        """
        Args:
            imagenes: (B, 3, H, W) — imagen normalizada.
            idx_texto: (B, T) — tokens de texto (prompt + respuesta).
            targets:  (B, P+T) — targets para CE loss. Las posiciones
                visuales deben tener `-100` para que el loss las ignore.
                Si es None, solo devuelve logits.

        Returns:
            logits: (B, P+T, vocab_size)
            loss: scalar o None.
        """
        B, T = idx_texto.shape

        # 1. Tokens visuales
        vis_tokens = self._tokens_visuales(imagenes)     # (B, P, n_embd)

        # 2. Embeddings de texto
        text_embeds = self.llm.tok_emb(idx_texto)        # (B, T, n_embd)

        # 3. Concatenar [vis | texto]
        x = torch.cat([vis_tokens, text_embeds], dim=1)  # (B, P+T, n_embd)
        T_total = x.size(1)
        x = self.llm.drop(x)

        # 4. RoPE para la secuencia completa
        cos, sin = self.llm._rope_para_longitud(T_total, x.device, x.dtype)

        # 5. Pila de bloques del LLM
        for bloque in self.llm.bloques:
            x = bloque(x, cos, sin)

        # 6. Norma final + LM head
        x = self.llm.norm_final(x)
        logits = self.llm.lm_head(x)                     # (B, P+T, vocab_size)

        loss = None
        if targets is not None:
            if targets.shape != (B, T_total):
                raise ValueError(
                    f"targets debe tener shape ({B}, {T_total}) "
                    f"= (B, num_visual_tokens + T_texto). "
                    f"Recibido {tuple(targets.shape)}. "
                    f"Recuerda enmascarar las {self.num_visual_tokens} "
                    f"posiciones visuales con -100."
                )
            loss = F.cross_entropy(
                logits.view(-1, logits.size(-1)),
                targets.view(-1),
                ignore_index=-100,
            )

        return logits, loss

    # ─────────────── Generación autoregresiva multimodal ───────────────

    @torch.no_grad()
    def generar(
        self,
        imagenes: torch.Tensor,
        idx_texto: torch.Tensor,
        max_new_tokens: int,
        temperatura: float = 1.0,
        top_k: int | None = None,
        top_p: float | None = None,
        token_eos: int | None = None,
    ) -> torch.Tensor:
        """Genera respuesta condicionada a imagen + prompt de texto.

        Returns:
            tensor (B, T + max_new_tokens) — tokens de texto generados
            (los tokens visuales NO se devuelven, son contexto interno).
        """
        # Precomputar tokens visuales una sola vez (no cambian durante la generación).
        vis_tokens = self._tokens_visuales(imagenes)
        P = vis_tokens.size(1)

        for _ in range(max_new_tokens):
            # Truncar texto a lo que cabe junto con los tokens visuales.
            max_texto = self.llm.cfg.block_size - P
            idx_cond = idx_texto if idx_texto.size(1) <= max_texto \
                else idx_texto[:, -max_texto:]

            # Forward sin targets para obtener logits del último token.
            text_embeds = self.llm.tok_emb(idx_cond)
            x = torch.cat([vis_tokens, text_embeds], dim=1)
            T_total = x.size(1)
            x = self.llm.drop(x)
            cos, sin = self.llm._rope_para_longitud(T_total, x.device, x.dtype)
            for bloque in self.llm.bloques:
                x = bloque(x, cos, sin)
            x = self.llm.norm_final(x)
            logits = self.llm.lm_head(x[:, -1, :]) / max(temperatura, 1e-6)

            if top_k is not None:
                logits = GPTEducativoV2._filtrar_top_k(logits, top_k)
            if top_p is not None:
                logits = GPTEducativoV2._filtrar_top_p(logits, top_p)

            probs = F.softmax(logits, dim=-1)
            sig = torch.multinomial(probs, num_samples=1)
            idx_texto = torch.cat([idx_texto, sig], dim=1)

            if token_eos is not None and (sig == token_eos).all():
                break

        return idx_texto

    # ─────────────── Optimizador con LRs separados por etapa ───────────────

    def configurar_optimizador_etapa_a(
        self, lr_projector: float = 1e-3, weight_decay: float = 0.0,
    ) -> torch.optim.Optimizer:
        """Etapa A: solo projector. ViT y LLM congelados."""
        return torch.optim.AdamW(
            self.projector.parameters(),
            lr=lr_projector, weight_decay=weight_decay,
        )

    def configurar_optimizador_etapa_b(
        self,
        lr_llm: float = 2e-5,
        lr_vit: float = 2e-5,
        lr_projector: float = 1e-4,
        weight_decay: float = 0.01,
    ) -> torch.optim.Optimizer:
        """Etapa B: todo entrenable, con LRs distintos por componente.

        Buena práctica:
            - Projector: LR más alto (es pequeño y nuevo).
            - LLM y ViT: LR bajo (no destruir lo aprendido en pre-train).
        """
        return torch.optim.AdamW([
            {"params": self.vit.parameters(),
             "lr": lr_vit, "weight_decay": weight_decay},
            {"params": self.projector.parameters(),
             "lr": lr_projector, "weight_decay": 0.0},
            {"params": self.llm.parameters(),
             "lr": lr_llm, "weight_decay": weight_decay},
        ])
