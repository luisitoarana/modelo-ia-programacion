# Guía del profesor: instalar y revisar PythonIA

La referencia vigente y detallada es el [README principal](../README.md). Descargue el repositorio completo, extraiga el ZIP y abra la carpeta.

## Elegir un acceso

| Necesidad | Doble clic |
|---|---|
| Probar aplicación, web y backend | `EJECUTAR_SISTEMA_TESIS.bat`, opción 1 normal u opción 2 Docker |
| Iniciar solamente la API | `iniciar_backend.bat`, opción 1 normal u opción 2 Docker |
| Abrir solamente el escritorio | `iniciar_sistema.bat`; el backend debe estar activo |

Normal: Python >=3.11, Node 22/24 LTS para web y Flutter con Dart >=3.10.1 más Visual Studio C++ para escritorio. Docker: Docker Desktop con contenedores Linux; no necesita Python/Node del host. Si abre el escritorio desde código, necesita Flutter incluso con Docker.

Se instalan las dependencias automáticamente. La primera vez hay descargas. La API se abre en http://127.0.0.1:8765/docs y la web en http://localhost:3000.

## Cuenta y evaluación

La configuración privada es `backend/.env`. Una instalación nueva genera una contraseña aleatoria; utilice ADMIN_EMAIL y ADMIN_PASSWORD para la cuenta administradora. Una configuración existente se conserva. No envíe ese archivo a GitHub.

En la aplicación abra Administración, revise participantes, intentos y respuestas, y utilice las exportaciones. Los estudiantes se registran desde la aplicación. La revisión docente evalúa respuestas breves o extensas según su contenido; los comentarios del asistente no son una nota docente.

## Modelo y comprobación

Los pesos y ejecutables del motor se entregan por separado. Sin motor/pesos puede revisar acceso y administración, pero no demostrar inferencia local. Coloque el GGUF en `models/asistente_python_ia_v1.gguf` y revise las instrucciones del README para Windows o Docker CPU.

Prueba sugerida: crear un archivo con una suma; en el mismo chat pedir cambiarla a resta; ejecutar ambas versiones y verificar su resultado; pedir una explicación y responder una pregunta guiada; entrar como docente y revisar la respuesta guardada. Las pruebas automáticas y las limitaciones de la entrega se registran en [validación](VALIDACION_INSTALACION_2026-10-13.md).

## Si recibió un cliente compilado

Abra `app_desktop.exe` junto con sus DLL y recursos. No necesita herramientas de desarrollo. Configure la dirección del backend del docente en Configuración. El backend debe estar disponible: localhost solamente funciona si está en esta misma computadora. El instalador no contiene servidor, datos privados ni modelos.

## Detener sin perder datos

En Flutter pulse q. En Docker ejecute `docker compose --env-file backend/.env down` desde la raíz. No añada -v a una instalación con información: borraría volúmenes. Los procesos nativos de API y web permanecen activos; identifíquelos por sus registros y puerto antes de cerrarlos.
