@echo off
REM Auto-eleva a admin y ejecuta el installer
NET SESSION >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Solicitando permisos de administrador...
    powershell -Command "Start-Process cmd.exe -ArgumentList '/c %~s0' -Verb RunAs"
    exit /b
)
echo Instalando Task Scheduler TemazoCookieSync...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_scheduled_task.ps1"
echo.
echo === Verificando ===
schtasks /Query /TN "TemazoCookieSync" /FO LIST 2>nul | findstr "Nombre TaskName Estado Status"
echo.
pause
