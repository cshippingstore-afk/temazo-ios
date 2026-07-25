# Registra sync_cookies.py en Task Scheduler
# Corre como el usuario logueado (necesita acceso a DPAPI de Chrome)
# Trigger: cada 12 horas + al inicio de sesion (delay 5 min)
#
# Ejecutar UNA vez como Administrador (Right-click PowerShell -> Run as Administrator):
#   powershell -ExecutionPolicy Bypass -File install_scheduled_task.ps1

$ErrorActionPreference = "Continue"

$taskName = "TemazoCookieSync"
$scriptDir = $PSScriptRoot
# Preferir el script de perfil dedicado (evita rotacion YT)
$botScript = Join-Path $scriptDir "find_and_sync_bot_profile.py"
$genScript = Join-Path $scriptDir "sync_cookies.py"
if (Test-Path $botScript) { $scriptPath = $botScript } else { $scriptPath = $genScript }
$pythonExe = (Get-Command python.exe).Source

Write-Host "Task name : $taskName"
Write-Host "Python    : $pythonExe"
Write-Host "Script    : $scriptPath"
if (-not (Test-Path $scriptPath)) {
    throw "sync_cookies.py no encontrado en $scriptPath"
}

# Borrar tarea previa si existe (silencioso si no existe)
$prev = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($prev) {
    Write-Host "Borrando tarea previa..."
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

# Action: python sync_cookies.py
$action = New-ScheduledTaskAction -Execute $pythonExe -Argument "`"$scriptPath`"" -WorkingDirectory $scriptDir

# Triggers: cada 12h + al login (delay 5 min)
$trigger1 = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(3) `
    -RepetitionInterval (New-TimeSpan -Hours 12)
$trigger2 = New-ScheduledTaskTrigger -AtLogOn
$trigger2.Delay = "PT5M"

# Settings
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -RunOnlyIfNetworkAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

# Corre como usuario actual con highest privileges (para DPAPI Chrome)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive -RunLevel Highest

Register-ScheduledTask -TaskName $taskName -Action $action `
    -Trigger @($trigger1, $trigger2) -Settings $settings -Principal $principal `
    -Description "Temazo: sync cookies YouTube (Chrome) -> VPS cada 12h" | Out-Null

Write-Host ""
Write-Host "==============================================="
Write-Host "  Task instalada: $taskName"
Write-Host "  Frecuencia: cada 12h + al iniciar sesion"
Write-Host "  Logs: %LOCALAPPDATA%\TemazoCookieSync\sync.log"
Write-Host "==============================================="
Write-Host ""
Write-Host "Ejecutando primera sync AHORA..."
schtasks /Run /TN $taskName | Out-Null
Start-Sleep -Seconds 5
Write-Host ""
Write-Host "Ultimos logs:"
Get-Content "$env:LOCALAPPDATA\TemazoCookieSync\sync.log" -Tail 20 -ErrorAction SilentlyContinue
