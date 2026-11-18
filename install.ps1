# Signal Copier - Windows installer (run via install.bat; needs Administrator)
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"
$Src = Split-Path -Parent $MyInvocation.MyCommand.Path
$Dest = "C:\SignalCopier"
$TaskName = "SignalCopierBot"
$Tmp = Join-Path $env:TEMP "SignalCopierSetup"
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
Add-Type -AssemblyName System.Windows.Forms

function Step($msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Popup($ar) { [System.Windows.Forms.MessageBox]::Show($ar, "Signal Copier", "OK", "Information", "Button1", "RtlReading") | Out-Null }
function Fail($en, $ar) {
    Write-Host ""; Write-Host "ERROR: $en" -ForegroundColor Red
    Popup $ar
    Read-Host "Press Enter to close"; exit 1
}
function Report() {
    if (Test-Path "$Dest\venv\Scripts\python.exe") { & "$Dest\venv\Scripts\python.exe" "$Dest\app\backend\check.py" | Out-Null }
    if (Test-Path "$Dest\check-report.txt") { Start-Process notepad.exe "$Dest\check-report.txt" }
}
function Download($url, $out) {
    for ($i = 0; $i -lt 3; $i++) {
        try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $out; if (Test-Path $out) { return $true } } catch { Start-Sleep -Seconds 3 }
    }
    return $false
}

# ---------- 1. Python 3.11 ----------
Step "Checking Python 3.11"
$py = "C:\Program Files\Python311\python.exe"
if (-not (Test-Path $py)) {
    $exe = "$Tmp\python-3.11.9-amd64.exe"
    Write-Host "Downloading Python 3.11 ..."
    if (-not (Download "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe" $exe)) {
        Fail "Could not download Python. Check the internet." "تعذّر تنزيل Python. تأكد من اتصال الـ VPS بالإنترنت ثم شغّل install.bat مرة أخرى."
    }
    Start-Process -Wait -FilePath $exe -ArgumentList '/quiet InstallAllUsers=1 PrependPath=1 Include_test=0 TargetDir="C:\Program Files\Python311"'
    if (-not (Test-Path $py)) { Fail "Python installation failed." "فشل تثبيت Python. أعد تشغيل الـ VPS ثم شغّل install.bat مرة أخرى." }
}
Write-Host "Python OK: $py"

