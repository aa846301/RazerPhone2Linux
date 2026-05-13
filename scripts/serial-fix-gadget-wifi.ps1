param(
    [string]$Port = "COM3",
    [string]$Pass = "klipper"
)
$sp = [System.IO.Ports.SerialPort]::new($Port, 115200)
$sp.ReadTimeout = 10000; $sp.Open()
Start-Sleep -Milliseconds 500; $sp.ReadExisting() | Out-Null

function Cmd([string]$c, [int]$ms=4000) {
    $sp.WriteLine($c); Start-Sleep -Milliseconds $ms
    $o = ""; try { $o = $sp.ReadExisting() } catch {}
    if ($o) { Write-Host $o }; return $o
}
function S([string]$c, [int]$ms=5000) { Cmd "echo $Pass | sudo -S bash -c '$c'" $ms }

# ── Fix 1: composite gadget (ACM + NCM) ─────────────────────────────────────
Write-Host "`n[1] Fixing USB gadget to composite (ACM+NCM)..." -ForegroundColor Yellow
$gadgetFix = @'
G=/sys/kernel/config/usb_gadget/g1
echo "" > "$G/UDC" 2>/dev/null || true; sleep 0.5
# Fix bDeviceClass for composite (multi-function)
echo 0xEF > "$G/bDeviceClass"
echo 0x02 > "$G/bDeviceSubClass"
echo 0x01 > "$G/bDeviceProtocol"
echo 0xa4a7 > "$G/idProduct"
echo "ACM serial + NCM ethernet" > "$G/configs/c.1/strings/0x409/configuration"
echo 250 > "$G/configs/c.1/MaxPower"
# Ensure NCM function exists
mkdir -p "$G/functions/ncm.usb0" 2>/dev/null || true
echo "02:de:ad:be:ef:02" > "$G/functions/ncm.usb0/host_addr" 2>/dev/null || true
echo "02:de:ad:be:ef:01" > "$G/functions/ncm.usb0/dev_addr" 2>/dev/null || true
ln -sf "$G/functions/ncm.usb0" "$G/configs/c.1/ncm.usb0" 2>/dev/null || true
sleep 0.3
echo "a600000.usb" > "$G/UDC"
sleep 1
echo "=== Gadget state ==="
echo "bDeviceClass: $(cat $G/bDeviceClass)"
echo "idProduct: $(cat $G/idProduct)"
echo "Functions:"; ls "$G/functions/"
echo "UDC: $(cat $G/UDC)"
'@
$gadgetFix = $gadgetFix -replace "'", "'\\''"; S $gadgetFix 8000

# ── Fix 2: Update usb-gadget-setup.sh to NCM version ───────────────────────
Write-Host "`n[2] Updating usb-gadget-setup.sh to ACM+NCM..." -ForegroundColor Yellow
$newScript = @'
#!/bin/bash
# USB composite gadget: ACM serial console + NCM ethernet
log() { echo "usb-gadget: $*" > /dev/kmsg 2>/dev/null || true; }

UDC=""
for _ in $(seq 1 30); do
    UDC=$(ls /sys/class/udc 2>/dev/null | head -n 1 || true)
    [ -n "$UDC" ] && break; sleep 0.2
done
[ -z "$UDC" ] && { log "no UDC"; exit 0; }
log "UDC: $UDC"
mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config 2>/dev/null || true
G=/sys/kernel/config/usb_gadget/g1
if [ -d "$G" ]; then
    echo "" > "$G/UDC" 2>/dev/null || true
    find "$G/configs" -type l -delete 2>/dev/null || true
    find "$G/functions" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | while read -r fn; do rmdir "$fn" 2>/dev/null || true; done
fi
mkdir -p "$G/strings/0x409" "$G/configs/c.1/strings/0x409"
echo 0x0525 > "$G/idVendor"; echo 0xa4a7 > "$G/idProduct"
echo 0x0200 > "$G/bcdUSB"; echo 0x0100 > "$G/bcdDevice"
echo 0xEF > "$G/bDeviceClass"; echo 0x02 > "$G/bDeviceSubClass"; echo 0x01 > "$G/bDeviceProtocol"
echo "Razer" > "$G/strings/0x409/manufacturer"
echo "Razer Phone 2 Linux" > "$G/strings/0x409/product"
echo "aura-linux" > "$G/strings/0x409/serialnumber"
echo "ACM serial + NCM ethernet" > "$G/configs/c.1/strings/0x409/configuration"
echo 250 > "$G/configs/c.1/MaxPower"
mkdir -p "$G/functions/acm.usb0"
ln -sf "$G/functions/acm.usb0" "$G/configs/c.1/acm.usb0" 2>/dev/null || true
mkdir -p "$G/functions/ncm.usb0" && {
    echo "02:de:ad:be:ef:02" > "$G/functions/ncm.usb0/host_addr" 2>/dev/null || true
    echo "02:de:ad:be:ef:01" > "$G/functions/ncm.usb0/dev_addr" 2>/dev/null || true
    ln -sf "$G/functions/ncm.usb0" "$G/configs/c.1/ncm.usb0" 2>/dev/null || true
}
echo "$UDC" > "$G/UDC" 2>/dev/null && log "composite gadget bound to $UDC" || log "UDC bind failed"
'@
$newScript = $newScript -replace '"', '\"'
# Write via heredoc
$encoded = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($newScript))
S "echo '$encoded' | base64 -d > /usr/local/bin/usb-gadget-setup.sh && chmod 755 /usr/local/bin/usb-gadget-setup.sh && echo SCRIPT_UPDATED" 5000

# ── Fix 3: Check WiFi modules in /lib/modules ────────────────────────────────
Write-Host "`n[3] Checking WiFi modules install..." -ForegroundColor Yellow
S 'ls /lib/modules/ 2>/dev/null; find /lib/modules -name "ath10k*" 2>/dev/null | head -5 || echo NO_ATH10K_KO' 3000

# ── Fix 4: Bring up usb0 network ─────────────────────────────────────────────
Write-Host "`n[4] Bringing up usb0 (NCM network interface)..." -ForegroundColor Yellow
Start-Sleep -Milliseconds 3000
S 'ip link set usb0 up 2>/dev/null && ip addr add 192.168.137.2/24 dev usb0 2>/dev/null || true; ip -brief addr show usb0 2>/dev/null || echo NO_USB0' 4000

Write-Host "`n[Done]" -ForegroundColor Green
Cmd "ls /sys/kernel/config/usb_gadget/g1/functions/; ip -brief link | grep usb" 3000

$sp.Close()
