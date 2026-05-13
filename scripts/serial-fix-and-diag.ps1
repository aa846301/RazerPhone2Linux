param(
    [string]$Port     = "COM3",
    [int]$BaudRate    = 115200,
    [string]$User     = "klipper",
    [string]$Pass     = "klipper",
    [switch]$DiagOnly
)
# Login via serial console then fix RNDIS + diagnose WiFi/display

$sp = [System.IO.Ports.SerialPort]::new($Port, $BaudRate)
$sp.ReadTimeout = 6000; $sp.WriteTimeout = 2000
try { $sp.Open() } catch { Write-Error "Cannot open $Port`: $_"; exit 1 }
Write-Host "Connected to $Port" -ForegroundColor Green

function Read-Until {
    param([string[]]$patterns, [int]$timeoutMs = 8000)
    $deadline = [DateTime]::Now.AddMilliseconds($timeoutMs)
    $buf = ""
    while ([DateTime]::Now -lt $deadline) {
        try {
            if ($sp.BytesToRead -gt 0) { $buf += $sp.ReadExisting() }
        } catch {}
        foreach ($p in $patterns) {
            if ($buf -match $p) { return @{ Text=$buf; Match=$p } }
        }
        Start-Sleep -Milliseconds 100
    }
    return @{ Text=$buf; Match="" }
}

function Cmd {
    param([string]$c, [int]$ms=3000)
    $sp.WriteLine($c)
    Start-Sleep -Milliseconds $ms
    try { $r = $sp.ReadExisting() } catch { $r = "" }
    if ($r) { Write-Host $r }
    return $r
}

# ── Wake terminal ────────────────────────────────────────────────────────
Write-Host "`n[0] Waking terminal..." -ForegroundColor Yellow
$sp.WriteLine("")
$res = Read-Until @("login:", "\$\s*$", "#\s*$") 10000
Write-Host $res.Text

# ── Login if needed ──────────────────────────────────────────────────────
if ($res.Match -match "login:") {
    Write-Host "[1] Logging in as $User..." -ForegroundColor Yellow
    $sp.WriteLine($User)
    $res2 = Read-Until @("Password:", "assword:") 5000
    Write-Host $res2.Text
    $sp.WriteLine($Pass)
    $res3 = Read-Until @("\$\s*$", "#\s*$", "~") 8000
    Write-Host $res3.Text
    if ($res3.Text -match "incorrect|failed") {
        Write-Error "Login failed! Check user/password."
        $sp.Close(); exit 1
    }
    Write-Host "  Logged in." -ForegroundColor Green
} elseif ($res.Match) {
    Write-Host "  Shell already active." -ForegroundColor Green
} else {
    Write-Host "  No prompt detected, proceeding anyway..." -ForegroundColor Yellow
}
Start-Sleep -Milliseconds 500

# ── Quick diagnostics ────────────────────────────────────────────────────
Write-Host "`n[2] Kernel + cmdline" -ForegroundColor Cyan
Cmd "uname -r; cat /proc/cmdline" 2000

Write-Host "`n[3] USB gadget functions" -ForegroundColor Cyan
Cmd "ls /sys/kernel/config/usb_gadget/g1/functions/ 2>/dev/null || echo NO_GADGET" 2000

Write-Host "`n[4] Backlight" -ForegroundColor Cyan
Cmd "ls /sys/class/backlight/ 2>/dev/null || echo EMPTY" 1500

Write-Host "`n[5] vtcon0 bind (fbcon)" -ForegroundColor Cyan
Cmd "cat /sys/class/vtconsole/vtcon0/bind 2>/dev/null" 1500

if (-not $DiagOnly) {
    # ── Fix RNDIS ────────────────────────────────────────────────────────
    Write-Host "`n[6] Removing RNDIS function..." -ForegroundColor Yellow
    $rndisCmd = @'
echo klipper | sudo -S bash -c '
G=/sys/kernel/config/usb_gadget/g1
if [ -d "$G/functions/rndis.usb0" ]; then
  echo "" > "$G/UDC" 2>/dev/null
  sleep 0.3
  rm -f "$G/configs/c.1/rndis.usb0"
  rmdir "$G/functions/rndis.usb0" 2>/dev/null
  sleep 0.2
  echo "a600000.usb" > "$G/UDC" 2>/dev/null
  echo RNDIS_REMOVED
else
  echo NO_RNDIS
fi'
'@
    Cmd $rndisCmd 5000

    Write-Host "`n[6b] Gadget functions after fix:" -ForegroundColor Cyan
    Cmd "ls /sys/kernel/config/usb_gadget/g1/functions/ 2>/dev/null" 2000

    # ── Fix usb-gadget-setup.sh (persist) ────────────────────────────────
    Write-Host "`n[7] Patching usb-gadget-setup.sh to remove RNDIS permanently..." -ForegroundColor Yellow
    $patchCmd = @'
echo klipper | sudo -S bash -c '
f=/usr/local/bin/usb-gadget-setup.sh
if grep -q rndis "$f" 2>/dev/null; then
  sed -i "/rndis/d" "$f"
  echo RNDIS_PATCHED_FROM_SCRIPT
else
  echo RNDIS_NOT_IN_SCRIPT
fi
head -3 "$f"'
'@
    Cmd $patchCmd 4000

    # ── Load WiFi ────────────────────────────────────────────────────────
    Write-Host "`n[8] Loading WiFi modules..." -ForegroundColor Yellow
    Cmd "echo klipper | sudo -S modprobe ath10k_core 2>&1; echo klipper | sudo -S modprobe ath10k_snoc 2>&1; echo WIFI_LOAD_DONE" 6000
    Start-Sleep -Milliseconds 2000
    Cmd "ip -brief link show wlan0 2>/dev/null || echo NO_WLAN0" 1500
    Cmd "dmesg | grep -iE 'ath10k|wcn3990' | tail -10" 2000

    # ── Ensure ath10k autoload ────────────────────────────────────────────
    Cmd "echo klipper | sudo -S bash -c 'echo -e ath10k_core\\\\nath10k_snoc > /etc/modules-load.d/ath10k.conf && echo ATH10K_AUTOLOAD_SET'" 3000

    # ── Unbind fbcon ──────────────────────────────────────────────────────
    Write-Host "`n[9] Unbinding fbcon..." -ForegroundColor Yellow
    Cmd "echo klipper | sudo -S bash -c 'echo 0 > /sys/class/vtconsole/vtcon0/bind && echo FBCON_UNBOUND || echo FBCON_ALREADY_UNBOUND'" 3000
}

Write-Host "`n=== Summary ===" -ForegroundColor Green
Cmd "ls /sys/kernel/config/usb_gadget/g1/functions/ 2>/dev/null; cat /sys/class/vtconsole/vtcon0/bind 2>/dev/null; ls /sys/class/backlight/ 2>/dev/null; ip -brief link show wlan0 2>/dev/null || echo NO_WLAN0" 3000

$sp.Close()
Write-Host "`n[Done] Check Windows Device Manager - UsbNcm should now install." -ForegroundColor Green
Write-Host "       Wait ~5s then test SSH: ssh -i `$env:USERPROFILE\.ssh\razer-phone klipper@192.168.137.133"
