"""Inferencia con el modelo B (arquitectura V2 + tokenizer sentencepiece).

Carga un checkpoint de los entrenados con `ml/training/run_fase.py` y genera
respuestas usando la misma plantilla chat que el entrenamiento:

    <|user|>{instruccion}\n{entrada}<|end|><|assistant|>{salida}<|end|>

Uso (CLI):

    # Una sola consulta:
    python -m ml.inferencia.generar_v2 \
        --checkpoint training/checkpoints/B_sft_5k/checkpoint_ultimo.pt \
        --tokenizer ml/tokenizer/artefactos/sp_v2_16k.model \
        --prompt "Escribe una funcion Python que devuelva el promedio de una lista."

    # Modo interactivo (chat):
    python -m ml.inferencia.generar_v2 \
        --checkpoint training/checkpoints/B_sft_5k/checkpoint_ultimo.pt \
        --tokenizer ml/tokenizer/artefactos/sp_v2_16k.model

    # Suite de pruebas pedagogicas predefinidas:
    python -m ml.inferencia.generar_v2 \
        --checkpoint training/checkpoints/B_sft_5k/checkpoint_ultimo.pt \
        --tokenizer ml/tokenizer/artefactos/sp_v2_16k.model \
        --suite
"""

from __future__ import annotations

import argparse
import time
from pathlib import Path

import sentencepiece as spm
import torch

from ml.model.transformer_v2 import GPTEducativoV2, ModelConfigV2


USER_TAG = "<|user|>"
ASSISTANT_TAG = "<|assistant|>"
END_TAG = "<|end|>"


SUITE_PRUEBAS = [
    ("Generacion basica",
     "Escribe una funcion Python que reciba una lista de numeros y devuelva el promedio."),
    ("Explicacion pedagogica",
     "Explicame que es una list comprehension en Python, como si tuviera 12 anos."),
    ("Refactor",
     "Refactoriza este codigo para que sea mas pythonico:\n\nresultado = []\nfor i in range(10):\n    if i % 2 == 0:\n        resultado.append(i * i)"),
    ("Deteccion de bug",
     "Encuentra el bug en este codigo y explica:\n\ndef contar(lista):\n    total = 0\n    for x in lista:\n        total += 1\n    return x"),
    ("Seguridad",
     "Este codigo es seguro? Explica:\n\nquery = f\"SELECT * FROM users WHERE email = '{email}'\"\ncursor.execute(query)"),
    ("Espanol nativo",
     "Que es un decorador en Python y para que sirve?"),
]


def cargar_modelo(checkpoint_path: Path, device: str) -> tuple[GPTEducativoV2, dict]:
    """Carga el checkpoint y reconstruye el modelo con la config guardada."""
    ckpt = torch.load(checkpoint_path, map_location=device, weights_only=False)

    # El runner guarda modelo_cfg como dict (asdict de ModelConfigV2).
    cfg_dict = ckpt.get("modelo_cfg") or ckpt.get("model_config")
    if cfg_dict is None:
        raise ValueError(
            f"El checkpoint no tiene 'modelo_cfg'. Claves disponibles: {list(ckpt.keys())}"
        )

    cfg = ModelConfigV2(**cfg_dict)
    modelo = GPTEducativoV2(cfg)

    state_dict = ckpt.get("model_state") or ckpt.get("state_dict") or ckpt
    modelo.load_state_dict(state_dict)
    modelo.to(device)
    modelo.eval()

    return modelo, cfg_dict


def cargar_tokenizer(tokenizer_path: Path) -> spm.SentencePieceProcessor:
    """Carga el tokenizer sentencepiece nativo (.model)."""
    sp = spm.SentencePieceProcessor()
    sp.Load(str(tokenizer_path))
    return sp


def construir_prompt(instruccion: str, entrada: str = "") -> str:
    """Aplica la plantilla chat usada durante el entrenamiento (SFTDataset)."""
    prompt = f"{USER_TAG}{instruccion}"
    if entrada.strip():
        prompt += f"\n{entrada}"
    prompt += f"{END_TAG}{ASSISTANT_TAG}"
    return prompt


def generar(
    modelo: GPTEducativoV2,
    tokenizer: spm.SentencePieceProcessor,
    instruccion: str,
    *,
    entrada: str = "",
    max_nuevos_tokens: int = 200,
    temperatura: float = 0.7,
    top_k: int | None = 40,
    top_p: float | None = 0.9,
    device: str = "cuda",
) -> tuple[str, float, int]:
    """Genera una respuesta autoregresiva y devuelve (texto, latencia_s, n_tokens)."""
    prompt = construir_prompt(instruccion, entrada)
    prompt_ids = tokenizer.EncodeAsIds(prompt)
    idx = torch.tensor([prompt_ids], dtype=torch.long, device=device)

    t0 = time.perf_counter()
    with torch.no_grad():
        salida = modelo.generar(
            idx,
            max_new_tokens=max_nuevos_tokens,
            temperatura=temperatura,
            top_k=top_k,
            top_p=top_p,
        )
    latencia = time.perf_counter() - t0

    # Recortar el prompt y decodificar solo lo nuevo.
    nuevos_ids = salida[0].tolist()[len(prompt_ids):]
    texto = tokenizer.DecodeIds(nuevos_ids)

    # Cortar en END_TAG si aparece.
    if END_TAG in texto:
        texto = texto.split(END_TAG)[0]

    return texto.strip(), latencia, len(nuevos_ids)


