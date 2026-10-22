# Validación del flujo de investigación — 22 de octubre de 2026

## Alcance de la entrega

Pretest e intervención/postest por estudiante en la aplicación Flutter y en la API, con instrumentos guardados, bloqueo de ayuda, revisión humana y exportación. El portal web conserva su interfaz previa: no ofrece todavía estas nuevas pantallas de instrumentos; para aplicar la evaluación se utiliza la aplicación de escritorio. El backend controla los accesos desde cualquier cliente.

## Comprobaciones realizadas

- **35 pruebas de backend aprobadas**: recorrido HTTP de ambos grupos, pre y post con seis preguntas, borrador, guardado, respuestas vacías, envío final, revisión por investigador, comparación 50/100 → 70/100 = +20 puntos porcentuales.
- **23 pruebas Flutter aprobadas**: incluye inicio del instrumento, código y explicación breve, confirmación de entrega, bloqueo de edición tras enviar, conservación del texto ante fallo de red y activación docente del pretest. También se conservan las pruebas anteriores de editor, administración y registro.
- **Compilación Windows debug aprobada**, sin generar instalador de distribución.
- Accesos del estudiante bloqueados a configuración/revisión docente; cuenta pública no puede convertirse en docente; no se puede usar el envío idempotente para recuperar la entrega de otra fase ni retroceder de post a pre sobre registros del estudio.
- Bloqueo de IA, historial, pistas, soluciones curriculares, ejecución y herramientas durante pre/post. La generación directa no puede acceder al explicador ni a las soluciones guiadas. En Estudio activo, un alumno sin asignación espera al docente antes de recibir ayuda.
- Las tareas iniciadas no cambian si después se seleccionan otras; el post utiliza los pares de su propio pretest. No se puede cambiar de condición después de iniciar la primera entrega.
- Las notas ausentes permanecen pendientes. Con pre = 0 no se calcula un cambio relativo por división entre cero.
- Las pruebas usan SQLite temporal o memoria y no introducen participantes ni calificaciones de prueba en la base del administrador.

## Pruebas reales del motor local

Se solicitó generación directa de variables, un condicional y una función. El código se analizó antes de ejecutarlo, rechazando importaciones y llamadas ajenas a los ejemplos; después se ejecutó en un subproceso con tiempo acotado. Resultados:

| Caso | Resultado observado |
|---|---|
| nombre Ana y edad 19 | Mostró Nombre: Ana y Edad: 19 |
| acceso con edad 18 | Mostró Acceso permitido |
| calcular_total(5, 3) | Mostró 15 |

Esto verifica tres casos sencillos, no la exactitud general del modelo. No se usaron APIs de pago.

En andamiaje se observó una pregunta genérica sobre entrada de datos en un programa sin input y una explicación imprecisa de tipos. Se reforzaron instrucciones y se añadió una pregunta derivada del AST del código: utiliza sus variables, funciones, condiciones o bucles reales. Las observaciones sobre literales distinguen texto e int mediante el parser. La fuente de la pregunta queda registrada como ast_del_codigo cuando se aplica.

La explicación libre del modelo todavía puede equivocarse. El componente de AST comprueba hechos puntuales y contextualiza la pregunta; no demuestra que todo el texto generado sea correcto. La generación directa se limpia mediante AST para no incluir explicaciones, comentarios o docstrings pedagógicos. Un resultado con error sintáctico se comunica como fallo de generación, sin fingir una solución correcta.

## Reproducción

Desde backend, con dependencias instaladas:

```powershell
$env:DATABASE_URL='sqlite+aiosqlite:///:memory:'
.\.venv\Scripts\python.exe -m pytest -q
Remove-Item Env:DATABASE_URL
```

Desde app-desktop: `flutter test` y `flutter build windows --debug`. Las pruebas de flujo experimental están en backend/tests/test_estudio_flujo.py. El banco y la rúbrica se documentan en [protocolo](../research/PROTOCOLO_PRE_POST_ANDAMIAJE.md).

## Límites y siguientes pasos

### Correcciones de generación directa y práctica común

Nueva comprobación: **42 pruebas backend y 26 pruebas Flutter aprobadas**. Se añadió una prueba de interfaz que elige una tarea en modo Solo código, genera un archivo y aplica dos correcciones consecutivas con el mismo identificador de conversación. Las pruebas HTTP comprueban que las tareas corresponden a las competencias del pretest y se bloquean durante pre/post; no incluyen soluciones ni pistas para el grupo directo.

