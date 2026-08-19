@echo off
REM Delayed GPU sampling: waits 15 s, then takes 8 samples 2 s apart.
REM Launch it, then switch straight back to your application so the numbers
REM reflect real work rather than an idle desktop. No admin needed.
echo === deferred sampling - go back to your application now === > "Z:\gpuwatch.txt"
timeout /t 15 /nobreak >nul
for /L %%i in (1,1,8) do (
  "C:\Windows\System32\nvidia-smi.exe" --query-gpu=utilization.gpu,clocks.current.graphics,clocks.max.graphics,memory.used --format=csv,noheader >> "Z:\gpuwatch.txt" 2>&1
  timeout /t 2 /nobreak >nul
)
echo --- done --- >> "Z:\gpuwatch.txt"
