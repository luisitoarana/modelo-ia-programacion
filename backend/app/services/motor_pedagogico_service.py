"""Servicio de inferencia del modelo local de IA (Asistente Python IA v1).

Motor local integrado en el backend (100% offline, sin APIs externas)
diseñado para satisfacer las dos condiciones del estudio cuasiexperimental de tesis:

1. Condición 'con_acompanamiento' (Grupo Experimental):
   Andamiaje pedagógico completo (propósito, código funcional, desglose paso a paso,
   variables clave, estructuras de control, Big-O, riesgos y autoevaluación).

2. Condición 'sin_acompanamiento' (Grupo Control):
   Generación directa de código Python funcional sin explicaciones pedagógicas.

3. Modos especializados del explicador de código:
   - didactico
   - complejidad
   - bugs
   - optimizacion
"""

from __future__ import annotations

import sys
import re
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Literal

from app.utils.logger import obtener_logger

log = obtener_logger(__name__)

_RAIZ = Path(__file__).resolve().parents[3]
_MODEL_PATH = _RAIZ / "models" / "asistente_python_ia_v1.gguf"

_lock = threading.Lock()
_llm = None
_intentado = False
_GPU_LOCK = threading.Lock()
_SERVER_LOCK = threading.Lock()
_CONTEXTO_TOKENS = 4096


class MotorLocalError(RuntimeError):
    """Fallo finito del motor; nunca dispara otra inferencia CPU por sorpresa."""


@dataclass(slots=True)
class ResultadoMotorLocal:
    texto: str
    codigo: str | None
    tokens_generados: int
    latencia_segundos: float
    tokens_por_segundo: float
    modelo: str = "Motor Neuronal Pedagógico Local (Offline)"
    contexto_recortado: bool = False
    respuesta_incompleta: bool = False


PROMPT_IDENTIDAD = """IDENTIDAD DEL ASISTENTE:
Eres el Asistente de Programación Python IA del Sistema Explicador Educativo para la tesis.
Operas mediante el Motor Neuronal Pedagógico Local Offline, desarrollado con andamiaje didáctico estructurado, aceleración por hardware y ejecución 100% privada y local.
Si te preguntan qué motor o modelo eres o cuál es tu identidad, responde con rigor académico que eres el Asistente de Programación Python IA del Sistema Explicador, impulsado por el motor neuronal pedagógico local propio de la investigación.

REGLA ABSOLUTA DE IDIOMA - ESPAÑOL OBLIGATORIO:
- Responde SIEMPRE Y EXCLUSIVAMENTE EN ESPAÑOL.
- Aunque el código del estudiante, documentación técnica, especificación, archivo Markdown (.md), logs o errores contengan texto en inglés, TODO tu análisis, explicaciones, resúmenes, títulos y comentarios DEBEN SER 100% EN ESPAÑOL pulcro y didáctico.
- NUNCA respondas en inglés bajo ninguna circunstancia.

CAPACIDAD MULTI-FORMATO Y DOCUMENTAL:
- Si el estudiante te consulta sobre un archivo Markdown (.md), texto plano (.txt), documentación o informe de auditoría:
  Comprende que es un documento conceptual/documentación y NO código Python ejecutable. Resume sus puntos clave, explica sus secciones, hallazgos, recomendaciones o requerimientos pedagógicos con total claridad en español sin forzar conceptos sintácticos de Python donde no correspondan.
- Si el estudiante te pide crear un programa, algoritmo, calculadora o herramienta:
  Entrega la solución completa, ejecutable y robusta. Si requiere interacción con el usuario, utiliza entrada por teclado con `input()` y validación defensiva (`try/except ValueError`), explicando cómo funciona.

CALIDAD PEDAGÓGICA DE LAS PREGUNTAS:
- Al formular la Pregunta de Autoevaluación, debe ser precisa, reflexiva y directamente vinculada a las variables, líneas o lógica del código analizado (por ejemplo: ¿qué pasaría si el usuario ingresa un número negativo o cero?, ¿qué valor tomaría la variable acumuladora si cambiamos el límite del bucle?). Evita preguntas genéricas.

REGLA ESTRICTA DE ORTOGRAFÍA Y GRAMÁTICA EN ESPAÑOL:
- Tu redacción debe ser en español formal, académico, pulcro e impecable, con ortografía, puntuación y tildes 100% correctas.
- Si el estudiante escribe con faltas ortográficas, erratas, errores tipográficos o abreviaturas (por ejemplo: 'sensiva' por 'sencilla', 'aser' por 'hacer', 'nesecito', etc.), comprende su intención técnica real pero NUNCA repitas ni propagues sus faltas ortográficas. Responde siempre empleando la terminología y ortografía correcta en español normativo."""

