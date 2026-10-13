"""Script de validacion exhaustiva y benchmark de todos los modelos entrenados.

Evalua cada checkpoint en disco con metricas de arquitectura, memoria VRAM,
velocidad de inferencia (tokens/segundo) y calidad de generacion didactica.
"""

from __future__ import annotations

import gc
import json
import sys
import time
from pathlib import Path

import torch

# Asegurar import de backend y ml
RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RAIZ))

from ml.inference.engine import InferenceEngine


MODELOS = [
    {
        "id": "smoke_30m",
        "nombre": "Smoke Test (30M)",
        "ruta": RAIZ / "training/checkpoints/smoke_test_30M/checkpoint_ultimo.pt",
        "pasos_esperados": "1,000",
        "descripcion": "Verificacion ligera",
    },
    {
        "id": "modelo_a_88m",
        "nombre": "Modelo A (88M)",
        "ruta": RAIZ / "training/checkpoints/modelo_grande_88m_5k.pt",
        "pasos_esperados": "5,000",
        "descripcion": "Baseline ligera (88M params)",
    },
    {
        "id": "modelo_b_150m_5k",
        "nombre": "Modelo B (150M - 5k)",
        "ruta": RAIZ / "training/checkpoints/B_sft_5k/checkpoint_ultimo.pt",
        "pasos_esperados": "5,000",
        "descripcion": "SFT intermedio",
    },
    {
        "id": "modelo_b_150m_15k",
        "nombre": "Modelo B v2 (150M - 15k)",
        "ruta": RAIZ / "training/checkpoints/B_sft_15k/checkpoint_ultimo.pt",
        "pasos_esperados": "15,000",
        "descripcion": "SFT completo (loss 1.41)",
    },
    {
        "id": "modelo_c_350m_5k",
        "nombre": "Modelo C (350M - 5k)",
        "ruta": RAIZ / "training/checkpoints/C_350m_5k/checkpoint_ultimo.pt",
        "pasos_esperados": "860",
        "descripcion": "Checkpoint intermedio 350M",
    },
    {
        "id": "modelo_c_350m_final",
        "nombre": "Modelo C (350M - Final)",
        "ruta": RAIZ / "training/checkpoints/C_350m_Final/checkpoint_ultimo.pt",
        "pasos_esperados": "18,618",
        "descripcion": "Modelo Estrella (173h train, loss 1.80)",
    },
]

PROMPTS_PRUEBA = [
    {
        "titulo": "Explicacion de Codigo Simple",
        "instruccion": "Explica que hace la siguiente funcion en Python:",
        "entrada": "def es_par(numero):\n    return numero % 2 == 0",
    },
    {
        "titulo": "Concepto de Programacion",
        "instruccion": "Cual es la diferencia entre una lista y una tupla en Python?",
        "entrada": "",
    },
]


