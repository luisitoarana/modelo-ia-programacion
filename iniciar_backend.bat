@echo off
setlocal
cd /d "%~dp0"
set "MODO=Nativo"
echo 1. Normal local (dependencias automaticas)
echo 2. Docker local (Docker Desktop debe estar iniciado)
choice /c 12 /n /m "Seleccione 1 o 2: "
if errorlevel 2 set "MODO=Docker"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\iniciar.ps1" -Componente Backend -Modo %MODO%
if errorlevel 1 (echo [ERROR] Revise el mensaje anterior. & pause & exit /b 1)
pause
