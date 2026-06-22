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


# ═══════════════════════════════════════════════════════════════════════
# CLI — permite entrenar el tokenizer desde la línea de comandos.
#
# Uso:
#     python -m ml.tokenizer.sp_tokenizer train \\
#         --corpus /ruta/al/corpus.jsonl \\
#         --salida ml/tokenizer/artefactos/sp_v2_16k.model \\
#         --vocab-size 16000
#
# El corpus puede ser:
#     * Un archivo JSONL (una línea = un objeto con campos
#       instruccion/entrada/salida o instruction/input/response).
#     * Un archivo de texto plano (una línea = un texto).
# ═══════════════════════════════════════════════════════════════════════

def _iter_textos_de_corpus(ruta: Path) -> Iterable[str]:
    """Lee un JSONL o .txt y devuelve los textos a usar para entrenar
    el tokenizer. Para JSONL extrae todos los campos de texto relevantes."""
    es_jsonl = ruta.suffix.lower() in (".jsonl", ".json")
    with ruta.open("r", encoding="utf-8") as f:
        for linea in f:
            linea = linea.strip()
            if not linea:
                continue
            if not es_jsonl:
                yield linea
                continue
            try:
                obj = json.loads(linea)
            except json.JSONDecodeError:
                continue
            if not isinstance(obj, dict):
                continue
            # Extraer todos los campos de texto del schema V1 y V2.
            for campo in (
                "instruccion", "instruction",
                "entrada", "input",
                "salida", "response", "output",
            ):
                v = obj.get(campo)
                if isinstance(v, str) and v.strip():
                    yield v.strip()
            # Si tiene 'explicacion_por_nivel', extraer cada nivel.
            niveles = obj.get("explicacion_por_nivel")
            if isinstance(niveles, dict):
                for v in niveles.values():
                    if isinstance(v, str) and v.strip():
                        yield v.strip()


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(
        description="Entrena un tokenizer sentencepiece V2 sobre un corpus."
    )
    sub = parser.add_subparsers(dest="comando", required=True)

    # ── train ──
    p_train = sub.add_parser("train", help="Entrenar un tokenizer nuevo.")
    p_train.add_argument("--corpus", required=True, type=Path,
                         help="Ruta al corpus .jsonl o .txt.")
    p_train.add_argument("--salida", required=True, type=Path,
                         help="Ruta de salida del tokenizer (.model). El "
                              ".vocab se guarda junto, también un .json "
                              "con metadatos.")
    p_train.add_argument("--vocab-size", type=int, default=16000)

    # ── encode (utilidad rápida para probar el tokenizer) ──
    p_enc = sub.add_parser("encode", help="Codificar un texto.")
    p_enc.add_argument("--modelo", required=True, type=Path,
                       help="Ruta al tokenizer .json o .model")
    p_enc.add_argument("--texto", required=True)

    args = parser.parse_args()

    if args.comando == "train":
        if not args.corpus.exists():
            raise SystemExit(f"No existe el corpus: {args.corpus}")

        print(f"[SP] Leyendo corpus desde: {args.corpus}")
        textos = list(_iter_textos_de_corpus(args.corpus))
        print(f"[SP] Textos extraídos: {len(textos):,}")
        if not textos:
            raise SystemExit("ERROR: no se extrajo ningún texto del corpus.")

        tok = SPTokenizer().entrenar(
            textos, vocab_size=args.vocab_size, verbose=True,
        )

        # Guardamos en dos formatos:
        #  - .json (el formato propio del proyecto, con model_b64).
        #  - .model y .vocab (formato nativo de sentencepiece, útil
        #    para auditar y para herramientas externas).
        args.salida.parent.mkdir(parents=True, exist_ok=True)

        # Si --salida termina en .model, derivamos los nombres.
        if args.salida.suffix == ".model":
            ruta_json = args.salida.with_suffix(".json")
            ruta_model_nativo = args.salida
            ruta_vocab = args.salida.with_suffix(".vocab")
        else:
            ruta_json = args.salida.with_suffix(args.salida.suffix + ".json")
            ruta_model_nativo = args.salida.with_suffix(".model")
            ruta_vocab = args.salida.with_suffix(".vocab")

        tok.guardar(ruta_json)
        print(f"[SP] Guardado JSON:  {ruta_json}")

        if tok.model_bytes:
            ruta_model_nativo.write_bytes(tok.model_bytes)
            print(f"[SP] Guardado .model: {ruta_model_nativo}")

        # Generar .vocab (lista de piezas para inspección humana).
        if tok.sp:
            with ruta_vocab.open("w", encoding="utf-8") as f:
                for i in range(tok.vocab_size):
                    f.write(f"{tok.sp.id_to_piece(i)}\t{tok.sp.get_score(i)}\n")
            print(f"[SP] Guardado .vocab: {ruta_vocab}")

        print(f"\n[OK] Tokenizer entrenado con {tok.vocab_size:,} tokens.")

    elif args.comando == "encode":
        tok = SPTokenizer.cargar(args.modelo)
        ids = tok.encode(args.texto)
        print(f"Tokens: {len(ids)}")
        print(f"IDs:    {ids}")
        print(f"Pieces: {[tok.sp.id_to_piece(i) for i in ids]}")


if __name__ == "__main__":
    main()
