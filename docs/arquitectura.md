# Arquitectura del sistema

## Diagrama de capas

```
+--------------------------------------------------------+
| Interfaz Web (Next.js 14) |
| Páginas, vista dividida código/explicación, layouts |
+--------------------------------------------------------+
 ↓ REST (JSON)
+--------------------------------------------------------+
| FastAPI (presentación) |
| routes/ — auth, ai_orchestrator, dataset, knowledge, |
| evaluation, research |
+--------------------------------------------------------+
 ↓
+--------------------------------------------------------+
| Servicios (aplicación / dominio) |
| explanation_service (orquestador + autocuración) |
| dataset_service (persistencia + JSONL) |
| evaluation_service (calificación de actividades) |
| knowledge_service (base de conocimiento) |
+--------------------------------------------------------+
 ↓
+--------------------------------------------------------+
| Proveedores IA | Repositorio (SQLAlchemy 2.0) |
| ai_provider: | PostgreSQL + JSONB |
| - GeminiProvider | Modelos: Usuario, Consulta, |
| - DeepSeekProvider | DatasetEducativo, Actividad, |
| - obtener_proveedor | Evaluacion |
+--------------------------------------------------------+
 ↓
+--------------------------------------------------------+
| Salidas para investigación |
| - Dataset JSONL para fine-tuning |
| - Reportes agregados (research routes) |
+--------------------------------------------------------+
```

## Principios arquitectónicos aplicados

- **Clean Architecture**: capas con dependencias hacia el dominio.
- **SOLID**: responsabilidad única por archivo; OCP en `ProveedorIA` (añadir
 modelos locales sin tocar el resto).
- **DDD ligero**: vocabulario del dominio en castellano educativo (Consulta,
 DatasetEducativo, Evaluacion).
- **CQRS pragmático**: `services/` lee y escribe; rutas son delgadas.
- **Inyección de dependencias**: FastAPI `Depends` para sesión, usuario, rol.

## Flujo: solicitud educativa

1. Estudiante envía `POST /ai/generar` con prompt + nivel + proveedor.
2. `ai_orchestrator.generar_explicacion` crea `Consulta` en estado
 `EN_PROCESO`.
3. `ExplanationService.explicar`:
 1. Compone prompt sistema (`prompt_pedagogico`) + prompt usuario.
 2. Llama al proveedor seleccionado (Gemini / DeepSeek).
 3. Parsea JSON con `parsear_json_lenient`.
 4. Valida contra `RespuestaIAEducativa` (Pydantic).
 5. Si falla → ciclo de auto-curación (hasta `AI_MAX_RETRIES_JSON_REPAIR`).
4. Si valida, `DatasetService.registrar_desde_respuesta` persiste el JSONB
 completo + campos derivados.
5. Se actualiza la `Consulta` con tokens, latencia e intentos de reparación.
6. Se devuelve `ConsultaLeer` al frontend.

## Extensibilidad

- **Nuevo proveedor LLM** (p. ej. modelo local): implementar `ProveedorIA`
 y registrarlo en `ai_provider.obtener_proveedor`.
- **Nuevo tipo de actividad**: añadir literal a `TipoActividadLiteral`
 y lógica en `EvaluationService._evaluar`.
- **Nuevo módulo educativo**: añadir carpeta en `knowledge_base/`.
