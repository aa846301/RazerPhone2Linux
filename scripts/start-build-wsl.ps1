[CmdletBinding()]
param(
    [ValidateSet("all", "validate", "validate-boot", "kernel", "rootfs", "refresh-rootfs", "boot")]
    [string]$Mode = "kernel",

    [string]$Distro = "Ubuntu-24.04",

    [switch]$NativePanel
)

$ErrorActionPreference = "Stop"
$repo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$logDir = Join-Path $repo "output\background-build"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$stdout = Join-Path $logDir "stdout.log"
$stderr = Join-Path $logDir "stderr.log"
$pidFile = Join-Path $logDir "pid"
$wrapper = Join-Path $PSScriptRoot "build-all-wsl.ps1"

$arguments = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-File", $wrapper,
    "-Mode", $Mode,
    "-Distro", $Distro
)
if ($NativePanel) {
    $arguments += "-NativePanel"
}

$process = Start-Process -FilePath "powershell.exe" `
    -ArgumentList $arguments `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr `
    -WindowStyle Hidden `
    -PassThru

Set-Content -LiteralPath $pidFile -Value $process.Id -NoNewline

Write-Output "Started WSL $Mode build as PID $($process.Id)."
Write-Output "Wrapper log: $stdout"
Write-Output "Error log:   $stderr"
Write-Output "Kernel log:  /home/klipper/razorphone2linux/output/base/build.log"
