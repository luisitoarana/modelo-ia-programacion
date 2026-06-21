# Recursividad

Una función recursiva se define en términos de sí misma. Requiere:

1. **Caso base**: condición que detiene la recursión.
2. **Caso recursivo**: avanza hacia el caso base.

## Ejemplo: factorial

```
def factorial(n: int) -> int:
    if n < 0:
        raise ValueError("n debe ser no negativo")
    if n <= 1:
        return 1
    return n * factorial(n - 1)
```

## Pila de llamadas

Cada llamada apila un frame. Python limita la profundidad (`sys.setrecursionlimit`)
para evitar `RecursionError`.

## Recursividad vs. iteración

- Recursividad: clarifica problemas con estructura recursiva (árboles, divide-y-vencerás).
- Iteración: más eficiente en memoria, evita stack overflow.

## Memoización

```
from functools import lru_cache

@lru_cache(maxsize=None)
def fib(n):
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)
```

Convierte un algoritmo exponencial O(2^n) en lineal O(n) almacenando resultados.
