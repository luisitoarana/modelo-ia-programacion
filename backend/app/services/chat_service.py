"""Servicio de chat conversacional.

Genera la respuesta del asistente para un mensaje del usuario, con esta
prioridad (alineada con la investigación):

    1. MODELO PROPIO (si está entrenado y habilitado)  → respuesta sin APIs.
    2. API como ANDAMIO temporal (si el admin configuró una key) → texto libre.
    3. Mensaje guía si no hay ninguno disponible.

Toda la conversación se persiste como hilos (Conversacion) con mensajes.
"""

from __future__ import annotations

import asyncio
import re
import time
import uuid
from datetime import datetime

from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.conversacion import Conversacion, Mensaje, RolMensaje
from app.models.intento_aprendizaje import AsignacionEstudio
from app.services import model_inference_service as modelo
from app.services.ai_provider import (
    ProveedorIAError,
    obtener_proveedor,
    proveedores_disponibles,
)
from app.services.content_filter import ResultadoFiltro, evaluar_mensaje
from app.services.prompt_pedagogico import construir_prompt_sistema_chat
from app.services.web_search import buscar_web
from app.utils.logger import obtener_logger


log = obtener_logger(__name__)


# Heurística para detectar si una pregunta probablemente se beneficia de
# información web actualizada (versiones nuevas, errores específicos, etc.).
_PATRONES_WEB = (
    re.compile(r"\b(versión|version|última|latest|nueva|new)\b", re.IGNORECASE),
    re.compile(r"\b(error|exception|traceback|stack ?overflow)\b", re.IGNORECASE),
    re.compile(r"\b(docu(?:mentaci[oó]n|mentation)|docs|readme)\b", re.IGNORECASE),
    re.compile(r"\b(2024|2025|2026|hoy|este a[ñn]o)\b", re.IGNORECASE),
    re.compile(r"\b(busca|search|investiga|google|consulta)\b", re.IGNORECASE),
)


def _necesita_busqueda_web(texto: str) -> bool:
    """Heurística simple para decidir si invocar búsqueda web."""
    return any(p.search(texto) for p in _PATRONES_WEB)


def _formatear_contexto_web(resultados) -> str:
    lineas = []
    for i, r in enumerate(resultados, 1):
        lineas.append(f"[{i}] {r.titulo}\n    URL: {r.url}\n    Resumen: {r.resumen}")
    return "\n\n".join(lineas)


_MAX_HISTORIAL = 10  # últimos N mensajes como contexto


def _peticion_actual(texto: str) -> str:
    """Separa la instrucción del estudiante del contexto de archivo del editor."""
    match = re.search(r"(?mi)^Petición(?: actual)? del estudiante:\s*(.+)$", texto)
    return match.group(1).strip() if match else texto.strip()


