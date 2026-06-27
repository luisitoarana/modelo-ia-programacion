<#
.SYNOPSIS
    Mueve las ultimas capturas de pantalla a docs/capturas/sesion-NN-YYYY-MM-DD/
    renombrandolas con prefijos numericos secuenciales y nombres descriptivos.
    Opcionalmente hace commit + push automatico.

.DESCRIPTION
    Busca las ultimas N capturas en la carpeta de OneDrive\Imagenes\Capturas de
    pantalla\ (o la que indiques), las renombra como "XX-<descripcion>.png" y
    las mueve a la carpeta de la sesion. Sirve para no tener que renombrar a
    mano cada vez.

.PARAMETER SesionId
    Numero de la sesion (ej: "08").

.PARAMETER Fecha
    Fecha de la sesion en formato YYYY-MM-DD.

.PARAMETER Nombres
    Array de nombres descriptivos para cada captura, en orden cronologico
    (de la mas vieja a la mas nueva). El numero de elementos determina cuantas
    capturas se mueven.

.PARAMETER CarpetaOrigen
    Donde buscar las capturas. Por defecto la carpeta estandar de Windows.

.PARAMETER AutoCommit
    Si se especifica, hace git add + commit + push automaticamente.

.EXAMPLE
    .\scripts\mover_capturas.ps1 -SesionId 08 -Fecha 2026-06-27 -Nombres @(
        "studio-git-pull",
        "procesos-y-log-entrenamiento",
        "modelo-b-v1-terminado-checkpoint",
        "metricas-inicio-vs-final",
        "dataset-v2-atorado-rate-limit"
    ) -AutoCommit

.EXAMPLE
    # Solo mover sin commit, para revisar antes:
    .\scripts\mover_capturas.ps1 -SesionId 08 -Fecha 2026-06-27 -Nombres @("captura-1", "captura-2")
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$SesionId,

    [Parameter(Mandatory=$true)]
    [string]$Fecha,

    [Parameter(Mandatory=$true)]
    [string[]]$Nombres,

    [string]$CarpetaOrigen = "",

    [switch]$AutoCommit
)

$ErrorActionPreference = 'Stop'

