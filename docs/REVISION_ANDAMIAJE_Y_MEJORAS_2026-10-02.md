# Revisión de Python IA y propuesta de mejoras para la tesis

Fecha: 2 de octubre de 2026. Revisión del estado local, incluidos los cambios sin confirmar en Git. Los hallazgos describen el estado inicial observado; algunas correcciones ya se aplicaron después de esta revisión.

**Actualización de implementación:** `Explicar código` incluye ahora una pestaña de práctica con predicción, pistas secuenciales, explicación propia y registro de intento sin nota de IA. La condición y fase asignadas por el docente se guardan en el servidor y prevalecen sobre la elección local para chat e intentos. Se corrigieron errores concretos del evaluador, analizador, currículo, procedencia del motor y continuación del código generado. Véase [protocolo piloto](../research/PROTOCOLO_PRE_POST_ANDAMIAJE.md). La ejecución integral con el modelo y la validez del instrumento pre/post siguen pendientes de comprobación; no presentar este avance como efecto educativo demostrado.

**Conclusión:** existe una base aprovechable de IA, editor, explicador y currículo. El siguiente avance debe cerrar el ciclo de aprendizaje: diagnosticar → pedir un intento → ofrecer ayuda graduada → comprobar comprensión → resolver un problema nuevo sin ayuda. La prioridad científica es medir qué aprende el estudiante y asegurar que las explicaciones y mediciones sean fiables.

## 1. Alcance y comprobaciones

Se revisaron las rutas principales de backend, escritorio Flutter, portal web, selección de modelos, currículo, explicación automática, evaluación, ejecución de código y documentos/benchmarks de investigación. No se hizo una auditoría exhaustiva de cada archivo ni una sesión visual completa de la aplicación.

- Análisis de sintaxis de **171 archivos Python** de backend/app, ml, mcp_server y scripts: sin errores sintácticos. Esto no prueba corrección funcional.
- TypeScript: `tsc --noEmit --incremental false`, correcto.
- Dart: `dart analyze lib test`, sin errores, con 8 advertencias y 36 informativos; salida 1 por advertencias.
- Se reprodujeron seis casos problemáticos del analizador Python y tres del evaluador mediante llamadas locales aisladas, sin modelos ni base de datos. Para el evaluador se cargaron sus funciones sin importar SQLAlchemy; no fue una prueba de API.
- Se leyó la cabecera del GGUF sin cargar sus pesos y se revisaron resultados de entrenamientos existentes.
- No se ejecutaron entrenamientos, benchmarks nuevos ni inferencias; no se instalaron dependencias ni se modificó la aplicación.
- No respondió el backend esperado en 8765 ni el portal en 3000. El servicio en 8000 devolvió un health diferente al código de este proyecto y 404 en rutas consultadas. **No quedó confirmado el modelo cargado ni el funcionamiento integral en ejecución.**

## 2. Qué existe y cómo organizar los módulos

Flutter ya permite acceder desde Explicar y Code a **3 módulos y 11 lecciones**, también presentes en el servicio curricular del backend:

| Módulo actual | Contenido existente | Mejora pedagógica recomendada |
|---|---|---|
| Fundamentos: 4 lecciones | Variables, tipos, palabras reservadas, indentación | Predecir resultados, convertir tipos y distinguir nombres integrados de palabras clave |
| Control y colecciones: 4 lecciones | Condicionales, bucles/acumuladores, listas, errores por división entre cero | Completar código, seguir valores de variables y explicar errores con casos concretos |
| Funciones y algoritmos: 3 lecciones | Funciones, búsqueda binaria/Big-O, POO | Introducir funciones básicas antes de tareas que ya usan `def/return`; reservar Big-O y POO para ampliación |

Ubicaciones: `app-desktop/lib/services/curriculum_catalog.dart:39`, `backend/app/services/curriculum_service.py:55`, `app-desktop/lib/widgets/explicar_view.dart:545`, `app-desktop/lib/widgets/code_view.dart:744`.

