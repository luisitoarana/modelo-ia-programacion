# Instalación del sistema

La instalación vigente está descrita en el [README](../README.md#instalar-e-iniciar) y en la [guía del jurado](INSTALACION_JURADO.md).

Los tres BAT instalan dependencias del componente solicitado y arrancan desde el código actual. Backend: Python aislado en backend/.venv y configuración backend/.env; escritorio: Flutter; web: npm ci. Docker Compose inicia PostgreSQL y API, y añade web para el sistema completo.

Consulte [validación de esta entrega](VALIDACION_INSTALACION_2026-10-13.md) para las versiones comprobadas, resultados y limitaciones.