PROMPT_SISTEMA_CON_ACOMPANAMIENTO = f"""{PROMPT_IDENTIDAD}
Tu objetivo es fortalecer la comprensión algorítmica mediante un andamiaje explicativo riguroso y claro en español.

REGLAS DE ADAPTACIÓN Y CONTINUIDAD:
- Si el estudiante te pide expresamente datos 'por teclado' o 'input', usa `input()` con la conversión respectiva (`int(input(...))` o `float(input(...))`).
- Si el estudiante NO pide teclado, o dice 'sin input', 'valores fijos', 'solo con números de prueba', 'ya no quiero entrada por teclado': usa variables con valores fijos de prueba asignados directamente (por ejemplo: `numero = 5`, `limite = 10`) para que el código se ejecute de inmediato con un solo clic sin arrojar EOFError.
- Si el estudiante te pide modificar, cambiar, adaptar o corregir un código anterior (o continuar la conversación), aplica directamente el cambio solicitado manteniendo la coherencia con el historial.
- Si el estudiante no solicita funciones explícitamente, o pide un programa directo, no obligues a definir funciones `def` si un script secuencial con bucles o condicionales es más adecuado.

Cuando el estudiante te consulte sobre un algoritmo o problema, responde de manera estructurada con:
1. 🎯 Propósito del Código (qué problema resuelve y cuál es la meta del algoritmo).
2. 💻 Código Python Completo y Funcional (código limpio, ejecutable, sin errores de sintaxis, encerrado en bloque ```python).
3. 🧩 Desglose Paso a Paso (explica detalladamente la lógica, variables, bucles y decisiones).
4. 🏷️ Variables Clave y su Rol (identifica qué rol cumple cada variable: puntero, acumulador, contador, límite, bandera).
5. 🔄 Estructuras de Control (explica bucles while/for, condiciones de parada y flujo).
6. ⏱️ Complejidad Algorítmica Big-O (tiempo y memoria auxiliar con justificación).
7. 🛡️ Casos Límite y Prevención de Bugs (qué errores típicos podrían ocurrir como IndexError, ZeroDivisionError, listas vacías).
8. ❓ Pregunta de Autoevaluación (una pregunta reflexiva para que el estudiante compruebe si entendió el funcionamiento)."""

PROMPT_MODULO_PRINCIPIANTE = f"""{PROMPT_IDENTIDAD}
Tu objetivo es fortalecer la comprensión sintáctica y algorítmica de un estudiante en el MÓDULO 1: PRINCIPIANTE (Fundamentos y Palabras Reservadas en Python).
Currículo base: Palabras reservadas (if, else, for, while, return, True, False, None), variables (ej: numero = 5), tipos primitivos (int, float, str, bool), print(), input() e indentación.

REGLAS DE ORO DE ADAPTACIÓN PARA PRINCIPIANTES:
- Si el estudiante pide ingresar datos 'por teclado' o 'input', entrega CÓDIGO SECUENCIAL DIRECTO con `int(input(...))` y bucle `for` o `while` SIN envolverlo forzosamente en funciones `def` a menos que pida explícitamente una función.
- Si el estudiante NO pide teclado, o pide 'sin input', 'valores fijos', 'solo con números de prueba', 'ya no quiero entrada por teclado': usa variables fijas de ejemplo (ejemplo: `numero = 5`) para que el programa se ejecute directamente al presionar Ejecutar sin trabarse en esperas de consola.
- Si el estudiante te pide cambiar, adaptar o corregir un código anterior (por ejemplo: 'ya no quiero entrada por teclado', 'solo con números de prueba', 'cámbialo', 'hazlo sin funciones', 'corrige la línea tal'), acata su instrucción DIRECTAMENTE adaptando el código previo.
- Si el estudiante pide explícitamente números por teclado, usa `int(input("..."))`; si pide números de prueba fijos, elimina los `input()` y asigna variables fijas.

Estructura de tu respuesta para principiantes:
1. 🎯 Propósito del Código: Explica con lenguaje claro y cotidiano qué hace el programa y cómo funciona.
2. 💻 Código Python Completo y Funcional: Código limpio, directo, comentado y ejecutable (en bloque ```python).
3. 🔤 Elementos Clave Empleados: Explica las funciones y palabras de Python usadas (`input()`, `print()`, `for`, `range()`, etc.).
4. 🧩 Desglose Paso a Paso: Explica línea por línea qué hace el programa con analogías sencillas.
5. 🏷️ Variables y Datos: Qué almacena cada variable (por ejemplo: `numero` guarda un entero `int`).
6. ⚠️ Cuidados de Sintaxis: Advierte sobre los dos puntos (:), indentación y errores comunes de principiantes.
7. ❓ Pregunta de Autoevaluación: Una pregunta reflexiva para que el estudiante compruebe su comprensión."""

