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

# ── Fix 1: kernel module symlink for WiFi ────────────────────────────────────
Write-Host "`n[1] Fixing kernel module path for WiFi..." -ForegroundColor Yellow
S 'KVER=$(uname -r); MODBASE=/lib/modules; if [ ! -d "$MODBASE/$KVER" ]; then SRC=$(ls "$MODBASE/" | grep "${KVER##*sdm845-}" 2>/dev/null | head -1); if [ -n "$SRC" ]; then ln -sf "$MODBASE/$SRC" "$MODBASE/$KVER" && depmod -a && echo "SYMLINK_CREATED: $SRC -> $KVER"; else echo "NO_MATCH: $(ls $MODBASE/)"; fi; else echo "MODULE_DIR_EXISTS"; fi' 6000

# ── Fix 2: Load WiFi after symlink ───────────────────────────────────────────
Write-Host "`n[2] Loading WiFi modules..." -ForegroundColor Yellow
S 'modprobe ath10k_core 2>&1 && modprobe ath10k_snoc 2>&1 && echo WIFI_OK || echo WIFI_FAIL' 6000
Start-Sleep -Milliseconds 2000
Cmd 'ip -brief link show wlan0 2>/dev/null || echo NO_WLAN0' 2000
S 'dmesg | grep -iE "ath10k|wcn3990|snoc" | tail -10' 2000

# ── Fix 3: Restart USB gadget to get composite UDC bind ──────────────────────
# (this will kill COM3 serial - schedule 3s delayed restart)
Write-Host "`n[3] Scheduling USB gadget restart (composite ACM+NCM)..." -ForegroundColor Yellow
Write-Host "    Serial will reconnect after ~5s" -ForegroundColor DarkYellow
S 'systemd-run --on-active=3s --unit=usb-gadget-restart systemctl restart usb-gadget 2>/dev/null && echo RESTART_SCHEDULED || echo RESTART_FAIL_FALLBACK' 4000

$sp.Close()
Write-Host "`nWaiting 8s for gadget to restart..." -ForegroundColor Gray
Start-Sleep -Seconds 8

# ── Reconnect and verify ──────────────────────────────────────────────────────
Write-Host "Reconnecting to serial..." -ForegroundColor Yellow
$sp2 = [System.IO.Ports.SerialPort]::new($Port, 115200)
$sp2.ReadTimeout = 8000; $sp2.Open()
Start-Sleep -Milliseconds 1000; $sp2.ReadExisting() | Out-Null
$sp2.WriteLine(""); Start-Sleep -Milliseconds 1500
$out = $sp2.ReadExisting(); Write-Host $out

Write-Host "`nChecking USB state from Windows..." -ForegroundColor Cyan
$sp2.Close()
