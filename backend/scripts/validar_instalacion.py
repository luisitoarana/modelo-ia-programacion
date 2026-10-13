"""Arranca API real con SQLite temporal y comprueba dos turnos del motor local.

No modifica usuarios ni la base existente; no usa proveedores de pago.
"""
import ast
import json
import os
from pathlib import Path
import re
import secrets
import socket
import subprocess
import sys
import tempfile
import time

import httpx


def validar():
    backend = Path(__file__).resolve().parents[1]
    with socket.socket() as puerto:
        puerto.bind(("127.0.0.1", 0))
        numero = puerto.getsockname()[1]
    with tempfile.TemporaryDirectory(prefix="pythonia-verificacion-") as carpeta:
        env = os.environ.copy()
        clave = secrets.token_urlsafe(24)
        env.update(DATABASE_URL=f"sqlite+aiosqlite:///{Path(carpeta, 'prueba.db').as_posix()}",
                   SECRET_KEY=secrets.token_hex(32), APP_ENV="development",
                   ADMIN_EMAIL="docente@example.org", ADMIN_PASSWORD=clave)
        with Path(carpeta, "backend.log").open("w") as registro:
            proceso = subprocess.Popen([sys.executable, "-m", "uvicorn", "app.main:app",
                                        "--host", "127.0.0.1", "--port", str(numero)],
                                       cwd=backend, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            # El motor GPU puede crear un subproceso: no heredar el descriptor del registro.
            registro.close()
            try:
                with httpx.Client(base_url=f"http://127.0.0.1:{numero}", timeout=90) as cliente:
                    for _ in range(80):
                        if proceso.poll() is not None:
                            raise RuntimeError("API no arranco; revise dependencias y configuración")
                        try:
                            cliente.get("/health").raise_for_status()
                            break
                        except httpx.HTTPError:
                            time.sleep(0.25)
                    else:
                        raise RuntimeError("API no respondio a tiempo")
                    login = cliente.post("/api/v1/auth/login", json={"email": "docente@example.org", "password": clave})
                    login.raise_for_status()
                    cliente.headers["Authorization"] = "Bearer " + login.json()["access_token"]
                    conversacion = cliente.post("/api/v1/chat/conversaciones", json={"titulo": "Verificacion aislada"})
                    conversacion.raise_for_status()
                    identificador = conversacion.json()["id"]
                    codigos = []
                    for pedido, operador in [("Crea la función calcular(a, b) que devuelva a + b.", ast.Add),
                                             ("Corrige calcular(a, b) para devolver a - b. Conserva el nombre y devuelve el archivo completo.", ast.Sub)]:
                        texto = "Petición actual del estudiante: " + pedido
                        if codigos:
                            texto += "\nCódigo actual en el editor (calcular.py):\n```python\n" + codigos[-1] + "\n```"
                        respuesta = cliente.post(f"/api/v1/chat/conversaciones/{identificador}/mensajes",
                                                 json={"contenido": texto, "proveedor": "propio"})
                        respuesta.raise_for_status()
                        contenido = respuesta.json()["mensaje_asistente"]["contenido"]
                        bloques = re.findall(r"```(?:python|py)\s*\n(.*?)```", contenido, re.S)
                        assert bloques, "El motor no devolvió código Python"
                        codigo = bloques[0].strip()
                        arbol = ast.parse(codigo)
                        assert any(isinstance(n, ast.BinOp) and isinstance(n.op, operador) for n in ast.walk(arbol))
                        # No ejecutamos código arbitrario del modelo: verificamos el AST esperado.
                        codigos.append(codigo)
                    hilo = cliente.get(f"/api/v1/chat/conversaciones/{identificador}")
                    hilo.raise_for_status()
                    assert len(hilo.json()["mensajes"]) == 4
                    print(json.dumps({"api_real": "ok", "login": "ok", "turnos": 2,
                                      "historial_persistido": 4, "codigo": codigos}, ensure_ascii=False))
            finally:
                proceso.terminate()
                try:
                    proceso.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proceso.kill()
                    proceso.wait()


if __name__ == "__main__":
    validar()
