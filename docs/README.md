# Documentación del Proyecto

> Instalación vigente: [README principal](../README.md), [guía del jurado](INSTALACION_JURADO.md) y [validación de entrega](VALIDACION_INSTALACION_2026-10-13.md). Los puertos públicos locales son API 8765 y web 3000; PostgreSQL 16 en Docker permanece privado.

> Este directorio contiene la documentación completa del proyecto.
> Está organizada en dos niveles: documentos académicos (del proyecto)
> y documentos técnicos (para implementación y mantenimiento).
>
> Lee los documentos en el orden recomendado abajo para entender el
> proyecto sin información previa.

---

## Orden de lectura recomendado

### Para entender el QUÉ y el PORQUÉ del proyecto

1. **[`PROPUESTA_INVESTIGACION.md`](./PROPUESTA_INVESTIGACION.md)** — Propuesta académica formal. Empezar aquí para entender el problema, los objetivos y los resultados esperados.
2. **[`HOJA_DE_RUTA.md`](./HOJA_DE_RUTA.md)** — Roadmap del proyecto desde la fase 1 hasta el modelo final.
3. **[`PLAN_ENTRENAMIENTO_V2.md`](./PLAN_ENTRENAMIENTO_V2.md)** — Plan técnico detallado de las 5 fases de entrenamiento, hardware, recursos.

### Para entender el CÓMO (técnico)

4. **[`ARQUITECTURA_TECNICA.md`](./ARQUITECTURA_TECNICA.md)** — Descripción técnica de cada componente, flujo de datos, contratos.
5. **[`INFRAESTRUCTURA.md`](./INFRAESTRUCTURA.md)** — Infraestructura completa: backend, frontend, app-desktop, MCP, RAG, BD, containers.
6. **[`DATASET_V2.md`](./DATASET_V2.md)** — Especificación del corpus pedagógico (10 tipos de datos, schema extendido, pipeline de generación).
7. **[`REWARD_MODELS.md`](./REWARD_MODELS.md)** — Sistema multi-criterio de 6 reward models (Seguridad, Legibilidad, Escalabilidad, Arquitectura, Rendimiento, Mantenibilidad).
8. **[`CATALOGO_ARCHIVOS.md`](./CATALOGO_ARCHIVOS.md)** — Inventario completo: qué hace cada archivo, dependencias, a qué objetivo específico responde.
9. **[`GLOSARIO.md`](./GLOSARIO.md)** — Definiciones de todos los términos técnicos del proyecto.

### Para entender el PROCESO de desarrollo

8. **[`BITACORA_DESARROLLO.md`](./BITACORA_DESARROLLO.md)** — Registro cronológico: qué se hizo, en qué orden, qué decisiones se tomaron.
9. **[`DECISIONES_DISENO.md`](./DECISIONES_DISENO.md)** — 20 decisiones técnicas con justificación y alternativas consideradas. Crítico para la presentación.
10. **[`BUGS_Y_SOLUCIONES.md`](./BUGS_Y_SOLUCIONES.md)** — Incidentes encontrados durante implementación, causa raíz, solución aplicada.

### Para entender los RESULTADOS

11. **[`EXPERIMENTOS.md`](./EXPERIMENTOS.md)** — Registro de smoke tests, configuraciones probadas, métricas obtenidas.
12. **[`ENTRENAMIENTO.md`](./ENTRENAMIENTO.md)** — Guía de entrenamiento del modelo V1 (46M, fase 1).
13. **[`RLHF_PLAN.md`](./RLHF_PLAN.md)** — Plan original de RLHF (single-judge, anterior al sistema multi-criterio actual).

### Para REPRODUCIR el sistema

14. **[`GUIA_REPRODUCCION.md`](./GUIA_REPRODUCCION.md)** — Guía paso a paso desde clonar el repo hasta el modelo final.

---

## Documentación del producto (usuarios finales)

| Documento | Para quién |
|---|---|
| [`manual_usuario.md`](./manual_usuario.md) | Usuario final del sistema |
| [`manual_administrador.md`](./manual_administrador.md) | Administrador de la plataforma |
| [`instalacion.md`](./instalacion.md) | Quien instala el sistema |
| [`INSTALACION_JURADO.md`](./INSTALACION_JURADO.md) | revisor del proyecto durante la presentación |
| [`api_documentation.md`](./api_documentation.md) | Desarrollador que integra el backend |

---

## Documentación de capacidades específicas

