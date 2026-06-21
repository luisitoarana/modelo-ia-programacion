"""Runner por YAML para las 5 fases del PLAN_ENTRENAMIENTO_V2.

Cada fase es un YAML que define modelo + datos + hyperparams + salida.
El runner se encarga de:
    - Cargar modelo (preset V2 o config custom).
    - Cargar checkpoint anterior si la fase continua desde otra (modelo_base).
    - Construir dataset según `modo`: pretrain (.txt) o sft (.jsonl).
    - Loop de entrenamiento con AMP + gradient accumulation + grad clip
      + gradient checkpointing + cosine LR + warmup.
    - Guardar checkpoints periódicos y resume entre sesiones (útil para
      corridas que pasan el límite 9h de Kaggle).
    - Logging de métricas a metrics.jsonl.

Uso:
    python -m ml.training.run_fase --config ml/training/configs/fase1_pretrain_B.yaml

Reanudar:
    python -m ml.training.run_fase --config <yaml> --resume <ruta_checkpoint>
"""

from __future__ import annotations

import argparse
import json
import math
import random
import signal
import sys
import time
from dataclasses import dataclass, field, asdict
from pathlib import Path
from typing import Any, Iterable, Iterator

import torch
import torch.nn.functional as F
from torch.utils.data import DataLoader, IterableDataset

from ml.config import PRESETS_V2, resolver_device
from ml.model.transformer_v2 import GPTEducativoV2, ModelConfigV2


# ════════════════════════════════════════════════════════════════════
# YAML loader simple (sin dependencia externa si PyYAML no está)
# ════════════════════════════════════════════════════════════════════

def cargar_config(path: Path) -> dict:
    """Carga YAML o JSON. Si PyYAML está, usa YAML; si no, asume JSON."""
    contenido = path.read_text(encoding="utf-8")
    try:
        import yaml  # type: ignore
        return yaml.safe_load(contenido)
    except ImportError:
        try:
            return json.loads(contenido)
        except json.JSONDecodeError as e:
            raise RuntimeError(
                f"Para leer {path} se necesita PyYAML (pip install pyyaml) "
                f"o convertir el archivo a JSON. Error: {e}"
            )


# ════════════════════════════════════════════════════════════════════
# Tokenizer wrapper (sentencepiece)
# ════════════════════════════════════════════════════════════════════

class _Tokenizer:
    """Wrapper minimal sobre sentencepiece para que el runner sea standalone."""

    def __init__(self, modelo_path: Path):
        import sentencepiece as spm
        self.sp = spm.SentencePieceProcessor()
        self.sp.Load(str(modelo_path))
        self.vocab_size = self.sp.get_piece_size()

    def codificar(self, texto: str) -> list[int]:
        return self.sp.encode_as_ids(texto)

    def decodificar(self, ids: list[int]) -> str:
        return self.sp.decode_ids(ids)


# ════════════════════════════════════════════════════════════════════
# Datasets
# ════════════════════════════════════════════════════════════════════

class PretrainDataset(IterableDataset):
    """Lee archivos .txt y emite chunks de tamaño block_size.

    Mezcla múltiples archivos (e.g. Python + JS + SQL en Fase 1) sampleando
    del corpus concatenado en chunks contiguos. Se reinicia infinitamente.
    """

    def __init__(self, archivos: list[Path], tokenizer: _Tokenizer,
                 block_size: int, *, shuffle_seed: int = 42):
        self.archivos = archivos
        self.tok = tokenizer
        self.block_size = block_size
        self.shuffle_seed = shuffle_seed

    def __iter__(self) -> Iterator[tuple[torch.Tensor, torch.Tensor]]:
        rng = random.Random(self.shuffle_seed)
        archivos = list(self.archivos)
        while True:
            rng.shuffle(archivos)
            for arch in archivos:
                texto = arch.read_text(encoding="utf-8", errors="ignore")
                ids = self.tok.codificar(texto)
                # Devolver chunks no-solapados de block_size+1
                # (input = chunk[:-1], target = chunk[1:])
                for i in range(0, len(ids) - self.block_size - 1, self.block_size):
                    chunk = ids[i:i + self.block_size + 1]
                    x = torch.tensor(chunk[:-1], dtype=torch.long)
                    y = torch.tensor(chunk[1:], dtype=torch.long)
                    yield x, y


