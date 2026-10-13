# Reporte de Validacion de Modelos LLM Propios

**Fecha:** 2026-09-15 08:04:44
**Acelerador:** NVIDIA CUDA (NVIDIA GeForce RTX 2050)

## 1. Resumen de Modelos Validados en GPU

| Modelo | Parametros | Pasos | Carga | VRAM (MB) | Vel (tok/s) | Estado |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Smoke Test (30M)** | **30.75M** | 1,000 | 0.75s | 120.4 MB | **52.3 tok/s** | Operativo |
| **Modelo A (88M)** | **87.8M** | 5,000 | 1.54s | 343.8 MB | **54.6 tok/s** | Operativo |
| **Modelo B (150M - 5k)** | **150.73M** | 5,000 | 3.22s | 583.3 MB | **38.0 tok/s** | Operativo |
| **Modelo B v2 (150M - 15k)** | **150.73M** | 15,000 | 2.48s | 583.3 MB | **41.5 tok/s** | Operativo |
| **Modelo C (350M - 5k)** | **350.93M** | 860 | 8.32s | 1347.3 MB | **2.1 tok/s** | Operativo |
| **Modelo C (350M - Final)** | **350.93M** | 18,618 | 8.71s | 1347.1 MB | **2.0 tok/s** | Operativo |

## 2. Pruebas de Inferencia Didactica

### Smoke Test (30M) (30.75M parametros)
- **Memoria ocupada en GPU:** 120.4 MB
- **Tiempo de carga en VRAM:** 0.75 segundos

#### Explicacion de Codigo Simple
- **Velocidad:** 52.3 tokens/s (Latencia: 0.765s)
```python
Here is a simple Python program that converts the given list to a list of numbers from a given string and checks if the input is a given string.

```python
def is_prime
```

#### Concepto de Programacion
- **Velocidad:** 77.8 tokens/s (Latencia: 0.514s)
```python
SELECT *
FROM table
WHERE (
 c2 = 1

# Calculate the first two integers in the list
y = (y * n) * (y + 1)
```

---

### Modelo A (88M) (87.8M parametros)
- **Memoria ocupada en GPU:** 343.8 MB
- **Tiempo de carga en VRAM:** 1.54 segundos

#### Explicacion de Codigo Simple
- **Velocidad:** 54.6 tokens/s (Latencia: 0.733s)
```python
5position = c pandsl
oup tedrint
()
me 1ientmeemessage sp
meResientme[atenher oñ enhancements`
 loc
```

#### Concepto de Programacion
- **Velocidad:** 55.9 tokens/s (Latencia: 0.716s)
```python
j* list*N place celxf=b Outputction expel)(l3uffc celxf=b Outputction build sh aab'-<cwordlections
```

---

### Modelo B (150M - 5k) (150.73M parametros)
- **Memoria ocupada en GPU:** 583.3 MB
- **Tiempo de carga en VRAM:** 3.22 segundos

#### Explicacion de Codigo Simple
- **Velocidad:** 38.0 tokens/s (Latencia: 1.054s)
```python
In Python, you can use list comprehension, which is a built-in function to solve this problem. Here's how you can use it:

```python
def perm_and
```

#### Concepto de Programacion
- **Velocidad:** 42.0 tokens/s (Latencia: 0.953s)
```python
In Python, the 'a' library can be used to define a list of numbers or values. Here is a Python script that uses the 'a' library to create a list of numbers and their
```

---

### Modelo B v2 (150M - 15k) (150.73M parametros)
- **Memoria ocupada en GPU:** 583.3 MB
- **Tiempo de carga en VRAM:** 2.48 segundos

#### Explicacion de Codigo Simple
- **Velocidad:** 41.5 tokens/s (Latencia: 0.963s)
```python
def es_par(numero):
 return numero % 2 == 0
```

#### Concepto de Programacion
- **Velocidad:** 44.5 tokens/s (Latencia: 0.898s)
```python
La forma es una lista y una tupla en Python es C# ya nota. La tupad es más a más que p
```

---

### Modelo C (350M - 5k) (350.93M parametros)
- **Memoria ocupada en GPU:** 1347.3 MB
- **Tiempo de carga en VRAM:** 8.32 segundos

#### Explicacion de Codigo Simple
- **Velocidad:** 2.1 tokens/s (Latencia: 18.713s)
```python
El nueadón del afractón
print("The number: "iso Pisa una es la lás de "fát
```

#### Concepto de Programacion
- **Velocidad:** 2.5 tokens/s (Latencia: 16.076s)
```python
El desdudático de el las una de la use de los para en la la de el de la ván.<|end|
```

---

### Modelo C (350M - Final) (350.93M parametros)
- **Memoria ocupada en GPU:** 1347.1 MB
- **Tiempo de carga en VRAM:** 8.71 segundos

#### Explicacion de Codigo Simple
- **Velocidad:** 2.0 tokens/s (Latencia: 19.835s)
```python
Here is the Python program that uses recursion to iterate through the given range and for loops through the range and for loops through the range.

```python
def es_par(
```

#### Concepto de Programacion
- **Velocidad:** 2.0 tokens/s (Latencia: 20.108s)
```python
La diferencia entre una lista y una tupla en Python es una lista de tupla. Las tupla de tupla es
```

---
