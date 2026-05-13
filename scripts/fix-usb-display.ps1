param(
    [string]$Port = "COM5",
    [int]$BaudRate = 115200
)
# Fix USB gadget (remove RNDIS), unbind fbcon, check WiFi via serial

$serial = $null
try {
    $serial = New-Object System.IO.Ports.SerialPort($Port, $BaudRate,
        [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
    $serial.ReadTimeout  = 5000
    $serial.WriteTimeout = 3000
    $serial.NewLine      = "`n"
    $serial.Encoding     = [System.Text.Encoding]::ASCII
    $serial.Open()
    Write-Host "Connected to $Port" -ForegroundColor Green
} catch {
    Write-Host "Cannot open ${Port}: $_" -ForegroundColor Red
    exit 1
}

function Send-Cmd {
    param([string]$Cmd, [int]$WaitMs = 2000)
    $serial.WriteLine($Cmd)
    Start-Sleep -Milliseconds $WaitMs
    $buf = ""
    try {
        $deadline = [DateTime]::Now.AddMilliseconds($WaitMs)
        while ([DateTime]::Now -lt $deadline) {
            if ($serial.BytesToRead -gt 0) {
                $buf += $serial.ReadExisting()
            }
            Start-Sleep -Milliseconds 80
        }
    } catch {}
    return $buf
}

# Wake shell
$null = Send-Cmd "" 600

Write-Host "`n[1/4] Fixing USB gadget - removing RNDIS function..." -ForegroundColor Yellow

# The fix script to run on device as root
$fixScript = @'
set -e
G=/sys/kernel/config/usb_gadget/g1

echo "--- Current functions ---"
ls $G/functions/ 2>/dev/null

# Step 1: Detach UDC
echo "" > $G/UDC 2>/dev/null || true
sleep 0.5

# Step 2: Remove RNDIS symlink from config
rm -f $G/configs/c.1/rndis.usb0 2>/dev/null || true

# Step 3: Remove RNDIS function directory
rmdir $G/functions/rndis.usb0 2>/dev/null || true

echo "--- Functions after fix ---"
ls $G/functions/

# Step 4: Rebind UDC
UDC=$(ls /sys/class/udc | head -n1)
echo "$UDC" > $G/UDC
echo "Rebound to $UDC"

echo "--- Config links ---"
ls $G/configs/c.1/
echo "USB_GADGET_FIXED"
'@

$out = Send-Cmd "echo klipper | sudo -S bash -c '$fixScript'" 8000
Write-Host $out

if ($out -match "USB_GADGET_FIXED") {
    Write-Host "[USB gadget fixed]" -ForegroundColor Green
} else {
    Write-Host "[WARNING: USB fix may not have completed]" -ForegroundColor Yellow
}

Write-Host "`n[2/4] Persisting fix - updating usb-gadget script on device..." -ForegroundColor Yellow

# Also update the script on device so it persists after reboot
$patchScript = @'
SCRIPT=/usr/local/bin/usb-gadget-setup.sh
if [ -f "$SCRIPT" ]; then
    # Remove RNDIS lines from the script
    sed -i '/rndis/Id' "$SCRIPT"
    echo "Script patched: RNDIS removed"
    grep -i rndis "$SCRIPT" && echo "WARNING: rndis still present" || echo "RNDIS lines removed OK"
else
    echo "Script not found at $SCRIPT, checking alternatives..."
    find /usr/local/bin /etc/gadget -name "*.sh" 2>/dev/null | xargs grep -l rndis 2>/dev/null || echo "No other scripts found"
fi
'@

$out2 = Send-Cmd "echo klipper | sudo -S bash -c '$patchScript'" 4000
Write-Host $out2

Write-Host "`n[3/4] Unbinding fbcon (fix garbled display)..." -ForegroundColor Yellow

$displayFix = @'
echo 0 > /sys/class/vtconsole/vtcon0/bind 2>/dev/null
echo "vtcon0 bind now: $(cat /sys/class/vtconsole/vtcon0/bind)"
# Restart HelixScreen if running
systemctl restart helixscreen 2>/dev/null || true
echo "DISPLAY_FIX_DONE"
'@

$out3 = Send-Cmd "echo klipper | sudo -S bash -c '$displayFix'" 5000
Write-Host $out3

Write-Host "`n[4/4] Checking WiFi status..." -ForegroundColor Yellow

$wifiCheck = @'
echo "=== ath10k modules ==="
lsmod | grep ath10k
echo "=== MPSS remoteproc ==="
cat /sys/bus/platform/devices/4080000.remoteproc/state 2>/dev/null || echo NO_MPSS
echo "=== ath10k dmesg ==="
dmesg | grep -iE 'ath10k|wcss|mpss|remoteproc' | tail -15
echo "=== wlan0 ==="
ip link show wlan0 2>/dev/null || echo NO_WLAN0
echo "WIFI_CHECK_DONE"
'@

$out4 = Send-Cmd "echo klipper | sudo -S bash -c '$wifiCheck'" 6000
Write-Host $out4

$serial.Close()

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "1. USB: RNDIS removed from gadget, rebound to UDC"
Write-Host "   -> Replug USB cable, Windows should now install UsbNcm correctly"
Write-Host "2. Display: fbcon unbound from vtcon0, HelixScreen restarted"
Write-Host "3. WiFi: check output above"
Write-Host ""
Write-Host "Next: Replug USB cable on Windows side, wait ~5 seconds, then:" -ForegroundColor Yellow
Write-Host '  $key = "$env:USERPROFILE\.ssh\razer-phone"'
Write-Host '  ssh -i $key klipper@192.168.137.133'
