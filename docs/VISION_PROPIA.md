# Modelo de Visión Propio — Decisión de Diseño

## Por qué NO usar Gemini Vision (ni ningún modelo externo) en inferencia

Cuando se implementó por primera vez la funcionalidad multimodal, la ruta más
rápida era enviar las imágenes a Gemini Vision y usar su respuesta. **Esto
fue rechazado deliberadamente** y se diseñó esta arquitectura propia. Las
razones:

1. **Coherencia con el proyecto.** El proyecto entrega un *sistema de IA propio*.
 Si la parte visual depende de una API externa, deja de serlo: el sistema
 se vuelve un *frontend* de Gemini. La argumentación técnica sería contradictoria.

2. **Privacidad y soberanía.** Las imágenes de código pueden contener
 credenciales, datos sensibles o información protegida. Mandarlas a un
 tercero crea una dependencia legal y técnica que el sistema no controla.

3. **Reproducibilidad.** Un modelo externo cambia, deprecia versiones y
 modifica precios. un proyecto tiene que poder reproducirse en cinco años
 con los mismos resultados; eso solo se logra con artefactos propios.

4. **APIs solo para entrenamiento.** Las APIs externas (Gemini, DeepSeek)
 se usan exclusivamente como *profesor* en distillation y RLAIF — generan
 datos sintéticos y juicios de preferencia. Pero **el modelo en producción
 es 100% nuestro**. Esta es la línea que separa "investigación con
 recursos" de "consumo de APIs".

## Arquitectura

```
 Imagen (RGB 224×224)
 │
 ▼
 ┌─────────────────────┐
 │ PatchEmbedder │ ml/model/vision/patch_embedder.py
 │ Conv2d(16×16) │
 │ → 196 patches │ cada uno = vector embed_dim=384
 │ + token CLS │
 │ + pos embeddings │
 └──────────┬──────────┘
 │
 ▼
 ┌─────────────────────┐
 │ Vision Transformer │ ml/model/vision/vit_encoder.py
 │ 6 capas │ no-causal attention, pre-norm
 │ 6 heads │ Flash via F.scaled_dot_product_attention
 │ embed_dim=384 │
 └──────────┬──────────┘
 │
 ▼ (B, 196, 384)
 ┌─────────────────────┐
 │ VisionProjector │ ml/model/vision/projector.py
 │ MLP 2 capas + GELU │
 │ 384 → hidden → 512 │
 └──────────┬──────────┘
 │
 ▼ (B, 196, 512)
 ┌──────────────────────────────────────────────────────┐
 │ GPTEducativoV2 (nuestro LLM) │
 │ │
 │ Entrada: [vis_tokens | text_embeds] │
 │ (B, 196 + T, 512) │
 │ │
 │ RoPE + GQA + SwiGLU + RMSNorm + FlashAttention │
 └──────────────────────────────────────────────────────┘
 │
 ▼
 logits (B, 196+T, vocab)
```

## Componentes — referencias bibliográficas

| Componente | Paper | Por qué este |
|------------|-------|--------------|
| **Patch embedding** | Dosovitskiy et al., *An Image is Worth 16×16 Words*, ICLR 2021 | Estándar ViT. Una sola Conv2d con stride=patch_size hace corte+proyección. |
| **ViT encoder** | Idem | Encoder-only, attention NO causal (imágenes no tienen orden temporal). |
| **MLP Projector** | Liu et al., *Visual Instruction Tuning (LLaVA)*, NeurIPS 2023 | LLaVA-1.0 usaba un Linear; LLaVA-1.5 mostró que MLP 2 capas + GELU es estrictamente mejor. |
| **Concatenación visual+texto** | Idem | En lugar de cross-attention (Flamingo), simplemente prepender tokens visuales mantiene la arquitectura del LLM intacta. Más simple, igual de efectivo a esta escala. |
| **Entrenamiento por etapas** | Idem | Etapa A (solo projector) alinea modalidades sin destruir el LLM. Etapa B refina todo conjuntamente. |

## Tamaños

| Modelo | Parámetros | Memoria (bf16) |
|--------|-----------|----------------|
| ViT (6×384) | ~10.6 M | ~21 MB |
| Projector | ~0.5 M | ~1 MB |
| LLM (8×512) | ~25 M | ~50 MB |
| **Total** | **~36 M** | **~72 MB** |

Tamaño comparable a LLaVA-tiny. Caben con holgura en una RTX 2050 (4 GB) con
batch=4–8 y secuencia de 256 tokens de texto + 196 visuales.

## Pipeline de entreno

### 1. Generar dataset sintético

```bash
python -m ml.data.generar_imagenes_codigo --n 2000
```

Genera `data/vision/imagenes/img_*.png` y `data/vision/pares.jsonl` con
snippets Python renderizados en 4 temas (VS Code dark/light, terminal verde,
Monokai). Cada par incluye imagen, instrucción y respuesta esperada.

### 2. Etapa A — pre-train del projector

```bash
python -m ml.train_multimodal --etapa a --iters 1500 --batch 8
```

ViT y LLM congelados. Solo se actualiza el adapter MLP. Aprende a "traducir"
el espacio del ViT al del LLM. Output: `runs/multimodal_a/best.pt`.

### 3. Etapa B — fine-tuning conjunto

```bash
python -m ml.train_multimodal --etapa b --iters 3000 --batch 4 \
 --checkpoint-prev runs/multimodal_a/best.pt
```

Descongela todo. LRs: ViT y LLM a 2e-5 (suaves), Projector a 1e-4. El modelo
aprende a razonar sobre código en imágenes. Output: `runs/multimodal_b/best.pt`.

## Verificación

```bash
python -c "
import torch
from ml.model.multimodal_model import ConfigMultimodal, ModeloMultimodal
m = ModeloMultimodal(ConfigMultimodal())
img = torch.randn(2, 3, 224, 224)
idx = torch.randint(0, 100, (2, 20))
logits, _ = m(img, idx)
print('logits.shape =', tuple(logits.shape)) # (2, 196+20, vocab)
print(m.num_parametros())
"
```

## Integración con el backend

El endpoint `POST /api/v1/chat/enviar-multimodal` (planificado) recibirá
multipart con imagen + texto, las pasará por `ModeloMultimodal.generar()` y
devolverá la respuesta. La capa intermedia será un servicio
`multimodal_service.py` análogo a `model_inference_service.py`.

> **Nota.** Hasta que se complete el entreno, el endpoint puede devolver
> "modelo en entrenamiento" — pero la arquitectura, el pipeline y los
> artefactos ya son los definitivos del proyecto.
