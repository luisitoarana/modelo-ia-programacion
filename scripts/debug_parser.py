"""Debug end-to-end: pool → parser → validador."""
import asyncio
from ml.data.pool_generadores import Pool, Tarea, extraer_json_array
from ml.data.generar_pensamiento import PROMPT_TEMPLATE
from ml.data.schema import EjemploEntrenamiento
from ml.data.validadores import validar_ejemplo


async def main():
    pool = Pool.desde_env()
    prompt = PROMPT_TEMPLATE.format(tema="api_rest", nivel="intermedio", n=2)
    texto, prov = await pool.generar(
        prompt, tarea=Tarea.COT, temperatura=0.9, max_tokens=4096,
        proveedor_forzado="groq",
    )

    print(f"Proveedor usado: {prov}")
    print(f"Largo de respuesta: {len(texto)} chars")
    print()

    arr = extraer_json_array(texto)
    if arr is None:
        print("[!] extraer_json_array devolvio None")
        return
    print(f"Items recuperados del array: {len(arr)}")
    print()

    for i, d in enumerate(arr):
        if not isinstance(d, dict):
            print(f"  [{i}] no es dict: {type(d).__name__}")
            continue
        d["tipo"] = "pensamiento_programador"
        d.setdefault("fuente", prov)
        try:
            ej = EjemploEntrenamiento.from_dict(d)
        except Exception as e:
            print(f"  [{i}] from_dict FAIL: {type(e).__name__}: {e}")
            continue
        ok, motivo = validar_ejemplo(ej)
        marca = "OK" if ok else "RECHAZADO"
        print(f"  [{i}] {marca}: {motivo[:140]}")


if __name__ == "__main__":
    asyncio.run(main())
