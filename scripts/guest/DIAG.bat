@echo off
REM Video adapters and monitors, as seen by Windows. No admin needed.
echo === Video adapters === > "Z:\diag.txt"
powershell -NoProfile -Command "Get-CimInstance Win32_VideoController | Select-Object Name,CurrentHorizontalResolution,CurrentVerticalResolution,Availability | Format-List" >> "Z:\diag.txt" 2>&1
echo. >> "Z:\diag.txt"
echo === Monitors (PnP) === >> "Z:\diag.txt"
powershell -NoProfile -Command "Get-PnpDevice -Class Monitor | Select-Object FriendlyName,Status,InstanceId | Format-List" >> "Z:\diag.txt" 2>&1
