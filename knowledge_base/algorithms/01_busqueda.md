# Búsqueda

## Lineal — O(n)

```
def buscar_lineal(items, objetivo):
    for i, x in enumerate(items):
        if x == objetivo:
            return i
    return -1
```

Funciona en cualquier lista. Comparaciones esperadas: n/2.

## Binaria — O(log n)

Requiere la lista **ordenada**.

```
def buscar_binaria(items, objetivo):
    izq, der = 0, len(items) - 1
    while izq <= der:
        mid = (izq + der) // 2
        if items[mid] == objetivo:
            return mid
        if items[mid] < objetivo:
            izq = mid + 1
        else:
            der = mid - 1
    return -1
```

Pedagógicamente, comparar lineal vs. binaria es ideal para introducir el concepto
de **complejidad temporal**: la binaria divide el problema a la mitad cada paso.
