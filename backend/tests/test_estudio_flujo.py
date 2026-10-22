"""Recorrido experimental completo: dos grupos, formas paralelas y revisión humana."""
from types import SimpleNamespace
import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
from app.database import Base, get_db
from app.main import crear_app
from app.models.usuario import Usuario, RolUsuario
from app.utils.helpers import hash_password
from app.services.estudio_service import BANCO
from app.services import motor_pedagogico_service as motor
from app.services.chat_service import ChatService


@pytest.fixture
async def prueba():
    engine = create_async_engine('sqlite+aiosqlite:///:memory:')
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    sesiones = async_sessionmaker(engine, expire_on_commit=False)
    async with sesiones() as s:
        for nombre, rol in [('profesor', RolUsuario.ADMINISTRADOR), ('evaluador', RolUsuario.INVESTIGADOR),
                            ('directo', RolUsuario.ESTUDIANTE), ('andamiaje', RolUsuario.ESTUDIANTE)]:
            s.add(Usuario(nombre=nombre, email=f'{nombre}@example.org', rol=rol, password_hash=hash_password('clave-prueba-segura')))
        await s.commit()
    async def db():
        async with sesiones() as s:
            yield s
    app = crear_app()
    app.dependency_overrides[get_db] = db
    async with AsyncClient(transport=ASGITransport(app=app), base_url='http://test') as c:
        usuarios = {}
        for nombre in ['profesor', 'evaluador', 'directo', 'andamiaje']:
            login = await c.post('/api/v1/auth/login', json={'email':f'{nombre}@example.org', 'password':'clave-prueba-segura'})
            h = {'Authorization':'Bearer '+login.json()['access_token']}
            perfil = (await c.get('/api/v1/auth/yo', headers=h)).json()
            usuarios[nombre] = (h, perfil['id'])
        yield c, usuarios
    app.dependency_overrides.clear()
    await engine.dispose()


