"""Smoke test del modelo multimodal: verifica forward + backward.

Confirma que toda la cadena (ViT → Projector → LLM) está bien cableada
sin necesidad de checkpoint base ni dataset real. Útil para validar la
arquitectura antes de invertir horas/días en entrenamiento.
"""

import sys
from pathlib import Path

import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from ml.model.multimodal_model import ConfigMultimodal, ModeloMultimodal
from ml.model.transformer_v2 import ModelConfigV2
from ml.model.vision.vit_encoder import ViTConfig


def main() -> None:
    print("=" * 60)
    print("Smoke test: ModeloMultimodal")
    print("=" * 60)

    cfg = ConfigMultimodal(
        vit=ViTConfig(image_size=224, patch_size=16, embed_dim=384,
                      n_layer=2, n_head=6),     # 2 capas para ir rapido
        llm=ModelConfigV2(vocab_size=2000, block_size=256,
                          n_layer=2, n_head=8, n_embd=512, n_kv_head=2),
    )
    print(f"\n[1] Configurando modelo (n_layer ViT=2, LLM=2, vocab=2000)")
    modelo = ModeloMultimodal(cfg)
    n = modelo.num_parametros()
    print(f"    ViT       : {n['vit']/1e6:>6.2f} M")
    print(f"    Projector : {n['projector']/1e6:>6.2f} M")
    print(f"    LLM       : {n['llm']/1e6:>6.2f} M")
    print(f"    TOTAL     : {n['total']/1e6:>6.2f} M")
    print(f"    num_visual_tokens = {modelo.num_visual_tokens}")

    print("\n[2] Forward pass (batch=2)")
    B, T = 2, 20
    img = torch.randn(B, 3, 224, 224)
    idx = torch.randint(0, cfg.llm.vocab_size, (B, T))
    P = modelo.num_visual_tokens
    targets = torch.full((B, P + T), -100, dtype=torch.long)
    targets[:, P + 5: P + T] = torch.randint(0, cfg.llm.vocab_size, (B, T - 5))

    logits, loss = modelo(img, idx, targets)
    print(f"    logits.shape = {tuple(logits.shape)}  (esperado: ({B}, {P+T}, {cfg.llm.vocab_size}))")
    print(f"    loss = {loss.item():.4f}")

    print("\n[3] Backward pass")
    loss.backward()
    print("    [OK] gradientes calculados")

    print("\n[4] generar() autoregresivo (5 tokens)")
    modelo.eval()
    with torch.no_grad():
        out = modelo.generar(
            imagenes=img[:1], idx_texto=idx[:1, :5],
            max_new_tokens=5, temperatura=1.0,
        )
    print(f"    salida.shape = {tuple(out.shape)}")
    print(f"    tokens generados: {out[0, 5:].tolist()}")

    print("\n" + "=" * 60)
    print("[OK] Smoke test PASO. Arquitectura cableada correctamente.")
    print("=" * 60)


if __name__ == "__main__":
    main()
