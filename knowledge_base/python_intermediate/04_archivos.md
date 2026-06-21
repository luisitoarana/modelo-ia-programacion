# Lectura y escritura de archivos

## Patrón básico

```
with open("notas.txt", "r", encoding="utf-8") as f:
    contenido = f.read()
```

`with` garantiza el cierre automático aun si hay excepción.

## Modos

| Modo | Significado |
|------|-------------|
| `r` | Lectura (default) |
| `w` | Escritura (sobrescribe) |
| `a` | Append |
| `x` | Crear exclusivo |
| `b` | Binario (combinar) |

## Iteración línea a línea

```
with open("notas.txt", encoding="utf-8") as f:
    for linea in f:
        print(linea.rstrip())
```

Esto es O(n) en tiempo y O(1) en memoria, ideal para archivos grandes.

## JSON

```
import json
with open("estudiantes.json", encoding="utf-8") as f:
    datos = json.load(f)
```
