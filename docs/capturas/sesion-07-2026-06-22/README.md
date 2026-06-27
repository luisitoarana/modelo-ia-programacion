# Sesión 7 — Smoke test 30M + Modelo B v1 + Ampliación de corpus

**Fecha**: 2026-06-22
**Lugar**: Lightning AI Studio (T4 GPU)
**Documentación textual**: ver
[`DIARIO_PROGRESO.md` — Sesión 7](../../DIARIO_PROGRESO.md#sesión-7--smoke-test-30m--modelo-b-v1-150m--ampliación-de-corpus).

---

## Estado de las capturas

**No se capturaron pantallas durante esta sesión.**

Razón: la sesión se ejecutó antes de establecer la política de captura
sistemática. El usuario y yo coordinábamos por chat, pero las
pantallas que él compartió en el momento no se guardaron en el repo.

Lo que **sí** quedó documentado de esa sesión:

- ✅ Toda la cronología y resultados en
  [`DIARIO_PROGRESO.md` — Sesión 7](../../DIARIO_PROGRESO.md).
- ✅ Los 4 bugs descubiertos en
  [`BUGS_Y_SOLUCIONES.md`](../../BUGS_Y_SOLUCIONES.md) (BUG-12 a BUG-15).
- ✅ Las 6 decisiones de diseño en
  [`DECISIONES_DISENO.md`](../../DECISIONES_DISENO.md) (DD-21 a DD-26).
- ✅ Los 4 experimentos en
  [`EXPERIMENTOS.md`](../../EXPERIMENTOS.md) (EXP-LA-01 a EXP-LA-04).
- ✅ Resumen en
  [`BITACORA_DESARROLLO.md`](../../BITACORA_DESARROLLO.md) (hitos 11-14).

Lo que **no quedó** (irrecuperable):

- ❌ La pantalla del smoke test arrancando (modelo 30M, primeros logs).
- ❌ La pantalla de la curva de loss final del smoke (9.21 → 3.94).
- ❌ La pantalla del `git pull` que trajo el fix BUG-12.
- ❌ La pantalla del lanzamiento del modelo B v1 con `nohup`.
- ❌ La pantalla de las descargas de los datasets nuevos.
- ❌ El `ls -lh datasets/publicos/` cuando se completaron las descargas.
- ❌ El `wc -l` mostrando los 882,856 ejemplos consolidados.

---

## Lección aprendida

Desde la **Sesión 8 en adelante**, antes de cualquier comando que dure
más de 1 minuto, capturar pantalla del antes y del después, y guardar
en la carpeta de la sesión correspondiente.

Ver `docs/capturas/README.md` para la política completa.
