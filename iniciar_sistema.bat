@echo off
setlocal
cd /d "%~dp0"
set "MODO=Nativo"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\iniciar.ps1" -Componente App -Modo %MODO%
if errorlevel 1 (echo [ERROR] Revise el mensaje anterior. & pause & exit /b 1)
pause
