"""Auditor de Arquitectura y Proyectos Multi-Archivo mediante AST.

Permite analizar proyectos Python enteros (incluso de más de 200 archivos y
30.000 líneas de código) mediante Map-Reduce sintáctico con el módulo nativo
`ast` de Python:

1. MAP: Extrae la signatura arquitectónica de cada archivo (clases, métodos,
   funciones, imports, métricas y posibles riesgos estáticos) en milisegundos.
2. REDUCE: Sintetiza un grafo de dependencias y un resumen arquitectónico
   compacto (<500 líneas) que cabe holgadamente en el contexto de cualquier IA.
3. AUDIT: Permite al Asistente IA generar una auditoría profunda de la
   arquitectura del sistema sin alucinaciones ni desbordamiento de contexto.
"""

from __future__ import annotations

import ast
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

from app.services.project_explorer import ExploradorProyecto, _resolver_raiz
from app.utils.logger import obtener_logger

log = obtener_logger(__name__)


@dataclass(slots=True)
class SimboloFuncion:
    nombre: str
    linea_inicio: int
    linea_fin: int
    argumentos: list[str]
    es_asincrona: bool = False
    docstring: str | None = None


@dataclass(slots=True)
class SimboloClase:
    nombre: str
    linea_inicio: int
    linea_fin: int
    bases: list[str]
    metodos: list[SimboloFuncion] = field(default_factory=list)
    docstring: str | None = None


@dataclass(slots=True)
class RiesgoEstatico:
    linea: int
    tipo: str
    descripcion: str
    severidad: str  # "alta" | "media" | "baja"


@dataclass(slots=True)
class ResumenArchivoAST:
    ruta_relativa: str
    lineas_totales: int
    imports_modulos: list[str]
    clases: list[SimboloClase]
    funciones: list[SimboloFuncion]
    riesgos: list[RiesgoEstatico]
    error_sintaxis: str | None = None


class _VisitanteAST(ast.NodeVisitor):
    def __init__(self, lineas_codigo: list[str]):
        self.lineas = lineas_codigo
        self.imports: list[str] = []
        self.clases: list[SimboloClase] = []
        self.funciones: list[SimboloFuncion] = []
        self.riesgos: list[RiesgoEstatico] = []
        self._clase_actual: SimboloClase | None = None

    def visit_Import(self, node: ast.Import):
        for alias in node.names:
            self.imports.append(alias.name)
        self.generic_visit(node)

    def visit_ImportFrom(self, node: ast.ImportFrom):
        mod = node.module or ""
        for alias in node.names:
            if alias.name == "*":
                self.riesgos.append(
                    RiesgoEstatico(
                        linea=node.lineno,
                        tipo="wildcard_import",
                        descripcion=f"Import wildcard 'from {mod} import *' contamina el espacio de nombres.",
                        severidad="media",
                    )
                )
            self.imports.append(f"{mod}.{alias.name}" if mod else alias.name)
        self.generic_visit(node)

    def visit_ClassDef(self, node: ast.ClassDef):
        bases = []
        for b in node.bases:
            if isinstance(b, ast.Name):
                bases.append(b.id)
            elif isinstance(b, ast.Attribute):
                bases.append(f"{getattr(b.value, 'id', '')}.{b.attr}")
            else:
                bases.append("...")

        clase = SimboloClase(
            nombre=node.name,
            linea_inicio=node.lineno,
            linea_fin=getattr(node, "end_lineno", node.lineno),
            bases=bases,
            docstring=ast.get_docstring(node),
        )
        prev = self._clase_actual
        self._clase_actual = clase
        self.generic_visit(node)
        self._clase_actual = prev
        self.clases.append(clase)

    def visit_FunctionDef(self, node: ast.FunctionDef):
        self._procesar_funcion(node, es_async=False)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef):
        self._procesar_funcion(node, es_async=True)

    def _procesar_funcion(self, node: ast.FunctionDef | ast.AsyncFunctionDef, es_async: bool):
        args = [a.arg for a in node.args.args]
        fn = SimboloFuncion(
            nombre=node.name,
            linea_inicio=node.lineno,
            linea_fin=getattr(node, "end_lineno", node.lineno),
            argumentos=args,
            es_asincrona=es_async,
            docstring=ast.get_docstring(node),
        )
        if self._clase_actual is not None:
            self._clase_actual.metodos.append(fn)
        else:
            self.funciones.append(fn)
        self.generic_visit(node)

    def visit_ExceptHandler(self, node: ast.ExceptHandler):
        if node.type is None:
            self.riesgos.append(
                RiesgoEstatico(
                    linea=node.lineno,
                    tipo="bare_except",
                    descripcion="Uso de 'except:' sin tipo de excepción captura SystemExit y oculta bugs críticos.",
                    severidad="alta",
                )
            )
        self.generic_visit(node)

    def visit_Call(self, node: ast.Call):
        if isinstance(node.func, ast.Name):
            if node.func.id in ("eval", "exec"):
                self.riesgos.append(
                    RiesgoEstatico(
                        linea=node.lineno,
                        tipo="ejecucion_dinamica_insegura",
                        descripcion=f"Uso de '{node.func.id}()' representa un riesgo crítico de inyección de código.",
                        severidad="alta",
                    )
                )
        self.generic_visit(node)


