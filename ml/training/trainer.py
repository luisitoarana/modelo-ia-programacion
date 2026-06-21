"""Pipeline de entrenamiento autoregresivo.

Incluye:
  - Scheduler de learning rate (warmup + cosine decay).
  - Acumulación de gradientes (batch efectivo mayor con poca VRAM).
  - Gradient clipping.
  - Evaluación periódica en train y val.
  - Checkpoints (mejor val_loss) con config y tokenizer asociados.
  - Registro de experimentos (config.json + metrics.jsonl).
  - Autocast/bf16/fp16 en GPU; float32 en CPU.
"""

from __future__ import annotations

import json
import math
import random
import time
from dataclasses import asdict
from pathlib import Path

import torch

from ml.config import ModelConfig, TrainConfig, resolver_device
from ml.data.loader import get_batch
from ml.model import GPTEducativo


class Trainer:
    def __init__(
        self,
        model_cfg: ModelConfig,
        train_cfg: TrainConfig,
        train_data: torch.Tensor,
        val_data: torch.Tensor,
        *,
        tokenizer_path: str | None = None,
    ) -> None:
        self.model_cfg = model_cfg
        self.cfg = train_cfg
        self.train_data = train_data
        self.val_data = val_data
        self.tokenizer_path = tokenizer_path

        self.device = resolver_device(train_cfg.device)
        self.rng = random.Random(train_cfg.seed)
        torch.manual_seed(train_cfg.seed)

        self.model = GPTEducativo(model_cfg).to(self.device)
        self.optimizer = self.model.configurar_optimizador(
            train_cfg.weight_decay,
            train_cfg.learning_rate,
            (train_cfg.beta1, train_cfg.beta2),
            self.device,
        )

        self.dtype = self._resolver_dtype()
        self.usar_amp = self.device == "cuda" and self.dtype in ("float16", "bfloat16")
        self.scaler = torch.amp.GradScaler(enabled=self.dtype == "float16")

        self.exp_dir = Path(train_cfg.checkpoint_dir).parent / "experiments" / train_cfg.nombre_experimento
        self.exp_dir.mkdir(parents=True, exist_ok=True)
        self.ckpt_dir = Path(train_cfg.checkpoint_dir)
        self.ckpt_dir.mkdir(parents=True, exist_ok=True)
        self.mejor_val = float("inf")
        self.historial: list[dict] = []

    def _resolver_dtype(self) -> str:
        if self.cfg.dtype != "auto":
            return self.cfg.dtype
        if self.device == "cuda":
            return "bfloat16" if torch.cuda.is_bf16_supported() else "float16"
        return "float32"

    # ------------------------------------------------------------------
    def _lr(self, it: int) -> float:
        c = self.cfg
        if not c.lr_decay:
            return c.learning_rate
        if it < c.warmup_iters:
            return c.learning_rate * (it + 1) / max(1, c.warmup_iters)
        if it > c.max_iters:
            return c.min_lr
        ratio = (it - c.warmup_iters) / max(1, c.max_iters - c.warmup_iters)
        coef = 0.5 * (1.0 + math.cos(math.pi * ratio))
        return c.min_lr + coef * (c.learning_rate - c.min_lr)

    def _lote(self, split: str) -> tuple[torch.Tensor, torch.Tensor]:
        data = self.train_data if split == "train" else self.val_data
        return get_batch(
            data,
            batch_size=self.cfg.batch_size,
            block_size=self.model_cfg.block_size,
            device=self.device,
            generador=self.rng,
        )

    @torch.no_grad()
    def estimar_perdida(self) -> dict[str, float]:
        self.model.eval()
        salida: dict[str, float] = {}
        for split in ("train", "val"):
            data = self.train_data if split == "train" else self.val_data
            if data.numel() <= self.model_cfg.block_size + 1:
                salida[split] = float("nan")
                continue
            perdidas = torch.zeros(self.cfg.eval_iters)
            for k in range(self.cfg.eval_iters):
                x, y = self._lote(split)
                _, loss = self.model(x, y)
                perdidas[k] = loss.item()
            salida[split] = perdidas.mean().item()
        self.model.train()
        return salida

    def _autocast(self):
        if self.usar_amp:
            return torch.autocast(device_type="cuda", dtype=getattr(torch, self.dtype))
        return torch.autocast(device_type="cpu", enabled=False)

    # ------------------------------------------------------------------
    def entrenar(self) -> dict:
        cfg = self.cfg
        self._guardar_config()
        print(
            f"[Trainer] device={self.device} dtype={self.dtype} "
            f"params={self.model.num_parametros():,} "
            f"train_tokens={self.train_data.numel():,}"
        )
        t0 = time.perf_counter()
        self.model.train()

        for it in range(cfg.max_iters + 1):
            lr = self._lr(it)
            for grupo in self.optimizer.param_groups:
                grupo["lr"] = lr

            # Evaluación + checkpoint
            if it % cfg.eval_interval == 0 or it == cfg.max_iters:
                losses = self.estimar_perdida()
                self._log(it, lr, losses, time.perf_counter() - t0)
                if losses["val"] == losses["val"] and losses["val"] < self.mejor_val:
                    self.mejor_val = losses["val"]
                    self._guardar_checkpoint(it, losses["val"], etiqueta="best")

            if it == cfg.max_iters:
                break

            # Paso de entrenamiento con acumulación de gradientes
            self.optimizer.zero_grad(set_to_none=True)
            loss_acum = 0.0
            for _ in range(cfg.grad_accum_steps):
                x, y = self._lote("train")
                with self._autocast():
                    _, loss = self.model(x, y)
                    loss = loss / cfg.grad_accum_steps
                self.scaler.scale(loss).backward()
                loss_acum += loss.item()

            if cfg.grad_clip > 0:
                self.scaler.unscale_(self.optimizer)
                torch.nn.utils.clip_grad_norm_(self.model.parameters(), cfg.grad_clip)
            self.scaler.step(self.optimizer)
            self.scaler.update()

            if it % cfg.log_interval == 0:
                print(f"  iter {it:5d} | loss {loss_acum:.4f} | lr {lr:.2e}")

        self._guardar_checkpoint(cfg.max_iters, self.mejor_val, etiqueta="final")
        dur = time.perf_counter() - t0
        print(f"[Trainer] Entrenamiento terminado en {dur:.1f}s. Mejor val_loss={self.mejor_val:.4f}")
        return {
            "mejor_val_loss": self.mejor_val,
            "duracion_seg": round(dur, 1),
            "iteraciones": cfg.max_iters,
            "experimento": str(self.exp_dir),
        }

    # ------------------------------------------------------------------
    def _guardar_config(self) -> None:
        payload = {
            "model": self.model_cfg.to_dict(),
            "train": self.cfg.to_dict(),
            "device": self.device,
            "dtype": self.dtype,
            "num_parametros": self.model.num_parametros(),
        }
        (self.exp_dir / "config.json").write_text(
            json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8"
        )

    def _log(self, it: int, lr: float, losses: dict, elapsed: float) -> None:
        registro = {
            "iter": it,
            "lr": lr,
            "train_loss": losses.get("train"),
            "val_loss": losses.get("val"),
            "elapsed_seg": round(elapsed, 1),
        }
        self.historial.append(registro)
        with (self.exp_dir / "metrics.jsonl").open("a", encoding="utf-8") as f:
            f.write(json.dumps(registro, ensure_ascii=False) + "\n")
        print(
            f"[eval] iter {it:5d} | train {losses.get('train'):.4f} | "
            f"val {losses.get('val'):.4f} | {elapsed:.1f}s"
        )

    def _guardar_checkpoint(self, it: int, val_loss: float, *, etiqueta: str) -> Path:
        ruta = self.ckpt_dir / f"{self.cfg.nombre_experimento}_{etiqueta}.pt"
        torch.save(
            {
                "model_state": self.model.state_dict(),
                "model_config": self.model_cfg.to_dict(),
                "iter": it,
                "val_loss": val_loss,
                "tokenizer_path": self.tokenizer_path,
            },
            ruta,
        )
        return ruta
