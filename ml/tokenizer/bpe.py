"""Tokenizer BPE byte-level propio, en Python puro (sin dependencias).

Diseñado para procesar simultáneamente:
    - Español (lenguaje natural, con tildes y ñ).
    - Código Python (símbolos, operadores, identación, palabras reservadas).

Por qué byte-level: trabajando sobre los 256 bytes UTF-8 base, CUALQUIER
texto es representable sin "unknown tokens". El BPE aprende a fusionar pares
de bytes frecuentes hasta alcanzar el tamaño de vocabulario deseado.

Tokens especiales estructuran los ejemplos instrucción→respuesta:
    <bos> <instr> ... <inp> ... <out> ... <eos>

La pre-segmentación por regex (estilo GPT-2) evita que las fusiones crucen
fronteras poco naturales (p.ej. mezclar letras con espacios y símbolos).
"""

from __future__ import annotations

import json
import re
from collections import Counter
from pathlib import Path
from typing import Iterable


# Orden importa: estos ids especiales se asignan primero.
TOKENS_ESPECIALES: tuple[str, ...] = (
    "<pad>",
    "<bos>",
    "<eos>",
    "<instr>",   # marca el inicio de la instrucción
    "<inp>",     # marca el inicio de la entrada (código/contexto)
    "<out>",     # marca el inicio de la salida (respuesta educativa)
    "<unk>",
)

# Patrón de pre-segmentación (contracciones, letras, dígitos, símbolos, espacios).
_PATRON = re.compile(
    r"""'(?:[sdmt]|ll|ve|re)| ?[^\W\d_]+| ?\d+| ?[^\s\w]+|\s+(?!\S)|\s+""",
    re.UNICODE,
)


