"""DPO (Direct Preference Optimization) — implementación desde cero.

Refina un modelo pre-entrenado usando pares (chosen, rejected) sin
necesitar un reward model separado ni rollouts costosos (a diferencia de
PPO clásico).

Paper: Rafailov et al., "Direct Preference Optimization: Your Language
       Model is Secretly a Reward Model", NeurIPS 2023.

═══════════════════════════════════════════════════════════════════
La intuición en una frase
═══════════════════════════════════════════════════════════════════

Tomamos dos modelos:
    - π_ref : modelo de REFERENCIA, congelado (copia del checkpoint pre-DPO)
    - π_θ   : modelo a ENTRENAR (parte de los mismos pesos, se actualiza)

Para cada par (prompt x, chosen y_w, rejected y_l) queremos que π_θ:
    - Asigne MÁS probabilidad a y_w que π_ref lo hacía
    - Asigne MENOS probabilidad a y_l que π_ref lo hacía

La función de pérdida DPO es:

    L = -log σ( β · [ (log π_θ(y_w|x) - log π_ref(y_w|x))
                    - (log π_θ(y_l|x) - log π_ref(y_l|x)) ] )

donde:
    - β controla cuánto el modelo puede ALEJARSE de π_ref (típico 0.1)
    - σ es la sigmoide

La belleza: minimizar L es matemáticamente equivalente a maximizar la
recompensa implícita r(x, y) = β·log(π_θ(y|x)/π_ref(y|x)) bajo el
Bradley-Terry model de preferencias. Sin reward model entrenado aparte.

═══════════════════════════════════════════════════════════════════
Uso
═══════════════════════════════════════════════════════════════════

    python -m ml.rlhf.dpo \
        --base-checkpoint training/checkpoints/tesis_v2_best.pt \
        --pares ml/data/dpo_v1.jsonl \
        --salida training/checkpoints/tesis_v2_dpo.pt \
        --epocas 3 \
        --batch 2 \
        --beta 0.1 \
        --lr 5e-7

Formato de los pares (JSONL):
    {"prompt": "...", "chosen": "...", "rejected": "...", "source": "..."}
"""

from __future__ import annotations

import argparse
import json
import math
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Iterator

import torch
import torch.nn.functional as F
from torch.utils.data import DataLoader, Dataset

from ml.config import PRESETS, resolver_device
from ml.model.transformer import GPTEducativo
from ml.tokenizer.sp_tokenizer import SPTokenizer


# ════════════════════════════════════════════════════════════════════
# Dataset de pares
# ════════════════════════════════════════════════════════════════════

@dataclass
class PreferenciaTokenizada:
    """Un par tokenizado listo para alimentar al modelo."""
    prompt_ids: torch.Tensor       # (P,)
    chosen_ids: torch.Tensor       # (C,) — solo la respuesta, sin prompt
    rejected_ids: torch.Tensor     # (R,) — solo la respuesta, sin prompt


class DatasetPares(Dataset):
    """Carga un JSONL con pares y tokeniza on-the-fly."""

    def __init__(
        self,
        ruta: Path,
        tokenizer: SPTokenizer,
        max_prompt_len: int = 256,
        max_resp_len: int = 256,
    ) -> None:
        self.tok = tokenizer
        self.max_prompt = max_prompt_len
        self.max_resp = max_resp_len
        self.pares: list[dict] = []
        with ruta.open("r", encoding="utf-8") as f:
            for linea in f:
                linea = linea.strip()
                if not linea:
                    continue
                try:
                    obj = json.loads(linea)
                    if all(k in obj for k in ("prompt", "chosen", "rejected")):
                        self.pares.append(obj)
                except json.JSONDecodeError:
                    continue

    def __len__(self) -> int:
        return len(self.pares)

    def __getitem__(self, i: int) -> PreferenciaTokenizada:
        par = self.pares[i]
        prompt_ids = self.tok.codificar(par["prompt"])[: self.max_prompt]
        chosen_ids = self.tok.codificar(par["chosen"])[: self.max_resp]
        rejected_ids = self.tok.codificar(par["rejected"])[: self.max_resp]
        return PreferenciaTokenizada(
            prompt_ids=torch.tensor(prompt_ids, dtype=torch.long),
            chosen_ids=torch.tensor(chosen_ids, dtype=torch.long),
            rejected_ids=torch.tensor(rejected_ids, dtype=torch.long),
        )


