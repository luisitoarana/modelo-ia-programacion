"""Fine-tuning de un LLM open-source con QLoRA (4-bit + adapters LoRA).

Pensado para correr en GPUs modestas (RTX 2050 / 3060 / etc.). Toma un
modelo pre-entrenado (Qwen2.5-Coder, CodeLlama, Mistral, etc.), lo carga
en 4-bit, le pega adapters LoRA pequeños, y lo afina sobre un dataset
propio en formato JSONL.

Ventaja vs entrenar desde cero:
  * El conocimiento general de programación YA está cocinado en el modelo
    base — tú solo añades el estilo pedagógico de tu corpus.
  * Cabe en 4 GB VRAM gracias a QLoRA.
  * Termina en horas, no semanas.

Formato del dataset (JSONL):
  Cada línea es un objeto con UNO de estos formatos:

  (A) Instruction / response simple:
    {"instruction": "Explica qué es una función en Python",
     "response": "Una función es..."}

  (B) Con input opcional (estilo Alpaca):
    {"instruction": "Refactoriza este código",
     "input": "def f(x): return x*2",
     "response": "..."}

  (C) Chat completo (estilo OpenAI):
    {"messages": [
       {"role": "user", "content": "..."},
       {"role": "assistant", "content": "..."}
     ]}

  El script normaliza los tres formatos al chat template del modelo base.

Uso típico:
    pip install -r ml/requirements-finetune.txt

    # Fine-tune rápido sobre tu dataset educativo
    python -m ml.finetune \\
        --base-model Qwen/Qwen2.5-Coder-3B-Instruct \\
        --dataset datasets/raw/generado_gemini.jsonl \\
        --output models/qwen-coder-3b-explicador \\
        --epochs 3

    # Más control
    python -m ml.finetune \\
        --base-model meta-llama/CodeLlama-7b-Instruct-hf \\
        --dataset datasets/raw/curated.jsonl \\
        --output models/codellama-7b-explicador \\
        --epochs 2 --batch-size 1 --grad-accum 16 \\
        --lora-r 32 --lora-alpha 64 \\
        --learning-rate 1e-4 --max-length 1024

Después del fine-tuning, el adapter LoRA queda en --output. Se puede
cargar junto al modelo base para inferencia (peft.PeftModel.from_pretrained).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path
from typing import Any


# ───────────────────────────── Carga del dataset ─────────────────────────────

def _normalizar_ejemplo(ej: dict, tokenizer) -> dict:
    """Convierte cualquiera de los 3 formatos al chat template del modelo."""
    # Formato C: messages
    if "messages" in ej and isinstance(ej["messages"], list):
        messages = ej["messages"]
    else:
        # Formato A o B
        instruction = ej.get("instruction") or ej.get("pregunta") or ej.get("prompt") or ""
        input_text = ej.get("input") or ""
        response = ej.get("response") or ej.get("output") or ej.get("respuesta") or ""
        if not instruction or not response:
            return {"text": ""}  # se filtra después
        user_content = instruction
        if input_text:
            user_content = f"{instruction}\n\n{input_text}"
        messages = [
            {"role": "user", "content": user_content},
            {"role": "assistant", "content": response},
        ]

    # Aplicar el chat template del modelo (cada modelo tiene el suyo).
    try:
        text = tokenizer.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=False
        )
    except Exception:
        # Fallback genérico si el tokenizer no tiene chat_template.
        partes = []
        for m in messages:
            rol = m["role"].upper()
            partes.append(f"<|{rol}|>\n{m['content']}\n")
        text = "".join(partes) + "<|END|>"
    return {"text": text}


def _cargar_jsonl(ruta: str) -> list[dict]:
    ejemplos: list[dict] = []
    with open(ruta, "r", encoding="utf-8") as f:
        for i, linea in enumerate(f, 1):
            linea = linea.strip()
            if not linea:
                continue
            try:
                ejemplos.append(json.loads(linea))
            except json.JSONDecodeError as e:
                print(f"  ⚠ línea {i} inválida (saltada): {e}")
    return ejemplos


# ───────────────────────────── Main ─────────────────────────────

def main() -> None:
    p = argparse.ArgumentParser(
        description="Fine-tuning QLoRA de un LLM open-source.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    p.add_argument(
        "--base-model",
        default="Qwen/Qwen2.5-Coder-3B-Instruct",
        help="Modelo base (id de HuggingFace). Default: Qwen2.5-Coder-3B-Instruct.",
    )
    p.add_argument(
        "--dataset",
        required=True,
        help="Ruta al archivo JSONL con ejemplos de entrenamiento.",
    )
    p.add_argument(
        "--output",
        required=True,
        help="Carpeta de salida donde se guardará el adapter LoRA.",
    )
    p.add_argument("--epochs", type=int, default=3)
    p.add_argument("--batch-size", type=int, default=1,
                   help="Mantén en 1 para 4 GB VRAM.")
    p.add_argument("--grad-accum", type=int, default=8,
                   help="Batch efectivo = batch-size × grad-accum.")
    p.add_argument("--learning-rate", type=float, default=2e-4)
    p.add_argument("--max-length", type=int, default=1024,
                   help="Tokens máx por ejemplo. Baja a 512 si te quedas sin VRAM.")
    p.add_argument("--lora-r", type=int, default=16,
                   help="Rank del adapter LoRA (8-64 típico).")
    p.add_argument("--lora-alpha", type=int, default=32)
    p.add_argument("--lora-dropout", type=float, default=0.05)
    p.add_argument("--max-samples", type=int, default=None,
                   help="Para pruebas rápidas: limita el dataset a N ejemplos.")
    p.add_argument("--warmup-ratio", type=float, default=0.03)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--no-4bit", action="store_true",
                   help="Carga en FP16 en vez de 4-bit (solo si tienes >=12 GB VRAM).")
    args = p.parse_args()

    # ── Validar dataset ──
    ruta_ds = Path(args.dataset)
    if not ruta_ds.exists():
        print(f"❌ Dataset no encontrado: {ruta_ds}")
        sys.exit(1)
    print(f"📂 Leyendo {ruta_ds}…")
    ejemplos_raw = _cargar_jsonl(str(ruta_ds))
    if args.max_samples:
        ejemplos_raw = ejemplos_raw[: args.max_samples]
    if not ejemplos_raw:
        print("❌ Dataset vacío.")
        sys.exit(1)
    print(f"   {len(ejemplos_raw)} ejemplos cargados.")

    # ── Imports pesados solo aquí (errores claros si faltan) ──
    print("📦 Cargando dependencias de fine-tuning…")
    try:
        import torch
        from datasets import Dataset
        from transformers import (
            AutoModelForCausalLM,
            AutoTokenizer,
            BitsAndBytesConfig,
            TrainingArguments,
        )
        from peft import (
            LoraConfig,
            get_peft_model,
            prepare_model_for_kbit_training,
        )
        from trl import SFTTrainer, SFTConfig
    except ImportError as e:
        print(f"❌ Falta una dependencia: {e}")
        print("   Instala con: pip install -r ml/requirements-finetune.txt")
        sys.exit(1)

    # ── Cargar tokenizer + modelo base ──
    print(f"🤖 Cargando modelo base: {args.base_model}")
    tokenizer = AutoTokenizer.from_pretrained(args.base_model, trust_remote_code=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    if args.no_4bit:
        print("   (Cargando en FP16 — sin cuantización)")
        model = AutoModelForCausalLM.from_pretrained(
            args.base_model,
            torch_dtype=torch.float16,
            device_map="auto",
            trust_remote_code=True,
        )
    else:
        print("   (Cargando en 4-bit con QLoRA)")
        bnb = BitsAndBytesConfig(
            load_in_4bit=True,
            bnb_4bit_quant_type="nf4",
            bnb_4bit_compute_dtype=torch.bfloat16,
            bnb_4bit_use_double_quant=True,
        )
        model = AutoModelForCausalLM.from_pretrained(
            args.base_model,
            quantization_config=bnb,
            device_map="auto",
            trust_remote_code=True,
        )
        model = prepare_model_for_kbit_training(model)

    # ── Configurar LoRA ──
    print(f"🧩 Configurando LoRA (r={args.lora_r}, alpha={args.lora_alpha})")
    # Los módulos objetivo varían por arquitectura. Estos cubren la mayoría
    # de modelos modernos (LLaMA-like, Qwen, Mistral).
    target_modules = _detectar_target_modules(model)
    lora_config = LoraConfig(
        r=args.lora_r,
        lora_alpha=args.lora_alpha,
        lora_dropout=args.lora_dropout,
        bias="none",
        task_type="CAUSAL_LM",
        target_modules=target_modules,
    )
    model = get_peft_model(model, lora_config)
    model.print_trainable_parameters()

    # ── Preparar dataset ──
    print("📝 Normalizando dataset al chat template del modelo…")
    ejemplos_norm = []
    for e in ejemplos_raw:
        n = _normalizar_ejemplo(e, tokenizer)
        if n["text"]:
            ejemplos_norm.append(n)
    print(f"   {len(ejemplos_norm)} ejemplos válidos tras normalización.")
    if not ejemplos_norm:
        print("❌ Ningún ejemplo válido. Revisa el formato del dataset.")
        sys.exit(1)
    dataset = Dataset.from_list(ejemplos_norm)

    # ── Configurar entrenamiento ──
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"💾 Salida: {output_dir.absolute()}")

    sft_config = SFTConfig(
        output_dir=str(output_dir),
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.batch_size,
        gradient_accumulation_steps=args.grad_accum,
        gradient_checkpointing=True,
        learning_rate=args.learning_rate,
        warmup_ratio=args.warmup_ratio,
        lr_scheduler_type="cosine",
        logging_steps=10,
        save_strategy="epoch",
        save_total_limit=2,
        bf16=torch.cuda.is_bf16_supported() if torch.cuda.is_available() else False,
        fp16=not (torch.cuda.is_bf16_supported() if torch.cuda.is_available() else False),
        optim="paged_adamw_8bit" if not args.no_4bit else "adamw_torch",
        max_seq_length=args.max_length,
        dataset_text_field="text",
        packing=False,
        seed=args.seed,
        report_to="none",  # cambia a "tensorboard" si quieres curvas
    )

    trainer = SFTTrainer(
        model=model,
        args=sft_config,
        train_dataset=dataset,
        tokenizer=tokenizer,
    )

    # ── Entrenar ──
    print()
    print("=" * 60)
    print("🚀 ARRANCANDO FINE-TUNING")
    print(f"   Modelo: {args.base_model}")
    print(f"   Ejemplos: {len(ejemplos_norm)}")
    print(f"   Épocas: {args.epochs}")
    print(f"   Batch efectivo: {args.batch_size * args.grad_accum}")
    print(f"   Max length: {args.max_length}")
    print("=" * 60)
    print()

    trainer.train()

    # ── Guardar adapter ──
    print()
    print("💾 Guardando adapter LoRA…")
    trainer.save_model(str(output_dir))
    tokenizer.save_pretrained(str(output_dir))
    print(f"✓ Listo. Adapter en: {output_dir.absolute()}")
    print()
    print("Para usar el modelo afinado en inferencia:")
    print()
    print("   from peft import PeftModel")
    print("   from transformers import AutoModelForCausalLM, AutoTokenizer")
    print(f"   base = AutoModelForCausalLM.from_pretrained('{args.base_model}')")
    print(f"   model = PeftModel.from_pretrained(base, '{output_dir}')")
    print(f"   tokenizer = AutoTokenizer.from_pretrained('{output_dir}')")


def _detectar_target_modules(model) -> list[str]:
    """Detecta los nombres de los Linear de atención/MLP del modelo.

    Los nombres varían: LLaMA usa q_proj/k_proj/..., GPT-2 usa c_attn,
    etc. Buscamos los típicos y devolvemos los que existen.
    """
    candidatos = [
        # LLaMA, Qwen, Mistral
        "q_proj", "k_proj", "v_proj", "o_proj",
        "gate_proj", "up_proj", "down_proj",
        # GPT-2
        "c_attn", "c_proj", "c_fc",
        # MPT, Falcon
        "Wqkv", "out_proj",
    ]
    presentes = set()
    for nombre, _ in model.named_modules():
        # nombre es la ruta jerárquica, p. ej. "model.layers.0.self_attn.q_proj"
        ultimo = nombre.split(".")[-1]
        if ultimo in candidatos:
            presentes.add(ultimo)
    if not presentes:
        # Fallback seguro
        return ["q_proj", "v_proj"]
    return sorted(presentes)


if __name__ == "__main__":
    main()