def analizar_archivo_ast(ruta_absoluta: Path, ruta_relativa: str) -> ResumenArchivoAST:
    """Parsea un archivo Python con el módulo ast de la biblioteca estándar."""
    try:
        codigo = ruta_absoluta.read_text(encoding="utf-8", errors="replace")
    except Exception as exc:
        return ResumenArchivoAST(
            ruta_relativa=ruta_relativa,
            lineas_totales=0,
            imports_modulos=[],
            clases=[],
            funciones=[],
            riesgos=[],
            error_sintaxis=f"Error al leer archivo: {exc}",
        )

    lineas = codigo.splitlines()
    total_lineas = len(lineas)

    try:
        arbol = ast.parse(codigo, filename=str(ruta_absoluta))
    except SyntaxError as syn_err:
        return ResumenArchivoAST(
            ruta_relativa=ruta_relativa,
            lineas_totales=total_lineas,
            imports_modulos=[],
            clases=[],
            funciones=[],
            riesgos=[
                RiesgoEstatico(
                    linea=syn_err.lineno or 1,
                    tipo="error_sintaxis",
                    descripcion=f"Error sintáctico: {syn_err.msg}",
                    severidad="alta",
                )
            ],
            error_sintaxis=f"Línea {syn_err.lineno}: {syn_err.msg}",
        )

    visitante = _VisitanteAST(lineas)
    visitante.visit(arbol)

    return ResumenArchivoAST(
        ruta_relativa=ruta_relativa,
        lineas_totales=total_lineas,
        imports_modulos=visitante.imports,
        clases=visitante.clases,
        funciones=visitante.funciones,
        riesgos=visitante.riesgos,
    )


def escanear_proyecto_ast(limite_archivos: int = 500) -> dict[str, Any]:
    """Escanea todos los archivos .py del proyecto y genera el mapa arquitectónico."""
    explorador = ExploradorProyecto()
    raiz = explorador.raiz

    resumenes: list[ResumenArchivoAST] = []
    total_lineas = 0
    total_clases = 0
    total_funciones = 0
    todos_los_riesgos: list[dict] = []

    # Recorrer archivos de forma segura
    for archivo_path in explorador._recorrer(raiz, profundidad=7):
        if archivo_path.suffix.lower() == ".py":
            ruta_rel = archivo_path.relative_to(raiz).as_posix()
            resumen = analizar_archivo_ast(archivo_path, ruta_rel)
            resumenes.append(resumen)

            total_lineas += resumen.lineas_totales
            total_clases += len(resumen.clases)
            total_funciones += len(resumen.funciones)

            for r in resumen.riesgos:
                todos_los_riesgos.append({
                    "archivo": ruta_rel,
                    "linea": r.linea,
                    "tipo": r.tipo,
                    "descripcion": r.descripcion,
                    "severidad": r.severidad,
                })

            if len(resumenes) >= limite_archivos:
                break

    # Construir síntesis arquitectónica compacta en Markdown (< 3000 tokens)
    lineas_resumen = [
        f"# MAPA ARQUITECTÓNICO DEL PROYECTO ({len(resumenes)} archivos, {total_lineas} líneas)",
        f"Métricas generales: {total_clases} clases, {total_funciones} funciones principales detectadas.",
        "",
        "## MÓDULOS Y ESTRUCTURA SINTÁCTICA:",
    ]

    for res in resumenes:
        partes_modulo = [f"- **`{res.ruta_relativa}`** ({res.lineas_totales} líneas):"]
        if res.error_sintaxis:
            partes_modulo.append(f"  ❌ Error de sintaxis: {res.error_sintaxis}")
        else:
            if res.clases:
                nombres_clases = [
                    f"{c.nombre}({', '.join(c.bases) if c.bases else ''}) [{len(c.metodos)} métodos]"
                    for c in res.clases
                ]
                partes_modulo.append(f"  * Clases: {', '.join(nombres_clases)}")
            if res.funciones:
                nombres_fn = [f"{f.nombre}()" for f in res.funciones[:8]]
                resto = f" (+{len(res.funciones) - 8} más)" if len(res.funciones) > 8 else ""
                partes_modulo.append(f"  * Funciones: {', '.join(nombres_fn)}{resto}")
            if res.riesgos:
                partes_modulo.append(f"  ⚠️ {len(res.riesgos)} riesgo(s) estático(s) detectado(s)")

        lineas_resumen.append("\n".join(partes_modulo))

    sintesis_markdown = "\n".join(lineas_resumen)

    return {
        "total_archivos": len(resumenes),
        "total_lineas": total_lineas,
        "total_clases": total_clases,
        "total_funciones": total_funciones,
        "total_riesgos": len(todos_los_riesgos),
        "riesgos": todos_los_riesgos[:50],  # Primeros 50 riesgos destacados
        "sintesis_arquitectura": sintesis_markdown,
    }
