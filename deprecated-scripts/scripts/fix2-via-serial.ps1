param([string]$Port = "COM4", [int]$BaudRate = 115200, [string]$Pass = "klipper")

$sp = New-Object System.IO.Ports.SerialPort($Port, $BaudRate, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$sp.ReadTimeout  = 8000; $sp.WriteTimeout = 2000; $sp.Open()

function Cmd { param([string]$c, [int]$ms = 3500)
    Write-Host "> $c" -ForegroundColor DarkGray
    $sp.WriteLine($c); Start-Sleep -Milliseconds $ms
    $o = $sp.ReadExisting(); Start-Sleep -Milliseconds 500; $o += $sp.ReadExisting()
    Write-Host $o }
function S { param([string]$c, [int]$ms = 4000) Cmd "echo $Pass | sudo -S $c" $ms }

$sp.ReadExisting() | Out-Null; $sp.WriteLine(""); Start-Sleep -Milliseconds 800; $sp.ReadExisting() | Out-Null

# ---- 1. Fix resizefs.service: delete broken file, then mask ----
Write-Host "`n[1] Masking resizefs.service (already expanded)..." -ForegroundColor Yellow
S 'bash -c "rm -f /etc/systemd/system/resizefs.service && systemctl mask resizefs.service && systemctl daemon-reload && systemctl reset-failed && echo MASK_OK"' 6000

# ---- 2. WiFi: load ath10k_snoc ----
Write-Host "`n[2] Loading ath10k_snoc WiFi driver..." -ForegroundColor Yellow
S 'modprobe ath10k_snoc 2>&1; echo modprobe_done'
Cmd 'dmesg 2>&1 | grep -iE "ath10k|snoc|wcn3990" | tail -20' 5000
Cmd 'ip -brief link 2>&1'

# ---- 3. ath10k firmware paths ----
Write-Host "`n[3] ath10k firmware paths..." -ForegroundColor Yellow
Cmd 'find /lib/firmware/ath10k/ -type f 2>/dev/null | head -20'

# ---- 4. Klipper status ----
Write-Host "`n[4] Klipper details..." -ForegroundColor Yellow
Cmd 'systemctl status klipper --no-pager 2>&1 | head -25'

$sp.Close(); Write-Host "`n=== DONE ===" -ForegroundColor Green
