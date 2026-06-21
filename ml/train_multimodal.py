"""Entrenamiento del modelo multimodal propio (ViT + Projector + LLM).

Pipeline en dos etapas (LLaVA-style):

    Etapa A — Pre-train del Projector:
        Congela ViT y LLM. Solo entrena el adapter MLP que mapea features
        visuales al espacio del LLM. Rápido y barato.

    Etapa B — Fine-tuning conjunto:
        Descongela todo con LRs diferenciados. El ViT y el LLM ajustan
        pesos suavemente; el projector sigue con LR más alto.

Uso:
    # 0) Generar el dataset sintético si no existe:
    python -m ml.data.generar_imagenes_codigo --n 2000

    # 1) Etapa A (solo projector):
    python -m ml.train_multimodal --etapa a --iters 1500 --batch 8

    # 2) Etapa B (todo entrenable):
    python -m ml.train_multimodal --etapa b --iters 3000 --batch 4 \
        --checkpoint-prev runs/multimodal_a/best.pt

El checkpoint base del LLM se carga desde `runs/exp01/best.pt`. Si no
existe, se entrena desde cero (más lento; preferible cargar el ya
preentrenado).
"""

from __future__ import annotations

import argparse
import json
from dataclasses import asdict
from pathlib import Path

import torch
from torch.utils.data import DataLoader

from ml.config import DIR_TOKENIZER
from ml.data.vision_dataset import (
    ConfigDatasetVision,
    VisionDataset,
    collate_multimodal,
)
from ml.model.multimodal_model import ConfigMultimodal, ModeloMultimodal
from ml.model.transformer_v2 import ModelConfigV2
from ml.model.vision.vit_encoder import ViTConfig
from ml.tokenizer.sp_tokenizer import SPTokenizer


# ════════════════════════════════════════════════════════════════════
# Helpers
# ════════════════════════════════════════════════════════════════════

def cargar_tokenizer() -> SPTokenizer:
    ruta = Path(DIR_TOKENIZER) / "tokenizer.json"
    if not ruta.exists():
        raise FileNotFoundError(
            f"No se encontró el tokenizer en {ruta}. "
            f"Entrena el modelo base primero con `python -m ml.train`."
        )
    return SPTokenizer.cargar(ruta)


def cargar_pesos_llm_si_existen(
    modelo: ModeloMultimodal, ruta_ckpt: Path,
) -> bool:
    """Carga el state_dict del LLM base si el checkpoint existe."""
    if not ruta_ckpt.exists():
        print(f"[i] No hay checkpoint base en {ruta_ckpt}. LLM empieza random.")
        return False
    ckpt = torch.load(ruta_ckpt, map_location="cpu", weights_only=False)
    state = ckpt.get("model", ckpt)

    # Prefijar las claves con "llm." porque en ModeloMultimodal el LLM
    # está como submódulo `self.llm`.
    state_renombrado = {f"llm.{k}": v for k, v in state.items()}
    res = modelo.load_state_dict(state_renombrado, strict=False)
    print(f"[OK] LLM cargado de {ruta_ckpt} "
          f"({len(res.missing_keys)} missing, {len(res.unexpected_keys)} unexpected)")
    return True


def cargar_checkpoint_multimodal(
    modelo: ModeloMultimodal, ruta: Path,
) -> None:
    ckpt = torch.load(ruta, map_location="cpu", weights_only=False)
    modelo.load_state_dict(ckpt["model"], strict=False)
    print(f"[OK] Checkpoint multimodal cargado de {ruta}")


# ════════════════════════════════════════════════════════════════════
# Bucle de entrenamiento
# ════════════════════════════════════════════════════════════════════

