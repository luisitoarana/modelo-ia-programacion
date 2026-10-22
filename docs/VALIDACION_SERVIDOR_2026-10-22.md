# Preparación del servidor y cliente — 22 de octubre de 2026

## Comprobado en la laptop servidor

- Compilación Flutter Windows Release correcta, versión `1.0.0+1`, API configurada en `https://api-pythonia.aranadev.com/api/v1`.
- Instalador Inno Setup compilado correctamente, con icono del proyecto y runtime redistribuible Visual C++ x64.
- Instalación silenciosa de prueba en una carpeta local aislada: salida 0; ejecutable, recursos, manifiesto y DLL de runtime presentes.
- Copia al escritorio y SHA256 idéntico al original. Sin `.env`, bases de datos, certificados, claves privadas ni modelos en la entrega.
- Sintaxis PowerShell comprobada sin errores; configuración de ingress validada por cloudflared.
- Backend local responde e identifica PythonIA en `127.0.0.1:8765`.
- Cloudflared instalado, autorización del dominio completada, túnel nuevo `pythonia-laptop` creado y DNS `api-pythonia.aranadev.com` asociado a él.
- La configuración apunta al puerto local 8765, común a Normal y Docker. Las rutas del túnel anterior no se modificaron.

## Pendiente antes de usar estudiantes reales

- Resolver la contraseña corta del administrador antes de conectar el túnel a la API completa. La creación del DNS no conecta el servidor por sí sola.
- Iniciar el túnel y comprobar HTTPS remoto y autenticación mediante `cloudflare.ps1 -Accion Verificar`.
- Instalar y ejecutar en la segunda laptop; comprobar desde otra red registro, separación de roles, inferencia, corrección, entrada por teclado, entrega de evaluaciones y persistencia tras reiniciar.
- El backend Docker no se reconstruyó ni se migraron usuarios entre SQLite y PostgreSQL en esta preparación. Son bases independientes.
- No se ha demostrado todavía funcionamiento entre dos equipos o dos redes. Esta validación no acredita aislamiento del ejecutor frente a código hostil ni un despliegue de producción endurecido.

Pasos: [servidor y Cloudflare](SERVIDOR_CLOUDFLARE.md), [prueba en otra laptop](PRUEBA_OTRA_LAPTOP.txt).
