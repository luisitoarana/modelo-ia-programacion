# Modelo v2 — Arquitectura SOTA

> Documento técnico del proyecto. Explica cada componente del
> `transformer_v2.py` con la justificación bibliográfica y la
> diferencia frente al modelo v1 clásico.

---

## 1. Resumen ejecutivo

| Componente | v1 (clásico) | v2 (SOTA) | Beneficio |
|---|---|---|---|
| Codificación posicional | Sinusoidal aditiva | **RoPE** (rotatoria) | Extrapola a contextos largos sin re-entrenar |
| Atención | MHA (n_head heads K/V) | **GQA** (n_kv_head < n_head) | KV-cache 4× más chico → contexto largo en VRAM 4GB |
| FFN activación | GeLU en MLP 2-capas | **SwiGLU** (3 lineales con gate) | +2-4% calidad gratis |
| Normalización | LayerNorm | **RMSNorm** | ~7% más rápido, mismo resultado |
| Implementación atención | Manual (softmax(QK^T/√d) V) | **FlashAttention** vía `F.SDPA` | 3-10× más rápido + sin materializar matriz N×N |
| Bias en linears | True | **False** | Estabilidad + menos params |

**Resultado**: arquitectura comparable a **Llama 3 / Mistral / Qwen 2.5** en sus técnicas fundamentales, manteniéndose dentro de 4 GB de VRAM.

---

## 2. RoPE — Rotary Position Embeddings

**Paper**: Su et al., "RoFormer: Enhanced Transformer with Rotary Position Embedding", 2021.

### Idea matemática

En lugar de SUMAR una codificación posicional al embedding (lo que mezcla
información de "qué palabra" con "dónde está"), RoPE **rota los vectores
de query y key** en cada head, con un ángulo que depende de la posición.

Para cada par de dimensiones `(2i, 2i+1)` y posición `m`:

```
q'_(2i) = q_(2i) * cos(m·θ_i) - q_(2i+1) * sin(m·θ_i)
q'_(2i+1) = q_(2i) * sin(m·θ_i) + q_(2i+1) * cos(m·θ_i)
```

donde `θ_i = theta^(-2i/head_dim)` (frecuencias en progresión geométrica).

### ¿Por qué es mejor?

1. **El producto Q·K resultante depende solo de la DIFERENCIA de posiciones**
 (m - n), no de las posiciones absolutas. El modelo aprende "relaciones",
 no "posiciones fijas".

2. **Extrapola**: si entrenas con block_size=512, puedes inferir con 2048
 sin re-entrenar (técnica YaRN escala las frecuencias).

3. **Sin parámetros entrenables**: no añade peso al modelo.

### Implementación en nuestro código

`precomputar_rope(head_dim, max_seq_len, theta)` calcula `(cos, sin)` una
sola vez al inicializar el modelo y los guarda como buffer no persistente.

`aplicar_rope(q, k, cos, sin)` se llama en cada forward dentro de
`GroupedQueryAttention`, antes de calcular Q·K.

---

## 3. GQA — Grouped-Query Attention

**Paper**: Ainslie et al., "GQA: Training Generalized Multi-Query Transformer Models", 2023.

### Idea

En MHA estándar:
- 8 heads → 8 conjuntos de K y V independientes.

En GQA con `n_kv_head=2`:
- 8 heads de **query** comparten **2 pares** de K y V.
- Cada par K/V sirve a `n_head/n_kv_head = 4` heads.

### Beneficio cuantitativo

| Métrica | MHA (v1) | GQA (v2) | Ratio |
|---|---|---|---|
| Params K + V proyecciones | 2 × 512² = 524k | 2 × 512 × 128 = 131k | **4× menos** |
| KV-cache por token en inferencia | 8 × 64 × 2 = 1024 | 2 × 64 × 2 = 256 | **4× menos** |
| Calidad (en papers) | baseline | -0.5% a +0.2% | ≈ igual |

El KV-cache es lo que **limita el contexto** en inferencia (no la VRAM del
modelo en sí). Reducirlo 4× permite contextos 4× más largos en la misma GPU.

### Implementación

```python
self.wq = nn.Linear(n_embd, n_head * head_dim) # 8 heads
self.wk = nn.Linear(n_embd, n_kv_head * head_dim) # solo 2
self.wv = nn.Linear(n_embd, n_kv_head * head_dim) # solo 2

# En forward, después de proyectar, duplicamos K y V para compartirlos:
k = k.repeat_interleave(n_query_per_kv, dim=1) # 2 -> 8 heads
v = v.repeat_interleave(n_query_per_kv, dim=1)
```

---

## 4. SwiGLU — Activación con gating

**Paper**: Shazeer, "GLU Variants Improve Transformer", 2020.

### Diseño

Clásico FFN:
```
hidden = GeLU(W_in(x))
out = W_out(hidden)
```

SwiGLU:
```
hidden = silu(W_gate(x)) * W_up(x)
out = W_down(hidden)
```

- `silu(x) = x · σ(x)` (también llamada **Swish**) — variante suave de ReLU
- El producto elemento-a-elemento actúa como **gate**: cada dimensión decide
 cuánto de la información "pasa" o "se bloquea"

### ¿Por qué funciona mejor?

1. **Capacidad efectiva mayor**: el gate permite combinaciones no lineales
 más expresivas que una activación unitaria.
2. **Mejor gradient flow**: SiLU es suave en todo el dominio (a diferencia
 de ReLU que tiene gradiente 0 en negativos).

### Costo

