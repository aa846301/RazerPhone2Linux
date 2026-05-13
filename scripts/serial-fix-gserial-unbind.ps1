param([string]$Port = "COM3")

# ─── Fix USB NCM: unbind built-in g_serial, bind composite ACM+NCM ───────────
# Background: CONFIG_USB_G_SERIAL=y auto-binds to UDC at boot, preventing
# our configfs gadget (g1 = ACM+NCM) from binding.  Fix: unbind g_serial via
# /sys/bus/gadget/drivers/g_serial/unbind, then bind g1 immediately.
# Side effect: COM3 will briefly drop then reappear (ACM in g1).
# ─────────────────────────────────────────────────────────────────────────────

function OpenSerial($port) {
    $sp = New-Object System.IO.Ports.SerialPort $port, 115200
    $sp.ReadTimeout = 8000
    $sp.Open()
    Start-Sleep -Milliseconds 400
    $sp.ReadExisting() | Out-Null
    return $sp
}

function SendAndWait($sp, $cmd, $waitMs = 5000) {
    $sp.WriteLine($cmd)
    Start-Sleep -Milliseconds $waitMs
    return $sp.ReadExisting()
}

# ─────────────────────────────────────────────────────────────────────────────
# Step 1: Push updated usb-gadget-setup.sh to device via base64
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "[1] Encoding updated usb-gadget-setup-ncm.sh..."
$scriptSrc = Join-Path $PSScriptRoot "..\wsl-scripts\usb-gadget-setup-ncm.sh"
$scriptBytes = [System.IO.File]::ReadAllBytes((Resolve-Path $scriptSrc).Path)
$scriptB64 = [Convert]::ToBase64String($scriptBytes)

Write-Host "[2] Sending updated script to device via serial (base64)..."
$sp = OpenSerial $Port

# Send in chunks to avoid serial buffer overflow
$chunkSize = 512
$tmpFile = "/tmp/usb-gadget-new.b64"
$sp.WriteLine("sudo bash -c 'rm -f $tmpFile; true'")
Start-Sleep -Milliseconds 1000
$sp.ReadExisting() | Out-Null

$totalChunks = [math]::Ceiling($scriptB64.Length / $chunkSize)
for ($i = 0; $i -lt $scriptB64.Length; $i += $chunkSize) {
    $chunk = $scriptB64.Substring($i, [math]::Min($chunkSize, $scriptB64.Length - $i))
    $sp.WriteLine("printf '%s' '$chunk' >> $tmpFile")
    Start-Sleep -Milliseconds 200
    $sp.ReadExisting() | Out-Null
    $chunkNum = [math]::Floor($i / $chunkSize) + 1
    if ($chunkNum % 5 -eq 0) {
        Write-Host "  Chunk $chunkNum/$totalChunks sent..."
    }
}
Write-Host "  All $totalChunks chunks sent."

# Decode and install
$out = SendAndWait $sp "sudo bash -c 'base64 -d $tmpFile > /usr/local/bin/usb-gadget-setup.sh && chmod +x /usr/local/bin/usb-gadget-setup.sh && echo INSTALL_OK || echo INSTALL_FAIL'" 5000
Write-Host "  Install result: $out"

# ─────────────────────────────────────────────────────────────────────────────
# Step 3: Schedule the gadget switch via systemd-run
# (loses serial briefly when g_serial unbinds, comes back when ACM binds)
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[3] Scheduling gadget switch in 5s..."
Write-Host "    (COM3 will drop briefly then reappear as ACM in composite gadget)"

$switchCmd = @'
sudo bash -c "
  # Unbind legacy g_serial from UDC
  if [ -d /sys/bus/gadget/drivers/g_serial ]; then
    ls /sys/bus/gadget/drivers/g_serial/ | grep -vE '^(bind|unbind|module|uevent|new_id|remove_id)$' | while read dev; do
      echo \"\$dev\" > /sys/bus/gadget/drivers/g_serial/unbind 2>/dev/null
    done
    sleep 0.2
  fi
  # Bind composite ACM+NCM
  echo a600000.usb > /sys/kernel/config/usb_gadget/g1/UDC 2>/dev/null
  sleep 1
  # Configure NCM ethernet
  ip link set usb0 up 2>/dev/null || true
  ip addr flush dev usb0 2>/dev/null || true
  ip addr add 192.168.137.133/24 dev usb0 2>/dev/null || true
" > /tmp/gadget-switch.log 2>&1
'@

$out3 = SendAndWait $sp "sudo systemd-run --on-active=5s --unit=gadget-switch-ncm /usr/local/bin/usb-gadget-setup.sh && echo SWITCH_SCHEDULED" 3000
Write-Host "  $out3"
$sp.Close()

Write-Host ""
Write-Host "[4] Waiting 25s for gadget switch and Windows re-enumeration..."
Start-Sleep -Seconds 25

# ─────────────────────────────────────────────────────────────────────────────
# Step 5: Check Windows USB devices
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[5] Windows USB device state:"
Get-PnpDevice | Where-Object { $_.InstanceId -like "*0525*" -or $_.InstanceId -like "*A4A7*" } |
    Format-Table FriendlyName, Status -AutoSize

Write-Host ""
Write-Host "[6] Looking for new COM port (ACM in composite)..."
Get-PnpDevice -Class Ports | Where-Object { $_.Status -eq "OK" } |
    Format-Table FriendlyName, Status -AutoSize

# ─────────────────────────────────────────────────────────────────────────────
# Step 7: Reconnect via serial and check NCM state
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[7] Reconnecting to check NCM state..."
$sp2 = $null
for ($i = 0; $i -lt 8; $i++) {
    try {
        $sp2 = OpenSerial $Port
        break
    } catch {
        Write-Host "  Attempt $($i+1) failed, retrying in 3s..."
        Start-Sleep -Seconds 3
    }
}

if ($null -eq $sp2) {
    Write-Host "  Could not reconnect to $Port - check if COM port changed (see Step 6 above)"
    exit 1
}

$out7 = SendAndWait $sp2 'echo "UDC=$(cat /sys/kernel/config/usb_gadget/g1/UDC)"; ip -brief addr; cat /sys/class/udc/a600000.usb/function; dmesg | grep -iE "ncm|usb0|composite|g_serial" | tail -10' 7000
Write-Host $out7
$sp2.Close()

Write-Host ""
Write-Host "[8] Testing SSH (if NCM usb0 got IP)..."
$sshResult = ssh -i "$env:USERPROFILE\.ssh\razer-phone" -o StrictHostKeyChecking=no -o ConnectTimeout=5 klipper@192.168.137.133 "echo SSH_OK; uname -r" 2>&1
Write-Host "  SSH result: $sshResult"
