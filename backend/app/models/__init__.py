"""Modelos ORM del dominio."""

from app.models.actividad import Actividad
from app.models.conocimiento import (
    EstadoConocimiento,
    OrigenConocimiento,
    UnidadConocimiento,
)
from app.models.configuracion import ConfiguracionSistema
from app.models.consulta import Consulta
from app.models.conversacion import Conversacion, Mensaje, RolMensaje
from app.models.dataset import DatasetEducativo
from app.models.evaluacion import Evaluacion
from app.models.feedback import Feedback
from app.models.usuario import Usuario

__all__ = [
    "Actividad",
    "ConfiguracionSistema",
    "Consulta",
    "Conversacion",
    "DatasetEducativo",
    "Feedback",
    "Mensaje",
    "RolMensaje",
    "EstadoConocimiento",
    "Evaluacion",
    "OrigenConocimiento",
    "UnidadConocimiento",
    "Usuario",
]
