param(
    [switch]$Reboot       = $true,
    [switch]$DryRun,
    [switch]$SkipUserdata   # pass when rootfs is already on device; only reflash boot_a
)
# NOTE: vbmeta is NOT flashed here.
# vbmeta_disabled.img (AVB flags=3) was flashed once and persists across reboots.
# No need to reflash it unless you wipe the device completely.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspace = Get-Location
$outputDir = Join-Path $workspace "output"

$bootImage   = Join-Path $outputDir "boot-observable.img"
$rootfsImage = Join-Path $outputDir "rootfs-sparse.img"

if (-not (Test-Path $bootImage)) {
    throw "boot-observable.img not found. Run rebuild-all.sh in WSL first."
}

if (-not $SkipUserdata -and -not (Test-Path $rootfsImage)) {
    throw "rootfs-sparse.img not found. Build it first, or pass -SkipUserdata if already flashed."
}

function Invoke-Fastboot {
    param([string[]]$Arguments)
    $commandText = "fastboot " + ($Arguments -join " ")
    Write-Host $commandText
    if ($DryRun) { return }
    & fastboot @Arguments
    if ($LASTEXITCODE -ne 0) { throw "fastboot failed: $commandText" }
}

Write-Host "=== Flashing Razer Phone 2 observable boot chain ==="
Write-Host "  boot image : $bootImage"
if ($SkipUserdata) {
    Write-Host "  userdata   : (skipped – rootfs already on device)"
} else {
    Write-Host "  userdata   : $rootfsImage"
}
Write-Host "  vbmeta     : (skipped – already disabled, no need to reflash)"
Write-Host ""

Invoke-Fastboot -Arguments @("flash", "boot_a", $bootImage)
Invoke-Fastboot -Arguments @("flash", "boot_b", $bootImage)

if (-not $SkipUserdata) {
    Invoke-Fastboot -Arguments @("flash", "userdata", $rootfsImage)
}

if ($Reboot) {
    Invoke-Fastboot -Arguments @("reboot")
    Write-Host ""
    Write-Host "Device rebooting. Waiting 15s for USB gadget serial to enumerate..."
    Start-Sleep -Seconds 15
    Write-Host ""
    Write-Host "Available COM ports:"
    [System.IO.Ports.SerialPort]::GetPortNames() | Sort-Object | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
    Write-Host "Then capture console with:"
    Write-Host "  .\scripts\06-capture-usb-console.ps1 -ListOnly"
    Write-Host "  .\scripts\06-capture-usb-console.ps1 -Port COM<N>"
}