class BPETokenizer:
    """Tokenizer BPE byte-level entrenable."""

    def __init__(self) -> None:
        # id -> bytes (para decodificar). Los especiales mapean a b"".
        self.vocab: dict[int, bytes] = {}
        # (id_a, id_b) -> id_nuevo, en orden de aprendizaje (rango = prioridad).
        self.merges: dict[tuple[int, int], int] = {}
        self.special_to_id: dict[str, int] = {}
        self.id_to_special: dict[int, str] = {}
        self._base_listo = False

    # ------------------------------------------------------------------
    # Construcción del vocabulario base
    # ------------------------------------------------------------------
    def _inicializar_base(self) -> None:
        self.vocab = {i: bytes([i]) for i in range(256)}
        siguiente = 256
        self.special_to_id.clear()
        self.id_to_special.clear()
        for tok in TOKENS_ESPECIALES:
            self.special_to_id[tok] = siguiente
            self.id_to_special[siguiente] = tok
            self.vocab[siguiente] = b""   # los especiales no producen bytes
            siguiente += 1
        self._base_listo = True

    @property
    def primer_id_merge(self) -> int:
        return 256 + len(TOKENS_ESPECIALES)

    @property
    def vocab_size(self) -> int:
        return len(self.vocab)

    @property
    def pad_id(self) -> int:
        return self.special_to_id["<pad>"]

    @property
    def bos_id(self) -> int:
        return self.special_to_id["<bos>"]

    @property
    def eos_id(self) -> int:
        return self.special_to_id["<eos>"]

    # ------------------------------------------------------------------
    # Entrenamiento
    # ------------------------------------------------------------------
    def entrenar(
        self,
        textos: Iterable[str],
        vocab_size: int = 8000,
        *,
        verbose: bool = True,
    ) -> "BPETokenizer":
        """Aprende fusiones BPE hasta alcanzar `vocab_size`."""
        self._inicializar_base()
        objetivo_merges = max(0, vocab_size - self.primer_id_merge)

        # 1) Pre-segmentar y convertir cada "palabra" a lista de ids de byte.
        secuencias: list[list[int]] = []
        for texto in textos:
            for chunk in _PATRON.findall(texto):
                if not chunk:
                    continue
                secuencias.append(list(chunk.encode("utf-8")))

        if verbose:
            print(f"[BPE] {len(secuencias):,} segmentos. Objetivo: {objetivo_merges} fusiones.")

        siguiente_id = self.primer_id_merge

        for paso in range(objetivo_merges):
            pares = self._contar_pares(secuencias)
            if not pares:
                break
            mejor_par, freq = pares.most_common(1)[0]
            if freq < 2:
                break  # ya no hay redundancia que comprimir

            self.merges[mejor_par] = siguiente_id
            self.vocab[siguiente_id] = (
                self.vocab[mejor_par[0]] + self.vocab[mejor_par[1]]
            )
            secuencias = [self._fusionar(seq, mejor_par, siguiente_id) for seq in secuencias]

            if verbose and (paso + 1) % 500 == 0:
                print(f"[BPE] fusión {paso + 1}/{objetivo_merges} (freq={freq})")
            siguiente_id += 1

        if verbose:
            print(f"[BPE] Listo. Vocabulario final: {self.vocab_size:,} tokens.")
        return self

    @staticmethod
    def _contar_pares(secuencias: list[list[int]]) -> Counter:
        pares: Counter = Counter()
        for seq in secuencias:
            for a, b in zip(seq, seq[1:]):
                pares[(a, b)] += 1
        return pares

    @staticmethod
    def _fusionar(seq: list[int], par: tuple[int, int], nuevo_id: int) -> list[int]:
        if len(seq) < 2:
            return seq
        salida: list[int] = []
        i = 0
        a, b = par
        while i < len(seq):
            if i < len(seq) - 1 and seq[i] == a and seq[i + 1] == b:
                salida.append(nuevo_id)
                i += 2
            else:
                salida.append(seq[i])
                i += 1
        return salida

    # ------------------------------------------------------------------
    # Codificación / decodificación
    # ------------------------------------------------------------------
    def _bpe_chunk(self, chunk: str) -> list[int]:
        ids = list(chunk.encode("utf-8"))
        if len(ids) < 2:
            return ids
        # Aplica fusiones por prioridad (rango = id asignado, menor primero).
        while True:
            mejor_par = None
            mejor_rango = None
            for a, b in zip(ids, ids[1:]):
                rango = self.merges.get((a, b))
                if rango is not None and (mejor_rango is None or rango < mejor_rango):
                    mejor_rango = rango
                    mejor_par = (a, b)
            if mejor_par is None:
                break
            ids = self._fusionar(ids, mejor_par, self.merges[mejor_par])
        return ids

    def encode(
        self,
        texto: str,
        *,
        add_bos: bool = False,
        add_eos: bool = False,
    ) -> list[int]:
        if not self._base_listo:
            raise RuntimeError("El tokenizer no está entrenado ni cargado.")
        ids: list[int] = []
        if add_bos:
            ids.append(self.bos_id)
        for chunk in _PATRON.findall(texto):
            if chunk:
                ids.extend(self._bpe_chunk(chunk))
        if add_eos:
            ids.append(self.eos_id)
        return ids

    def encode_especial(self, token: str) -> int:
        """Devuelve el id de un token especial, p.ej. '<out>'."""
        return self.special_to_id[token]

    def encode_plantilla(
        self,
        *,
        instruccion: str,
        entrada: str = "",
        salida: str | None = None,
    ) -> list[int]:
        """Serializa un ejemplo al formato de entrenamiento.

            <bos><instr> instruccion <inp> entrada <out> salida <eos>

        Si `salida` es None, deja el prompt listo para inferencia (termina en <out>).
        """
        ids = [self.bos_id, self.special_to_id["<instr>"]]
        ids += self.encode(" " + instruccion.strip())
        if entrada and entrada.strip():
            ids.append(self.special_to_id["<inp>"])
            ids += self.encode(" " + entrada.strip())
        ids.append(self.special_to_id["<out>"])
        if salida is not None:
            ids += self.encode(" " + salida.strip())
            ids.append(self.eos_id)
        return ids

    def decode(self, ids: list[int], *, omitir_especiales: bool = True) -> str:
        partes: list[bytes] = []
        for i in ids:
            if i in self.id_to_special:
                if omitir_especiales:
                    continue
                partes.append(self.id_to_special[i].encode("utf-8"))
            else:
                partes.append(self.vocab.get(i, b""))
        return b"".join(partes).decode("utf-8", errors="replace")

    # ------------------------------------------------------------------
    # Persistencia
    # ------------------------------------------------------------------
    def guardar(self, ruta: str | Path) -> Path:
        ruta = Path(ruta)
        ruta.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "version": 1,
            "tokens_especiales": list(TOKENS_ESPECIALES),
            "merges": [
                {"par": [a, b], "id": nid} for (a, b), nid in self.merges.items()
            ],
        }
        ruta.write_text(json.dumps(payload, ensure_ascii=False), encoding="utf-8")
        return ruta

    @classmethod
    def cargar(cls, ruta: str | Path) -> "BPETokenizer":
        ruta = Path(ruta)
        data = json.loads(ruta.read_text(encoding="utf-8"))
        tok = cls()
        tok._inicializar_base()
        # Reconstruir merges en orden de id (importa para el vocab).
        merges = sorted(data["merges"], key=lambda m: m["id"])
        for m in merges:
            a, b = m["par"]
            nid = m["id"]
            tok.merges[(a, b)] = nid
            tok.vocab[nid] = tok.vocab[a] + tok.vocab[b]
        return tok
