# Operadores

## Aritméticos

`+  -  *  /  //  %  **`

`/` siempre devuelve `float`. `//` es división entera.

## Comparación

`==  !=  <  <=  >  >=`

Devuelven `bool`.

## Lógicos

`and  or  not`

Con cortocircuito: `or` no evalúa el segundo operando si el primero es verdadero.

## Asignación combinada

`+=  -=  *=  /=  //=  %=  **=  &=  |=  ^=`

## Identidad y pertenencia

- `is`, `is not`: comparan identidad de objeto (misma posición en memoria).
- `in`, `not in`: pertenencia en secuencias / colecciones.

## Precedencia (resumen)

`**` > `unario` > `* / // %` > `+ -` > comparaciones > `not` > `and` > `or`.

Usa paréntesis para legibilidad antes que memorizar precedencia.
