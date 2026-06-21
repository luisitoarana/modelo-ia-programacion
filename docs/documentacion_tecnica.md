# Documentación técnica

## Stack

| Capa | Tecnología | Versión |
|------|------------|---------|
| Backend | FastAPI | 0.115 |
| ORM | SQLAlchemy | 2.0 |
| Validación | Pydantic | 2.10 |
| DB | PostgreSQL | 16 |
| HTTP | httpx async | 0.28 |
| Auth | python-jose + bcrypt | — |
| Frontend | Next.js | 14.2 |
| Editor | Monaco | 4.6 |

## Modelo de datos (resumen)

- `usuarios`: identidad, rol, institución.
- `consultas`: prompt, modelo, tokens, latencia, estado, intentos de reparación.
- `datasets_educativos`: registro pedagógico estructurado en JSONB + flags de
 validación y exportación.
- `actividades`: ejercicios derivados.
- `evaluaciones`: respuestas y puntajes.

Relaciones clave:

- Usuario 1—N Consulta.
- Consulta 1—1 DatasetEducativo.
- DatasetEducativo 1—N Actividad, 1—N Evaluacion.

## Auto-curación de JSON

`backend/app/services/explanation_service.py:_validar_con_autocuracion`

1. Intenta `parsear_json_lenient` (extrae bloque, repara comas finales, comillas).
2. Si falla `pydantic.ValidationError` o `JSONIrrecuperableError`:
 - Construye prompt de reparación (`construir_prompt_reparacion`).
 - Reduce temperatura para máxima determinismo.
 - Vuelve a llamar al proveedor.
3. Repite hasta `AI_MAX_RETRIES_JSON_REPAIR` veces (default: 3).
4. Si nunca valida → lanza `ExplicacionServiceError`, la consulta queda en
 estado `FALLIDA` con `error_mensaje` registrado para análisis.

## Seguridad

- Contraseñas hasheadas con **bcrypt** (cost 12).
- JWT firmado HS256, expiración configurable.
- `SECRET_KEY` debe tener ≥ 32 caracteres (validado por Pydantic).
- Dependencias FastAPI (`obtener_usuario_actual`, `requerir_rol`) protegen
 rutas sensibles.
- CORS configurable por `.env`.

## Logging

`logs/sistema.log` (rotación de 5 MB × 5). Nivel por defecto INFO.
Cada error de proveedor IA loguea status HTTP y primeros 500 chars del body.

## Testing (siguiente fase)

Estructura sugerida:

```
backend/tests/
 unit/test_json_repair.py
 unit/test_explanation_service.py
 integration/test_routes_ai.py
```
