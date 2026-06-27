# Capturas de pantalla del proceso de entrenamiento

> Documentación visual paso a paso del entrenamiento real del modelo,
> los comandos ejecutados, los resultados observados y los hallazgos
> encontrados. Es complemento visual de los documentos
> `DIARIO_PROGRESO.md`, `EXPERIMENTOS.md` y `BITACORA_DESARROLLO.md`.

---

## Por qué existen estas capturas

Tres razones:

1. **Evidencia visual irreemplazable**: el código está en git, los
   métricas están en JSONL, pero **lo que se ve en la terminal en el
   momento exacto** solo queda si se captura. Los logs se truncan, los
   tmp se borran, las sesiones se cierran. La captura sobrevive.

2. **Reproducibilidad para quien lea esto después**: alguien que quiera
   reproducir el flujo ve exactamente qué comando se corrió, qué
   pantalla salió, y qué pasos siguieron.

3. **Documentación final del proyecto**: las capturas son la columna
   vertebral de la sección "Implementación" del informe del proyecto.
   Sin ellas, esa sección es solo prosa abstracta.

---

## Cómo se organiza

Una carpeta por **sesión** de trabajo. Cada sesión es un día (o un
bloque continuo de trabajo si dura varios días).

```
docs/capturas/
├── README.md                          # Este archivo
├── sesion-NN-YYYY-MM-DD/              # Una carpeta por sesión
│   ├── README.md                      # Índice + contexto de la sesión
│   ├── 01-<descripcion-corta>.png
│   ├── 02-<descripcion-corta>.png
│   └── ...
```

### Convenciones de nombres de archivo

| Patrón | Ejemplo |
|---|---|
| Numeradas en orden cronológico | `01-`, `02-`, `03-` |
| Descripción corta en kebab-case | `01-smoke-test-arranque.png` |
| Sin espacios, sin mayúsculas, sin acentos | `02-loss-final-modelo-b.png` |
| Extensión `.png` (no `.jpg` ni `.jpeg`) | (consistencia) |

### Qué capturar — checklist por tipo de paso

#### Antes de lanzar un comando
- Estado del directorio relevante (`ls -lh`).
- Procesos corriendo (`ps aux | grep <relevante>`).
- Espacio en disco (`df -h`) si la operación es pesada.

#### Durante un comando largo (entrenamiento, descarga)
- Los primeros logs (modelo cargado, dataset abierto, primeros pasos).
- Logs intermedios cada 1-2h si es muy largo (loss curve, ETA).
- Logs finales (último paso, métricas finales, checkpoint guardado).

#### Tras un comando
- Salida completa o relevante en la terminal.
- Archivos creados (`ls -lh` de la carpeta destino).
- Métricas (`tail` del `metrics.jsonl` correspondiente).

#### Cuando hay un error
- El traceback completo.
- El comando que lo provocó.
- El estado inmediato anterior.

---

## Cómo nombrar las sesiones

Una sesión nueva = una carpeta nueva con el formato:

```
sesion-NN-YYYY-MM-DD/
```

Donde:
- `NN` = número correlativo (continúa la numeración del
  `DIARIO_PROGRESO.md`).
- `YYYY-MM-DD` = fecha de inicio de la sesión.

Cada carpeta de sesión debe tener su propio `README.md` con:

- Resumen de lo que se hizo en esa sesión.
- Lista numerada de las capturas con descripción de cada una.
- Enlaces cruzados al `DIARIO_PROGRESO.md` correspondiente.

---

## Política de retención

- **Conservar todo**: nunca borrar capturas antiguas aunque parezcan
  obsoletas. Son evidencia histórica del proceso.
- **No editar**: las capturas son del momento exacto. Si una captura
  contiene un error, anotar el error en el `README.md` de la sesión,
  no editar la imagen.
- **Pseudo-anonimizar si hace falta**: tachar API keys, emails
  personales, paths con nombres de usuario que pueda quedar mal
  publicado. Pero solo eso.

---

## Sesiones documentadas

| Sesión | Fecha | Tema principal | Estado |
|---|---|---|---|
| Sesión 7 | 2026-06-22 | Smoke 30M + Modelo B v1 + ampliación corpus | Capturas perdidas (ver carpeta) |
| Sesión 8 | 2026-06-27 | Revisar estado del modelo B v1 + lanzar v2 | En curso |

---

## Para Claude (instrucción permanente)

Antes de pedir al usuario que ejecute cualquier comando que dure más
de 1 minuto, recordarle: **"Captura pantalla del antes y después,
guárdala en `docs/capturas/sesion-NN-YYYY-MM-DD/`."**

Después de la sesión, ayudar al usuario a generar el índice en el
`README.md` de esa carpeta y a hacer commit + push de las imágenes a
GitHub.
