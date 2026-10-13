# Documentación Técnica de Infraestructura y Aplicación

> **Sistema Explicador de Código Python con Asistente de Inteligencia Artificial**\
> **Proyecto de Titulación / Investigación Universitaria**\
> **Área**: Ciencias de la Computación, Inteligencia Artificial Educativa\
> **Entorno**: 100% Local, Offline y Autónomo (Aceleración GPU CUDA)

---

## 1. Resumen Ejecutivo

El presente sistema es una plataforma educativa integral desarrollada para fortalecer la comprensión algorítmica y la resolución de problemas de programación en lenguaje Python. La solución se sustenta en una arquitectura desacoplada y soberana, ejecutando un **modelo de lenguaje neuronal propio en inferencia local acelerada por hardware (GPU CUDA)**, eliminando por completo la dependencia de proveedores o APIs comerciales de terceros durante su operación.

El sistema provee dos interfaces para los estudiantes e investigadores:
1. **Aplicación de Escritorio Nativa (Desktop)** desarrollada en Flutter para Windows, optimizada para baja latencia y alta interactividad.
2. **Backend de Servicios de IA y Gestión Educativa** desarrollado en FastAPI (Python asíncrono), responsable de la orquestación del modelo, el andamiaje pedagógico y el registro de telemetría.

---

## 2. Diagrama de Arquitectura del Sistema

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      CAPA DE PRESENTACIÓN / CLIENTES                    │
│                                                                         │
│   ┌───────────────────────────────────┐ ┌───────────────────────────┐   │
│   │   Aplicación Desktop Nativa       │ │    Portal Web de Gestión  │   │
│   │   Flutter (Windows Release x64)   │ │    Next.js + TailwindCSS  │   │
│   │   - Chat con andamiaje pedagógico │ │    - Panel de evaluación  │   │
│   │   - Explicador multinivel AST     │ │    - Monitoreo de modelo  │   │
│   │   - Editor interactivo de código  │ │    - Base de conocimiento │   │
│   └─────────────────┬─────────────────┘ └─────────────┬─────────────┘   │
└─────────────────────┼─────────────────────────────────┼─────────────────┘
                      │                                 │
                      ▼                                 ▼
         Peticiones HTTP REST / JSON Asíncrono (Puerto 8765)
                      │
┌─────────────────────┼───────────────────────────────────────────────────┐
│                     ▼  CAPA DE SERVICIOS Y ORQUESTACIÓN                 │
│                                                                         │
│   ┌─────────────────────────────────────────────────────────────────┐   │
│   │   Servidor Backend FastAPI (Python 3.11+, Uvicorn Async)        │   │
│   │   ├── Router de Chat y Conversaciones (/api/v1/chat)            │   │
│   │   ├── Router de Explicador Didáctico (/api/v1/ai)               │   │
│   │   ├── Motor de Andamiaje Pedagógico (educational_engine)        │   │
│   │   ├── Analizador Sintáctico AST Nativo (code_explainer_service) │   │
│   │   ├── Base de Conocimiento Curada / RAG (retrieval_service)     │   │
│   │   └── Servicio de Telemetría y Métricas (tokens, latencia)      │   │
│   └─────────────────┬───────────────────────────────┬───────────────┘   │
└─────────────────────┼───────────────────────────────┼───────────────────┘
                      │                               │
        ┌─────────────┴─────────────┐   ┌─────────────┴─────────────┐
        ▼                           ▼   ▼                           ▼
