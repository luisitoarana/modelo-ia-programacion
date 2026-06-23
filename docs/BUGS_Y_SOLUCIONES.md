# Bugs Encontrados y Soluciones Aplicadas

> Registro de los incidentes encontrados durante la implementación, su
> causa raíz, la solución aplicada y las lecciones aprendidas. Este
> documento sirve para el sección de Desarrollo de el proyecto, ya que
> evidencia el método iterativo de prueba y corrección.

---

## BUG-01: Parser de fences agarra bloques de código internos

### Síntoma

Al pedir al pool una respuesta en formato JSON, el modelo Groq
respondía con un array JSON correcto, pero internamente contenía
bloques ```` ```python... ``` ```` (porque la respuesta incluye código
Python en el campo `salida`). El parser devolvía `None` y el dataset no
generaba ningún ejemplo válido.

### Causa raíz

La función `_quitar_fences` en `pool_generadores.py` aplicaba la
expresión regular `r"```(?:json)?\s*(.*?)\s*```"` siempre, sin
verificar si el texto venía realmente envuelto en ```` ``` ````. Como
la respuesta contenía ```` ```python ```` interno, la regex
matcheaba ese fence interno y descartaba todo el JSON externo.

### Solución

Modificar `_quitar_fences` para que solo aplique la regex si el texto
empieza con ```` ``` ```` (es decir, si está realmente envuelto):

```python
def _quitar_fences(texto: str) -> str:
 texto_stripped = texto.strip()
 if not texto_stripped.startswith("```"):
 return texto
 m = re.match(r"```(?:json)?\s*(.*?)\s*```\s*$", texto_stripped, re.DOTALL)
 if m:
 return m.group(1)
 return texto_stripped.split("\n", 1)[1] if "\n" in texto_stripped else texto
```

### Verificación

Test manual con la misma llamada que fallaba: parser ahora extrae 2/2
items y ambos pasan validación.

### Lección aprendida

Las regex con `.*?` (non-greedy) y `(?:...)` se comportan de manera
poco intuitiva cuando hay matches anidados. Es preferible verificar la
condición de aplicabilidad antes de invocar la regex.

---

## BUG-02: `json.loads` rechaza saltos de línea literales dentro de strings

### Síntoma

Después de arreglar BUG-01, el parser todavía fallaba con error
`Invalid control character at line N column M`.

### Causa raíz

El JSON generado por el LLM contenía strings con saltos de línea
literales (no escapados como `\n`). Esto es común cuando el LLM
incluye código Python multilinea dentro del campo `salida`. Por
ejemplo:

```json
{
 "salida": "Aquí está el código:
```python
def f():
 pass
```
"
}
```

Los `\n` después de `"Aquí está el código:` no están escapados como
`\\n`. El parser JSON estricto rechaza estos caracteres de control
dentro de strings.

### Solución

Usar `json.loads(texto, strict=False)`, que permite caracteres de
control dentro de strings JSON.

```python
json.loads(m.group(0), strict=False)
```

### Lección aprendida

Cuando se parsea JSON generado por LLMs, asumir que NO será
estrictamente válido. Usar `strict=False` y un extractor robusto que
recupere lo recuperable.

---

## BUG-03: Modelo Groq 8B genera JSON con `}}` extra

### Síntoma

Con el modelo `llama-3.1-8b-instant` (mucho más rápido por tokens por
minuto que el 70B), el JSON generado a veces tenía estructuras
malformadas como `}}` extra entre objetos del array, o se truncaba
abruptamente cuando `max_tokens` se agotaba.

### Causa raíz

Los modelos más pequeños son menos disciplinados con el formato JSON
estricto. Además, cuando `max_tokens` es bajo, la respuesta se trunca
sin cerrar el último objeto o el array.

### Solución

Implementar un extractor robusto que NO depende de que el array global
parsee correctamente:

```python
def _extraer_objetos_balanceados(texto: str) -> list[Any]:
 objetos = []
 i = 0
 while i < len(texto):
 if texto[i] != "{":
 i += 1
 continue
 # Buscar el cierre balanceado a partir de i
 depth = 0
 in_string = False
 escape = False
 j = i
 while j < len(texto):
 c = texto[j]
 if in_string:
 if escape:
 escape = False
 elif c == "\\":
 escape = True
 elif c == '"':
 in_string = False
 else:
 if c == '"':
 in_string = True
 elif c == "{":
 depth += 1
 elif c == "}":
 depth -= 1
 if depth == 0:
 candidato = texto[i:j+1]
 try:
 objetos.append(json.loads(candidato, strict=False))
 except json.JSONDecodeError:
 pass
 i = j + 1
 break
 j += 1
 else:
 break # No cerró, terminar
 return objetos
```

