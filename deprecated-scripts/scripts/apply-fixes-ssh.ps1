# apply-fixes-ssh.ps1
# Apply runtime fixes to Razer Phone 2 via SSH — no rootfs reflash needed.
# Fixes: RNDIS removal, WiFi (ath10k_snoc), and optional nmcli connect.
#
# Usage:
#   .\scripts\apply-fixes-ssh.ps1                     # full fix (RNDIS + WiFi diag)
#   .\scripts\apply-fixes-ssh.ps1 -WifiConnect        # also connect to WiFi SSID
#   .\scripts\apply-fixes-ssh.ps1 -DiagOnly           # diagnostics only, no changes
#   .\scripts\apply-fixes-ssh.ps1 -DeviceIP 10.0.0.1  # override IP

param(
    [string]$DeviceIP    = "192.168.137.133",
    [string]$User        = "klipper",
    [string]$KeyPath     = "",
    [string]$WifiSSID    = "CimforceTw-Guest",
    [string]$WifiPass    = "61828630",
    [switch]$WifiConnect,
    [switch]$DiagOnly
)

$ErrorActionPreference = "Stop"

if (-not $KeyPath) { $KeyPath = "$env:USERPROFILE\.ssh\razer-phone" }
$o = @("-i",$KeyPath,"-o","StrictHostKeyChecking=no","-o","BatchMode=yes","-o","ConnectTimeout=15")

function SSH([string]$cmd) {
    & ssh @o "${User}@${DeviceIP}" $cmd
    return $LASTEXITCODE
}

function SSHSudo([string]$cmd, [string]$label="") {
    if ($label) { Write-Host "`n[$label]" -ForegroundColor Cyan }
    $rc = SSH "echo klipper | sudo -S bash -c '$cmd'"
    if ($rc -ne 0) { Write-Host "  exit: $rc" -ForegroundColor Yellow }
    return $rc
}

Write-Host "=== Razer Phone 2 Live Fix via SSH ===" -ForegroundColor Green
Write-Host "  Target: $User@$DeviceIP"
Write-Host "  Mode:   $(if ($DiagOnly) {'DIAGNOSTICS ONLY'} elseif ($WifiConnect) {'FULL FIX + WiFi Connect'} else {'FULL FIX'})"
Write-Host ""

# ─ Connectivity check ──────────────────────────────────────────────────────
Write-Host "[0] Testing SSH connectivity..." -ForegroundColor Yellow
$rc = SSH "echo CONNECTED"
if ($rc -ne 0) {
    Write-Host "ERROR: Cannot SSH to $DeviceIP. Check USB NCM or WiFi connection." -ForegroundColor Red
    exit 1
}
Write-Host "  SSH OK" -ForegroundColor Green

# ─ 1. Kernel/boot info ─────────────────────────────────────────────────────
Write-Host "`n[1] Kernel and boot info" -ForegroundColor Cyan
SSH "uname -r; cat /proc/cmdline"

# ─ 2. USB Gadget / RNDIS fix ───────────────────────────────────────────────
Write-Host "`n[2] USB gadget state" -ForegroundColor Cyan
SSH "echo klipper | sudo -S bash -c 'ls /sys/kernel/config/usb_gadget/g1/functions/ 2>/dev/null || echo NO_GADGET'"

if (-not $DiagOnly) {
    Write-Host "`n[2b] Fixing RNDIS (remove rndis function if present)..." -ForegroundColor Yellow
    $rndisFixScript = @'
G=/sys/kernel/config/usb_gadget/g1
if [ ! -d "$G" ]; then echo "NO_GADGET"; exit 0; fi
if [ ! -d "$G/functions/rndis.usb0" ]; then echo "NO_RNDIS"; exit 0; fi
echo "RNDIS_FOUND - removing..."
echo "" > "$G/UDC" 2>/dev/null || true
sleep 0.3
rm -f "$G/configs/c.1/rndis.usb0" 2>/dev/null || true
rmdir "$G/functions/rndis.usb0" 2>/dev/null || true
sleep 0.2
echo "a600000.usb" > "$G/UDC" 2>/dev/null || true
echo "RNDIS_REMOVED"
'@
    $rndisFixScript = $rndisFixScript -replace "'", "'\''"
    SSHSudo $rndisFixScript "2b: RNDIS runtime removal" | Out-Null
    SSH "echo klipper | sudo -S bash -c 'ls /sys/kernel/config/usb_gadget/g1/functions/ 2>/dev/null'"

    # Also patch the persistent usb-gadget-setup.sh on device to remove RNDIS permanently
    Write-Host "`n[2c] Persisting NCM-only gadget script..." -ForegroundColor Yellow
    $gadgetScript = Get-Content (Join-Path (Split-Path $PSScriptRoot) "wsl-scripts\usb-gadget-setup-ncm.sh") -Raw
    # Send via heredoc
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($gadgetScript))
    SSH "echo klipper | sudo -S bash -c 'echo $encoded | base64 -d > /usr/local/bin/usb-gadget-setup.sh && chmod 755 /usr/local/bin/usb-gadget-setup.sh && echo GADGET_SCRIPT_UPDATED'"
}

