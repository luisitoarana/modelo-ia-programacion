"""Servicio de chat conversacional.

Genera la respuesta del asistente para un mensaje del usuario, con esta
prioridad (alineada con la investigación):

    1. MODELO PROPIO (si está entrenado y habilitado)  → respuesta sin APIs.
    2. API como ANDAMIO temporal (si el admin configuró una key) → texto libre.
    3. Mensaje guía si no hay ninguno disponible.

Toda la conversación se persiste como hilos (Conversacion) con mensajes.
"""

from __future__ import annotations

import re
import time
import uuid
from datetime import datetime

from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models.conversacion import Conversacion, Mensaje, RolMensaje
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
    ) -> tuple[Mensaje, Mensaje]:
        """Guarda el mensaje del usuario, genera la respuesta y la guarda.

        ``habilitar_busqueda_web`` permite al cliente forzar el uso de la
        herramienta de búsqueda web (heurística pegada al texto del mensaje).

        ``imagenes`` es una lista de tuplas ``(bytes, mime_type)``. Si está
        presente, se enruta al modelo de visión propio (ViT + Projector + LLM,
        ver ``ml/model/multimodal_model.py``). NO se delega a APIs externas
        para inferencia visual — esa es una decisión arquitectónica deliberada
        (ver ``docs/VISION_PROPIA.md``). Si el modelo multimodal aún no está
        entrenado, se devuelve un mensaje informativo.
        """
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
        historial = await self._historial_reciente(conv.id)
        texto_asistente, meta = await self._generar_respuesta(
            texto_usuario,
            historial,
            idioma=idioma,
            habilitar_busqueda_web=habilitar_busqueda_web,
            imagenes=imagenes,
            proveedor_forzado=proveedor_forzado,
        )

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
    ) -> tuple[str, dict]:
        # 0) Filtro de contenido — bloquea peticiones claramente maliciosas
        # (robo de credenciales, malware, etc.) y deja pasar las educativas.
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
        # Por decisión arquitectónica, NO delegamos visión a APIs externas
        # (ver docs/VISION_PROPIA.md). Si el modelo no está disponible,
        # devolvemos un mensaje claro.
        if imagenes:
            try:
                from app.services import multimodal_service
                if multimodal_service.modelo_disponible():
                    r = await multimodal_service.responder(
                        texto_usuario, imagenes,
                    )
                    return r.texto, {
                        "origen": "modelo_propio_multimodal",
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

        # 1b) MODELO PROPIO — si el usuario lo eligió o si está en modo auto.
        if prov in ("auto", "propio", "modelo_propio") and modelo.modelo_disponible():
            try:
                r = modelo.responder_con_modelo(texto_usuario)
                return r.texto or "(sin respuesta)", {
                    "origen": "modelo_propio",
                    "tokens": r.tokens_generados,
                    "latencia": r.latencia_segundos,
                    "device": r.device,
                }
            except RuntimeError as exc:
                log.warning("Modelo propio no respondió: %s", exc)

        # Si el usuario forzó "propio" y no está disponible, no caemos a API.
        if prov in ("propio", "modelo_propio") and not modelo.modelo_disponible():
            return (
                "Elegiste el modelo propio, pero aún no hay un checkpoint "
                "entrenado disponible. Entrénalo con `python -m ml.train` o "
                "elige otra IA en el selector del chat.",
                {"origen": "modelo_propio_no_disponible"},
            )

        # 2) API — usuario forzó una concreta (gemini/deepseek) o auto.
        if proveedores_disponibles():
            return await self._respuesta_api(
                texto_usuario,
                historial,
                idioma=idioma,
                habilitar_busqueda_web=habilitar_busqueda_web,
                proveedor_forzado=prov,
            )

        # 3) Sin cerebro disponible.
        return (
            "Todavía no hay un modelo entrenado ni una API configurada. "
            "Si eres administrador, configura una API key en el panel de "
            "administrador o entrena el modelo propio para empezar a conversar.",
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
    ) -> tuple[str, dict]:
        # Búsqueda web opcional: si el cliente la habilitó Y la pregunta
        # parece beneficiarse, consultamos antes de generar.
        contexto_web: str | None = None
        fuentes_web: list[dict] = []
        if habilitar_busqueda_web and _necesita_busqueda_web(texto_usuario):
            try:
                resultados = await buscar_web(texto_usuario, limite=5)
                if resultados:
                    contexto_web = _formatear_contexto_web(resultados)
                    fuentes_web = [r.to_dict() for r in resultados]
                    log.info(
                        "Búsqueda web aplicada: %d resultados para %r",
                        len(resultados),
                        texto_usuario[:60],
                    )
            except Exception as exc:  # noqa: BLE001
                log.warning("Búsqueda web falló (continúo sin ella): %s", exc)

        # RAG: si hay documentos del usuario indexados y la pregunta lo amerita,
        # añadimos los chunks más relevantes al prompt. El LLM los cita en lugar
        # de inventar (anti-alucinación).
        contexto_rag: str | None = None
        fuentes_rag: list[dict] = []
        try:
            from app.services import rag_service
            if rag_service.debe_recuperar(texto_usuario):
                contexto_rag, fuentes_rag = rag_service.recuperar_y_formatear(
                    texto_usuario, k=4,
                )
                if fuentes_rag:
                    log.info(
                        "[rag] %d chunks recuperados para %r",
                        len(fuentes_rag), texto_usuario[:60],
                    )
        except Exception as exc:  # noqa: BLE001
            log.warning("RAG falló (continúo sin él): %s", exc)

        # Nota: las imágenes NUNCA llegan aquí — la ruta multimodal está
        # cortada en `_generar_respuesta` para evitar Gemini Vision por
        # diseño (ver docs/VISION_PROPIA.md). Si llegaran, las ignoramos.
        # Si el usuario eligió una API concreta (gemini/deepseek) la
        # respetamos; en otro caso usamos el default configurado.
        prov_api = proveedor_forzado if proveedor_forzado in ("gemini", "deepseek") else "auto"
        try:
            proveedor = obtener_proveedor(prov_api)
        except Exception as exc:  # noqa: BLE001
            log.warning("Proveedor %r no disponible, uso auto: %s", prov_api, exc)
            proveedor = obtener_proveedor("auto")
        transcripcion = self._formatear_historial(historial)
        bloque_rag = f"\n\n{contexto_rag}\n\n" if contexto_rag else ""
        usuario = (
            f"{transcripcion}{bloque_rag}\n\nMensaje actual del estudiante:\n"
            f"{texto_usuario}\n\nResponde aplicando la estructura pedagógica. "
            f"Si usas información de las FUENTES, cita el título entre paréntesis."
        )
        sistema = construir_prompt_sistema_chat(
            idioma=idioma,
            contexto_web=contexto_web,
        )
        inicio = time.perf_counter()
        try:
            resultado = await proveedor.generar(
                sistema=sistema,
                usuario=usuario,
                temperatura=0.6,
                max_tokens=settings.ai_max_output_tokens,
                json_mode=False,
            )
        except ProveedorIAError as exc:
            return (
                f"No pude generar una respuesta: {exc}",
                {"origen": "api_error"},
            )
        latencia = round(time.perf_counter() - inicio, 3)
        texto = resultado.texto.strip() or "(sin respuesta)"
        meta: dict = {
            "origen": "api",
            "proveedor": resultado.proveedor,
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