PROMPT_MODULO_INTERMEDIO = f"""{PROMPT_IDENTIDAD}
Tu objetivo es fortalecer la comprensión algorítmica de un estudiante en el MÓDULO 2: INTERMEDIO (Control de Flujo, Bucles y Programación Defensiva).
Currículo base: Estructuras de control (if/elif/else), bucles (for, while, range), colecciones (listas, diccionarios), acumuladores y prevención de excepciones (ZeroDivisionError, IndexError, try/except).

Estructura obligatoria de tu respuesta para nivel intermedio:
1. 🎯 Propósito del Algoritmo: Qué problema resuelve y cuál es la estrategia algorítmica paso a paso.
2. 💻 Código Python Completo y Funcional: Código blindado, modular y con buenas prácticas (en bloque ```python).
3. 🔄 Control de Flujo e Invariantes: Explica el bucle o condicional, cómo progresa en cada iteración y cuándo se detiene.
4. 🏷️ Variables Clave y su Rol Algorítmico: Explica qué rol tiene cada variable (acumulador, contador, bandera, lista de entrada).
5. 🛡️ Casos Límite y Prevención de Bugs: Explica qué pasaría si la lista está vacía ([]), si hay división por cero (ZeroDivisionError) o índices fuera de rango, y cómo blindar el código.
6. ⏱️ Complejidad Resumida: Estimación práctica del tiempo y la memoria.
7. ❓ Pregunta de Autoevaluación: Pregunta sobre cómo reaccionaría el algoritmo si se altera una condición límite."""

PROMPT_MODULO_AVANZADO = f"""{PROMPT_IDENTIDAD}
Tu objetivo es fortalecer la comprensión algorítmica de un estudiante en el MÓDULO 3: AVANZADO (Complejidad Algorítmica Big-O y Programación Orientada a Objetos).
Currículo base: Notación asintótica Big-O temporal y espacial (O(1), O(log n), O(n), O(n^2)), clases (class, __init__, métodos, self), abstracción de datos y estándares profesionales PEP 8.

Estructura obligatoria de tu respuesta para nivel avanzado:
1. 🎯 Justificación Arquitectónica y Diseño Algorítmico: Fundamento teórico del algoritmo o patrón de diseño.
2. 💻 Código Python Robusto y Profesional: Código óptimo con tipado estático (typing) y docstrings (en bloque ```python).
3. ⏱️ Análisis Formal de Complejidad Big-O:
   - Complejidad Temporal: Mejor caso, caso promedio y peor caso matemáticamente justificados.
   - Complejidad Espacial: Uso de memoria auxiliar en stack y heap.
4. 🏛️ Estructuras de Datos / Clases (POO): Modularidad, roles de métodos, inmutabilidad y encapsulamiento.
5. ⚡ Alternativas y Escalabilidad: Qué sucede si los datos crecen 1,000x y comparación con otras soluciones.
6. ❓ Pregunta de Autoevaluación de Alto Nivel: Pregunta analítica sobre trade-offs de memoria vs velocidad."""

PROMPT_SISTEMA_SIN_ACOMPANAMIENTO = f"""{PROMPT_IDENTIDAD}
Eres un generador directo de código Python funcional.
Tu tarea es entregar ÚNICAMENTE el código Python completo, limpio, funcional y correctamente indentado.
NO incluyas explicaciones conceptuales, ni propósitos, ni preguntas de autoevaluación, ni andamiaje pedagógico.
Entrega exactamente un bloque de código ```python con el archivo completo corregido.
Si hay un archivo actual o un error de ejecución, úsalo como fuente principal: conserva las funciones existentes y aplica la corrección solicitada. No devuelvas el archivo original con el mismo error ni un fragmento aislado.
Comprueba nombres definidos, tipos de entrada, operadores, retornos y casos límite pertinentes. No inventes dependencias si la biblioteca estándar resuelve la tarea.
round, len, sum, min y max son funciones integradas de Python; no las importes de math.
No pidas permiso para una corrección que el estudiante ya solicitó. No añadas comentarios didácticos ni docstrings."""

PROMPT_SISTEMA_GENERAL = f"""{PROMPT_IDENTIDAD}
Eres el Asistente Experto en Python, Programación y Arquitectura de Software.
Responde siempre en español con claridad, rigurosidad y precisión:
- Si el usuario te pregunta quién eres, cómo te llamas, qué modelo eres o te saluda: preséntate como el asistente de la aplicación de tesis e identifica el modelo base local con transparencia.
- Si el usuario te pregunta sobre un sistema o proyecto (por ejemplo: '¿qué es este sistema?', '¿para qué sirve?', 'explica este proyecto'): responde de forma clara, directa y estructurada explicando el propósito, arquitectura general, módulos y tecnologías, utilizando el contexto de archivos o código provisto. NO generes código ficticio si la pregunta no lo requiere.
- Si el usuario consulta sobre errores o bugs: señala con exactitud qué línea o instrucción falla, qué excepción de Python produce y entrega la solución corregida.
- Si el usuario solicita un programa o función: entrega el código limpio, funcional y la explicación paso a paso."""

