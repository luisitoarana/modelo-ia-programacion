"""Generador de dataset sintético — renderiza código Python como imágenes.

Para entrenar el modelo de visión propio necesitamos pares:

    (imagen_de_codigo, instrucción_texto, respuesta_texto)

En lugar de descargar capturas reales de IDEs (que tienen ruido y
problemas de copyright), las generamos sintéticamente:

    Snippet Python (texto) → PIL.Image renderizada con fuente monoespaciada
                          → guardada como PNG
                          → pareada con metadata JSONL

Estilo visual rotado para variar:
    - Editor claro estilo VS Code Light
    - Editor oscuro estilo VS Code Dark
    - Terminal verde sobre negro
    - Jupyter notebook con celda

Esto da al ViT ejemplos diversos del "look" del código real, mientras
mantenemos control total sobre la verdad (sabemos exactamente qué hay
en cada imagen, sin OCR errors).

Output:
    data/vision/
        imagenes/
            img_000001.png
            img_000002.png
            ...
        pares.jsonl   ← {"imagen": "img_000001.png", "instruccion": "...",
                         "respuesta": "...", "codigo": "..."}
"""

from __future__ import annotations

import argparse
import json
import random
from dataclasses import dataclass
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


# ════════════════════════════════════════════════════════════════════
# Paletas / temas visuales
# ════════════════════════════════════════════════════════════════════

@dataclass(frozen=True)
class Tema:
    nombre: str
    fondo: tuple[int, int, int]
    texto: tuple[int, int, int]
    palabra_clave: tuple[int, int, int]
    cadena: tuple[int, int, int]
    comentario: tuple[int, int, int]
    numero: tuple[int, int, int]
    funcion: tuple[int, int, int]


TEMAS: list[Tema] = [
    # VS Code Dark
    Tema(
        "vscode_dark",
        fondo=(30, 30, 30),
        texto=(212, 212, 212),
        palabra_clave=(86, 156, 214),
        cadena=(206, 145, 120),
        comentario=(106, 153, 85),
        numero=(181, 206, 168),
        funcion=(220, 220, 170),
    ),
    # VS Code Light
    Tema(
        "vscode_light",
        fondo=(255, 255, 255),
        texto=(0, 0, 0),
        palabra_clave=(0, 0, 255),
        cadena=(163, 21, 21),
        comentario=(0, 128, 0),
        numero=(9, 134, 88),
        funcion=(121, 94, 38),
    ),
    # Terminal verde
    Tema(
        "terminal_verde",
        fondo=(0, 0, 0),
        texto=(0, 255, 0),
        palabra_clave=(0, 255, 0),
        cadena=(0, 255, 0),
        comentario=(0, 180, 0),
        numero=(0, 255, 0),
        funcion=(0, 255, 0),
    ),
    # Monokai
    Tema(
        "monokai",
        fondo=(39, 40, 34),
        texto=(248, 248, 242),
        palabra_clave=(249, 38, 114),
        cadena=(230, 219, 116),
        comentario=(117, 113, 94),
        numero=(174, 129, 255),
        funcion=(166, 226, 46),
    ),
]


PALABRAS_CLAVE = {
    "def", "class", "return", "if", "elif", "else", "for", "while", "in",
    "import", "from", "as", "with", "try", "except", "finally", "raise",
    "pass", "break", "continue", "lambda", "yield", "async", "await",
    "True", "False", "None", "and", "or", "not", "is", "self",
}


# ════════════════════════════════════════════════════════════════════
# Renderizado de un snippet
# ════════════════════════════════════════════════════════════════════

def _cargar_fuente(tam: int = 16) -> ImageFont.FreeTypeFont | ImageFont.ImageFont:
    """Busca una fuente monoespaciada disponible en el sistema."""
    candidatos = [
        r"C:\Windows\Fonts\consola.ttf",     # Consolas
        r"C:\Windows\Fonts\cour.ttf",        # Courier New
        r"C:\Windows\Fonts\lucon.ttf",       # Lucida Console
        "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf",
        "/System/Library/Fonts/Menlo.ttc",
    ]
    for ruta in candidatos:
        try:
            return ImageFont.truetype(ruta, tam)
        except OSError:
            continue
    return ImageFont.load_default()


def _color_token(token: str, tema: Tema) -> tuple[int, int, int]:
    """Asigna color a un token muy básicamente (sin lexer real)."""
    if token in PALABRAS_CLAVE:
        return tema.palabra_clave
    if token.startswith(("'", '"')):
        return tema.cadena
    if token.startswith("#"):
        return tema.comentario
    if token.replace(".", "").isdigit():
        return tema.numero
    return tema.texto


