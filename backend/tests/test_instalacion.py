import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "preparar_entorno", Path(__file__).resolve().parents[1] / "scripts" / "preparar_entorno.py",
)
entorno = importlib.util.module_from_spec(spec)
spec.loader.exec_module(entorno)


def test_instalacion_nueva_genera_secretos_y_es_idempotente(tmp_path):
    backend = tmp_path / "backend"
    backend.mkdir()
    ruta = entorno.preparar(backend)
    inicial = ruta.read_text()
    datos = dict(linea.split("=", 1) for linea in inicial.splitlines() if "=" in linea)
    assert len(datos["SECRET_KEY"]) >= 32
    assert datos["ADMIN_PASSWORD"] != "admin12345"
    assert datos["POSTGRES_PASSWORD"] != datos["ADMIN_PASSWORD"]
    assert datos["DATABASE_URL"].startswith("sqlite+aiosqlite:")
    entorno.preparar(backend)
    assert ruta.read_text() == inicial


def test_conserva_configuracion_y_conexion_preexistentes(tmp_path):
    backend = tmp_path / "backend"
    backend.mkdir()
    legado = "SECRET_KEY=" + "s" * 40 + "\nDATABASE_URL=mysql+aiomysql://usuario@localhost/base\n"
    (tmp_path / ".env").write_text(legado)
    ruta = entorno.preparar(backend)
    assert ruta.read_text().startswith(legado)
    # La configuración propia del backend tiene prioridad, aunque cambie el legado.
    (tmp_path / ".env").write_text("DATABASE_URL=otra\n")
    entorno.preparar(backend)
    assert ruta.read_text().startswith(legado)