Cada unidad debería contener: objetivo observable, prerrequisitos, ejemplo trabajado, ejercicio incompleto, pistas graduadas, pregunta conceptual, reto nuevo y criterio de dominio. Un nivel seleccionado manualmente no demuestra competencia alcanzada.

Los módulos funcionales que conviene presentar al profesor son: **diagnóstico, aprendizaje guiado, laboratorio de código, evaluación y seguimiento docente**. Pueden aprovechar las pantallas existentes; no requieren cinco aplicaciones separadas.

Después del piloto se puede ampliar con diccionarios, archivos y módulos Python (`import`, archivos `.py` y reutilización). La arquitectura puede permitir otros lenguajes en el futuro, manteniendo Python como alcance de la evaluación actual.

## 3. Capacidades nuevas con mayor valor

| Prioridad | Capacidad | Comportamiento concreto | Evidencia que produciría |
|---|---|---|---|
| 1 | Diagnóstico por concepto | Pedir que prediga una salida, complete una línea y justifique una decisión | Desempeño inicial por variables, bucles y funciones; errores identificados |
| 1 | Tutor con pistas graduadas | Pedir intento; revelar una pista conceptual, luego ubicación del error, pseudocódigo y finalmente un fragmento | Intentos, tipo de error, cantidad/nivel de ayudas y respuesta tras cada ayuda |
| 1 | Evaluación de comprensión | Solicitar explicación propia, corrección de un error y un caso límite | Rúbrica conceptual y pruebas funcionales, registradas por separado |
| 1 | Retirada de ayuda y transferencia | Reducir apoyo tras aciertos independientes; plantear otra tarea sin tutor | Resolución de problemas nuevos y dependencia de ayudas |
| 1 | Panel del docente y registro experimental | Mostrar avance por objetivo, errores frecuentes, pre/post-test y condición asignada | Datos exportables que permitan contrastar las dos condiciones |
| 2 | Ejecución paso a paso | Resaltar línea ejecutada y valores de variables, usando una traza real | Predicción del alumno frente a la ejecución observada |
| 2 | Retroalimentación basada en pruebas | Probar entradas normales, límites y errores; relacionar la explicación con el fallo real | Casos aprobados y capacidad de reparar código |
| 2 | Perfil persistente del estudiante | Elegir próxima práctica según errores y tareas resueltas sin ayuda | Historial por concepto y justificación de la adaptación |
| 3 | Revisión de buenas prácticas | Comentar nombres, responsabilidades de funciones y legibilidad, con criterios publicados | Mejoras justificadas por el estudiante, sin confundir estilo con corrección |

Un primer perfil adaptativo puede usar reglas sencillas y transparentes: ante el mismo error conceptual, ofrecer un ejemplo más pequeño; tras tareas nuevas resueltas sin ayuda, reducir apoyo. Los umbrales deben pilotarse y no presentarse como dominio científicamente validado.

