"""Flujo HTTP de registro, autorización y revisión, sin tocar la BD real."""

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.database import Base, get_db
from app.main import crear_app
from app.models import Usuario
from app.models.usuario import RolUsuario
from app.utils.helpers import hash_password
from app.services.chat_service import ChatService
from app.models.conversacion import RolMensaje


@pytest.mark.asyncio
async def test_estudiante_y_docente_comparten_intentos_con_permisos_distintos(monkeypatch):
    motor = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with motor.begin() as conexion:
        await conexion.run_sync(Base.metadata.create_all)
    sesiones = async_sessionmaker(motor, expire_on_commit=False)
    async with sesiones() as sesion:
        sesion.add(Usuario(
            nombre="Docente", email="docente@example.org",
            password_hash=hash_password("clave-docente-segura"),
            rol=RolUsuario.ADMINISTRADOR,
        ))
        await sesion.commit()

    async def base_prueba():
        async with sesiones() as sesion:
            yield sesion

    app = crear_app()
    app.dependency_overrides[get_db] = base_prueba
    try:
        async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as cliente:
            alta = await cliente.post("/api/v1/auth/registro", json={
                "nombre": "Estudiante de prueba", "email": "estudiante@example.org",
                "password": "clave-estudiante-segura", "nivel_academico": "Segundo semestre",
            })
            assert alta.status_code == 201, alta.text
            usuario_id = alta.json()["id"]
            prohibida = await cliente.post("/api/v1/auth/registro", json={
                "nombre": "Intruso", "email": "intruso@example.org",
                "password": "clave-segura", "rol": "administrador",
            })
            assert prohibida.status_code == 403

            acceso = await cliente.post("/api/v1/auth/login", json={
                "email": "estudiante@example.org", "password": "clave-estudiante-segura",
            })
            assert acceso.status_code == 200
            estudiante = {"Authorization": "Bearer " + acceso.json()["access_token"]}
            assert (await cliente.get("/api/v1/admin/usuarios", headers=estudiante)).status_code == 403

            async def respuesta_prueba(self, texto, historial, **_opciones):
                numero = sum(m.rol == RolMensaje.USUARIO for m in historial)
                return f"turno {numero}: {texto}", {"origen": "prueba", "tokens": 0, "latencia": 0.0}
            monkeypatch.setattr(ChatService, "_generar_respuesta", respuesta_prueba)
            conversacion = await cliente.post("/api/v1/chat/conversaciones", headers=estudiante,
                                              json={"titulo": "Editor de código"})
            assert conversacion.status_code == 201, conversacion.text
            conv_id = conversacion.json()["id"]
            for pregunta, numero in (("Crea una función", 1), ("Ahora corrígela", 2)):
                respuesta = await cliente.post(f"/api/v1/chat/conversaciones/{conv_id}/mensajes",
                                               headers=estudiante,
                                               json={"contenido": pregunta, "proveedor": "propio"})
                assert respuesta.status_code == 200, respuesta.text
                assert respuesta.json()["mensaje_asistente"]["contenido"].startswith(f"turno {numero}")
            hilo = await cliente.get(f"/api/v1/chat/conversaciones/{conv_id}", headers=estudiante)
            assert hilo.status_code == 200
            assert len(hilo.json()["mensajes"]) == 4
            archivo_largo = "# Archivo del explorador\nx = 1\n" * 1200
            largo_chat = await cliente.post(f"/api/v1/chat/conversaciones/{conv_id}/mensajes",
                                            headers=estudiante,
                                            json={"contenido": archivo_largo, "proveedor": "propio"})
            assert largo_chat.status_code == 200, largo_chat.text
            assert largo_chat.json()["mensaje_usuario"]["contenido"] == archivo_largo.strip()

            intento = await cliente.post("/api/v1/aprendizaje/intentos", headers=estudiante, json={
                "leccion_id": "m1_l1_variables", "modo": "con_acompanamiento",
                "pregunta": "¿Qué valor tiene x al final?",
                "codigo_inicial": "x = 1", "codigo_final": "x = 2",
                "prediccion": "2", "explicacion_propia": "x cambia de valor.",
                "pistas_usadas": 1, "duracion_segundos": 45,
            })
            assert intento.status_code == 201, intento.text
            intento_id = intento.json()["id"]
            larga = await cliente.post("/api/v1/aprendizaje/intentos", headers=estudiante, json={
                "leccion_id": "m1_l1_variables", "modo": "con_acompanamiento",
                "codigo_inicial": "x = 1", "codigo_final": "x = 2",
                "prediccion": "Creo que imprime 2", "explicacion_propia": "Porque cambia x. " * 250,
                "pistas_usadas": 0, "duracion_segundos": 90,
            })
            assert larga.status_code == 201, larga.text

            admin_login = await cliente.post("/api/v1/auth/login", json={
                "email": "docente@example.org", "password": "clave-docente-segura",
            })
            assert admin_login.status_code == 200
            docente = {"Authorization": "Bearer " + admin_login.json()["access_token"]}
            usuarios = await cliente.get("/api/v1/admin/usuarios", headers=docente)
            assert usuarios.status_code == 200, usuarios.text
            assert any(u["id"] == usuario_id for u in usuarios.json())
            asignar = await cliente.put(
                f"/api/v1/aprendizaje/asignaciones/{usuario_id}", headers=docente,
                json={"condicion": "sin_acompanamiento", "fase": "intervencion"},
            )
            assert asignar.status_code == 200, asignar.text
            assert (await cliente.get("/api/v1/aprendizaje/asignacion", headers=estudiante)).json()["modo_efectivo"] == "sin_acompanamiento"
            revision = await cliente.put(
                f"/api/v1/aprendizaje/investigacion/intentos/{intento_id}/revision",
                headers=docente,
                json={"comprension": 4, "codigo": 3, "casos_limite": 2,
                      "observaciones": "Breve y correcta; la longitud no afecta la nota."},
            )
            assert revision.status_code == 200, revision.text
            assert revision.json()["puntaje"] == 9
            bandeja = await cliente.get("/api/v1/aprendizaje/investigacion/intentos", headers=docente)
            assert bandeja.status_code == 200, bandeja.text
            assert any(i["id"] == intento_id and i["revision_docente"]["puntaje"] == 9
                       for i in bandeja.json())
            assert next(i for i in bandeja.json() if i["id"] == intento_id)["pregunta"] == "¿Qué valor tiene x al final?"
            pagina1 = await cliente.get("/api/v1/aprendizaje/investigacion/intentos?limite=1&offset=0", headers=docente)
            pagina2 = await cliente.get("/api/v1/aprendizaje/investigacion/intentos?limite=1&offset=1", headers=docente)
            assert len(pagina1.json()) == len(pagina2.json()) == 1
            assert pagina1.json()[0]["id"] != pagina2.json()[0]["id"]
            assert (await cliente.get("/api/v1/aprendizaje/investigacion/intentos", headers=estudiante)).status_code == 403
            assert (await cliente.put("/api/v1/auth/clave", headers=docente,
                                      json={"actual": "incorrecta", "nueva": "clave-nueva-segura"})).status_code == 400
            assert (await cliente.put("/api/v1/auth/clave", headers=docente,
                                      json={"actual": "clave-docente-segura", "nueva": "clave-nueva-segura"})).status_code == 200
            assert (await cliente.post("/api/v1/auth/login", json={
                "email": "docente@example.org", "password": "clave-docente-segura",
            })).status_code == 401
            assert (await cliente.post("/api/v1/auth/login", json={
                "email": "docente@example.org", "password": "clave-nueva-segura",
            })).status_code == 200
    finally:
        app.dependency_overrides.clear()
        await motor.dispose()
