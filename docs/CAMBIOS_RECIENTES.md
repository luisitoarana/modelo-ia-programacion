# Cambios recientes — Visión, RLHF, Documentación

> Resumen ejecutivo de lo añadido en esta iteración. Para detalle ver
> los planes individuales en esta misma carpeta `docs/`.

---

## 1. Documentación nueva (del proyecto)

5 documentos clave creados en `docs/`:

| Archivo | Propósito |
|---|---|
| `HOJA_DE_RUTA.md` | Visión completa: 7 fases desde plataforma hasta producto comercial |
| `ENTRENAMIENTO.md` | Guía paso a paso para entrenar el modelo propio en RTX 2050 |
| `RLHF_PLAN.md` | Plan completo de DPO + RLAIF, métricas, timeline |
| `VISION_PLAN.md` | Arquitectura multimodal con Gemini Vision |
| `MCP_PLAN.md` | Plan Model Context Protocol (filesystem, Python REPL, Unity) |

Todos en español, con tablas, fórmulas y comandos copy-paste. Listos
para citar en el documentación de la propuesta de investigación.

---

## 2. Feedback Loop (base RLHF) — IMPLEMENTADO

### Backend
- **Nuevo modelo** `Feedback` en `backend/app/models/feedback.py`
 - Guarda: usuario, mensaje, voto (+1/-1), razón, comentario,
 prompt original, respuesta, modelo usado
 - Flag `procesado` para que el exportador no reuse votos ya usados
- **Schemas Pydantic** en `backend/app/schemas/feedback.py`
- **Endpoints REST** en `backend/app/routes/feedback.py`:
 - `POST /api/v1/feedback` — registrar voto
 - `DELETE /api/v1/feedback/{id}` — deshacer
 - `GET /api/v1/feedback/estadisticas` — KPI admin
 - `GET /api/v1/feedback/recientes` — listar para revisar (admin)

### Frontend web
- **Servicio** `frontend/src/services/feedback.ts`
- Los botones 👍/👎 del chat AHORA **persisten al backend** (antes solo
 cambiaban estado local)
- Optimistic UI con rollback si la API falla
- Tooltip explica que el voto ayuda a entrenar el modelo

### Desktop
- Método `ApiClient.enviarFeedback()` en `app-desktop/lib/api.dart`
- Los thumbs en chat desktop también persisten al backend ahora
- Misma UX (optimistic + rollback)

### Exportador
- `ml/rlhf/exportar_dataset.py` — script CLI que convierte votos
 acumulados en dataset DPO `.jsonl`
- 2 estrategias:
 1. **Pares directos** — cuando hay 👍 y 👎 para el mismo prompt
 2. **RLAIF** (opcional con `--rlaif`) — Gemini genera la respuesta
 mejorada para los 👎 sin par humano
- Marca `procesado=True` con `--marcar-procesados` para no reusar

**Comando típico**:
```powershell
python -m ml.rlhf.exportar_dataset --salida ml/data/dpo_v1.jsonl
```

---

## 3. Visión multimodal — IMPLEMENTADO

### Backend
- **Nuevo método** `GeminiProvider.generar_multimodal()` que acepta
 imágenes (bytes + mime_type) y las envía a Gemini Vision API
- **`ChatService.enviar_mensaje()`** ahora acepta `imagenes` opcional
 y enruta forzadamente a Gemini cuando hay imágenes
- **Nuevo endpoint** `POST /api/v1/chat/conversaciones/{id}/mensajes-multimodal`
 (multipart form-data) — paralelo al JSON existente para no romper
 compatibilidad

### Límites configurados
- Max 3 imágenes por mensaje
- Max 5 MB por imagen
- Formatos: PNG, JPEG, WebP

### Casos de uso desbloqueados
- 📷 Foto de error de consola → asistente lo diagnostica
- 📷 Diagrama a mano alzada → asistente lo explica
- 📷 Screenshot de IDE con código → asistente lo refactoriza

> **Pendiente para próximo turno**: wire el frontend (composer admite
> imágenes, las envía al endpoint multipart). El backend está listo.

---

## 4. Migración de BD

La nueva tabla `feedbacks` se crea automáticamente al iniciar el
backend (vía `init_models()` en `app/database.py`).

Si tu BD ya existe y quieres añadir solo esa tabla:

```python
# Desde un REPL del backend
from app.database import init_models
import asyncio
asyncio.run(init_models())
```

O recrear todo (CUIDADO — borra datos):

```sql
DROP TABLE IF EXISTS feedbacks CASCADE;
-- Luego reiniciar el backend
```

---

## 5. Próximos pasos sugeridos

| # | Tarea | Estado | Esfuerzo |
|---|---|---|---|
| 1 | Wire frontend web para subir imágenes al endpoint multimodal | ⏳ | 1 turno |
| 2 | Wire desktop para subir imágenes | ⏳ | 1 turno |
| 3 | Dataset RLHF inicial con feedback de los primeros 100 usos | ⏳ | depende de uso |
| 4 | Primer entrenamiento DPO (`ml/rlhf/dpo.py`) | 📄 doc'd | 1 turno |
| 5 | MCP server propio (`mcp_server/main.py`) | 📄 doc'd | 2-3 turnos |
| 6 | Modo IDE en desktop (editor + chat lateral) | 📄 doc'd | 5+ turnos |
| 7 | Tour del proyecto: capturas + métricas para el documentación | ⏳ | 1 turno |

---

## 6. Cómo reiniciar todo

```powershell
# Backend (Docker)
cd C:\Users\tanyi\OneDrive\Escritorio\sistema-explicador-python-ia
docker compose restart backend

# Web frontend
docker compose restart frontend

# Desktop
cd app-desktop
flutter pub get
flutter run -d windows
```

Verifica:
- `http://localhost:8000/docs` → endpoints `/feedback` aparecen
- Chat web/desktop: 👍/👎 en una respuesta → ver en
 `http://localhost:8000/api/v1/feedback/estadisticas` (admin)