class SFTDataset(IterableDataset):
    """Lee JSONL con schema V2 y emite (input_ids, labels) para SFT.

    Aplica template chat:
        <|user|>{instruccion}\n{entrada}<|end|>
        <|assistant|>{salida}<|end|>

    El loss solo se computa sobre los tokens de la respuesta (labels
    para el prompt = -100, ignorados por F.cross_entropy).
    """

    def __init__(self, jsonl: Path, tokenizer: _Tokenizer, block_size: int,
                 *, filtro_tipos: list[str] | None = None,
                 shuffle_seed: int = 42,
                 ids_especiales: dict[str, int] | None = None):
        self.jsonl = jsonl
        self.tok = tokenizer
        self.block_size = block_size
        self.filtro_tipos = set(filtro_tipos) if filtro_tipos else None
        self.shuffle_seed = shuffle_seed
        # Tokens especiales para la plantilla. Si el tokenizer no los tiene,
        # usamos representaciones de texto que él pueda tokenizar.
        self.user_tag = "<|user|>"
        self.assistant_tag = "<|assistant|>"
        self.end_tag = "<|end|>"

    def _formatear(self, ej: dict) -> tuple[list[int], list[int]]:
        instr = ej.get("instruccion", "").strip()
        entrada = ej.get("entrada", "").strip()
        salida = ej.get("salida", "").strip()

        prompt = f"{self.user_tag}{instr}"
        if entrada:
            prompt += f"\n{entrada}"
        prompt += f"{self.end_tag}{self.assistant_tag}"
        respuesta = f"{salida}{self.end_tag}"

        prompt_ids = self.tok.codificar(prompt)
        respuesta_ids = self.tok.codificar(respuesta)

        # input = prompt + respuesta. labels = -100 para prompt, ids reales para respuesta.
        input_ids = prompt_ids + respuesta_ids
        labels = [-100] * len(prompt_ids) + respuesta_ids

        return input_ids, labels

    def __iter__(self) -> Iterator[tuple[torch.Tensor, torch.Tensor]]:
        rng = random.Random(self.shuffle_seed)
        while True:
            buffer = []
            with self.jsonl.open(encoding="utf-8") as f:
                for linea in f:
                    linea = linea.strip()
                    if not linea:
                        continue
                    try:
                        ej = json.loads(linea)
                    except json.JSONDecodeError:
                        continue
                    if self.filtro_tipos and ej.get("tipo") not in self.filtro_tipos:
                        continue
                    buffer.append(ej)
            rng.shuffle(buffer)
            for ej in buffer:
                input_ids, labels = self._formatear(ej)
                # Truncar al block_size (manteniendo final con respuesta)
                if len(input_ids) > self.block_size:
                    # Truncamos por el inicio (mantenemos la respuesta)
                    exceso = len(input_ids) - self.block_size
                    input_ids = input_ids[exceso:]
                    labels = labels[exceso:]
                # Padding a block_size con -100 (ignorado por loss)
                pad = self.block_size - len(input_ids)
                if pad > 0:
                    input_ids = input_ids + [0] * pad
                    labels = labels + [-100] * pad

                x = torch.tensor(input_ids[:-1], dtype=torch.long)
                y = torch.tensor(labels[1:], dtype=torch.long)
                yield x, y


# ════════════════════════════════════════════════════════════════════
# Trainer
# ════════════════════════════════════════════════════════════════════

