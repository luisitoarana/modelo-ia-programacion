# Variables en Python

Una variable es un nombre simbólico que apunta a un objeto en memoria. En Python las variables NO declaran tipo: el tipo lo lleva el objeto.

## Sintaxis

```
nombre = "Ana"
edad = 21
promedio = 14.5
es_activa = True
```

## Reglas de nombres

- Solo letras, dígitos y guion bajo `_`.
- No pueden empezar con dígito.
- No pueden coincidir con palabras reservadas (`if`, `for`, `class`, etc.).
- Convención: `snake_case` para variables y funciones.

## Tipado dinámico vs. anotaciones

```
edad: int = 21          # anotación (opcional, no impone tipo en runtime)
edad = "veintiuno"      # válido en Python, pero rompe la intención
```

Las anotaciones son útiles para herramientas como mypy y para legibilidad.

## Por qué importa pedagógicamente

Entender variables = entender el concepto de **referencia**: un nombre puede
re-apuntar a otro objeto en cualquier momento. Esto sustenta más adelante la
discusión de mutabilidad, alias y paso de argumentos.
