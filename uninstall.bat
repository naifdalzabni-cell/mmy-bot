@echo off
net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
schtasks /end /tn SignalCopierBot
schtasks /delete /tn SignalCopierBot /f
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='pythonw.exe'\" | Where-Object { $_.ExecutablePath -like '*SignalCopier*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
del "%PUBLIC%\Desktop\Signal Copier.url" 2>nul
echo Bot removed from startup. You can now delete the folder C:\SignalCopier
timeout /t 10