La base teórica del andamiaje incluye ayuda ajustada al desempeño, retirada gradual y transferencia de responsabilidad. Aplicar estos principios al tutor es una propuesta de diseño; no demuestra de antemano su eficacia en universitarios ni con IA. [Van de Pol, Volman y Beishuizen, 2010](https://link.springer.com/article/10.1007/s10648-010-9127-6).

## 4. Problemas que deben corregirse para que esas capacidades sean fiables

### Identidad del modelo y trazabilidad — prioridad alta

No aparece una etiqueta exacta «B1». Existen **Modelo B (150M–5K)** y **Modelo B v2 (150M–15K)**. La búsqueda automática de checkpoints prioriza B v2 incluso antes del checkpoint configurado (`backend/app/services/model_inference_service.py:61`, `:130`).

La cabecera de `models/asistente_python_ia_v1.gguf` identifica **Qwen2.5-Coder 1.5B Instruct**, arquitectura qwen2. Los metadatos no permiten determinar si se adaptaron sus pesos posteriormente. El servicio fija ese archivo como candidato local (`backend/app/services/local_qwen_service.py:34`).

Seleccionar B/C puede ejecutar una inferencia corta cuyo texto se descarta y luego entregar la respuesta del GGUF (`backend/app/services/chat_service.py:402`, `:444`). Además, el prompt obliga a presentarse como modelo propio y ocultar Qwen (`backend/app/services/local_qwen_service.py:51`). Debe corregirse la atribución: aplicación y estrategia pedagógica propias, modelo base identificado y entrenamientos B/C documentados por separado.

La telemetría inicializa 220 tokens, 1,80 segundos y dispositivo CUDA sin medirlos, y los mezcla con resultados de otros motores (`backend/app/services/chat_service.py:399`, `:457`). El endpoint de pregunta al modelo también puede reemplazar su respuesta conservando metadatos anteriores (`backend/app/routes/ai_orchestrator.py:98`). Registrar siempre motor real, versión/checkpoint, proveedor, origen AST/RAG/LLM, tiempo y tokens medidos; usar «no disponible» cuando no exista medición.

El modo automático puede priorizar APIs externas (`backend/app/services/chat_service.py:377`). Por ello no garantiza operación offline ni costes constantes. Para el estudio, fijar motor y política de fallos; no cambiar silenciosamente a otro proveedor.

### Exactitud de las explicaciones — prioridad alta

Casos reproducidos llamando `analizar_codigo_python`:

| Entrada resumida | Resultado actual | Problema |
|---|---|---|
| `def doble(x): return x * 2`, seguido de `doble(4)` | Algoritmo recursivo | Una llamada a una función definida no implica recursión |
| `for i in range(3): print(i)` | O(n) | El límite es constante respecto al tamaño de entrada |
| Tres bucles anidados `range(n)` | O(n²) | En este ejemplo el número de iteraciones es cúbico |
| `[x * 2 for x in datos]` | Tiempo y espacio O(1) | Omite el recorrido y la lista resultante |
| `busqueda_binaria = 5; print(busqueda_binaria)` | Búsqueda binaria O(log n) | Se guía por el nombre, sin existir búsqueda |
| Primera línea `    x = 1`, segunda `print(x)` | Sintaxis válida | `strip()` elimina la indentación inicial inválida |

Evidencia: `backend/app/services/code_explainer_service.py:207`, `:220`, `:248`, `:278`. La actividad generada también selecciona una respuesta de crecimiento logarítmico para cualquier complejidad distinta de O(n), incluso O(1) (`:640`).

Recomendación: preservar el código original para verificar sintaxis; restringir reglas a casos comprobables; expresar incertidumbre cuando no se pueda inferir Big-O. Una explicación convincente pero incorrecta perjudica directamente la intervención educativa.

En Flutter, el explicador usa expresiones regulares sobre líneas completas. Su lógica puede considerar cadena sin cerrar `producto = 'Cuaderno' # str`, o falta de dos puntos un `for` con comentario después de `:`. Estas formas aparecen en el propio catálogo. Revisado estáticamente en `app-desktop/lib/services/explicador_automatico.dart:128`, `:344`, `:512`. Validar sintaxis mediante Python y distinguir sugerencias heurísticas de diagnósticos confirmados.

El contenido etiqueta `print`, `len` y `range` como palabras reservadas. Son nombres integrados; la clasificación debe contrastarse con `keyword.iskeyword`. [Documentación de palabras clave](https://docs.python.org/3/library/keyword.html), [nombres integrados](https://docs.python.org/3/library/functions.html). Revisar también indentación como convención de cuatro espacios y anotaciones de tipo sin enforcement automático.

### Evaluación y condiciones del estudio — prioridad alta

Se reprodujeron tres fallos en `backend/app/services/evaluation_service.py`:

- Opción «A» frente a correcta «B»: devuelve **1,0** porque la normalización elimina ambas letras (`:18`).
- Respuesta de código con un espacio frente a `print(1)`: devuelve **0,5** por coincidencia de subcadena vacía (`:73`).
- `print('ab')` frente a `print('a b')`: devuelve **1,0** al eliminar espacios también dentro de literales, aunque producen salidas distintas.

Las explicaciones libres reciben 0,5 provisional; el promedio del reporte no distingue esas pendientes de notas definitivas (`backend/app/services/evaluation_service.py:89`, `backend/app/routes/research.py`). Conviene guardar estado pendiente sin nota final y evaluar código por comportamiento con casos de prueba, complementado por rúbrica conceptual.

La condición con/sin acompañamiento/post-test se puede cambiar desde preferencias del estudiante. Las pistas y el explicador automático no quedan bloqueados de forma completa. Evidencia: `app-desktop/lib/widgets/settings/section_capacidades.dart:129`, `app-desktop/lib/providers.dart:48`, `app-desktop/lib/widgets/code_view.dart:2705`. Asignar participante, condición y fase desde el servidor con permisos docentes, cubriendo todas las vías de ayuda. El bloqueo actual del chat es una base, no un control experimental completo.

### Coherencia de la aplicación y preparación del piloto

- Las pistas se muestran juntas y varios retos cargan código ya resuelto. Separar ejemplo trabajado, práctica guiada y evaluación independiente (`app-desktop/lib/widgets/explicar_view.dart:645`, `app-desktop/lib/widgets/code_view.dart:623`).
- Code envía `modulo_1/2/3`, pero el backend espera `principiante/intermedio/avanzado`; Qwen cae en principiante y el prompt cloud puede perder la guía. Unificar identificadores (`app-desktop/lib/widgets/code_view.dart:781`, `backend/app/services/local_qwen_service.py:405`).
- Explicar fuerza `proveedor: auto`, ignorando la selección previa (`app-desktop/lib/widgets/explicar_view.dart:374`). Al cargar un archivo puede conservar la lección anterior. Vincular contexto al documento/intento.
- Escritorio y web no implementan la misma intervención: la web no expone este currículo ni envía condición experimental; su actividad es principalmente texto. Usar una interfaz consistente para el piloto y luego unificar catálogo y contratos.
- Antes de un despliegue compartido, aislar de verdad la ejecución: el subproceso con directorio temporal mantiene permisos del usuario y la lista de llamadas bloqueadas no es un aislamiento del sistema (`mcp_server/sandbox.py:40`, `:164`). Limitar recursos, filesystem y red desde el entorno de ejecución. No se ejecutaron pruebas destructivas.
- El registro público permite elegir investigador, aunque bloquea administrador; ese rol puede validar datasets. Restringir su concesión a personal autorizado (`backend/app/routes/auth.py:41`, `backend/app/routes/dataset.py:53`).

## 5. Cómo demostrar aprendizaje en esta tesis

Pregunta propuesta: **¿qué efecto tiene el andamiaje explicativo sobre la comprensión, depuración y resolución independiente de código Python, frente a la generación directa, en los estudiantes universitarios participantes?**

| Elemento | Diseño recomendado |
|---|---|
| Comparación principal | Mismo modelo, versión, tareas, recursos y tiempo; condición A generación directa y B andamiaje |
| Línea base | Pre-test objetivo sin IA; cuestionario de experiencia como información complementaria |
| Durante la intervención | Intentos, ayudas, errores, tiempo activo y pruebas aprobadas |
| Resultado principal | Post-test con problemas nuevos de dificultad equivalente y sin ayuda en ambas condiciones |
| Transferencia/retención | Tarea distinta que requiera el mismo concepto; evaluación posterior si el calendario lo permite |
| Percepción | Utilidad, claridad y satisfacción, reportadas separadamente del desempeño |
| Análisis | Comparar resultados considerando nivel inicial, variabilidad e incertidumbre; justificar tamaño muestral con el tutor |

Los documentos actuales mezclan control «sin sistema», comparación entre B/C y generación directa. Son preguntas diferentes. Para el objetivo expresado por el estudiante, definir la generación directa como comparación principal; evaluar B/C en un experimento técnico separado. No cambiar el modelo entre condiciones si se pretende atribuir el efecto al andamiaje.

Una rúbrica inicial de comprensión puede valorar de 0 a 2: predicción de salida, explicación de variables, justificación del flujo, identificación/corrección de un error y resolución de una variante. Total 0–10, pendiente de revisión docente y pilotaje. Puntuar casos funcionales por separado. La IA puede sugerir feedback, pero no debería ser el único juez de una medida principal aún no validada.

Registrar, como mínimo: participante seudónimo, condición, fase, versión del ejercicio, concepto, número de intento, código, respuesta conceptual, ayudas solicitadas/reveladas, resultados de pruebas, tiempos, motor real, configuración y versión de la rúbrica. Registrar exposición a soluciones. Obtener consentimiento y acordar acceso/retención de los datos del estudio.

## 6. Qué significa que «aprende»

- **El estudiante aprende:** mejora en tareas objetivas nuevas y puede resolver con menos ayuda. El historial de consultas o la satisfacción no bastan para demostrarlo.
- **El tutor se adapta:** usa evidencias del estudiante para elegir dificultad y ayuda. Puede lograrse con perfil persistente y reglas sin reentrenar el modelo.
- **El modelo se entrena:** cambian sus pesos mediante un proceso evaluado. Guardar conversaciones o añadir documentos a RAG no demuestra que el modelo neuronal haya aprendido.

El repositorio ya contiene modelos neuronales y experimentos propios: no necesita más botones para «ser IA». Si más adelante se busca mejorar el modelo, conviene partir de errores revisados por docentes, datos de entrenamiento separados de evaluación y una comparación de versiones. Durante el estudio, congelar versiones para mantener comparabilidad.

El benchmark existente usa 45 tokens y puntuación por palabras/marcadores (`scripts/benchmark_tesis_40_preguntas.py:70`, `:116`). B v2 y C figuran cerca de 9,4/100 en esa heurística: **no es un porcentaje de exactitud ni de aprendizaje**. Su limitación de longitud tampoco permite valorar explicaciones extensas. Las salidas y resultados son útiles como exploración, sin demostrar eficacia pedagógica ni superioridad de arquitectura.

## 7. Avance concreto para mañana y trabajo posterior

**Presentar mañana:** los 3 módulos y sus 11 lecciones; arquitectura real y procedencia de modelos; una lección revisada manualmente; el diseño de comparación y el plan de mejora. Identificar claramente qué está implementado y qué se propone.

**Secuencia de demostración propuesta, 6–8 minutos:** objetivo «comprender un acumulador» → predecir salida → escribir/completar suma de elementos → recibir una pista → ejecutar → explicar por qué se inicializa el acumulador fuera del bucle → resolver una variante (por ejemplo, contar valores que cumplen una condición) sin tutor. Registrar desempeño y ayudas. La variante también puede requerir otros conceptos: verificar prerrequisitos y equivalencia antes de usarla como instrumento.

**Primer bloque de implementación:** corregir identidad/telemetría y evaluación; fijar condiciones; unificar módulos; convertir una lección en ese recorrido completo con intentos persistidos. Criterio de aceptación: una sesión de prueba permite reconstruir qué hizo el alumno, qué ayuda recibió, qué motor respondió y cómo resolvió la tarea final.

**Segundo bloque:** ampliar el recorrido a las lecciones elegidas, añadir panel docente/exportación y pilotar rúbricas/tareas. Corregir contenidos a partir de los errores observados.

**Después:** ejecución visual, perfil adaptativo más elaborado, más contenidos y entrenamiento adicional solo si las evaluaciones lo justifican. Más proveedores, voz, visión, agentes o lenguajes pueden esperar: su aportación debe responder a una necesidad de aprendizaje comprobada.
