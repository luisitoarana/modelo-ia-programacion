"""Schemas Pydantic v2 del sistema."""

from app.schemas.ai_response import (
    ActividadEvaluativa,
    AnalisisComplejidad,
    ConceptoClave,
    ExplicacionLinea,
    MetadataRespuestaIA,
    RespuestaIAEducativa,
)
from app.schemas.consulta import (
    ConsultaCrear,
    ConsultaLeer,
    ConsultaResumen,
    SolicitudGeneracion,
)
from app.schemas.dataset import (
    DatasetCrear,
    DatasetLeer,
    DatasetValidacion,
    ExportacionJSONLPar,
)
from app.schemas.evaluacion import EvaluacionCrear, EvaluacionLeer
from app.schemas.usuario import (
    Token,
    TokenData,
    UsuarioCrear,
    UsuarioLeer,
    UsuarioLogin,
)

__all__ = [
    "ActividadEvaluativa",
    "AnalisisComplejidad",
    "ConceptoClave",
    "ConsultaCrear",
    "ConsultaLeer",
    "ConsultaResumen",
    "DatasetCrear",
    "DatasetLeer",
    "DatasetValidacion",
    "EvaluacionCrear",
    "EvaluacionLeer",
    "ExplicacionLinea",
    "ExportacionJSONLPar",
    "MetadataRespuestaIA",
    "RespuestaIAEducativa",
    "SolicitudGeneracion",
    "Token",
    "TokenData",
    "UsuarioCrear",
    "UsuarioLeer",
    "UsuarioLogin",
]
