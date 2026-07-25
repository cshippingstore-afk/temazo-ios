@echo off
REM Doble-click aqui - te pedira permiso de Administrador y lo instalara todo.

REM Re-lanzar como admin si no lo somos ya
NET SESSION >nul 2>&1
if %errorLevel% NEQ 0 (
    echo Solicitando permisos de administrador...
    powershell -Command "Start-Process cmd.exe -ArgumentList '/c %~s0' -Verb RunAs"
    exit /b
)

cd /d "%~dp0"
echo.
echo ==========================================================
echo   TEMAZO Cookie Sync - Instalador
echo ==========================================================
echo.
echo 1) Comprobando que estas logueado en YouTube (Firefox)...
python -c "import browser_cookie3; cj=browser_cookie3.firefox(domain_name='youtube.com'); names={c.name for c in cj}; print('OK LOGUEADO en Firefox' if 'SAPISID' in names else 'NO LOGUEADO - abre youtube.com en Firefox y logueate primero')"
if %errorLevel% NEQ 0 (
    echo.
    echo ERROR al leer cookies. Cierra Chrome COMPLETAMENTE y reintenta.
    pause
    exit /b 1
)
echo.
echo 2) Instalando Task Scheduler (sync cada 12h)...
powershell -ExecutionPolicy Bypass -File "%~dp0install_scheduled_task.ps1"
echo.
echo 3) Todo listo. Cierra esta ventana.
pause
