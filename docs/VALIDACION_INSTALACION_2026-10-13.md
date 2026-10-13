# Validación de instalación — 13 de octubre de 2026

## Alcance

Trabajo realizado exclusivamente en Sistema Explicador Python IA. Se verificaron instalación y arranque nativos, configuración Docker, dependencias, autenticación, persistencia y continuidad del editor. No se generó un instalador para distribución ni se desplegó un servidor público.

## Resultados comprobados

| Comprobación | Resultado |
|---|---|
| Instalación Python desde el lanzador | Entorno propio backend/.venv; dependencias instaladas; configuración existente conservada |
| Configuración nueva y legado | Pruebas de claves aleatorias, idempotencia y conservación de conexión existente |
| Backend | 26 pruebas aprobadas, con SQLite de prueba; incluye registro, permisos, intentos, revisión y continuidad |
| Flutter | Compilación Windows debug y arranque independiente aprobados. 18 pruebas aprobadas: editor, confirmación, recuperación de error, cambio de pestaña, administrador y registro |
| API y modelo real | API temporal con SQLite aislada: login, dos turnos en una conversación y cuatro mensajes persistidos. El modelo creó calcular(a,b) con suma y la corrigió a resta |
| Archivo largo | Consulta de más de 8000 caracteres aceptada por el motor; recorte de contexto informado como análisis parcial |
| Portal web | TypeScript y compilación de producción aprobados con Next.js 16.4.0, React 19 y Tailwind 4; formulario de acceso revisado visualmente |
| Auditoría npm | Cero vulnerabilidades conocidas reportadas en las dependencias instaladas al momento de la comprobación |
| Auditoría Python | Cero vulnerabilidades conocidas reportadas después de sustituir python-jose por PyJWT y actualizar pip del entorno virtual |
| Arranque normal | API responde /health en 8765; portal responde /api/sistema en 3000. El lanzador de backend reutiliza el servicio identificado sin cerrar procesos ajenos |
| Docker | Configuración válida; imágenes construidas; PostgreSQL, backend y web arrancaron en el proyecto aislado pythonia-verificacion (puertos 18765 y 13000) |
| Publicación | Revisión de archivos candidatos: sin .env, BD, pesos, ZIP, DLL o EXE; sin patrones detectados de credenciales reales y sin archivos candidatos mayores de 5 MB |

Las pruebas HTTP de aprendizaje utilizan bases separadas de la instalación del docente. Las consultas reales utilizaron el motor local, sin llamadas a proveedores de pago.

## Correcciones de esta entrega

- Tres BAT claros: todo el sistema; backend normal/Docker; aplicación independiente.
- El sistema completo compila código Flutter vigente e inicia también la web.
- Dependencias PostgreSQL y SQLAlchemy async declaradas; versiones Python comprobadas registradas como restricciones.
- Dockerfiles dentro de backend y frontend; PostgreSQL privado, puertos del host limitados a localhost y procesos de aplicación sin privilegios.
- Se eliminó el montaje de todo el repositorio en Docker; el explorador opera en un volumen de proyectos y bloquea secretos y rutas privadas también por acceso directo.
- El backend deja de indicar disponibilidad si falla la inicialización de BD o administrador.
- Una confirmación «sí» conserva la intención de la corrección propuesta. Las explicaciones sin solicitud de cambio no reemplazan automáticamente el archivo.
- Los fallos del motor local se devuelven una vez, sin ocultarlos mediante reintentos en otras rutas.
- Actualización de dependencias web con avisos de seguridad y sustitución de la biblioteca JWT anterior. Rechazo de JWT caducados, sin firma o firmados con otra clave comprobado.
- Nuevas contraseñas de registro requieren ocho caracteres y respetan el límite de bytes de bcrypt.
- Empaquetado limitado al cliente, sin copiar carpetas del servidor con credenciales o datos. No borra entregas anteriores.

## Reproducir las comprobaciones

Desde la raíz, después de instalar dependencias:

```powershell
$env:DATABASE_URL='sqlite+aiosqlite:///:memory:'
Push-Location backend
.\.venv\Scripts\python.exe -m pytest -q
Pop-Location
Remove-Item Env:DATABASE_URL
backend\.venv\Scripts\python.exe backend/scripts/validar_instalacion.py
```

La comprobación real del chat requiere el GGUF y el motor entregados por separado. Desde app-desktop: `flutter test`. Desde frontend: `npm run typecheck`, `npm run lint`, `npm run build` y `npm audit`. Para repetir auditoría Python instala pip-audit exclusivamente en el entorno virtual y ejecuta `python -m pip_audit` con ese intérprete.

## Límites de esta validación

No acredita que el modelo resuelva todos los programas o preguntas ni que una propuesta sintácticamente válida sea correcta. No reemplaza una prueba docente del contenido ni la medición pre/post con estudiantes. La prueba real cubre suma, resta y continuidad; otras tareas necesitan casos funcionales propios.

Flutter analyze conserva avisos previos de estilo y API; no se declara una revisión estática totalmente limpia. Las pruebas Python muestran avisos de deprecación. No se ejecutó entrenamiento ni se validaron nuevamente todos los checkpoints de investigación.

No se construyó ni probó el instalador Inno Setup en una segunda computadora. Su plantilla y el empaquetado están preparados para esa fase. Tampoco se verificaron DNS, HTTPS, túneles, aislamiento de código hostil, carga multiusuario ni despliegue de producción. No se modificaron los modelos ni bases de datos existentes.

Las auditorías consultan avisos conocidos a una fecha concreta y no garantizan ausencia absoluta de vulnerabilidades. Docker aquí es un entorno local de evaluación; revise el despliegue antes de dar acceso desde Internet.

Referencias de compatibilidad: [migración oficial de Next.js 16](https://nextjs.org/docs/app/guides/upgrading/version-16) y [migración oficial de Tailwind CSS](https://tailwindcss.com/docs/upgrade-guide).
