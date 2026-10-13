"""Ejecutor del Benchmark Académico de Tesis (40 preguntas x N modelos).

Tesis: "Efecto de un asistente basado en modelos de lenguaje con andamiaje explicativo
sobre la comprensión de código Python en estudiantes universitarios: estudio cuasiexperimental"
Autor: Arana Panezo Luis Miguel
PUCESE - Esmeraldas
"""

from __future__ import annotations

import gc
import json
import os
import sys
import time
from pathlib import Path
from typing import Any, Dict, List

import torch

RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(RAIZ))

from ml.inference.engine import InferenceEngine
from scripts.preguntas_benchmark_tesis import PREGUNTAS_BENCHMARK, PreguntaBenchmark

MODELOS_EVALUAR = [
    {
        "id": "smoke_30m",
        "nombre": "Smoke Test (30M)",
        "arquitectura": "V2 (30.75M params)",
        "ruta": RAIZ / "training/checkpoints/smoke_test_30M/checkpoint_ultimo.pt",
        "rol_tesis": "Baseline de verificación sintáctica mínima",
    },
    {
        "id": "modelo_a_88m",
        "nombre": "Modelo A (88M)",
        "arquitectura": "V1 (87.80M params)",
        "ruta": RAIZ / "training/checkpoints/modelo_grande_88m_5k.pt",
        "rol_tesis": "Baseline compacta arquitectura clásica V1",
    },
    {
        "id": "modelo_b_150m_5k",
        "nombre": "Modelo B (150M - 5k pasos)",
        "arquitectura": "V2 RoPE/GQA (150.73M params)",
        "ruta": RAIZ / "training/checkpoints/B_sft_5k/checkpoint_ultimo.pt",
        "rol_tesis": "Punto de control intermedio de escalamiento",
    },
    {
        "id": "modelo_b_150m_15k",
        "nombre": "Modelo B v2 (150M - 15k pasos)",
        "arquitectura": "V2 RoPE/GQA (150.73M params, loss 1.41)",
        "ruta": RAIZ / "training/checkpoints/B_sft_15k/checkpoint_ultimo.pt",
        "rol_tesis": "Candidato principal para inferencia interactiva en tiempo real",
    },
    {
        "id": "modelo_c_350m_final",
        "nombre": "Modelo C (350M - Final SFT)",
        "arquitectura": "V2 RoPE/GQA (350.93M params, 22 capas, 173h train)",
        "ruta": RAIZ / "training/checkpoints/C_350m_Final/checkpoint_ultimo.pt",
        "rol_tesis": "Modelo insignia de máxima capacidad y razonamiento profundo",
    },
]


def evaluar_respuesta(
    pregunta: PreguntaBenchmark, respuesta_texto: str
) -> Dict[str, Any]:
    """Evalúa objetivamente la respuesta generada según las rúbricas de la tesis."""
    texto_lower = respuesta_texto.lower()

    # 1. Porcentaje de palabras clave cubiertas
    kw_hits = [
        kw for kw in pregunta.palabras_clave if kw.lower() in texto_lower
    ]
    pct_kw = len(kw_hits) / max(len(pregunta.palabras_clave), 1)

    # 2. Indicadores de Andamiaje Pedagógico (Scaffolding markers)
    marcadores_andamiaje = [
        "paso", "primero", "luego", "porque", "debido a", "significa",
        "ejemplo", "recomienda", "evita", "recuerda", "en resumen", "observa",
        "1.", "2.", "3.", "flujo", "memoria", "variable"
    ]
    andamiaje_hits = [m for m in marcadores_andamiaje if m in texto_lower]
    score_andamiaje = min(1.0, len(andamiaje_hits) / 3.0)

    # 3. Detección de error (si aplica en dimensión 2)
    score_diagnostico = 0.0
    if pregunta.dimension == "deteccion_errores":
        # Verificar si menciona el nombre técnico o la causa del error
        if any(kw.lower() in texto_lower for kw in pregunta.palabras_clave[:2]):
            score_diagnostico = 1.0
        elif any(kw.lower() in texto_lower for kw in pregunta.palabras_clave):
            score_diagnostico = 0.6
    else:
        score_diagnostico = 1.0 if pct_kw >= 0.5 else pct_kw

    # 4. Score combinado de la pregunta (0 a 100)
    if pregunta.dimension == "deteccion_errores":
        score_pregunta = (score_diagnostico * 0.50 + pct_kw * 0.30 + score_andamiaje * 0.20) * 100
    elif pregunta.dimension == "andamiaje_algoritmico":
        score_pregunta = (score_andamiaje * 0.50 + pct_kw * 0.50) * 100
    elif pregunta.dimension == "transferencia_calidad":
        score_pregunta = (pct_kw * 0.60 + score_andamiaje * 0.40) * 100
    else:  # interpretacion
        score_pregunta = (pct_kw * 0.70 + score_andamiaje * 0.30) * 100

    return {
        "score_pregunta": round(min(100.0, score_pregunta), 1),
        "pct_palabras_clave": round(pct_kw * 100, 1),
        "palabras_detectadas": kw_hits,
        "score_andamiaje": round(score_andamiaje * 100, 1),
        "score_diagnostico": round(score_diagnostico * 100, 1),
    }