# ─ 3. Display / fbcon fix ──────────────────────────────────────────────────
Write-Host "`n[3] Display state" -ForegroundColor Cyan
SSH "echo klipper | sudo -S bash -c 'cat /sys/class/vtconsole/vtcon0/bind 2>/dev/null; cat /sys/class/graphics/fb0/name 2>/dev/null; cat /proc/cmdline | tr \" \" \"\n\" | grep fbcon'"

if (-not $DiagOnly) {
    Write-Host "`n[3b] Unbinding fbcon from fb0 (suppress garbled screen)..." -ForegroundColor Yellow
    SSHSudo 'echo 0 > /sys/class/vtconsole/vtcon0/bind 2>/dev/null && echo FBCON_UNBOUND || echo FBCON_BUILTIN_OR_NOT_BOUND'
}

# ─ 4. Backlight (WLED) ─────────────────────────────────────────────────────
Write-Host "`n[4] WLED backlight" -ForegroundColor Cyan
SSH "echo klipper | sudo -S bash -c 'ls /sys/class/backlight/ 2>/dev/null || echo NO_BACKLIGHT; dmesg | grep -i wled | tail -5'"

# ─ 5. WiFi diagnostics ─────────────────────────────────────────────────────
Write-Host "`n[5] WiFi (ath10k_snoc / WCN3990)" -ForegroundColor Cyan
SSH "echo klipper | sudo -S bash -c 'lsmod | grep -E \"ath10k|wcn|snoc\"; echo ---; ip -brief link show wlan0 2>/dev/null || echo NO_WLAN0; echo ---; dmesg | grep -iE \"ath10k|snoc|wcn3990|qcom.*wifi\" | tail -20'"

Write-Host "`n[5b] Firmware check..." -ForegroundColor Yellow
SSH "echo klipper | sudo -S bash -c 'echo == ath10k firmware ==; ls -lh /lib/firmware/ath10k/WCN3990/hw1.0/ 2>/dev/null || echo EMPTY; echo == qcom sdm845 firmware ==; ls /lib/firmware/qcom/sdm845/ 2>/dev/null | head -10 || echo EMPTY'"

if (-not $DiagOnly) {
    Write-Host "`n[5c] Loading ath10k_snoc..." -ForegroundColor Yellow
    $wifiLoadScript = @'
# Load ath10k modules in order
modprobe ath10k_core 2>&1 || true
modprobe ath10k_snoc 2>&1 || true
sleep 2
echo "--- lsmod ---"
lsmod | grep ath10k
echo "--- wlan0 state ---"
ip -brief link show wlan0 2>/dev/null || echo NO_WLAN0
echo "--- dmesg WiFi tail ---"
dmesg | grep -iE "ath10k|wcn3990|snoc" | tail -15
'@
    $wifiLoadScript = $wifiLoadScript -replace "'", "'\''"
    SSHSudo $wifiLoadScript "5c: Loading WiFi modules" | Out-Null

    # Ensure ath10k_snoc is in modules-load.d
    SSHSudo 'echo -e "ath10k_core\nath10k_snoc" > /etc/modules-load.d/ath10k.conf && echo ATH10K_AUTOLOAD_SET' "5d: Set autoload"
}

if ($WifiConnect) {
    Write-Host "`n[6] Connecting to WiFi: $WifiSSID" -ForegroundColor Cyan
    SSH "echo klipper | sudo -S bash -c 'nmcli dev wifi connect `"$WifiSSID`" password `"$WifiPass`" 2>&1 || echo WIFI_CONNECT_FAILED'"
    SSH "ip -brief addr show wlan0 2>/dev/null; echo ---; ping -c 2 8.8.8.8 2>&1 | tail -3"
}

# ─ Summary ─────────────────────────────────────────────────────────────────
Write-Host "`n=== Summary ===" -ForegroundColor Green
SSH "echo klipper | sudo -S bash -c 'echo == USB gadget ==; ls /sys/kernel/config/usb_gadget/g1/functions/ 2>/dev/null; echo == vtcon ==; cat /sys/class/vtconsole/vtcon0/bind 2>/dev/null; echo == backlight ==; ls /sys/class/backlight/ 2>/dev/null; echo == wlan0 ==; ip -brief link show wlan0 2>/dev/null || echo NO_WLAN0'"

Write-Host "`nDone. To sync these fixes into rootfs-sparse.img run:" -ForegroundColor DarkGray
Write-Host "  wsl -d Ubuntu -u root -- bash /mnt/c/repo/razorphone2linux/wsl-scripts/sync-fixes-to-rootfs.sh" -ForegroundColor DarkGray
