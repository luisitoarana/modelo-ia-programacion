"""Motor de inferencia: el modelo propio responde SIN APIs.

Carga un checkpoint entrenado y el tokenizer asociado, construye el prompt
con la plantilla instrucción→respuesta y genera la salida de forma
autoregresiva. Este es el componente que reemplaza definitivamente a las
APIs externas en el flujo del estudiante.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import torch

from ml.config import ModelConfig, resolver_device
from ml.model import GPTEducativo
from ml.tokenizer.bpe import BPETokenizer


@dataclass(slots=True)
class RespuestaModelo:
    texto: str
    tokens_generados: int
    latencia_segundos: float
    device: str


class InferenceEngine:
    """Carga el LLM propio y genera respuestas educativas."""

    def __init__(
        self,
        checkpoint_path: str | Path,
        *,
        tokenizer_path: str | Path | None = None,
        device: str = "auto",
    ) -> None:
        self.device = resolver_device(device)
        ckpt = torch.load(checkpoint_path, map_location=self.device, weights_only=False)

        self.model_cfg = ModelConfig.from_dict(ckpt["model_config"])
        self.model = GPTEducativo(self.model_cfg)
        self.model.load_state_dict(ckpt["model_state"])
        self.model.to(self.device)
        self.model.eval()

        tok_path = tokenizer_path or ckpt.get("tokenizer_path")
        if not tok_path or not Path(tok_path).exists():
            raise FileNotFoundError(
                "No se encontró el tokenizer. Pasa tokenizer_path explícitamente."
            )
        self.tokenizer = BPETokenizer.cargar(tok_path)

    @property
    def num_parametros(self) -> int:
        return self.model.num_parametros()

    def responder(
        self,
        instruccion: str,
        *,
        entrada: str = "",
        max_nuevos_tokens: int = 200,
        temperatura: float = 0.8,
        top_k: int | None = 40,
        top_p: float | None = 0.95,
    ) -> RespuestaModelo:
        import time

        prompt_ids = self.tokenizer.encode_plantilla(
            instruccion=instruccion, entrada=entrada, salida=None
        )
        idx = torch.tensor([prompt_ids], dtype=torch.long, device=self.device)

        t0 = time.perf_counter()
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
