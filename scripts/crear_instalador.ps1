param(
    [string]$ApiUrl = 'https://api-pythonia.aranadev.com/api/v1',
    [switch]$SinCompilar,
    [switch]$CopiarAlEscritorio
)
$ErrorActionPreference = 'Stop'
$raiz = Split-Path $PSScriptRoot -Parent
if ($ApiUrl -notmatch '^https?://[^\s]+/api/v1/?$') { throw 'API URL invalida.' }
$contenido = Get-Content (Join-Path $raiz 'app-desktop\pubspec.yaml') -Raw
$version = [regex]::Match($contenido, '(?m)^version:\s*([\w.+-]+)').Groups[1].Value
if (-not $version) { throw 'No se encontro version en pubspec.yaml.' }
$versionApp = ($version -split '\+')[0]
if (-not $SinCompilar) { & (Join-Path $raiz 'empaquetar.ps1') -ApiUrl $ApiUrl }
$cliente = Join-Path $raiz "release\$version\desktop"
$manifiesto = Join-Path $cliente 'entrega.json'
if (-not (Test-Path -LiteralPath $manifiesto)) { throw 'No hay manifiesto de compilacion. Compile con empaquetar.ps1 antes de empaquetar.' }
$datos = Get-Content -LiteralPath $manifiesto -Raw | ConvertFrom-Json
if ($datos.api_url -ne $ApiUrl -or $datos.version -ne $version) { throw 'El cliente compilado corresponde a otra URL o version.' }
# Distribucion local del runtime de Visual C++: no exigir Visual Studio al alumno.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path -LiteralPath $vswhere)) { throw 'No se encuentra vswhere para localizar el runtime redistribuible de Visual C++.' }
$vs = & $vswhere -latest -products '*' -property installationPath
if ($LASTEXITCODE -ne 0 -or -not $vs) { throw 'No se encuentra una instalacion de Visual Studio.' }
$runtimes = @(Get-ChildItem -Path (Join-Path $vs 'VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT') -Directory -ErrorAction SilentlyContinue | Sort-Object FullName -Descending)
if ($runtimes.Count -eq 0) { throw 'Falta el runtime redistribuible x64 de Visual C++; instale las herramientas de C++.' }
Copy-Item -Path (Join-Path $runtimes[0].FullName '*.dll') -Destination $cliente -Force
foreach ($dll in @('msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll')) {
    if (-not (Test-Path -LiteralPath (Join-Path $cliente $dll))) { throw "Falta $dll en la entrega." }
}
$iscc = Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $iscc) {
    foreach ($ruta in @("$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe", "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", "$env:ProgramFiles\Inno Setup 6\ISCC.exe")) {
        if (Test-Path -LiteralPath $ruta) { $iscc = $ruta; break }
    }
}
if (-not $iscc) { throw 'Instale Inno Setup: winget install --id JRSoftware.InnoSetup --exact --source winget --scope user' }
Push-Location $raiz
try {
    & $iscc "/DAppVersion=$versionApp" "/DBuildVersion=$version" 'instalador_inno_setup.iss'
    if ($LASTEXITCODE -ne 0) { throw 'Fallo la compilacion del instalador.' }
} finally { Pop-Location }
$instalador = Join-Path $raiz "release\$version\instalador\Instalador_PythonIA_$versionApp.exe"
$hash = (Get-FileHash -LiteralPath $instalador -Algorithm SHA256).Hash
Set-Content -LiteralPath "$instalador.sha256" -Value "$hash  $([IO.Path]::GetFileName($instalador))" -Encoding ASCII
if ($CopiarAlEscritorio) {
    $escritorio = [Environment]::GetFolderPath('Desktop')
    Copy-Item -LiteralPath $instalador,"$instalador.sha256" -Destination $escritorio -Force
    Copy-Item -LiteralPath (Join-Path $raiz 'docs\PRUEBA_OTRA_LAPTOP.txt') -Destination $escritorio -Force
    Write-Host "[OK] Instalador y guia copiados a $escritorio"
}
Write-Host "[OK] Instalador: $instalador"
