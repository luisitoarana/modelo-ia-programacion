# Lanzador único de la visión propia.
#
# Ejecuta en orden:
#   1) Verifica que torch ve la GPU (RTX 2050)
#   2) Smoke test (3 segundos) — confirma que la arquitectura está bien
#   3) Genera dataset sintético (2000 imágenes, ~30 seg)
#   4) Entrena etapa A — solo projector (~1-2 h en RTX 2050)
#   5) Entrena etapa B — todo el modelo (~3-5 h en RTX 2050)
#
# Si en algún paso falla, se detiene. Ningún paso bloquea la GUI del
# sistema más allá del uso de la GPU.

$ErrorActionPreference = "Stop"
$RaizProyecto = $PSScriptRoot
Set-Location $RaizProyecto

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Lanzador entrenamiento Vision Propia" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# 1) GPU check
Write-Host "`n[1/5] Verificando GPU..." -ForegroundColor Yellow
$gpuOk = python -c "import torch; print('OK' if torch.cuda.is_available() else 'NO')"
if ($gpuOk -ne "OK") {
    Write-Host "  [X] CUDA no detectado. Instala torch con CUDA:" -ForegroundColor Red
    Write-Host "      pip install torch --index-url https://download.pytorch.org/whl/cu124"
    exit 1
}
$gpuName = python -c "import torch; print(torch.cuda.get_device_name(0))"
Write-Host "  [OK] $gpuName" -ForegroundColor Green

# 2) Smoke test
Write-Host "`n[2/5] Smoke test del modelo..." -ForegroundColor Yellow
python scripts/smoke_multimodal.py
if ($LASTEXITCODE -ne 0) { Write-Host "  [X] Smoke test falló" -ForegroundColor Red; exit 1 }

# 3) Dataset
Write-Host "`n[3/5] Generando dataset sintético (2000 imágenes)..." -ForegroundColor Yellow
python -m ml.data.generar_imagenes_codigo --n 2000 --salida data/vision

# 4) Etapa A
Write-Host "`n[4/5] Entrenando ETAPA A (solo projector) — ~1-2h..." -ForegroundColor Yellow
python -m ml.train_multimodal --etapa a --iters 1500 --batch 8

# 5) Etapa B
Write-Host "`n[5/5] Entrenando ETAPA B (todo el modelo) — ~3-5h..." -ForegroundColor Yellow
python -m ml.train_multimodal --etapa b --iters 3000 --batch 4 `
    --checkpoint-prev runs/multimodal_a/best.pt

Write-Host "`n==============================================" -ForegroundColor Green
Write-Host "  [OK] Visión propia entrenada." -ForegroundColor Green
Write-Host "  Checkpoint: runs/multimodal_b/best.pt" -ForegroundColor Green
Write-Host "  El backend lo cargará automáticamente al arrancar." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
