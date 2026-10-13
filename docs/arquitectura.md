# Arquitectura del sistema

> Instalación vigente: [README principal](../README.md), [guía del jurado](INSTALACION_JURADO.md) y [validación de entrega](VALIDACION_INSTALACION_2026-10-13.md). Los puertos públicos locales son API 8765 y web 3000; PostgreSQL 16 en Docker permanece privado.

## Diagrama de capas

```
+--------------------------------------------------------+
| Interfaces de Usuario                                 |
| - App Desktop (Flutter Windows Release)                |
| - Interfaz Web (Next.js)                               |
+--------------------------------------------------------+
        ↓ REST (JSON) / HTTP Local (Puerto 8765)
+--------------------------------------------------------+
| FastAPI (Capa de Presentación y Ruteo)                 |
| routes/ — auth, chat, ai_orchestrator, dataset,       |
| evaluation, research, knowledge                        |
+--------------------------------------------------------+
        ↓
+--------------------------------------------------------+
| Servicios (Aplicación / Dominio Pedagógico)            |
| - chat_service (orquestador de inferencia y contexto)  |
| - code_explainer_service (andamiaje didáctico AST)     |
| - educational_engine (gestión de explicaciones)        |
| - evaluation_service (calificación de actividades)     |
| - retrieval_service (RAG pedagógico en base local)     |
+--------------------------------------------------------+
        ↓                                ↓
+-----------------------------+ +------------------------+
| Motor Local de Inferencia   | | Repositorio de Datos   |
| - Modelo Propio IA          | | PostgreSQL / SQLite    |
| - Aceleración CUDA GPU      | | Modelos: Usuario,      |
| - Telemetría de tokens/s    | | Conversacion, Mensaje, |
| - Parser AST determinista   | | Dataset, Evaluacion    |
+-----------------------------+ +------------------------+
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

1. Estudiante envía consulta o código con nivel y modo deseado.
2. `chat_service` o `code_explainer_service` recibe la solicitud.
3. El servicio orquesta:
   1. Compone el prompt con andamiaje pedagógico estructurado.
   2. Ejecuta la inferencia en el motor neuronal propio local con aceleración GPU.
   3. Registra telemetría de rendimiento (latencia, tokens generados, velocidad tokens/s).
   4. Valida y estructura la respuesta (desglose paso a paso, complejidades, riesgos).
4. Se persiste la conversación y la telemetría en la base de datos.
5. Se retorna la respuesta didáctica a la interfaz de usuario (Flutter / Web).

## Extensibilidad

- **Nuevo proveedor LLM** (p. ej. modelo local): implementar `ProveedorIA`
 y registrarlo en `ai_provider.obtener_proveedor`.
- **Nuevo tipo de actividad**: añadir literal a `TipoActividadLiteral`
 y lógica en `EvaluationService._evaluar`.
- **Nuevo módulo educativo**: añadir carpeta en `knowledge_base/`.
