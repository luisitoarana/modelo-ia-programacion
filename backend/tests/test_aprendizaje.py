"""Regresiones que afectarían directamente la medición del aprendizaje."""

import pytest
from unittest.mock import AsyncMock
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.database import Base
from app.models import Usuario  # registra las tablas relacionadas en Base.metadata
from app.routes.aprendizaje import (
    IntentoCrear, listar_intentos, obtener_asignacion, registrar_intento, revisar_intentos,
)
from app.routes.herramientas import ValidarSintaxisReq, validar_sintaxis
from app.services.code_explainer_service import analizar_codigo_python
from app.services.evaluation_service import EvaluationService
from app.services.chat_service import ChatService, _ultimo_bloque_python
from app.models.conversacion import Mensaje, RolMensaje
from app.models.intento_aprendizaje import AsignacionEstudio
from app.models.usuario import RolUsuario
from app.routes.aprendizaje import RubricaDocente, calificar_intento
from app.routes.admin import listar_usuarios
from app.services.chat_service import _peticion_actual
from app.services import motor_pedagogico_service


def test_opciones_distintas_no_reciben_la_misma_nota():
    nota, _ = EvaluationService._evaluar("opcion_multiple", "A", "B", "")
    assert nota == 0.0
    assert EvaluationService._evaluar("opcion_multiple", "A", "A) válida", "")[0] == 1.0
    assert EvaluationService._evaluar("opcion_multiple", "B", "A) válida", "")[0] == 0.0


def test_peticion_actual_no_se_confunde_con_el_codigo_del_editor():
    prompt = "Petición actual del estudiante: ¿Qué es una variable?\n\nCódigo actual en el editor:\n```python\ndef funcion(): pass\n```"
    assert _peticion_actual(prompt) == "¿Qué es una variable?"


def test_prompt_local_adapta_consulta_breve_y_continuacion_sin_inferencia(monkeypatch):
    capturados = []
    def fake_gpu(prompt, _max, _temp):
        capturados.append(prompt)
        return motor_pedagogico_service.ResultadoMotorLocal("respuesta", None, 1, 0.01, 100)
    monkeypatch.setattr(motor_pedagogico_service, "_consultar_gpu_server", fake_gpu)
    motor_pedagogico_service.generar_respuesta("¿Qué es una variable?", modo_acompanamiento="con_acompanamiento")
    assert "No agregues secciones fijas" in capturados[-1]
    motor_pedagogico_service.generar_respuesta(
        "Petición actual del estudiante: Corrige esta función\nCódigo actual en el editor: x",
        modo_acompanamiento="con_acompanamiento",
    )
    assert "No repitas la respuesta anterior" in capturados[-1]


def test_codigo_con_espacios_dentro_de_literal_no_es_equivalente():
    nota, _ = EvaluationService._evaluar(
        "completar_codigo", "print('ab')", "print('a b')", ""
    )
    assert nota == 0.0
    nota_formato, _ = EvaluationService._evaluar(
        "completar_codigo", "print( 1 )", "print(1)", ""
    )
    assert nota_formato == 1.0


def test_explicacion_libre_espera_revision_docente():
    nota, mensaje = EvaluationService._evaluar("explicacion_libre", "porque...", "", "")
    assert nota == 0.0
    assert "revisión docente" in mensaje


def test_una_llamada_normal_no_es_recursion():
    analisis = analizar_codigo_python("def doble(x):\n    return x * 2\nprint(doble(4))")
    assert analisis.es_valido
    assert analisis.algoritmo_detectado != "Función recursiva"


def test_sintaxis_conserva_indentacion_original():
    analisis = analizar_codigo_python("    x = 1\nprint(x)")
    assert not analisis.es_valido


def test_comprension_y_tres_bucles_no_se_clasifican_como_constantes():
    comprension = analizar_codigo_python("dobles = [x * 2 for x in datos]")
    assert comprension.complejidad_tiempo.startswith("O(n)")
    assert comprension.complejidad_espacio.startswith("O(n)")
    cubico = analizar_codigo_python(
        "for i in range(n):\n"
        "    for j in range(n):\n"
        "        for k in range(n):\n"
        "            print(i, j, k)"
    )
    assert cubico.complejidad_tiempo.startswith("O(n^3)")


