"""Regresiones de los fallos reportados: archivos largos y motor que no responde."""

from types import SimpleNamespace
from unittest.mock import Mock

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from app.database import actualizar_esquema_desarrollo
from app.schemas.chat import EnviarMensaje
from app.services import motor_pedagogico_service as motor
from app.services.chat_service import ChatService, _codigo_directo
from app.models.conversacion import Mensaje, RolMensaje


def test_importacion_inexistente_se_detecta_sin_ejecutar_el_programa():
    with pytest.raises(ValueError, match='ImportError: math no contiene round'):
        _codigo_directo('```python\nfrom math import round\nprint(round(1.67))\n```', None)
    assert 'round(1.67)' in _codigo_directo('```python\nprint(round(1.67))\n```', None)


def test_no_ignora_una_entrada_que_se_pidio_mostrar():
    with pytest.raises(ValueError, match='Se pidió mostrar nombre'):
        _codigo_directo('```python\nnombre=input("Nombre: ")\nprint(22)\n```', None, 'Pide el nombre y muestra el nombre y la edad.')


@pytest.mark.asyncio
async def test_andamiaje_ancla_codigo_del_estudiante_aunque_modelo_no_lo_repita(monkeypatch):
    monkeypatch.setattr(motor, 'esta_disponible', lambda: True)
    monkeypatch.setattr(motor, 'generar_respuesta', lambda *a, **k: motor.ResultadoMotorLocal(
        'La variable almacena el dato y print lo muestra.', None, 10, .1, 100))
    texto, meta = await ChatService(None)._generar_respuesta(
        'Explica mi intento:\n```python\nedad=20\nprint(edad)\n```', [],
        proveedor_forzado='propio', modo_acompanamiento='con_acompanamiento')
    assert meta['pregunta_origen']=='ast_del_codigo'
    assert '`edad`' in texto and 'entero (int)' in texto


@pytest.mark.asyncio
async def test_explicar_no_sustituye_codigo_del_estudiante_por_entrada_inventada(monkeypatch):
    monkeypatch.setattr(motor, 'esta_disponible', lambda: True)
    inventado = 'edad=input("Edad: ")\nprint(edad)'
    monkeypatch.setattr(motor, 'generar_respuesta', lambda *a, **k: motor.ResultadoMotorLocal(
        'Usa input para pedir la edad.\n```python\n'+inventado+'\n```', inventado, 10, .1, 100))
    texto, meta = await ChatService(None)._generar_respuesta(
        'Petición actual del estudiante: Explica mi intento sin modificar el código.\n```python\nedad=20\nprint(edad)\n```',
        [], proveedor_forzado='propio', modo_acompanamiento='con_acompanamiento')
    assert 'input(' not in texto
    assert 'int (entero)' in texto and 'Pregunta sobre este código' in texto
    assert meta['explicacion_origen']=='ast_por_cambio_no_solicitado'


@pytest.mark.asyncio
@pytest.mark.parametrize('reparacion_valida', [True, False])
async def test_generacion_directa_repara_sintaxis_una_vez_sin_andamiaje(monkeypatch, reparacion_valida):
    monkeypatch.setattr(motor, 'esta_disponible', lambda: True)
    def resultado(codigo):
        return motor.ResultadoMotorLocal('```python\n'+codigo+'\n```', codigo, 10, .1, 100)
    consulta = Mock(side_effect=[resultado('print('), resultado('print(2)' if reparacion_valida else 'print(')])
    monkeypatch.setattr(motor, 'generar_respuesta', consulta)
    respuesta, meta = await ChatService(None)._generar_respuesta(
        'Petición actual del estudiante: genera la corrección\nCódigo actual en el editor:\n```python\nprint(1)\n```',
        [], proveedor_forzado='propio', modo_acompanamiento='sin_acompanamiento')
    assert consulta.call_count == 2
    assert 'print(1)' in consulta.call_args.args[0]
    assert '[REPARACIÓN DE LA RESPUESTA]' in consulta.call_args.args[0]
    assert all(c.kwargs['modo_acompanamiento']=='sin_acompanamiento' for c in consulta.call_args_list)
    if reparacion_valida:
        assert respuesta == '```python\nprint(2)\n```'
        assert meta['tokens'] == 20
    else:
        assert meta['origen']=='error_generacion_directa'
        assert 'archivo se conserva' in respuesta.lower()


