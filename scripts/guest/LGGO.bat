@echo off
REM Restarts the Looking Glass host. Needs NO administrator rights:
REM the scheduled task already carries the privileges.
schtasks /run /tn "LookingGlassHost" > "Z:\lggo.txt" 2>&1
