param(
    [switch]$DryRun
)
# ==========================================================================
# 08-finish-flash.ps1
# Flash ONLY vbmeta + reboot.  Run this after 07-flash-observable.ps1
# if the vbmeta step failed (boot_a and userdata are already flashed).
# ==========================================================================
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$workspace   = (Get-Item -LiteralPath $PSScriptRoot).Parent.FullName
$outputDir   = Join-Path $workspace "output"
$vbmetaImage = Join-Path $outputDir "vbmeta_disabled.img"

if (-not (Test-Path $vbmetaImage)) {
    Write-Error "vbmeta image not found: $vbmetaImage"
    Write-Host  "Run this in WSL first:"
    Write-Host  "  python3 /mnt/c/repo/razorphone2linux/wsl-scripts/make-vbmeta-disabled.py"
    exit 1
}

function Invoke-Fastboot {
    param([string[]]$Arguments)
    $txt = "fastboot " + ($Arguments -join " ")
    Write-Host $txt
    if ($DryRun) { return }
    & fastboot @Arguments
    if ($LASTEXITCODE -ne 0) { throw "fastboot failed: $txt" }
}

Write-Host "=== Finishing flash: vbmeta + reboot ==="

# Verify the image actually has AVB magic before sending to fastboot
$magic = [System.IO.File]::ReadAllBytes($vbmetaImage)[0..3]
$expected = [byte[]](0x41, 0x56, 0x42, 0x30)   # "AVB0"
for ($i = 0; $i -lt 4; $i++) {
    if ($magic[$i] -ne $expected[$i]) {
        Write-Error "vbmeta_disabled.img does not start with AVB0 magic."
        Write-Host  "Regenerate it in WSL:"
        Write-Host  "  python3 /mnt/c/repo/razorphone2linux/wsl-scripts/make-vbmeta-disabled.py"
        exit 1
    }
}
Write-Host "  [ok] AVB0 magic verified"

# Flash vbmeta WITHOUT --disable-verity / --disable-verification flags because
# the image was already created with flags=3 (both disabled).
Invoke-Fastboot -Arguments @("flash", "vbmeta", $vbmetaImage)

Write-Host "Rebooting..."
Invoke-Fastboot -Arguments @("reboot")
Write-Host "=== Done. Connect COM3 to capture boot log. ==="