@pytest.mark.asyncio
async def test_pre_intervencion_post_ambos_grupos_y_revision(prueba):
    c, usuarios = prueba
    profesor = usuarios['profesor'][0]
    cfg = dict(estudio_activo=True, pre_abierto=True, post_abierto=True, practica_guiada=False, preguntas_activas=[p['id'] for p in BANCO])
    assert (await c.put('/api/v1/estudio/configuracion', headers=profesor, json=cfg)).status_code == 200
    pretests = {}
    for nombre, grupo in [('directo','sin_acompanamiento'), ('andamiaje','con_acompanamiento')]:
        h, uid = usuarios[nombre]
        assert (await c.put('/api/v1/estudio/configuracion', headers=h, json=cfg)).status_code == 403
        assert (await c.put(f'/api/v1/aprendizaje/asignaciones/{uid}', headers=profesor,
                            json={'fase':'pre','condicion':grupo})).status_code == 200
        for url in ['/api/v1/curriculo/modulos', '/api/v1/mcp/tools', '/api/v1/chat/conversaciones']:
            assert (await c.get(url, headers=h)).status_code == 403
        for url in ['/api/v1/ai/preguntar-modelo','/api/v1/agente/consultar','/api/v1/herramientas/ejecutar-python']:
            assert (await c.post(url, headers=h, json={})).status_code == 403
        iniciar = await c.post('/api/v1/estudio/iniciar', headers=h, json={})
        assert iniciar.status_code == 200, iniciar.text
        e = iniciar.json()
        assert len(e['preguntas']) == 6 and {p['modulo'] for p in e['preguntas']} == {1,2,3}
        assert (await c.post('/api/v1/estudio/iniciar', headers=h, json={})).json()['id'] == e['id']
        assert (await c.put(f'/api/v1/aprendizaje/asignaciones/{uid}', headers=profesor,
                            json={'fase':'intervencion','condicion':grupo})).status_code == 409
        # No se exige acierto ni respuesta larga. Cinco preguntas vacías también se conservan.
        borrador = await c.put(f"/api/v1/estudio/entregas/{e['id']}", headers=h, json={
            'respuestas':{'m1_1':{'codigo':"print('Ana')", 'explicacion':'Muestra Ana.'}}, 'revision':e['revision']})
        assert borrador.status_code == 200, borrador.text
        assert (await c.put(f"/api/v1/estudio/entregas/{e['id']}", headers=h,
                            json={'respuestas':{},'revision':e['revision']})).status_code == 409
        enviada = await c.put(f"/api/v1/estudio/entregas/{e['id']}", headers=h,
                             json={'respuestas':{},'revision':borrador.json()['revision'],'finalizar':True})
        assert enviada.status_code == 200, enviada.text
        pretests[nombre] = enviada.json()
        assert len(pretests[nombre]['respuestas']) == 6
        assert pretests[nombre]['respuestas']['m1_2']['sin_responder'] is True
        assert 'revisiones' not in pretests[nombre] and 'puntaje' not in pretests[nombre]
        assert (await c.put(f"/api/v1/estudio/entregas/{e['id']}", headers=h,
                            json={'respuestas':{},'revision':enviada.json()['revision']})).status_code == 409
        assert (await c.put(f'/api/v1/aprendizaje/asignaciones/{uid}', headers=profesor,
                            json={'fase':'intervencion','condicion':grupo})).status_code == 200
        datos = (await c.get('/api/v1/estudio/actual', headers=h)).json()
        assert len(datos['tareas']) == 6
        modulos = await c.get('/api/v1/curriculo/modulos', headers=h)
        assert modulos.status_code == (403 if nombre=='directo' else 200)
    assert pretests['directo']['preguntas'] == pretests['andamiaje']['preguntas']
    # Las selecciones posteriores no alteran el instrumento ni reducen arbitrariamente el postest.
    cfg['preguntas_activas'] = ['m1_1','m2_1','m3_1']
    assert (await c.put('/api/v1/estudio/configuracion', headers=profesor, json=cfg)).status_code == 200
    for nombre, grupo in [('directo','sin_acompanamiento'), ('andamiaje','con_acompanamiento')]:
        h, uid = usuarios[nombre]
        assert (await c.put(f'/api/v1/aprendizaje/asignaciones/{uid}', headers=profesor,
                            json={'fase':'post','condicion':grupo})).status_code == 200
        post = (await c.post('/api/v1/estudio/iniciar', headers=h, json={})).json()
        assert (await c.put(f"/api/v1/estudio/entregas/{pretests[nombre]['id']}", headers=h,
                            json={'respuestas':{},'revision':pretests[nombre]['revision'],'finalizar':True})).status_code == 403
        assert (await c.put(f'/api/v1/aprendizaje/asignaciones/{uid}', headers=profesor,
                            json={'fase':'pre','condicion':grupo})).status_code == 409
        assert len(post['preguntas']) == 6
        for a,b in zip(pretests[nombre]['preguntas'], post['preguntas']):
            assert a['id'] == b['id'] and a['consigna'] != b['consigna']
        assert (await c.put(f"/api/v1/estudio/entregas/{post['id']}", headers=h,
                            json={'respuestas':{},'revision':post['revision'],'finalizar':True})).status_code == 200
        # Otro alumno no puede sobrescribir entregas ajenas ni calificarlas.
        assert (await c.put(f"/api/v1/estudio/entregas/{post['id']}", headers=usuarios['evaluador'][0],
                            json={'respuestas':{},'revision':1})).status_code == 404
        rubrica = dict(comprension=2,codigo=2,casos_limite=1,observaciones='Revisión humana de prueba')
        for entrega in (pretests[nombre], post):
            for p in entrega['preguntas']:
                if entrega is post:
                    rubrica = dict(comprension=3,codigo=3,casos_limite=1,observaciones='Revisión de prueba; no es una nota automática')
                respuesta = await c.put(f"/api/v1/estudio/docente/entregas/{entrega['id']}/preguntas/{p['id']}",
                                        headers=usuarios['evaluador'][0], json=rubrica)
                assert respuesta.status_code == 200, respuesta.text
        assert (await c.get('/api/v1/estudio/docente/resumen', headers=h)).status_code == 403
        cambiar = await c.put(f'/api/v1/aprendizaje/asignaciones/{uid}', headers=profesor,
                             json={'fase':'post','condicion':'con_acompanamiento' if nombre=='directo' else 'sin_acompanamiento'})
        assert cambiar.status_code == 409
    resultados = (await c.get('/api/v1/estudio/docente/resumen', headers=profesor)).json()
    assert len(resultados['entregas']) == 4
    for u in resultados['participantes']:
        assert u['comparacion']['pre_porcentaje'] == 50
        assert u['comparacion']['post_porcentaje'] == 70
        assert u['comparacion']['cambio_puntos_porcentuales'] == 20


@pytest.mark.asyncio
async def test_evaluacion_cerrada_y_preguntas_invalidas(prueba):
    c,u = prueba
    h,uid = u['directo']
    await c.put(f'/api/v1/aprendizaje/asignaciones/{uid}', headers=u['profesor'][0],
                json={'fase':'pre','condicion':'sin_acompanamiento'})
    assert (await c.post('/api/v1/estudio/iniciar', headers=h,json={})).status_code == 403
    assert (await c.put('/api/v1/estudio/configuracion', headers=u['profesor'][0],json={
        'pre_abierto':True,'post_abierto':False,'practica_guiada':True,'preguntas_activas':['m1_1']})).status_code == 422


@pytest.mark.asyncio
async def test_generacion_directa_no_expone_expansion_pedagogica(monkeypatch):
    monkeypatch.setattr(motor, 'esta_disponible', lambda: True)
    monkeypatch.setattr(motor, 'generar_respuesta', lambda *a,**k: motor.ResultadoMotorLocal(
        'Propósito y pista didáctica\n```python\nnombre = "Ana"\nprint(nombre)\n```\nPregunta de reflexión',
        'nombre = "Ana"\nprint(nombre)', 20, 0.1, 200))
    respuesta,meta = await ChatService(None)._generar_respuesta('Imprime Ana',[],proveedor_forzado='propio',modo_acompanamiento='sin_acompanamiento')
    import ast
    assert respuesta.startswith('```python\n') and respuesta.endswith('```')
    assert 'Propósito' not in respuesta and 'reflexión' not in respuesta
    assert ast.dump(ast.parse(respuesta.removeprefix('```python\n').removesuffix('\n```'))) == ast.dump(ast.parse('nombre = "Ana"\nprint(nombre)'))
    assert meta['proveedor']=='propio'


