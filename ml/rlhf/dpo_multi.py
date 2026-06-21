"""DPO multi-objetivo con pesos por dimensión — Fase 5b del PLAN_ENTRENAMIENTO_V2.

Pérdida DPO clásica (Rafailov et al., NeurIPS 2023):

    L_DPO = -E[ log σ( β · (log π_θ(y_w|x) − log π_ref(y_w|x)
                              − log π_θ(y_l|x) + log π_ref(y_l|x))) ]

Donde:
    y_w  = chosen   (respuesta mejor)
    y_l  = rejected (respuesta peor)
    π_θ  = modelo entrenable (típicamente checkpoint de Fase 5a)
    π_ref = modelo de referencia congelado (típicamente la MISMA fase 5a)
    β    = 0.1 (controla cuánto se aleja π_θ de π_ref)

Multi-objetivo: en lugar de UN dataset de pares, tenemos varios pares
categorizados por DIMENSIÓN de calidad (SEG/LEG/ESC/ARQ/REN/MAN). La
pérdida total es una suma ponderada con pesos por dimensión:

    L_total = Σ_d w_d · L_DPO_d

Esto permite priorizar dimensiones (p.ej. SEG > REN para un asistente
educativo).

Esquema del dataset:
    Opción A (un archivo por dimensión):
        data/dpo_v2_SEG.jsonl  con {"prompt", "chosen", "rejected"}
        data/dpo_v2_LEG.jsonl
        ...
    Opción B (un archivo con campo "dim"):
        data/dpo_v2.jsonl      con {"prompt", "chosen", "rejected", "dim": "SEG"}

Ambas se cargan con `--config` apuntando a YAML que las describe.
"""

from __future__ import annotations

import argparse
import json
import math
import random
import signal
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Iterator

import torch
import torch.nn.functional as F
from torch.utils.data import DataLoader, IterableDataset

from ml.config import PRESETS_V2, resolver_device
from ml.data.schema import DIMENSIONES_PUNTUACION
from ml.model.transformer_v2 import GPTEducativoV2, ModelConfigV2
from ml.training.run_fase import _Tokenizer, cargar_config


# ════════════════════════════════════════════════════════════════════
# Dataset de pares por dimensión
# ════════════════════════════════════════════════════════════════════