def test_continuacion_recupera_el_codigo_del_ultimo_mensaje():
    anterior = Mensaje(
        rol=RolMensaje.ASISTENTE,
        contenido="Explicación larga.\n```python\ndef saludo(nombre):\n    print(nombre)\n```",
    )
    assert _ultimo_bloque_python([anterior]) == "def saludo(nombre):\n    print(nombre)"


@pytest.mark.asyncio
async def test_parser_python_confirma_sintaxis_sin_ejecutar_el_codigo():
    valido = await validar_sintaxis(ValidarSintaxisReq(codigo="x = 1"), None)
    invalido = await validar_sintaxis(ValidarSintaxisReq(codigo="if True\n    pass"), None)
    assert valido["valido"] is True
    assert invalido["valido"] is False
    assert invalido["linea"] == 1


@pytest.mark.asyncio
async def test_intento_persiste_respuestas_y_ayudas_sin_nota_automatica():
    motor = create_async_engine("sqlite+aiosqlite:///:memory:")
    try:
        async with motor.begin() as conexion:
            await conexion.run_sync(Base.metadata.create_all)
        sesiones = async_sessionmaker(motor, expire_on_commit=False)
        async with sesiones() as sesion:
            usuario = Usuario(nombre="Estudiante", email="estudiante@example.org", password_hash="test")
            sesion.add(usuario)
            await sesion.commit()
            datos = IntentoCrear(
                leccion_id="m1_l1_variables",
                modo="con_acompanamiento",
                codigo_inicial="x = 1\nprint(x)",
                codigo_final="x = 2\nprint(x)",
                prediccion="Creo que imprime 1",
                explicacion_propia="Cambia el valor de x antes de imprimirlo.",
                pistas_usadas=1,
                duracion_segundos=25,
            )
            guardado = await registrar_intento(datos, usuario, sesion)
            registros = await listar_intentos(usuario, sesion)
            assert registros[0].id == guardado.id
            assert registros[0].prediccion == "Creo que imprime 1"
            assert registros[0].pistas_usadas == 1
            assert not hasattr(registros[0], "puntaje")
            sesion.add(AsignacionEstudio(
                usuario_id=usuario.id, condicion="sin_acompanamiento", fase="intervencion"
            ))
            await sesion.commit()
            datos.modo = "con_acompanamiento"
            control = await registrar_intento(datos, usuario, sesion)
            assert control.modo == "sin_acompanamiento"
            assert control.fase == "intervencion"
            revision = await revisar_intentos(usuario, sesion, usuario_id=usuario.id, fase="intervencion")
            assert len(revision) == 1 and revision[0]["id"] == control.id
            assert revision[0]["usuario_email"] == usuario.email
            docente = Usuario(nombre="Docente", email="docente@example.org", password_hash="test",
                              rol=RolUsuario.ADMINISTRADOR)
            sesion.add(docente)
            await sesion.commit()
            nota = await calificar_intento(
                control.id,
                RubricaDocente(comprension=4, codigo=3, casos_limite=2,
                               observaciones="Respuesta breve pero correcta."),
                docente, sesion,
            )
            assert nota["puntaje"] == 9
            revision_actualizada = await revisar_intentos(docente, sesion, usuario_id=usuario.id,
                                                          fase="intervencion")
            assert revision_actualizada[0]["revision_docente"]["puntaje"] == 9
            usuarios = await listar_usuarios(sesion, docente)
            assert any(u["email"] == usuario.email and u["fase"] == "intervencion"
                       for u in usuarios)
            assert (await obtener_asignacion(usuario, sesion))["modo_efectivo"] == "sin_acompanamiento"
            asignacion = await sesion.get(AsignacionEstudio, usuario.id)
            asignacion.fase = "post"
            servicio = ChatService(sesion)
            servicio._generar_respuesta = AsyncMock(return_value=("Bloqueado", {"origen": "bloqueado_post_test"}))
            conv = await servicio.crear_conversacion(usuario.id)
            _, respuesta = await servicio.enviar_mensaje(
                conv, "Dame la solución", modo_acompanamiento="con_acompanamiento"
            )
            assert servicio._generar_respuesta.await_args.kwargs["modo_acompanamiento"] == "bloqueado_post_test"
            assert servicio._generar_respuesta.await_args.kwargs["proveedor_forzado"] == "propio"
            assert respuesta.metadata_json["fase_estudio"] == "post"
    finally:
        await motor.dispose()
