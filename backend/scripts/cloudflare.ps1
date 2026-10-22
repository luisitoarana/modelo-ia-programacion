param(
    [ValidateSet('Autorizar','Preparar','Publicar','Iniciar','Verificar')]
    [string]$Accion = 'Verificar',
    [string]$Hostname = 'api-pythonia.aranadev.com',
    [string]$NombreTunel = 'pythonia-laptop'
)
$ErrorActionPreference = 'Stop'
if ($Hostname -notmatch '^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$') { throw 'Hostname invalido: use solo el dominio, sin https ni rutas.' }
if ($NombreTunel -notmatch '^[a-zA-Z0-9-]+$') { throw 'Nombre de tunel invalido.' }
$backend = Split-Path $PSScriptRoot -Parent
$carpeta = Join-Path $backend '.runtime\cloudflare'
$config = Join-Path $carpeta 'config.yml'
$idArchivo = Join-Path $carpeta 'tunnel-id.txt'

function Obtener-Conector {
    $comando = Get-Command cloudflared.exe -ErrorAction SilentlyContinue
    if ($comando) { return $comando.Source }
    foreach ($ruta in @("${env:ProgramFiles(x86)}\cloudflared\cloudflared.exe", "$env:ProgramFiles\cloudflared\cloudflared.exe")) {
        if (Test-Path -LiteralPath $ruta) { return $ruta }
    }
    throw 'Instale el conector: winget install --id Cloudflare.cloudflared --exact --source winget'
}
function Ejecutar-Conector([string[]]$Argumentos) {
    & $script:conector @Argumentos
    if ($LASTEXITCODE -ne 0) { throw 'Cloudflared no completo la operacion. Revise el mensaje anterior.' }
}
function Verificar-Local {
    $respuesta = Invoke-RestMethod 'http://127.0.0.1:8765/' -TimeoutSec 10
    if ($respuesta.sistema -ne 'Sistema Explicador Python IA') { throw 'El puerto 8765 no corresponde a PythonIA.' }
    $salud = Invoke-RestMethod 'http://127.0.0.1:8765/health' -TimeoutSec 10
    if ($salud.status -ne 'ok') { throw 'El backend no esta listo.' }
    Write-Host '[OK] Backend local disponible en 127.0.0.1:8765.'
}

if ($Accion -eq 'Verificar') {
    Verificar-Local
    $respuesta = Invoke-RestMethod "https://$Hostname/" -TimeoutSec 15
    if ($respuesta.sistema -ne 'Sistema Explicador Python IA') { throw 'El dominio no apunta a PythonIA.' }
    $salud = Invoke-RestMethod "https://$Hostname/health" -TimeoutSec 15
    if ($salud.status -ne 'ok') { throw 'El backend remoto no esta listo.' }
    # El perfil debe rechazar peticiones sin iniciar sesion.
    try {
        Invoke-WebRequest "https://$Hostname/api/v1/auth/yo" -UseBasicParsing -TimeoutSec 15 | Out-Null
        throw 'El perfil respondio sin autenticacion. No continuar con estudiantes.'
    } catch {
        if (-not $_.Exception.Response -or [int]$_.Exception.Response.StatusCode -notin @(401,403)) { throw }
    }
    Write-Host "[OK] HTTPS y autenticacion comprobados: https://$Hostname/api/v1"
    exit 0
}
$script:conector = Obtener-Conector
if ($Accion -eq 'Autorizar') {
    Ejecutar-Conector @('tunnel','login')
    exit 0
}
if ($Accion -eq 'Preparar') {
    New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
    $lista = & $script:conector tunnel list --output json
    if ($LASTEXITCODE -ne 0) { throw 'Primero ejecute -Accion Autorizar y seleccione su dominio en el navegador.' }
    $todos = $lista | ConvertFrom-Json
    $tuneles = @($todos | Where-Object { $_.name -eq $NombreTunel })
    if ($tuneles.Count -gt 1) { throw 'Hay varios tuneles con el mismo nombre. Use un nombre unico.' }
    if ($tuneles.Count -eq 0) {
        Ejecutar-Conector @('tunnel','create',$NombreTunel)
        $lista = & $script:conector tunnel list --output json
        if ($LASTEXITCODE -ne 0) { throw 'No se pudo consultar el tunel creado.' }
        $todos = $lista | ConvertFrom-Json
        $tuneles = @($todos | Where-Object { $_.name -eq $NombreTunel })
    }
    if ($tuneles.Count -ne 1) { throw 'No se encontro un tunel unico.' }
    $idTunel = [string]$tuneles[0].id
    $credenciales = Join-Path $env:USERPROFILE ".cloudflared\$idTunel.json"
    if (-not (Test-Path -LiteralPath $credenciales)) { throw 'Este tunel pertenece a otra instalacion o no tiene credenciales locales. Use otro nombre; no altere sus tuneles actuales.' }
    $rutaYaml = $credenciales.Replace('\','/')
    @"
# Configuracion privada de ESTA laptop. No copiar al instalador ni a GitHub.
tunnel: $idTunel
credentials-file: '$rutaYaml'
ingress:
  - hostname: $Hostname
    service: http://127.0.0.1:8765
    originRequest:
      connectTimeout: 30s
  - service: http_status:404
"@ | Set-Content -LiteralPath $config -Encoding UTF8
    Set-Content -LiteralPath $idArchivo -Value $idTunel -Encoding ASCII
    Ejecutar-Conector @('tunnel','--config',$config,'ingress','validate')
    Write-Host '[OK] Configuracion preparada. Todavia no se ha creado el DNS ni iniciado el tunel.'
    exit 0
}
if (-not (Test-Path -LiteralPath $config) -or -not (Test-Path -LiteralPath $idArchivo)) { throw 'Ejecute primero -Accion Preparar.' }
$idTunel = (Get-Content -LiteralPath $idArchivo -Raw).Trim()
if ($idTunel -notmatch '^[a-f0-9-]{36}$') { throw 'Identificador local de tunel invalido.' }
# La configuracion guardada es la autoridad: no publicar otro hostname por error.
if ((Get-Content -LiteralPath $config -Raw) -notmatch "(?m)^  - hostname: $([regex]::Escape($Hostname))\s*$") { throw 'El hostname no coincide con la configuracion preparada.' }
if ($Accion -eq 'Publicar') {
    Verificar-Local
    # Sin --overwrite-dns: nunca reemplazar una ruta existente de otro servicio.
    Ejecutar-Conector @('tunnel','route','dns',$idTunel,$Hostname)
    Write-Host '[OK] DNS creado. Ejecute -Accion Iniciar para conectar esta laptop.'
} elseif ($Accion -eq 'Iniciar') {
    Verificar-Local
    Write-Host '[INFO] Mantenga esta ventana abierta. Ctrl+C desconecta SOLO este tunel.'
    Ejecutar-Conector @('tunnel','--config',$config,'run',$idTunel)
}
