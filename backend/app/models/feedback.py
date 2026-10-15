"""Modelo Feedback: valoración 👍/👎 del usuario sobre una respuesta del asistente.

Esta tabla es la base del entrenamiento por refuerzo (RLHF). Cada
voto genera una fila que, junto con el prompt y la respuesta originales,
se exporta luego como par (chosen, rejected) para DPO.

Ver: docs/RLHF_PLAN.md
"""

from __future__ import annotations

import uuid
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, ForeignKey, SmallInteger, String, Text
from sqlalchemy import Uuid as UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.database import Base, TimestampMixin

if TYPE_CHECKING:
    from app.models.conversacion import Conversacion, Mensaje
    from app.models.usuario import Usuario


class Feedback(Base, TimestampMixin):
    """Valoración del usuario sobre una respuesta del asistente.

    Cada feedback queda asociado al `Mensaje` específico que recibió el
    voto (`mensaje_id`), pero también guarda copias del `prompt` y la
    `respuesta` para que el ejemplo de entrenamiento sea reconstruible
    aunque el mensaje original se borre.
    """

    __tablename__ = "feedbacks"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )

    # — Quién y qué votó —
    usuario_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("usuarios.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    mensaje_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("mensajes.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    conversacion_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("conversaciones.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    # — El voto —
    # +1 = pulgar arriba, -1 = pulgar abajo
    voto: Mapped[int] = mapped_column(SmallInteger, nullable=False, index=True)

    # — Detalle opcional del usuario —
    comentario: Mapped[str | None] = mapped_column(Text, nullable=True)
    # razones predefinidas: "preciso", "claro", "incorrecto", "alucina",
    # "incompleto", "muy_largo", "muy_corto", "fuera_de_tema"
    razon: Mapped[str | None] = mapped_column(String(40), nullable=True)

    # — Contexto necesario para reconstruir el ejemplo —
    prompt: Mapped[str] = mapped_column(Text, nullable=False)
    respuesta: Mapped[str] = mapped_column(Text, nullable=False)
    # "gemini", "deepseek", "propio:exp02", ...
    modelo: Mapped[str | None] = mapped_column(String(60), nullable=True)
    # "basico" | "intermedio" | "avanzado"
    nivel: Mapped[str | None] = mapped_column(String(20), nullable=True)

    # — Flag para el exportador RLHF —
    # True cuando este feedback ya entró a un dataset DPO.
    procesado: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, index=True
    )

    # — Relaciones —
    usuario: Mapped["Usuario"] = relationship()
    mensaje: Mapped["Mensaje | None"] = relationship()
    conversacion: Mapped["Conversacion | None"] = relationship()

    def __repr__(self) -> str:
        signo = "👍" if self.voto > 0 else "👎"
        return f"<Feedback {self.id} {signo} usuario={self.usuario_id}>"
