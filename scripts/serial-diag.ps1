param(
    [string]$Port = "COM5",
    [int]$BaudRate = 115200
)
# Send diagnostic commands to device via serial console and capture output

$serial = $null
try {
    $serial = New-Object System.IO.Ports.SerialPort($Port, $BaudRate, 
        [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
    $serial.ReadTimeout  = 3000
    $serial.WriteTimeout = 3000
    $serial.NewLine      = "`n"
    $serial.Encoding     = [System.Text.Encoding]::ASCII
    $serial.Open()
    Write-Host "Connected to $Port @ $BaudRate" -ForegroundColor Green
} catch {
    Write-Host "Cannot open $Port : $_" -ForegroundColor Red
    exit 1
}

function Send-Cmd {
    param([string]$Cmd, [int]$WaitMs = 2500)
    $serial.WriteLine($Cmd)
    Start-Sleep -Milliseconds $WaitMs
    $buf = ""
    try {
        while ($serial.BytesToRead -gt 0) {
            $buf += $serial.ReadExisting()
            Start-Sleep -Milliseconds 100
        }
    } catch {}
    return $buf
}

# Press Enter to get a prompt, then run each command
Write-Host "--- Pressing Enter to wake shell ---"
$null = Send-Cmd "" 500

$cmds = @(
    @{ Label="CMDLINE";      Cmd="cat /proc/cmdline";                                  Wait=1500 }
    @{ Label="UNAME";        Cmd="uname -a";                                            Wait=1500 }
    @{ Label="BACKLIGHT";    Cmd="ls /sys/class/backlight/ 2>/dev/null || echo EMPTY"; Wait=1500 }
    @{ Label="VTCON0_BIND";  Cmd="cat /sys/class/vtconsole/vtcon0/bind 2>/dev/null";   Wait=1500 }
    @{ Label="FB0_NAME";     Cmd="cat /sys/class/graphics/fb0/name 2>/dev/null || echo NO_FB0"; Wait=1500 }
    @{ Label="USB_GADGET_FUNCS"; Cmd="ls /sys/kernel/config/usb_gadget/g1/functions/ 2>/dev/null || echo NO_GADGET"; Wait=1500 }
    @{ Label="USB_GADGET_IDS";   Cmd="cat /sys/kernel/config/usb_gadget/g1/idProduct 2>/dev/null; cat /sys/kernel/config/usb_gadget/g1/bDeviceClass 2>/dev/null"; Wait=1500 }
    @{ Label="UDC";          Cmd="cat /sys/kernel/config/usb_gadget/g1/UDC 2>/dev/null || echo NO_UDC"; Wait=1500 }
    @{ Label="DMESG_USB";    Cmd="dmesg | grep -iE 'usb_f_ncm|usb_f_acm|configfs|gadget|RNDIS|ncm|rndis' | tail -20"; Wait=2000 }
    @{ Label="DMESG_WLED";   Cmd="dmesg | grep -iE 'wled|backlight|pmi8998' | tail -15"; Wait=2000 }
    @{ Label="DMESG_DRM";    Cmd="dmesg | grep -iE 'drm|simplefb|simpledrm|fb0' | tail -15"; Wait=2000 }
    @{ Label="SYSTEMCTL_USB";Cmd="systemctl status usb-gadget 2>/dev/null | head -15 || echo NO_SERVICE"; Wait=2000 }
    @{ Label="KERNEL_CONFIG_USB"; Cmd="zcat /proc/config.gz 2>/dev/null | grep -E 'USB_F_NCM|USB_F_ACM|USB_G_NCM|USB_CONFIGFS_NCM|USB_G_SERIAL' || echo NO_KCONFIG"; Wait=2000 }
    @{ Label="WLED_CONFIG";  Cmd="zcat /proc/config.gz 2>/dev/null | grep -E 'BACKLIGHT_QCOM_WLED|QCOM_WLED' || echo NO_WLED_KCONFIG"; Wait=2000 }
)

$results = [System.Collections.ArrayList]::new()
foreach ($c in $cmds) {
    Write-Host ">>> $($c.Label)" -ForegroundColor Cyan
    $out = Send-Cmd $c.Cmd $c.Wait
    Write-Host $out
    $null = $results.Add([PSCustomObject]@{ Label=$c.Label; Output=$out })
}

$serial.Close()
Write-Host "`n=== DONE ===" -ForegroundColor Green

# Save to file
$outFile = "$PSScriptRoot\..\output\serial-diag-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
$results | ForEach-Object { "=== $($_.Label) ===`n$($_.Output)`n" } | Out-File $outFile -Encoding UTF8
Write-Host "Saved to: $outFile" -ForegroundColor Yellow
