# Manejo de excepciones

## try / except / else / finally

```
try:
    valor = int(entrada)
except ValueError as exc:
    print(f"Entrada inválida: {exc}")
else:
    print("Conversión exitosa")
finally:
    print("Cierro recursos siempre")
```

## Jerarquía clave

`BaseException` → `Exception` → ( `ValueError`, `TypeError`, `KeyError`, `IndexError`, `OSError`, ... )

- Atrapa `Exception`, no `BaseException` (este último incluye `KeyboardInterrupt`, `SystemExit`).
- Atrapa la excepción más específica posible.

## Raise y excepciones propias

```
class NotaInvalida(ValueError):
    pass

if nota < 0 or nota > 20:
    raise NotaInvalida(f"Nota fuera de rango: {nota}")
```

## Anti-patrones

- `except:` sin tipo: oculta errores graves.
- `except Exception: pass`: borra evidencia. Loguea siempre.
- Catch wide en código de bajo nivel.
