# Tipos de datos en Python

## Tipos primitivos

| Tipo | Ejemplo | Mutable |
|------|---------|---------|
| `int` | `42` | No |
| `float` | `3.14` | No |
| `bool` | `True`, `False` | No |
| `str` | `"hola"` | No |
| `NoneType` | `None` | No |

## Tipos compuestos

| Tipo | Ejemplo | Mutable | Ordenado |
|------|---------|---------|----------|
| `list` | `[1, 2, 3]` | Sí | Sí |
| `tuple` | `(1, 2)` | No | Sí |
| `dict` | `{"a": 1}` | Sí | Sí (3.7+) |
| `set` | `{1, 2}` | Sí | No |

## Conversión (casting)

```
n = int("42")
x = float("3.14")
s = str(99)
b = bool(0)   # False
```

## Por qué importa

Conocer el tipo permite predecir las operaciones legales, anticipar errores
(`TypeError`) y razonar sobre eficiencia (p. ej. listas vs. tuplas).