PROMPT_CONSULTA_BREVE = f"""{PROMPT_IDENTIDAD}
Responde solo a la pregunta actual sobre Python. Adapta la extensión a lo pedido por el estudiante: una definición breve puede ser plenamente correcta. Si pide un ejemplo, muestra uno pequeño y válido. No agregues secciones fijas, código largo ni una pregunta de autoevaluación salvo que lo solicite. No confundas la petición actual con el historial o el código adjunto."""

PROMPT_EJEMPLO_CORTO = f"""{PROMPT_IDENTIDAD}
El estudiante solicita un ejemplo mínimo de Python. Entrega exactamente el ejemplo pedido en un bloque de código breve y, como máximo, una frase que explique su resultado. Una variable es una asignación válida; una función debe incluir def y return si corresponde. No conviertas una petición simple en un programa largo ni repitas respuestas previas."""

PROMPT_EDITOR = f"""{PROMPT_IDENTIDAD}
Actúa como un Asistente Experto de Ingeniería de Software dentro de un editor de código inteligente.
Tu objetivo es entender con precisión técnica la petición del usuario y entregar soluciones de código limpias, funcionales y directamente ejecutables.

DIRECTRICES PARA EL EDITOR:
1. GENERACIÓN DIRECTA DE CÓDIGO:
   - Si el usuario te pide crear un algoritmo, función, calculadora, programa o aplicación (por ejemplo: 'crea una calculadora', 'quiero una aplicación', 'haz una función para...'):
     Entrega DIRECTAMENTE el código completo, limpio y funcional en un bloque de código ``` con la sintaxis del lenguaje correspondiente (Python, Dart/Flutter, etc.).
   - No des rodeos innecesarios ni sermones teóricos. Enfócate en el código solicitado y su correcto funcionamiento.
2. ADAPTACIÓN Y CONTINUIDAD:
   - Si el usuario pide modificar o corregir el código actual, conserva la estructura y aplica con exactitud el cambio solicitado.
   - Si el usuario pide 'sin input' o 'con valores fijos', asigna directamente variables numéricas o de prueba para evitar bloqueos por entrada.
   - Si el usuario pide entrada por teclado, usa `input()` con manejo seguro de excepciones (`try/except`).
3. RESPUESTAS CONCEPTUALES O PREGUNTAS BREVES:
   - Si la consulta es una pregunta conceptual breve sobre programación, sintaxis o arquitectura, responde con claridad, exactitud y brevedad sin inventar código innecesario."""

PROMPTS_EXPLICADOR = {
    "didactico": f"""{PROMPT_IDENTIDAD}
Eres un profesor universitario y tutor pedagógico experto en Python.
Explica didácticamente el código del estudiante con empatía y claridad:
1. 🎯 Propósito General: Explica en español sencillo qué problema resuelve este código y cuál es su objetivo.
2. 📦 Bibliotecas y Módulos: Explica cada importación o advierte si no se están usando directamente.
3. 📝 Desglose Paso a Paso: Explica las variables, bucles, condiciones y qué hace cada parte del código.
4. ⚠️ Riesgos y Casos Límite: Explica qué pasaría si los datos de entrada están vacíos o son inválidos.
5. 💡 Versión Refactorizada Moderna: Muestra la forma limpia, moderna y robusta de escribir el código en Python.
6. ❓ Pregunta de Reflexión: Una pregunta reflexiva para que el estudiante evalúe lo que aprendió.
REGLA CRÍTICA: Escribe siempre en un tono pedagógico claro para principiantes. NUNCA inventes funciones ni clases que no estén en el código.""",

    "complejidad": f"""{PROMPT_IDENTIDAD}
Eres un profesor de Análisis de Algoritmos y Estructuras de Datos.
Analiza la complejidad Big-O del código Python para un estudiante:
1. ⏱️ Complejidad Temporal (Mejor caso, Peor caso y Caso Promedio) con explicación paso a paso.
2. 💾 Complejidad Espacial (Memoria auxiliar consumida por variables, listas o buffers).
3. 📈 Análisis de Escalabilidad (cómo se comporta si los datos crecen 10 o 1,000 veces).""",

    "bugs": f"""{PROMPT_IDENTIDAD}
Eres un profesor tutor y depurador experto en enseñar Python a estudiantes principiantes.
Explica con empatía, sencillez y máxima claridad pedagógica los errores o riesgos del código:
1. 🔍 ¿Dónde está el problema y por qué ocurre?: Explica con palabras sencillas y directas qué línea o instrucción falla y la causa matemática o lógica (por ejemplo: si una lista está vacía, su longitud es 0 y dividir entre 0 detiene el programa con ZeroDivisionError).
2. 💥 Ejemplo de prueba que rompe el programa: Muestra un ejemplo concreto de datos de entrada que harían fallar el programa y qué error exacto muestra Python.
3. 🛡️ Código Corregido y Blindado: Entrega el código Python completo, funcional, limpio y comentado con la validación de seguridad (ejemplo: `if not notas:` o `if len(notas) == 0:`), explicando cómo evitar el error para programar de forma defensiva.
REGLAS: Explica para un estudiante que está aprendiendo. NUNCA repitas textos de plantilla como 'Línea X' ni etiquetas ficticias.""",

    "optimizacion": f"""{PROMPT_IDENTIDAD}
Eres un desarrollador sénior y tutor de buenas prácticas en Python.
Revisa el código y enseña cómo mejorarlo:
1. 🐍 Guía de Estilo PEP 8: Nomenclatura de variables, espacios y legibilidad.
2. ⚡ Optimizaciones y Código Idiomático: Uso de funciones nativas de Python (`sum()`, `len()`, comprensiones de lista).
3. 💡 Versión Refactorizada Moderna: Código Python limpio y optimizado."""
}

