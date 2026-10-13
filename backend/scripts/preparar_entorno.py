"""Configuración inicial local; conserva credenciales y BD existentes."""
from pathlib import Path
import secrets


def preparar(backend: Path) -> Path:
    destino = backend / ".env"
    legado = backend.parent / ".env"
    if not destino.exists():
        if legado.exists():
            destino.write_bytes(legado.read_bytes())
        else:
            destino.write_text(
                "APP_ENV=development\nAPP_DEBUG=true\n"
                "APP_HOST=127.0.0.1\nAPP_PORT=8765\n"
                f"SECRET_KEY={secrets.token_hex(32)}\n"
                "ADMIN_EMAIL=admin@explicador.com\n"
                f"ADMIN_PASSWORD={secrets.token_urlsafe(24)}\n"
                "ADMIN_NOMBRE=Administrador\n"
                "DATABASE_URL=sqlite+aiosqlite:///./local.db\n"
                "CORS_ORIGINS=http://localhost:3000,http://127.0.0.1:3000\n"
                "MODEL_ENABLED=true\n", encoding="utf-8",
            )
    contenido = destino.read_text(encoding="utf-8-sig")
    adicionales = {"POSTGRES_USER": "explicador", "POSTGRES_PASSWORD": secrets.token_hex(24), "POSTGRES_DB": "sistema_explicador"}
    existentes = {linea.partition("=")[0].strip() for linea in contenido.splitlines()}
    faltantes = [f"{k}={v}" for k, v in adicionales.items() if k not in existentes]
    if faltantes:
        with destino.open("a", encoding="utf-8") as archivo:
            archivo.write("\n# Conexion privada para Docker\n" + "\n".join(faltantes) + "\n")
    return destino


if __name__ == "__main__":
    ruta = preparar(Path(__file__).resolve().parents[1])
    print(f"[OK] Configuracion conservada/preparada en {ruta}")
    print("[INFO] Credenciales iniciales: ADMIN_EMAIL y ADMIN_PASSWORD en ese archivo privado.")
