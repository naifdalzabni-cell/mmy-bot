# Start the bot and confirm it answers; otherwise show the Arabic check report
$Dest = "C:\SignalCopier"
Add-Type -AssemblyName System.Windows.Forms
function Popup($ar) { [System.Windows.Forms.MessageBox]::Show($ar, "Signal Copier", "OK", "Information", "Button1", "RtlReading") | Out-Null }

if (-not (Get-ScheduledTask -TaskName SignalCopierBot -ErrorAction SilentlyContinue)) {
    Popup "البوت غير مثبت بعد. شغّل install.bat أولاً."; exit 1
}
Start-Service MongoDB -ErrorAction SilentlyContinue
schtasks /change /tn SignalCopierBot /enable | Out-Null
schtasks /run /tn SignalCopierBot | Out-Null
Write-Host "Starting the bot..."
for ($i = 0; $i -lt 45; $i++) {
    try {
        Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:8001/api/" -TimeoutSec 3 | Out-Null
        $lnk = "[InternetShortcut]`r`nURL=http://localhost:8001`r`n"
        foreach ($d in @("$env:PUBLIC\Desktop", [Environment]::GetFolderPath("Desktop"))) {
            try { [System.IO.File]::WriteAllText("$d\Signal Copier.url", $lnk) } catch {}
        }
        try { Start-Process "http://localhost:8001" -ErrorAction Stop } catch {
            try { Start-Process "msedge.exe" "http://localhost:8001" -ErrorAction Stop } catch {}
        }
        Popup "البوت يعمل ✓`n`nلوحة التحكم: http://localhost:8001"
        exit 0
    } catch { Start-Sleep -Seconds 2 }
}
& "$Dest\venv\Scripts\python.exe" "$Dest\app\backend\check.py" | Out-Null
Start-Process notepad.exe "$Dest\check-report.txt"
Popup "البوت لم يبدأ. فتحت لك ملف التقرير، وفيه السبب وطريقة الحل."
exit 1
