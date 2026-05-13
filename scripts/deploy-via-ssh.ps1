# deploy-via-ssh.ps1
# Deploy scripts to Razer Phone 2 via SSH over NCM USB ethernet (usb0).
# Uses Windows built-in ssh.exe/scp.exe with SSH key auth (no WSL/sshpass needed).
#
# Prerequisites:
#   1. Device booted with NCM gadget active
#   2. Windows ICS configured (ncpa.cpl -> WiFi -> Sharing -> select NCM adapter)
#   3. Run ONCE to install SSH key: .\scripts\setup-ssh-key-via-serial.ps1
#
# Usage:
#   .\scripts\deploy-via-ssh.ps1
#   .\scripts\deploy-via-ssh.ps1 -DeviceIP 192.168.137.133   # skip auto-detect
#   .\scripts\deploy-via-ssh.ps1 -RunSetup                    # also run post-internet-setup.sh
#   .\scripts\deploy-via-ssh.ps1 -HelixPhase                  # run --helix phase

param(
    [string]$DeviceIP = "",
    [string]$User = "klipper",
    [string]$Password = "klipper",
    [string]$KeyPath = "",
    [switch]$RunSetup,
    [switch]$HelixPhase
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path $PSScriptRoot -Parent

# ─ Files to deploy ────────────────────────────────────────────────────────────
$filesToDeploy = @(
    @{ Src = Join-Path $repoRoot "wsl-scripts\usb-gadget-setup-ncm.sh"
        Dest = "/usr/local/bin/usb-gadget-setup.sh"; Sudo = $true; Mode = "755" 
    },
    @{ Src = Join-Path $repoRoot "wsl-scripts\post-internet-setup.sh"
        Dest = "/root/post-internet-setup.sh"; Sudo = $true; Mode = "755" 
    },
    @{ Src = Join-Path $repoRoot "wsl-scripts\fix-wifi-firmware.sh"
        Dest = "/root/fix-wifi-firmware.sh"; Sudo = $true; Mode = "755" 
    }
)
foreach ($f in $filesToDeploy) {
    if (-not (Test-Path $f.Src)) { Write-Error "Missing: $($f.Src)"; exit 1 }
}

# ─ SSH key ────────────────────────────────────────────────────────────────────
$sshDir = Join-Path $env:USERPROFILE ".ssh"
if (-not $KeyPath) { $KeyPath = Join-Path $sshDir "razer-phone" }

if (-not (Test-Path $KeyPath)) {
    Write-Host ""
    Write-Host "ERROR: SSH key not found at $KeyPath" -ForegroundColor Red
    Write-Host "Run once to install key to device via serial:" -ForegroundColor Yellow
    Write-Host "  .\scripts\setup-ssh-key-via-serial.ps1" -ForegroundColor Cyan
    exit 1
}

# SSH options - key auth only, no password prompt
$o = @("-i", $KeyPath, "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=10",
    "-o", "BatchMode=yes", "-o", "PasswordAuthentication=no")

# ─ Helpers ────────────────────────────────────────────────────────────────────
function SSHRun([string]$ip, [string]$cmd, [string]$desc = "") {
    if ($desc) { Write-Host "  >> $desc" -ForegroundColor Yellow }
    & ssh @o "${User}@${ip}" $cmd 2>&1 | Write-Host
    return $LASTEXITCODE
}
function SCPSend([string]$src, [string]$ip, [string]$dst) {
    Write-Host "  SCP: $(Split-Path $src -Leaf) -> ${ip}:${dst}" -ForegroundColor Yellow
    & scp @o "$src" "${User}@${ip}:${dst}" 2>&1 | Write-Host
}

# ─ Auto-detect IP ─────────────────────────────────────────────────────────────
function Find-DeviceIP {
    Write-Host "Scanning 192.168.137.0/24 ..." -ForegroundColor Yellow
    $arp = arp -a 2>$null | Select-String "192\.168\.137\."
    foreach ($line in $arp) {
        if ($line -match "(192\.168\.137\.(\d+))") {
            $ip = $Matches[1]; $oct = [int]$Matches[2]
            if ($oct -le 1 -or $oct -ge 224) { continue }
            Write-Host "  ARP: $ip ..." -ForegroundColor Gray
            try {
                $t = New-Object System.Net.Sockets.TcpClient
                $ar = $t.BeginConnect($ip, 22, $null, $null)
                $ok = $ar.AsyncWaitHandle.WaitOne(2000)
                if ($ok) { try { $t.EndConnect($ar) } catch { $ok = $false } }
                $t.Close()
                if ($ok) { Write-Host "  Port 22 open: $ip" -ForegroundColor Green; return $ip }
            }
            catch {}
        }
    }
    Write-Host "  ARP miss - sweeping 100-149..." -ForegroundColor Gray
    $jobs = 100..149 | ForEach-Object {
        $addr = "192.168.137.$_"
        Start-Job -ScriptBlock {
            param($a)
            if (Test-Connection $a -Count 1 -TimeoutSeconds 1 -Quiet 2>$null) {
                try {
                    $t = New-Object System.Net.Sockets.TcpClient
                    $ar = $t.BeginConnect($a, 22, $null, $null)
                    $ok = $ar.AsyncWaitHandle.WaitOne(1500)
                    if ($ok) { try { $t.EndConnect($ar) } catch { $ok = $false } }
                    $t.Close()
                    if ($ok) { return $a }
                }
                catch {}
            }
        } -ArgumentList $addr
    }
    $found = $null
    $jobs | ForEach-Object {
        $r = Receive-Job $_ -Wait -AutoRemoveJob 2>$null
        if ($r -and -not $found) { $found = $r }
    }
    return $found
}

# ─ Main ───────────────────────────────────────────────────────────────────────
Write-Host "=== deploy-via-ssh.ps1 ===" -ForegroundColor Cyan
Write-Host "Key: $KeyPath" -ForegroundColor Gray

if (-not $DeviceIP) {
    $DeviceIP = Find-DeviceIP
    if (-not $DeviceIP) {
        Write-Error "Device not found. Check ICS setup and try: .\scripts\deploy-via-ssh.ps1 -DeviceIP 192.168.137.133"
        exit 1
    }
}
Write-Host "Device IP: $DeviceIP" -ForegroundColor Green

# Test SSH
Write-Host "Testing SSH..." -ForegroundColor Yellow
$whoami = & ssh @o "${User}@${DeviceIP}" "whoami" 2>&1
if ($LASTEXITCODE -ne 0 -or "$whoami" -notmatch "klipper") {
    Write-Host "  Result: $whoami" -ForegroundColor Red
    Write-Error "SSH failed. Run: .\scripts\setup-ssh-key-via-serial.ps1"
    exit 1
}
Write-Host "SSH OK (user: $whoami)" -ForegroundColor Green

# Deploy
Write-Host ""
Write-Host "Deploying files..." -ForegroundColor Cyan
foreach ($f in $filesToDeploy) {
    $tmp = "/tmp/$(Split-Path $f.Src -Leaf)"
    SCPSend $f.Src $DeviceIP $tmp
    $mv = "mv $tmp $($f.Dest) && chmod $($f.Mode) $($f.Dest) && echo INSTALLED"
    if ($f.Sudo) {
        SSHRun $DeviceIP "echo '$Password' | sudo -S bash -c '$mv'" "Install $($f.Dest)"
    }
    else {
        SSHRun $DeviceIP $mv "Install $($f.Dest)"
    }
}

# Verify
Write-Host ""
Write-Host "Verifying..." -ForegroundColor Cyan
SSHRun $DeviceIP "echo '$Password' | sudo -S head -2 /usr/local/bin/usb-gadget-setup.sh" "gadget script"
SSHRun $DeviceIP "echo '$Password' | sudo -S head -2 /root/post-internet-setup.sh" "setup script"

if ($RunSetup) {
    Write-Host ""
    Write-Host "Running post-internet-setup.sh..." -ForegroundColor Cyan
    SSHRun $DeviceIP "echo '$Password' | sudo -S bash /root/post-internet-setup.sh" "post-internet-setup.sh"
}
if ($HelixPhase) {
    Write-Host ""
    Write-Host "Running post-internet-setup.sh --helix..." -ForegroundColor Cyan
    SSHRun $DeviceIP "echo '$Password' | sudo -S bash /root/post-internet-setup.sh --helix" "--helix"
}

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
Write-Host "SSH: ssh -i $KeyPath klipper@$DeviceIP"