def collate_pares(batch: list[PreferenciaTokenizada], pad_id: int = 0
                  ) -> dict[str, torch.Tensor]:
    """Junta un batch de PreferenciaTokenizada en tensores padded.

    Devuelve dict con:
        chosen_input:  (B, T_chosen) — prompt + chosen, padded
        rejected_input:(B, T_rejected) — prompt + rejected, padded
        chosen_labels: (B, T_chosen) — -100 en padding y en parte del prompt
        rejected_labels:(B, T_rejected)
    """
    # Construir secuencias prompt+respuesta
    chosen_seqs = []
    chosen_labels = []
    rejected_seqs = []
    rejected_labels = []

    for ex in batch:
        # CHOSEN: concatenar prompt + respuesta
        seq_c = torch.cat([ex.prompt_ids, ex.chosen_ids])
        lbl_c = seq_c.clone()
        # Solo aprendemos sobre los tokens de la RESPUESTA, no del prompt.
        lbl_c[: len(ex.prompt_ids)] = -100
        chosen_seqs.append(seq_c)
        chosen_labels.append(lbl_c)

        # REJECTED: lo mismo
        seq_r = torch.cat([ex.prompt_ids, ex.rejected_ids])
        lbl_r = seq_r.clone()
        lbl_r[: len(ex.prompt_ids)] = -100
        rejected_seqs.append(seq_r)
        rejected_labels.append(lbl_r)

    # Padding hasta el largo máximo del batch
    def _pad(tensores: list[torch.Tensor], valor: int) -> torch.Tensor:
        max_len = max(t.size(0) for t in tensores)
        out = torch.full((len(tensores), max_len), valor, dtype=torch.long)
        for i, t in enumerate(tensores):
            out[i, : t.size(0)] = t
        return out

    return {
        "chosen_input": _pad(chosen_seqs, pad_id),
        "chosen_labels": _pad(chosen_labels, -100),
        "rejected_input": _pad(rejected_seqs, pad_id),
        "rejected_labels": _pad(rejected_labels, -100),
    }


# ════════════════════════════════════════════════════════════════════
# Cálculo de log-probabilidades de una secuencia
# ════════════════════════════════════════════════════════════════════

def logprobs_de_etiquetas(
    modelo: GPTEducativo,
    input_ids: torch.Tensor,
    labels: torch.Tensor,
) -> torch.Tensor:
    """Devuelve la log-prob de la respuesta bajo `modelo`, por ejemplo.

    Para cada secuencia del batch, suma log p(token_t | tokens_<t) sobre
    los tokens cuya etiqueta es distinta de -100 (es decir, sobre la
    respuesta, no sobre el prompt).

    Returns:
        Tensor (B,) con la log-prob acumulada de la respuesta.
    """
    # Forward sin labels (queremos los logits crudos).
    logits, _ = modelo(input_ids, targets=None)
    # logits: (B, T, V)
    # Shift: predecimos token_t a partir de los anteriores.
    # logits[:, t-1, :] -> distribución sobre token_t
    logits = logits[:, :-1, :].contiguous()      # (B, T-1, V)
    targets = labels[:, 1:].contiguous()          # (B, T-1)

    log_probs = F.log_softmax(logits, dim=-1)     # (B, T-1, V)

    # Marcamos -100 con 0 temporalmente para gather (esos no contribuyen)
    mascara = (targets != -100)
    targets_seguros = targets.masked_fill(~mascara, 0)

    # Gather: para cada (B, T) recoger log p[token_real]
    sel = log_probs.gather(dim=-1, index=targets_seguros.unsqueeze(-1)).squeeze(-1)
    sel = sel * mascara.float()                   # poner 0 donde labels=-100

    return sel.sum(dim=-1)                        # (B,)


# ════════════════════════════════════════════════════════════════════
# Pérdida DPO
# ════════════════════════════════════════════════════════════════════

