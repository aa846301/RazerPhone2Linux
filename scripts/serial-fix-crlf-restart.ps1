param([string]$Port = "COM3")

function OpenSerial($port) {
    $sp = New-Object System.IO.Ports.SerialPort $port, 115200
    $sp.ReadTimeout = 8000
    $sp.Open()
    Start-Sleep -Milliseconds 300
    $sp.ReadExisting() | Out-Null
    return $sp
}

function SendAndWait($sp, $cmd, $waitMs=4000) {
    $sp.WriteLine($cmd)
    Start-Sleep -Milliseconds $waitMs
    return $sp.ReadExisting()
}

Write-Host "[1] Scheduling gadget restart in 5s (will briefly drop serial)..."
$sp = OpenSerial $Port
$out = SendAndWait $sp "sudo systemd-run --on-active=5s --unit=usb-gadget-fix systemctl restart usb-gadget && echo RESTART2_SCHEDULED" 3000
Write-Host $out
$sp.Close()

Write-Host ""
Write-Host "Waiting 20s for gadget to restart and re-enumerate..."
Start-Sleep -Seconds 20

Write-Host ""
Write-Host "[2] Reconnecting to check gadget state..."
$sp2 = $null
for ($i = 0; $i -lt 5; $i++) {
    try {
        $sp2 = OpenSerial $Port
        break
    } catch {
        Write-Host "  Attempt $($i+1) failed, retrying in 3s..."
        Start-Sleep -Seconds 3
    }
}
if ($null -eq $sp2) {
    Write-Host "ERROR: Could not reconnect to $Port"
    exit 1
}

$out2 = SendAndWait $sp2 "echo UDC=`$(cat /sys/kernel/config/usb_gadget/g1/UDC); systemctl status usb-gadget 2>&1 | head -5; ip -brief link" 5000
Write-Host $out2
$sp2.Close()

Write-Host ""
Write-Host "[3] Windows USB device state:"
Get-PnpDevice | Where-Object {$_.InstanceId -like "*0525*" -or $_.InstanceId -like "*A4A7*"} | Format-Table FriendlyName, Status -AutoSize
