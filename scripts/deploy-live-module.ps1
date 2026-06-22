param(
    [Parameter(Mandatory = $true)]
    [string]$Module,

    [Parameter(Mandatory = $true)]
    [string]$TargetRelativePath,

    [string]$HostName = "192.168.137.133",
    [string]$User = "klipper",
    [string]$Key = "C:\tmp\razer_usb_ed25519",
    [string]$SudoPassword = "",
    [switch]$AllowCoreModuleAbiRisk,
    [switch]$Reboot
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $Module)) {
    throw "Module file not found: $Module"
}

if (!(Test-Path -LiteralPath $Key)) {
    throw "SSH key not found: $Key"
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$releaseFile = Join-Path $repoRoot "output\kernel.release"
if (!(Test-Path -LiteralPath $releaseFile)) {
    throw "Missing output\kernel.release. Build the kernel first."
}

$expectedRelease = (Get-Content -LiteralPath $releaseFile -Raw).Trim()
$sshBase = @(
    "-i", $Key,
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=8",
    "-o", "StrictHostKeyChecking=no",
    "-o", "UserKnownHostsFile=C:\tmp\razer_known_hosts"
)

$remote = "$User@$HostName"
$actualRelease = (& ssh.exe @sshBase $remote "uname -r").Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($actualRelease)) {
    throw "Unable to read phone kernel release over SSH."
}

if ($actualRelease -ne $expectedRelease) {
    throw "Kernel release mismatch. Phone=$actualRelease, output=$expectedRelease. Do not live-copy modules across releases."
}

$moduleName = Split-Path -Leaf $Module
$coreAbiRiskModules = @(
    "qcom_q6v5.ko",
    "qcom_q6v5.ko.zst",
    "qcom_q6v5_mss.ko",
    "qcom_q6v5_mss.ko.zst",
    "qcom_pd_mapper.ko",
    "qcom_pd_mapper.ko.zst"
)
if (($coreAbiRiskModules -contains $moduleName) -and !$AllowCoreModuleAbiRisk) {
    throw @"
Refusing to live-deploy $moduleName by default.

These Qualcomm core modules are ABI-sensitive enough that matching uname -r is
not sufficient; a module from another kernel tree/flavor can fail at boot with:
  .gnu.linkonce.this_module section size must match the kernel's built struct module size

Use a boot/rootfs-matched build artifact, or rerun with -AllowCoreModuleAbiRisk
only after confirming the module was built from the exact kernel tree that
produced the currently flashed boot image.
"@
}
$remoteTmp = "/tmp/$moduleName"
$targetRel = $TargetRelativePath.Replace("\", "/").TrimStart("/")
$target = "/lib/modules/$actualRelease/$targetRel"

& scp.exe @sshBase $Module "$remote`:$remoteTmp"
if ($LASTEXITCODE -ne 0) {
    throw "scp failed."
}

$sudo = "sudo"
if (![string]::IsNullOrEmpty($SudoPassword)) {
    $quotedPassword = $SudoPassword.Replace("'", "'\''")
    $sudo = "printf '%s\n' '$quotedPassword' | sudo -S"
}

$installCmd = "$sudo install -D -m 0644 '$remoteTmp' '$target' && $sudo depmod -a '$actualRelease'"
if ($Reboot) {
    $installCmd = "$installCmd && $sudo reboot"
}

& ssh.exe @sshBase $remote $installCmd
if ($LASTEXITCODE -ne 0) {
    throw "remote install failed."
}

Write-Host "Installed $moduleName to $target"
if ($Reboot) {
    Write-Host "Phone reboot requested."
}
