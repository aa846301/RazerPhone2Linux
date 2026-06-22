[CmdletBinding()]
param(
    [ValidateSet(
        "all",
        "validate",
        "validate-boot",
        "kernel",
        "rootfs",
        "refresh-rootfs",
        "boot",
        "pmos-kernel",
        "pmos-contrast",
        "pmos-mss-diag"
    )]
    [string]$Mode = "all",

    [ValidateSet("base", "printer")]
    [string]$Profile = "printer",

    [string]$UbuntuMirror = "https://ports.ubuntu.com/ubuntu-ports",

    [string]$WslRepo = "",
    [string]$WslWorkdir = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($WslRepo)) {
    $windowsRepo = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path.Replace("\", "/")
    $WslRepo = (& wsl.exe -- wslpath -a -u $windowsRepo).Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($WslRepo)) {
        throw "Could not convert the repository path for WSL."
    }
}

if ([string]::IsNullOrWhiteSpace($WslWorkdir)) {
    $WslWorkdir = (& wsl.exe -- bash -lc 'printf "%s" "$HOME/razorphone2linux"').Trim()
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($WslWorkdir)) {
        throw "Could not determine the WSL user work directory."
    }
}

function Invoke-WslUser {
    param([Parameter(Mandatory)][string]$Command)

    & wsl.exe -- bash -lc $Command
    if ($LASTEXITCODE -ne 0) {
        throw "WSL user phase failed with exit code $LASTEXITCODE."
    }
}

function Invoke-WslRoot {
    param([Parameter(Mandatory)][string]$Command)

    & wsl.exe -u root -- bash -lc $Command
    if ($LASTEXITCODE -ne 0) {
        throw "WSL root phase failed with exit code $LASTEXITCODE."
    }
}

$repo = $WslRepo.Replace("'", "'\''")
$workdir = $WslWorkdir.Replace("'", "'\''")
$mirror = $UbuntuMirror.Replace("'", "'\''")
$userPrefix = "cd '$repo' && RAZER_WORKDIR='$workdir' RAZER_IMAGE_PROFILE='$Profile' RAZER_UBUNTU_MIRROR='$mirror'"
$rootPrefix = "cd '$repo' && RAZER_WORKDIR='$workdir' RAZER_IMAGE_PROFILE='$Profile' RAZER_UBUNTU_MIRROR='$mirror'"

switch ($Mode) {
    "all" {
        Invoke-WslUser "$userPrefix bash scripts/02-build-kernel.sh"
        Invoke-WslRoot "$rootPrefix bash scripts/03-build-rootfs.sh"
        Invoke-WslUser "$userPrefix bash scripts/04-make-boot-image.sh"
    }
    "validate" {
        Invoke-WslUser "$userPrefix bash scripts/02-build-kernel.sh"
        Invoke-WslRoot "$rootPrefix bash scripts/03-refresh-rootfs.sh"
        Invoke-WslUser "$userPrefix bash scripts/04-make-boot-image.sh"
    }
    "pmos-contrast" {
        Invoke-WslUser "$userPrefix bash scripts/02-build-pmos-kernel-contrast.sh"
        Invoke-WslRoot "$rootPrefix bash scripts/03-refresh-rootfs.sh"
        Invoke-WslUser "$userPrefix bash scripts/04-make-boot-image.sh"
    }
    "pmos-mss-diag" {
        Invoke-WslUser "$userPrefix PMOS_APPLY_DIAG_PATCHES=1 bash scripts/02-build-pmos-kernel-contrast.sh"
        Invoke-WslRoot "$rootPrefix RAZER_MSS_DIAG_MANUAL=1 bash scripts/03-refresh-rootfs.sh"
        Invoke-WslUser "$userPrefix bash scripts/04-make-boot-image.sh && echo pmos-mss-diag > 'output/$Profile/kernel.flavor' && mkdir -p '$workdir/output/$Profile' && echo pmos-mss-diag > '$workdir/output/$Profile/kernel.flavor'"
    }
    "rootfs" {
        Invoke-WslRoot "$rootPrefix bash scripts/03-build-rootfs.sh"
    }
    "refresh-rootfs" {
        Invoke-WslRoot "$rootPrefix bash scripts/03-refresh-rootfs.sh"
    }
    default {
        Invoke-WslUser "$userPrefix bash scripts/build-all.sh '$Mode'"
    }
}
