# One-click update: keeps settings (database + .env), rolls back automatically if the new version fails
$ErrorActionPreference = "Continue"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ProgressPreference = "SilentlyContinue"
$Dest = "C:\SignalCopier"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$TaskName = "SignalCopierBot"
$Py = "$Dest\venv\Scripts\python.exe"
$Tmp = Join-Path $env:TEMP "SignalCopierUpdate"
Add-Type -AssemblyName System.Windows.Forms

function Step($msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Popup($ar) { [System.Windows.Forms.MessageBox]::Show($ar, "Signal Copier", "OK", "Information", "Button1", "RtlReading") | Out-Null }
function Done($ar, $code) { Popup $ar; exit $code }
function Ver($s) { try { return [version]($s.Trim()) } catch { return [version]"0.0.0" } }
function StopBot() {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Get-CimInstance Win32_Process -Filter "Name='pythonw.exe' OR Name='python.exe'" | Where-Object { $_.CommandLine -like "*SignalCopier*app*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 3
}
function StartAndWait() {
    Start-Service MongoDB -ErrorAction SilentlyContinue
    schtasks /change /tn $TaskName /enable | Out-Null
    schtasks /run /tn $TaskName | Out-Null
    for ($i = 0; $i -lt 45; $i++) {
        try { Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:8001/api/" -TimeoutSec 3 | Out-Null; return $true } catch { Start-Sleep -Seconds 2 }
    }
    return $false
}
function OpenDash() {
    $lnk = "[InternetShortcut]`r`nURL=http://localhost:8001`r`n"
    foreach ($d in @("$env:PUBLIC\Desktop", [Environment]::GetFolderPath("Desktop"))) {
        try { [System.IO.File]::WriteAllText("$d\Signal Copier.url", $lnk) } catch {}
    }
    try { Start-Process "http://localhost:8001" -ErrorAction Stop } catch {
        try { Start-Process "msedge.exe" "http://localhost:8001" -ErrorAction Stop } catch {}
    }
}

if (-not (Test-Path $Py) -or -not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
    Done "البوت غير مثبت بعد. شغّل install.bat أولاً." 1
}
$current = Ver ((Get-Content "$Dest\version.txt" -ErrorAction SilentlyContinue) -join "")
Write-Host "Installed version: $current"

# ---------- 1. Get the new package (zip next to this file, or download) ----------
Step "Getting the new version"
if (Test-Path $Tmp) { Remove-Item -Recurse -Force $Tmp }
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null
$zip = Get-ChildItem -Path $Here -Filter "SignalCopier*.zip" -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$fromFolder = ($Here.TrimEnd("\") -ne $Dest) -and (Test-Path "$Here\app\backend\server.py")
$local = $fromFolder -or [bool]$zip
if ($fromFolder) {
    Write-Host "Using the extracted folder $Here"
    $NewRoot = $Here
} elseif ($zip) {
    $zipPath = $zip.FullName
    Write-Host "Using $zipPath"
} else {
    $url = ((Get-Content "$Dest\update-url.txt" -ErrorAction SilentlyContinue) -join "").Trim()
    if (-not $url) { Done "لا يوجد رابط تحديث. ضع ملف التحديث SignalCopier-Windows.zip بجانب update.bat ثم شغّله مرة أخرى." 1 }
    $zipPath = "$Tmp\update.zip"
    try { Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zipPath } catch {}
    if (-not (Test-Path $zipPath)) {
        Done "تعذّر تنزيل التحديث. تأكد من الإنترنت، أو نزّل ملف SignalCopier-Windows.zip وضعه بجانب update.bat ثم شغّله مرة أخرى." 1
    }
}
if (-not $fromFolder) {
    try { Expand-Archive -Path $zipPath -DestinationPath "$Tmp\x" -Force } catch {
        Done "ملف التحديث تالف. نزّله مرة أخرى." 1
    }
    $NewRoot = Get-ChildItem -Path "$Tmp\x" -Recurse -Filter "install.ps1" | Select-Object -First 1 | ForEach-Object { $_.DirectoryName }
}
if (-not $NewRoot -or -not (Test-Path "$NewRoot\app\backend\server.py")) { Done "ملف التحديث ليس حزمة SignalCopier صحيحة." 1 }
$latest = Ver ((Get-Content "$NewRoot\version.txt" -ErrorAction SilentlyContinue) -join "")
Write-Host "New version: $latest"
if ($latest -le $current) {
    if (StartAndWait) {
        OpenDash
        Done "عندك آخر نسخة ($current) ✓ والبوت يعمل.`n`nفتحت لك لوحة التحكم، وأيقونة «Signal Copier» على سطح المكتب." 0
    }
    & $Py "$Dest\app\backend\check.py" | Out-Null
    Start-Process notepad.exe "$Dest\check-report.txt"
    Done "عندك آخر نسخة ($current) لكن البوت لا يعمل الآن. فتحت لك ملف التقرير وفيه السبب والحل." 1
}

# ---------- 2. Back up, replace files (keep .env), install packages ----------
Step "Updating $current -> $latest (your settings are kept)"
StopBot
$Bak = "$Dest\backup"
if (Test-Path $Bak) { Remove-Item -Recurse -Force $Bak }
New-Item -ItemType Directory -Force -Path $Bak | Out-Null
Copy-Item -Recurse -Force "$Dest\app" "$Bak\app"
Get-ChildItem -Path $Dest -File | Where-Object { $_.Extension -in ".bat", ".ps1", ".txt" -and $_.Name -notin "check-report.txt" } | Copy-Item -Destination $Bak -Force

$envBackup = Get-Content -Raw "$Dest\app\backend\.env" -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force "$Dest\app"
Copy-Item -Recurse -Force "$NewRoot\app" "$Dest\app"
if ($envBackup) { [System.IO.File]::WriteAllText("$Dest\app\backend\.env", $envBackup, (New-Object System.Text.UTF8Encoding $false)) }
$urlKeep = Get-Content -Raw "$Dest\update-url.txt" -ErrorAction SilentlyContinue
Get-ChildItem -Path $NewRoot -File | Where-Object { $_.Extension -in ".bat", ".ps1", ".txt" -and $_.Name -ne "update.ps1" } | Copy-Item -Destination $Dest -Force
if ($urlKeep -and -not (Get-Content -Raw "$Dest\update-url.txt" -ErrorAction SilentlyContinue)) { Set-Content "$Dest\update-url.txt" $urlKeep }

& $Py -m pip install -r "$Dest\requirements-windows.txt" --quiet --disable-pip-version-check
$pipOk = ($LASTEXITCODE -eq 0)

# ---------- 3. Start; roll back if it does not come up ----------
Step "Starting the new version"
if ($pipOk -and (StartAndWait)) {
    Copy-Item -Force "$NewRoot\update.ps1" "$Dest\update.ps1" -ErrorAction SilentlyContinue
    Add-Content -Path "$Dest\bot.log" -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - updater - INFO - تم التحديث من $current إلى $latest" -Encoding UTF8
    OpenDash
    Done "تم التحديث بنجاح ✓`n`nالنسخة الآن: $latest`nكل إعداداتك وربط تيليجرام وPocket Option كما هي." 0
}
Write-Host "New version failed - restoring the previous one" -ForegroundColor Yellow
StopBot
Remove-Item -Recurse -Force "$Dest\app"
Copy-Item -Recurse -Force "$Bak\app" "$Dest\app"
Get-ChildItem -Path $Bak -File | Copy-Item -Destination $Dest -Force
& $Py -m pip install -r "$Dest\requirements-windows.txt" --quiet --disable-pip-version-check
$back = StartAndWait
Add-Content -Path "$Dest\bot.log" -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - updater - ERROR - فشل التحديث إلى $latest وتم الرجوع إلى $current" -Encoding UTF8
if ($back) { Done "التحديث لم ينجح، فرجّعت النسخة السابقة ($current) والبوت يعمل الآن كالعادة ✓`n`nأرسل ملف bot.log إلى الدعم." 1 }
& $Py "$Dest\app\backend\check.py" | Out-Null
Start-Process notepad.exe "$Dest\check-report.txt"
Done "التحديث لم ينجح، والبوت لم يبدأ بعد الرجوع للنسخة السابقة. فتحت لك ملف التقرير وفيه السبب والحل." 1