def _tokens_simple(linea: str) -> list[tuple[str, str]]:
    """Tokenización muy básica para colorear. Devuelve (tipo, texto)."""
    tokens: list[tuple[str, str]] = []
    i = 0
    # Comentario completo
    s = linea.lstrip()
    if s.startswith("#"):
        return [("comentario", linea)]

    actual = ""
    while i < len(linea):
        ch = linea[i]
        if ch in (" ", "\t", "(", ")", ":", ",", "[", "]", "=", "+", "-", "*", "/", "."):
            if actual:
                tokens.append(("ident", actual))
                actual = ""
            tokens.append(("sep", ch))
            i += 1
            continue
        if ch in ("'", '"'):
            if actual:
                tokens.append(("ident", actual))
                actual = ""
            comilla = ch
            j = i + 1
            while j < len(linea) and linea[j] != comilla:
                j += 1
            tokens.append(("cadena", linea[i : j + 1]))
            i = j + 1
            continue
        actual += ch
        i += 1
    if actual:
        tokens.append(("ident", actual))
    return tokens


def renderizar_codigo(
    codigo: str,
    tema: Tema,
    image_size: int = 224,
    tam_fuente: int = 13,
    padding: int = 12,
) -> Image.Image:
    """Renderiza un snippet Python como imagen cuadrada `image_size×image_size`.

    Aplica syntax highlight básico según `tema`. Si el código no entra,
    se recorta. Si sobra espacio, queda fondo del tema.
    """
    img = Image.new("RGB", (image_size, image_size), tema.fondo)
    draw = ImageDraw.Draw(img)
    fuente = _cargar_fuente(tam_fuente)

    # Estimar altura de línea
    bbox = draw.textbbox((0, 0), "Ag", font=fuente)
    altura_linea = (bbox[3] - bbox[1]) + 2

    y = padding
    for linea in codigo.split("\n"):
        if y + altura_linea > image_size - padding:
            break
        x = padding
        # Renderizar token a token con su color
        for tipo, texto in _tokens_simple(linea):
            if tipo == "comentario":
                color = tema.comentario
            elif tipo == "cadena":
                color = tema.cadena
            elif tipo == "sep":
                color = tema.texto
            else:
                color = _color_token(texto, tema)
            try:
                draw.text((x, y), texto, fill=color, font=fuente)
                bb = draw.textbbox((x, y), texto, font=fuente)
                x = bb[2]
            except Exception:
                draw.text((x, y), texto, fill=color)
                x += len(texto) * (tam_fuente // 2)
            if x > image_size - padding:
                break
        y += altura_linea

    return img


# ════════════════════════════════════════════════════════════════════
# Banco de snippets + instrucciones
# ════════════════════════════════════════════════════════════════════

SNIPPETS: list[dict[str, str]] = [
    {
        "codigo": (
            "def factorial(n):\n"
            "    if n <= 1:\n"
            "        return 1\n"
            "    return n * factorial(n - 1)\n"
            "\n"
            "print(factorial(5))"
        ),
        "instruccion": "¿Qué hace este código?",
        "respuesta": (
            "Define una función recursiva `factorial(n)` que calcula n! "
            "multiplicando n por factorial(n-1) hasta que n ≤ 1, donde "
            "devuelve 1. La línea final imprime factorial(5), que es 120."
        ),
    },
    {
        "codigo": (
            "for i in range(10):\n"
            "    if i % 2 == 0:\n"
            "        print(i, 'par')\n"
            "    else:\n"
            "        print(i, 'impar')"
        ),
        "instruccion": "Explica este bucle.",
        "respuesta": (
            "Itera desde i=0 hasta i=9. Para cada valor, comprueba si "
            "es divisible por 2 (i % 2 == 0). Si sí, imprime el número "
            "seguido de 'par'; si no, de 'impar'."
        ),
    },
    {
        "codigo": (
            "import json\n"
            "\n"
            "with open('datos.json') as f:\n"
            "    datos = json.load(f)\n"
            "\n"
            "for usuario in datos['usuarios']:\n"
            "    print(usuario['nombre'])"
        ),
        "instruccion": "¿Qué hace este script?",
        "respuesta": (
            "Importa el módulo `json`, abre el archivo `datos.json` y lo "
            "carga como diccionario Python. Luego recorre la lista "
            "`datos['usuarios']` e imprime el campo `nombre` de cada uno."
        ),
    },
    {
        "codigo": (
            "class Pila:\n"
            "    def __init__(self):\n"
            "        self.items = []\n"
            "\n"
            "    def push(self, x):\n"
            "        self.items.append(x)\n"
            "\n"
            "    def pop(self):\n"
            "        return self.items.pop()"
        ),
        "instruccion": "Describe esta clase.",
        "respuesta": (
            "Implementa una pila (LIFO) usando una lista interna. `push` "
            "añade un elemento al final con `append`, y `pop` lo retira "
            "del final con `pop()`. Es el comportamiento típico de stack."
        ),
    },
    {
        "codigo": (
            "# Buscar el máximo de una lista\n"
            "nums = [3, 7, 2, 9, 1, 8]\n"
            "maximo = nums[0]\n"
            "for n in nums[1:]:\n"
            "    if n > maximo:\n"
            "        maximo = n\n"
            "print(maximo)"
        ),
        "instruccion": "¿Cuál es el output?",
        "respuesta": (
            "Recorre la lista comparando cada elemento con `maximo`, "
            "actualizándolo cuando encuentra uno mayor. El máximo de "
            "[3, 7, 2, 9, 1, 8] es 9, por lo que imprime 9."
        ),
    },
    {
        "codigo": (
            "def fib(n):\n"
            "    a, b = 0, 1\n"
            "    for _ in range(n):\n"
            "        a, b = b, a + b\n"
            "    return a\n"
            "\n"
            "print([fib(i) for i in range(8)])"
        ),
        "instruccion": "Explica el algoritmo.",
        "respuesta": (
            "Calcula el n-ésimo Fibonacci iterativamente: parte de a=0, "
            "b=1 y en cada paso desplaza (a, b) ← (b, a+b). La line final "
            "imprime los primeros 8 Fibonacci: [0,1,1,2,3,5,8,13]."
        ),
    },
    {
        "codigo": (
            "try:\n"
            "    x = int(input())\n"
            "    print(10 / x)\n"
            "except ZeroDivisionError:\n"
            "    print('No se puede dividir entre cero')\n"
            "except ValueError:\n"
            "    print('Entrada no es entero')"
        ),
        "instruccion": "¿Qué errores maneja?",
        "respuesta": (
            "Maneja dos excepciones: `ZeroDivisionError` si el usuario "
            "introduce 0 (división por cero) y `ValueError` si la "
            "entrada no se puede convertir a entero con `int()`."
        ),
    },
    {
        "codigo": (
            "def cuadrado(x):\n"
            "    return x * x\n"
            "\n"
            "resultados = list(map(cuadrado, [1, 2, 3, 4]))\n"
            "print(resultados)"
        ),
        "instruccion": "¿Qué imprime?",
        "respuesta": (
            "`map` aplica la función `cuadrado` a cada elemento de la "
            "lista. Se convierte a lista y se imprime [1, 4, 9, 16]."
        ),
    },
]


# ════════════════════════════════════════════════════════════════════
# Generador principal
# ════════════════════════════════════════════════════════════════════

def generar_dataset(
    salida: Path,
    n_muestras: int = 1000,
    image_size: int = 224,
    semilla: int = 42,
) -> dict[str, int]:
    """Genera `n_muestras` imágenes + su JSONL en `salida/`.

    Returns:
        dict con estadísticas {imagenes, temas_usados, snippets_unicos}.
    """
    random.seed(semilla)
    salida.mkdir(parents=True, exist_ok=True)
    dir_imgs = salida / "imagenes"
    dir_imgs.mkdir(exist_ok=True)
    pares_path = salida / "pares.jsonl"

    contador_tema: dict[str, int] = {t.nombre: 0 for t in TEMAS}
    snippets_usados: set[int] = set()

    with pares_path.open("w", encoding="utf-8") as f:
        for i in range(n_muestras):
            snippet_idx = random.randrange(len(SNIPPETS))
            snippet = SNIPPETS[snippet_idx]
            tema = random.choice(TEMAS)
            tam_fuente = random.choice([12, 13, 14, 15])

            img = renderizar_codigo(
                snippet["codigo"], tema, image_size, tam_fuente,
            )
            nombre = f"img_{i:06d}.png"
            img.save(dir_imgs / nombre, "PNG")
            contador_tema[tema.nombre] += 1
            snippets_usados.add(snippet_idx)

            registro = {
                "imagen": nombre,
                "tema": tema.nombre,
                "instruccion": snippet["instruccion"],
                "respuesta": snippet["respuesta"],
                "codigo": snippet["codigo"],
            }
            f.write(json.dumps(registro, ensure_ascii=False) + "\n")

    return {
        "imagenes": n_muestras,
        "temas_usados": len([t for t, c in contador_tema.items() if c > 0]),
        "snippets_unicos": len(snippets_usados),
        **{f"tema_{k}": v for k, v in contador_tema.items()},
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--salida", type=Path, default=Path("data/vision"),
        help="Directorio de salida.",
    )
    parser.add_argument("--n", type=int, default=1000, help="Número de imágenes.")
    parser.add_argument("--image-size", type=int, default=224)
    parser.add_argument("--semilla", type=int, default=42)
    args = parser.parse_args()

    stats = generar_dataset(
        salida=args.salida, n_muestras=args.n,
        image_size=args.image_size, semilla=args.semilla,
    )
    print("[OK] Dataset generado:")
    for k, v in stats.items():
        print(f"  {k}: {v}")
    print(f"  Salida: {args.salida.resolve()}")


if __name__ == "__main__":
    main()
