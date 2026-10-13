from datetime import datetime, timedelta, timezone
import uuid

import jwt
import pytest

from app.config import settings
from app.services.project_explorer import ExploradorProyecto
from app.utils.helpers import JWTError, crear_access_token, decodificar_token


def test_jwt_firma_expiracion_y_algoritmo_no_se_eluden():
    token, _ = crear_access_token(usuario_id=uuid.uuid4(), email='prueba@example.org', rol='estudiante')
    assert decodificar_token(token)['rol'] == 'estudiante'
    caducado = jwt.encode({'sub': str(uuid.uuid4()), 'exp': datetime.now(timezone.utc) - timedelta(seconds=10)}, settings.secret_key, algorithm='HS256')
    falso = jwt.encode({'sub': str(uuid.uuid4())}, 'clave-del-atacante' * 3, algorithm='HS256')
    sin_firma = jwt.encode({'sub': str(uuid.uuid4())}, key='', algorithm='none')
    for inseguro in (caducado, falso, sin_firma):
        with pytest.raises(JWTError):
            decodificar_token(inseguro)


def test_explorador_bloquea_secretos_y_carpetas_privadas(tmp_path):
    explorador = ExploradorProyecto()
    explorador.raiz = tmp_path
    for ruta in ('.env.production', '.runtime/sesion.txt', '.venv/credencial.txt', 'backend/local.db', '../fuera.txt'):
        with pytest.raises(PermissionError):
            explorador._resolver_seguro(ruta)
    assert explorador._resolver_seguro('ejemplo.py') == tmp_path / 'ejemplo.py'