class DPODataset(IterableDataset):
    """Lee pares DPO desde varios archivos (uno por dim) o uno solo con campo dim.

    Emite (input_chosen, labels_chosen, input_rejected, labels_rejected, dim_idx)
    donde `labels` tiene -100 para el prompt y los IDs reales para la respuesta
    (se usa para extraer los log-probs solo de la respuesta).
    """

    def __init__(self, corpus_cfg: dict, tokenizer: _Tokenizer, block_size: int,
                 *, shuffle_seed: int = 42, split: str = "train",
                 val_split: float = 0.05):
        self.tok = tokenizer
        self.block_size = block_size
        self.shuffle_seed = shuffle_seed
        self.split = split
        self.val_split = val_split

        # Resolver archivos: corpus puede tener
        #   "por_dimension": {SEG: ruta, LEG: ruta, ...}
        # o "unico": ruta (con campo dim por línea)
        self.archivos_por_dim: dict[str, Path] = {}
        self.archivo_unico: Path | None = None
        if "por_dimension" in corpus_cfg:
            for d, ruta in corpus_cfg["por_dimension"].items():
                if d not in DIMENSIONES_PUNTUACION:
                    raise ValueError(f"dimensión desconocida en corpus: {d}")
                p = Path(ruta)
                if not p.exists():
                    raise FileNotFoundError(p)
                self.archivos_por_dim[d] = p
        elif "unico" in corpus_cfg:
            self.archivo_unico = Path(corpus_cfg["unico"])
            if not self.archivo_unico.exists():
                raise FileNotFoundError(self.archivo_unico)
        else:
            raise ValueError("corpus debe tener 'por_dimension' o 'unico'")

    def _es_para_split(self, idx: int) -> bool:
        rng = random.Random(self.shuffle_seed + idx)
        r = rng.random()
        in_val = r < self.val_split
        return (self.split == "val" and in_val) or (self.split == "train" and not in_val)

    def _formatear(self, prompt: str, respuesta: str
                   ) -> tuple[list[int], list[int]]:
        """Construye input_ids + labels (con -100 en el prompt)."""
        prompt_t = f"<|user|>{prompt.strip()}<|end|><|assistant|>"
        resp_t = f"{respuesta.strip()}<|end|>"
        prompt_ids = self.tok.codificar(prompt_t)
        resp_ids = self.tok.codificar(resp_t)
        input_ids = prompt_ids + resp_ids
        labels = [-100] * len(prompt_ids) + resp_ids

        if len(input_ids) > self.block_size:
            exceso = len(input_ids) - self.block_size
            input_ids = input_ids[exceso:]
            labels = labels[exceso:]

        pad = self.block_size - len(input_ids)
        if pad > 0:
            input_ids = input_ids + [0] * pad
            labels = labels + [-100] * pad
        return input_ids, labels

    def _iterar_archivo(self, ruta: Path, dim_fija: str | None) -> Iterator:
        with ruta.open(encoding="utf-8") as f:
            for i, linea in enumerate(f):
                if not self._es_para_split(i):
                    continue
                linea = linea.strip()
                if not linea:
                    continue
                try:
                    obj = json.loads(linea)
                except json.JSONDecodeError:
                    continue
                prompt = obj.get("prompt") or obj.get("instruccion") or ""
                chosen = obj.get("chosen") or ""
                rejected = obj.get("rejected") or ""
                dim = dim_fija or obj.get("dim") or obj.get("dimension")
                if not (prompt and chosen and rejected and dim):
                    continue
                if dim not in DIMENSIONES_PUNTUACION:
                    continue

                ids_ch, lab_ch = self._formatear(prompt, chosen)
                ids_rj, lab_rj = self._formatear(prompt, rejected)
                dim_idx = DIMENSIONES_PUNTUACION.index(dim)
                yield (
                    torch.tensor(ids_ch, dtype=torch.long),
                    torch.tensor(lab_ch, dtype=torch.long),
                    torch.tensor(ids_rj, dtype=torch.long),
                    torch.tensor(lab_rj, dtype=torch.long),
                    torch.tensor(dim_idx, dtype=torch.long),
                )

    def __iter__(self) -> Iterator:
        if self.archivo_unico:
            yield from self._iterar_archivo(self.archivo_unico, None)
            return
        # Por_dimension: round-robin con shuffle dentro de cada archivo.
        iters = {d: self._iterar_archivo(ruta, d)
                 for d, ruta in self.archivos_por_dim.items()}
        activos = dict(iters)
        rng = random.Random(self.shuffle_seed)
        while activos:
            d = rng.choice(list(activos.keys()))
            try:
                yield next(activos[d])
            except StopIteration:
                del activos[d]


# ════════════════════════════════════════════════════════════════════
# Loss DPO con pesos por dimensión
# ════════════════════════════════════════════════════════════════════

def _log_prob_secuencia(logits: torch.Tensor, labels: torch.Tensor) -> torch.Tensor:
    """Suma de log-probs de los tokens en labels != -100.

    logits: (B, T, V)
    labels: (B, T) con -100 para tokens que no cuentan (prompt + padding)
    """
    # Shift: logits[:, :-1] predice labels[:, 1:]
    logits = logits[:, :-1, :]
    labels_shift = labels[:, 1:]
    mask = (labels_shift != -100)

    log_probs = F.log_softmax(logits, dim=-1)
    # gather del log_prob del label correcto. Para labels=-100 usamos 0 para
    # no romper gather, después enmascaramos.
    labels_seg = labels_shift.clamp(min=0)
    selected = log_probs.gather(-1, labels_seg.unsqueeze(-1)).squeeze(-1)
    selected = selected * mask.float()
    return selected.sum(dim=-1)  # (B,)


