<#
.SYNOPSIS
    Version DEFINITIVA — mueve TODAS las capturas del proyecto de tu PC al repo.

.DESCRIPTION
    Busca todas las capturas PNG/JPG en OneDrive/Imagenes/Capturas de pantalla
    y las clasifica por fecha, moviendolas a las carpetas correctas de sesion.

    Sesiones documentadas:
    - sesion-07-2026-06-22 (smoke test + modelo B v1 + datasets)
    - sesion-08-2026-06-27 (inferencia + EduCodeEval + modelo B v2)
    - sesion-09-2026-06-27 (Kaggle + modelo grande 88M)

    Si hay capturas de fechas fuera de esas sesiones, crea una nueva
    carpeta con la fecha del dia.

.PARAMETER DryRun
    Si se especifica, solo MUESTRA lo que haria sin mover nada.

.PARAMETER AutoCommit
    Si se especifica, hace git add + commit + push automatico.

.EXAMPLE
    # Ver que capturas hay, sin mover:
    .\scripts\mover_todas_capturas.ps1 -DryRun

    # Mover todo + commit + push automatico:
    .\scripts\mover_todas_capturas.ps1 -AutoCommit
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$AutoCommit
)

$ErrorActionPreference = 'Stop'

# Detectar carpeta de capturas (con o sin tildes)
$rutasPosibles = @(
    "$env:USERPROFILE\OneDrive\Im*genes\Capturas de pantalla",
    "$env:USERPROFILE\OneDrive\Pictures\Screenshots",
    "$env:USERPROFILE\Im*genes\Capturas de pantalla",
    "$env:USERPROFILE\Pictures\Screenshots"
)

$carpetaCapturas = $null
foreach ($ruta in $rutasPosibles) {
    $resolved = Resolve-Path -Path $ruta -ErrorAction SilentlyContinue
    if ($resolved) {
        $carpetaCapturas = $resolved.Path
        break
    }
}

if (-not $carpetaCapturas) {
    Write-Error "No se pudo detectar la carpeta de capturas."
    Write-Host "Especifica la ruta manualmente."
    exit 1
}

Write-Host "Carpeta de capturas detectada:" -ForegroundColor Cyan
Write-Host "  $carpetaCapturas"
Write-Host ""

