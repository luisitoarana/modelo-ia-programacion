"""Búsqueda web: capacidad de consultar internet (sin API key).

Usa DuckDuckGo (endpoint HTML) para obtener resultados de búsqueda. Es una
herramienta del agente: permite que el sistema se "actualice" y consulte
información fresca de la web. No requiere clave.

Nota: el scraping de buscadores puede cambiar/bloquearse; el servicio maneja
errores con elegancia y devuelve lo que pueda.
"""

from __future__ import annotations

import html
import re
import urllib.parse
from dataclasses import dataclass

import httpx

from app.utils.logger import obtener_logger


log = obtener_logger(__name__)

_DDG_HTML = "https://html.duckduckgo.com/html/"
_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0 Safari/537.36"
)

# Enlace de resultado y snippet en la página HTML de DuckDuckGo.
_RE_RESULTADO = re.compile(
    r'<a[^>]*class="result__a"[^>]*href="(?P<href>[^"]+)"[^>]*>(?P<titulo>.*?)</a>',
    re.DOTALL,
)
_RE_SNIPPET = re.compile(
    r'<a[^>]*class="result__snippet"[^>]*>(?P<snippet>.*?)</a>', re.DOTALL
)
_RE_TAGS = re.compile(r"<[^>]+>")


def _limpiar(texto: str) -> str:
    return html.unescape(_RE_TAGS.sub("", texto)).strip()


def _resolver_url(href: str) -> str:
    """DuckDuckGo envuelve las URLs en un redirect ?uddg=...; lo desenvuelve."""
    if "uddg=" in href:
        try:
            query = urllib.parse.urlparse(href).query
            params = urllib.parse.parse_qs(query)
            if "uddg" in params:
                return urllib.parse.unquote(params["uddg"][0])
        except (ValueError, KeyError):
            pass
    if href.startswith("//"):
        return "https:" + href
    return href


@dataclass(slots=True)
class ResultadoWeb:
    titulo: str
    url: str
    resumen: str

    def to_dict(self) -> dict[str, str]:
        return {"titulo": self.titulo, "url": self.url, "resumen": self.resumen}


async def buscar_web(consulta: str, *, limite: int = 8) -> list[ResultadoWeb]:
    """Busca en la web y devuelve los principales resultados."""
    consulta = (consulta or "").strip()
    if not consulta:
        return []

    try:
        async with httpx.AsyncClient(timeout=20.0, follow_redirects=True) as cliente:
            resp = await cliente.post(
                _DDG_HTML,
                data={"q": consulta, "kl": "es-es"},
                headers={"User-Agent": _UA, "Content-Type": "application/x-www-form-urlencoded"},
            )
            resp.raise_for_status()
            pagina = resp.text
    except httpx.HTTPError as exc:
        log.warning("Búsqueda web falló: %s", exc)
        raise RuntimeError(f"No se pudo realizar la búsqueda web: {exc}") from exc

    titulos = list(_RE_RESULTADO.finditer(pagina))
    snippets = list(_RE_SNIPPET.finditer(pagina))

    resultados: list[ResultadoWeb] = []
    for i, m in enumerate(titulos):
        href = m.group("href")
        if "y.js" in href or "ad_domain" in href:  # saltar anuncios
            continue
        url = _resolver_url(href)
        if "duckduckgo.com/y.js" in url:
            continue
        titulo = _limpiar(m.group("titulo"))
        resumen = _limpiar(snippets[i].group("snippet")) if i < len(snippets) else ""
        if titulo and url:
            resultados.append(ResultadoWeb(titulo=titulo, url=url, resumen=resumen))
        if len(resultados) >= limite:
            break
    return resultados
