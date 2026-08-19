@echo off
REM Instantaneous GPU load. No admin needed.
REM WARNING: switching to this script sends a fullscreen application to the
REM background, where it stops rendering - you will measure an idle desktop.
REM Use GPUWATCH.bat instead to measure while the application is in front.
echo === GPU load === > "Z:\gpucheck.txt"
"C:\Windows\System32\nvidia-smi.exe" --query-gpu=name,utilization.gpu,clocks.current.graphics,clocks.max.graphics,memory.used,temperature.gpu --format=csv >> "Z:\gpucheck.txt" 2>&1
echo. >> "Z:\gpucheck.txt"
echo === Processes using the GPU === >> "Z:\gpucheck.txt"
"C:\Windows\System32\nvidia-smi.exe" --query-compute-apps=pid,process_name,used_memory --format=csv >> "Z:\gpucheck.txt" 2>&1
