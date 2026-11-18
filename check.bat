@echo off
cd /d C:\SignalCopier
if not exist "C:\SignalCopier\venv\Scripts\python.exe" (
  echo The bot is not installed yet. Run install.bat first.
  timeout /t 10
  exit /b
)
echo Checking...
"C:\SignalCopier\venv\Scripts\python.exe" "C:\SignalCopier\app\backend\check.py"
start "" notepad.exe "C:\SignalCopier\check-report.txt"