def _codigo_directo(texto: str, codigo: str | None) -> str:
    """Una sola solución completa; comentarios didácticos fuera de la condición directa."""
    import ast
    bloques = re.findall(r'```(?:python|py)?\s*\n(.*?)```', texto, re.S)
    if len(bloques) > 1:
        raise ValueError('Devuelve un único bloque con el archivo completo corregido, no versiones alternativas.')
    arbol = ast.parse(bloques[0] if bloques else codigo or texto)
    if not arbol.body:
        raise ValueError('El archivo de respuesta está vacío.')
    # Verificar nombres de módulos básicos conocidos sin importar ni ejecutar
    # dependencias propuestas por el modelo, ni consultar servicios externos.
    import math, statistics, string, collections, itertools, functools, operator
    modulos = {m.__name__: m for m in (math, statistics, string, collections, itertools, functools, operator)}
    for nodo in ast.walk(arbol):
        if isinstance(nodo, ast.ImportFrom) and not nodo.level and nodo.module in modulos:
            for alias in nodo.names:
                if alias.name != '*' and not hasattr(modulos[nodo.module], alias.name):
                    raise ValueError(f'ImportError: {nodo.module} no contiene {alias.name}. Corrige la importación. round, len, sum, min y max son funciones integradas y no se importan de math.')
    for nodo in ast.walk(arbol):
        if isinstance(nodo, (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            if nodo.body and isinstance(nodo.body[0], ast.Expr) and isinstance(nodo.body[0].value, ast.Constant) and isinstance(nodo.body[0].value.value, str):
                nodo.body.pop(0)
                if not nodo.body:
                    nodo.body.append(ast.Pass())
    return '```python\n' + ast.unparse(ast.fix_missing_locations(arbol)).strip() + '\n```'

_BLOQUE_PYTHON = re.compile(
    r"```(?:python|py)?[ \t]*\r?\n(.*?)```", re.IGNORECASE | re.DOTALL
)


def _ultimo_bloque_python(historial: list[Mensaje]) -> str | None:
    """Recupera el último archivo generado para peticiones de continuación."""
    for mensaje in reversed(historial):
        if mensaje.rol != RolMensaje.ASISTENTE:
            continue
        bloques = _BLOQUE_PYTHON.findall(mensaje.contenido)
        if bloques:
            codigo = bloques[-1].strip()
            return codigo[:6000] if codigo else None
    return None

from app.services.code_explainer_service import generar_explicacion_didactica


def _extraer_codigo_y_modo(texto: str) -> tuple[str | None, str, str]:
    """Extrae fragmentos de código Python, modo y nivel solicitados."""
    t_low = texto.lower()
    modo = "didactico"
    if any(k in t_low for k in ("complejidad", "big-o", "big o", "temporal", "espacial")):
        modo = "complejidad"
    elif any(k in t_low for k in ("bug", "riesgo", "límite", "limite", "error")):
        modo = "bugs"
    elif any(k in t_low for k in ("optimiz", "pep 8", "pep8", "pythonic", "limpio")):
        modo = "optimizacion"

    nivel = "principiante"
    if "intermedio" in t_low:
        nivel = "intermedio"
    elif "avanzado" in t_low:
        nivel = "avanzado"

    # 1. Bloques markdown ```python ... ```
    if "```" in texto:
        partes = texto.split("```")
        for i in range(1, len(partes), 2):
            bloque = partes[i].strip()
            if bloque.lower().startswith("python"):
                bloque = bloque[6:].strip()
            bloque = bloque.strip("`").strip()
            if any(k in bloque for k in ("def ", "class ", "for ", "while ", "print(", "=", "import ", "return ")):
                return bloque, modo, nivel

    # 2. Código sin formato markdown que contenga estructura reconocible
    lineas = [l for l in texto.splitlines() if l.strip()]
    if lineas:
        tiene_def = any(l.strip().startswith("def ") for l in lineas)
        tiene_control = any(l.strip().startswith(("for ", "while ", "class ")) for l in lineas)
        if tiene_def or (tiene_control and len(lineas) >= 2):
            primer_idx = next(i for i, l in enumerate(lineas) if l.strip().startswith(("def ", "class ", "for ", "while ", "import ", "from ")))
            return "\n".join(lineas[primer_idx:]).strip(), modo, nivel

    return None, modo, nivel


def _buscar_concepto_educativo(texto: str) -> str | None:
    """Busca en knowledge_base si la pregunta es conceptual sobre Python."""
    t = texto.lower().strip()
    senales = ("que es", "qué es", "como funciona", "cómo funciona", "para que sirve", "para qué sirve", "explica", "ejemplo de")
    if not any(s in t for s in senales):
        return None
    try:
        from app.services.knowledge_service import KnowledgeService
        ks = KnowledgeService()
        mapeo = {
            "funcion": "01_funciones",
            "función": "01_funciones",
            "bucle": "05_bucles",
            "for": "05_bucles",
            "while": "05_bucles",
            "variable": "01_variables",
            "lista": "02_listas_y_diccionarios",
            "diccionario": "02_listas_y_diccionarios",
            "excepcion": "03_excepciones",
            "excepción": "03_excepciones",
            "try": "03_excepciones",
            "clase": "01_clases_y_objetos",
            "objeto": "01_clases_y_objetos",
            "poo": "01_clases_y_objetos",
            "herencia": "02_herencia_polimorfismo",
            "polimorfismo": "02_herencia_polimorfismo",
            "busqueda": "01_busqueda",
            "búsqueda": "01_busqueda",
            "binaria": "01_busqueda",
            "burbuja": "02_ordenamiento_burbuja",
            "ordenamiento": "02_ordenamiento_burbuja",
            "recursiv": "03_recursividad",
            "complejidad": "04_complejidad",
            "big-o": "04_complejidad",
        }
        for clave, archivo_slug in mapeo.items():
            if clave in t:
                for cat in ks.listar_categorias():
                    for tema in ks.listar_temas(cat):
                        if tema.slug == archivo_slug or clave in tema.titulo.lower():
                            return (
                                f"## 📚 Concepto Pedagógico: {tema.titulo}\n\n"
                                f"{tema.contenido.strip()}\n\n"
                                f"---\n*Respuesta tomada de la base curricular local.*"
                            )
    except Exception as exc:
        log.warning("Búsqueda conceptual falló: %s", exc)
    return None



NOMBRES_MOTORES = {
    "groq": "Motor Neuronal de Alta Velocidad (Cloud L-Engine)",
    "gemini": "Motor Neuronal de Contexto Extenso (Cloud G-Engine)",
    "deepseek": "Motor Neuronal de Razonamiento Profundo (Cloud D-Engine)",
    "openrouter": "Motor Neuronal Distribuido (Cloud R-Engine)",
    "openai": "Motor Neuronal GPT (Cloud O-Engine)",
    "anthropic": "Motor Neuronal Claude (Cloud C-Engine)",
    "propio": "Motor Propio Local Offline (Edge-Engine)",
    "modelo_propio": "Motor Propio Local Offline (Edge-Engine)",
}


class ChatService:
    def __init__(self, sesion: AsyncSession) -> None:
        self.sesion = sesion

    # ---------------- Conversaciones ----------------
    async def crear_conversacion(
        self, usuario_id: uuid.UUID, *, titulo: str = "Nueva conversación"
    ) -> Conversacion:
        conv = Conversacion(usuario_id=usuario_id, titulo=titulo)
        self.sesion.add(conv)
        await self.sesion.flush()
        return conv

    async def listar_conversaciones(
        self, usuario_id: uuid.UUID, *, limite: int = 100
    ) -> list[Conversacion]:
        stmt = (
            select(Conversacion)
            .where(
                Conversacion.usuario_id == usuario_id,
                Conversacion.archivada.is_(False),
            )
            .order_by(desc(Conversacion.fecha_actualizacion))
            .limit(limite)
        )
        return list((await self.sesion.scalars(stmt)).all())

    async def obtener_conversacion(
        self, conv_id: uuid.UUID, usuario_id: uuid.UUID
    ) -> Conversacion | None:
        conv = await self.sesion.get(Conversacion, conv_id)
        if conv is None or conv.usuario_id != usuario_id:
            return None
        return conv

    async def renombrar(self, conv: Conversacion, titulo: str) -> None:
        conv.titulo = titulo[:160]
        await self.sesion.flush()

    async def eliminar(self, conv: Conversacion) -> None:
        await self.sesion.delete(conv)
        await self.sesion.flush()

    async def mensajes(self, conv_id: uuid.UUID) -> list[Mensaje]:
        stmt = (
            select(Mensaje)
            .where(Mensaje.conversacion_id == conv_id)
            .order_by(Mensaje.fecha_creacion)
        )
        return list((await self.sesion.scalars(stmt)).all())

    # ---------------- Envío de mensaje ----------------
    async def enviar_mensaje(
        self,
        conv: Conversacion,
        texto_usuario: str,
        *,
        idioma: str = "es",
        habilitar_busqueda_web: bool = False,
        imagenes: list[tuple[bytes, str]] | None = None,
        proveedor_forzado: str = "auto",
        modo_acompanamiento: str | None = None,
        nivel_modulo: str | None = "principiante",
    ) -> tuple[Mensaje, Mensaje]:
        """Guarda el mensaje del usuario, genera la respuesta y la guarda."""
        # 1) Guardar mensaje del usuario.
        msg_usuario = Mensaje(
            conversacion_id=conv.id,
            rol=RolMensaje.USUARIO,
            contenido=texto_usuario.strip(),
        )
        self.sesion.add(msg_usuario)
        await self.sesion.flush()

        # Auto-título a partir del primer mensaje.
        n_msgs = await self.sesion.scalar(
            select(func.count(Mensaje.id)).where(Mensaje.conversacion_id == conv.id)
        )
        if (n_msgs or 0) <= 1 and conv.titulo in ("Nueva conversación", "", None):
            conv.titulo = (texto_usuario.strip()[:60] or "Conversación")

        # 2) Construir contexto y generar respuesta.
        asignacion = await self.sesion.get(AsignacionEstudio, conv.usuario_id)
        if asignacion is not None:
            modo_acompanamiento = (
                "bloqueado_post_test"
                if asignacion.fase in ("pre", "post")
                else asignacion.condicion
            )
            # Ambas condiciones deben usar el mismo motor para que la
            # comparación mida el andamiaje, no un cambio de proveedor.
            proveedor_forzado = "propio"
            imagenes = None
            habilitar_busqueda_web = False
        historial = await self._historial_reciente(conv.id)
        texto_asistente, meta = await self._generar_respuesta(
            texto_usuario,
            historial,
            idioma=idioma,
            habilitar_busqueda_web=habilitar_busqueda_web,
            imagenes=imagenes,
            proveedor_forzado=proveedor_forzado,
            modo_acompanamiento=modo_acompanamiento,
            nivel_modulo=nivel_modulo,
        )
        if asignacion is not None:
            fase_inicial = asignacion.fase
            await self.sesion.refresh(asignacion)
            if asignacion.fase != fase_inicial:
                texto_asistente = 'El docente cambió la fase durante la consulta. Actualiza la aplicación.'
                meta = {'origen': 'cambio_fase_estudio', 'tokens': 0, 'latencia': 0.0}
            meta["condicion_estudio"] = asignacion.condicion
            meta["fase_estudio"] = asignacion.fase
            meta["modo_efectivo"] = modo_acompanamiento

        # 3) Guardar respuesta del asistente.
        msg_asistente = Mensaje(
            conversacion_id=conv.id,
            rol=RolMensaje.ASISTENTE,
            contenido=texto_asistente,
            origen_respuesta=meta.get("origen"),
            tokens_totales=int(meta.get("tokens", 0)),
            latencia_segundos=float(meta.get("latencia", 0.0)),
            metadata_json=meta,
        )
        self.sesion.add(msg_asistente)
        conv.fecha_actualizacion = datetime.utcnow()
        await self.sesion.flush()
        return msg_usuario, msg_asistente

    async def _historial_reciente(self, conv_id: uuid.UUID) -> list[Mensaje]:
        stmt = (
            select(Mensaje)
            .where(Mensaje.conversacion_id == conv_id)
            .order_by(desc(Mensaje.fecha_creacion))
            .limit(_MAX_HISTORIAL)
        )
        msgs = list((await self.sesion.scalars(stmt)).all())
        return list(reversed(msgs))

    async def _generar_respuesta(
        self,
        texto_usuario: str,
        historial: list[Mensaje],
        *,
        idioma: str = "es",
        habilitar_busqueda_web: bool = False,
        imagenes: list[tuple[bytes, str]] | None = None,
        proveedor_forzado: str = "auto",
        modo_acompanamiento: str | None = None,
        nivel_modulo: str | None = "principiante",
    ) -> tuple[str, dict]:
        # -1) Condición experimental bloqueada (Post-Test): asistente deshabilitado
        if modo_acompanamiento == "bloqueado_post_test":
            return (
                "🔒 **Modo de Evaluación Post-Test Activo**\n\n"
                "El asistente de inteligencia artificial está temporalmente deshabilitado en esta fase para evaluar tus competencias de programación independiente.\n\n"
                "Por favor, resuelve el ejercicio de programación directamente en el editor de código utilizando tus conocimientos.",
                {
                    "origen": "bloqueado_post_test",
                    "motor": "Evaluación Post-Test (Bloqueado)",
                    "tokens": 0,
                    "latencia": 0.0,
                },
            )

        # 0) Filtro de contenido — bloquea peticiones claramente maliciosas
        evaluacion = evaluar_mensaje(texto_usuario)
        if evaluacion.resultado == ResultadoFiltro.BLOQUEADO:
            log.info(
                "Mensaje bloqueado por filtro (%s): %r",
                evaluacion.razon,
                texto_usuario[:80],
            )
            return (
                evaluacion.mensaje_usuario,
                {"origen": "filtro_contenido", "categoria": evaluacion.razon},
            )

        # 1a) Si hay imágenes, intentar SOLO el modelo multimodal propio.
        if imagenes:
            try:
                from app.services import multimodal_service
                if multimodal_service.modelo_disponible():
                    r = await multimodal_service.responder(
                        texto_usuario, imagenes,
                    )
                    return r.texto, {
                        "origen": "modelo_propio_multimodal",
                        "motor": "Motor Multimodal Propio (Local)",
                        "n_imagenes": len(imagenes),
                        "tokens": r.tokens_generados,
                        "latencia": r.latencia_segundos,
                    }
            except Exception as exc:  # noqa: BLE001
                log.warning("Modelo multimodal propio falló: %s", exc)
            return (
                "El modelo de visión propio todavía está en entrenamiento. "
                "Pronto podré analizar imágenes de código sin depender de "
                "APIs externas. Por ahora, puedes pegar el código como texto "
                "y te lo explico igual de bien.",
                {"origen": "vision_en_entrenamiento", "n_imagenes": len(imagenes)},
            )

        # Normalizar la elección del usuario.
        prov = (proveedor_forzado or "auto").lower().strip()
        es_propio_especifico = prov.startswith("propio_")
        disponibles_cloud = proveedores_disponibles()

        # CASO A: El usuario pide EXPLÍCITAMENTE una nube específica (groq, gemini, deepseek, openrouter, openai, anthropic)
        if prov in ("groq", "gemini", "deepseek", "openrouter", "openai", "anthropic"):
            if prov in disponibles_cloud:
                texto_api, meta_api = await self._respuesta_api(
                    texto_usuario,
                    historial,
                    idioma=idioma,
                    habilitar_busqueda_web=habilitar_busqueda_web,
                    proveedor_forzado=prov,
                    modo_acompanamiento=modo_acompanamiento,
                    nivel_modulo=nivel_modulo,
                )
                if meta_api.get("origen") != "api_error":
                    return texto_api, meta_api

        # CASO B: Si prov es "auto" o "propio", la PRIMERA PRIORIDAD es el Motor Neuronal Pedagógico Local Offline
        if prov in ("auto", "propio", "modelo_propio"):
            try:
                from app.services import motor_pedagogico_service
                if motor_pedagogico_service.esta_disponible():
                    modo_acomp = modo_acompanamiento or "con_acompanamiento"
                    if modo_acompanamiento is None:
                        t_low = texto_usuario.lower()
                        if any(sin in t_low for sin in ("sin explicar", "sin explicacion", "solo codigo", "solo el codigo", "sin acompanamiento")):
                            modo_acomp = "sin_acompanamiento"

                    # Conservar el último bloque Python completo para continuidad del diálogo
                    prompt_con_historial = texto_usuario
                    if historial and len(historial) > 1:
                        buffer_hist = []
                        previos = historial[:-1][-2:]
                        for m in previos:
                            rol_txt = "Estudiante" if m.rol == RolMensaje.USUARIO else "Asistente"
                            contenido = _peticion_actual(m.contenido) if m.rol == RolMensaje.USUARIO else m.contenido
                            c_limpio = contenido[:260] + "..." if len(contenido) > 260 else contenido
                            buffer_hist.append(f"{rol_txt}: {c_limpio}")
                        if buffer_hist:
                            prompt_con_historial = (
                                "[HISTORIAL PREVIO DEL DIÁLOGO]\n"
                                + "\n".join(buffer_hist)
                                + "\n[/HISTORIAL PREVIO]\n\n"
                                + "[PETICIÓN ACTUAL]\n" + texto_usuario
                            )
                        ultimo_codigo = _ultimo_bloque_python(historial[:-1])
                        if ultimo_codigo and "Código actual en el editor" not in texto_usuario and "Último código generado para continuar" not in texto_usuario:
                            prompt_con_historial += (
                                "\n\n[ARCHIVO PYTHON GENERADO ANTES; conserva su "
                                "funcionalidad y aplica la petición actual]\n"
                                f"```python\n{ultimo_codigo[:3000]}\n```\n"
                                "[/ARCHIVO PYTHON GENERADO ANTES]"
                            )

                    r_local = await asyncio.to_thread(
                        motor_pedagogico_service.generar_respuesta,
                        prompt_con_historial,
                        modo_acompanamiento=modo_acomp,
                        nivel_modulo=nivel_modulo,
                        temperatura=0.25,
                    )
                    if r_local and r_local.texto:
                        respuesta_local = r_local.texto
                        andamiaje_verificado = False
                        bloques_actuales = re.findall(r'```(?:python|py)\s*\n(.*?)```', texto_usuario, re.S)
                        codigo_explicado = r_local.codigo or (bloques_actuales[-1] if bloques_actuales else None)
                        explicacion_estatica = False
                        pedido_actual = _peticion_actual(texto_usuario).lower()
                        solo_explicar = re.search(r'\b(explica|explicar|analiza|comprender)\b', pedido_actual) and not re.search(r'\b(corrige|modifica|cambia|genera|crea|repara|arregla)\b', pedido_actual)
                        if modo_acomp == 'con_acompanamiento' and bloques_actuales and solo_explicar:
                            import ast
                            from app.services.andamiaje_verificado import explicar_sin_cambiar
                            codigo_explicado = bloques_actuales[-1]
                            try:
                                original = ast.parse(codigo_explicado)
                                if r_local.codigo and ast.dump(ast.parse(r_local.codigo)) != ast.dump(original):
                                    respuesta_local = explicar_sin_cambiar(codigo_explicado)
                                    explicacion_estatica = True
                            except (SyntaxError, ValueError):
                                pass
                        if modo_acomp == 'con_acompanamiento' and codigo_explicado:
                            from app.services.andamiaje_verificado import completar
                            try:
                                respuesta_local = completar(respuesta_local, codigo_explicado)
                                andamiaje_verificado = True
                            except (SyntaxError, ValueError):
                                # No presentar una comprobación estática de código inválido.
                                pass
                        if modo_acomp == 'sin_acompanamiento':
                            try:
                                respuesta_local = _codigo_directo(r_local.texto, r_local.codigo)
                            except (SyntaxError, ValueError) as error:
                                # Un solo intento de reparación, con el mismo motor y condición.
                                # No ejecutar código del modelo en el servidor para validarlo.
                                reparada = await asyncio.to_thread(
                                    motor_pedagogico_service.generar_respuesta,
                                    prompt_con_historial + "\n\n[REPARACIÓN DE LA RESPUESTA]\n"
                                    + "Tu propuesta no pasó la validación Python: " + str(error)
                                    + "\nPropuesta rechazada:\n" + r_local.texto[:6000]
                                    + "\nDevuelve un único bloque Python completo que resuelva la petición original.",
                                    modo_acompanamiento=modo_acomp, nivel_modulo=nivel_modulo, temperatura=0.1,
                                )
                                try:
                                    if not reparada or not reparada.texto:
                                        raise ValueError('Respuesta vacía')
                                    respuesta_local = _codigo_directo(reparada.texto, reparada.codigo)
                                except (SyntaxError, ValueError):
                                    return 'No se pudo obtener una corrección Python válida. El archivo se conserva; vuelve a intentarlo.', {
                                        'origen': 'error_generacion_directa', 'tokens': r_local.tokens_generados, 'latencia': r_local.latencia_segundos,
                                    }
                                reparada.contexto_recortado |= r_local.contexto_recortado
                                reparada.tokens_generados += r_local.tokens_generados
                                reparada.latencia_segundos += r_local.latencia_segundos
                                r_local = reparada
                        return respuesta_local, {
                            "origen": "motor_pedagogico_local",
                            "proveedor": "propio",
                            "motor": "Motor Neuronal Pedagógico Local",
                            "tokens": r_local.tokens_generados,
                            "latencia": r_local.latencia_segundos,
                            "tokens_por_segundo": r_local.tokens_por_segundo,
                            "device": "gpu" if getattr(motor_pedagogico_service, "es_gpu", lambda: True)() else "cpu",
                            "contexto_recortado": r_local.contexto_recortado,
                            "respuesta_incompleta": r_local.respuesta_incompleta,
                            "pregunta_origen": "ast_del_codigo" if andamiaje_verificado else None,
                            "explicacion_origen": "ast_por_cambio_no_solicitado" if explicacion_estatica else "modelo",
                        }
            except motor_pedagogico_service.MotorLocalError as exc:
                return str(exc), {"origen": "error_motor_local", "proveedor": "propio", "tokens": 0, "latencia": 0.0}
            except Exception as exc:
                log.warning("Fallo en motor local pedagógico: %s, evaluando alternativas...", exc)

        # CASO C: Fallback a Cloud solo si prov == "auto" y el motor local no está disponible
        if prov == "auto" and disponibles_cloud:
            orden_cascada = ["groq", "gemini", "deepseek", "openrouter", "openai", "anthropic"]
            for p_cand in orden_cascada:
                if p_cand in disponibles_cloud:
                    try:
                        texto_api, meta_api = await self._respuesta_api(
                            texto_usuario,
                            historial,
                            idioma=idioma,
                            habilitar_busqueda_web=habilitar_busqueda_web,
                            proveedor_forzado=p_cand,
                            modo_acompanamiento=modo_acompanamiento,
                            nivel_modulo=nivel_modulo,
                        )
                        if meta_api.get("origen") != "api_error":
                            return texto_api, meta_api
                    except Exception as exc:
                        log.warning("Fallo en proveedor cloud %s: %s, probando siguiente...", p_cand, exc)

        # CASO D: Checkpoint B/C específico
        if es_propio_especifico:
            if not await asyncio.to_thread(modelo.cambiar_modelo, prov):
                return "El checkpoint seleccionado no está disponible.", {
                    "origen": "modelo_no_disponible", "proveedor": prov,
                    "tokens": 0, "latencia": 0.0,
                }
            try:
                r_propio = await asyncio.to_thread(
                    modelo.responder_con_modelo, texto_usuario,
                    max_tokens=512, temperatura=0.3,
                )
                return r_propio.texto, {
                    "origen": "modelo_propio", "proveedor": prov,
                    "motor": prov, "tokens": r_propio.tokens_generados,
                    "latencia": r_propio.latencia_segundos, "device": r_propio.device,
                }
            except RuntimeError as exc:
                log.warning("Checkpoint %s no respondió: %s", prov, exc)
                return "El checkpoint seleccionado no pudo responder.", {
                    "origen": "modelo_no_disponible", "proveedor": prov,
                    "tokens": 0, "latencia": 0.0,
                }

        if prov in ("propio", "modelo_propio"):
            return "El motor neuronal propio local offline no está disponible.", {
                "origen": "modelo_no_disponible", "proveedor": "propio",
                "tokens": 0, "latencia": 0.0,
            }

            # 2. Fallback al analizador sintáctico AST pedagógico
            pedido_actual = _peticion_actual(texto_usuario)
            codigo_detectado, modo_detectado, nivel_detectado = _extraer_codigo_y_modo(texto_usuario)
            # Un archivo adjunto es contexto, no una orden de explicarlo. En
            # peticiones de edición o creación, AST repetiría la explicación
            # anterior si el proveedor principal fallara.
            pide_analisis = any(k in pedido_actual.lower() for k in (
                "explica", "analiza", "audita", "revisa", "error", "bug",
                "complejidad", "optimiza", "qué hace", "que hace",
            ))
            if codigo_detectado and pide_analisis:
                explicacion = generar_explicacion_didactica(
                    codigo_detectado,
                    modo=modo_detectado,
                    nivel=nivel_detectado,
                    modelo_nombre="Motor Sintáctico AST Pedagógico",
                    usar_modelo=False,
                )
                return explicacion, {
                    "origen": "ast_local",
                    "proveedor": "ast_local",
                    "motor": "Motor Sintáctico AST Didáctico",
                    "tokens": 0,
                    "latencia": 0.0,
                }

            concepto = _buscar_concepto_educativo(pedido_actual)
            if concepto:
                return concepto, {
                    "origen": "curriculo_local",
                    "proveedor": "curriculo_local",
                    "motor": "Base Curricular Pedagógica Local",
                    "tokens": 0,
                    "latencia": 0.0,
                }

            # 3. Fallback a inferencia cruda de PyTorch
            if modelo.modelo_disponible():
                try:
                    r = await asyncio.to_thread(
                        modelo.responder_con_modelo,
                        texto_usuario,
                        max_tokens=220,
                        temperatura=0.7,
                    )
                    return r.texto, {
                        "origen": "modelo_propio",
                        "proveedor": "pytorch_local",
                        "motor": "Modelo Propio PyTorch (Local)",
                        "tokens": r.tokens_generados,
                        "latencia": r.latencia_segundos,
                        "device": r.device,
                    }
                except RuntimeError as exc:
                    log.warning("Modelo propio no respondió: %s", exc)

        return (
            "No hay un motor neuronal local disponible ni claves de conexión configuradas en el sistema. "
            "Por favor, revisa la configuración del sistema para activar un motor.",
            {"origen": "sin_configurar"},
        )

    async def _respuesta_api(
        self,
        texto_usuario: str,
        historial: list[Mensaje],
        *,
        idioma: str = "es",
        habilitar_busqueda_web: bool = False,
        proveedor_forzado: str = "auto",
        modo_acompanamiento: str | None = None,
        nivel_modulo: str | None = "principiante",
    ) -> tuple[str, dict]:
        contexto_web: str | None = None
        fuentes_web: list[dict] = []
        if habilitar_busqueda_web and _necesita_busqueda_web(texto_usuario):
            try:
                resultados = await buscar_web(texto_usuario, limite=5)
                if resultados:
                    contexto_web = _formatear_contexto_web(resultados)
                    fuentes_web = [r.to_dict() for r in resultados]
            except Exception as exc:  # noqa: BLE001
                log.warning("Búsqueda web falló (continúo sin ella): %s", exc)

        contexto_rag: str | None = None
        fuentes_rag: list[dict] = []
        try:
            from app.services import rag_service
            if rag_service.debe_recuperar(texto_usuario):
                contexto_rag, fuentes_rag = rag_service.recuperar_y_formatear(
                    texto_usuario, k=4,
                )
        except Exception as exc:  # noqa: BLE001
            log.warning("RAG falló (continúo sin él): %s", exc)

        prov_api = proveedor_forzado.lower().strip() if proveedor_forzado else "auto"
        try:
            proveedor = obtener_proveedor(prov_api)
        except Exception as exc:  # noqa: BLE001
            log.warning("Proveedor %r no disponible, uso auto: %s", prov_api, exc)
            proveedor = obtener_proveedor("auto")

        transcripcion = self._formatear_historial(historial)
        bloque_rag = f"\n\n{contexto_rag}\n\n" if contexto_rag else ""

        # Adaptar prompt según condición del estudio de tesis y módulo curricular
        if modo_acompanamiento == "sin_acompanamiento":
            sistema = (
                "Eres un generador directo de código Python funcional.\n"
                "Tu tarea es entregar ÚNICAMENTE el código Python completo, limpio, funcional y correctamente indentado.\n"
                "NO incluyas explicaciones conceptuales, ni propósitos, ni preguntas de autoevaluación, ni andamiaje pedagógico.\n"
                "Entrega directamente el bloque de código ```python con breves comentarios internos esenciales."
            )
            usuario = f"{transcripcion}{bloque_rag}\n\nRequerimiento de código:\n{texto_usuario}"
            temp = 0.2
        else:
            modulo_guia = ""
            nivel_norm = (nivel_modulo or "principiante").lower()
            if nivel_norm == "principiante":
                modulo_guia = (
                    "\n\n[MÓDULO CURRICULAR: 1. PRINCIPIANTE - Fundamentos y Palabras Reservadas]\n"
                    "Prioriza la explicación de palabras reservadas (keyword.kwlist, def, if, for, etc.), variables, "
                    "tipos primitivos y desglose paso a paso muy sencillo, alertando sobre dos puntos (:) e indentación."
                )
            elif nivel_norm == "intermedio":
                modulo_guia = (
                    "\n\n[MÓDULO CURRICULAR: 2. INTERMEDIO - Control de Flujo y Colecciones]\n"
                    "Prioriza la lógica de bucles (for/while), acumuladores, listas/diccionarios, "
                    "casos límite y prevención de bugs como ZeroDivisionError y listas vacías."
                )
            elif nivel_norm == "avanzado":
                modulo_guia = (
                    "\n\n[MÓDULO CURRICULAR: 3. AVANZADO - Complejidad Big-O y POO]\n"
                    "Prioriza el análisis formal de complejidad Big-O temporal y espacial, Programación Orientada "
                    "a Objetos (clases, métodos, __init__) y estándares profesionales PEP 8."
                )

            sistema = (
                construir_prompt_sistema_chat(
                    idioma=idioma,
                    contexto_web=contexto_web,
                )
                + modulo_guia
            )
            usuario = (
                f"{transcripcion}{bloque_rag}\n\nMensaje actual del estudiante:\n"
                f"{texto_usuario}\n\nResponde aplicando la estructura pedagógica. "
                f"Si usas información de las FUENTES, cita el título entre paréntesis."
            )
            temp = 0.5

        inicio = time.perf_counter()
        try:
            resultado = await proveedor.generar(
                sistema=sistema,
                usuario=usuario,
                temperatura=temp,
                max_tokens=settings.ai_max_output_tokens,
                json_mode=False,
            )
        except Exception as exc:
            return (
                f"No pude generar una respuesta: {exc}",
                {"origen": "api_error", "error": str(exc)},
            )

        latencia = round(time.perf_counter() - inicio, 3)
        texto = resultado.texto.strip() or "(sin respuesta)"
        nombre_motor = NOMBRES_MOTORES.get(
            resultado.proveedor.lower(),
            f"Motor Neuronal ({resultado.proveedor.capitalize()})",
        )
        meta: dict = {
            "origen": "api",
            "proveedor": resultado.proveedor,
            "motor": nombre_motor,
            "modelo": resultado.modelo,
            "tokens": resultado.tokens_totales,
            "latencia": latencia,
        }
        if fuentes_web:
            meta["fuentes_web"] = fuentes_web
        if fuentes_rag:
            meta["fuentes_rag"] = fuentes_rag
        return texto, meta

    @staticmethod
    def _formatear_historial(historial: list[Mensaje]) -> str:
        if not historial:
            return "Inicio de la conversación."
        lineas = []
        for m in historial[:-1]:  # excluye el último (que es el actual)
            quien = "Estudiante" if m.rol == RolMensaje.USUARIO else "Asistente"
            lineas.append(f"{quien}: {m.contenido}")
        return "Historial reciente:\n" + "\n".join(lineas) if lineas else "Inicio de la conversación."
