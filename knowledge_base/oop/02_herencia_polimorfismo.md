# Herencia y polimorfismo

## Herencia simple

```
class Persona:
    def __init__(self, nombre: str):
        self.nombre = nombre

    def saludar(self) -> str:
        return f"Hola, soy {self.nombre}"


class Estudiante(Persona):
    def __init__(self, nombre: str, carrera: str):
        super().__init__(nombre)
        self.carrera = carrera

    def saludar(self) -> str:
        return f"Soy {self.nombre} y estudio {self.carrera}"
```

`super()` delega al constructor (o método) del padre.

## Polimorfismo

```
def saludar_a_todos(personas: list[Persona]) -> None:
    for p in personas:
        print(p.saludar())
```

La función no necesita saber el tipo concreto; cada subclase responde a su modo
al mismo mensaje (`saludar()`).

## Encapsulamiento

- `_atributo`: convención privada (no impone restricción).
- `__atributo`: name mangling (`_Clase__atributo`).

## Composición vs. herencia

Prefiere **composición** ("tener un") sobre **herencia** ("ser un") cuando la
relación no es claramente "es-un". La herencia profunda complica el mantenimiento.
