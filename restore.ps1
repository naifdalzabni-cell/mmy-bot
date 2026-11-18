# Restore a backup file made by backup.bat (on the same or a new VPS)
$Dest = "C:\SignalCopier"
$Py = "$Dest\venv\Scripts\python.exe"
$TaskName = "SignalCopierBot"
Add-Type -AssemblyName System.Windows.Forms
function Popup($ar) { [System.Windows.Forms.MessageBox]::Show($ar, "Signal Copier", "OK", "Information", "Button1", "RtlReading") | Out-Null }
function Ask($ar) { return [System.Windows.Forms.MessageBox]::Show($ar, "Signal Copier", "YesNo", "Warning", "Button2", "RtlReading") -eq "Yes" }

if (-not (Test-Path $Py) -or -not (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
    Popup "البوت غير مثبت على هذا الجهاز. شغّل install.bat أولاً، ثم استرجع النسخة."; exit 1
}
$file = $args[0]
if (-not $file) {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "اختر ملف النسخة الاحتياطية"
    $dlg.Filter = "SignalCopier backup (*.json)|*.json"
    $dlg.InitialDirectory = [Environment]::GetFolderPath("Desktop")
    if ($dlg.ShowDialog() -ne "OK") { exit 0 }
    $file = $dlg.FileName
}
if (-not (Ask "سيتم استبدال إعدادات البوت الحالية بإعدادات هذا الملف:`n$([IO.Path]::GetFileName($file))`n`nالصفقات الموجودة لن تُحذف.`nهل تريد المتابعة؟")) { exit 0 }

Write-Host "Stopping the bot..."
Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
Get-CimInstance Win32_Process -Filter "Name='pythonw.exe'" | Where-Object { $_.CommandLine -like "*SignalCopier*" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep -Seconds 2
Start-Service MongoDB -ErrorAction SilentlyContinue

# safety copy of the current settings first
New-Item -ItemType Directory -Force -Path "$Dest\backups" | Out-Null
& $Py "$Dest\app\backend\backup.py" export "$Dest\backups\before-restore-$(Get-Date -Format 'yyyy-MM-dd_HH-mm').json" | Out-Null

Write-Host "Restoring..."
$out = (& $Py "$Dest\app\backend\backup.py" import $file) -join " "
$code = $LASTEXITCODE
schtasks /run /tn $TaskName | Out-Null
if ($code -eq 3) { Popup "هذا الملف ليس نسخة احتياطية من البوت، أو أنه تالف. لم يتغيّر شيء."; exit 1 }
if ($code -ne 0) { Popup "تعذّر الاسترجاع: قاعدة البيانات لا تعمل. شغّل check.bat لمعرفة السبب."; exit 1 }

$ok = $false
for ($i = 0; $i -lt 45; $i++) {
    try { Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:8001/api/" -TimeoutSec 3 | Out-Null; $ok = $true; break } catch { Start-Sleep -Seconds 2 }
}
if (-not $ok) { Popup "تم استرجاع الإعدادات، لكن البوت لم يبدأ. شغّل check.bat لمعرفة السبب."; exit 1 }
Start-Process "http://localhost:8001"
Popup ("تم الاسترجاع ✓`n`nربط تيليجرام والقنوات والـ SSID والإعدادات رجعت كلها.`n`n" +
    "مهم: أوقفت الاستماع للأمان. أوقف البوت في الجهاز القديم أولاً (stop.bat)، ثم اضغط «بدء الاستماع» في لوحة التحكم هنا، حتى لا تُفتح كل صفقة مرتين.")
