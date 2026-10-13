$ErrorActionPreference = 'Stop'
$raiz = $PSScriptRoot
$contenido = Get-Content (Join-Path $raiz 'app-desktop\pubspec.yaml') -Raw
$version = [regex]::Match($contenido, '(?m)^version:\s*([\w.+-]+)').Groups[1].Value
if (-not $version) { throw 'No se encontro la version.' }
$origen = Join-Path $raiz "release\$version\desktop"
if (-not (Test-Path (Join-Path $origen 'app_desktop.exe'))) { throw 'Ejecute primero empaquetar.ps1.' }
$destino = Join-Path $raiz "release\Sistema_Explicador_Python_IA_$version.zip"
if (Test-Path $destino) { throw 'El ZIP ya existe. Use otra version para la siguiente entrega.' }
Compress-Archive -Path (Join-Path $origen '*') -DestinationPath $destino -CompressionLevel Optimal
Write-Host "[OK] ZIP: $destino"