# ---------- 2. MongoDB (database service) ----------
# 4.4 runs on every VPS CPU (newer versions need AVX, which many VPS do not expose)
Step "Checking MongoDB database"
function MongoRunning() { $s = Get-Service -Name MongoDB -ErrorAction SilentlyContinue; return ($s -and $s.Status -eq "Running") }
function TryStartMongo() {
    Set-Service -Name MongoDB -StartupType Automatic -ErrorAction SilentlyContinue
    Start-Service MongoDB -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 5
    return (MongoRunning)
}
$svc = Get-Service -Name MongoDB -ErrorAction SilentlyContinue
if ($svc -and -not (TryStartMongo)) {
    Write-Host "Installed MongoDB does not run on this VPS - replacing it with a compatible version" -ForegroundColor Yellow
    Stop-Service MongoDB -Force -ErrorAction SilentlyContinue
    sc.exe delete MongoDB | Out-Null
    Start-Sleep -Seconds 3
    $svc = $null
}
if (-not $svc) {
    $msi = "$Tmp\mongodb-4.4.29.msi"
    Write-Host "Downloading MongoDB 4.4 ..."
    if (-not (Download "https://fastdl.mongodb.org/windows/mongodb-windows-x86_64-4.4.29-signed.msi" $msi)) {
        Fail "Could not download MongoDB." "تعذّر تنزيل قاعدة البيانات MongoDB. تأكد من الإنترنت ثم شغّل install.bat مرة أخرى."
    }
    Start-Process -Wait msiexec.exe -ArgumentList "/i `"$msi`" /qn /l*v `"$Tmp\mongo-install.log`" ADDLOCAL=`"ServerService`" SHOULD_INSTALL_COMPASS=`"0`""
    Start-Sleep -Seconds 5
    if (-not (Get-Service -Name MongoDB -ErrorAction SilentlyContinue) -or -not (TryStartMongo)) {
        Fail "MongoDB did not start." "قاعدة البيانات MongoDB لم تعمل. أعد تشغيل الـ VPS ثم شغّل install.bat مرة أخرى."
    }
}
Write-Host "MongoDB OK (starts automatically with Windows)"

# ---------- 3. Copy the bot ----------
Step "Copying the bot to $Dest"
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) { Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' OR Name='python.exe'" | Where-Object { $_.CommandLine -like "*SignalCopier*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2
New-Item -ItemType Directory -Force -Path $Dest | Out-Null
if ($Src -ne $Dest) {
    if (Test-Path "$Dest\app") { Remove-Item -Recurse -Force "$Dest\app" }
    Copy-Item -Recurse -Force "$Src\app" "$Dest\app"
    Get-ChildItem -Path $Src -File | Where-Object { $_.Extension -in ".bat", ".ps1", ".txt" } | Copy-Item -Destination $Dest -Force
}
$envFile = @"
MONGO_URL=mongodb://127.0.0.1:27017
DB_NAME=signal_copier
CORS_ORIGINS=*
TG_DEFAULT_API_ID=2040
TG_DEFAULT_API_HASH=b18441a1ff607e10a989891a5462e627
SERVE_FRONTEND_DIR=$Dest\app\web
LOG_FILE=$Dest\bot.log
PYTHONUTF8=1
"@
[System.IO.File]::WriteAllText("$Dest\app\backend\.env", $envFile, (New-Object System.Text.UTF8Encoding $false))

# ---------- 4. Python packages ----------
Step "Installing Python packages (first time takes a few minutes)"
if (-not (Test-Path "$Dest\venv\Scripts\python.exe")) { & $py -m venv "$Dest\venv" }
$env:PYTHONUTF8 = "1"
& "$Dest\venv\Scripts\python.exe" -m pip install --upgrade pip --quiet --disable-pip-version-check
& "$Dest\venv\Scripts\python.exe" -m pip install -r "$Dest\requirements-windows.txt" --quiet --disable-pip-version-check
if ($LASTEXITCODE -ne 0) { Fail "Package installation failed." "فشل تثبيت البرامج المساعدة. تأكد من الإنترنت ثم شغّل install.bat مرة أخرى." }

# ---------- 5. Pre-flight check ----------
Step "Checking everything before starting"
& "$Dest\venv\Scripts\python.exe" "$Dest\app\backend\check.py"
if ($LASTEXITCODE -ne 0) {
    Start-Process notepad.exe "$Dest\check-report.txt"
    Fail "Pre-flight check found problems - see check-report.txt" "يوجد شيء ناقص. فتحت لك ملف التقرير، وفيه المشكلة وطريقة حلها."
}

# ---------- 6. Run in background, start with Windows, restart if it stops ----------
Step "Registering the bot to run in the background 24/7"
$action = New-ScheduledTaskAction -Execute "$Dest\venv\Scripts\pythonw.exe" -Argument "`"$Dest\app\backend\run.py`"" -WorkingDirectory "$Dest\app\backend"
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable `
    -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

# ---------- 7. Keep the PC awake ----------
powercfg /change standby-timeout-ac 0 2>$null
powercfg /change hibernate-timeout-ac 0 2>$null

# ---------- 8. Desktop shortcut ----------
$shortcut = "[InternetShortcut]`r`nURL=http://localhost:8001`r`n"
[System.IO.File]::WriteAllText("$env:PUBLIC\Desktop\Signal Copier.url", $shortcut)

Step "Waiting for the bot to start"
$ok = $false
for ($i = 0; $i -lt 60; $i++) {
    try { Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:8001/api/" -TimeoutSec 3 | Out-Null; $ok = $true; break } catch { Start-Sleep -Seconds 2 }
}
if (-not $ok) {
    Report
    Fail "The bot did not start - see check-report.txt" "البوت لم يبدأ. فتحت لك ملف التقرير check-report.txt وفيه السبب وطريقة الحل."
}

Write-Host ""
Write-Host "DONE! The bot is running in the background and starts automatically with Windows." -ForegroundColor Green
Write-Host "Dashboard: http://localhost:8001" -ForegroundColor Green
Start-Process "http://localhost:8001"
Popup "البوت يعمل الآن ✓`n`nلوحة التحكم: http://localhost:8001`nيشتغل وحده مع تشغيل الـ VPS."
