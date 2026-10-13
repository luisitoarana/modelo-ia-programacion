"""El enunciado que ve el estudiante debe corresponder a su lección."""

from pathlib import Path
import re
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock
from uuid import uuid4

import pytest

from app.routes.aprendizaje import IntentoCrear, registrar_intento
from app.services.curriculum_service import CurriculumService


def preguntas_desktop() -> dict[str, str]:
    catalogo = (
        Path(__file__).resolve().parents[2]
        / "app-desktop/lib/services/curriculum_catalog.dart"
    ).read_text(encoding="utf-8")
    return dict(re.findall(
        r"\bid: '([^']+)'[\s\S]*?preguntaAutoevaluacion:\s*'([^']*)'",
        catalogo,
    ))


def test_preguntas_de_las_once_lecciones_coinciden_con_desktop():
    preguntas = preguntas_desktop()
    assert len(preguntas) == 11
    for identificador, pregunta in preguntas.items():
        leccion = CurriculumService.obtener_leccion(identificador)
        assert leccion is not None, identificador
        assert leccion.pregunta_autoevaluacion == pregunta, identificador


@pytest.mark.asyncio
@pytest.mark.parametrize("identificador", [
    "m1_l4_indentacion", "m2_l3_listas_indexacion",
])
async def test_registro_acepta_ids_desktop_y_conserva_pregunta(identificador):
    pregunta = preguntas_desktop()[identificador]
    datos = IntentoCrear(
        leccion_id=identificador, pregunta=pregunta,
        modo="con_acompanamiento", codigo_inicial="print(1)",
        codigo_final="print(2)", prediccion="Mostrará 1.",
        explicacion_propia="La función print muestra el dato.",
        pistas_usadas=0, duracion_segundos=10,
    )
    sesion = AsyncMock()
    sesion.get.return_value = None
    sesion.add = Mock()
    resultado = await registrar_intento(datos, SimpleNamespace(id=uuid4()), sesion)
    assert resultado.leccion_id == identificador
    assert resultado.pregunta == pregunta
    sesion.add.assert_called_once_with(resultado)
    sesion.commit.assert_awaited_once()
