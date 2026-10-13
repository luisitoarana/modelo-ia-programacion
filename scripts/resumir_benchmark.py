import json
from pathlib import Path

ruta = Path("training/results/benchmark_tesis_40_preguntas.json")
with open(ruta, encoding="utf-8") as f:
    data = json.load(f)

print("| Modelo | Params | VRAM | Vel (tok/s) | Latencia | EduCode Global | D1: Interp | D2: Errores | D3: Andamiaje | D4: Transf |")
print("|---|---|---|---|---|---|---|---|---|---|")
for m in data["modelos"]:
    dims = m["scores_por_dimension"]
    p_m = m["num_parametros"] / 1e6
    print(f"| {m['nombre']} | {p_m:.1f}M | {m['vram_mb']} MB | {m['tokens_por_segundo']} tok/s | {m['latencia_media_s']}s | **{m['score_educode_global']}/100** | {dims['interpretacion']} | {dims['deteccion_errores']} | {dims['andamiaje_algoritmico']} | {dims['transferencia_calidad']} |")

print("\n--- EJEMPLOS CUALITATIVOS (MODELO B 15k vs MODELO C 350M) ---")
for m in data["modelos"][3:]:
    print(f"\n>>> {m['nombre']} <<<")
    for r in m["respuestas"]:
        if r["pregunta_id"] in ["D1_01_bucle_while_acumulador", "D2_01_off_by_one_index", "D3_01_busqueda_binaria_andamiaje", "D4_01_bucle_a_comprension"]:
            print(f"  [{r['pregunta_id']}] Score: {r['score_pregunta']}/100")
            print(f"  Texto: {repr(r['texto_generado'][:140])}\n")