@pytest.mark.asyncio
async def test_estudio_activo_impide_ayuda_antes_de_asignar_y_docente_no_es_participante(prueba):
    c,u = prueba
    profesor = u['profesor'][0]
    cfg = dict(estudio_activo=True,pre_abierto=True,post_abierto=False,practica_guiada=True,preguntas_activas=[p['id'] for p in BANCO])
    await c.put('/api/v1/estudio/configuracion',headers=profesor,json=cfg)
    h,uid = u['directo']
    assert (await c.get('/api/v1/aprendizaje/asignacion',headers=h)).json()['pendiente_asignacion'] is True
    assert (await c.post('/api/v1/chat/conversaciones',headers=h,json={'titulo':'Intento antes del pre'})).status_code == 403
    assert (await c.put(f'/api/v1/estudio/docente/autorizar/{uid}',headers=u['evaluador'][0],json={})).status_code == 403
    assert (await c.put(f'/api/v1/estudio/docente/autorizar/{uid}',headers=profesor,json={})).status_code == 200
    assert (await c.get('/api/v1/auth/yo',headers=h)).json()['rol'] == 'investigador'
    assert (await c.post('/api/v1/estudio/iniciar',headers=h,json={})).status_code == 403
    alta = await c.post('/api/v1/auth/registro',json={'nombre':'Demostración','email':'demo.estudiante@example.org','password':'DemoPythonIA2026!'})
    assert alta.status_code == 201
    assert (await c.put(f"/api/v1/estudio/docente/autorizar/{alta.json()['id']}",headers=profesor,json={})).status_code == 409


@pytest.mark.asyncio
async def test_cerrar_fase_preserva_borrador_y_no_admite_notas_antes_de_entregar(prueba):
    c,u=prueba
    h,uid=u['directo']; profesor=u['profesor'][0]
    cfg=dict(pre_abierto=True,post_abierto=False,practica_guiada=False,preguntas_activas=[p['id'] for p in BANCO])
    await c.put('/api/v1/estudio/configuracion',headers=profesor,json=cfg)
    await c.put(f'/api/v1/aprendizaje/asignaciones/{uid}',headers=profesor,json={'fase':'pre','condicion':'sin_acompanamiento'})
    e=(await c.post('/api/v1/estudio/iniciar',headers=h,json={})).json()
    assert (await c.put(f"/api/v1/estudio/docente/entregas/{e['id']}/preguntas/m1_1",headers=profesor,
                        json={'comprension':4,'codigo':4,'casos_limite':2})).status_code == 409
    cfg['pre_abierto']=False
    await c.put('/api/v1/estudio/configuracion',headers=profesor,json=cfg)
    assert (await c.put(f"/api/v1/estudio/entregas/{e['id']}",headers=h,json={'respuestas':{},'revision':e['revision']})).status_code == 403
    actual=(await c.get('/api/v1/estudio/actual',headers=h)).json()
    assert actual['entrega']['estado']=='borrador' and actual['entrega']['respuestas']=={}


def test_cambio_sin_dividir_por_pre_cero_y_sin_inventar_notas():
    from app.services.estudio_service import comparar
    def e(nota):
        return SimpleNamespace(estado='enviado', preguntas=[{'id':'m1_1'}],
            revisiones={'m1_1':{'comprension':nota,'codigo':0,'casos_limite':0}}, condicion='con_acompanamiento',version='piloto')
    pre,post=e(0),e(4)
    resultado=comparar(pre,post)
    assert resultado['cambio_puntos_porcentuales']==40
    assert resultado['cambio_relativo_porcentaje'] is None
    post.revisiones={}
    assert comparar(pre,post)['estado']=='pendiente'


def test_pregunta_del_andamiaje_se_ancla_al_codigo_real():
    from app.services.andamiaje_verificado import completar
    codigo="nombre = 'Ana'\nedad = 19\nprint(nombre, edad)"
    respuesta = completar('```python\n'+codigo+'\n```\nExplicación válida.\nLa pregunta final sería: ¿Qué pasa si el usuario ingresa datos?', codigo)
    assert 'Explicación válida.' in respuesta
    assert 'usuario ingresa' not in respuesta
    assert 'literal asignado es entero (int)' in respuesta
    assert '`nombre`' in respuesta.split('Pregunta sobre este código:')[-1]
    funcion = completar('```python\ndef doble(n):\n    return n*2\n```', 'def doble(n):\n    return n*2')
    assert 'argumento `n`' in funcion and '`doble`' in funcion
