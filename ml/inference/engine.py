"""Motor de inferencia unificado: el modelo propio responde SIN APIs.

Soporta:
  - Arquitectura V1 (GPTEducativo + BPETokenizer)
  - Arquitectura V2 SOTA (GPTEducativoV2 con RoPE/GQA/SwiGLU/RMSNorm + SentencePiece)
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from pathlib import Path

import torch

from ml.config import ModelConfig, resolver_device
from ml.model import GPTEducativo
from ml.model.transformer_v2 import GPTEducativoV2, ModelConfigV2
from ml.tokenizer.bpe import BPETokenizer


@dataclass(slots=True)
class RespuestaModelo:
    texto: str
    tokens_generados: int
    latencia_segundos: float
    device: str


class InferenceEngine:
    """Carga el LLM propio (V1 o V2) y genera respuestas educativas."""

    def __init__(
        self,
        checkpoint_path: str | Path,
        *,
        tokenizer_path: str | Path | None = None,
        device: str = "auto",
    ) -> None:
        self.device = resolver_device(device)
        self.checkpoint_path = Path(checkpoint_path)
        ckpt = torch.load(self.checkpoint_path, map_location=self.device, weights_only=False)

        # 1. Determinar si es V1 o V2
        is_v2 = "modelo_cfg" in ckpt or (
            "model_config" in ckpt and "n_kv_head" in ckpt["model_config"]
        )
        self.es_v2 = is_v2

        if is_v2:
            cfg_dict = ckpt.get("modelo_cfg") or ckpt.get("model_config")
            self.model_cfg = ModelConfigV2(**cfg_dict)
            self.model = GPTEducativoV2(self.model_cfg)
        else:
            self.model_cfg = ModelConfig.from_dict(ckpt["model_config"])
            self.model = GPTEducativo(self.model_cfg)

        self.model.load_state_dict(ckpt["model_state"])
        self.model.to(self.device)
        self.model.eval()

        # 2. Resolver y cargar Tokenizer
        tok_file = self._resolver_tokenizer(tokenizer_path, ckpt)
        self._cargar_tokenizer(tok_file)

    def _resolver_tokenizer(
        self, tokenizer_path: str | Path | None, ckpt: dict
    ) -> Path:
        if tokenizer_path and Path(tokenizer_path).exists():
            return Path(tokenizer_path)

        en_ckpt = ckpt.get("tokenizer_path")
        if en_ckpt and Path(en_ckpt).exists():
            return Path(en_ckpt)

        raiz = Path(__file__).resolve().parents[2]
        candidatos = [
            raiz / "ml" / "tokenizer" / "artefactos" / "sp_v2_16k.model",
            raiz / "ml" / "tokenizer" / "artefactos" / "sp_v2_16k.json",
            raiz / "ml" / "tokenizer" / "artefactos" / "tokenizer_tesis_v1.json",
            raiz / "ml" / "tokenizer" / "artefactos" / "tokenizer_sanity_check.json",
        ]
        for c in candidatos:
            if c.exists():
                return c

        raise FileNotFoundError(
            "No se encontró ningún tokenizer válido en ml/tokenizer/artefactos/."
        )

    def _cargar_tokenizer(self, tok_path: Path) -> None:
        self.tok_path = tok_path
        if tok_path.suffix == ".model":
            import sentencepiece as spm

            sp = spm.SentencePieceProcessor()
            sp.Load(str(tok_path))
            self.tokenizer = sp
            self.tipo_tok = "spm"
            end_id = sp.piece_to_id("<|end|>")
            self.eos_id = end_id if end_id != -1 else sp.eos_id()
        else:
            self.tokenizer = BPETokenizer.cargar(tok_path)
            self.tipo_tok = "bpe"
            self.eos_id = getattr(self.tokenizer, "eos_id", None)

    @property
    def num_parametros(self) -> int:
        return self.model.num_parametros()

    def responder(
        self,
        instruccion: str,
        *,
        entrada: str = "",
        max_nuevos_tokens: int = 200,
        temperatura: float = 0.5,
        top_k: int | None = 40,
        top_p: float | None = 0.95,
        repetition_penalty: float = 1.25,
    ) -> RespuestaModelo:
        t0 = time.perf_counter()

        use_autocast = (self.device == "cuda" or (isinstance(self.device, torch.device) and self.device.type == "cuda"))

        if self.tipo_tok == "spm":
            # Plantilla SOTA V2
            prompt = f"<|user|>{instruccion}"
            if entrada:
                prompt += f"\n{entrada}"
            prompt += "<|end|><|assistant|>"
            prompt_ids = self.tokenizer.encode_as_ids(prompt)
            idx = torch.tensor([prompt_ids], dtype=torch.long, device=self.device)

            if use_autocast:
                with torch.autocast("cuda", dtype=torch.float16):
                    salida = self.model.generar(
                        idx,
                        max_new_tokens=max_nuevos_tokens,
                        temperatura=temperatura,
                        top_k=top_k,
                        top_p=top_p,
                        eos_token=self.eos_id,
                        repetition_penalty=repetition_penalty,
                    )
            else:
                salida = self.model.generar(
                    idx,
                    max_new_tokens=max_nuevos_tokens,
                    temperatura=temperatura,
                    top_k=top_k,
                    top_p=top_p,
                    eos_token=self.eos_id,
                    repetition_penalty=repetition_penalty,
                )
            latencia = time.perf_counter() - t0
            generado = salida[0].tolist()[len(prompt_ids):]
            texto = self.tokenizer.decode_ids(generado).strip()
            if "<|end|>" in texto:
                texto = texto.split("<|end|>")[0].strip()
        else:
            prompt_ids = self.tokenizer.encode_plantilla(
                instruccion=instruccion, entrada=entrada, salida=None
            )
            idx = torch.tensor([prompt_ids], dtype=torch.long, device=self.device)

            if use_autocast:
                with torch.autocast("cuda", dtype=torch.float16):
                    salida = self.model.generar(
                        idx,
                        max_nuevos_tokens=max_nuevos_tokens,
                        temperatura=temperatura,
                        top_k=top_k,
                        top_p=top_p,
                        eos_token=self.tokenizer.eos_id,
                    )
            else:
                salida = self.model.generar(
                    idx,
                    max_nuevos_tokens=max_nuevos_tokens,
                    temperatura=temperatura,
                    top_k=top_k,
                    top_p=top_p,
                    eos_token=self.tokenizer.eos_id,
                )
            latencia = time.perf_counter() - t0
            generado = salida[0].tolist()[len(prompt_ids):]
            texto = self.tokenizer.decode(generado, omitir_especiales=True).strip()

        return RespuestaModelo(
            texto=texto,
            tokens_generados=len(generado),
            latencia_segundos=round(latencia, 3),
            device=self.device,
        )
