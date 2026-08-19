@echo off
REM Actual resolution and refresh rate, plus the modes the EDID declares.
REM No admin needed - safe to run when you cannot see the screen.
echo === Adapter resolution and refresh === > "Z:\refresh.txt"
powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | Select-Object Name,CurrentHorizontalResolution,CurrentVerticalResolution,CurrentRefreshRate,MaxRefreshRate | Format-List" >> "Z:\refresh.txt" 2>&1
echo === Modes declared by the attached display (EDID) === >> "Z:\refresh.txt"
powershell -NoProfile -Command "Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorListedSupportedSourceModes -ErrorAction SilentlyContinue | ForEach-Object { $_.InstanceName; $_.MonitorSourceModes | Select-Object HorizontalActivePixels,VerticalActivePixels,VerticalRefreshRateNumerator | Format-Table }" >> "Z:\refresh.txt" 2>&1
