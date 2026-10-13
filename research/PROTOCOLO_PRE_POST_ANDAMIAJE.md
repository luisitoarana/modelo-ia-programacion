# Protocolo piloto para medir el andamiaje explicativo

Versión 0.1, 2 de octubre de 2026. Instrumento de trabajo para revisión del docente y pilotaje; sus tareas y rúbrica todavía no están validadas. La práctica guiada de la aplicación registra intentos, pero **no asigna una nota automática**. Este protocolo distingue esas trazas del pre-test y post-test independientes.

## Pregunta y condiciones

Pregunta principal: ¿cambia la comprensión y la capacidad de resolver problemas nuevos de Python cuando el estudiante recibe andamiaje explicativo, frente a recibir generación directa?

- Condición A: mismo motor y tiempo de uso, con generación directa de código.
- Condición B: mismo motor y tiempo de uso, con predicción previa, intento, pistas solicitadas una a una y explicación propia.
- Fijar antes de cada sesión el GGUF/checkpoint real, versión, parámetros, material, tareas, interfaz y política de red. Registrar proveedor real por respuesta. El selector `auto` no sirve para esta comparación porque puede variar de proveedor.
- Asignar condición y fase desde el servidor/docente antes de cada sesión. `PUT /api/v1/aprendizaje/asignaciones/{usuario_id}` requiere rol investigador o administrador. La aplicación consulta `GET /api/v1/aprendizaje/asignacion`; el servidor prevalece sobre el modo enviado por el cliente para chat e intentos. La vista Explicar se oculta para la condición directa y durante pre/post; el chat queda bloqueado en pre/post. **Aún falta bloquear de forma integral las otras rutas y materiales de ayuda**; por tanto, usar este mecanismo para pilotaje supervisado, no para una prueba autónoma de alta integridad.

## Secuencia sugerida

1. Informar propósito, tratamiento de datos y consentimiento. Asignar un identificador seudónimo.
2. Pre-test individual sin IA ni ejecución de código: 20–25 minutos. Una mitad recibe forma A y otra B dentro de cada condición.
3. Intervención con tareas comunes: 30–45 minutos. Registrar intentos, ayuda solicitada, errores, código y tiempo. El docente solo resuelve incidencias técnicas.
4. Post-test individual sin IA ni ejecución: 20–25 minutos, con la otra forma. Si es viable, repetir una tarea nueva una semana después para explorar retención.
5. Dos evaluadores puntúan las respuestas sin ver condición ni identidad. Resolver discrepancias con la rúbrica antes del análisis. Reportar también si el post-test contiene tareas sin resolver.

Las formas A/B siguientes son borradores paralelos. Los números cambian y la estructura cognitiva se mantiene parecida; deben pilotarse para comprobar dificultad comparable. Evitar que las respuestas correctas se muestren al estudiante durante la medición.

## Formas paralelas (cinco tareas, 0–10 puntos)

| Tarea | Forma A | Forma B | Qué mide |
|---|---|---|---|
| 1. Variables | `x = 3; x = x + 2; print(x)` en líneas separadas: predice salida y explica el cambio de `x`. | `x = 4; x = x + 3; print(x)`: misma consigna. | Estado de variable y secuencia |
| 2. Condicional | `nota = 7; if nota >= 7: print('aprueba'); else: print('recupera')`, con indentación Python: predice y justifica la rama. | `edad = 18; if edad >= 18: print('mayor'); else: print('menor')`: misma consigna. | Condición y rama ejecutada |
| 3. Bucle | `total = 0; for n in [2, 3, 4]: total += n; print(total)`: predice y explica el valor final. | `total = 0; for n in [1, 4, 5]: total += n; print(total)`: misma consigna. | Iteración y acumulador |
| 4. Depuración | `def promedio(v): return sum(v) / len(v); print(promedio([]))`: identifica el fallo y escribe una corrección segura para lista vacía. | Igual patrón con `def media(numeros)` y `print(media([]))`. | Error, caso límite y reparación |
| 5. Producción | Escribe `contar_pares(numeros)` para devolver cuántos elementos son pares; considera `[]`. | Escribe `contar_positivos(numeros)` para devolver cuántos son mayores que cero; considera `[]`. | Función, bucle, condición y caso límite |

Las versiones impresas para participantes deben poner cada instrucción en líneas reales, con indentación correcta. La tabla usa punto y coma solo para compactar el protocolo.

## Clave y rúbrica docente

Cada tarea vale 0–2. Tareas 1–3: 1 punto por resultado correcto y 1 por explicar correctamente el estado, la rama o las iteraciones. Tarea 4: 1 por identificar `ZeroDivisionError` causado por `len([]) == 0`, 1 por una prevención válida y coherente (por ejemplo devolver `None` o lanzar una excepción documentada). Tarea 5: 1 por resolver entradas normales y 1 por resolver también lista vacía y entradas mixtas. Se aceptan soluciones Python equivalentes; no exigir una redacción o estilo únicos.

Clave A: tarea 1 imprime `5`; tarea 2 imprime `aprueba`; tarea 3 imprime `9`. Clave B: `7`, `mayor`, `10`. En tarea 4 el fallo ocurre al dividir por cero; en tarea 5 se cuentan elementos según el predicado y `[]` devuelve `0`.

No pedir al mismo modelo que asigne la nota principal. Puede dar sugerencias formativas durante la intervención; el puntaje del pre/post procede de rúbrica y revisión ciega. Para código generado, ejecutar casos de prueba deterministas como apoyo al evaluador, sin sustituir la revisión conceptual.

## Análisis y evidencia

Resultado principal por participante: diferencia `post − pre` en 0–10, comparada entre condiciones. Reportar también puntajes iniciales, distribución, valores faltantes y ejemplos de errores conceptuales, sin reducirlo a satisfacción. La muestra prevista en `research/plan_pruebas.md` (20 estudiantes) sirve como piloto exploratorio; interpretar intervalos y variabilidad antes de afirmar un efecto generalizable.

Durante la intervención, `POST /api/v1/aprendizaje/intentos` guarda usuario autenticado, lección, condición y fase efectiva si existe asignación docente, código inicial/final, predicción, explicación propia, número de pistas y duración. `GET /api/v1/aprendizaje/intentos` devuelve los intentos del usuario; `GET /api/v1/aprendizaje/investigacion/intentos` permite al investigador revisar hasta 1000 intentos con filtros de participante y fase. Estos registros permiten revisar el proceso, pero no prueban por sí solos aprendizaje ni sustituyen el post-test. **Duración, pistas y código llegan del cliente** y aún requieren verificación externa si se usan como variables formales. En entorno de desarrollo las nuevas tablas se crean al iniciar; un despliegue de producción necesita migración de base de datos.