def test_rechaza_nota_indefinida_y_respeta_ambitos_validos():
    with pytest.raises(ValueError, match="undefined name 'nota'"):
        _codigo_directo('```python\nedad=25\nif edad>=18 and nota>=7:\n    print("Aprobado")\n```', None)
    correcto = 'def doble(n):\n    return n*2\nvalores=[doble(x) for x in range(3)]\nprint(valores)'
    assert 'def doble(n)' in _codigo_directo('```python\n'+correcto+'\n```', None)


def test_nameerror_no_se_oculta_con_una_nota_inventada():
    with pytest.raises(ValueError, match='No se conoce el dato real nota'):
        _codigo_directo('```python\nnota=7.5\nprint(nota)\n```', None, "Corrige NameError: name 'nota' is not defined")
    assert 'nota = 8' in _codigo_directo('```python\nnota=8\nprint(nota)\n```', None, "Corrige NameError: name 'nota' is not defined. Usa nota = 8.")


@pytest.mark.asyncio
async def test_nueva_peticion_descarta_codigo_e_historial_de_otra_tarea(monkeypatch):
    monkeypatch.setattr(motor, 'esta_disponible', lambda: True)
    consulta=Mock(return_value=motor.ResultadoMotorLocal('```python\nprint("Luis")\n```', 'print("Luis")', 10, .1, 100))
    monkeypatch.setattr(motor, 'generar_respuesta', consulta)
    pedido='[PETICION_USUARIO]\nImprime el nombre Luis.\nNo hagas sumas.\n[/PETICION_USUARIO]\n[EDITOR_OPERACION:crear]'
    historial=[Mensaje(rol=RolMensaje.USUARIO,contenido='Crea una suma'),
               Mensaje(rol=RolMensaje.ASISTENTE,contenido='```python\nSUMA_ANTERIOR=100+200\nprint(SUMA_ANTERIOR)\n```'),
               Mensaje(rol=RolMensaje.USUARIO,contenido=pedido)]
    respuesta,_=await ChatService(None)._generar_respuesta(pedido,historial,proveedor_forzado='propio',modo_acompanamiento='sin_acompanamiento')
    assert 'SUMA_ANTERIOR' not in consulta.call_args.args[0]
    assert 'Crea una suma' not in consulta.call_args.args[0]
    assert 'Imprime el nombre Luis.\nNo hagas sumas.' in consulta.call_args.args[0]
    assert 'Luis' in respuesta


@pytest.mark.asyncio
async def test_correccion_de_nota_repetida_se_rechaza_en_vez_de_aceptar_mismo_error(monkeypatch):
    monkeypatch.setattr(motor, 'esta_disponible', lambda: True)
    codigo='edad=25\nif edad>=18 and nota>=7:\n    print("Aprobado")'
    consulta=Mock(return_value=motor.ResultadoMotorLocal('```python\n'+codigo+'\n```', codigo, 10,.1,100))
    monkeypatch.setattr(motor,'generar_respuesta',consulta)
    texto,meta=await ChatService(None)._generar_respuesta(
        'Petición actual del estudiante: Corrige NameError nota\nCódigo actual en el editor:\n```python\n'+codigo+'\n```',
        [],proveedor_forzado='propio',modo_acompanamiento='sin_acompanamiento')
    assert consulta.call_count==2
    assert "undefined name 'nota'" in consulta.call_args.args[0]
    assert meta['origen']=='error_generacion_directa'
    assert '```' not in texto and 'nota' in texto


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
