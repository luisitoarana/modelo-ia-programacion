param([string]$ApiUrl = 'http://localhost:8765/api/v1')
$ErrorActionPreference = 'Stop'
if ($ApiUrl -notmatch '^https?://[^\s]+/api/v1/?$') { throw 'API URL invalida.' }
$raiz = $PSScriptRoot
$contenido = Get-Content (Join-Path $raiz 'app-desktop\pubspec.yaml') -Raw
$version = [regex]::Match($contenido, '(?m)^version:\s*([\w.+-]+)').Groups[1].Value
if (-not $version) { throw 'No se encontro version en pubspec.yaml.' }
$destino = Join-Path $raiz "release\$version\desktop"
if (Test-Path $destino) { throw "Ya existe $destino. Cambie la version antes de generar otra entrega." }
Push-Location (Join-Path $raiz 'app-desktop')
try {
    & flutter.bat pub get
    if ($LASTEXITCODE -ne 0) { throw 'Fallo pub get.' }
    & flutter.bat build windows --release "--dart-define=API_URL=$ApiUrl"
    if ($LASTEXITCODE -ne 0) { throw 'Fallo la compilacion de Windows.' }
    $origen = Join-Path $raiz 'app-desktop\build\windows\x64\runner\Release'
    if (-not (Test-Path (Join-Path $origen 'app_desktop.exe'))) { throw 'No existe el ejecutable compilado.' }
    New-Item -ItemType Directory -Path $destino -Force | Out-Null
    Copy-Item -Path (Join-Path $origen '*') -Destination $destino -Recurse
    Copy-Item -LiteralPath (Join-Path $raiz 'docs\INSTALACION_JURADO.md') -Destination (Join-Path $raiz "release\$version\LEEME.md")
    Write-Host "[OK] Cliente compilado: $destino"
    Write-Host "[INFO] Backend configurado: $ApiUrl. El cliente no incluye servidor ni modelos."
} finally { Pop-Location }
