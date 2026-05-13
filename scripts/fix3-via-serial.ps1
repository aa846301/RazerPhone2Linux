# fix3-via-serial.ps1
# Sends NCM USB gadget update + post-internet HelixScreen setup script to running device via ACM serial.
# Run AFTER closing 06-capture-usb-console.ps1 (it holds the COM port).
#
# What this does:
#   1. Updates /usr/local/bin/usb-gadget-setup.sh to add CDC-NCM USB ethernet
#   2. Copies post-internet-setup.sh to /root/ on the device
#   3. Reboots the device
#
# After reboot:
#   - Windows will see a new USB NCM ethernet adapter
#   - Share internet via ICS (see instructions below)
#   - Run: sudo bash /root/post-internet-setup.sh  (on device via serial)

param(
    [string]$ComPort = "",   # Leave blank to auto-detect first available COM port
    [int]$Baud = 115200
)

# ── Auto-detect COM port ──────────────────────────────────────
if (-not $ComPort) {
    Write-Host "Auto-detecting COM port..." -ForegroundColor Yellow
    $detected = $null
    foreach ($n in 1..30) {
        $name = "COM$n"
        try {
            $test = New-Object System.IO.Ports.SerialPort $name, 115200
            $test.Open()
            $test.Close()
            $test.Dispose()
            $detected = $name
            break
        }
        catch { }
    }
    if (-not $detected) {
        Write-Error "No COM port found. Is the phone connected and ACM gadget active?"
        exit 1
    }
    $ComPort = $detected
    Write-Host "Detected: $ComPort" -ForegroundColor Green
}

$ErrorActionPreference = "Stop"

# ── Helpers ──────────────────────────────────────────────────
function OpenPort {
    $p = New-Object System.IO.Ports.SerialPort $ComPort, $Baud
    $p.ReadTimeout = 4000
    $p.WriteTimeout = 5000
    $p.NewLine = "`n"
    $p.Open()
    return $p
}

function Rx($port, $ms = 500) {
    Start-Sleep -Milliseconds $ms
    try { $out = $port.ReadExisting(); if ($out -ne "") { Write-Host $out -NoNewline } }
    catch { }
}

function Tx($port, $cmd, $delayMs = 400) {
    $port.WriteLine($cmd)
    Rx $port $delayMs
}

# ── Read scripts from repo ────────────────────────────────────
$repoRoot = Split-Path $PSScriptRoot -Parent
$gadgetSrc = Join-Path $repoRoot "wsl-scripts\usb-gadget-setup-ncm.sh"
$setupSrc = Join-Path $repoRoot "wsl-scripts\post-internet-setup.sh"

if (-not (Test-Path $gadgetSrc)) {
    Write-Error "Missing: $gadgetSrc - run this script from the repo root."
    exit 1
}
if (-not (Test-Path $setupSrc)) {
    Write-Error "Missing: $setupSrc"
    exit 1
}

# Base64-encode both scripts (Unix line endings)
function EncodeScript($path) {
    $content = (Get-Content -Raw $path) -replace "`r`n", "`n"
    [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($content))
}

$gadgetB64 = EncodeScript $gadgetSrc
$setupB64 = EncodeScript $setupSrc

# Split into 72-char chunks safe for echo
function SplitB64($b64, $chunkSize = 72) {
    $lines = @()
    for ($i = 0; $i -lt $b64.Length; $i += $chunkSize) {
        $lines += $b64.Substring($i, [Math]::Min($chunkSize, $b64.Length - $i))
    }
    return $lines
}

$gadgetChunks = SplitB64 $gadgetB64
$setupChunks = SplitB64 $setupB64

Write-Host "=== fix3-via-serial.ps1 ===" -ForegroundColor Cyan
Write-Host "Port: $ComPort | Gadget script: $($gadgetChunks.Count) chunks | Setup script: $($setupChunks.Count) chunks"
Write-Host ""
Write-Host "Opening $ComPort..." -ForegroundColor Yellow

$sp = OpenPort

try {
    # ── Wake terminal ────────────────────────────────────────
    Write-Host "Waking terminal..." -ForegroundColor Yellow
    Tx $sp "" 500
    Tx $sp "" 300
    Rx $sp 500

    # ── Send usb-gadget-setup.sh ─────────────────────────────
    Write-Host "Sending usb-gadget-setup.sh (NCM)..." -ForegroundColor Yellow

    # Clear temp b64 file first
    Tx $sp "echo klipper | sudo -S bash -c 'rm -f /tmp/gadget.b64'" 600

    # Append chunks
    foreach ($chunk in $gadgetChunks) {
        Tx $sp "printf '%s' '$chunk' >> /tmp/gadget.b64" 150
    }

    # Decode + install
    Tx $sp "echo klipper | sudo -S bash -c 'base64 -d /tmp/gadget.b64 > /usr/local/bin/usb-gadget-setup.sh && chmod 755 /usr/local/bin/usb-gadget-setup.sh && rm /tmp/gadget.b64 && echo GADGET_OK'" 2000
    Rx $sp 1000

    # ── Send post-internet-setup.sh ──────────────────────────
    Write-Host "Sending post-internet-setup.sh..." -ForegroundColor Yellow

    Tx $sp "rm -f /tmp/setup.b64" 300

    foreach ($chunk in $setupChunks) {
        Tx $sp "printf '%s' '$chunk' >> /tmp/setup.b64" 150
    }

    Tx $sp "echo klipper | sudo -S bash -c 'base64 -d /tmp/setup.b64 > /root/post-internet-setup.sh && chmod 755 /root/post-internet-setup.sh && rm /tmp/setup.b64 && echo SETUP_OK'" 2000
    Rx $sp 1000

    # ── Verify ───────────────────────────────────────────────
    Write-Host "Verifying..." -ForegroundColor Yellow
    Tx $sp "echo klipper | sudo -S head -3 /usr/local/bin/usb-gadget-setup.sh" 800
    Tx $sp "echo klipper | sudo -S head -3 /root/post-internet-setup.sh" 800
    Tx $sp "echo klipper | sudo -S grep -c ncm /usr/local/bin/usb-gadget-setup.sh && echo 'NCM lines found'" 800

    # ── Reboot ───────────────────────────────────────────────
    Write-Host ""
    Write-Host "Rebooting device..." -ForegroundColor Green
    Tx $sp "echo klipper | sudo -S reboot" 1000
}
finally {
    if ($sp -and $sp -is [System.IO.Ports.SerialPort]) {
        try { $sp.Close() } catch { }
        try { $sp.Dispose() } catch { }
    }
}

Write-Host ""
Write-Host "=== After reboot ===" -ForegroundColor Cyan
Write-Host "1. Windows will show TWO USB devices from the phone:"
Write-Host "   - A COM port (ACM serial console)"
Write-Host "   - A new 'Remote NDIS' or 'USB Ethernet' adapter (CDC NCM)"
Write-Host ""
Write-Host "2. Share internet via Windows ICS:"
Write-Host "   - Open: ncpa.cpl (Network Connections)"
Write-Host "   - Right-click your WiFi/Ethernet -> Properties -> Sharing tab"
Write-Host "   - Enable: 'Allow other network users to connect...'"
Write-Host "   - Select: the new CDC NCM / RNDIS adapter"
Write-Host "   - Click OK"
Write-Host ""
Write-Host "3. On device (via serial console):" 
Write-Host "   sudo bash /root/post-internet-setup.sh"
Write-Host ""
Write-Host "4. After packages install + KIAUH (Klipper+Moonraker):"
Write-Host "   sudo bash /root/post-internet-setup.sh --helix"
Write-Host ""
