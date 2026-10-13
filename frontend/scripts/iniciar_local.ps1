$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '..')
try {
    & npm.cmd run dev -- --hostname 127.0.0.1
    exit $LASTEXITCODE
} finally { Pop-Location }
