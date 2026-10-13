"""Regresiones de los fallos reportados: archivos largos y motor que no responde."""

from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from app.database import actualizar_esquema_desarrollo
from app.schemas.chat import EnviarMensaje
from app.services import motor_pedagogico_service as motor
from app.services.chat_service import ChatService
from app.models.conversacion import Mensaje, RolMensaje


def test_archivo_mayor_de_8000_caracteres_se_acepta_completo():
    contenido = "# archivo largo\nx = 1\n" * 1000
    assert EnviarMensaje(contenido=contenido).contenido == contenido


def test_presupuesto_reserva_salida_y_conserva_peticion_y_extremos_del_archivo():
    mensaje = ("Petición actual del estudiante: Explica este archivo\n"
               "ARCHIVO: ejemplo.py\n```python\n# INICIO\n" + "x = 1\n" * 5000 + "# FINAL\n```")
    prompt = "<|im_start|>system\nTutor breve<|im_end|>\n<|im_start|>user\n" + mensaje + "<|im_end|>\n<|im_start|>assistant\n"
    ajustado, parcial = motor._ajustar_prompt_al_contexto(prompt, 900, len)
    assert parcial
    assert len(ajustado) <= 4096 - 900 - 64
    assert "Explica este archivo" in ajustado
    assert "# INICIO" in ajustado and "# FINAL" in ajustado
    assert ajustado.count("```") == 2


def test_contexto_breve_se_conserva_sin_recortes():
    prompt = "<|im_start|>system\nTutor<|im_end|>\n<|im_start|>user\nHola<|im_end|>\n<|im_start|>assistant\n"
    assert motor._ajustar_prompt_al_contexto(prompt, 900, len) == (prompt, False)


def test_timeout_gpu_no_carga_un_segundo_motor_cpu(monkeypatch):
    monkeypatch.setattr(motor, "_LLAMA_SERVER_EXE", SimpleNamespace(exists=lambda: True))
    gpu = Mock(side_effect=motor.MotorLocalError("Tiempo agotado"))
    cpu = Mock()
    monkeypatch.setattr(motor, "_consultar_gpu_server", gpu)
    monkeypatch.setattr(motor, "obtener_motor", cpu)
    with pytest.raises(motor.MotorLocalError, match="Tiempo agotado"):
        motor.generar_respuesta("Corrige este código")
    cpu.assert_not_called()


@pytest.mark.asyncio
async def test_error_motor_se_devuelve_una_vez_y_no_reintenta_ast(monkeypatch):
    monkeypatch.setattr(motor, "esta_disponible", lambda: True)
    consulta = Mock(side_effect=motor.MotorLocalError("El motor está ocupado"))
    monkeypatch.setattr(motor, "generar_respuesta", consulta)
    respuesta, meta = await ChatService(None)._generar_respuesta(
        "Corrige este archivo\n```python\nx = 1\n```", [], proveedor_forzado="propio",
    )
    assert respuesta == "El motor está ocupado"
    assert meta["origen"] == "error_motor_local"
    consulta.assert_called_once()


@pytest.mark.asyncio
async def test_segundo_turno_con_historial_sigue_usando_prompt_del_editor(monkeypatch):
    capturados = []
    monkeypatch.setattr(motor, "_LLAMA_SERVER_EXE", SimpleNamespace(exists=lambda: True))
    monkeypatch.setattr(motor, "esta_disponible", lambda: True)
    def gpu(prompt, _max, _temp):
        capturados.append(prompt)
        return motor.ResultadoMotorLocal("```python\nprint(2)\n```", "print(2)", 10, 0.1, 100)
    monkeypatch.setattr(motor, "_consultar_gpu_server", gpu)
    actual = "Petición actual del estudiante: Corrige para mostrar 2\nCódigo actual en el editor:\n```python\nprint(1)\n```"
    historial = [
        Mensaje(rol=RolMensaje.USUARIO, contenido="Crea un programa"),
        Mensaje(rol=RolMensaje.ASISTENTE, contenido="```python\nprint(1)\n```"),
        Mensaje(rol=RolMensaje.USUARIO, contenido=actual),
    ]
    await ChatService(None)._generar_respuesta(actual, historial, proveedor_forzado="propio")
    assert "Actúa como asistente de programación dentro de un editor" in capturados[0]
    assert "[PETICIÓN ACTUAL]\n" in capturados[0]
    assert "Corrige para mostrar 2" in capturados[0]


@pytest.mark.asyncio
async def test_migracion_pregunta_conserva_filas_y_puede_repetirse():
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    try:
        async with engine.begin() as conn:
            await conn.execute(text("CREATE TABLE intentos_aprendizaje (id TEXT PRIMARY KEY)"))
            await conn.execute(text("INSERT INTO intentos_aprendizaje (id) VALUES ('previo')"))
            await conn.run_sync(actualizar_esquema_desarrollo)
            await conn.run_sync(actualizar_esquema_desarrollo)
            fila = (await conn.execute(text("SELECT id, pregunta FROM intentos_aprendizaje"))).one()
            assert fila == ("previo", None)
    finally:
        await engine.dispose()