def ejecutar_benchmark_completo(max_tokens_por_pregunta: int = 45) -> Dict[str, Any]:
    dispositivo = "cuda" if torch.cuda.is_available() else "cpu"
    nombre_gpu = torch.cuda.get_device_name(0) if dispositivo == "cuda" else "CPU"

    print("=" * 70)
    print("BENCHMARK ACADÉMICO DE TESIS — EVALUACIÓN DE MODELOS LLM")
    print("Tesis: Asistente con Andamiaje Explicativo para Python (PUCESE)")
    print(f"Hardware: {dispositivo.upper()} ({nombre_gpu})")
    print(f"Total preguntas: {len(PREGUNTAS_BENCHMARK)} (4 dimensiones x 10 ítems)")
    print("=" * 70)

    resultados_globales = {
        "fecha": time.strftime("%Y-%m-%d %H:%M:%S"),
        "hardware": nombre_gpu,
        "dispositivo": dispositivo,
        "total_preguntas": len(PREGUNTAS_BENCHMARK),
        "modelos": [],
    }

    ruta_salida_json = RAIZ / "training/results/benchmark_tesis_40_preguntas.json"
    ruta_salida_json.parent.mkdir(parents=True, exist_ok=True)

    for m in MODELOS_EVALUAR:
        ruta = m["ruta"]
        print(f"\n[{m['id'].upper()}] Cargando: {m['nombre']}...")
        if not ruta.exists():
            print(f"   [SKIP] Archivo no encontrado: {ruta}")
            continue

        # Limpieza de memoria previa
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
            gc.collect()
            vram_inicial = torch.cuda.memory_allocated(0) / (1024**2)
        else:
            vram_inicial = 0.0

        try:
            engine = InferenceEngine(str(ruta), device=dispositivo)
        except Exception as e:
            print(f"   [ERROR] Fallo al instanciar modelo: {e}")
            continue

        if torch.cuda.is_available():
            vram_cargado = torch.cuda.memory_allocated(0) / (1024**2)
            vram_modelo = vram_cargado - vram_inicial
        else:
            vram_modelo = 0.0

        respuestas_modelo = []
        tiempos_respuesta = []
        tokens_totales = 0
        tiempo_total_inferencia = 0.0

        scores_por_dimension = {
            "interpretacion": [],
            "deteccion_errores": [],
            "andamiaje_algoritmico": [],
            "transferencia_calidad": [],
        }

        print(f"   Iniciando evaluación de las 40 preguntas...")

        for idx, p in enumerate(PREGUNTAS_BENCHMARK, 1):
            t_ini = time.perf_counter()
            try:
                res = engine.responder(
                    p.instruccion,
                    entrada=p.entrada,
                    max_nuevos_tokens=max_tokens_por_pregunta,
                    temperatura=0.7,
                )
                t_dur = time.perf_counter() - t_ini
                texto_gen = res.texto
                toks_gen = res.tokens_generados
            except Exception as e:
                t_dur = time.perf_counter() - t_ini
                texto_gen = f"[ERROR: {e}]"
                toks_gen = 0

            tokens_totales += toks_gen
            tiempo_total_inferencia += t_dur
            tiempos_respuesta.append(t_dur)

            # Evaluación métrica
            eval_dict = evaluar_respuesta(p, texto_gen)
            scores_por_dimension[p.dimension].append(eval_dict["score_pregunta"])

            respuestas_modelo.append({
                "pregunta_id": p.id,
                "dimension": p.dimension,
                "titulo": p.titulo,
                "tokens": toks_gen,
                "latencia_s": round(t_dur, 3),
                "texto_generado": texto_gen,
                **eval_dict,
            })

            # Imprimir progreso cada 10 preguntas
            if idx % 10 == 0:
                promedio_parcial = sum(r["score_pregunta"] for r in respuestas_modelo) / len(respuestas_modelo)
                print(f"   --> Progreso: {idx}/40 preguntas | Score medio: {promedio_parcial:.1f}/100")

        # Métricas agregadas
        latencia_media = sum(tiempos_respuesta) / len(tiempos_respuesta) if tiempos_respuesta else 0.0
        toks_por_seg = tokens_totales / tiempo_total_inferencia if tiempo_total_inferencia > 0 else 0.0

        resumen_dimensiones = {
            dim: round(sum(vals) / len(vals), 1) if vals else 0.0
            for dim, vals in scores_por_dimension.items()
        }

        # Score global ponderado:
        # Interpretación (25%) + Detección Errores (25%) + Andamiaje (25%) + Transferencia (25%)
        score_educode_global = round(
            (
                resumen_dimensiones["interpretacion"] * 0.25
                + resumen_dimensiones["deteccion_errores"] * 0.25
                + resumen_dimensiones["andamiaje_algoritmico"] * 0.25
                + resumen_dimensiones["transferencia_calidad"] * 0.25
            ),
            1,
        )

        registro_modelo = {
            "id": m["id"],
            "nombre": m["nombre"],
            "arquitectura": m["arquitectura"],
            "num_parametros": engine.num_parametros,
            "vram_mb": round(vram_modelo, 1),
            "latencia_media_s": round(latencia_media, 2),
            "tokens_por_segundo": round(toks_por_seg, 1),
            "score_educode_global": score_educode_global,
            "scores_por_dimension": resumen_dimensiones,
            "rol_tesis": m["rol_tesis"],
            "respuestas": respuestas_modelo,
        }

        resultados_globales["modelos"].append(registro_modelo)

        # Guardado incremental de resultados
        with open(ruta_salida_json, "w", encoding="utf-8") as f:
            json.dump(resultados_globales, f, indent=2, ensure_ascii=False)

        print(f"   [FINALIZADO {m['nombre']}] Score Global: {score_educode_global}/100 | Vel: {toks_por_seg:.1f} tok/s | VRAM: {vram_modelo:.1f}MB")

        del engine
        if torch.cuda.is_available():
            torch.cuda.empty_cache()
            gc.collect()

    return resultados_globales


if __name__ == "__main__":
    ejecutar_benchmark_completo()
