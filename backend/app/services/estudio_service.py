"""Formas paralelas propuestas: no son un instrumento psicométrico validado."""
from copy import deepcopy
from sqlalchemy import select
from app.models.estudio import ConfiguracionEstudio

VERSION = 'piloto-6-v1'
# Las competencias y la rúbrica son comunes; cambian contexto y datos.
BANCO = [
    dict(id='m1_1', modulo=1, competencia='Variables y salida',
         pre="Guarda el nombre 'Ana' y la edad 19 en dos variables. Escribe código que muestre ambos datos. Explica qué guarda cada variable y qué aparece en pantalla. Indica qué cambia si edad pasa a 20.",
         post="Guarda el nombre 'Juan' y el año 2004 en dos variables. Escribe código que muestre ambos datos. Explica qué guarda cada variable y qué aparece en pantalla. Indica qué cambia si el año pasa a 2005.",
         practica="Pide al asistente código para guardar tu nombre y tu edad en variables y mostrarlos con print(). Cambia los datos y observa el resultado."),
    dict(id='m1_2', modulo=1, competencia='Expresiones numéricas',
         pre="Un cuaderno cuesta 3 y se compran 4. Usa variables para calcular y mostrar el total. Explica la operación y qué cambia si se compran 0 cuadernos.",
         post="Hay 5 filas con 6 sillas en cada fila. Usa variables para calcular y mostrar el total. Explica la operación y qué cambia si hay 0 filas.",
         practica="Pide código que calcule el precio total de varios lápices usando precio y cantidad. Prueba otras cantidades, incluido cero."),
    dict(id='m2_1', modulo=2, competencia='Decisiones y frontera',
         pre="Con edad = 18, escribe un if/else que imprima 'Acceso permitido' si edad es mayor o igual a 18 y 'Acceso restringido' en otro caso. Explica qué imprime con 17 y con 18.",
         post="Con temperatura = 30, escribe un if/else que imprima 'Ventilador encendido' si temperatura es mayor o igual a 30 y 'Ventilador apagado' en otro caso. Explica qué imprime con 29 y con 30.",
         practica="Pide código que indique si una nota alcanza el mínimo de aprobación 7, usando if/else. Prueba notas 6, 7 y 8."),
    dict(id='m2_2', modulo=2, competencia='Bucles y acumulador',
         pre="Usa un bucle for y un acumulador para sumar [2, 4, 6] y mostrar el total. Explica cómo cambia el acumulador y qué ocurre con una lista vacía.",
         post="Usa un bucle for y un acumulador para sumar [3, 5, 7] y mostrar el total. Explica cómo cambia el acumulador y qué ocurre con una lista vacía.",
         practica="Pide código para sumar una lista de gastos con un for y un acumulador. Cambia los valores y prueba una lista vacía."),
    dict(id='m3_1', modulo=3, competencia='Funciones, parámetros y retorno',
         pre="Define calcular_total(precio, cantidad) para devolver su producto con return. Llámala con 5 y 3 y muestra el resultado. Explica la diferencia entre devolver un valor e imprimirlo. Indica qué devuelve si cantidad es 0.",
         post="Define calcular_distancia(velocidad, horas) para devolver su producto con return. Llámala con 6 y 4 y muestra el resultado. Explica la diferencia entre devolver un valor e imprimirlo. Indica qué devuelve si horas es 0.",
         practica="Pide una función que reciba base y altura y devuelva el área de un rectángulo. Llama la función con distintos valores y muestra el resultado."),
    dict(id='m3_2', modulo=3, competencia='Funciones con listas y casos límite',
         pre="Define contar_mayores(valores) para devolver cuántos elementos son mayores que 10. Usa [8, 10, 12] como ejemplo. Explica qué ocurre con 10 y con una lista vacía.",
         post="Define contar_menores(valores) para devolver cuántos elementos son menores que 5. Usa [3, 5, 7] como ejemplo. Explica qué ocurre con 5 y con una lista vacía.",
         practica="Pide una función que cuente números positivos de una lista. Prueba números negativos, cero y una lista vacía."),
]
DEFAULTS = dict(estudio_activo=False, pre_abierto=False, post_abierto=False, practica_guiada=True,
                preguntas_activas=[p['id'] for p in BANCO])


async def configuracion(sesion):
    fila = await sesion.get(ConfiguracionEstudio, 1)
    return deepcopy(DEFAULTS | (fila.datos if fila else {}))


def preguntas(fase, ids):
    return [dict(id=p['id'], modulo=p['modulo'], competencia=p['competencia'],
                 consigna=p[fase], maximo=10) for p in BANCO if p['id'] in ids]


def puntaje(entrega):
    ids = {p['id'] for p in entrega.preguntas}
    if entrega.estado != 'enviado' or not ids or set(entrega.revisiones) != ids:
        return None
    return sum(sum(entrega.revisiones[i][k] for k in ('comprension', 'codigo', 'casos_limite')) for i in ids)


def comparar(pre, post):
    if not pre or not post or puntaje(pre) is None or puntaje(post) is None:
        return dict(estado='pendiente', cambio_puntos_porcentuales=None)
    if pre.condicion != post.condicion or pre.version != post.version or {p['id'] for p in pre.preguntas} != {p['id'] for p in post.preguntas}:
        return dict(estado='no_comparable', cambio_puntos_porcentuales=None)
    a = puntaje(pre) / (10 * len(pre.preguntas)) * 100
    b = puntaje(post) / (10 * len(post.preguntas)) * 100
    return dict(estado='revisado', pre_porcentaje=round(a, 2), post_porcentaje=round(b, 2),
                cambio_puntos_porcentuales=round(b-a, 2),
                cambio_relativo_porcentaje=round((b-a)/a*100, 2) if a else None)