Este algoritmo extrae cada objeto `{...}` que cierre con llaves
balanceadas, ignorando las llaves dentro de strings JSON (manejo
correcto de escape). Si un objeto es inválido, lo descarta y continúa
con el siguiente.

### Resultado

Con el extractor robusto, el dataset puede generarse aún con respuestas
parcialmente malformadas, lo que es típico de los LLMs más pequeños.

### Lección aprendida

Diseñar el sistema de extracción para que sea tolerante a respuestas
imperfectas. Los LLMs gratuitos son menos disciplinados que los pagos;
la robustez del parser determina la viabilidad del pipeline.

---

## BUG-04: Pool abandona ante 429 del server en lugar de esperar

### Síntoma

Cuando el server respondía con 429 (Too Many Requests), el pool reportaba
"todos los proveedores fallaron" inmediatamente y abandonaba el ciclo,
en lugar de esperar y reintentar.

### Causa raíz

La lógica original del pool ante un error:

```python
except Exception as exc:
 if _es_rate_limit_error(exc):
...
 # Penalizar este proveedor en intentos siguientes
 candidatos = [p for p in candidatos if p is not disponible]
 if not candidatos:
 break
```

Cuando solo había un proveedor (Groq, porque Gemini fallaba 401), el
pool lo quitaba de `candidatos` y al quedar la lista vacía
abandonaba con `break`.

### Solución (primera, descartada)

Saturar artificialmente el rate-limit local del proveedor para forzar
la espera en el siguiente iter del while:

```python
if _es_rate_limit_error(exc):
 rl = disponible.rate_limit
 rl.timestamps_min.extend([ahora] * rl.rpm)
...
 if esperar_si_rate_limited:
 candidatos = list(candidatos_originales)
 continue
```

Esta solución funcionó al principio, pero acumulaba timestamps cada
vez que el server respondía 429. Después de cinco 429 sucesivos, los
timestamps locales mostraban 150 llamadas en el último minuto (cinco
veces el RPM real), lo que extendía la espera a cuatro minutos por
llamada y atascaba completamente el pipeline.

### Solución definitiva

Reemplazar la saturación local por una espera fija de 60 segundos:

```python
if _es_rate_limit_error(exc):
 self._stats[disponible.nombre].rate_limited += 1
 if esperar_si_rate_limited:
 print(f" [pool] {disponible.nombre} 429, espera 60s...")
 await asyncio.sleep(60)
 candidatos = list(candidatos_originales)
 continue
```

### Verificación

El smoke test con el generador `pensamiento` completó las 20 llamadas
en 4.7 minutos, sin atascos.

### Lección aprendida

Cuando un fix introduce comportamiento que se acumula, hay que
analizar el caso de fallos repetidos. La solución "saturar para
forzar espera" parecía elegante pero era patológica.

---

## BUG-05: Clave Gemini formato OAuth no compatible con el endpoint

### Síntoma

Al usar una clave Gemini del formato `AQ.Ab8RN6ltX...`, el endpoint
respondía con 401 Unauthorized.

### Causa raíz

Las claves Gemini estándar de AI Studio empiezan con `AIzaSy...` y se
pasan como query parameter `?key=...`. Las claves que empiezan con
`AQ.` son tokens OAuth de un proyecto Google Cloud y requieren
autenticación distinta (Bearer token en header HTTP), no como query
parameter.

### Solución

Verificar el formato de la clave antes de usarla; si es OAuth,
solicitar que el usuario genere una clave estándar de AI Studio. Por
ahora, vaciamos la clave en `.env` para que el pool no la cargue, y
seguimos usando solo Groq.

### Lección aprendida

Los servicios cloud tienen múltiples mecanismos de autenticación
(API key vs OAuth). Documentar qué formato espera cada cliente. Para
producción robusta, detectar el formato y aplicar el método correcto.

---

## BUG-06: Sentencepiece no instalado interrumpe el runner

### Síntoma

Al importar `ml/training/run_fase.py` en un entorno sin
`sentencepiece` instalado, la inicialización del trainer falla.

### Causa raíz

El runner usa la clase `_Tokenizer` que importa `sentencepiece` en
tiempo de uso. Si el paquete no está, error.

### Solución

Documentar en el README que `sentencepiece` es dependencia obligatoria
del runner (`pip install sentencepiece`). En el código, falla pronto
con mensaje claro:

```python
def __init__(self, modelo_path: Path):
 import sentencepiece as spm
...
```

