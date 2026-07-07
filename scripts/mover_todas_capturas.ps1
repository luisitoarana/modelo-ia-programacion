<#
.SYNOPSIS
    Version DEFINITIVA — mueve las capturas de tu PC al repo usando los nombres
    EXACTOS que estan en los README.md de cada sesion.

.DESCRIPTION
    1. Lee los README.md de cada sesion en docs/capturas/sesion-XX/
    2. Extrae los nombres esperados de capturas (formato: XX-nombre.png)
    3. Encuentra las capturas de tu PC en OneDrive/Imagenes/Capturas de pantalla
    4. Las agrupa por sesion segun fecha del archivo
    5. Las renombra y mueve usando los nombres exactos del README
    6. Opcionalmente hace git add + commit + push

.PARAMETER DryRun
    Solo muestra que haria sin mover archivos.

.PARAMETER AutoCommit
    Hace git add + commit + push automatico despues de mover.

.EXAMPLE
    # Ver que haria:
    .\scripts\mover_todas_capturas.ps1 -DryRun

    # Mover todo y subir:
    .\scripts\mover_todas_capturas.ps1 -AutoCommit
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$AutoCommit
)

$ErrorActionPreference = 'Stop'

# === Detectar carpeta de capturas ===
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
    Write-Error "No se encontro carpeta de capturas."
    exit 1
}

Write-Host "Carpeta de capturas: $carpetaCapturas" -ForegroundColor Cyan
Write-Host ""

# === Detectar raiz del repo ===
$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
    Write-Error "No estas en un repo git."
    exit 1
}
$repoRoot = $repoRoot.Replace('/', '\')

# === Definir sesiones y sus rangos de fecha ===
$sesiones = @(
    @{
        Id = "sesion-07-2026-06-22"
        FechaInicio = [datetime]"2026-06-22 00:00:00"
        FechaFin = [datetime]"2026-06-26 23:59:59"
        Descripcion = "Smoke + B v1 + Datasets"
    },
    @{
        Id = "sesion-08-2026-06-27"
        FechaInicio = [datetime]"2026-06-27 00:00:00"
        FechaFin = [datetime]"2026-06-27 20:00:00"
        Descripcion = "Inferencia B v1 + EduCodeEval"
    },
    @{
        Id = "sesion-09-2026-06-27"
        FechaInicio = [datetime]"2026-06-27 20:00:00"
        FechaFin = [datetime]"2026-06-29 12:00:00"
        Descripcion = "Kaggle + Modelo grande 88M"
    }
)

# === Funcion: extraer nombres esperados del README de una sesion ===
function Get-NombresEsperados {
    param([string]$RutaReadme)

    if (-not (Test-Path $RutaReadme)) {
        return @()
    }

    $contenido = Get-Content $RutaReadme -Raw -Encoding UTF8
    # Buscar patrones tipo `01-nombre.png` o `22-otro-nombre.png`
    $matches = [regex]::Matches($contenido, '`(\d+-[a-z0-9-]+\.png)`')

    $nombres = @()
    $vistos = @{}
    foreach ($m in $matches) {
        $nombre = $m.Groups[1].Value
        # Extraer el numero para ordenar
        $numero = [int]($nombre -replace '^(\d+).*', '$1')
        if (-not $vistos.ContainsKey($numero)) {
            $vistos[$numero] = $true
            $nombres += [PSCustomObject]@{
                Numero = $numero
                Nombre = $nombre
            }
        }
    }

    return $nombres | Sort-Object Numero
}

# === Encontrar capturas en tu PC ===
$extensionesValidas = @('.png', '.jpg', '.jpeg')
$todasLasCapturas = Get-ChildItem -Path $carpetaCapturas -File |
    Where-Object { $extensionesValidas -contains $_.Extension.ToLower() } |
    Sort-Object LastWriteTime

Write-Host "Total imagenes en tu PC: $($todasLasCapturas.Count)" -ForegroundColor Green
Write-Host ""

# === Procesar cada sesion ===
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  PLAN DE MOVIMIENTO" -ForegroundColor Cyan
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

$planCompleto = @()
$sinAsignar = @()

foreach ($sesion in $sesiones) {
    # Filtrar capturas por rango de fecha
    $capturasSesion = $todasLasCapturas | Where-Object {
        $_.LastWriteTime -ge $sesion.FechaInicio -and $_.LastWriteTime -le $sesion.FechaFin
    } | Sort-Object LastWriteTime

    # Leer nombres esperados del README
    $rutaReadme = Join-Path $repoRoot "docs\capturas\$($sesion.Id)\README.md"
    $nombresEsperados = Get-NombresEsperados -RutaReadme $rutaReadme

    Write-Host "[$($sesion.Id)]" -ForegroundColor Yellow
    Write-Host "  Descripcion: $($sesion.Descripcion)"
    Write-Host "  Capturas encontradas (por fecha): $($capturasSesion.Count)"
    Write-Host "  Nombres esperados en README: $($nombresEsperados.Count)"

    if ($capturasSesion.Count -eq 0) {
        Write-Host "  (no hay capturas de tu PC para esta sesion)" -ForegroundColor DarkGray
        Write-Host ""
        continue
    }

    if ($nombresEsperados.Count -eq 0) {
        Write-Host "  (no hay nombres esperados en el README — se usaran genericos)" -ForegroundColor DarkYellow
    }

    # Emparejar en orden cronologico con los nombres esperados
    $i = 0
    foreach ($captura in $capturasSesion) {
        if ($i -lt $nombresEsperados.Count) {
            $nombreDestino = $nombresEsperados[$i].Nombre
        } else {
            # Fallback: nombre generico si hay mas capturas que nombres
            $num = "{0:D2}" -f ($i + 1)
            $ts = Get-Date $captura.LastWriteTime -Format 'HHmm'
            $nombreDestino = "$num-captura-$ts$($captura.Extension.ToLower())"
        }

        $planCompleto += [PSCustomObject]@{
            Origen = $captura.FullName
            Fecha = $captura.LastWriteTime
            Sesion = $sesion.Id
            NombreDestino = $nombreDestino
            RutaDestino = Join-Path $repoRoot "docs\capturas\$($sesion.Id)\$nombreDestino"
        }
        $i++
    }

    Write-Host "  Se moveran: $i" -ForegroundColor Green
    Write-Host ""
}

# Capturas fuera de rangos conocidos
foreach ($captura in $todasLasCapturas) {
    $enAlgunaSesion = $sesiones | Where-Object {
        $captura.LastWriteTime -ge $_.FechaInicio -and $captura.LastWriteTime -le $_.FechaFin
    }
    if (-not $enAlgunaSesion) {
        $sinAsignar += $captura
    }
}

if ($sinAsignar.Count -gt 0) {
    $hoy = Get-Date -Format 'yyyy-MM-dd'
    $nombreSesionNueva = "sesion-10-$hoy"
    Write-Host "[$nombreSesionNueva]" -ForegroundColor Yellow
    Write-Host "  Capturas de fechas fuera de sesiones conocidas: $($sinAsignar.Count)"
    Write-Host ""

    $i = 0
    foreach ($captura in ($sinAsignar | Sort-Object LastWriteTime)) {
        $num = "{0:D2}" -f ($i + 1)
        $ts = Get-Date $captura.LastWriteTime -Format 'HHmm'
        $nombreDestino = "$num-captura-$ts$($captura.Extension.ToLower())"

        $planCompleto += [PSCustomObject]@{
            Origen = $captura.FullName
            Fecha = $captura.LastWriteTime
            Sesion = $nombreSesionNueva
            NombreDestino = $nombreDestino
            RutaDestino = Join-Path $repoRoot "docs\capturas\$nombreSesionNueva\$nombreDestino"
        }
        $i++
    }
}

# === Ejecutar plan ===
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host "  TOTAL A MOVER: $($planCompleto.Count) capturas" -ForegroundColor Green
Write-Host "=====================================" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "DRY RUN — mostrando primeros 10 movimientos que se harian:" -ForegroundColor Yellow
    Write-Host ""
    foreach ($mov in ($planCompleto | Select-Object -First 10)) {
        $origenCorto = Split-Path -Leaf $mov.Origen
        Write-Host "  $origenCorto"
        Write-Host "    -> $($mov.Sesion)\$($mov.NombreDestino)" -ForegroundColor DarkGray
    }
    if ($planCompleto.Count -gt 10) {
        Write-Host "  ... y $($planCompleto.Count - 10) mas"
    }
    Write-Host ""
    Write-Host "Ejecuta sin -DryRun para mover realmente." -ForegroundColor Yellow
    exit 0
}

