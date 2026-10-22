@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\cloudflare.ps1" -Accion Iniciar
if errorlevel 1 echo [ERROR] Revise docs\SERVIDOR_CLOUDFLARE.md en la raiz del proyecto.
pause
