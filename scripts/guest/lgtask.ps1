# Registers the Looking Glass host as a scheduled task:
#   - runs at logon, with highest privileges  -> no UAC prompt
#   - repeats every minute                    -> watchdog, restarts it if it dies
# See docs/04-looking-glass.md

$exe = "C:\Program Files\Looking Glass (host)\looking-glass-host.exe"
$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$adm = (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
           [Security.Principal.WindowsBuiltInRole]::Administrator)

"Elevated   : $adm"
"Executable : " + (Test-Path $exe)
if (-not $adm)         { "ABORT: not elevated";        exit 1 }
if (-not (Test-Path $exe)) { "ABORT: host not installed"; exit 1 }

$action  = New-ScheduledTaskAction -Execute $exe
$trigger = New-ScheduledTaskTrigger -AtLogOn

# NOTE: [TimeSpan]::MaxValue is rejected by Task Scheduler (value out of range).
# A bounded duration is fine - the window restarts at every logon.
$trigger.Repetition = (New-ScheduledTaskTrigger -Once -At (Get-Date) `
        -RepetitionInterval (New-TimeSpan -Minutes 1) `
        -RepetitionDuration (New-TimeSpan -Days 30)).Repetition

$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
        -RunLevel Highest -LogonType Interactive
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) `
        -MultipleInstances IgnoreNew -RestartCount 0

Register-ScheduledTask -TaskName "LookingGlassHost" -Action $action `
        -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

$t = Get-ScheduledTask -TaskName "LookingGlassHost"
"TaskName   : " + $t.TaskName
"State      : " + $t.State
"Repetition : " + $t.Triggers[0].Repetition.Interval   # expect PT1M
"Instances  : " + $t.Settings.MultipleInstances        # expect IgnoreNew
"--- done ---"