# Confirmar
Write-Host "Se van a MOVER $($planCompleto.Count) archivos." -ForegroundColor Yellow
$confirm = Read-Host "Continuar? (s/n)"
if ($confirm -ne 's' -and $confirm -ne 'S' -and $confirm -ne 'y' -and $confirm -ne 'Y') {
    Write-Host "Cancelado." -ForegroundColor Yellow
    exit 0
}

# Crear carpetas destino
$carpetasDestino = ($planCompleto | ForEach-Object { Split-Path $_.RutaDestino }) | Sort-Object -Unique
foreach ($carpeta in $carpetasDestino) {
    if (-not (Test-Path $carpeta)) {
        New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
    }
}

# Mover archivos
$totalMovido = 0
foreach ($mov in $planCompleto) {
    if (Test-Path $mov.RutaDestino) {
        Write-Host "  [SKIP] Ya existe: $($mov.NombreDestino)" -ForegroundColor DarkGray
        continue
    }
    try {
        Move-Item -Path $mov.Origen -Destination $mov.RutaDestino
        Write-Host "  [OK] $($mov.Sesion)\$($mov.NombreDestino)" -ForegroundColor Green
        $totalMovido++
    } catch {
        Write-Host "  [ERR] $($mov.Origen): $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "$totalMovido archivos movidos con exito." -ForegroundColor Green

# Commit + push
if ($AutoCommit -and $totalMovido -gt 0) {
    Write-Host ""
    Write-Host "Haciendo commit + push..." -ForegroundColor Cyan
    Push-Location $repoRoot
    try {
        git add "docs/capturas/"

        $mensaje = "docs(capturas): mover $totalMovido capturas fisicas al repo`n`n" +
                   "Capturas movidas desde carpeta local de Windows a las`n" +
                   "carpetas correspondientes en docs/capturas/, usando los`n" +
                   "nombres exactos definidos en los README de cada sesion."

        $tmpFile = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $tmpFile -Value $mensaje -Encoding UTF8
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