def loss_dpo(
    logp_chosen_pol: torch.Tensor,
    logp_rejected_pol: torch.Tensor,
    logp_chosen_ref: torch.Tensor,
    logp_rejected_ref: torch.Tensor,
    beta: float = 0.1,
) -> tuple[torch.Tensor, dict[str, float]]:
    """Calcula la pérdida DPO + métricas para tracking.

    Args:
        logp_chosen_pol:   log π_θ(y_w | x)  — política a entrenar
        logp_rejected_pol: log π_θ(y_l | x)
        logp_chosen_ref:   log π_ref(y_w | x) — modelo de referencia congelado
        logp_rejected_ref: log π_ref(y_l | x)
        beta: temperatura DPO (típico 0.1)

    Returns:
        (loss escalar, dict de métricas para logger)
    """
    # Diferencia de log-ratios entre chosen y rejected.
    pi_logratios = logp_chosen_pol - logp_rejected_pol
    ref_logratios = logp_chosen_ref - logp_rejected_ref

    logits = beta * (pi_logratios - ref_logratios)

    # Loss = -log σ(logits) = softplus(-logits) — más estable numéricamente.
    loss = F.softplus(-logits).mean()

    # Métricas
    with torch.no_grad():
        # Recompensas implícitas
        reward_chosen = beta * (logp_chosen_pol - logp_chosen_ref)
        reward_rejected = beta * (logp_rejected_pol - logp_rejected_ref)
        # ¿Cuántas veces el chosen tiene mayor recompensa? (debería tender a 1)
        accuracy = (reward_chosen > reward_rejected).float().mean()
        # Margen promedio (chosen - rejected) — debería crecer
        margin = (reward_chosen - reward_rejected).mean()

    metricas = {
        "loss": loss.item(),
        "rewards/chosen": reward_chosen.mean().item(),
        "rewards/rejected": reward_rejected.mean().item(),
        "rewards/accuracy": accuracy.item(),
        "rewards/margin": margin.item(),
    }
    return loss, metricas


# ════════════════════════════════════════════════════════════════════
# Entrenamiento DPO
# ════════════════════════════════════════════════════════════════════

def cargar_checkpoint(ruta: Path, device: str) -> tuple[GPTEducativo, dict]:
    """Carga un checkpoint y reconstruye el modelo."""
    estado = torch.load(ruta, map_location=device, weights_only=False)
    # El checkpoint contiene 'model_state' y 'model_config'
    cfg_dict = estado["model_config"]
    # Construir ModelConfig desde dict
    from ml.config import ModelConfig
    cfg = ModelConfig.from_dict(cfg_dict)
    modelo = GPTEducativo(cfg).to(device)
    modelo.load_state_dict(estado["model_state"])
    return modelo, estado