| Documento | Sobre |
|---|---|
| [`AGENTE.md`](./AGENTE.md) | Capacidades agénticas |
| [`MCP_PLAN.md`](./MCP_PLAN.md) | Model Context Protocol |
| [`VISION_PLAN.md`](./VISION_PLAN.md) | Sistema multimodal (visión) |
| [`VISION_PROPIA.md`](./VISION_PROPIA.md) | ViT propio |
| [`RAG.md`](./RAG.md) | Sistema de Retrieval-Augmented Generation |
| [`MEJORAS_NIVEL_TOP.md`](./MEJORAS_NIVEL_TOP.md) | Análisis de gaps respecto al estado del arte |
| [`MODELO_V2.md`](./MODELO_V2.md) | Notas sobre el modelo V2 |
| [`arquitectura.md`](./arquitectura.md) | Arquitectura general del sistema |
| [`documentacion_tecnica.md`](./documentacion_tecnica.md) | Detalles técnicos adicionales |

---

## Cómo se usa esta documentación

### Para escribir la propuesta de investigación

La estructura típica de una propuesta es:
- Problema y justificación → [`PROPUESTA_INVESTIGACION.md`](./PROPUESTA_INVESTIGACION.md) secciones 2 y 3.
- Objetivos → sección 4.
- Marco teórico → sección 5.
- Metodología → sección 6 + [`ARQUITECTURA_TECNICA.md`](./ARQUITECTURA_TECNICA.md).
- Resultados esperados → sección 7.
- Cronograma → sección 8.

### Para escribir el documentación del proyecto

- sección de Introducción → secciones 2-3 de la propuesta.
- sección de Marco Teórico → sección 5 de la propuesta + referencias.
- sección de Metodología → sección 6 + [`PLAN_ENTRENAMIENTO_V2.md`](./PLAN_ENTRENAMIENTO_V2.md).
- sección de Diseño → [`ARQUITECTURA_TECNICA.md`](./ARQUITECTURA_TECNICA.md) + [`DECISIONES_DISENO.md`](./DECISIONES_DISENO.md).
- sección de Implementación → [`BITACORA_DESARROLLO.md`](./BITACORA_DESARROLLO.md) + [`CATALOGO_ARCHIVOS.md`](./CATALOGO_ARCHIVOS.md).
- sección de Desarrollo (iterativo, problemas) → [`BUGS_Y_SOLUCIONES.md`](./BUGS_Y_SOLUCIONES.md).
- sección de Resultados → [`EXPERIMENTOS.md`](./EXPERIMENTOS.md) + métricas finales.
- sección de Conclusiones → derivar de los objetivos cumplidos.

### Para la presentación del proyecto

El revisor típicamente pregunta:

| Pregunta | Documento que responde |
|---|---|
| "¿Por qué entrenas desde cero?" | [`DECISIONES_DISENO.md`](./DECISIONES_DISENO.md) DD-01 |
| "¿Por qué seis dimensiones de calidad?" | DD-05 |
| "¿Por qué DPO y no PPO?" | DD-08 |
| "¿Cómo evitas el catastrophic forgetting?" | DD-12 + [`PLAN_ENTRENAMIENTO_V2.md`](./PLAN_ENTRENAMIENTO_V2.md) §3 |
| "¿Cómo manejas las limitaciones de hardware?" | DD-13, DD-15 + [`PLAN_ENTRENAMIENTO_V2.md`](./PLAN_ENTRENAMIENTO_V2.md) §3 |
| "¿Cómo aseguras la calidad del corpus?" | DD-04 + [`DATASET_V2.md`](./DATASET_V2.md) §7 |
| "¿Qué problemas encontraste?" | [`BUGS_Y_SOLUCIONES.md`](./BUGS_Y_SOLUCIONES.md) |
| "¿Tu sistema es reproducible?" | DD-19 + [`EXPERIMENTOS.md`](./EXPERIMENTOS.md) §8 |

---

## Mantenimiento de la documentación

Cada vez que se hace una decisión técnica significativa:

1. **Si es una decisión arquitectónica**: agregar entrada a [`DECISIONES_DISENO.md`](./DECISIONES_DISENO.md) con formato DD-NN.
2. **Si es un bug o problema técnico**: agregar entrada a [`BUGS_Y_SOLUCIONES.md`](./BUGS_Y_SOLUCIONES.md) con formato BUG-NN.
3. **Si es un experimento**: agregar resultados a [`EXPERIMENTOS.md`](./EXPERIMENTOS.md).
4. **Si afecta el desarrollo histórico**: agregar entrada cronológica a [`BITACORA_DESARROLLO.md`](./BITACORA_DESARROLLO.md).
5. **Si es un componente nuevo**: agregar al inventario de [`CATALOGO_ARCHIVOS.md`](./CATALOGO_ARCHIVOS.md).
6. **Si afecta la metodología**: agregar entrada a `research/bitacora_investigacion.md`.

La documentación NO es un extra del proyecto: es donde vive el conocimiento que sustenta el proyecto.