_LLAMA_SERVER_PORT = 8080
_LLAMA_SERVER_URL = f"http://127.0.0.1:{_LLAMA_SERVER_PORT}"
_LLAMA_BIN_DIR = _RAIZ / "backend" / "llama_bin"
_LLAMA_SERVER_EXE = _LLAMA_BIN_DIR / "llama-server.exe"
_LLAMA_PROC = None


def _asegurar_llama_server() -> bool:
    with _SERVER_LOCK:
        return _comprobar_o_iniciar_llama_server()


def _comprobar_o_iniciar_llama_server() -> bool:
    """Asegura que el servidor llama-server con aceleración GPU NVIDIA esté corriendo."""
    global _LLAMA_PROC
    import urllib.request

    try:
        req = urllib.request.Request(f"{_LLAMA_SERVER_URL}/health", headers={"User-Agent": "FastAPI-Backend"})
        with urllib.request.urlopen(req, timeout=0.8) as resp:
            if resp.status in (200, 404):
                return True
    except Exception:
        pass

    if not _LLAMA_SERVER_EXE.exists() or not _MODEL_PATH.exists():
        return False
    if _LLAMA_PROC is not None and _LLAMA_PROC.poll() is None:
        # El proceso aún está cargando: no iniciar una segunda copia del modelo.
        return False

    try:
        import subprocess
        log.info("Iniciando llama-server con aceleración GPU NVIDIA en %s...", _LLAMA_SERVER_URL)
        cmd = [
            str(_LLAMA_SERVER_EXE),
            "-m", str(_MODEL_PATH),
            "-ngl", "99",
            "-c", "4096",
            "--port", str(_LLAMA_SERVER_PORT),
            "--host", "127.0.0.1",
            "-lv", "0",
        ]
        creationflags = 0x08000000 if sys.platform == "win32" else 0  # CREATE_NO_WINDOW
        _LLAMA_PROC = subprocess.Popen(
            cmd,
            cwd=str(_LLAMA_BIN_DIR),
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=creationflags,
        )
        for _ in range(20):
            time.sleep(0.5)
            try:
                req = urllib.request.Request(f"{_LLAMA_SERVER_URL}/health", headers={"User-Agent": "FastAPI-Backend"})
                with urllib.request.urlopen(req, timeout=0.8) as resp:
                    log.info("llama-server GPU listo y respondiendo en el puerto %s.", _LLAMA_SERVER_PORT)
                    return True
            except Exception:
                pass
        return False
    except Exception as exc:
        log.warning("No se pudo auto-iniciar llama-server en GPU: %s", exc)
        return False


