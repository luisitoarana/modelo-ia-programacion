"""Separa la petición actual de los archivos y turnos anteriores del editor."""
import re


def peticion_actual(texto: str) -> str:
    marcado = re.search(r'\[PETICION_USUARIO\]\s*\n(.*?)\n\[/PETICION_USUARIO\]', texto, re.S)
    if marcado:
        return marcado.group(1).strip()
    anterior = re.search(
        r'^Petición(?: actual)? del estudiante:\s*(.*?)(?=\n(?:Contexto:|Código actual en el editor|Documento Markdown/Texto|Instrucción:|Último código|Salida de error|\[RETO)|\Z)',
        texto, re.M | re.S)
    return anterior.group(1).strip() if anterior else texto.strip()


def es_creacion_nueva(texto: str) -> bool:
    if '[EDITOR_OPERACION:crear]' in texto:
        return True
    if '[EDITOR_OPERACION:' in texto:
        return False
    pedido = peticion_actual(texto)
    referencia = re.search(r'\b(corr[ií]g\w*|corrige|correg\w*|correcci[oó]n|arregl\w*|repara\w*|modifica\w*|cambia\w*|este archivo|este c[oó]digo|esta funci[oó]n|archivo actual|c[oó]digo actual)\b', pedido, re.I)
    creacion = re.search(r'\b(crea\w*|cr[eé]ame|haz(?:me)?|genera\w*|escr[ií]be\w*|escribir|dame|imprim[ae]|imprimir|muestra\w*|calcula\w*|implementa\w*)\b', pedido, re.I)
    return bool(creacion and not referencia)
