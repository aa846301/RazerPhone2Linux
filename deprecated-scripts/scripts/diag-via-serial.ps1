param([string]$Port = "COM4", [int]$BaudRate = 115200)

$sp = New-Object System.IO.Ports.SerialPort($Port, $BaudRate, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$sp.ReadTimeout  = 4000
$sp.WriteTimeout = 2000
$sp.Open()

function Cmd {
    param([string]$c, [int]$ms = 3000)
    $sp.WriteLine($c)
    Start-Sleep -Milliseconds $ms
    # Drain with bounded read
    $out = $sp.ReadExisting()
    # Give one more short read to catch tail
    Start-Sleep -Milliseconds 500
    $out += $sp.ReadExisting()
    Write-Host $out
}

# flush any pending data
$sp.ReadExisting() | Out-Null
# get a clean prompt
$sp.WriteLine("")
Start-Sleep -Milliseconds 800
$sp.ReadExisting() | Out-Null

Write-Host "`n=== FAILED UNITS ===" -ForegroundColor Cyan
Cmd "systemctl list-units --state=failed --no-pager 2>&1 | head -40"

Write-Host "`n=== JOURNAL ERRORS ===" -ForegroundColor Cyan
Cmd "journalctl -b -p err --no-pager -n 25 2>&1" 4000

Write-Host "`n=== DISPLAY / DRM ===" -ForegroundColor Cyan
Cmd "ls /dev/dri/ 2>&1; for f in /sys/class/drm/card0-*/status; do echo `"`$f:`$(cat `$f 2>/dev/null)`"; done"

Write-Host "`n=== NETWORK ===" -ForegroundColor Cyan
Cmd "ip -brief link 2>&1; iw dev 2>/dev/null | grep -E 'Interface|type|ssid'"

Write-Host "`n=== KLIPPER SERVICES ===" -ForegroundColor Cyan
Cmd "for s in klipper moonraker klipperscreen; do echo `"`$s: `$(systemctl is-active `$s 2>&1)`"; done"

Write-Host "`n=== DISK SPACE ===" -ForegroundColor Cyan
Cmd "df -h / 2>&1"

Write-Host "`n=== MODULES ===" -ForegroundColor Cyan
Cmd "lsmod 2>&1 | head -30"

$sp.Close()
Write-Host "`n=== DONE ===" -ForegroundColor Green