def entrenar(
    etapa: str,
    iters: int,
    batch: int,
    raiz_dataset: Path,
    salida: Path,
    device: str,
    checkpoint_prev: Path | None,
    log_cada: int = 50,
    eval_cada: int = 500,
    grad_accum: int = 1,
) -> None:
    salida.mkdir(parents=True, exist_ok=True)
    dev = torch.device(device)

    # ── Tokenizer ──
    tok = cargar_tokenizer()

    # ── Modelo ──
    vit_cfg = ViTConfig(
        image_size=224, patch_size=16, embed_dim=384,
        n_layer=6, n_head=6,
    )
    llm_cfg = ModelConfigV2(
        vocab_size=tok.vocab_size,
        block_size=512,
        n_layer=8, n_head=8, n_embd=512, n_kv_head=2,
    )
    cfg = ConfigMultimodal(vit=vit_cfg, llm=llm_cfg)
    modelo = ModeloMultimodal(cfg).to(dev)

    # Cargar pesos del LLM base si existen
    cargar_pesos_llm_si_existen(modelo, Path("runs/exp01/best.pt"))

    # Cargar checkpoint multimodal previo si se pidió (etapa B desde A)
    if checkpoint_prev is not None:
        cargar_checkpoint_multimodal(modelo, checkpoint_prev)

    # Configuración por etapa
    if etapa == "a":
        modelo.congelar_vit()
        modelo.congelar_llm()
        opt = modelo.configurar_optimizador_etapa_a(lr_projector=1e-3)
        print("[etapa A] ViT y LLM congelados. Solo se entrena el projector.")
    elif etapa == "b":
        modelo.descongelar_vit()
        modelo.descongelar_llm()
        opt = modelo.configurar_optimizador_etapa_b(
            lr_llm=2e-5, lr_vit=2e-5, lr_projector=1e-4,
        )
        print("[etapa B] Todos los componentes entrenables.")
    else:
        raise ValueError(f"etapa debe ser 'a' o 'b', recibido: {etapa}")

    n = modelo.num_parametros()
    print(f"[modelo] vit={n['vit']/1e6:.1f}M  proj={n['projector']/1e6:.2f}M  "
          f"llm={n['llm']/1e6:.1f}M  entrenables={n['entrenables']/1e6:.1f}M")

    # ── Dataset ──
    ds_cfg = ConfigDatasetVision(
        raiz=raiz_dataset,
        image_size=cfg.vit.image_size,
        block_size=256,
        num_visual_tokens=modelo.num_visual_tokens,
    )
    dataset = VisionDataset(
        cfg=ds_cfg,
        codificar=lambda s: tok.encode(s),
        token_pad=tok.pad_id,
        token_bos=tok.bos_id,
    )
    print(f"[data] {len(dataset)} muestras en {raiz_dataset}")

    loader = DataLoader(
        dataset, batch_size=batch, shuffle=True,
        num_workers=0, collate_fn=collate_multimodal, drop_last=True,
    )

    # ── Loop ──
    historia: list[dict] = []
    it = 0
    mejor_loss = float("inf")
    suma_loss = 0.0
    n_acumuladas = 0
    modelo.train()
    autocast_dtype = torch.bfloat16 if dev.type == "cuda" else torch.float32

    while it < iters:
        for batch_dict in loader:
            if it >= iters:
                break

            imagen = batch_dict["imagen"].to(dev, non_blocking=True)
            idx_texto = batch_dict["idx_texto"].to(dev, non_blocking=True)
            targets = batch_dict["targets"].to(dev, non_blocking=True)

            with torch.autocast(device_type=dev.type, dtype=autocast_dtype):
                _, loss = modelo(imagen, idx_texto, targets)
            if loss is None:
                continue
            loss = loss / grad_accum
            loss.backward()

            suma_loss += loss.item() * grad_accum
            n_acumuladas += 1

            if n_acumuladas % grad_accum == 0:
                torch.nn.utils.clip_grad_norm_(
                    [p for p in modelo.parameters() if p.requires_grad],
                    max_norm=1.0,
                )
                opt.step()
                opt.zero_grad(set_to_none=True)
                it += 1

                if it % log_cada == 0:
                    media = suma_loss / max(1, n_acumuladas)
                    print(f"[iter {it:>5}/{iters}]  loss={media:.4f}")
                    historia.append({"iter": it, "loss": media})
                    suma_loss, n_acumuladas = 0.0, 0

                if it % eval_cada == 0 or it == iters:
                    media = sum(h["loss"] for h in historia[-10:]) / max(1, len(historia[-10:]))
                    if media < mejor_loss:
                        mejor_loss = media
                        torch.save(
                            {
                                "model": modelo.state_dict(),
                                "cfg": asdict(cfg),
                                "iter": it,
                                "loss": media,
                                "etapa": etapa,
                            },
                            salida / "best.pt",
                        )
                        print(f"  [OK] Guardado best.pt en iter {it} con loss {media:.4f}")

    # Persistir historia
    (salida / "historia.json").write_text(
        json.dumps(historia, indent=2), encoding="utf-8",
    )
    print(f"[fin] Entrenamiento completo. Mejor loss: {mejor_loss:.4f}")
    print(f"[fin] Checkpoint en: {salida / 'best.pt'}")


# ════════════════════════════════════════════════════════════════════
# CLI
# ════════════════════════════════════════════════════════════════════

def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--etapa", choices=["a", "b"], required=True,
                   help="A = solo projector. B = todo el modelo.")
    p.add_argument("--iters", type=int, default=1500)
    p.add_argument("--batch", type=int, default=8)
    p.add_argument("--grad-accum", type=int, default=1)
    p.add_argument("--dataset", type=Path, default=Path("data/vision"))
    p.add_argument("--salida", type=Path, default=None,
                   help="Por defecto: runs/multimodal_<etapa>")
    p.add_argument("--device", default="cuda" if torch.cuda.is_available() else "cpu")
    p.add_argument("--checkpoint-prev", type=Path, default=None,
                   help="Para etapa B: best.pt de la etapa A.")
    p.add_argument("--log-cada", type=int, default=50)
    p.add_argument("--eval-cada", type=int, default=500)
    args = p.parse_args()

    salida = args.salida or Path(f"runs/multimodal_{args.etapa}")

    entrenar(
        etapa=args.etapa,
        iters=args.iters,
        batch=args.batch,
        raiz_dataset=args.dataset,
        salida=salida,
        device=args.device,
        checkpoint_prev=args.checkpoint_prev,
        log_cada=args.log_cada,
        eval_cada=args.eval_cada,
        grad_accum=args.grad_accum,
    )


if __name__ == "__main__":
    main()