Pasa de 2 a 3 lineales. Para mantener el conteo de parámetros similar al
FFN clásico, el hidden se reduce: `hidden = round_to_64(n_embd * 8/3)` en
lugar del clásico `hidden = n_embd * 4`.

---

## 5. RMSNorm

**Paper**: Zhang & Sennrich, "Root Mean Square Layer Normalization", 2019.

### Idea

LayerNorm:
```
μ = mean(x)
σ = std(x)
y = (x - μ) / σ * g + b
```

RMSNorm:
```
y = x / sqrt(mean(x²) + ε) * g
```

Se elimina:
- La **resta de la media** (μ)
- El **bias** (b)

### Beneficio

- ~7% más rápido (1 menos pasada sobre `x`)
- Sin pérdida de calidad en pruebas a escala
- Implementación más simple

### Stability trick

En nuestro código calculamos en `fp32` aunque la entrada sea `bf16`:

```python
x = x.float() # promotemos
norm = x * torch.rsqrt(x.pow(2).mean(-1) + eps)
return (peso * norm).to(original_dtype) # volvemos al dtype original
```

Esto evita problemas numéricos cuando `mean(x²)` se hace muy pequeño.

---

## 6. FlashAttention (vía PyTorch SDPA)

**Paper**: Dao et al., "FlashAttention: Fast and Memory-Efficient Exact Attention with IO-Awareness", 2022.

### Problema con la atención clásica

```python
att = softmax(Q @ K^T / sqrt(d_k)) # ← matriz (B, h, T, T)
y = att @ V
```

La matriz `att` es `T × T`. Para `T=4096` ocupa `4096² = 16M` valores
por head. Con 8 heads y batch 4 → **2 GB solo para esa matriz**, lo que
hace inviable el contexto largo en 4 GB de VRAM.

### Solución FlashAttention

No materializa la matriz `att` en HBM (memoria principal). En su lugar:
- Divide Q, K, V en bloques.
- Calcula la atención bloque por bloque dentro del **SRAM** del GPU.
- Usa rescaling online para mantener la equivalencia matemática exacta.

Resultado: usa O(N) memoria en lugar de O(N²). Hasta **10× más rápido**.

### Cómo lo usamos

PyTorch 2.0+ expone `F.scaled_dot_product_attention(q, k, v, is_causal=True)`
que internamente elige el mejor kernel:
- CUDA + dtype bf16/fp16 → **FlashAttention v2** (Triton kernel)
- CUDA + fp32 → kernel memoria-eficiente
- CPU → implementación clásica

No requiere instalar `flash-attn` aparte. Una sola línea:

```python
y = F.scaled_dot_product_attention(q, k, v, is_causal=True, dropout_p=...)
```

---

## 7. Cuándo usar v1 vs v2

### v1 (`transformer.py`)
- ✅ Pedagógico: cada paso es explícito y didáctico
- ✅ Más fiel al GPT original (para enseñar la arquitectura clásica)
- ✅ Compatible con presets clásicos (`nano`, `pequeno`,..., `xxl`)
- ❌ Más lento, más memoria, contexto corto

### v2 (`transformer_v2.py`)
- ✅ SOTA: técnicas que usan los modelos de 2024-2025
- ✅ Mucho más rápido en GPU
- ✅ Habilita contexto largo (8k+) en 4 GB VRAM
- ✅ Mejor calidad a igual número de parámetros
- ❌ Algo más complejo de entender (justificable: cada técnica está documentada)

**del proyecto**: entrenar ambos y comparar **es el experimento principal del capítulo de resultados**. Los modelos comparten dataset, tokenizador y dataset de evaluación, lo que produce una tabla cristalina:

| Modelo | Params | block_size | Loss val | tok/s entrenando | KB de KV-cache por token |
|---|---|---|---|---|---|
| v1 experto | 46M | 512 |... |... | 1024 |
| v2 sota_experto | 50M | 512 |... |... | 256 |

---

## 8. Cómo entrenar v2

```powershell
# Requiere `--modelo v2` para que train.py use el constructor nuevo
# (próxima tarea: integrar el flag en train.py)

ml/.venv/Scripts/python.exe -u -m ml.train `
 --preset sota_experto `
 --modelo v2 `
 --iters 30000 `
 --batch 8 `
 --experimento v2_sota `
 --corpus datasets/processed/corpus_entrenamiento.jsonl `
 --tokenizer-existente ml/tokenizer/artefactos/tokenizer_v1.json `
 --sin-semilla
```

(El flag `--modelo` aún no existe; lo añadiremos cuando termine el run actual v1 y entremos al run v2.)

---

## 9. Referencias del proyecto

```bibtex
@article{su2021roformer,
 title={RoFormer: Enhanced Transformer with Rotary Position Embedding},
 author={Su, Jianlin et al.},
 year={2021}, journal={arXiv:2104.09864}
}

@inproceedings{ainslie2023gqa,
 title={GQA: Training Generalized Multi-Query Transformer Models},
 author={Ainslie, Joshua et al.},
 year={2023}, booktitle={EMNLP}
}

@article{shazeer2020glu,
 title={GLU Variants Improve Transformer},
 author={Shazeer, Noam}, year={2020}, journal={arXiv:2002.05202}
}

@article{zhang2019rms,
 title={Root Mean Square Layer Normalization},
 author={Zhang, Biao and Sennrich, Rico}, year={2019},
 journal={NeurIPS}
}

@article{dao2022flashattention,
 title={FlashAttention: Fast and Memory-Efficient Exact Attention},
 author={Dao, Tri et al.}, year={2022}, journal={NeurIPS}
}
```