# Detectar raiz del repo
$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
    Write-Error "No estas en un repo git."
    exit 1
}
$repoRoot = $repoRoot.Replace('/', '\')

# Definir sesiones y sus rangos de fecha
$sesiones = @(
    @{
        Id = "sesion-07-2026-06-22"
        FechaInicio = [datetime]"2026-06-22 00:00:00"
        FechaFin = [datetime]"2026-06-26 23:59:59"
        Descripcion = "Smoke test + Modelo B v1 + Datasets iniciales"
    },
    @{
        Id = "sesion-08-2026-06-27"
        FechaInicio = [datetime]"2026-06-27 00:00:00"
        FechaFin = [datetime]"2026-06-27 12:00:00"
        Descripcion = "Inferencia + EduCodeEval del B v1 + Sistema capturas"
    },
    @{
        Id = "sesion-09-2026-06-27"
        FechaInicio = [datetime]"2026-06-27 12:00:00"
        FechaFin = [datetime]"2026-06-29 23:59:59"
        Descripcion = "Kaggle + Modelo grande 88M + EduCodeEval grande"
    }
)

# Buscar todas las capturas
$extensionesValidas = @('.png', '.jpg', '.jpeg')
$todasLasCapturas = Get-ChildItem -Path $carpetaCapturas -File |
    Where-Object { $extensionesValidas -contains $_.Extension.ToLower() } |
    Sort-Object LastWriteTime

Write-Host "Total de imagenes encontradas en tu PC: $($todasLasCapturas.Count)" -ForegroundColor Green
Write-Host ""

# Clasificar por sesion
$clasificacion = @{}
$sinClasificar = @()

foreach ($sesion in $sesiones) {
    $clasificacion[$sesion.Id] = @()
}

foreach ($captura in $todasLasCapturas) {
    $asignada = $false
    foreach ($sesion in $sesiones) {
        if ($captura.LastWriteTime -ge $sesion.FechaInicio -and $captura.LastWriteTime -le $sesion.FechaFin) {
            $clasificacion[$sesion.Id] += $captura
            $asignada = $true
            break
        }
    }
    if (-not $asignada) {
        $sinClasificar += $captura
    }
}

# Mostrar resumen
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "  RESUMEN DE CLASIFICACION" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""

foreach ($sesion in $sesiones) {
    $count = $clasificacion[$sesion.Id].Count
    $color = if ($count -gt 0) { 'Green' } else { 'DarkGray' }
    Write-Host "[$($sesion.Id)]" -ForegroundColor $color
    Write-Host "  Descripcion: $($sesion.Descripcion)"
    Write-Host "  Capturas encontradas: $count" -ForegroundColor $color
    Write-Host ""
}

if ($sinClasificar.Count -gt 0) {
    Write-Host "[capturas fuera de rango de sesiones conocidas]" -ForegroundColor Yellow
    Write-Host "  Total: $($sinClasificar.Count)"
    Write-Host "  Estas se moveran a: sesion-10-$(Get-Date -Format 'yyyy-MM-dd')/"
    Write-Host ""
    foreach ($c in ($sinClasificar | Select-Object -First 5)) {
        Write-Host "    - $($c.Name) ($(Get-Date $c.LastWriteTime -Format 'yyyy-MM-dd HH:mm'))"
    }
    if ($sinClasificar.Count -gt 5) {
        Write-Host "    ... y $($sinClasificar.Count - 5) mas"
    }
    Write-Host ""
}

if ($DryRun) {
    Write-Host "DRY RUN — no se movio nada." -ForegroundColor Yellow
    Write-Host "Ejecuta sin -DryRun para mover los archivos."
    exit 0
}

# Mover archivos
Write-Host "MOVIENDO ARCHIVOS..." -ForegroundColor Green
Write-Host ""

$totalMovidos = 0
$sesionesConCambios = @()

# Mover a sesiones existentes
foreach ($sesion in $sesiones) {
    $capturasEnEsta = $clasificacion[$sesion.Id]
    if ($capturasEnEsta.Count -eq 0) { continue }

    $carpetaDestino = Join-Path $repoRoot "docs\capturas\$($sesion.Id)"
    if (-not (Test-Path $carpetaDestino)) {
        New-Item -ItemType Directory -Path $carpetaDestino | Out-Null
    }

    # Determinar numeracion siguiente
    $existentes = Get-ChildItem -Path $carpetaDestino -File -ErrorAction SilentlyContinue |
        Where-Object { $extensionesValidas -contains $_.Extension.ToLower() }

    $siguienteNumero = 1
    if ($existentes) {
        $maxNumero = ($existentes | ForEach-Object {
            if ($_.Name -match '^(\d+)-') { [int]$matches[1] } else { 0 }
        } | Measure-Object -Maximum).Maximum
        $siguienteNumero = $maxNumero + 1
    }

    Write-Host "==> $($sesion.Id) ($($capturasEnEsta.Count) capturas)" -ForegroundColor Cyan

    foreach ($captura in $capturasEnEsta) {
        $numero = "{0:D2}" -f $siguienteNumero
        $timestamp = Get-Date $captura.LastWriteTime -Format 'HHmm'
        $nombreNuevo = "$numero-captura-$timestamp$($captura.Extension.ToLower())"
        $rutaDestino = Join-Path $carpetaDestino $nombreNuevo

        Move-Item -Path $captura.FullName -Destination $rutaDestino
        Write-Host "  [OK] $($captura.Name) -> $nombreNuevo"
        $siguienteNumero++
        $totalMovidos++
    }
    $sesionesConCambios += $sesion.Id
    Write-Host ""
}

# Mover sin clasificar a nueva sesion
if ($sinClasificar.Count -gt 0) {
    $hoy = Get-Date -Format 'yyyy-MM-dd'
    $nombreSesionNueva = "sesion-10-$hoy"
    $carpetaDestino = Join-Path $repoRoot "docs\capturas\$nombreSesionNueva"

    if (-not (Test-Path $carpetaDestino)) {
        New-Item -ItemType Directory -Path $carpetaDestino | Out-Null
    }

    Write-Host "==> $nombreSesionNueva ($($sinClasificar.Count) capturas fuera de rango)" -ForegroundColor Cyan

    $numero = 1
    foreach ($captura in $sinClasificar) {
        $num = "{0:D2}" -f $numero
        $timestamp = Get-Date $captura.LastWriteTime -Format 'yyyyMMdd-HHmm'
        $nombreNuevo = "$num-$timestamp$($captura.Extension.ToLower())"
        $rutaDestino = Join-Path $carpetaDestino $nombreNuevo

        Move-Item -Path $captura.FullName -Destination $rutaDestino
        Write-Host "  [OK] $($captura.Name) -> $nombreNuevo"
        $numero++
        $totalMovidos++
    }
    $sesionesConCambios += $nombreSesionNueva
    Write-Host ""
}

Write-Host "==============================" -ForegroundColor Green
Write-Host "  TOTAL MOVIDO: $totalMovidos capturas" -ForegroundColor Green
Write-Host "==============================" -ForegroundColor Green

# Auto-commit
if ($AutoCommit -and $totalMovidos -gt 0) {
    Write-Host ""
    Write-Host "Haciendo commit + push..." -ForegroundColor Cyan

    Push-Location $repoRoot
    try {
        foreach ($sesion in $sesionesConCambios) {
            git add "docs/capturas/$sesion/"
        }

        $mensajeCommit = "docs(capturas): mover $totalMovidos capturas fisicas al repo`n`nSesiones actualizadas:`n"
        foreach ($sesion in $sesionesConCambios) {
            $mensajeCommit += "- $sesion`n"
        }

        $tmpFile = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $tmpFile -Value $mensajeCommit -Encoding UTF8
        git commit -F $tmpFile
        Remove-Item $tmpFile -Force

        git push origin main

        Write-Host "Commit + push exitosos." -ForegroundColor Green
    } finally {
        Pop-Location
    }
}

Write-Host ""
Write-Host "Listo." -ForegroundColor Green
