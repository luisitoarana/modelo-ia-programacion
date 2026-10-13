# Correcciones verificadas del explorador, editor y revisión docente

## Fallos reportados y causa

- **Explorador: HTTP 422 por más de 8.000 caracteres.** La API rechazaba el archivo antes de llegar al motor. Ahora acepta hasta 250.000 caracteres; MySQL utiliza MEDIUMTEXT para conservar mensajes largos. El tokenizador calcula por separado qué contenido cabe en el modelo y reserva espacio para la respuesta. Los análisis parciales se identifican como tales.
- **Editor: “Generando respuesta…” sin terminar y RangeError con posición -1.** Una lectura de selección ocurría fuera del try/finally. La selección sin foco ahora se trata como ausencia de selección y toda la preparación de la consulta está protegida.
- **Segunda petición: instrucciones del editor perdían su formato al añadir historial.** El historial ahora conserva una sección independiente para la petición actual; la corrección continúa usando las instrucciones del editor.
- **Correcciones que no se aplicaban.** Se reconocen “corregir”, “corrígelo” y confirmaciones como “sí”. El botón de problemas pide corregir el archivo. Las propuestas completas pasan validación de sintaxis Python antes de actualizar el editor. Se ofrece Deshacer y el usuario guarda con Ctrl+S. Se conserva la pestaña que originó la petición y se comprueba que no haya sido editada mientras se generaba la respuesta.
- **Fallos de GPU que iniciaban otra generación CPU sin límite.** Un fallo del servidor local produce una respuesta controlada. No carga un segundo motor CPU por un timeout del servidor GPU. La carga del servidor comprueba salud y evita lanzar procesos duplicados.
- **Crear archivo: controlador de texto liberado durante el cierre del diálogo.** Se espera que la ruta del diálogo termine antes de liberar su controlador. También se corrigió un desbordamiento del encabezado del asistente.
- **Intentos que no podían guardarse.** Se corrigieron dos IDs de lección mediante alias compatibles y se sincronizaron las once preguntas del catálogo desktop/backend.

## Revisión docente

El administrador tiene **Administración** en el menú lateral. Puede filtrar intentos por estudiante y fase, consultar identidad, pregunta, respuesta inicial, explicación propia y código inicial/final, y guardar una rúbrica manual. CSV y JSON exportan los registros cargados del filtro. Se pueden cargar páginas de intentos anteriores.

La pregunta exacta se guarda con cada intento nuevo. En registros anteriores, la interfaz señala que el enunciado viene del catálogo actual: no inventa la pregunta original. La ampliación de la base de desarrollo conserva las filas existentes.

## Validación

Resultado final: 22 pruebas de backend y 16 pruebas de Flutter aprobadas, compilación Windows debug correcta y backend reiniciado con las rutas actuales. El análisis de los archivos modificados no encontró errores de compilación; quedan sugerencias de estilo.

Se añadieron regresiones para selección -1, confirmación de cambios, continuidad del chat, recuperación de errores, cambio de pestaña durante generación, archivos largos, presupuesto de contexto, fallo del motor sin reintento y migración idempotente. La prueba HTTP conserva un archivo de más de 8.000 caracteres y la pregunta del estudiante. Las pruebas de UI verifican el acceso exclusivo de administrador y la evidencia disponible para revisión.

`scripts/validar_flujo_editor_local.py` consulta el GGUF local, sin APIs externas: genera `calcular(a, b)` con suma, luego cambia su cuerpo a resta con historial, y comprueba que un archivo largo reciba la marca de contexto parcial.

La base real comprobada es MySQL, con `mensajes.contenido` de tipo MEDIUMTEXT y `intentos_aprendizaje.pregunta` presente.

## Cómo ver los cambios

Cerrar la app de desarrollo y volver a abrir `iniciar_sistema.bat`. El ejecutable de `release` corresponde a una compilación anterior. En una sesión Flutter abierta desde ese script, R reinicia la app con el código actualizado.

El `ModuleNotFoundError: No module named 'flask'` de la captura significa que falta Flask en el intérprete que ejecuta el código generado. Es un problema del entorno del programa: validar sintaxis no instala dependencias ni demuestra que un servidor web funcione. El asistente recibe esa distinción en sus instrucciones y debe indicar requisitos cuando el usuario solicite un framework.
