param(
    [ValidateSet('Sistema','Backend','App')][string]$Componente = 'Sistema',
    [ValidateSet('Nativo','Docker')][string]$Modo = 'Nativo',
    [switch]$SoloInstalar,
    [switch]$SinAbrirApp
)
$ErrorActionPreference = 'Stop'
$raiz = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$backend = Join-Path $raiz 'backend'
$frontend = Join-Path $raiz 'frontend'
$app = Join-Path $raiz 'app-desktop'
$logs = Join-Path $env:LOCALAPPDATA 'SistemaExplicadorPythonIA\logs'
New-Item -ItemType Directory -Force -Path $logs | Out-Null

function Ejecutar([string]$Programa, [string[]]$Argumentos) {
    & $Programa @Argumentos
    if ($LASTEXITCODE -ne 0) { throw "$Programa fallo (codigo $LASTEXITCODE)." }
}
function Requerir([string]$Nombre, [string]$Instruccion) {
    $c = Get-Command $Nombre -ErrorAction SilentlyContinue
    if (-not $c) { throw "$Nombre no esta en PATH. $Instruccion" }
    return $c.Source
}
function Preparar-Backend {
    $base = Requerir 'python' 'Instale Python 3.11 o superior con la opcion Add Python to PATH.'
    $script:python = Join-Path $backend '.venv\Scripts\python.exe'
    if (-not (Test-Path $script:python)) { Ejecutar $base @('-m','venv',(Join-Path $backend '.venv')) }
    & $script:python -c "import importlib.util,sys; sys.exit(0 if importlib.util.find_spec('pip') else 1)"
    if ($LASTEXITCODE -ne 0) { Ejecutar $script:python @('-m','ensurepip','--upgrade') }
    $req = Join-Path $backend 'requirements.txt'
    $stamp = Join-Path $backend '.venv\requirements.sha256'
    $hash = (Get-FileHash -LiteralPath $req).Hash + (Get-FileHash (Join-Path $backend 'requirements-lock.txt')).Hash
    if (-not (Test-Path $stamp) -or (Get-Content $stamp -Raw).Trim() -ne $hash) {
        Ejecutar $script:python @('-m','pip','install','-r',$req)
        Set-Content -LiteralPath $stamp -Value $hash
    }
    Ejecutar $script:python @((Join-Path $backend 'scripts\preparar_entorno.py'))
}
function Preparar-Web {
    $script:npm = Requerir 'npm.cmd' 'Instale Node.js 22 LTS o 24 LTS.'
    $stamp = Join-Path $frontend 'node_modules\.instalacion.sha256'
    $hash = (Get-FileHash (Join-Path $frontend 'package-lock.json')).Hash
    Push-Location $frontend
    try {
        if (-not (Test-Path $stamp) -or (Get-Content $stamp -Raw).Trim() -ne $hash) {
            Ejecutar $script:npm @('ci')
            Set-Content -LiteralPath $stamp -Value $hash
        }
    } finally { Pop-Location }
}
function Preparar-App {
    $script:flutter = Requerir 'flutter.bat' 'Instale Flutter stable (Dart >=3.10.1) y Visual Studio con Desktop development with C++.'
    Push-Location $app
    try { Ejecutar $script:flutter @('pub','get') } finally { Pop-Location }
}
function Puerto-Ocupado([int]$Puerto) {
    return [bool](Get-NetTCPConnection -LocalPort $Puerto -State Listen -ErrorAction SilentlyContinue)
}
function Esperar([string]$Url, [int]$Segundos = 60) {
    $fin = (Get-Date).AddSeconds($Segundos)
    while ((Get-Date) -lt $fin) {
        try { return Invoke-RestMethod -Uri $Url -TimeoutSec 2 } catch { Start-Sleep -Milliseconds 500 }
    }
    throw "No respondio $Url. Revise los registros en $logs."
}
try {
    if ($Componente -ne 'App') {
        if ($Modo -eq 'Docker') {
            $docker = Requerir 'docker' 'Instale e inicie Docker Desktop (contenedores Linux).'
            Ejecutar $docker @('info','--format','{{.ServerVersion}}')
            # Docker no necesita Python instalado en el equipo.
            $envBackend = Join-Path $backend '.env'
            if (-not (Test-Path $envBackend)) {
                $legacy = Join-Path $raiz '.env'
                if (Test-Path $legacy) { Copy-Item -LiteralPath $legacy -Destination $envBackend }
                else {
                    $secret = ([guid]::NewGuid().ToString('N') + [guid]::NewGuid().ToString('N'))
                    $clave = [guid]::NewGuid().ToString('N')
                    Set-Content -LiteralPath $envBackend -Encoding ASCII -Value "APP_ENV=development`nSECRET_KEY=$secret`nADMIN_EMAIL=admin@explicador.com`nADMIN_PASSWORD=$clave`nMODEL_ENABLED=true"
                }
            }
            $texto = Get-Content $envBackend -Raw
            foreach ($par in @(@('POSTGRES_USER','explicador'),@('POSTGRES_PASSWORD',[guid]::NewGuid().ToString('N')),@('POSTGRES_DB','sistema_explicador'))) {
                if ($texto -notmatch "(?m)^$($par[0])=") { Add-Content $envBackend -Value "$($par[0])=$($par[1])" }
            }
            $compose = @('compose','--project-directory',$raiz,'--env-file',$envBackend,'-f',(Join-Path $raiz 'docker-compose.yml'))
            if ($SoloInstalar) { Ejecutar $docker ($compose + @('build')) }
            else {
                $servicios = @('db','backend')
                if ($Componente -eq 'Sistema') { $servicios += 'frontend' }
                Ejecutar $docker ($compose + @('up','-d','--build','--wait','--wait-timeout','180') + $servicios)
            }
        } else {
            Preparar-Backend
            if ($Componente -eq 'Sistema') { Preparar-Web }
            if (-not $SoloInstalar) {
                if (Puerto-Ocupado 8765) {
                    $salud = Esperar 'http://127.0.0.1:8765/' 3
                    if ($salud.sistema -ne 'Sistema Explicador Python IA') { throw 'Puerto 8765 ocupado por otro servicio.' }
                    Write-Host '[INFO] Se reutiliza el backend activo. Si era antiguo, cierre su proceso antes de reiniciar.'
                } else {
                    Start-Process -FilePath $script:python -ArgumentList @('-m','uvicorn','app.main:app','--host','127.0.0.1','--port','8765','--reload','--reload-dir','app') -WorkingDirectory $backend -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logs 'backend-out.log') -RedirectStandardError (Join-Path $logs 'backend-error.log') | Out-Null
                }
                Esperar 'http://127.0.0.1:8765/health' | Out-Null
                if ($Componente -eq 'Sistema') {
                    if (Puerto-Ocupado 3000) {
                        $web = Esperar 'http://127.0.0.1:3000/api/sistema' 3
                        if ($web.sistema -ne 'Sistema Explicador Python IA' -or $web.componente -ne 'web') { throw 'Puerto 3000 ocupado por otro servicio.' }
                        Write-Host '[INFO] Se reutiliza el portal activo.'
                    } else {
                        $webScript = Join-Path $frontend 'scripts\iniciar_local.ps1'
                        Start-Process -FilePath 'powershell.exe' -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$webScript`"" -WorkingDirectory $frontend -WindowStyle Hidden -RedirectStandardOutput (Join-Path $logs 'web-out.log') -RedirectStandardError (Join-Path $logs 'web-error.log') | Out-Null
                    }
                    Esperar 'http://127.0.0.1:3000/api/sistema' 120 | Out-Null
                }
            }
        }
        if ($SoloInstalar) { Write-Host '[OK] Dependencias preparadas; no se han iniciado servicios.' }
        else { Write-Host '[OK] Backend: http://127.0.0.1:8765/docs' }
    }
    if ($Componente -ne 'Backend' -and -not $SinAbrirApp) {
        Preparar-App
        if (-not $SoloInstalar) {
            if ($Componente -eq 'Sistema') { Start-Process 'http://localhost:3000' }
            Write-Host '[INFO] Flutter compila el codigo actual. R reinicia; q cierra la aplicacion.'
            Push-Location $app
            try { Ejecutar $script:flutter @('run','-d','windows','--debug') } finally { Pop-Location }
        }
    }
} catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
