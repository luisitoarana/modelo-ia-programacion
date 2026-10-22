"""Reglas del estudio en servidor: no dependen de ocultar botones."""
from uuid import UUID
from fastapi import Depends, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession
from app.config import settings
from app.database import get_db
from app.models.usuario import Usuario, RolUsuario
from app.models.intento_aprendizaje import AsignacionEstudio
from app.utils.helpers import decodificar_token, JWTError
from app.services.estudio_service import configuracion


async def proteger_estudio(request: Request, db: AsyncSession = Depends(get_db)):
    ruta = request.url.path.removeprefix(settings.api_v1_prefix)
    superficies = ('/chat', '/ai', '/agente', '/mcp', '/curriculo', '/proyecto',
                   '/herramientas', '/knowledge', '/knowledge-gen', '/rag', '/evaluation', '/ml', '/aprendizaje/intentos')
    if not any(ruta == p or ruta.startswith(p + '/') for p in superficies):
        return
    autorizacion = request.headers.get('Authorization', '')
    if not autorizacion.startswith('Bearer '):
        raise HTTPException(401, 'Se requiere iniciar sesión.')
    try:
        uid = UUID(decodificar_token(autorizacion[7:])['sub'])
    except (JWTError, ValueError, KeyError, TypeError) as exc:
        raise HTTPException(401, 'Sesión inválida.') from exc
    u = await db.get(Usuario, uid)
    if not u or not u.activo:
        raise HTTPException(401, 'Sesión inválida.')
    if u.rol != RolUsuario.ESTUDIANTE:
        return
    a = await db.get(AsignacionEstudio, uid)
    if not a:
        if (await configuracion(db))['estudio_activo']:
            raise HTTPException(403, 'Estudio activo: el docente debe asignar tu grupo y pretest antes de usar ayuda.')
        return
    if ruta in ('/ai/modelo-estado', '/chat/proveedores'):
        return
    if a.fase in ('pre', 'post'):
        # El chat normal ya devuelve un aviso sin invocar ningún modelo.
        if ruta.endswith('/mensajes') and request.method == 'POST':
            return
        raise HTTPException(403, 'Evaluación individual: IA, historial, ejecución, pistas y materiales están bloqueados.')
    if ruta == '/herramientas/buscar-web':
        raise HTTPException(403, 'La búsqueda externa no está habilitada durante el estudio.')
    if a.condicion == 'sin_acompanamiento' and not ruta.startswith('/chat') and not ruta.startswith('/herramientas'):
        raise HTTPException(403, 'Generación directa: utiliza el chat del editor, sin explicaciones ni soluciones guiadas.')
    # Todo estudiante asignado usa la misma vía de generación y el mismo motor.
    if ruta.startswith(('/agente', '/mcp', '/ai/')) and ruta != '/ai/modelo-estado':
        raise HTTPException(403, 'En el estudio utiliza el chat o editor con el motor fijado por el servidor.')
