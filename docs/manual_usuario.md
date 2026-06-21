# Manual de usuario (estudiante)

## 1. Crear cuenta

1. Abre `http://localhost:3000`.
2. Clic en **Crear cuenta**.
3. Completa nombre, correo, contraseña (mínimo 8) e institución.
4. Inicio de sesión automático.

## 2. Generar una explicación

En la pantalla principal:

1. Escribe tu solicitud. Ejemplos:
 - "Explícame qué es una función en Python."
 - "Genera un programa que calcule el promedio de notas y explícame cómo funciona."
 - "Crea un ejemplo de clase padre e hija."
2. Selecciona nivel (básico / intermedio / avanzado).
3. Elige proveedor (`automático` por defecto).
4. Clic en **Generar y explicar**.

Recibirás:
- Código Python limpio.
- Explicación general.
- Explicación línea por línea con impacto en memoria.
- Conceptos clave.
- Análisis de complejidad (cuando aplica).
- Actividad evaluativa de comprensión.

## 3. Responder actividades evaluativas

La actividad aparece en el panel derecho de la respuesta. Puedes:

- Resolverla y enviarla vía la API (`POST /evaluation/responder`).
- En próximas versiones del frontend, contestar directamente desde la UI.

## 4. Historial

La pestaña **Historial** lista todas tus consultas con métricas:
modelo usado, estado, tokens y latencia.

## 5. Base de conocimiento

La pestaña **Conocimiento** muestra los temas curados de Python.
Útil para repasar conceptos antes de pedir un ejercicio.
