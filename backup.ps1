# Save all bot settings + history into one file (Desktop + C:\SignalCopier\backups)
$Dest = "C:\SignalCopier"
$Py = "$Dest\venv\Scripts\python.exe"
Add-Type -AssemblyName System.Windows.Forms
function Popup($ar) { [System.Windows.Forms.MessageBox]::Show($ar, "Signal Copier", "OK", "Information", "Button1", "RtlReading") | Out-Null }

if (-not (Test-Path $Py)) { Popup "البوت غير مثبت بعد. شغّل install.bat أولاً."; exit 1 }
Start-Service MongoDB -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path "$Dest\backups" | Out-Null
$name = "SignalCopier-backup-" + (Get-Date -Format "yyyy-MM-dd_HH-mm") + ".json"
$file = "$Dest\backups\$name"
$env:PYTHONIOENCODING = "utf-8"
$out = (& $Py "$Dest\app\backend\backup.py" export $file) -join " "
if ($LASTEXITCODE -ne 0) {
    Popup "تعذّر حفظ النسخة الاحتياطية: قاعدة البيانات لا تعمل.`nشغّل check.bat لمعرفة السبب."
    exit 1
}
$desk = [Environment]::GetFolderPath("Desktop")
Copy-Item -Force $file "$desk\$name" -ErrorAction SilentlyContinue
$m = [regex]::Match($out, "trades=(\d+)")
Popup ("تم حفظ النسخة الاحتياطية ✓`n`nالملف على سطح المكتب:`n$name`n`n" +
    "فيها: ربط تيليجرام، القنوات، الـ SSID، كل الإعدادات، و$($m.Groups[1].Value) صفقة.`n`n" +
    "⚠ هذا الملف يفتح حسابك في تيليجرام وPocket Option. لا ترسله لأحد واحفظه في مكان آمن.")