El mensaje de error de Python (`ModuleNotFoundError`) es suficientemente
claro.

### Lección aprendida

Las dependencias condicionales (no del core ML del proyecto) se
importan dentro de las clases, no en el top-level del módulo. Esto
permite que el módulo se importe en cualquier entorno y solo falle
cuando realmente se usa.

---

## BUG-07: Rate limit de Groq 70B muy restrictivo para volumen

### Síntoma

Con el modelo `llama-3.3-70b-versatile`, el rate limit por tokens por
minuto (6 000 TPM) hacía que el dataset mini full (235 llamadas con
~4 000 tokens cada una) requiriera ~3 horas mínimo en TPM puro, más
latencia de cada llamada. En la práctica, el pipeline tardaba más de 4
horas, lo que no es práctico para un smoke test.

### Causa raíz

Limitaciones del tier gratuito de Groq con el modelo de 70 mil millones
de parámetros. El modelo es excelente en calidad pero costoso en tokens
por minuto.

### Solución

Para smoke tests y volumen masivo, cambiar a
`llama-3.1-8b-instant` que tiene 20 000 TPM (3.3× más rápido). El
modelo es menos disciplinado con JSON, pero el extractor robusto
(BUG-03) compensa esto.

Para tareas críticas que requieren mejor calidad (por ejemplo,
generar el corpus de auto-crítica del Nivel 12), se puede usar el 70B
con concurrencia muy baja, aceptando que tomará más tiempo.

### Lección aprendida

Los tiers gratuitos tienen trade-offs claros: calidad vs throughput.
Diseñar el sistema para usar distintos modelos según la tarea
(parámetro `tarea` en el pool) y caer al más rápido para volumen.

---

## BUG-08: Backtick triple en script bash inline rompe el parser

### Síntoma

