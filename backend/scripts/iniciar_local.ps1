# Compatibilidad para iniciar solo el backend nativo.
& (Join-Path $PSScriptRoot '..\..\scripts\iniciar.ps1') -Componente Backend -Modo Nativo
exit $LASTEXITCODE
