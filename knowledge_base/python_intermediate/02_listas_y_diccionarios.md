# Listas y diccionarios

## Listas

```
notas = [13, 14, 17, 9]
notas.append(11)
notas[0] = 12
ordenadas = sorted(notas)
mayores = [n for n in notas if n >= 11]
```

- Mutables, ordenadas, permiten duplicados.
- Acceso O(1), inserción al final O(1) amortizado.
- `list.sort()` muta; `sorted()` devuelve copia.

## Diccionarios

```
estudiante = {"nombre": "Ana", "edad": 21}
estudiante["promedio"] = 14.2
nombre = estudiante.get("nombre", "Sin nombre")

for clave, valor in estudiante.items():
    print(clave, valor)
```

- Mapeo clave→valor. Claves deben ser hashables.
- Acceso, inserción y borrado promedio O(1).

## Comprehensions

```
cuadrados = [x**2 for x in range(10)]
indice = {v: i for i, v in enumerate(notas)}
unicos = {n for n in notas}
```

Son más expresivas y suelen ser más rápidas que un `for` equivalente.
