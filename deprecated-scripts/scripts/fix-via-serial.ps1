param([string]$Port = "COM4", [int]$BaudRate = 115200, [string]$Pass = "klipper")

$sp = New-Object System.IO.Ports.SerialPort($Port, $BaudRate, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$sp.ReadTimeout  = 8000
$sp.WriteTimeout = 2000
$sp.Open()

function Cmd {
    param([string]$c, [int]$ms = 3500)
    Write-Host "> $c" -ForegroundColor DarkGray
    $sp.WriteLine($c)
    Start-Sleep -Milliseconds $ms
    $out = $sp.ReadExisting()
    Start-Sleep -Milliseconds 500
    $out += $sp.ReadExisting()
    Write-Host $out
}
function SudoCmd {
    param([string]$c, [int]$ms = 4000)
    # Pipe password to sudo -S to avoid interactive prompt
    Cmd "echo $Pass | sudo -S $c" $ms
}

$sp.ReadExisting() | Out-Null
$sp.WriteLine(""); Start-Sleep -Milliseconds 800; $sp.ReadExisting() | Out-Null

# ---- 1. Blacklist msm and panel_novatek_nt36830 via modprobe.d ----
Write-Host "`n[1] Blacklisting MSM DRM and NT36830 panel modules..." -ForegroundColor Yellow
# Use single-quoted PS string so $ is literal; use printf for reliable multiline write
SudoCmd 'bash -c "printf \"blacklist msm\nblacklist panel_novatek_nt36830\n\" > /etc/modprobe.d/razer-blacklist.conf && echo OK"'

# ---- 2. Expand filesystem ----
Write-Host "`n[2] Expanding root filesystem (resize2fs)..." -ForegroundColor Yellow
SudoCmd 'resize2fs /dev/sda14 2>&1' 20000

# ---- 3. WiFi: check modules and firmware ----
Write-Host "`n[3] WiFi module availability..." -ForegroundColor Yellow
Cmd 'find /lib/modules/$(uname -r) -name "*ath10k*" -o -name "*wcn3*" -o -name "*qca6174*" 2>/dev/null | head -20'
Cmd 'ls /lib/firmware/ath10k/ 2>/dev/null; ls /lib/firmware/qca/ 2>/dev/null'
Cmd 'dmesg 2>&1 | grep -iE "ath10k|wcn|wifi|wlan|qca" | tail -15' 4000

# ---- 4. Check after resize ----
Write-Host "`n[4] Disk space after resize..." -ForegroundColor Yellow
Cmd 'df -h /'

# ---- 5. Check resizefs unit ----
Write-Host "`n[5] resizefs service log..." -ForegroundColor Yellow
SudoCmd 'journalctl -u resizefs.service --no-pager -n 20 2>&1' 4000

$sp.Close()
Write-Host "`n=== DONE ===" -ForegroundColor Green