def correr_suite(modelo, tokenizer, device: str, **gen_kwargs) -> None:
    """Ejecuta la suite de 6 pruebas pedagogicas y muestra resultados."""
    print(f"\n{'='*70}")
    print(f"  SUITE DE PRUEBAS PEDAGOGICAS — modelo B v1")
    print(f"{'='*70}\n")

    for i, (categoria, prompt_texto) in enumerate(SUITE_PRUEBAS, 1):
        print(f"\n[Prueba {i}/{len(SUITE_PRUEBAS)}] {categoria}")
        print(f"PROMPT: {prompt_texto[:100]}{'...' if len(prompt_texto) > 100 else ''}")
        print("-" * 70)
        try:
            texto, latencia, n_tokens = generar(
                modelo, tokenizer, prompt_texto, device=device, **gen_kwargs
            )
            print(f"RESPUESTA:\n{texto}\n")
            print(f"({n_tokens} tokens en {latencia:.2f}s = {n_tokens/latencia:.1f} tok/s)")
        except Exception as exc:
            print(f"ERROR: {exc}")
        print()


def modo_interactivo(modelo, tokenizer, device: str, **gen_kwargs) -> None:
    """Chat interactivo en la terminal."""
    print(f"\n{'='*70}")
    print(f"  MODO INTERACTIVO — modelo B v1")
    print(f"  (Enter en blanco para salir)")
    print(f"{'='*70}\n")

    while True:
        try:
            instr = input(">>> instruccion: ").strip()
        except (EOFError, KeyboardInterrupt):
            break
        if not instr:
            break
        try:
            texto, latencia, n_tokens = generar(
                modelo, tokenizer, instr, device=device, **gen_kwargs
            )
            print(f"\n--- RESPUESTA ({n_tokens} tokens, {latencia:.2f}s) ---")
            print(texto)
            print()
        except Exception as exc:
            print(f"ERROR: {exc}\n")


def main() -> None:
    p = argparse.ArgumentParser(
        description="Inferencia con el modelo B (V2) entrenado desde cero.",
    )
    p.add_argument("--checkpoint", required=True, type=Path,
                   help="Ruta al checkpoint .pt entrenado con run_fase.py")
    p.add_argument("--tokenizer", required=True, type=Path,
                   help="Ruta al tokenizer sentencepiece .model")
    p.add_argument("--prompt", type=str, default=None,
                   help="Una sola instruccion. Si no se pasa, modo interactivo.")
    p.add_argument("--entrada", type=str, default="",
                   help="Codigo o contexto adicional (campo 'entrada' del schema V2).")
    p.add_argument("--suite", action="store_true",
                   help="Ejecuta la suite de 6 pruebas pedagogicas predefinidas.")
    p.add_argument("--max-tokens", type=int, default=200,
                   help="Tokens nuevos a generar (default 200).")
    p.add_argument("--temperatura", type=float, default=0.7,
                   help="Sampling temperature (default 0.7).")
    p.add_argument("--top-k", type=int, default=40,
                   help="Top-k filtering (default 40, 0 para desactivar).")
    p.add_argument("--top-p", type=float, default=0.9,
                   help="Nucleus sampling (default 0.9, 0 para desactivar).")
    p.add_argument("--device", type=str, default="auto",
                   help="Device: auto / cuda / cpu (default auto).")
    args = p.parse_args()

    # Resolver device
    if args.device == "auto":
        device = "cuda" if torch.cuda.is_available() else "cpu"
    else:
        device = args.device

    print(f"[device] {device}")
    if device == "cuda":
        print(f"[cuda] {torch.cuda.get_device_name(0)} — "
              f"{torch.cuda.get_device_properties(0).total_memory / 1e9:.1f} GB total")

    # Cargar modelo
    print(f"[cargando] {args.checkpoint}")
    t0 = time.perf_counter()
    modelo, cfg_dict = cargar_modelo(args.checkpoint, device)
    print(f"[modelo] {sum(p.numel() for p in modelo.parameters()):,} params en {time.perf_counter()-t0:.1f}s")
    print(f"[arquitectura] n_layer={cfg_dict.get('n_layer')} "
          f"n_embd={cfg_dict.get('n_embd')} "
          f"vocab={cfg_dict.get('vocab_size')} "
          f"block_size={cfg_dict.get('block_size')}")

    # Cargar tokenizer
    print(f"[cargando] {args.tokenizer}")
    tokenizer = cargar_tokenizer(args.tokenizer)
    print(f"[tokenizer] vocab={tokenizer.GetPieceSize()}")

    # Parametros de generacion
    gen_kwargs = dict(
        max_nuevos_tokens=args.max_tokens,
        temperatura=args.temperatura,
        top_k=args.top_k if args.top_k > 0 else None,
        top_p=args.top_p if args.top_p > 0 else None,
    )

    # Ejecutar modo elegido
    if args.suite:
        correr_suite(modelo, tokenizer, device, **gen_kwargs)
    elif args.prompt:
        texto, latencia, n_tokens = generar(
            modelo, tokenizer, args.prompt, entrada=args.entrada,
            device=device, **gen_kwargs,
        )
        print(f"\n>>> PROMPT: {args.prompt}")
        if args.entrada:
            print(f"    ENTRADA: {args.entrada}")
        print(f"\n--- RESPUESTA ({n_tokens} tokens, {latencia:.2f}s, "
              f"{n_tokens/latencia:.1f} tok/s) ---")
        print(texto)
        print()
    else:
        modo_interactivo(modelo, tokenizer, device, **gen_kwargs)


if __name__ == "__main__":
    main()