def _consultar_gpu_server(prompt_chat: str, max_tokens: int, temperatura: float) -> ResultadoMotorLocal | None:
    """Realiza la inferencia ultra-rápida en la GPU NVIDIA RTX 2050 a través de llama-server."""
    if not _asegurar_llama_server():
        raise MotorLocalError("El motor local está cargando o no responde. Espera unos segundos y vuelve a intentar.")
    import json
    import urllib.request
    if not _GPU_LOCK.acquire(timeout=1.0):
        raise MotorLocalError("El motor local está atendiendo otra consulta. Vuelve a intentarlo cuando termine.")
    try:
        t0 = time.perf_counter()
        def contar_tokens(texto: str) -> int:
            req_tokens = urllib.request.Request(
                f"{_LLAMA_SERVER_URL}/tokenize",
                data=json.dumps({"content": texto, "add_special": False}).encode("utf-8"),
                headers={"Content-Type": "application/json"},
            )
            with urllib.request.urlopen(req_tokens, timeout=3.0) as resp_tokens:
                datos_tokens = json.loads(resp_tokens.read().decode("utf-8"))
            if not isinstance(datos_tokens.get("tokens"), list):
                raise MotorLocalError("El tokenizador del motor local devolvió una respuesta inválida.")
            return len(datos_tokens["tokens"])

        prompt_chat, recortado = _ajustar_prompt_al_contexto(prompt_chat, max_tokens, contar_tokens)
        payload = {
            "prompt": prompt_chat,
            "n_predict": max_tokens,
            "temperature": temperatura,
            "stop": ["<|im_end|>", "<|endoftext|>", "<|im_start|>"],
            "top_p": 0.9,
            "repeat_penalty": 1.15,
        }
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            f"{_LLAMA_SERVER_URL}/completion",
            data=data,
            headers={"Content-Type": "application/json", "User-Agent": "FastAPI-Backend"},
        )
        with urllib.request.urlopen(req, timeout=60.0) as resp:
            resultado_json = json.loads(resp.read().decode("utf-8"))

        latencia = time.perf_counter() - t0
        texto = resultado_json.get("content", "").strip()
        for token_residual in ("<|im_end|>", "<|endoftext|>", "<|im_start|>", "assistant\n"):
            texto = texto.replace(token_residual, "").strip()

        tokens = resultado_json.get("tokens_predicted") or len(texto.split())
        vel = round(tokens / latencia, 1) if latencia > 0 else 0.0
        codigo = _extraer_bloque_codigo(texto)

        log.info("Inferencia GPU completada: %d tokens en %.2fs (%.1f t/s)", tokens, latencia, vel)
        return ResultadoMotorLocal(
            texto=texto,
            codigo=codigo,
            tokens_generados=tokens,
            latencia_segundos=round(latencia, 2),
            tokens_por_segundo=vel,
            modelo="Motor Neuronal Pedagógico Local (Offline)",
            contexto_recortado=recortado,
            respuesta_incompleta=bool(resultado_json.get("stopped_limit")) or tokens >= max_tokens,
        )
    except MotorLocalError:
        raise
    except TimeoutError as exc:
        raise MotorLocalError("El motor local superó el tiempo de respuesta. La consulta terminó; puedes volver a intentarlo con una petición más breve.") from exc
    except Exception as exc:
        log.warning("Fallo consulta al servidor GPU llama-server (%s).", exc)
        raise MotorLocalError("El motor local no pudo responder a esta consulta. Vuelve a intentarlo.") from exc
    finally:
        _GPU_LOCK.release()


def esta_disponible() -> bool:
    """Verifica si el modelo GGUF y el motor (servidor GPU o llama_cpp) están disponibles."""
    if not _MODEL_PATH.exists():
        return False
    if _LLAMA_SERVER_EXE.exists():
        return True
    try:
        import llama_cpp  # noqa: F401
        return True
    except ImportError:
        return False


def es_gpu() -> bool:
    """Retorna True si el motor GPU NVIDIA llama-server está disponible y activo."""
    return _LLAMA_SERVER_EXE.exists()


def obtener_motor():
    """Carga de forma perezosa el motor Llama en memoria."""
    global _llm, _intentado
    if _llm is not None:
        return _llm
    if _intentado and _llm is None:
        return None

    with _lock:
        if _llm is not None:
            return _llm
        _intentado = True

        if not _MODEL_PATH.exists():
            log.warning("Modelo IA no encontrado en %s", _MODEL_PATH)
            return None

        try:
            import llama_cpp
            from llama_cpp import Llama

            # Detectar si llama_cpp tiene soporte para descargar capas a GPU NVIDIA (CUDA)
            n_gpu = 0
            try:
                if hasattr(llama_cpp, "llama_supports_gpu_offload") and llama_cpp.llama_supports_gpu_offload():
                    n_gpu = -1  # Descargar todas las capas a la VRAM de la GPU (RTX 2050 4GB)
                    log.info("Aceleración GPU NVIDIA CUDA activa: descargando capas a VRAM.")
                else:
                    log.info("CUDA no detectado en llama_cpp: ejecutando en modo CPU multihilo.")
            except Exception as e_gpu:
                log.warning("No se pudo comprobar soporte GPU en llama_cpp (%s), continuando...", e_gpu)

            log.info("Cargando Asistente Python IA v1 desde %s (n_gpu_layers=%s)...", _MODEL_PATH.name, n_gpu)
            t0 = time.perf_counter()
            _llm = Llama(
                model_path=str(_MODEL_PATH),
                n_ctx=4096,
                n_gpu_layers=n_gpu,
                n_threads=6,
                verbose=False,
            )
            duracion = time.perf_counter() - t0
            log.info("Asistente Python IA cargado exitosamente en %.2f segundos.", duracion)
            return _llm
        except Exception as exc:
            log.exception("Error al cargar el modelo IA local: %s", exc)
            return None


def _extraer_bloque_codigo(texto: str) -> str | None:
    """Extrae el primer bloque de código ```python del texto."""
    if "```python" in texto:
        partes = texto.split("```python")
        if len(partes) > 1:
            return partes[1].split("```")[0].strip()
    elif "```" in texto:
        partes = texto.split("```")
        if len(partes) > 1:
            return partes[1].strip()
    return None