def ejecutar_benchmark() -> list[dict]:
    device = "cuda" if torch.cuda.is_available() else "cpu"
    device_nombre = torch.cuda.get_device_name(0) if device == "cuda" else "CPU"
    print(f"=== INICIANDO VALIDACION DE MODELOS ===")
    print(f"Dispositivo de ejecucion: {device.upper()} ({device_nombre})\n")

    resultados = []

    for m in MODELOS:
        ruta = m["ruta"]
        print(f"--> Validando: {m['nombre']} ({ruta.name})...")
        if not ruta.exists():
            print(f"    [SKIP] Archivo no encontrado: {ruta}")
            resultados.append({
                **m,
                "disponible": False,
                "error": "Archivo no encontrado",
            })
            continue

        try:
            if device == "cuda":
                torch.cuda.empty_cache()
                torch.cuda.reset_peak_memory_stats()

            t_carga_0 = time.perf_counter()
            engine = InferenceEngine(str(ruta), device=device)
            t_carga = round(time.perf_counter() - t_carga_0, 2)

            vram_mb = 0.0
            if device == "cuda":
                vram_mb = round(torch.cuda.memory_allocated() / (1024 * 1024), 1)

            num_params = engine.num_parametros
            params_m = round(num_params / 1e6, 2)

            pruebas = []
            for p in PROMPTS_PRUEBA:
                resp = engine.responder(
                    p["instruccion"],
                    entrada=p["entrada"],
                    max_nuevos_tokens=40,
                    temperatura=0.7,
                )
                vel_tok_s = round(resp.tokens_generados / max(resp.latencia_segundos, 1e-4), 1)
                pruebas.append({
                    "titulo": p["titulo"],
                    "texto": resp.texto,
                    "tokens": resp.tokens_generados,
                    "latencia_s": resp.latencia_segundos,
                    "vel_tok_s": vel_tok_s,
                })

            res_modelo = {
                **m,
                "disponible": True,
                "num_params": num_params,
                "params_m": params_m,
                "tiempo_carga_s": t_carga,
                "vram_mb": vram_mb,
                "pruebas": pruebas,
            }
            resultados.append(res_modelo)
            print(f"    [OK] {params_m}M params | Carga: {t_carga}s | VRAM: {vram_mb}MB | Vel: {pruebas[0]['vel_tok_s']} tok/s")
            print(f"    Ejemplo: {pruebas[0]['texto'][:100]}...\n")

            del engine
            gc.collect()
            if device == "cuda":
                torch.cuda.empty_cache()

        except Exception as exc:
            print(f"    [ERROR] {exc}")
            resultados.append({
                **m,
                "disponible": False,
                "error": str(exc),
            })

    return resultados


def generar_reporte(resultados: list[dict], device_nombre: str) -> str:
    lineas = [
        "# Reporte de Validacion de Modelos LLM Propios",
        f"\n**Fecha:** {time.strftime('%Y-%m-%d %H:%M:%S')}",
        f"**Acelerador:** NVIDIA CUDA ({device_nombre})",
        "\n## 1. Resumen de Modelos Validados en GPU\n",
        "| Modelo | Parametros | Pasos | Carga | VRAM (MB) | Vel (tok/s) | Estado |",
        "| :--- | :---: | :---: | :---: | :---: | :---: | :---: |",
    ]

    for r in resultados:
        if not r.get("disponible"):
            lineas.append(f"| **{r['nombre']}** | - | {r.get('pasos_esperados', '-')} | - | - | - | No disponible |")
            continue
        vel = r["pruebas"][0]["vel_tok_s"] if r.get("pruebas") else "-"
        lineas.append(
            f"| **{r['nombre']}** | **{r['params_m']}M** | {r['pasos_esperados']} | {r['tiempo_carga_s']}s | {r['vram_mb']} MB | **{vel} tok/s** | Operativo |"
        )

    lineas.append("\n## 2. Pruebas de Inferencia Didactica\n")
    for r in resultados:
        if not r.get("disponible"):
            continue
        lineas.append(f"### {r['nombre']} ({r['params_m']}M parametros)")
        lineas.append(f"- **Memoria ocupada en GPU:** {r['vram_mb']} MB")
        lineas.append(f"- **Tiempo de carga en VRAM:** {r['tiempo_carga_s']} segundos")
        for p in r.get("pruebas", []):
            lineas.append(f"\n#### {p['titulo']}")
            lineas.append(f"- **Velocidad:** {p['vel_tok_s']} tokens/s (Latencia: {p['latencia_s']}s)")
            lineas.append("```python")
            lineas.append(p["texto"])
            lineas.append("```")
        lineas.append("\n---\n")

    return "\n".join(lineas)


if __name__ == "__main__":
    device_nombre = torch.cuda.get_device_name(0) if torch.cuda.is_available() else "CPU"
    resultados = ejecutar_benchmark()
    reporte = generar_reporte(resultados, device_nombre)

    salida_md = RAIZ / "training" / "results" / "reporte_validacion_modelos.md"
    salida_md.parent.mkdir(parents=True, exist_ok=True)
    salida_md.write_text(reporte, encoding="utf-8")
    print(f"\n[EXITO] Reporte guardado en: {salida_md}")
