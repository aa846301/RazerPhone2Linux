param(
    [string]$HostName = "192.168.137.133",
    [string]$User = "klipper",
    [string]$Key = "C:\tmp\razer_usb_ed25519",
    [string]$SudoPassword = "klipper",
    [switch]$NoReboot
)

$ErrorActionPreference = "Stop"

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$releaseFile = Join-Path $repoRoot "output\kernel.release"
$moduleRoot = Join-Path $repoRoot "output\live-modules\pmos-mss-diag\kernel\drivers\remoteproc"

if (!(Test-Path -LiteralPath $releaseFile)) {
    throw "Missing output\kernel.release. Build pmos-kernel first."
}
if (!(Test-Path -LiteralPath $Key)) {
    throw "SSH key not found: $Key"
}

$modules = @(
    @{
        Source = Join-Path $moduleRoot "qcom_q6v5.ko.zst"
        Target = "kernel/drivers/remoteproc/qcom_q6v5.ko.zst"
    },
    @{
        Source = Join-Path $moduleRoot "qcom_q6v5_mss.ko.zst"
        Target = "kernel/drivers/remoteproc/qcom_q6v5_mss.ko.zst"
    }
)

foreach ($module in $modules) {
    if (!(Test-Path -LiteralPath $module.Source)) {
        throw "Module file not found: $($module.Source)"
    }
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
    throw "Kernel release mismatch. Phone=$actualRelease, output=$expectedRelease."
}

foreach ($module in $modules) {
    $moduleName = Split-Path -Leaf $module.Source
    $remoteTmp = "/tmp/$moduleName"
    $target = "/lib/modules/$actualRelease/$($module.Target)"

    & scp.exe @sshBase $module.Source "$remote`:$remoteTmp"
    if ($LASTEXITCODE -ne 0) {
        throw "scp failed for $moduleName."
    }

    $quotedPassword = $SudoPassword.Replace("'", "'\''")
    $installCmd = "printf '%s\n' '$quotedPassword' | sudo -S install -D -m 0644 '$remoteTmp' '$target'"
    & ssh.exe @sshBase $remote $installCmd
    if ($LASTEXITCODE -ne 0) {
        throw "remote install failed for $moduleName."
    }

    Write-Host "Installed $moduleName to $target"
}

$quotedPassword = $SudoPassword.Replace("'", "'\''")
$finalCmd = "printf '%s\n' '$quotedPassword' | sudo -S depmod -a '$actualRelease'"
if (!$NoReboot) {
    $finalCmd = "$finalCmd && printf '%s\n' '$quotedPassword' | sudo -S reboot"
}

& ssh.exe @sshBase $remote $finalCmd
if ($LASTEXITCODE -ne 0) {
    throw "remote depmod/reboot failed."
}

if ($NoReboot) {
    Write-Host "Installed pmOS MSS diagnostic modules. Reboot is still required before testing."
} else {
    Write-Host "Installed pmOS MSS diagnostic modules and requested reboot."
}
