@echo off
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
schtasks /end /tn SignalCopierBot
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='pythonw.exe'\" | Where-Object { $_.CommandLine -like '*SignalCopier*' -or $_.ExecutablePath -like '*SignalCopier*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
echo Bot stopped. It will NOT start with Windows until you run start.bat again.
timeout /t 8