def loss_dpo_multi(
    logits_pi_ch: torch.Tensor, labels_ch: torch.Tensor,
    logits_pi_rj: torch.Tensor, labels_rj: torch.Tensor,
    logits_ref_ch: torch.Tensor, logits_ref_rj: torch.Tensor,
    dim_idx: torch.Tensor,
    *, beta: float, pesos_dim: dict[str, float] | None = None,
) -> tuple[torch.Tensor, dict[str, float]]:
    """DPO loss con pesos por dimensión.

    Cada item del batch viene asociado a una dimensión (en dim_idx). La
    pérdida se computa por item y se pondera por dimensión.
    """
    pesos_dim = pesos_dim or {d: 1.0 for d in DIMENSIONES_PUNTUACION}

    logp_pi_ch = _log_prob_secuencia(logits_pi_ch, labels_ch)
    logp_pi_rj = _log_prob_secuencia(logits_pi_rj, labels_rj)
    logp_ref_ch = _log_prob_secuencia(logits_ref_ch, labels_ch).detach()
    logp_ref_rj = _log_prob_secuencia(logits_ref_rj, labels_rj).detach()

    # Margen DPO por item
    margen = beta * ((logp_pi_ch - logp_ref_ch) - (logp_pi_rj - logp_ref_rj))
    perdida_por_item = -F.logsigmoid(margen)  # (B,)

    # Aplicar pesos por dimensión
    pesos_t = torch.tensor(
        [pesos_dim.get(d, 1.0) for d in DIMENSIONES_PUNTUACION],
        device=perdida_por_item.device,
    )
    pesos_item = pesos_t[dim_idx]  # (B,)
    perdida_pond = (perdida_por_item * pesos_item) / pesos_item.mean().clamp(min=1e-8)
    loss = perdida_pond.mean()

    # Métricas detalladas por dim
    detalle: dict[str, float] = {"margen_promedio": margen.mean().item(),
                                  "accuracy": (margen > 0).float().mean().item()}
    for i, d in enumerate(DIMENSIONES_PUNTUACION):
        mask_d = (dim_idx == i)
        if mask_d.any():
            detalle[f"loss_{d}"] = perdida_por_item[mask_d].mean().item()
            detalle[f"acc_{d}"] = (margen[mask_d] > 0).float().mean().item()
    return loss, detalle


# ════════════════════════════════════════════════════════════════════
# Trainer DPO
# ════════════════════════════════════════════════════════════════════

@dataclass
class _DPOState:
    paso: int = 0
    mejor_val_loss: float = float("inf")
    mejor_accuracy: float = 0.0
    tiempo_total_segundos: float = 0.0


