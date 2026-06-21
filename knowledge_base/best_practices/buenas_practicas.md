# Buenas prácticas de programación en Python

## Nombres

- Usa `snake_case` para funciones y variables, `PascalCase` para clases.
- Los nombres deben revelar intención: `calcular_promedio_notas`, no `f1`.
- Evita abreviaturas crípticas.

## Funciones pequeñas

Una función debería hacer una sola cosa y caber en una pantalla.
Si pasa de 30 líneas, normalmente puede dividirse.

## Comentarios

- Explica **por qué**, no **qué**.
- Si el código no es obvio, refactoriza antes de comentar.

## Validación de entrada

- Valida en los bordes (entrada de usuario, APIs externas).
- Confía en el código interno con tipado.

## Manejo de errores

- Usa excepciones específicas.
- No silencies errores sin loguear.
- Usa `with` para recursos.

## Tipado

- Usa anotaciones: facilita lectura y permite mypy/pyright.
- `Optional`, `Union`, `Literal`, `TypedDict` cuando aporta claridad.

## PEP 8

- 4 espacios de indentación, no tabs.
- 79–100 caracteres por línea.
- Imports al inicio, agrupados (stdlib, terceros, propios).

## Tests

- Cada función pública merece test.
- Nombres expresivos: `test_promedio_con_lista_vacia_lanza_excepcion`.
