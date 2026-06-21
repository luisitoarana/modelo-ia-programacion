"""Tokenizer BPE de alto rendimiento basado en sentencepiece (C++).

Mantiene la MISMA interfaz que ``BPETokenizer`` (Python puro) para que el
resto del proyecto no se entere — solo cambia de qué módulo se importa.

Diferencia clave: el entrenamiento del BPE en C++ pasa de horas (Python
puro) a segundos para un corpus de 200k ejemplos. Para tu RTX 2050 esto
es lo que permite tener un tokenizer decente sin esperar días.

Decisión de diseño:
  * BPE con byte_fallback=True → cualquier texto se puede codificar sin <unk>.
  * Special tokens registrados como ``user_defined_symbols`` para que
    sentencepiece los reconozca y NO los rompa con BPE interno.
  * ``character_coverage=0.9995`` para cubrir tildes, ñ y la mayoría de
    símbolos manteniendo el tamaño de vocabulario bajo.
  * El modelo se guarda como base64 dentro del .json para que el formato
    de persistencia siga siendo un solo archivo.
"""

from __future__ import annotations

import base64
import io
import json
import tempfile
from pathlib import Path
from typing import Iterable

import sentencepiece as spm

from ml.tokenizer.bpe import TOKENS_ESPECIALES


class SPTokenizer:
    """Adapter sentencepiece con interfaz compatible con BPETokenizer."""

    def __init__(self) -> None:
        self.sp: spm.SentencePieceProcessor | None = None
        self.model_bytes: bytes | None = None
        self.special_to_id: dict[str, int] = {}
        self.id_to_special: dict[int, str] = {}

    # ─────────────────────────── Propiedades ───────────────────────────

    @property
    def vocab_size(self) -> int:
        return self.sp.get_piece_size() if self.sp else 0

    @property
    def primer_id_merge(self) -> int:
        # Compat con BPETokenizer (no se usa internamente aquí).
        return len(TOKENS_ESPECIALES) + 256

    @property
    def bos_id(self) -> int:
        return self.special_to_id.get("<bos>", 1)

    @property
    def eos_id(self) -> int:
        return self.special_to_id.get("<eos>", 2)

    @property
    def pad_id(self) -> int:
        return self.special_to_id.get("<pad>", 0)

    # ─────────────────────────── Entrenamiento ───────────────────────────

    def entrenar(
        self,
        textos: Iterable[str],
        vocab_size: int = 8000,
        *,
        verbose: bool = True,
    ) -> "SPTokenizer":
        """Entrena un BPE con sentencepiece sobre el iterable de textos.

        ``vocab_size`` es el TOTAL incluyendo specials, byte fallback (256)
        y bpe merges. sentencepiece lo gestiona internamente.
        """
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", suffix=".txt", delete=False
        ) as f:
            n_lineas = 0
            for t in textos:
                # Una línea por texto. Reemplaza saltos para que cada texto
                # quede en una sola línea (sentencepiece lee por líneas).
                limpio = t.replace("\n", " ").strip()
                if limpio:
                    f.write(limpio + "\n")
                    n_lineas += 1
            tmp_path = f.name

        if verbose:
            print(f"[SP] Entrenando sobre {n_lineas:,} líneas, vocab={vocab_size}")

        model_buf = io.BytesIO()
        try:
            spm.SentencePieceTrainer.train(
                input=tmp_path,
                model_writer=model_buf,
                vocab_size=vocab_size,
                model_type="bpe",
                character_coverage=0.9995,
                byte_fallback=True,
                pad_id=0,
                bos_id=1,
                eos_id=2,
                unk_id=3,
                user_defined_symbols=["<instr>", "<inp>", "<out>"],
                # Sin normalización para preservar el código tal cual.
                normalization_rule_name="identity",
                num_threads=4,
                # Por defecto sentencepiece muestrea max_sentence_length=4192
                # — bueno para nuestros ejemplos.
            )
        finally:
            Path(tmp_path).unlink(missing_ok=True)

        self.model_bytes = model_buf.getvalue()
        self.sp = spm.SentencePieceProcessor()
        self.sp.load_from_serialized_proto(self.model_bytes)

        # Mapear tokens especiales → ids.
        for token in TOKENS_ESPECIALES:
            tid = self.sp.piece_to_id(token)
            # piece_to_id devuelve unk_id si no encuentra. Validamos.
            if tid != self.sp.unk_id() or token == "<unk>":
                self.special_to_id[token] = tid
        self.id_to_special = {v: k for k, v in self.special_to_id.items()}

        if verbose:
            print(f"[SP] Listo. Vocabulario: {self.vocab_size:,} tokens.")
        return self

    # ─────────────────────────── Codificación ───────────────────────────

    def encode(
        self,
        texto: str,
        *,
        add_bos: bool = False,
        add_eos: bool = False,
    ) -> list[int]:
        if self.sp is None:
            raise RuntimeError("Tokenizer no entrenado/cargado.")
        ids: list[int] = []
        if add_bos:
            ids.append(self.bos_id)
        ids.extend(self.sp.encode(texto, out_type=int))
        if add_eos:
            ids.append(self.eos_id)
        return ids

    def encode_especial(self, token: str) -> int:
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
        if self.sp is None:
            raise RuntimeError("Tokenizer no entrenado/cargado.")
        if omitir_especiales:
            ids = [i for i in ids if i not in self.id_to_special]
        return self.sp.decode(ids)

    # ─────────────────────────── Persistencia ───────────────────────────

    def guardar(self, ruta: str | Path) -> Path:
        if self.model_bytes is None:
            raise RuntimeError("Tokenizer no entrenado.")
        ruta = Path(ruta)
        ruta.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "version": 2,
            "backend": "sentencepiece",
            "tokens_especiales": list(TOKENS_ESPECIALES),
            "special_to_id": self.special_to_id,
            "model_b64": base64.b64encode(self.model_bytes).decode("ascii"),
        }
        ruta.write_text(json.dumps(payload), encoding="utf-8")
        return ruta

    @classmethod
    def cargar(cls, ruta: str | Path) -> "SPTokenizer":
        data = json.loads(Path(ruta).read_text(encoding="utf-8"))
        if data.get("backend") != "sentencepiece":
            raise ValueError(
                "Este archivo no es un tokenizer sentencepiece. "
                "Usa BPETokenizer.cargar() para el formato antiguo."
            )
        tok = cls()
        tok.model_bytes = base64.b64decode(data["model_b64"])
        tok.sp = spm.SentencePieceProcessor()
        tok.sp.load_from_serialized_proto(tok.model_bytes)
        tok.special_to_id = {k: int(v) for k, v in data["special_to_id"].items()}
        tok.id_to_special = {v: k for k, v in tok.special_to_id.items()}
        return tok