class DPOTrainer:
    """Trainer DPO multi-objetivo. Usa GPTEducativoV2 como base."""

    def __init__(self, cfg: dict, *, resume_path: Path | None = None,
                 tiempo_max_minutos: int | None = None):
        self.cfg = cfg
        self.tiempo_max_segundos = tiempo_max_minutos * 60 if tiempo_max_minutos else None
        self.device = resolver_device(cfg.get("device", "auto"))
        torch.manual_seed(cfg.get("seed", 42))

        # Tokenizer
        self.tok = _Tokenizer(Path(cfg["tokenizer"]))

        # Modelo (cargar de Fase 5a)
        self.modelo_cfg = self._resolver_modelo_cfg()
        self.modelo_cfg.vocab_size = self.tok.vocab_size

        self.modelo = GPTEducativoV2(self.modelo_cfg).to(self.device)
        self.modelo_ref = GPTEducativoV2(self.modelo_cfg).to(self.device)

        base_path = cfg.get("modelo_base")
        if not base_path or not Path(base_path).exists():
            raise FileNotFoundError(
                f"DPO requiere modelo_base entrenado en SFT (típicamente Fase 5a). "
                f"Especifica `modelo_base` en el YAML. Recibido: {base_path}"
            )
        ck = torch.load(base_path, map_location=self.device)
        sd = ck.get("model_state") or ck.get("state_dict") or ck
        self.modelo.load_state_dict(sd, strict=False)
        self.modelo_ref.load_state_dict(sd, strict=False)
        self.modelo_ref.eval()
        for p in self.modelo_ref.parameters():
            p.requires_grad = False
        print(f"[init] modelo base cargado: {base_path}", flush=True)

        tcfg = cfg.get("training", {})
        if tcfg.get("gradient_checkpointing"):
            self.modelo.gradient_checkpointing_enable()

        # Hyperparams DPO
        self.beta = float(cfg.get("beta", 0.1))
        self.pesos_dim = cfg.get("pesos_dim", {
            "SEG": 1.5, "ARQ": 1.2, "MAN": 1.0,
            "LEG": 1.0, "ESC": 0.8, "REN": 0.8,
        })

        # Optimizador (LR mucho más bajo que SFT)
        self.lr_inicial = float(tcfg.get("learning_rate", 5e-7))
        self.lr_min = float(tcfg.get("min_learning_rate", self.lr_inicial * 0.1))
        self.weight_decay = float(tcfg.get("weight_decay", 0.0))
        self.opt = self.modelo.configurar_optimizador(
            self.weight_decay, self.lr_inicial,
            (float(tcfg.get("beta1", 0.9)), float(tcfg.get("beta2", 0.95))),
        )

        # AMP
        self.dtype = self._resolver_dtype(tcfg.get("dtype", "auto"))
        self.autocast_dtype = {"float16": torch.float16,
                               "bfloat16": torch.bfloat16,
                               "float32": torch.float32}[self.dtype]
        self.usar_amp = self.device == "cuda" and self.dtype != "float32"
        self.scaler = torch.amp.GradScaler(enabled=self.dtype == "float16")

        # Loop hyperparams
        self.batch_size = int(tcfg.get("per_device_batch_size", 1))
        self.grad_accum = int(tcfg.get("grad_accum_steps", 16))
        self.grad_clip = float(tcfg.get("grad_clip", 1.0))
        self.epocas = int(tcfg.get("epocas", 3))
        self.max_pasos = int(tcfg.get("max_pasos", 0)) or None
        self.warmup_ratio = float(tcfg.get("warmup_ratio", 0.05))
        self.eval_cada = int(tcfg.get("eval_cada", 200))
        self.save_cada = int(tcfg.get("save_cada", 500))
        self.log_cada = int(tcfg.get("log_cada", 25))

        # Datasets
        corpus = cfg["corpus"]
        seed = cfg.get("seed", 42)
        self.train_ds = DPODataset(
            corpus, self.tok, self.modelo_cfg.block_size,
            shuffle_seed=seed, split="train",
            val_split=float(corpus.get("val_split", 0.05)),
        )
        self.val_ds = DPODataset(
            corpus, self.tok, self.modelo_cfg.block_size,
            shuffle_seed=seed, split="val",
            val_split=float(corpus.get("val_split", 0.05)),
        )
        self.train_dl = DataLoader(self.train_ds, batch_size=self.batch_size, num_workers=0)
        self.val_dl = DataLoader(self.val_ds, batch_size=self.batch_size, num_workers=0)

        # Estado / persistencia
        self.estado = _DPOState()
        self.salida_dir = Path(cfg["salida"])
        self.salida_dir.mkdir(parents=True, exist_ok=True)
        self.metricas_path = self.salida_dir / "metrics.jsonl"

        if resume_path and resume_path.exists():
            self._cargar_estado(resume_path)

        self._abortar = False
        signal.signal(signal.SIGINT, lambda *a: setattr(self, "_abortar", True))

        # Persistir config
        (self.salida_dir / "config_resuelta.json").write_text(
            json.dumps({
                "cfg": cfg, "modelo_cfg": asdict(self.modelo_cfg),
                "device": self.device, "dtype": self.dtype,
                "beta": self.beta, "pesos_dim": self.pesos_dim,
            }, indent=2, ensure_ascii=False), encoding="utf-8",
        )

    # ────────────────────────────────────────────────────────────────
    # Setup helpers
    # ────────────────────────────────────────────────────────────────

    def _resolver_modelo_cfg(self) -> ModelConfigV2:
        mcfg = self.cfg.get("modelo", {})
        preset = mcfg.get("preset")
        if preset:
            if preset not in PRESETS_V2:
                raise ValueError(f"preset desconocido: {preset}")
            return PRESETS_V2[preset]()
        return ModelConfigV2(**mcfg.get("custom", {}))

    def _resolver_dtype(self, pref: str) -> str:
        if pref != "auto":
            return pref
        if self.device != "cuda":
            return "float32"
        return "bfloat16" if torch.cuda.is_bf16_supported() else "float16"

    def _cargar_estado(self, ruta: Path) -> None:
        print(f"[resume] {ruta}", flush=True)
        ck = torch.load(ruta, map_location=self.device)
        self.modelo.load_state_dict(ck["model_state"])
        self.opt.load_state_dict(ck["opt_state"])
        if ck.get("scaler_state"):
            self.scaler.load_state_dict(ck["scaler_state"])
        for k, v in ck["state"].items():
            setattr(self.estado, k, v)
        print(f"[resume] paso={self.estado.paso}  mejor_val={self.estado.mejor_val_loss:.4f}",
              flush=True)

    def _lr(self, paso: int, total_pasos: int) -> float:
        warmup = int(total_pasos * self.warmup_ratio)
        if paso < warmup:
            return self.lr_inicial * (paso + 1) / max(1, warmup)
        ratio = (paso - warmup) / max(1, total_pasos - warmup)
        coef = 0.5 * (1.0 + math.cos(math.pi * ratio))
        return self.lr_min + coef * (self.lr_inicial - self.lr_min)

    def _set_lr(self, lr: float) -> None:
        for pg in self.opt.param_groups:
            pg["lr"] = lr

    # ────────────────────────────────────────────────────────────────
    # Paso
    # ────────────────────────────────────────────────────────────────

    def _paso(self, batch) -> tuple[torch.Tensor, dict[str, float]]:
        ids_ch, lab_ch, ids_rj, lab_rj, dim_idx = batch
        ids_ch = ids_ch.to(self.device, non_blocking=True)
        lab_ch = lab_ch.to(self.device, non_blocking=True)
        ids_rj = ids_rj.to(self.device, non_blocking=True)
        lab_rj = lab_rj.to(self.device, non_blocking=True)
        dim_idx = dim_idx.to(self.device, non_blocking=True)

        with torch.autocast(device_type="cuda", dtype=self.autocast_dtype,
                            enabled=self.usar_amp):
            logits_pi_ch, _ = self.modelo(ids_ch)
            logits_pi_rj, _ = self.modelo(ids_rj)
            with torch.no_grad():
                logits_ref_ch, _ = self.modelo_ref(ids_ch)
                logits_ref_rj, _ = self.modelo_ref(ids_rj)
            loss, detalle = loss_dpo_multi(
                logits_pi_ch, lab_ch, logits_pi_rj, lab_rj,
                logits_ref_ch, logits_ref_rj, dim_idx,
                beta=self.beta, pesos_dim=self.pesos_dim,
            )
        return loss, detalle

    @torch.no_grad()
    def _evaluar(self) -> dict[str, float]:
        self.modelo.eval()
        losses, accs = [], []
        for i, batch in enumerate(self.val_dl):
            if i >= 50:
                break
            loss, det = self._paso(batch)
            losses.append(loss.item())
            accs.append(det.get("accuracy", 0.0))
        self.modelo.train()
        return {
            "val_loss": sum(losses)/len(losses) if losses else float("nan"),
            "val_accuracy": sum(accs)/len(accs) if accs else float("nan"),
        }

    def _guardar_ckpt(self, sufijo: str) -> Path:
        ruta = self.salida_dir / f"checkpoint_{sufijo}.pt"
        torch.save({
            "model_state": self.modelo.state_dict(),
            "opt_state": self.opt.state_dict(),
            "scaler_state": self.scaler.state_dict() if self.scaler.is_enabled() else None,
            "state": asdict(self.estado),
            "modelo_cfg": asdict(self.modelo_cfg),
        }, ruta)
        return ruta

    def _registrar(self, paso: int, **kv) -> None:
        with self.metricas_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps({"paso": paso, "timestamp": time.time(), **kv}) + "\n")

    def _tiempo_agotado(self) -> bool:
        return (self.tiempo_max_segundos is not None
                and self.estado.tiempo_total_segundos >= self.tiempo_max_segundos)

    # ────────────────────────────────────────────────────────────────
    # Loop principal
    # ────────────────────────────────────────────────────────────────

    def entrenar(self) -> None:
        total_pasos = self.max_pasos or (self.epocas * 3000)
        print(f"[dpo-train] modelo: {self.modelo.num_parametros()/1e6:.1f}M params  "
              f"beta={self.beta}  device={self.device}  dtype={self.dtype}", flush=True)
        print(f"[dpo-train] pesos_dim: {self.pesos_dim}", flush=True)
        print(f"[dpo-train] total_pasos={total_pasos}  batch={self.batch_size}  "
              f"grad_accum={self.grad_accum}  lr={self.lr_inicial}", flush=True)

        self.modelo.train()
        inicio = time.time()
        ultimo = inicio
        train_iter = iter(self.train_dl)
        losses, accs = [], []

        while self.estado.paso < total_pasos and not self._abortar:
            self.opt.zero_grad(set_to_none=True)
            loss_acum = 0.0
            acc_acum = 0.0
            for _ in range(self.grad_accum):
                try:
                    batch = next(train_iter)
                except StopIteration:
                    train_iter = iter(self.train_dl)
                    batch = next(train_iter)
                loss, det = self._paso(batch)
                loss = loss / self.grad_accum
                if self.scaler.is_enabled():
                    self.scaler.scale(loss).backward()
                else:
                    loss.backward()
                loss_acum += loss.item()
                acc_acum += det.get("accuracy", 0.0)
            acc_acum /= self.grad_accum

            if self.scaler.is_enabled():
                self.scaler.unscale_(self.opt)
                torch.nn.utils.clip_grad_norm_(self.modelo.parameters(), self.grad_clip)
                self.scaler.step(self.opt)
                self.scaler.update()
            else:
                torch.nn.utils.clip_grad_norm_(self.modelo.parameters(), self.grad_clip)
                self.opt.step()

            lr_actual = self._lr(self.estado.paso, total_pasos)
            self._set_lr(lr_actual)

            losses.append(loss_acum)
            accs.append(acc_acum)
            self.estado.paso += 1

            ahora = time.time()
            self.estado.tiempo_total_segundos += (ahora - ultimo)
            ultimo = ahora

            if self.estado.paso % self.log_cada == 0:
                avg_l = sum(losses[-self.log_cada:]) / min(self.log_cada, len(losses))
                avg_a = sum(accs[-self.log_cada:]) / min(self.log_cada, len(accs))
                vel = self.estado.paso / max(1, time.time() - inicio)
                eta_min = (total_pasos - self.estado.paso) / vel / 60 if vel > 0 else 0
                print(f"[paso {self.estado.paso:5d}/{total_pasos}] "
                      f"loss={avg_l:.4f}  acc={avg_a:.3f}  lr={lr_actual:.2e}  "
                      f"vel={vel:.2f}p/s  ETA={eta_min:.0f}m", flush=True)
                self._registrar(self.estado.paso, loss_train=avg_l, acc_train=avg_a,
                                lr=lr_actual)

            if self.estado.paso % self.eval_cada == 0:
                metricas = self._evaluar()
                print(f"[eval  {self.estado.paso:5d}     ] " +
                      "  ".join(f"{k}={v:.4f}" for k, v in metricas.items()),
                      flush=True)
                self._registrar(self.estado.paso, **metricas)
                vl = metricas.get("val_loss", float("inf"))
                if vl < self.estado.mejor_val_loss:
                    self.estado.mejor_val_loss = vl
                    self._guardar_ckpt("best")
                    print(f"        guardado checkpoint_best.pt (val={vl:.4f})", flush=True)
                va = metricas.get("val_accuracy", 0.0)
                if va > self.estado.mejor_accuracy:
                    self.estado.mejor_accuracy = va

            if self.estado.paso % self.save_cada == 0:
                self._guardar_ckpt("ultimo")

            if self._tiempo_agotado():
                print(f"[dpo-train] tiempo agotado, guardando...", flush=True)
                break

        ruta_final = self._guardar_ckpt("ultimo")
        print(f"\n[done] paso={self.estado.paso}  mejor_val={self.estado.mejor_val_loss:.4f}  "
              f"mejor_acc={self.estado.mejor_accuracy:.4f}\n        final: {ruta_final}",
              flush=True)


# ════════════════════════════════════════════════════════════════════
# CLI
# ════════════════════════════════════════════════════════════════════

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", required=True)
    parser.add_argument("--resume")
    parser.add_argument("--tiempo-max-minutos", type=int, default=None,
                        help="Para chunking Kaggle (540 = 9h)")
    args = parser.parse_args()

    cfg = cargar_config(Path(args.config))
    resume = Path(args.resume) if args.resume else None
    trainer = DPOTrainer(cfg, resume_path=resume,
                         tiempo_max_minutos=args.tiempo_max_minutos)
    trainer.entrenar()


if __name__ == "__main__":
    main()