Se corrigió la clasificación de «genera la corrección» y «no funciona», que podía perder el contexto o impedir aplicar una corrección. La generación directa comprueba una única solución Python y algunos nombres importados de bibliotecas básicas, con un solo intento de reparación y sin ejecutar el programa del alumno en ese proceso de validación.

Prueba real con el motor local, ejecutando las propuestas en el sandbox: una función promedio fallaba por división entre cero con una lista vacía. La corrección debía conservar la función, devolver 0 para `[]` y 3 para `[2, 4]`; en el siguiente turno debía mantener ese comportamiento y devolver 1.67 para `[1, 2, 2]`. Ambas correcciones finales pasaron sus aserciones y la respuesta contenía solo código. En la comprobación inicial se detectó una importación inexistente (`round` desde `math`), cubierta ahora por una regresión y por el intento de reparación.

La prueba real del explicador también detectó una modificación no solicitada: el modelo reemplazaba una edad fija por una entrada de teclado. Se añadió un respaldo estructural que conserva el código original si se pidió únicamente explicar y lo identifica en pantalla. La nueva prueba confirmó que edad=20 se describe como entero, conserva los literales originales y formula una pregunta sobre una variable real. Las predicciones y razonamientos del estudiante se incluyen en la petición de explicación; no se califican automáticamente. Estos resultados documentan los casos comprobados, no garantizan respuestas correctas para cualquier código ni equivalen a evidencia de aprendizaje.

### Corrección de acceso docente y demostración aislada

Se corrigió el selector que permitía persistir el bloqueo Post-Test en una cuenta administradora. El escritorio mantiene disponibles los controles docentes y permite abrir vistas previas de pretest y postest desde Administración o desde el selector superior. Las vistas previas funcionan con las evaluaciones cerradas, permiten escribir y simular la entrega, y no crean registros de participantes ni alteran resultados. La API de vista previa exige rol administrador/investigador; la entrega real continúa reservada a estudiantes.

Comprobaciones posteriores a esta corrección: **37 pruebas backend y 25 pruebas Flutter aprobadas**. Se comprobó por HTTP contra el backend local que la cuenta administradora privada sigue activa, que su contraseña configurada coincide y que ambas vistas previas devuelven seis preguntas. No se imprimieron ni publicaron sus credenciales.

El nuevo `backend/scripts/iniciar_demo_admin.py` prepara un administrador público únicamente en una base SQLite separada, con clave JWT propia, sin heredar el `.env` ni claves de proveedores. El servidor demo escucha en localhost:8766. Se verificaron el inicio de sesión y la vista previa con esa cuenta (HTTP 200), así como el rechazo del administrador público en el servidor privado, de la cuenta privada en la demo y del token demo en el servidor privado (HTTP 401). El servidor demo utilizado en estas comprobaciones se detuvo al terminar; los datos de demostración quedan en un directorio excluido de Git.

Las pruebas del software no validan el instrumento ni demuestran aprendizaje. Se necesita aprobación docente de las seis parejas de consignas, tiempos, rúbrica y procedimiento; pilotaje y revisión de dificultad; acuerdo entre evaluadores; y decidir cómo tratar incidencias del modelo antes del ensayo real. El banco mide transferencia cercana de un subconjunto de temas, no dominio general de Python.

La revisión ciega es una opción de presentación/exportación, no anonimización frente a personal autorizado. Se guarda la última revisión por pregunta y su autor/fecha, sin historial inmutable de todos los cambios de nota. Hay avisos de deprecación Python y de estilo Flutter previos; no se declara que todo el análisis estático esté limpio.

Los nuevos formularios no ofrecen ejecución durante la evaluación, en coherencia con un pre y post sin retroalimentación de resultados. Si el profesor decide permitir ejecución, deberá definirse igual en ambos y validarse otra configuración antes de aplicarla.

La aplicación renueva la asignación cada diez segundos; el servidor comprueba la fase en cada solicitud protegida. Las respuestas se guardan manualmente y mediante autoguardado con acuse del servidor. Un fallo de conexión no confirma la entrega y no autoriza cerrar la pantalla con cambios pendientes.

No se han configurado DNS, túneles, HTTPS ni acceso universitario externo. La validación Docker completa de la infraestructura anterior se documenta por separado; esta entrega valida el nuevo flujo con SQLite y pruebas HTTP, sin repetir una evaluación completa de PostgreSQL/MySQL. La migración nueva solo crea tablas y requiere respaldo previo en un despliegue real.
