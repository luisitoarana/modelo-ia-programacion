# Bucles

## `for`

Itera sobre cualquier iterable:

```
for nota in notas:
    print(nota)

for i in range(5):       # 0..4
    print(i)

for i, valor in enumerate(notas, start=1):
    print(f"{i}: {valor}")
```

## `while`

Itera mientras la condición sea verdadera:

```
n = 0
while n < 5:
    n += 1
```

## Control

- `break`: rompe el bucle más interno.
- `continue`: salta a la siguiente iteración.
- `else` en bucles: se ejecuta si el bucle terminó sin `break`.

## Patrón: acumular promedio

```
suma = 0
for nota in notas:
    suma += nota
promedio = suma / len(notas)
```

Pedagógicamente: el bucle expone la diferencia entre **iteración** y
**acumulación**, dos conceptos algorítmicos clave.
