param(
    [string]$Port = "COM3",
    [string]$Pass = "klipper"
)
$sp = [System.IO.Ports.SerialPort]::new($Port, 115200)
$sp.ReadTimeout = 8000; $sp.Open()
Start-Sleep -Milliseconds 500; $sp.ReadExisting() | Out-Null

function Cmd([string]$c, [int]$ms=4000) {
    $sp.WriteLine($c); Start-Sleep -Milliseconds $ms
    $o = ""; try { $o = $sp.ReadExisting() } catch {}
    if ($o) { Write-Host $o }; return $o
}
function S([string]$c, [int]$ms=5000) { Cmd "echo $Pass | sudo -S bash -c '$c'" $ms }

# 1. usb-gadget-setup.sh 內容
Write-Host "`n=== usb-gadget-setup.sh ===" -ForegroundColor Cyan
Cmd "cat /usr/local/bin/usb-gadget-setup.sh" 3000

# 2. WiFi kernel config
Write-Host "`n=== WiFi kernel config ===" -ForegroundColor Cyan
S 'zcat /proc/config.gz 2>/dev/null | grep -E "ATH10K|WCN|QCOM_WIFI|MAC80211"' 3000

# 3. Deploy NCM gadget script + add NCM function
Write-Host "`n=== Adding NCM to running gadget ===" -ForegroundColor Yellow
$ncmScript = @'
G=/sys/kernel/config/usb_gadget/g1
if [ -d "$G/functions/ncm.usb0" ]; then echo NCM_ALREADY; exit 0; fi
# Detach UDC first
echo "" > "$G/UDC" 2>/dev/null || true; sleep 0.3
# Create NCM function
mkdir -p "$G/functions/ncm.usb0"
echo "02:de:ad:be:ef:02" > "$G/functions/ncm.usb0/host_addr" 2>/dev/null || true
echo "02:de:ad:be:ef:01" > "$G/functions/ncm.usb0/dev_addr" 2>/dev/null || true
ln -sf "$G/functions/ncm.usb0" "$G/configs/c.1/ncm.usb0" 2>/dev/null || true
sleep 0.2
# Re-attach UDC
echo "a600000.usb" > "$G/UDC" 2>/dev/null || true
sleep 1
echo "Functions now:"; ls "$G/functions/"
echo "UDC:"; cat "$G/UDC"
'@
$ncmScript = $ncmScript -replace "'", "'\\''"; S $ncmScript 6000

# 4. Bring up usb0 network interface
Write-Host "`n=== Bringing up usb0 ===" -ForegroundColor Yellow
S 'ip link set usb0 up 2>/dev/null; ip addr add 192.168.137.2/24 dev usb0 2>/dev/null || true; ip -brief addr show usb0 2>/dev/null || echo NO_USB0' 3000

# 5. Summary
Write-Host "`n=== Final state ===" -ForegroundColor Green
Cmd "ls /sys/kernel/config/usb_gadget/g1/functions/; ip -brief link" 3000

$sp.Close()
Write-Host "`nDone. Check Windows Device Manager for UsbNcm." -ForegroundColor Green