Al intentar ejecutar un script Python inline en bash que contenía
literales ```` ``` ```` (triple backtick), el shell fallaba con
`unexpected EOF while looking for matching backtick`.

### Causa raíz

Bash interpreta backticks como sustitución de comando, incluso cuando
están dentro de strings de Python pasados a `python -c`.

### Solución

Guardar el script en un archivo separado (`scripts/debug_parser.py`)
y ejecutarlo con `python -m scripts.debug_parser`. Para scripts que
necesitan caracteres especiales del shell, NO usar `python -c`.

### Lección aprendida

Scripts de debug deberían ir en archivos del repositorio (en
`scripts/`), no inline en el shell. Beneficios adicionales:
- Versionable en Git.
- Reutilizable.
- No tiene problemas de escape.

---

## BUG-09: Sintaxis incorrecta de tupla-clave-valor en dict literal

### Síntoma

Al definir `_MAPEO_V2` en `download_hf.py`, escribí accidentalmente
`"alpaca-es", : (...)` (con coma extra antes del `:`), lo que produjo
`SyntaxError`.

### Causa raíz

Typo. El IDE lo permitió porque la coma puede ser válida en otros
contextos (tuple).

### Solución

Removida la coma extra: `"alpaca-es": (...)`.

### Lección aprendida

Los dict literales son especialmente propensos a este typo. Vale la
pena correr `python -c "from módulo import OBJETO"` después de cada
cambio significativo para detectar SyntaxError rápido.

---

## BUG-10: `validar_salida_pedagogica` rechaza ejemplos cortos con código intencional

### Síntoma

En un test manual, un ejemplo con código Python intencional pero
explicación corta (~75 caracteres fuera de los fences) fue rechazado
con el motivo "solo código, sin explicación pedagógica".

### Causa raíz

`validar_salida_pedagogica` aplica una heurística para detectar
respuestas que son solo bloques de código sin contexto: si después de
quitar los fences quedan menos de 100 caracteres de texto, lo rechaza.
Esto es por diseño para evitar respuestas LLM degeneradas, pero puede
ser muy estricto en algunos casos legítimos.

### Solución

Mantener el umbral en 100 caracteres como compromiso entre falsos
positivos (rechazar ejemplos buenos) y falsos negativos (aceptar
basura). En los tests durante desarrollo, todos los ejemplos válidos
de los generadores reales tienen explicación amplia (300+ caracteres
fuera de fences), así que el umbral no genera problemas prácticos.

### Lección aprendida

Las heurísticas de validación tienen falsos positivos. Documentar el
threshold elegido y la justificación, para futuros ajustes informados.

---

## BUG-11: Tipo de `Optional` no exportado desde typing

### Síntoma

En `pool_generadores.py`, código original usaba `Optional[dict]` que
requería `from typing import Optional`, pero la versión Python actual
prefiere `dict | None` (sintaxis 3.10+).

### Solución

Reescribir todas las anotaciones de tipo a la sintaxis moderna
(`dict | None` en lugar de `Optional[dict]`). El proyecto requiere
Python 3.11+ explícitamente.

### Lección aprendida

Estandarizar la versión mínima de Python en el README. Usar la sintaxis
moderna de type hints donde sea posible.

---

## Tabla resumen

| ID | Bug | Severidad | Tiempo de fix |
|---|---|---|---|
| BUG-01 | Parser de fences agarra bloques internos | Alta | 15 min |
| BUG-02 | `json.loads` rechaza `\n` literales | Alta | 5 min |
| BUG-03 | 8B genera JSON malformed | Media | 30 min |
| BUG-04 | Pool abandona en 429 | Alta | 25 min |
| BUG-05 | Clave Gemini formato OAuth | Baja | 5 min |
| BUG-06 | Sentencepiece no instalado | Baja | (documentación) |
| BUG-07 | Rate limit Groq 70B restrictivo | Media | 5 min |
| BUG-08 | Backtick en bash inline | Baja | 2 min |
| BUG-09 | Typo `,` extra en dict | Baja | 1 min |
| BUG-10 | Validador rechaza ejemplos legítimos | Baja | (acepta) |
| BUG-11 | Optional vs `\| None` | Baja | (estilo) |
| BUG-12 | Tokenizer config apunta a `.json` en lugar de `.model` | Alta | 2 min |
| BUG-13 | Corpus en `/tmp` no persiste tras reinicio del Studio | Media | 2 min |
| BUG-14 | HF deprecó dataset scripts (`cot`, `python-edu` fallan) | Media | (skip) |
| BUG-15 | `open-code-interp` guardado en `datasets/raw/` en lugar de `datasets/publicos/` | Baja | 1 min |

---

## BUG-12: Config de tokenizer apunta a `.json` en lugar de `.model`

### Fecha de descubrimiento

2026-06-22, durante el primer smoke test del modelo 30M en Lightning AI.

### Síntoma

Al lanzar `python -m ml.training.run_fase --config ml/training/configs/smoke_sft.yaml`,
el runner crashea con:

```
RuntimeError: Internal: could not parse ModelProto from
ml/tokenizer/artefactos/sp_v2_16k.json
```

### Causa raíz

La clase `_Tokenizer` en `ml/training/run_fase.py` línea 72 invoca
`self.sp.Load(str(modelo_path))`, que es el método de
**sentencepiece nativo** y espera el archivo binario `.model`.

El YAML `smoke_sft.yaml` apuntaba por error al wrapper `.json` del
proyecto (que contiene metadatos pero no es ModelProto).

### Solución

Cambiar una línea en el YAML:

```yaml
# Antes:
tokenizer: ml/tokenizer/artefactos/sp_v2_16k.json
# Después:
tokenizer: ml/tokenizer/artefactos/sp_v2_16k.model
```

Commit `161d339`.

### Verificación

Tras el fix, el runner cargó el tokenizer correctamente y el smoke test
completó las 1000 iteraciones bajando loss de 9.21 → 3.94.

### Lección aprendida

Sentencepiece tiene **dos formatos de archivo**: el `.model` nativo
(ModelProto serializado) y wrappers de proyectos (a menudo `.json` con
metadatos + vocab). Siempre apuntar al `.model` cuando el código usa
`sp.Load()`.

---

## BUG-13: Corpus en `/tmp` no persiste tras reinicio del Studio

### Fecha de descubrimiento

2026-06-22, al reanudar Lightning AI después de cierre de pestaña.

### Síntoma

Tras `git pull` para traer el fix BUG-12, el runner crashea con:

```
FileNotFoundError: jsonl inexistente: /tmp/corpus_tokenizer.jsonl
```

A pesar de que ese archivo se había creado en la sesión anterior.

### Causa raíz

Lightning AI **no preserva `/tmp` entre sesiones del Studio** (es como
una RAM disk efímera). Cuando el Studio se suspende por inactividad o
se reinicia, todo en `/tmp` se borra.

El smoke test config `smoke_sft.yaml` apuntaba a `/tmp/corpus_tokenizer.jsonl`
porque originalmente era el output temporal del entrenamiento del
tokenizer V2.

### Solución

Reconstruir el corpus concatenando los JSONL descargados:

```bash
cat datasets/publicos/*.jsonl datasets/raw/dataset_v2.jsonl > /tmp/corpus_tokenizer.jsonl
```

Comando idempotente; lo recreas cada vez que vuelves al Studio.

### Solución de fondo (pendiente)

Cambiar el config para apuntar a una ruta persistente:

```yaml
corpus:
  jsonl: datasets/corpus_consolidado.jsonl
```

Y crear ese archivo una sola vez con un script que regenere si no existe.

### Lección aprendida

**Las rutas en `/tmp` solo son seguras dentro de UNA sesión.** En
plataformas con Studios efímeros (Lightning, Colab, Kaggle), usar
siempre rutas dentro del repo o de volúmenes persistentes.

---

## BUG-14: HuggingFace deprecó dataset scripts (`cot`, `python-edu` fallan)

### Fecha de descubrimiento

2026-06-22, durante la descarga masiva de datasets adicionales.

### Síntoma

Dos datasets crashean al cargar con:

```
RuntimeError: Dataset scripts are no longer supported, but found CoT-Collection.py
RuntimeError: Dataset scripts are no longer supported, but found <nombre>.py
```

Mismo error que tuvimos previamente con `apps` y `mbpp` (antes de
moverlos a versiones `apps`/`mbpp-plus`).

### Causa raíz

La librería `datasets` de HuggingFace **deprecó los "dataset scripts"**
(archivos `.py` que definían el loader) en favor del nuevo formato
parquet/streaming. Datasets que aún usan scripts viejos:

- `kaist-ai/CoT-Collection` → `CoT-Collection.py`
- `HuggingFaceTB/smollm-corpus` config `python-edu` → falla silenciosa

### Solución (workaround)

Skipear esos datasets:

```bash
python -m ml.data.download_hf --dataset codeparrot-py,openhermes,alpaca-es,open-code-interp \
    --salida-dir datasets/publicos --schema-v2 --max-items 200000
```

Excluyendo `cot` y `python-edu` de la lista.

### Solución de fondo (futuro)

Reemplazar por alternativas modernas:

| Dataset deprecado | Alternativa moderna |
|---|---|
| `kaist-ai/CoT-Collection` | `Open-Orca/OpenOrca` (más grande, GPT-4 distilled) |
| `HuggingFaceTB/smollm-corpus` python-edu | `HuggingFaceTB/cosmopedia` (Python educational) |
| `apps` | `codeparrot/apps` (versión sin script) |

Agregar manejo de errores en `ml/data/download_hf.py` para que si un
dataset falla, continúe con los demás en lugar de abortar todo el
proceso.

### Impacto

Ninguno crítico: `codeparrot-py` cubre Python masivo y los otros 4
datasets descargados (codeparrot-py + openhermes + alpaca-es +
open-code-interp) aportan 882K ejemplos.

### Lección aprendida

**Los datasets de HuggingFace tienen vida útil limitada.** Antes de
incluir un dataset en el pipeline, verificar:

1. ¿Está activamente mantenido?
2. ¿Usa el nuevo formato parquet/safetensors?
3. ¿Hay una versión `bigcode/`, `Open-Orca/`, o `HuggingFaceTB/`
   (mantenidos por equipos serios)?

---

## BUG-15: `open-code-interp` guardado en `datasets/raw/` en lugar de `datasets/publicos/`

### Fecha de descubrimiento

2026-06-22, tras descarga individual de `open-code-interp`.

### Síntoma

A pesar de pasar `--salida-dir datasets/publicos`, el archivo terminó
en `datasets/raw/open-code-interp.jsonl`.

### Causa raíz

A confirmar leyendo el código de `download_hf.py`. Posibles causas:

- Hardcode de `datasets/raw/` en alguna ruta interna del script.
- Conflicto entre `--salida-dir` y el directorio por defecto.

### Solución temporal

```bash
mv datasets/raw/open-code-interp.jsonl datasets/publicos/
```

### Solución de fondo (pendiente)

Auditar `ml/data/download_hf.py` para que respete consistentemente el
`--salida-dir`.

### Lección aprendida

Cuando un script soporta múltiples paths de salida, **verificar que el
flag de CLI realmente se respete** en todas las rutas internas del
código.

---

## Lecciones generales

1. **Los LLMs gratuitos generan respuestas imperfectas**: el sistema
 debe tolerar JSON malformed, truncated, con caracteres de control
 no escapados.

2. **Los rate limits del cloud requieren manejo cuidadoso**: 429
 transitorios deben provocar espera, no abandono.

3. **Los smoke tests revelan más bugs que los unit tests**: probar el
 pipeline completo con APIs reales descubrió 4 bugs críticos que los
 tests unitarios no habrían encontrado.

4. **Documentar bugs es valioso del proyecto**: la sección de
 "Desarrollo iterativo y resolución de problemas" del documentación se
 construye a partir de este documento.
