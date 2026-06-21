# Ordenamiento burbuja

```
def burbuja(lista):
    n = len(lista)
    for i in range(n):
        intercambio = False
        for j in range(0, n - i - 1):
            if lista[j] > lista[j + 1]:
                lista[j], lista[j + 1] = lista[j + 1], lista[j]
                intercambio = True
        if not intercambio:
            break
    return lista
```

## Complejidad

- Tiempo: peor O(n²), mejor O(n) con la guarda de `intercambio`.
- Espacio: O(1) (in-place).
- Estable: sí.

Pedagógicamente, es el algoritmo canónico para introducir:
- Bucles anidados.
- Invariantes de bucle.
- Cómo identificar y demostrar mejoras (early-exit).

No es competitivo en práctica frente a `sorted` (Timsort, O(n log n)), pero
es excelente para entender qué significa "ordenar" mecánicamente.
