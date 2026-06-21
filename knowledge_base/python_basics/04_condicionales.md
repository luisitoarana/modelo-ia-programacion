# Condicionales

```
if nota >= 11:
    print("Aprobado")
elif nota >= 7:
    print("En recuperación")
else:
    print("Desaprobado")
```

- `elif` evita anidamiento profundo.
- La condición debe evaluar a `bool` (Python aplica truthiness implícita: `0`, `""`, `[]`, `None` son falsy).
- Evita comparar contra `True`/`False` directamente; usa la propia expresión.

## Operador ternario

```
estado = "aprobado" if nota >= 11 else "desaprobado"
```

## Pattern matching (3.10+)

```
match comando:
    case "inicio": iniciar()
    case "salir": cerrar()
    case _: ayuda()
```