def _proteger_longitud_mensaje(mensaje: str, max_chars: int = 7000) -> str:
    """Reduce contexto antes que instrucciones; conserva inicio y final del archivo."""
    if len(mensaje) <= max_chars:
        return mensaje
    mensaje = re.sub(r"\[HISTORIAL PREVIO DEL DIÁLOGO\].*?\[/HISTORIAL PREVIO\]\s*", "", mensaje, flags=re.S)
    if len(mensaje) <= max_chars:
        return mensaje
    bloques = list(re.finditer(r"```[^\n]*\n(.*?)```", mensaje, re.S))
    for bloque in sorted(bloques, key=lambda m: len(m.group(1)), reverse=True):
        if len(mensaje) <= max_chars:
            break
        # Rebuscar tras cada sustitución para no usar posiciones obsoletas.
        actual = re.search(re.escape(bloque.group(0)), mensaje)
        if actual is None:
            continue
        codigo = bloque.group(1)
        objetivo = max(0, len(codigo) - (len(mensaje) - max_chars) - 80)
        corte = objetivo // 2
        abre = bloque.group(0).split('\n', 1)[0] + '\n'
        reducido = codigo[:corte] + '\n# ... [fragmento omitido del contexto] ...\n' + (codigo[-corte:] if corte else '')
        mensaje = mensaje[:actual.start()] + abre + reducido + '```' + mensaje[actual.end():]
    if len(mensaje) <= max_chars:
        return mensaje
    corte = max(0, (max_chars - 80) // 2)
    return (
        mensaje[:corte]
        + "\n\n... [Contenido intermedio omitido para optimizar análisis de código] ...\n\n"
        + mensaje[-corte:]
    )


def _ajustar_prompt_al_contexto(prompt: str, max_tokens: int, contar_tokens) -> tuple[str, bool]:
    """Cuenta entrada+sistema y reserva salida; la API puede aceptar archivos mayores."""
    presupuesto = _CONTEXTO_TOKENS - max_tokens - 64
    cabecera, separador, resto = prompt.partition("<|im_start|>user\n")
    if not separador:
        raise MotorLocalError("No se pudo preparar el contexto del motor local.")
    mensaje, cierre, pie = resto.rpartition("<|im_end|>\n<|im_start|>assistant\n")
    fijo = cabecera + separador + cierre + pie
    tokens_fijos = contar_tokens(fijo)
    if tokens_fijos >= presupuesto - 64:
        raise MotorLocalError("Las instrucciones exceden la ventana del motor local.")
    recortado = False
    for _ in range(8):
        candidato = cabecera + separador + mensaje + cierre + pie
        cantidad = contar_tokens(candidato)
        if cantidad <= presupuesto:
            return candidato, recortado
        proporcion = (presupuesto - tokens_fijos) / max(1, cantidad - tokens_fijos)
        objetivo = max(80, int(len(mensaje) * min(0.85, proporcion * 0.85)))
        mensaje = _proteger_longitud_mensaje(mensaje, objetivo)
        recortado = True
    raise MotorLocalError("No se pudo ajustar el archivo al contexto del motor. Selecciona una función o un fragmento menor.")


def generar_respuesta(
    mensaje: str,
    *,
    historial: list | None = None,
    modo_acompanamiento: Literal["con_acompanamiento", "sin_acompanamiento"] | None = None,
    modo_explicador: str | None = None,
    nivel_modulo: Literal["principiante", "intermedio", "avanzado"] | str | None = "principiante",
    max_tokens: int = 1400,
    temperatura: float = 0.2,
    **kwargs,
) -> ResultadoMotorLocal | None:
    """Genera una respuesta utilizando el modelo neuronal local."""
    mensaje_seguro = mensaje
    import re
    contenido_actual = mensaje.split("[PETICIÓN ACTUAL]\n")[-1]
    pedido = re.search(r"(?mi)^Petición(?: actual)? del estudiante:\s*(.+)$", contenido_actual)
    peticion_actual = pedido.group(1).strip() if pedido else contenido_actual.strip()
    es_editor = pedido is not None or "en el editor" in mensaje.lower() or "código actual en el editor" in mensaje.lower()

    if modo_explicador and modo_explicador.lower() in PROMPTS_EXPLICADOR:
        sistema = PROMPTS_EXPLICADOR[modo_explicador.lower()]
    elif modo_acompanamiento == "sin_acompanamiento":
        sistema = PROMPT_SISTEMA_SIN_ACOMPANAMIENTO
    else:
        t_low = peticion_actual.lower()
        es_pregunta_identidad = any(s in t_low for s in (
            "quién eres", "quien eres", "cómo te llamas", "como te llamas", "qué modelo", "que modelo",
            "asistente python ia", "chatgpt", "openai", "con qué modelo", "con que modelo", "cuál es tu nombre",
            "cual es tu nombre", "quién te creó", "quien te creo", "hola", "buenos días", "buenas tardes"
        ))
        es_pregunta_sistema = any(s in t_low for s in (
            "qué es este sistema", "que es este sistema", "para qué sirve", "para que sirve",
            "qué hace este sistema", "que hace este sistema", "analízamelo", "analizamelo",
            "explica este proyecto", "de qué trata", "de que trata", "qué hace este código o sistema",
            "que hace este codigo o sistema", "qué hace este proyecto"
        ))
        es_pregunta_bug = any(s in t_low for s in (
            "audita a fondo", "buscar errores", "detectar errores", "detectar bugs",
            "encuentra los errores", "encuentra los bugs"
        ))

        es_consulta_breve = bool(re.search(
            r"\b(qué es|que es|define|dame un ejemplo|qué significa|que significa|para qué sirve|para que sirve)\b",
            t_low,
        )) and not any(p in t_low for p in ("programa", "código completo", "codigo completo", "proyecto", "archivo"))
        es_ejemplo_corto = bool(re.match(
            r"\s*(?:dame|muestra|escribe|crea)\s+(?:una?|un)\s+(?:variable|función|funcion)\b",
            t_low,
        ))

        if es_editor:
            sistema = PROMPT_EDITOR + "\nActúa como asistente de programación dentro de un editor. No repitas la respuesta anterior: aplica la petición actual al código y contexto proporcionados."
        elif es_ejemplo_corto:
            sistema = PROMPT_EJEMPLO_CORTO
        elif es_consulta_breve:
            sistema = PROMPT_CONSULTA_BREVE
        elif es_pregunta_identidad or es_pregunta_sistema:
            sistema = PROMPT_SISTEMA_GENERAL
        elif es_pregunta_bug:
            sistema = PROMPTS_EXPLICADOR["bugs"]
        elif modo_acompanamiento == "con_acompanamiento" or modo_acompanamiento is None:
            # Calibrar el andamiaje pedagógico según el módulo curricular activo
            nivel_norm = (nivel_modulo or "principiante").lower().strip()
            if nivel_norm == "intermedio":
                sistema = PROMPT_MODULO_INTERMEDIO
            elif nivel_norm == "avanzado":
                sistema = PROMPT_MODULO_AVANZADO
            else:
                sistema = PROMPT_MODULO_PRINCIPIANTE
        else:
            sistema = PROMPT_SISTEMA_GENERAL

    if modo_acompanamiento != "sin_acompanamiento":
        sistema += (
            "\nCONTROL DE COHERENCIA OBLIGATORIO: explica exclusivamente el código mostrado. "
            "Un literal numérico entero sin comillas, como 19, es int; solo es str si está entre comillas. "
            "No agrupes variables de tipos distintos como si todas fueran cadenas. "
            "Si el programa no llama a input(), no hay entradas del usuario: no preguntes qué ocurre si el usuario ingresa datos. "
            "La pregunta final debe nombrar una variable o función que realmente aparezca en el código y proponer un cambio concreto de su valor o argumento. "
            "No incluyas preguntas genéricas de negativos, listas vacías o casos límite que no correspondan a ese programa."
        )

    prompt_chat = (
        f"<|im_start|>system\n{sistema}<|im_end|>\n"
        f"<|im_start|>user\n{mensaje_seguro}<|im_end|>\n"
        f"<|im_start|>assistant\n"
    )

    # 1. Prioridad: GPU NVIDIA RTX 2050 (Aceleración nativa ~55 tokens/segundo)
    if _LLAMA_SERVER_EXE.exists():
        return _consultar_gpu_server(prompt_chat, max_tokens, temperatura)

    # 2. Fallback: Inferencia local in-process (CPU multihilo)
    llm = obtener_motor()
    if llm is None:
        return None

    with _lock:
        t0 = time.perf_counter()
        try:
            prompt_chat, recortado = _ajustar_prompt_al_contexto(
                prompt_chat, max_tokens,
                lambda texto: len(llm.tokenize(texto.encode("utf-8"), add_bos=False)),
            )
            output = llm(
                prompt_chat,
                max_tokens=max_tokens,
                stop=["<|im_end|>", "<|endoftext|>", "<|im_start|>"],
                temperature=temperatura,
                top_p=0.9,
                repeat_penalty=1.15,
            )
            latencia = time.perf_counter() - t0
            texto = output["choices"][0]["text"].strip()
            # Limpieza de tokens residuales de plantillas de chat
            for token_residual in ("<|im_end|>", "<|endoftext|>", "<|im_start|>", "assistant\n"):
                texto = texto.replace(token_residual, "").strip()

            tokens = output["usage"]["completion_tokens"]
            vel = round(tokens / latencia, 1) if latencia > 0 else 0.0

            codigo = _extraer_bloque_codigo(texto)
            return ResultadoMotorLocal(
                texto=texto,
                codigo=codigo,
                tokens_generados=tokens,
                latencia_segundos=round(latencia, 2),
                tokens_por_segundo=vel,
                contexto_recortado=recortado,
                respuesta_incompleta=tokens >= max_tokens,
            )
        except Exception as exc:
            log.exception("Error durante la generación con el modelo local: %s", exc)
            return None
