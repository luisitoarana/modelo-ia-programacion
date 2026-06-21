# ════════════════════════════════════════════════════════════════════
#  Script de empaquetado para la defensa de tesis
# ════════════════════════════════════════════════════════════════════
#
#  Produce 3 artefactos listos para mostrar al jurado:
#    1. release/desktop/  — app desktop compilada (.exe + DLLs)
#    2. release/docker/   — docker-compose listo para arrancar backend+web
#    3. release/jurado/   — un README con instrucciones simples
#
#  Uso:
#       ./empaquetar_tesis.ps1
#
#  Pre-requisitos:
#       - Flutter SDK instalado y en PATH
#       - Docker Desktop instalado
#       - Modelo entrenado en training/checkpoints/tesis_v2_best.pt (opcional)
# ════════════════════════════════════════════════════════════════════

$ErrorActionPreference = "Continue"
$RAIZ = $PSScriptRoot
$RELEASE = "$RAIZ\release"

Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " Empaquetando Sistema Explicador Python IA — Tesis        " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

# Limpiar release anterior
if (Test-Path $RELEASE) {
    Write-Host "[clean] eliminando release/ anterior..." -ForegroundColor Yellow
    Remove-Item -Recurse -Force $RELEASE -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Force -Path "$RELEASE\desktop" | Out-Null
New-Item -ItemType Directory -Force -Path "$RELEASE\docker" | Out-Null
New-Item -ItemType Directory -Force -Path "$RELEASE\jurado" | Out-Null

# ── 1. Compilar app desktop ──────────────────────────────────────────
Write-Host ""
Write-Host "[1/3] Compilando app desktop (Flutter)..." -ForegroundColor Green
Set-Location "$RAIZ\app-desktop"

# Verificar Flutter
$flutter = Get-Command flutter -ErrorAction SilentlyContinue
if ($null -eq $flutter) {
    Write-Host "[ERROR] flutter no está en PATH. Instala Flutter y reintenta." -ForegroundColor Red
    exit 1
}

# Build release
& flutter build windows --release
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] flutter build falló (código $LASTEXITCODE)." -ForegroundColor Red
    Set-Location $RAIZ
    exit 1
}

# Copiar artefactos
$buildDir = "$RAIZ\app-desktop\build\windows\x64\runner\Release"
if (Test-Path $buildDir) {
    Write-Host "[1/3] copiando .exe + DLLs a release/desktop/..." -ForegroundColor Green
    Copy-Item -Recurse -Force "$buildDir\*" "$RELEASE\desktop\"
} else {
    Write-Host "[ERROR] No se encontró el build en $buildDir" -ForegroundColor Red
}

Set-Location $RAIZ

# ── 2. Empaquetar Docker config ──────────────────────────────────────
Write-Host ""
Write-Host "[2/3] Copiando docker-compose + dockerfiles..." -ForegroundColor Green
Copy-Item -Force "$RAIZ\docker-compose.yml" "$RELEASE\docker\"
Copy-Item -Recurse -Force "$RAIZ\docker" "$RELEASE\docker\dockerfiles" -ErrorAction SilentlyContinue
Copy-Item -Force "$RAIZ\.env.example" "$RELEASE\docker\.env.example"
Copy-Item -Recurse -Force "$RAIZ\backend" "$RELEASE\docker\backend"
Copy-Item -Recurse -Force "$RAIZ\frontend" "$RELEASE\docker\frontend"
Copy-Item -Recurse -Force "$RAIZ\mcp_server" "$RELEASE\docker\mcp_server"

# ── 3. README del jurado ─────────────────────────────────────────────
Write-Host ""
Write-Host "[3/3] Generando guía para el jurado..." -ForegroundColor Green
Copy-Item -Force "$RAIZ\docs\INSTALACION_JURADO.md" "$RELEASE\jurado\LEEME.md" -ErrorAction SilentlyContinue

# Tamaño total
$total = (Get-ChildItem -Recurse $RELEASE | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " EMPAQUETADO COMPLETO" -ForegroundColor Green
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  release/desktop/  — app .exe lista (doble click para correr)" -ForegroundColor White
Write-Host "  release/docker/   — backend + web (docker compose up)" -ForegroundColor White
Write-Host "  release/jurado/   — instrucciones simples" -ForegroundColor White
Write-Host ""
Write-Host ("  Tamaño total: {0:N1} MB" -f $total) -ForegroundColor White
Write-Host ""
Write-Host "Listo para entregar al jurado o subir a una USB." -ForegroundColor Green
