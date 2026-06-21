# ════════════════════════════════════════════════════════════════════
#  Script supervisor — entrenar el modelo de la tesis
# ════════════════════════════════════════════════════════════════════
#
#  Lanza ml/train.py con la config "tesis_v2" y deja el log corriendo
#  en background. Si el proceso se cae, lo reinicia automáticamente
#  desde el último checkpoint hasta llegar a max_iters.
#
#  Uso:
#       ./entrenar_tesis.ps1                  (interactivo)
#       Start-Job { ./entrenar_tesis.ps1 }    (background)
#
#  Configuración rápida (editar arriba si quieres cambiar):
#       - PRESET       = "experto"   (~55M params, óptimo para RTX 2050)
#       - ITERS        = 30000       (run completo, ~24-36 h)
#       - BATCH        = 8           (4 GB VRAM caben con bfloat16)
#       - EXPERIMENTO  = "tesis_v2"
#
#  Datasets/tokenizer reutilizados:
#       Si ya hay tokenizer_tesis_v2.json en ml/tokenizer/artefactos/
#       lo reusará. Si no, lo entrena (rápido con sentencepiece).
# ════════════════════════════════════════════════════════════════════

$ErrorActionPreference = "Continue"

# ── CONFIG ──────────────────────────────────────────────────────────
$PRESET       = "experto"
$ITERS        = 30000
$BATCH        = 8
$EXPERIMENTO  = "tesis_v2"
$VOCAB        = 16000
$CORPUS       = "datasets/processed/corpus_entrenamiento.jsonl"
$LOG          = "training_tesis_v2.log"
$MAX_REINICIOS = 5

# ── ENTORNO ────────────────────────────────────────────────────────
Set-Location "$PSScriptRoot\.."   # raíz del proyecto
$env:PYTHONUNBUFFERED = "1"
$env:PYTHONIOENCODING = "utf-8"

# Activar venv si existe
if (Test-Path "ml\.venv\Scripts\Activate.ps1") {
    & ml\.venv\Scripts\Activate.ps1
    Write-Host "[supervisor] venv activado" -ForegroundColor Green
}

# ── COMANDO BASE ────────────────────────────────────────────────────
# IMPORTANTE: ejecutamos como módulo (`-m ml.train`) — no `ml/train.py` —
# porque train.py usa imports absolutos `from ml.config import ...`
$cmd = @(
    "python", "-u", "-m", "ml.train",
    "--preset", $PRESET,
    "--iters", "$ITERS",
    "--batch", "$BATCH",
    "--experimento", $EXPERIMENTO,
    "--vocab", "$VOCAB",
    "--corpus", $CORPUS,
    "--tokenizer-backend", "sp",
    "--sin-semilla"
)

# Si ya hay tokenizer, reusar
$tokExistente = "ml/tokenizer/artefactos/tokenizer_${EXPERIMENTO}.json"
if (Test-Path $tokExistente) {
    $cmd += @("--tokenizer-existente", $tokExistente)
    Write-Host "[supervisor] tokenizer reutilizado: $tokExistente" -ForegroundColor Yellow
}

# ── LOOP CON REINICIO AUTOMÁTICO ────────────────────────────────────
$reintentos = 0
while ($reintentos -lt $MAX_REINICIOS) {
    $inicio = Get-Date
    Write-Host ""
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Intento $($reintentos + 1) — $($inicio.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
    Write-Host "  Log: $LOG" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan

    # Ejecutar y redirigir TODO a log (append) y a pantalla
    & $cmd[0] $cmd[1..($cmd.Length-1)] 2>&1 | Tee-Object -FilePath $LOG -Append
    $exitCode = $LASTEXITCODE
    $dur = (Get-Date) - $inicio

    if ($exitCode -eq 0) {
        Write-Host ""
        Write-Host "✓ ENTRENAMIENTO COMPLETADO" -ForegroundColor Green
        Write-Host "  Duración total: $($dur.TotalHours.ToString('0.00')) horas" -ForegroundColor Green
        Write-Host "  Checkpoint en: ml/experiments/$EXPERIMENTO/" -ForegroundColor Green
        break
    }

    $reintentos++
    Write-Host ""
    Write-Host "⚠ Proceso terminó con exit code $exitCode después de $($dur.TotalMinutes.ToString('0.0')) min" -ForegroundColor Yellow
    Write-Host "  Reintentando en 10s... (intento $reintentos / $MAX_REINICIOS)" -ForegroundColor Yellow
    Start-Sleep -Seconds 10
}

if ($reintentos -eq $MAX_REINICIOS) {
    Write-Host ""
    Write-Host "✗ Se alcanzó el máximo de reintentos. Revisa $LOG." -ForegroundColor Red
    exit 1
}