@dataclass
class _RunState:
    """Estado serializable para reanudación entre sesiones."""
    paso: int = 0
    epoca: int = 0
    mejor_val_loss: float = float("inf")
    rng_seed_actual: int = 42
    tiempo_total_segundos: float = 0.0


class TrainerV2:
    """Trainer para modelos V2 con AMP + GC + grad accum + cosine LR + resume."""

    def __init__(self, cfg: dict, *, resume_path: Path | None = None,
                 tiempo_max_minutos: int | None = None):
        self.cfg = cfg
        self.tiempo_max_segundos = tiempo_max_minutos * 60 if tiempo_max_minutos else None

        self.device = resolver_device(cfg.get("device", "auto"))
        torch.manual_seed(cfg.get("seed", 42))

        # Tokenizer
        tok_path = Path(cfg["tokenizer"])
        if not tok_path.exists():
            raise FileNotFoundError(f"No existe tokenizer: {tok_path}")
        self.tok = _Tokenizer(tok_path)

        # Modelo
        self.modelo_cfg = self._resolver_modelo_cfg()
        # Forzar vocab_size del tokenizer (puede diferir del preset)
        self.modelo_cfg.vocab_size = self.tok.vocab_size
        self.modelo = GPTEducativoV2(self.modelo_cfg).to(self.device)
        if cfg.get("training", {}).get("gradient_checkpointing"):
            self.modelo.gradient_checkpointing_enable()

        # Cargar checkpoint anterior si la fase continúa de otra
        modelo_base = cfg.get("modelo_base")
        if modelo_base and Path(modelo_base).exists():
            self._cargar_modelo_base(Path(modelo_base))

        # Optimizador
        tcfg = cfg.get("training", {})
        self.lr_inicial = float(tcfg.get("learning_rate", 3e-4))
        self.lr_min = float(tcfg.get("min_learning_rate", self.lr_inicial * 0.1))
        self.weight_decay = float(tcfg.get("weight_decay", 0.1))
        self.beta1 = float(tcfg.get("beta1", 0.9))
        self.beta2 = float(tcfg.get("beta2", 0.95))
        self.opt = self.modelo.configurar_optimizador(
            self.weight_decay, self.lr_inicial, (self.beta1, self.beta2),
        )

        # AMP
        self.dtype = self._resolver_dtype(tcfg.get("dtype", "auto"))
        self.autocast_dtype = {"float16": torch.float16, "bfloat16": torch.bfloat16,
                               "float32": torch.float32}[self.dtype]
        self.usar_amp = self.device == "cuda" and self.dtype != "float32"
        self.scaler = torch.amp.GradScaler(enabled=self.dtype == "float16")

        # Hyperparams del loop
        self.batch_size = int(tcfg.get("per_device_batch_size", 4))
        self.grad_accum = int(tcfg.get("grad_accum_steps", 1))
        self.grad_clip = float(tcfg.get("grad_clip", 1.0))
        self.max_pasos = int(tcfg.get("max_pasos", 0)) or None
        self.epocas = int(tcfg.get("epocas", 1))
        self.warmup_ratio = float(tcfg.get("warmup_ratio", 0.02))
        self.eval_cada = int(tcfg.get("eval_cada", 250))
        self.eval_pasos = int(tcfg.get("eval_pasos", 50))
        self.save_cada = int(tcfg.get("save_cada", 500))
        self.log_cada = int(tcfg.get("log_cada", 20))

        # Datasets
        self.train_ds, self.val_ds = self._construir_datasets()
        self.train_dl = DataLoader(
            self.train_ds, batch_size=self.batch_size,
            num_workers=0,  # IterableDataset + multiproc puede dar problemas en Windows
        )
        self.val_dl = DataLoader(
            self.val_ds, batch_size=self.batch_size, num_workers=0,
        ) if self.val_ds else None

        # Estado
        self.estado = _RunState()
        self.salida_dir = Path(cfg["salida"])
        self.salida_dir.mkdir(parents=True, exist_ok=True)
        self.metricas_path = self.salida_dir / "metrics.jsonl"

        if resume_path and resume_path.exists():
            self._cargar_estado(resume_path)

        self._guardar_config_resuelta()

        # Captura de SIGINT/SIGTERM para guardar antes de morir
        self._abortar = False
        signal.signal(signal.SIGINT, lambda *a: setattr(self, "_abortar", True))
        try:
            signal.signal(signal.SIGTERM, lambda *a: setattr(self, "_abortar", True))
        except (AttributeError, ValueError):
            pass  # Windows no soporta SIGTERM en todos los casos

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
        # Custom config
        return ModelConfigV2(**mcfg.get("custom", {}))

    def _resolver_dtype(self, pref: str) -> str:
        if pref != "auto":
            return pref
        if self.device != "cuda":
            return "float32"
        return "bfloat16" if torch.cuda.is_bf16_supported() else "float16"

    def _construir_datasets(self) -> tuple[IterableDataset, IterableDataset | None]:
        corpus = self.cfg.get("corpus", {})
        modo = self.cfg.get("modo", "sft")

        if modo == "pretrain":
            archivos = [Path(p) for p in corpus.get("archivos", [])]
            faltan = [str(a) for a in archivos if not a.exists()]
            if faltan:
                raise FileNotFoundError(f"Archivos de corpus inexistentes: {faltan}")
            if not archivos:
                raise ValueError("modo=pretrain requiere `corpus.archivos`")
            train = PretrainDataset(archivos, self.tok, self.modelo_cfg.block_size,
                                    shuffle_seed=self.cfg.get("seed", 42))
            val_arch = corpus.get("val_archivos")
            val = PretrainDataset([Path(p) for p in val_arch], self.tok,
                                  self.modelo_cfg.block_size,
                                  shuffle_seed=self.cfg.get("seed", 42) + 1) if val_arch else None
            return train, val

        if modo == "sft":
            jsonl = Path(corpus["jsonl"])
            if not jsonl.exists():
                raise FileNotFoundError(f"jsonl inexistente: {jsonl}")
            filtro = corpus.get("filtro_tipos")
            train = SFTDataset(jsonl, self.tok, self.modelo_cfg.block_size,
                               filtro_tipos=filtro,
                               shuffle_seed=self.cfg.get("seed", 42))
            val_jsonl = corpus.get("val_jsonl")
            val = SFTDataset(Path(val_jsonl), self.tok, self.modelo_cfg.block_size,
                             filtro_tipos=filtro,
                             shuffle_seed=self.cfg.get("seed", 42) + 1) if val_jsonl else None
            return train, val

        if modo == "dpo":
            raise NotImplementedError(
                "modo=dpo todavía no implementado. Se hará en ml/rlhf/dpo_multi.py "
                "junto con los reward models multi-criterio."
            )

        raise ValueError(f"modo desconocido: {modo!r}")

    def _cargar_modelo_base(self, ruta: Path) -> None:
        print(f"[init] Cargando pesos de fase anterior: {ruta}", flush=True)
        ck = torch.load(ruta, map_location=self.device)
        state_dict = ck.get("model_state") or ck.get("state_dict") or ck
        # Si la arquitectura cambió (e.g. vocab_size diferente por tokenizer
        # actualizado), permitimos cargar parcialmente.
        info = self.modelo.load_state_dict(state_dict, strict=False)
        if info.missing_keys:
            print(f"[init]   {len(info.missing_keys)} pesos sin inicializar (esperado si arquitectura cambió)", flush=True)
        if info.unexpected_keys:
            print(f"[init]   {len(info.unexpected_keys)} pesos del checkpoint ignorados", flush=True)

    def _cargar_estado(self, ruta: Path) -> None:
        print(f"[resume] Reanudando desde: {ruta}", flush=True)
        ck = torch.load(ruta, map_location=self.device)
        self.modelo.load_state_dict(ck["model_state"])
        self.opt.load_state_dict(ck["opt_state"])
        if ck.get("scaler_state"):
            self.scaler.load_state_dict(ck["scaler_state"])
        for k, v in ck["run_state"].items():
            setattr(self.estado, k, v)
        print(f"[resume]   paso={self.estado.paso}  mejor_val={self.estado.mejor_val_loss:.4f}", flush=True)

    def _guardar_config_resuelta(self) -> None:
        ruta = self.salida_dir / "config_resuelta.json"
        d = {
            "modelo_cfg": asdict(self.modelo_cfg),
            "cfg": self.cfg,
            "dtype": self.dtype,
            "device": self.device,
        }
        ruta.write_text(json.dumps(d, indent=2, default=str, ensure_ascii=False), encoding="utf-8")

    # ────────────────────────────────────────────────────────────────
    # Loop de entrenamiento
    # ────────────────────────────────────────────────────────────────

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

    @torch.no_grad()
    def _evaluar(self) -> float | None:
        if not self.val_dl:
            return None
        self.modelo.eval()
        losses = []
        for i, (x, y) in enumerate(self.val_dl):
            if i >= self.eval_pasos:
                break
            x, y = x.to(self.device), y.to(self.device)
            with torch.autocast(device_type="cuda", dtype=self.autocast_dtype, enabled=self.usar_amp):
                _, loss = self.modelo(x, y)
            losses.append(loss.item())
        self.modelo.train()
        return sum(losses) / len(losses) if losses else None

    def _guardar_checkpoint(self, sufijo: str = "") -> Path:
        ruta = self.salida_dir / f"checkpoint{('_' + sufijo) if sufijo else ''}.pt"
        torch.save({
            "model_state": self.modelo.state_dict(),
            "opt_state": self.opt.state_dict(),
            "scaler_state": self.scaler.state_dict() if self.scaler.is_enabled() else None,
            "run_state": asdict(self.estado),
            "modelo_cfg": asdict(self.modelo_cfg),
        }, ruta)
        return ruta

    def _registrar_metricas(self, paso: int, **kwargs) -> None:
        registro = {"paso": paso, "timestamp": time.time(), **kwargs}
        with self.metricas_path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(registro) + "\n")

    def _tiempo_agotado(self) -> bool:
        return (self.tiempo_max_segundos is not None
                and self.estado.tiempo_total_segundos >= self.tiempo_max_segundos)

    def entrenar(self) -> None:
        """Loop principal."""
        total_pasos = self.max_pasos or 10_000  # fallback razonable
        print(f"[train] modelo {self.modelo.num_parametros()/1e6:.1f}M params  "
              f"device={self.device}  dtype={self.dtype}  amp={self.usar_amp}  "
              f"gc={self.modelo._gradient_checkpointing}", flush=True)
        print(f"[train] total_pasos={total_pasos}  batch={self.batch_size}  "
              f"grad_accum={self.grad_accum}  lr={self.lr_inicial}", flush=True)

        self.modelo.train()
        train_iter = iter(self.train_dl)
        inicio_sesion = time.time()
        ultimo_log = inicio_sesion
        losses_acumuladas: list[float] = []

        while self.estado.paso < total_pasos and not self._abortar:
            # Gradient accumulation
            self.opt.zero_grad(set_to_none=True)
            loss_paso = 0.0
            for _ in range(self.grad_accum):
                try:
                    x, y = next(train_iter)
                except StopIteration:
                    train_iter = iter(self.train_dl)
                    x, y = next(train_iter)
                x, y = x.to(self.device, non_blocking=True), y.to(self.device, non_blocking=True)
                with torch.autocast(device_type="cuda", dtype=self.autocast_dtype, enabled=self.usar_amp):
                    _, loss = self.modelo(x, y)
                    loss = loss / self.grad_accum
                if self.scaler.is_enabled():
                    self.scaler.scale(loss).backward()
                else:
                    loss.backward()
                loss_paso += loss.item()

            # Clip + step
            if self.scaler.is_enabled():
                self.scaler.unscale_(self.opt)
                torch.nn.utils.clip_grad_norm_(self.modelo.parameters(), self.grad_clip)
                self.scaler.step(self.opt)
                self.scaler.update()
            else:
                torch.nn.utils.clip_grad_norm_(self.modelo.parameters(), self.grad_clip)
                self.opt.step()

            # LR scheduler
            lr_actual = self._lr(self.estado.paso, total_pasos)
            self._set_lr(lr_actual)

            losses_acumuladas.append(loss_paso)
            self.estado.paso += 1

            # Tiempo
            ahora = time.time()
            self.estado.tiempo_total_segundos += (ahora - ultimo_log)
            ultimo_log = ahora

            # Log
            if self.estado.paso % self.log_cada == 0:
                avg_loss = sum(losses_acumuladas[-self.log_cada:]) / min(self.log_cada, len(losses_acumuladas))
                pasos_restantes = total_pasos - self.estado.paso
                vel = self.estado.paso / max(1, time.time() - inicio_sesion)
                eta_min = (pasos_restantes / vel / 60) if vel > 0 else 0
                print(f"[paso {self.estado.paso:6d}/{total_pasos}] loss={avg_loss:.4f}  "
                      f"lr={lr_actual:.2e}  vel={vel:.2f} pasos/s  ETA={eta_min:.0f} min",
                      flush=True)
                self._registrar_metricas(
                    self.estado.paso, loss_train=avg_loss, lr=lr_actual,
                    velocidad_pasos_s=vel,
                )

            # Eval
            if self.estado.paso % self.eval_cada == 0 and self.val_dl:
                val_loss = self._evaluar()
                if val_loss is not None:
                    print(f"[eval  {self.estado.paso:6d}     ] val_loss={val_loss:.4f}", flush=True)
                    self._registrar_metricas(self.estado.paso, loss_val=val_loss)
                    if val_loss < self.estado.mejor_val_loss:
                        self.estado.mejor_val_loss = val_loss
                        self._guardar_checkpoint("best")
                        print(f"        guardado checkpoint_best.pt (val={val_loss:.4f})", flush=True)

            # Save checkpoint periódico
            if self.estado.paso % self.save_cada == 0:
                ruta = self._guardar_checkpoint("ultimo")
                print(f"        guardado {ruta.name}", flush=True)

            # Tiempo agotado (para chunking Kaggle 9h)
            if self._tiempo_agotado():
                print(f"[train] Tiempo máximo alcanzado ({self.tiempo_max_segundos/60:.0f} min). "
                      "Guardando estado para reanudar...", flush=True)
                break

        # Guardar al salir (por abort, fin, o tiempo)
        ruta_final = self._guardar_checkpoint("ultimo")
        print(f"\n[done] paso={self.estado.paso}  mejor_val={self.estado.mejor_val_loss:.4f}  "
              f"checkpoint final: {ruta_final}", flush=True)


# ════════════════════════════════════════════════════════════════════
# CLI
# ════════════════════════════════════════════════════════════════════

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--config", required=True, help="YAML de la fase")
    parser.add_argument("--resume", help="Ruta a checkpoint para reanudar")
    parser.add_argument("--tiempo-max-minutos", type=int, default=None,
                        help="Detener tras N minutos (chunking Kaggle 9h = 540)")
    args = parser.parse_args()

    cfg = cargar_config(Path(args.config))
    resume = Path(args.resume) if args.resume else None
    trainer = TrainerV2(cfg, resume_path=resume,
                        tiempo_max_minutos=args.tiempo_max_minutos)
    trainer.entrenar()


if __name__ == "__main__":
    main()
