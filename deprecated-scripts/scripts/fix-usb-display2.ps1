param(
    [string]$Port = "COM5",
    [int]$BaudRate = 115200
)

$serial = $null
try {
    $serial = New-Object System.IO.Ports.SerialPort($Port, $BaudRate,
        [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
    $serial.ReadTimeout  = 500
    $serial.WriteTimeout = 3000
    $serial.NewLine      = "`n"
    $serial.Encoding     = [System.Text.Encoding]::ASCII
    $serial.Open()
    Write-Host "Connected to $Port" -ForegroundColor Green
} catch {
    Write-Host "Cannot open ${Port}: $_" -ForegroundColor Red
    exit 1
}

function Read-Available {
    param([int]$WaitMs = 1500)
    Start-Sleep -Milliseconds $WaitMs
    $buf = ""
    $deadline = [DateTime]::Now.AddMilliseconds(500)
    while ([DateTime]::Now -lt $deadline) {
        try {
            if ($serial.BytesToRead -gt 0) {
                $buf += $serial.ReadExisting()
                $deadline = [DateTime]::Now.AddMilliseconds(300)
            }
        } catch { break }
        Start-Sleep -Milliseconds 50
    }
    return $buf
}

function Send-Line {
    param([string]$Line)
    try {
        $serial.WriteLine($Line)
    } catch {
        Write-Host "Port error: $_" -ForegroundColor Red
        return ""
    }
    return Read-Available
}

# Wake terminal
$null = Send-Line ""
$null = Send-Line ""

Write-Host "=== Step 1: Elevate to root ===" -ForegroundColor Cyan
$out = Send-Line "sudo -S bash"
Write-Host $out
if ($out -match "password|Password") {
    $out = Send-Line "klipper"
    Write-Host $out
}
Start-Sleep -Milliseconds 500

Write-Host "=== Step 2: Fix USB gadget (remove RNDIS) ===" -ForegroundColor Cyan
$cmds = @(
    "G=/sys/kernel/config/usb_gadget/g1",
    'echo "Functions before:"; ls $G/functions/ 2>/dev/null',
    'echo "" > $G/UDC 2>/dev/null; sleep 0.5; echo UDC_DETACHED',
    'rm -f $G/configs/c.1/rndis.usb0 2>/dev/null; echo RNDIS_SYMLINK_REMOVED',
    'rmdir $G/functions/rndis.usb0 2>/dev/null; echo RNDIS_FUNC_REMOVED',
    'echo "Functions after:"; ls $G/functions/',
    'UDC=$(ls /sys/class/udc | head -n1); echo "$UDC" > $G/UDC; echo "Rebound to $UDC"',
    'echo "Config links:"; ls $G/configs/c.1/'
)
foreach ($cmd in $cmds) {
    $out = Send-Line $cmd
    Write-Host $out.Trim()
}

Write-Host "`n=== Step 3: Persist RNDIS removal ===" -ForegroundColor Cyan
$out = Send-Line 'SCRIPT=$(find /usr/local/bin /etc -name "usb-gadget*" 2>/dev/null | head -1); echo "Script: $SCRIPT"'
Write-Host $out.Trim()
$out = Send-Line 'if [ -n "$SCRIPT" ]; then sed -i "/rndis/Id" "$SCRIPT"; echo PATCHED; grep -i rndis "$SCRIPT" && echo RNDIS_STILL_THERE || echo RNDIS_GONE; fi'
Write-Host $out.Trim()

Write-Host "`n=== Step 4: Unbind fbcon ===" -ForegroundColor Cyan
$out = Send-Line 'echo 0 > /sys/class/vtconsole/vtcon0/bind 2>/dev/null; echo "vtcon0 bind: $(cat /sys/class/vtconsole/vtcon0/bind)"'
Write-Host $out.Trim()
$out = Send-Line 'systemctl restart helixscreen 2>/dev/null && echo HELIX_RESTARTED || echo HELIX_NOT_FOUND'
Write-Host $out.Trim()

Write-Host "`n=== Step 5: WiFi check ===" -ForegroundColor Cyan
$out = Send-Line 'dmesg | grep -iE "ath10k_snoc|wcss.*start|mpss.*start|remoteproc.*start" | tail -10'
Write-Host $out.Trim()
$out = Send-Line 'ip link show wlan0 2>/dev/null || echo NO_WLAN0'
Write-Host $out.Trim()
$out = Send-Line 'ls /sys/bus/platform/devices/18800000.wifi/driver 2>/dev/null && echo WIFI_BOUND || echo WIFI_UNBOUND'
Write-Host $out.Trim()

Write-Host "`n=== Step 6: Check backlight ===" -ForegroundColor Cyan
$out = Send-Line 'ls /sys/class/backlight/ 2>/dev/null || echo NO_BACKLIGHT'
Write-Host $out.Trim()

$serial.Close()
Write-Host "`nDone. Now replug USB cable on PC." -ForegroundColor Green
