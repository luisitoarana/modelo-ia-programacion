# Funciones

## Definición

```
def saludar(nombre: str) -> str:
    return f"Hola, {nombre}"
```

- Las anotaciones son opcionales pero recomendadas.
- `return` sin valor devuelve `None`.

## Parámetros

```
def configurar(host: str, puerto: int = 8000, *, debug: bool = False):
    ...
```

- Posicionales.
- Por defecto (deben ir al final).
- Solo por nombre después de `*`.
- Solo posicionales antes de `/` (3.8+).

## *args y **kwargs

```
def loguear(*args, **kwargs):
    print(args, kwargs)
```

## Funciones como objetos

Las funciones son ciudadanos de primera clase: se pueden pasar como argumento,
devolver y asignar a variables.

## Funciones puras

Una función pura:
1. No depende de estado externo.
2. No produce efectos secundarios.
3. Dado el mismo input, devuelve el mismo output.

Las funciones puras son más fáciles de testear y razonar.
