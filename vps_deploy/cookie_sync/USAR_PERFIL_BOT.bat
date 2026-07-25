@echo off
REM Sincroniza cookies del perfil Firefox "TemazoBot" al VPS
REM y configura Task Scheduler para hacerlo cada 12h automatico
cd /d "%~dp0"
echo.
echo === Buscando perfil Firefox "TemazoBot" ===
python find_and_sync_bot_profile.py
if %errorLevel% NEQ 0 (
    echo.
    echo Sync fallo. Asegurate de haber creado el perfil "TemazoBot" y logueado a YouTube.
    pause
    exit /b 1
)
echo.
echo === Instalando Task Scheduler (auto sync cada 12h) ===
NET SESSION >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Solicitando permisos de administrador...
    powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File %~dp0install_scheduled_task.ps1' -Verb RunAs"
) else (
    powershell -ExecutionPolicy Bypass -File "%~dp0install_scheduled_task.ps1"
)
echo.
pause
