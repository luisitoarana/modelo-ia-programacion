# Diario de Progreso

> Bitácora cronológica de la preparación, generación de datos, entrenamiento
> y evaluación del modelo. Cada sesión queda documentada con fecha, lo que
> se hizo, lo que salió, lo que se aprendió y los próximos pasos.

---

## Sesión 1 — Preparación inicial en Lightning AI

**Fecha**: 2026-06-21
**Lugar**: Lightning AI Studio (`Luis / default-project / modelo-ia-programacion`)
**Hardware**: CPU (Default, 4 cores, 0.33 créditos/h)

### Lo que se preparó previamente

- Repositorio público en GitHub: `https://github.com/luisitoarana/modelo-ia-programacion`
- Toda la base del proyecto: backend, frontend, app desktop, `ml/`, docs, research.
- `.gitignore` blindado (no se suben `.env`, modelos, datasets, builds, secretos).

### Acciones realizadas en esta sesión

1. Clonado del repo dentro del Studio:

   ```bash
   git clone https://github.com/luisitoarana/modelo-ia-programacion.git
   cd modelo-ia-programacion
   ```

2. Creación del `.env` local con las API keys de Groq (Gemini queda
   pendiente, opcional).

3. Verificación del entorno:

   ```bash
   python -c "import torch; print('PyTorch', torch.__version__)"
   # → 2.8.0+cu128
   ```

   - PyTorch 2.8 con CUDA 12.8 ya instalado por defecto en Lightning.
   - NumPy, httpx y todas las dependencias `requirements.txt` ya presentes.
   - El proyecto importa sin errores.
   - EduCodeEval carga 30 tareas correctamente.

4. Pool de proveedores activo: solo `groq` por ahora.

### Conclusiones de la sesión

- Lightning AI viene preconfigurado con todo el stack CUDA, ahorra los
  3-5 minutos de instalación que tomaría en otra plataforma.
- El repo está limpio y listo para ejecutar cualquier script `ml/...`.
- Próximo paso: descargar datasets públicos y generar el dataset V2
  propio en paralelo.

---

## Sesión 2 — Descarga de datasets públicos

**Fecha**: (a completar)
**Comando objetivo**:

```bash
python -m ml.data.download_hf \
    --dataset codealpaca,codefeedback,magicoder-oss,magicoder-evol,apps,mbpp,humaneval,ds-1000,humaneval-plus,mbpp-plus \
    --salida-dir datasets/publicos \
    --schema-v2
```

**Datasets a descargar**:

| Dataset | Tamaño aprox | Por qué |
|---|---|---|
| `codealpaca` | 20 000 ejemplos | Instrucciones → código didáctico. |
| `codefeedback` | 156 000 ejemplos | Instrucciones + crítica de código. |
| `magicoder-oss` | 75 000 ejemplos | Instrucciones derivadas de código OSS real. |
| `magicoder-evol` | 110 000 ejemplos | Instrucciones evolucionadas iterativamente. |
| `apps` | 10 000 problemas | Problemas competitivos con tests. |
| `mbpp` | 1 000 problemas | Mostly Basic Python Problems. |
| `humaneval` | 164 problemas | Benchmark estándar de generación. |
| `humaneval-plus` | 164 problemas | Versión con tests más rigurosos. |
| `mbpp-plus` | 378 problemas | MBPP con tests robustos. |
| `ds-1000` | 1 000 problemas | Data science (pandas, numpy, sklearn). |
| **Total aproximado** | **~373 000 ejemplos** | en formato V2 (schema unificado). |

**Tiempo estimado**: 1-3 horas según la red.
**Espacio en disco**: ~3-5 GB.

### Resultado

(A completar tras la ejecución: cuántos ejemplos exactos por dataset,
tiempos reales, errores si los hubo.)

---

## Sesión 3 — Generación del Dataset V2 propio

**Fecha**: (a completar)
**Comando objetivo (smoke test mini)**:

```bash
python -m ml.data.construir_dataset_v2 \
    --salida-dir datasets/raw \
    --escala mini
```

**Comando objetivo (escala media, después del mini)**:

```bash
python -m ml.data.construir_dataset_v2 \
    --salida-dir datasets/raw \
    --escala media \
    --reset
```

**Tipos pedagógicos generados** (10 generadores en serie):

1. `pensamiento_programador` (47 objetivos, 8 dominios).
2. `explicacion_multinivel` (42 conceptos, 4 niveles cada uno).
3. `anti_patron` (30 antipatrones).
4. `bug_sutil` (25 categorías).
5. `evolucion_codigo` (15 problemas × 5 versiones).
6. `decision_diseno` (30 decisiones técnicas).
7. `arquitectura_sistema` (25 diseños).
8. `seguridad` (25 categorías OWASP+).
9. `testing_complejidad` (25 casos).
10. `pensamiento_autocritico` (20 problemas A→B→C).

**Tiempo estimado mini**: 30-60 min (con Groq 8b).
**Tiempo estimado media**: 3-5 horas.

### Resultado

(A completar.)

---

## Sesión 4 — Entrenamiento del Tokenizer V2

**Fecha**: (a completar)
**Comando objetivo**:

```bash
mkdir -p ml/tokenizer/artefactos
python ml/tokenizer/sp_tokenizer.py train \
    --corpus datasets/raw/dataset_v2.jsonl \
    --salida ml/tokenizer/artefactos/sp_v2_16k.model \
    --vocab-size 16000
```

**Tiempo estimado**: 5-15 min.
**Tamaño del archivo**: ~500 KB.

### Resultado

(A completar.)

---

## Sesión 5 — Auditoría del corpus consolidado

**Fecha**: (a completar)
**Comando objetivo**:

```bash
python -m ml.data.audit --corpus datasets/raw/dataset_v2.jsonl
```

**Métricas que se verifican**:

- Porcentaje de ejemplos válidos (objetivo: ≥ 98%).
- Duplicados (objetivo: ≤ 1%).
- Distribución por tipo / nivel / tema / fuente.
- Porcentaje de código que compila (objetivo: ≥ 95%).
- Porcentaje con chain-of-thought poblado (objetivo: ≥ 30%).

### Resultado

(A completar.)

---

## Sesión 6 — Activación de GPU y Fase 1 de entrenamiento

**Fecha**: (a completar)

**Acción 1**: cambiar el Studio de CPU a GPU T4 desde el panel de
Lightning AI.

**Acción 2**: lanzar la primera fase del entrenamiento:

```bash
python -m ml.training.run_fase \
    --config ml/training/configs/fase1_pretrain_B.yaml \
    --tiempo-max-minutos 525
```

**Modelo objetivo**: B (150 millones de parámetros), arquitectura V2
moderna (RoPE + GQA + SwiGLU + RMSNorm + FlashAttention).

**Tiempo estimado por chunk**: 8 horas 45 minutos (luego se reanuda).
**Tiempo total estimado Fase 1**: 25-40 horas en T4.

### Resultado

(A completar.)

---

## Plantilla para nuevas sesiones

```markdown
## Sesión N — Título

**Fecha**: YYYY-MM-DD
**Lugar**: Lightning AI Studio / RTX 2050 local / Modal / etc.
**Hardware**: CPU / GPU T4 / GPU A10G / etc.

### Lo que se hizo

(Descripción cronológica.)

### Comandos ejecutados

```bash
(Comandos exactos.)
```

### Resultado

(Salidas, métricas, tiempos.)

### Observaciones / aprendizajes

(Bugs encontrados, decisiones tomadas, ajustes para próxima sesión.)
```
