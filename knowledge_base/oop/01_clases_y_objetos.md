# Clases y objetos

## Definición mínima

```
class Estudiante:
    def __init__(self, nombre: str, edad: int) -> None:
        self.nombre = nombre
        self.edad = edad

    def presentarse(self) -> str:
        return f"Soy {self.nombre} y tengo {self.edad} años"

ana = Estudiante("Ana", 21)
print(ana.presentarse())
```

## Conceptos clave

- **Clase**: plantilla.
- **Objeto / instancia**: realización concreta en memoria.
- **Atributo**: dato del objeto.
- **Método**: función que opera sobre `self`.
- **Constructor**: `__init__`, se ejecuta al crear la instancia.

## Atributos de clase vs. de instancia

```
class Curso:
    universidad = "UNS"          # atributo de clase

    def __init__(self, nombre):
        self.nombre = nombre     # atributo de instancia
```

Pedagógicamente, OOP introduce la separación entre **estado** y **comportamiento**,
fundamental para entender más adelante encapsulamiento y diseño modular.
