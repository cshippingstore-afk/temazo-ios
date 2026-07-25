@echo off
setlocal
set FIREFOX="C:\Program Files\Mozilla Firefox\firefox.exe"
if not exist %FIREFOX% (
    echo Firefox no encontrado en C:\Program Files\Mozilla Firefox\
    pause
    exit /b 1
)

echo.
echo ============================================================
echo  TEMAZO - Setup perfil Firefox dedicado para el bot
echo ============================================================
echo.
echo 1) Creando perfil "TemazoBot"...
%FIREFOX% -CreateProfile "TemazoBot"
timeout /t 2 /nobreak >nul

echo.
echo 2) Abriendo Firefox con ese perfil en youtube.com...
echo.
echo    == LOGUEATE con la cuenta BURNER ==
echo    (crea una si no la tienes en accounts.google.com/signup)
echo.
echo    Cuando veas tu avatar arriba a la derecha:
echo    1. Cierra ESE Firefox (X arriba a la derecha)
echo    2. Vuelve a esta ventana y presiona cualquier tecla
echo.

start "" %FIREFOX% -P "TemazoBot" -no-remote "https://accounts.google.com/ServiceLogin?service=youtube&continue=https://www.youtube.com/"

echo.
echo ============================================================
pause
echo.
echo 3) Ejecutando primera sincronizacion...
cd /d "%~dp0"
python find_and_sync_bot_profile.py
if %errorLevel% NEQ 0 (
    echo.
    echo Sync fallo. Revisa que hayas logueado en YouTube en el perfil TemazoBot.
    pause
    exit /b 1
)
echo.
echo 4) Instalando Task Scheduler para auto-sync cada 12h...
NET SESSION >nul 2>&1
if %errorLevel% NEQ 0 (
    powershell -Command "Start-Process powershell -ArgumentList '-ExecutionPolicy Bypass -File %~dp0install_scheduled_task.ps1' -Verb RunAs"
) else (
    powershell -ExecutionPolicy Bypass -File "%~dp0install_scheduled_task.ps1"
)
echo.
echo === TODO LISTO ===
pause