┌───────────────────────────────┐   ┌───────────────────────────────────┐
│    MOTOR NEURONAL LOCAL IA    │   │      PERSISTENCIA DE DATOS        │
│                               │   │                                   │
│  - Modelo Propio IA           │   │  - PostgreSQL 16 / SQLite Local   │
│  - Formato: GGUF Cuantizado   │   │  - Tablas: usuarios, consultas,  │
│  - Aceleración: NVIDIA CUDA   │   │    conversaciones, mensajes,      │
│  - Contexto: 8,192 tokens     │   │    telemetría y evaluaciones      │
│  - Inferencia offline 100%    │   │  - Almacenamiento seguro bcrypt   │
└───────────────────────────────┘   └───────────────────────────────────┘
```

---

## 3. Especificaciones de Infraestructura de Hardware

### 3.1 Servidor de Inferencia / Estación de Trabajo
* **Procesador (CPU)**: 6 núcleos / 12 hilos o superior (Intel Core i5/i7 o AMD Ryzen 5/7).
* **Memoria RAM**: Mínimo 16 GB DDR4/DDR5.
* **Acelerador Gráfico (GPU)**: NVIDIA GeForce RTX (ej. RTX 2050 / 3050 / 3060 / 4060) con arquitectura Turing/Ampere o superior, soporte CUDA 12.x y mínimo 4 GB de VRAM dedicada.
* **Almacenamiento**: Disco de estado sólido (NVMe/SSD) con al menos 10 GB de espacio libre para binarios del modelo y base de datos.
* **Sistema Operativo**: Windows 10/11 Pro 64-bit o Ubuntu Linux 22.04 LTS.

### 3.2 Clientes / Estaciones de Estudiantes
* Cualquier computadora con Windows 10/11 de 64 bits.
* No requiere tarjeta gráfica dedicada en las máquinas de los estudiantes; toda la carga de inferencia la procesa el servidor del sistema.

---

## 4. Componentes de la Infraestructura

### 4.1 Backend (Servicios REST y Motor de IA)
* **Framework**: FastAPI 0.115+ (asíncrono, basado en Starlette y Pydantic v2).
* **Gestor ASGI**: Uvicorn con workers asíncronos.
* **Capa de Abstracción de Datos**: SQLAlchemy 2.0 en modo asíncrono con Alembic para versionado de esquemas.
* **Inferencia Neuronal**: Motor local con soporte de aceleración offloading total a GPU (`n_gpu_layers = -1`, `n_ctx = 8192`, `n_threads = 6`).
* **Seguridad y Control de Acceso**:
  - Autenticación mediante tokens JWT firmados con algoritmo HS256.
  - Hashing criptográfico de contraseñas con `bcrypt` (factor de costo 12).
  - Control de acceso basado en roles (RBAC: Estudiante, Docente, Administrador).

### 4.2 Aplicación de Escritorio (Desktop)
* **Framework**: Flutter 3.24+ compilado en código nativo de producción C++ / Windows Release.
* **Arquitectura de Estado**: Provider / MultiProvider desacoplado reactivamente.
* **Tematización**: Paleta tipográfica de alta legibilidad, soporte para modo claro/oscuro y diseño responsivo.
* **Capacidades Integradas**:
  - **Chat Didáctico**: Comunicación fluida con el modelo, renderizado de markdown con resaltado de sintaxis para Python y bloques de código copiables.
  - **Explicador de Código Especializado**: Análisis en 4 modos clave: Didáctico paso a paso, Complejidad algorítmica Big-O, Detección de bugs y riesgos, y Optimización de rendimiento.
  - **Selector de Condición Experimental**: Soporte para evaluación cuasiexperimental con grupo experimental (con acompañamiento metacognitivo) y grupo de control (sin acompañamiento).

---

## 5. Módulos Funcionales del Sistema

### 5.1 Motor de Andamiaje Pedagógico
A diferencia de modelos generalistas, este sistema integra una capa de prompts estructurados y validadores sintácticos que obligan al modelo a razonar educativamente:
1. **Propósito del Algoritmo**: Explica qué problema resuelve antes de mostrar la sintaxis.
2. **Código Python Estructurado**: Código limpio, comentado y tipado según PEP 8.
3. **Desglose Paso a Paso**: Rastreo de ejecución línea a línea o por fases.
4. **Variables y Estructuras Clave**: Explicación de los roles de cada variable en memoria.
5. **Análisis de Complejidad**: Tiempo $\mathcal{O}(n)$ y espacio en memoria auxiliar.
6. **Riesgos y Casos Borde**: Advertencias de desbordamiento, errores comunes de principiantes y buenas prácticas.

### 5.2 Sistema de Telemetría y Métricas en Tiempo Real
Cada solicitud procesada por el sistema registra métricas de rendimiento computacional que se devuelven al cliente y se almacenan para análisis empírico de la tesis:
* **Latencia de Respuesta**: Tiempo total de inferencia en segundos.
* **Tokens Generados**: Cantidad de tokens emitidos en la respuesta.
* **Velocidad de Procesamiento**: Tasa en tokens por segundo ($\text{tokens/s}$).
* **Dispositivo de Cómputo**: Identificador del dispositivo activo (`cuda:0` para GPU).

---

## 6. Scripts de Operación y Puesta en Marcha

El sistema cuenta con scripts automatizados de arranque rápido para facilitar la demostración y evaluación:

| Archivo | Función |
|---|---|
| `iniciar_sistema.bat` | Script principal en un clic. Detecta si el backend está activo; si no, lo inicia en segundo plano y levanta de inmediato la aplicación de escritorio compilada. |
| `iniciar_backend.bat` | Inicia exclusivamente el servidor backend FastAPI en el puerto `8765`, mostrando la consola de telemetría y logs de inferencia en tiempo real. |
| `release/desktop/app_desktop.exe` | Binario nativo compilado de la aplicación de escritorio Flutter (listo para distribución). |

---

## 7. Despliegue para Evaluación Multi-Usuario

Para la fase de pruebas y recolección de datos con grupos de estudiantes (20 usuarios simultáneos), la infraestructura admite dos topologías de despliegue:

### 7.1 Topología en Red de Área Local (Laboratorio de Cómputo)
* El servidor principal (PC con GPU) ejecuta el backend escuchando en todas las interfaces de red (`0.0.0.0:8765`).
* Las computadoras de los estudiantes ejecutan la aplicación de escritorio configurando la dirección IP local del servidor (ej. `http://192.168.1.50:8765`).
* Todo el tráfico permanece dentro de la red del laboratorio sin consumir ancho de banda de internet.

### 7.2 Topología Remota con Túnel Seguro (Acceso Fuera del Campus)
* Se habilita un túnel seguro mediante Cloudflare Tunnel hacia el puerto `8765`.
* El túnel genera un dominio seguro `https://asistente-ia.midominio.com`.
* Los estudiantes pueden conectarse desde sus hogares u otros dispositivos sin necesidad de abrir puertos en el router ni configurar VPNs.

---

## 8. Verificación y Pruebas del Sistema

El sistema cuenta con una suite de pruebas automatizadas en `verificar_capacidades.py` que valida:
1. **Resolución de Consultas Conceptuales**: Explicación de recursión, estructuras de datos y algoritmos.
2. **Generación de Código Funcional**: Síntesis de algoritmos con validación sintáctica.
3. **Detección de Bugs y Errores**: Diagnóstico acertado de excepciones comunes (`ZeroDivisionError`, `IndexError`, errores de indentación).
4. **Identidad Pedagógica**: Garantía de respuesta como asistente educativo del proyecto sin referencias a entidades comerciales externas.
