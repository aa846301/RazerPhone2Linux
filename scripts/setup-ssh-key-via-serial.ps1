# setup-ssh-key-via-serial.ps1
# Installs a Windows SSH public key to Razer Phone 2 via serial console.
# Run this ONCE before using deploy-via-ssh.ps1.
#
# Usage:
#   .\scripts\setup-ssh-key-via-serial.ps1

param(
    [string]$ComPort  = "",        # blank = auto-detect
    [string]$KeyPath  = "",        # blank = use default razer-phone key
    [string]$User     = "klipper",
    [string]$Password = "klipper",
    [int]$Baud        = 115200
)

$ErrorActionPreference = "Stop"

# ── Key paths ─────────────────────────────────────────────────────────────────
$sshDir  = Join-Path $env:USERPROFILE ".ssh"
if (-not $KeyPath) { $KeyPath = Join-Path $sshDir "razer-phone" }
$pubPath = "$KeyPath.pub"

# ── Generate key if missing ───────────────────────────────────────────────────
if (-not (Test-Path $pubPath)) {
    Write-Host "Generating SSH key at $KeyPath ..." -ForegroundColor Yellow
    if (-not (Test-Path $sshDir)) { New-Item -ItemType Directory $sshDir | Out-Null }
    & ssh-keygen -t ed25519 -f $KeyPath -N "" -C "razer-phone-deploy"
    if ($LASTEXITCODE -ne 0) { Write-Error "ssh-keygen failed"; exit 1 }
}

$pubKey = (Get-Content $pubPath -Raw).Trim()
Write-Host "Public key: $pubKey" -ForegroundColor Cyan
Write-Host ""

# ── Auto-detect COM port ──────────────────────────────────────────────────────
if (-not $ComPort) {
    Write-Host "Auto-detecting COM port..." -ForegroundColor Yellow
    foreach ($n in 1..30) {
        try {
            $t = New-Object System.IO.Ports.SerialPort "COM$n", $Baud
            $t.Open(); $t.Close(); $t.Dispose()
            $ComPort = "COM$n"
            break
        } catch { }
    }
    if (-not $ComPort) { Write-Error "No COM port found."; exit 1 }
    Write-Host "Detected: $ComPort" -ForegroundColor Green
}

# ── Serial helpers ────────────────────────────────────────────────────────────
function Rx($port, $ms = 500) {
    Start-Sleep -Milliseconds $ms
    try { $out = $port.ReadExisting(); if ($out) { Write-Host $out -NoNewline } } catch { }
}
function Tx($port, $cmd, $ms = 600) {
    $port.WriteLine($cmd)
    Rx $port $ms
}

# ── Open port ─────────────────────────────────────────────────────────────────
Write-Host "Opening $ComPort..." -ForegroundColor Yellow
$sp = New-Object System.IO.Ports.SerialPort $ComPort, $Baud
$sp.ReadTimeout  = 5000
$sp.WriteTimeout = 5000
$sp.NewLine      = "`n"
$sp.Open()

try {
    # Wake terminal
    Tx $sp "" 600
    Tx $sp "" 400

    # Install public key for klipper user (NOT via sudo - ~ must resolve to /home/klipper)
    $klipperHome = "/home/$User"
    $cmd = "mkdir -p $klipperHome/.ssh && echo '$pubKey' >> $klipperHome/.ssh/authorized_keys && chmod 700 $klipperHome/.ssh && chmod 600 $klipperHome/.ssh/authorized_keys && echo KEY_OK"
    Tx $sp $cmd 1500

    # Also install to root (for /root/ file deployment)
    $rootCmd = "mkdir -p /root/.ssh && echo '$pubKey' >> /root/.ssh/authorized_keys && chmod 700 /root/.ssh && chmod 600 /root/.ssh/authorized_keys && echo ROOT_KEY_OK"
    Tx $sp "echo '$Password' | sudo -S bash -c '$rootCmd'" 2000

    # Verify
    Tx $sp "cat ~/.ssh/authorized_keys" 800

    Write-Host ""
    Write-Host "SSH key installed!" -ForegroundColor Green
    Write-Host "Now run: .\scripts\deploy-via-ssh.ps1" -ForegroundColor Cyan
}
finally {
    try { $sp.Close() } catch { }
    try { $sp.Dispose() } catch { }
}
