"""Entrenador de los 6 reward models multi-criterio.

Pipeline:
    1. Lee un JSONL etiquetado (formato salida de `etiquetar_dataset.py`):
       {"prompt": "...", "respuesta": "...", "scores": {"SEG":8, "LEG":7, ...}}
    2. Tokeniza prompt+respuesta con sentencepiece.
    3. Entrena `MultiCriteriaRewardModel` con MSE multi-dim (default)
       o pairwise ranking loss (si el dataset tiene pares).
    4. Evalúa con Pearson correlation y accuracy de ranking.
    5. Guarda checkpoints con resume support.

Uso:
    python -m ml.rlhf.entrenar_rm --config ml/rlhf/configs/rm_v1.yaml

Config YAML mínimo (ml/rlhf/configs/rm_v1.yaml):
    modelo:
      preset: mediano        # pequeno / mediano / grande
    tokenizer: ml/tokenizer/artefactos/sp_v2_16k.model
    corpus:
      jsonl: datasets/etiquetado/scores_v1.jsonl
      val_split: 0.1
    training:
      per_device_batch_size: 8
      grad_accum_steps: 2
      epocas: 3
      learning_rate: 1e-4
      modo_loss: mse         # mse | ranking
      gradient_checkpointing: false
    salida: training/checkpoints/RM_v1
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

from ml.config import resolver_device
from ml.data.schema import DIMENSIONES_PUNTUACION
from ml.rlhf.reward_model import (
    MultiCriteriaRewardModel,
    PRESETS_RM,
    RewardConfig,
    loss_mse_multi,
    loss_ranking_multi,
)
from ml.training.run_fase import _Tokenizer, cargar_config


# ════════════════════════════════════════════════════════════════════
# Dataset
# ════════════════════════════════════════════════════════════════════

class RMScoresDataset(IterableDataset):
    """Lee JSONL etiquetado y emite (input_ids, attention_mask, scores).

    Soporta dos modos:
        - "mse": {"prompt", "respuesta", "scores": {dim: 0-10}}
        - "ranking": {"prompt", "chosen", "rejected", "dim": "SEG"|...}
          emite (input_chosen, mask_chosen, input_rejected, mask_rejected, dim)
    """

    def __init__(self, jsonl: Path, tokenizer: _Tokenizer, block_size: int,
                 *, modo: str = "mse",
                 split: str = "train", val_split: float = 0.1,
                 shuffle_seed: int = 42):
        self.jsonl = jsonl
        self.tok = tokenizer
        self.block_size = block_size
        self.modo = modo
        self.split = split
        self.val_split = val_split
        self.shuffle_seed = shuffle_seed

    def _es_para_este_split(self, idx: int) -> bool:
        # Split determinista por índice: los primeros val_split% van a val.
        # Como el dataset se mezcla globalmente, esto es razonable.
        rng = random.Random(self.shuffle_seed + idx)
        r = rng.random()
        in_val = r < self.val_split
        return (self.split == "val" and in_val) or (self.split == "train" and not in_val)

    def _tokenizar(self, prompt: str, respuesta: str) -> tuple[list[int], list[int]]:
        """Combina prompt+respuesta y devuelve (input_ids, attention_mask).

        Trunca por el final si excede block_size (mantenemos el prompt).
        """
        texto = f"{prompt.strip()}\n\n{respuesta.strip()}"
        ids = self.tok.codificar(texto)[:self.block_size]
        mask = [1] * len(ids)
        # Padding
        pad = self.block_size - len(ids)
        if pad > 0:
            ids = ids + [0] * pad
            mask = mask + [0] * pad
        return ids, mask

    def __iter__(self) -> Iterator:
        with self.jsonl.open(encoding="utf-8") as f:
            for i, linea in enumerate(f):
                if not self._es_para_este_split(i):
                    continue
                linea = linea.strip()
                if not linea:
                    continue
                try:
                    obj = json.loads(linea)
                except json.JSONDecodeError:
                    continue

                if self.modo == "mse":
                    prompt = obj.get("prompt") or obj.get("instruccion") or ""
                    respuesta = obj.get("respuesta") or obj.get("salida") or ""
                    scores = obj.get("scores") or {}
                    # Solo emitir si las 6 dimensiones están presentes
                    if not all(d in scores for d in DIMENSIONES_PUNTUACION):
                        continue
                    ids, mask = self._tokenizar(prompt, respuesta)
                    scores_t = torch.tensor(
                        [scores[d] for d in DIMENSIONES_PUNTUACION],
                        dtype=torch.float,
                    )
                    yield (
                        torch.tensor(ids, dtype=torch.long),
                        torch.tensor(mask, dtype=torch.long),
                        scores_t,
                    )

                elif self.modo == "ranking":
                    prompt = obj.get("prompt") or ""
                    chosen = obj.get("chosen") or ""
                    rejected = obj.get("rejected") or ""
                    dim = obj.get("dim") or obj.get("dimension")
                    if not (prompt and chosen and rejected and dim):
                        continue
                    if dim not in DIMENSIONES_PUNTUACION:
                        continue
                    ids_ch, mask_ch = self._tokenizar(prompt, chosen)
                    ids_rj, mask_rj = self._tokenizar(prompt, rejected)
                    dim_idx = DIMENSIONES_PUNTUACION.index(dim)
                    yield (
                        torch.tensor(ids_ch, dtype=torch.long),
                        torch.tensor(mask_ch, dtype=torch.long),
                        torch.tensor(ids_rj, dtype=torch.long),
                        torch.tensor(mask_rj, dtype=torch.long),
                        torch.tensor(dim_idx, dtype=torch.long),
                    )


# ════════════════════════════════════════════════════════════════════
# Trainer
# ════════════════════════════════════════════════════════════════════

@dataclass
class _RMState:
    paso: int = 0
    mejor_val_loss: float = float("inf")
    mejor_pearson: float = -1.0
    tiempo_total_segundos: float = 0.0


class RMTrainer:
    """Trainer para `MultiCriteriaRewardModel`."""

    def __init__(self, cfg: dict, *, resume_path: Path | None = None):
        self.cfg = cfg
        self.device = resolver_device(cfg.get("device", "auto"))
        torch.manual_seed(cfg.get("seed", 42))

        # Tokenizer
        self.tok = _Tokenizer(Path(cfg["tokenizer"]))

        # Modelo
        self.rm_cfg = self._resolver_rm_cfg()
        self.rm_cfg.vocab_size = self.tok.vocab_size
        self.modelo = MultiCriteriaRewardModel(self.rm_cfg).to(self.device)
        if cfg.get("training", {}).get("gradient_checkpointing"):
            # Activar manualmente en el encoder (no tiene método público;
            # usamos checkpoint sobre cada bloque en runtime — simple fix
            # sería extender el encoder con un flag igual al GPTEducativoV2,
            # pero por ahora dejamos sin GC dado que el RM es pequeño).
            print("[warn] gradient_checkpointing solicitado pero el RM es pequeño; "
                  "se ignora (cabe sin GC).", flush=True)

        # Optimizador
        tcfg = cfg.get("training", {})
        self.lr_inicial = float(tcfg.get("learning_rate", 1e-4))
        self.lr_min = float(tcfg.get("min_learning_rate", self.lr_inicial * 0.1))
        self.weight_decay = float(tcfg.get("weight_decay", 0.05))
        decay, no_decay = [], []
        for _, p in self.modelo.named_parameters():
            if not p.requires_grad:
                continue
            (decay if p.ndim >= 2 else no_decay).append(p)
        grupos = [
            {"params": decay, "weight_decay": self.weight_decay},
            {"params": no_decay, "weight_decay": 0.0},
        ]
        self.opt = torch.optim.AdamW(
            grupos, lr=self.lr_inicial, betas=(0.9, 0.95),
        )

        # AMP
        self.dtype = self._resolver_dtype(tcfg.get("dtype", "auto"))
        self.autocast_dtype = {"float16": torch.float16,
                               "bfloat16": torch.bfloat16,
                               "float32": torch.float32}[self.dtype]
        self.usar_amp = self.device == "cuda" and self.dtype != "float32"
        self.scaler = torch.amp.GradScaler(enabled=self.dtype == "float16")

        # Loop hyperparams
        self.batch_size = int(tcfg.get("per_device_batch_size", 8))
        self.grad_accum = int(tcfg.get("grad_accum_steps", 1))
        self.grad_clip = float(tcfg.get("grad_clip", 1.0))
        self.epocas = int(tcfg.get("epocas", 3))
        self.max_pasos = int(tcfg.get("max_pasos", 0)) or None
        self.warmup_ratio = float(tcfg.get("warmup_ratio", 0.03))
        self.eval_cada = int(tcfg.get("eval_cada", 200))
        self.save_cada = int(tcfg.get("save_cada", 500))
        self.log_cada = int(tcfg.get("log_cada", 25))
        self.modo_loss = tcfg.get("modo_loss", "mse")
        if self.modo_loss not in ("mse", "ranking"):
            raise ValueError(f"modo_loss inválido: {self.modo_loss}")

        # Pesos por dimensión
        self.pesos_dim = cfg.get("pesos_dim", {
            "SEG": 1.5, "ARQ": 1.2, "MAN": 1.0,
            "LEG": 1.0, "ESC": 0.8, "REN": 0.8,
        })

        # Datasets
        corpus = cfg["corpus"]
        jsonl = Path(corpus["jsonl"])
        val_split = float(corpus.get("val_split", 0.1))
        self.train_ds = RMScoresDataset(
            jsonl, self.tok, self.rm_cfg.block_size,
            modo=self.modo_loss, split="train",
            val_split=val_split, shuffle_seed=cfg.get("seed", 42),
        )
        self.val_ds = RMScoresDataset(
            jsonl, self.tok, self.rm_cfg.block_size,
            modo=self.modo_loss, split="val",
            val_split=val_split, shuffle_seed=cfg.get("seed", 42),
        )
        self.train_dl = DataLoader(self.train_ds, batch_size=self.batch_size, num_workers=0)
        self.val_dl = DataLoader(self.val_ds, batch_size=self.batch_size, num_workers=0)

        # Estado
        self.estado = _RMState()
        self.salida_dir = Path(cfg["salida"])
        self.salida_dir.mkdir(parents=True, exist_ok=True)
        self.metricas_path = self.salida_dir / "metrics.jsonl"

        if resume_path and resume_path.exists():
            self._cargar_estado(resume_path)

        self._abortar = False
        signal.signal(signal.SIGINT, lambda *a: setattr(self, "_abortar", True))

        # Persistir config resuelta para reproducibilidad de tesis
        ruta_cfg = self.salida_dir / "config_resuelta.json"
        ruta_cfg.write_text(json.dumps({
            "rm_cfg": asdict(self.rm_cfg),
            "cfg": cfg,
            "device": self.device,
            "dtype": self.dtype,
            "modelo_params": self.modelo.num_parametros(),
        }, indent=2, ensure_ascii=False), encoding="utf-8")

    # ────────────────────────────────────────────────────────────────
    # Setup helpers
    # ────────────────────────────────────────────────────────────────

    def _resolver_rm_cfg(self) -> RewardConfig:
        mcfg = self.cfg.get("modelo", {})
        preset = mcfg.get("preset")
        if preset:
            if preset not in PRESETS_RM:
                raise ValueError(f"preset RM desconocido: {preset}")
            return PRESETS_RM[preset]()
        return RewardConfig(**mcfg.get("custom", {}))

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

    # ────────────────────────────────────────────────────────────────
    # Loop
    # ────────────────────────────────────────────────────────────────

    def _paso_mse(self, batch) -> tuple[torch.Tensor, dict[str, float]]:
        input_ids, mask, scores_t = batch
        input_ids = input_ids.to(self.device)
        mask = mask.to(self.device)
        scores_t = scores_t.to(self.device)  # (B, 6)

        with torch.autocast(device_type="cuda", dtype=self.autocast_dtype,
                            enabled=self.usar_amp):
            scores_pred = self.modelo(input_ids, mask)
            # targets como dict
            targets = {d: scores_t[:, i]
                       for i, d in enumerate(DIMENSIONES_PUNTUACION)}
            loss, detalle = loss_mse_multi(
                scores_pred, targets, pesos=self.pesos_dim,
                score_max=self.rm_cfg.score_max,
            )
        return loss, detalle

    def _paso_ranking(self, batch) -> tuple[torch.Tensor, dict[str, float]]:
        ids_ch, mask_ch, ids_rj, mask_rj, dim_idx = batch
        ids_ch, mask_ch = ids_ch.to(self.device), mask_ch.to(self.device)
        ids_rj, mask_rj = ids_rj.to(self.device), mask_rj.to(self.device)
        with torch.autocast(device_type="cuda", dtype=self.autocast_dtype,
                            enabled=self.usar_amp):
            sc_ch = self.modelo(ids_ch, mask_ch)
            sc_rj = self.modelo(ids_rj, mask_rj)
            loss, detalle = loss_ranking_multi(sc_ch, sc_rj, pesos=self.pesos_dim)
        return loss, detalle

    @torch.no_grad()
    def _evaluar(self) -> dict[str, float]:
        self.modelo.eval()
        losses = []
        preds_por_dim: dict[str, list[float]] = {d: [] for d in DIMENSIONES_PUNTUACION}
        targets_por_dim: dict[str, list[float]] = {d: [] for d in DIMENSIONES_PUNTUACION}

        for i, batch in enumerate(self.val_dl):
            if i >= 100:  # Tope para eval rápida
                break
            if self.modo_loss == "mse":
                input_ids, mask, scores_t = batch
                input_ids = input_ids.to(self.device)
                mask = mask.to(self.device)
                scores_t = scores_t.to(self.device)
                with torch.autocast(device_type="cuda", dtype=self.autocast_dtype,
                                    enabled=self.usar_amp):
                    scores_pred = self.modelo(input_ids, mask)
                    targets = {d: scores_t[:, j]
                               for j, d in enumerate(DIMENSIONES_PUNTUACION)}
                    loss, _ = loss_mse_multi(scores_pred, targets,
                                             pesos=self.pesos_dim,
                                             score_max=self.rm_cfg.score_max)
                losses.append(loss.item())
                for d in DIMENSIONES_PUNTUACION:
                    preds_por_dim[d].extend(scores_pred[d].cpu().tolist())
                    targets_por_dim[d].extend(targets[d].cpu().tolist())
            else:
                loss, _ = self._paso_ranking(batch)
                losses.append(loss.item())

        self.modelo.train()

        resultado: dict[str, float] = {
            "val_loss": sum(losses) / len(losses) if losses else float("nan"),
        }

        # Pearson por dimensión (solo en modo MSE)
        if self.modo_loss == "mse":
            pearsons = []
            for d in DIMENSIONES_PUNTUACION:
                p = torch.tensor(preds_por_dim[d])
                t = torch.tensor(targets_por_dim[d])
                if len(p) > 2 and t.std() > 0 and p.std() > 0:
                    r = ((p - p.mean()) * (t - t.mean())).mean() / (p.std() * t.std() + 1e-8)
                    resultado[f"pearson_{d}"] = r.item()
                    pearsons.append(r.item())
            if pearsons:
                resultado["pearson_promedio"] = sum(pearsons) / len(pearsons)

        return resultado

    def _guardar_ckpt(self, sufijo: str) -> Path:
        ruta = self.salida_dir / f"checkpoint_{sufijo}.pt"
        torch.save({
            "model_state": self.modelo.state_dict(),
            "opt_state": self.opt.state_dict(),
            "scaler_state": self.scaler.state_dict() if self.scaler.is_enabled() else None,
            "state": asdict(self.estado),
            "rm_cfg": asdict(self.rm_cfg),
        }, ruta)
        return ruta

    def _set_lr(self, lr: float) -> None:
        for pg in self.opt.param_groups:
            pg["lr"] = lr

    def _registrar(self, paso: int, **kv) -> None:
        with self.metricas_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps({"paso": paso, "timestamp": time.time(), **kv}) + "\n")

    def entrenar(self) -> None:
        # Pasos totales aproximados: epocas * (n_ejemplos / batch). No podemos
        # contar `n_ejemplos` sin pasada extra; usamos max_pasos como tope si
        # se da, sino estimamos por defecto.
        total_pasos = self.max_pasos or (self.epocas * 5000)
        print(f"[rm-train] modelo: {self.modelo.num_parametros()/1e6:.1f}M params  "
              f"device={self.device}  dtype={self.dtype}  modo={self.modo_loss}",
              flush=True)
        print(f"[rm-train] total_pasos={total_pasos}  batch={self.batch_size}  "
              f"grad_accum={self.grad_accum}  lr={self.lr_inicial}", flush=True)

        self.modelo.train()
        inicio = time.time()
        train_iter = iter(self.train_dl)
        losses = []
        paso_fn = self._paso_mse if self.modo_loss == "mse" else self._paso_ranking

        while self.estado.paso < total_pasos and not self._abortar:
            self.opt.zero_grad(set_to_none=True)
            loss_acum = 0.0
            for _ in range(self.grad_accum):
                try:
                    batch = next(train_iter)
                except StopIteration:
                    train_iter = iter(self.train_dl)
                    batch = next(train_iter)
                loss, _ = paso_fn(batch)
                loss = loss / self.grad_accum
                if self.scaler.is_enabled():
                    self.scaler.scale(loss).backward()
                else:
                    loss.backward()
                loss_acum += loss.item()

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
            self.estado.paso += 1

            if self.estado.paso % self.log_cada == 0:
                avg = sum(losses[-self.log_cada:]) / min(self.log_cada, len(losses))
                vel = self.estado.paso / max(1, time.time() - inicio)
                eta_min = (total_pasos - self.estado.paso) / vel / 60 if vel > 0 else 0
                print(f"[paso {self.estado.paso:5d}/{total_pasos}] loss={avg:.4f}  "
                      f"lr={lr_actual:.2e}  vel={vel:.2f}p/s  ETA={eta_min:.0f} min",
                      flush=True)
                self._registrar(self.estado.paso, loss_train=avg, lr=lr_actual)

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
                # Mejor Pearson también es interesante
                pr = metricas.get("pearson_promedio")
                if pr is not None and pr > self.estado.mejor_pearson:
                    self.estado.mejor_pearson = pr

            if self.estado.paso % self.save_cada == 0:
                self._guardar_ckpt("ultimo")

        ruta_final = self._guardar_ckpt("ultimo")
        print(f"\n[done] paso={self.estado.paso}  mejor_val={self.estado.mejor_val_loss:.4f}  "
              f"mejor_pearson_promedio={self.estado.mejor_pearson:.4f}", flush=True)
        print(f"        final: {ruta_final}", flush=True)


# ════════════════════════════════════════════════════════════════════
# CLI
# ════════════════════════════════════════════════════════════════════

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", required=True, help="YAML del entrenamiento RM")
    parser.add_argument("--resume", help="Checkpoint para reanudar")
    args = parser.parse_args()

    cfg = cargar_config(Path(args.config))
    resume = Path(args.resume) if args.resume else None
    trainer = RMTrainer(cfg, resume_path=resume)
    trainer.entrenar()


if __name__ == "__main__":
    main()