def entrenar_dpo(args: argparse.Namespace) -> None:
    """Pipeline principal de entrenamiento DPO."""
    device = resolver_device(args.device)
    print(f"[dpo] device={device}")

    # ── Cargar modelo base como POLÍTICA (entrenable) ──
    print(f"[dpo] cargando política desde {args.base_checkpoint}")
    politica, estado = cargar_checkpoint(Path(args.base_checkpoint), device)
    politica.train()

    # ── Cargar el mismo checkpoint como REFERENCIA (congelado) ──
    print("[dpo] inicializando referencia (congelada)")
    referencia, _ = cargar_checkpoint(Path(args.base_checkpoint), device)
    referencia.eval()
    for p in referencia.parameters():
        p.requires_grad = False

    n_params = politica.num_parametros()
    print(f"[dpo] política · {n_params:,} params entrenables")

    # ── Tokenizador ──
    tok_path = Path(args.tokenizer)
    print(f"[dpo] tokenizador desde {tok_path}")
    tokenizer = SPTokenizer.cargar(tok_path)

    # ── Dataset y DataLoader ──
    print(f"[dpo] cargando pares desde {args.pares}")
    dataset = DatasetPares(
        Path(args.pares), tokenizer,
        max_prompt_len=args.max_prompt, max_resp_len=args.max_resp,
    )
    print(f"[dpo] {len(dataset)} pares cargados")
    if len(dataset) == 0:
        raise RuntimeError(
            "No se cargaron pares válidos. Verifica el .jsonl con "
            "claves prompt/chosen/rejected."
        )

    loader = DataLoader(
        dataset, batch_size=args.batch, shuffle=True,
        collate_fn=lambda b: collate_pares(b, pad_id=0),
    )

    # ── Optimizador (AdamW con LR muy bajo — característico de DPO) ──
    optimizer = torch.optim.AdamW(
        politica.parameters(),
        lr=args.lr,
        betas=(0.9, 0.95),
        weight_decay=0.0,   # en DPO no se suele usar weight decay
    )

    # ── Mixed precision si hay GPU ──
    dtype = torch.bfloat16 if device == "cuda" else torch.float32
    print(f"[dpo] dtype: {dtype}")

    # ── Loop de entrenamiento ──
    total_steps = args.epocas * len(loader)
    print(f"[dpo] total_steps = {total_steps} ({args.epocas} épocas × {len(loader)} batches)")

    step = 0
    inicio = time.time()
    historico: list[dict] = []

    for epoca in range(args.epocas):
        for batch in loader:
            batch_d = {k: v.to(device) for k, v in batch.items()}

            # ─── Forward de la política sobre chosen y rejected ───
            with torch.autocast(device_type=device, dtype=dtype, enabled=(device == "cuda")):
                logp_chosen_pol = logprobs_de_etiquetas(
                    politica, batch_d["chosen_input"], batch_d["chosen_labels"])
                logp_rejected_pol = logprobs_de_etiquetas(
                    politica, batch_d["rejected_input"], batch_d["rejected_labels"])

            # ─── Forward del modelo de referencia (no acumula gradientes) ───
            with torch.no_grad():
                with torch.autocast(device_type=device, dtype=dtype, enabled=(device == "cuda")):
                    logp_chosen_ref = logprobs_de_etiquetas(
                        referencia, batch_d["chosen_input"], batch_d["chosen_labels"])
                    logp_rejected_ref = logprobs_de_etiquetas(
                        referencia, batch_d["rejected_input"], batch_d["rejected_labels"])

            # ─── Pérdida DPO + métricas ───
            loss, metricas = loss_dpo(
                logp_chosen_pol, logp_rejected_pol,
                logp_chosen_ref, logp_rejected_ref,
                beta=args.beta,
            )

            # ─── Backprop ───
            optimizer.zero_grad(set_to_none=True)
            loss.backward()
            torch.nn.utils.clip_grad_norm_(politica.parameters(), 1.0)
            optimizer.step()

            step += 1
            metricas["epoca"] = epoca
            metricas["step"] = step
            historico.append(metricas)

            if step % max(1, args.log_each) == 0:
                t = time.time() - inicio
                print(
                    f"[dpo] ep{epoca+1}/{args.epocas} step {step}/{total_steps} "
                    f"loss={metricas['loss']:.4f} "
                    f"acc={metricas['rewards/accuracy']:.3f} "
                    f"margin={metricas['rewards/margin']:+.3f} "
                    f"({t:.1f}s)"
                )

    # ── Guardar checkpoint refinado ──
    salida = Path(args.salida)
    salida.parent.mkdir(parents=True, exist_ok=True)
    torch.save({
        "model_state": politica.state_dict(),
        "model_config": estado["model_config"],
        "dpo_args": vars(args),
        "ultimo_step": step,
        "historico_metricas": historico,
    }, salida)
    print(f"[dpo] checkpoint guardado: {salida}")

    # ── Guardar métricas como CSV para gráfica ──
    csv_path = salida.parent / f"{salida.stem}_metricas.csv"
    with csv_path.open("w", encoding="utf-8") as f:
        if historico:
            keys = list(historico[0].keys())
            f.write(",".join(keys) + "\n")
            for fila in historico:
                f.write(",".join(str(fila[k]) for k in keys) + "\n")
    print(f"[dpo] métricas guardadas: {csv_path}")


# ════════════════════════════════════════════════════════════════════
# CLI
# ════════════════════════════════════════════════════════════════════

def main() -> None:
    p = argparse.ArgumentParser(
        description="Entrena DPO sobre un checkpoint pre-entrenado."
    )
    p.add_argument("--base-checkpoint", required=True,
                   help="Ruta al .pt del modelo base (pre-DPO).")
    p.add_argument("--tokenizer", required=True,
                   help="Ruta al tokenizer SentencePiece (JSON).")
    p.add_argument("--pares", required=True,
                   help="JSONL con pares {prompt, chosen, rejected}.")
    p.add_argument("--salida", required=True,
                   help="Ruta de salida del checkpoint DPO.")
    p.add_argument("--epocas", type=int, default=3)
    p.add_argument("--batch", type=int, default=2)
    p.add_argument("--lr", type=float, default=5e-7,
                   help="LR de DPO (mucho más bajo que pretraining).")
    p.add_argument("--beta", type=float, default=0.1,
                   help="Temperatura DPO. Más alto → más lejos de π_ref.")
    p.add_argument("--max-prompt", type=int, default=256)
    p.add_argument("--max-resp", type=int, default=256)
    p.add_argument("--device", default="auto")
    p.add_argument("--log-each", type=int, default=10)
    args = p.parse_args()
    entrenar_dpo(args)


if __name__ == "__main__":
    main()