# Resolver raiz del repo
$repoRoot = git rev-parse --show-toplevel 2>$null
if (-not $repoRoot) {
    Write-Error "No estas en un repo git. Ejecuta este script desde el proyecto."
    exit 1
}
$repoRoot = $repoRoot.Replace('/', '\')

# Carpeta destino
$carpetaDestino = Join-Path $repoRoot "docs\capturas\sesion-$SesionId-$Fecha"
if (-not (Test-Path $carpetaDestino)) {
    Write-Host "Creando carpeta destino: $carpetaDestino" -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $carpetaDestino | Out-Null
}

# Detectar carpeta origen automaticamente si no se paso por parametro.
# Probamos rutas comunes en Windows (OneDrive y local, espanol e ingles).
# Usamos wildcards para evitar problemas de codificacion con tildes.
if (-not $CarpetaOrigen) {
    $rutasPosibles = @(
        # OneDrive en espanol con tilde — usamos wildcard para evitar encoding
        "$env:USERPROFILE\OneDrive\Im*genes\Capturas de pantalla",
        "$env:USERPROFILE\OneDrive\Im*genes\Screenshots",
        # OneDrive en ingles
        "$env:USERPROFILE\OneDrive\Pictures\Screenshots",
        "$env:USERPROFILE\OneDrive\Pictures\Capturas de pantalla",
        # Local sin OneDrive en espanol
        "$env:USERPROFILE\Im*genes\Capturas de pantalla",
        # Local sin OneDrive en ingles
        "$env:USERPROFILE\Pictures\Screenshots",
        # Snipping Tool nuevo (Windows 11)
        "$env:USERPROFILE\OneDrive\Im*genes\Recortes de pantalla",
        "$env:USERPROFILE\Im*genes\Recortes de pantalla"
    )

    Write-Host "Detectando carpeta de capturas automaticamente..." -ForegroundColor Cyan
    foreach ($ruta in $rutasPosibles) {
        # Resolve-Path expande el wildcard si la carpeta existe.
        $resolved = Resolve-Path -Path $ruta -ErrorAction SilentlyContinue
        if ($resolved) {
            $CarpetaOrigen = $resolved.Path
            Write-Host "  [OK] Encontrada: $CarpetaOrigen" -ForegroundColor Green
            break
        }
    }

    if (-not $CarpetaOrigen) {
        Write-Error @"
No se pudo detectar la carpeta de capturas automaticamente. Rutas probadas:
$($rutasPosibles -join "`n  ")

Pasa la ruta explicitamente con -CarpetaOrigen "ruta\completa", por ejemplo:
  .\scripts\mover_capturas.ps1 -SesionId 08 -Fecha 2026-06-27 -Nombres @(...) ``
      -CarpetaOrigen "$env:USERPROFILE\OneDrive\Imagenes\Capturas de pantalla"

(Tambien podes copiar la ruta desde Windows Explorer: abri la carpeta y
copia la barra de direcciones.)
"@
        exit 1
    }
}

# Verificar carpeta origen
if (-not (Test-Path $CarpetaOrigen)) {
    Write-Error "Carpeta origen no existe: $CarpetaOrigen"
    Write-Host "Intentalo con -CarpetaOrigen apuntando a tu carpeta real de capturas."
    exit 1
}

# Buscar las ultimas N capturas (N = numero de nombres dados)
$numCapturas = $Nombres.Count
Write-Host "Buscando las ultimas $numCapturas capturas en:" -ForegroundColor Cyan
Write-Host "  $CarpetaOrigen"

$capturas = Get-ChildItem -Path $CarpetaOrigen -Filter "*.png" -File |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First $numCapturas |
    Sort-Object LastWriteTime  # Re-ordenar cronologicamente (mas vieja primero)

if ($capturas.Count -eq 0) {
    Write-Error "No se encontraron archivos PNG en $CarpetaOrigen"
    exit 1
}

if ($capturas.Count -lt $numCapturas) {
    Write-Warning "Solo se encontraron $($capturas.Count) capturas, pero se pidieron $numCapturas nombres."
    Write-Warning "Se moveran las $($capturas.Count) disponibles con los primeros nombres."
}

# Determinar el siguiente numero de archivo en la carpeta destino
$existentes = Get-ChildItem -Path $carpetaDestino -Filter "*.png" -File -ErrorAction SilentlyContinue
$siguienteNumero = 1
if ($existentes) {
    $maxNumero = ($existentes | ForEach-Object {
        if ($_.Name -match '^(\d+)-') { [int]$matches[1] } else { 0 }
    } | Measure-Object -Maximum).Maximum
    $siguienteNumero = $maxNumero + 1
    Write-Host "Continuando numeracion desde $siguienteNumero (ya hay $($existentes.Count) capturas en destino)." -ForegroundColor Yellow
}

# Mover y renombrar
Write-Host "`nMoviendo capturas:" -ForegroundColor Green
$movidas = @()
$i = 0
foreach ($captura in $capturas) {
    if ($i -ge $Nombres.Count) { break }
    $numero = "{0:D2}" -f $siguienteNumero
    $nombreDescriptivo = $Nombres[$i]
    $nombreNuevo = "$numero-$nombreDescriptivo.png"
    $rutaDestino = Join-Path $carpetaDestino $nombreNuevo

    Move-Item -Path $captura.FullName -Destination $rutaDestino
    $movidas += $nombreNuevo
    Write-Host "  [OK] $($captura.Name) (mod: $($captura.LastWriteTime.ToString('HH:mm:ss')))"
    Write-Host "       -> docs\capturas\sesion-$SesionId-$Fecha\$nombreNuevo" -ForegroundColor DarkGray
    $siguienteNumero++
    $i++
}

Write-Host "`n$($movidas.Count) capturas movidas a:" -ForegroundColor Cyan
Write-Host "  docs\capturas\sesion-$SesionId-$Fecha\"

# Auto commit si se pidio
if ($AutoCommit) {
    Push-Location $repoRoot
    try {
        Write-Host "`nHaciendo commit + push automatico..." -ForegroundColor Green

        git add "docs/capturas/sesion-$SesionId-$Fecha/"
        if ($LASTEXITCODE -ne 0) { throw "git add fallo" }

        $listaCapturas = ($movidas | ForEach-Object { "- $_" }) -join "`n"
        $mensajeCommit = @"
docs(capturas): sesion $SesionId — $($movidas.Count) capturas movidas

$listaCapturas
"@

        # Pasar el mensaje por archivo temporal para evitar problemas de escape
        $tmpFile = [System.IO.Path]::GetTempFileName()
        Set-Content -Path $tmpFile -Value $mensajeCommit -Encoding UTF8
        git commit -F $tmpFile
        Remove-Item $tmpFile -Force
        if ($LASTEXITCODE -ne 0) { throw "git commit fallo" }

        git push origin main
        if ($LASTEXITCODE -ne 0) { throw "git push fallo" }

        Write-Host "`nCommit y push exitosos." -ForegroundColor Green
    } finally {
        Pop-Location
    }
} else {
    Write-Host "`nPara hacer commit y push manualmente:" -ForegroundColor Yellow
    Write-Host "  cd $repoRoot"
    Write-Host "  git add docs/capturas/sesion-$SesionId-$Fecha/"
    Write-Host "  git commit -m 'docs: capturas sesion $SesionId'"
    Write-Host "  git push"
}
