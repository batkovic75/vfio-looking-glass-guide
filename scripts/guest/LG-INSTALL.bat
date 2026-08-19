@echo off
REM Installs the LookingGlassHost scheduled task. Run once, accept the UAC prompt.
REM Elevation is unconditional: testing "net session" gives a false positive.
if "%~1"=="ELEV" goto doit
powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList 'ELEV' -Verb RunAs"
exit /b
:doit
powershell -NoProfile -ExecutionPolicy Bypass -File "Z:\lgtask.ps1" > "Z:\task.txt" 2>&1
