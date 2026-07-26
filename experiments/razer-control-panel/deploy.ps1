param(
    [string]$Distro = "Ubuntu-24.04",
    [string]$HostName = "192.168.137.133",
    [string]$UserName = "klipper",
    [string]$IdentityFile = "C:\tmp\razer_usb_ed25519",
    [string]$KnownHostsFile = "C:\tmp\razer_control_panel_known_hosts",
    [string]$SudoPassword = "klipper",
    [string]$CryptoDashboardPath = "",
    [switch]$SkipCryptoDashboard
)

$ErrorActionPreference = "Stop"
$experimentDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repositoryDir = Split-Path -Parent (Split-Path -Parent $experimentDir)
if ([string]::IsNullOrWhiteSpace($CryptoDashboardPath)) {
    $CryptoDashboardPath = Join-Path (Split-Path -Parent $repositoryDir) "crypto_dashboard"
}
$kmsSource = Join-Path $experimentDir "razer-kms-present.c"
$kmsBinary = Join-Path $env:TEMP "razer-kms-present-arm64"
$cameraSource = Join-Path $experimentDir "razer-camera-preview.c"
$cameraBinary = Join-Path $env:TEMP "razer-camera-preview-arm64"
$hapticSource = Join-Path $experimentDir "razer-haptic-ff.c"
$hapticBinary = Join-Path $env:TEMP "razer-haptic-ff-arm64"
$cryptoBinary = Join-Path $env:TEMP "crypto-dashboard-linux-arm64"
$cryptoBundle = Join-Path $env:TEMP "crypto-dashboard-assets.tar.gz"
$cryptoPort = 8080

function Build-WslArm64(
    [string]$Source,
    [string]$Binary,
    [string]$CompilerArguments,
    [string]$Description
) {
    # Feed source through stdin and return the binary as base64. This avoids
    # depending on WSL's /mnt/c or /mnt/d DrvFS mounts, which can be stalled
    # even while the distro and compiler themselves are healthy.
    $compileCommand = @'
set -e
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
aarch64-linux-gnu-gcc {0} -x c -o "$tmp" -
base64 -w0 "$tmp"
'@ -f $CompilerArguments
    $sourceText = [IO.File]::ReadAllText($Source)
    $encoded = ($sourceText | & wsl.exe -d $Distro --exec bash -lc $compileCommand) -join ""
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($encoded)) {
        throw "Failed to cross-compile $Description"
    }
    try {
        [IO.File]::WriteAllBytes($Binary, [Convert]::FromBase64String($encoded))
    }
    catch {
        throw "Failed to receive the compiled ${Description}: $($_.Exception.Message)"
    }
}

function Test-TcpPort(
    [string]$Address,
    [int]$Port,
    [int]$TimeoutMilliseconds = 3000
) {
    $client = [Net.Sockets.TcpClient]::new()
    try {
        $connect = $client.ConnectAsync($Address, $Port)
        return $connect.Wait($TimeoutMilliseconds) -and $client.Connected
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

if (!(Test-TcpPort $HostName 22)) {
    throw "Phone SSH is unreachable at ${HostName}:22; reconnect/wake the device before deployment"
}

Build-WslArm64 $kmsSource $kmsBinary `
    "-O2 -Wall -Wextra -I /usr/include/drm" "the DRM/KMS presenter"
Build-WslArm64 $cameraSource $cameraBinary `
    "-O2 -Wall -Wextra" "the camera preview helper"
Build-WslArm64 $hapticSource $hapticBinary `
    "-O2 -Wall -Wextra" "the haptics helper"

if (!$SkipCryptoDashboard) {
    $cryptoConfig = Join-Path $CryptoDashboardPath "config.json"
    $cryptoWeb = Join-Path $CryptoDashboardPath "web"
    $cryptoMigration = Join-Path $CryptoDashboardPath "db\migrations\001_init.sql"
    foreach ($requiredPath in @($cryptoConfig, $cryptoWeb, $cryptoMigration)) {
        if (!(Test-Path -LiteralPath $requiredPath)) {
            throw "Crypto Dashboard input is missing: $requiredPath"
        }
    }
    $cryptoSettings = Get-Content -Raw -LiteralPath $cryptoConfig | ConvertFrom-Json
    $cryptoPort = [int]$cryptoSettings.server.port
    if ($cryptoPort -lt 1 -or $cryptoPort -gt 65535) {
        throw "Crypto Dashboard server.port is invalid: $cryptoPort"
    }
    if (!(Get-Command go.exe -ErrorAction SilentlyContinue)) {
        throw "Go is required to build Crypto Dashboard"
    }
    if (!(Get-Command tar.exe -ErrorAction SilentlyContinue)) {
        throw "Windows tar is required to package Crypto Dashboard assets"
    }

    Write-Output "Testing Crypto Dashboard APIs..."
    Push-Location $CryptoDashboardPath
    try {
        & go.exe test ./...
        if ($LASTEXITCODE -ne 0) {
            throw "Crypto Dashboard API tests failed"
        }

        $previousGoos = $env:GOOS
        $previousGoarch = $env:GOARCH
        $previousCgo = $env:CGO_ENABLED
        try {
            $env:GOOS = "linux"
            $env:GOARCH = "arm64"
            $env:CGO_ENABLED = "0"
            & go.exe build -trimpath -ldflags "-s -w" `
                -o $cryptoBinary ./cmd/server
            if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $cryptoBinary)) {
                throw "Failed to build Crypto Dashboard for linux/arm64"
            }
        }
        finally {
            $env:GOOS = $previousGoos
            $env:GOARCH = $previousGoarch
            $env:CGO_ENABLED = $previousCgo
        }
    }
    finally {
        Pop-Location
    }

    & tar.exe -czf $cryptoBundle -C $CryptoDashboardPath web db/migrations
    if ($LASTEXITCODE -ne 0 -or !(Test-Path -LiteralPath $cryptoBundle)) {
        throw "Failed to package Crypto Dashboard web and migration assets"
    }
}

if (!(Test-Path -LiteralPath $IdentityFile)) {
    $defaultIdentity = Join-Path $env:USERPROFILE ".ssh\id_ed25519"
    if (Test-Path -LiteralPath $defaultIdentity) {
        Write-Output "Requested identity is missing; using $defaultIdentity"
        $IdentityFile = $defaultIdentity
    }
}

$sshOptions = @(
    "-i", $IdentityFile,
    "-o", "BatchMode=yes",
    "-o", "ConnectTimeout=10",
    "-o", "StrictHostKeyChecking=accept-new",
    "-o", "UserKnownHostsFile=$KnownHostsFile"
)
$target = "${UserName}@${HostName}"

$savedErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = "Continue"
& ssh @sshOptions $target "true" 2>$null
$keyLoginExitCode = $LASTEXITCODE
$ErrorActionPreference = $savedErrorActionPreference
if ($keyLoginExitCode -ne 0) {
    $plink = "C:\Program Files\PuTTY\plink.exe"
    $publicKeyFile = "${IdentityFile}.pub"
    if (!(Test-Path -LiteralPath $plink) -or !(Test-Path -LiteralPath $publicKeyFile)) {
        throw "Key login failed and PuTTY/public key is unavailable for password bootstrap"
    }

    $scanFile = [IO.Path]::GetTempFileName()
    try {
        $savedErrorActionPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"
            # Windows ssh-keyscan may not support the KEX preferred by a new
            # Ubuntu host. A normal OpenSSH handshake still records the host
            # key before the expected authentication failure.
            & ssh `
                -o BatchMode=yes `
                -o ConnectTimeout=10 `
                -o PreferredAuthentications=none `
                -o StrictHostKeyChecking=accept-new `
                -o UserKnownHostsFile=$scanFile `
                $target "true" 2>$null
        }
        finally {
            $ErrorActionPreference = $savedErrorActionPreference
        }
        if ((Get-Item -LiteralPath $scanFile).Length -eq 0) {
            throw "Unable to record the phone SSH host key"
        }
        $fingerprintLine = & ssh-keygen -lf $scanFile
        if ($LASTEXITCODE -ne 0 -or !$fingerprintLine) {
            throw "Unable to read the phone SSH host key"
        }
        $fingerprint = ($fingerprintLine -split "\s+")[1]
        $publicKey = [IO.File]::ReadAllBytes($publicKeyFile)
        $encodedKey = [Convert]::ToBase64String($publicKey)
        $bootstrap = "umask 077; mkdir -p ~/.ssh; echo '$encodedKey' | base64 -d >> ~/.ssh/authorized_keys; sort -u -o ~/.ssh/authorized_keys ~/.ssh/authorized_keys; chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys"
        & $plink -ssh -batch -pw $SudoPassword -hostkey $fingerprint $target $bootstrap
        if ($LASTEXITCODE -ne 0) {
            throw "Password bootstrap failed"
        }

        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $KnownHostsFile) | Out-Null
        Copy-Item -Force -LiteralPath $scanFile -Destination $KnownHostsFile
    }
    finally {
        Remove-Item -Force -LiteralPath $scanFile -ErrorAction SilentlyContinue
    }
}

$copyFiles = @(
    (Join-Path $experimentDir "razer-control-panel.py"),
    (Join-Path $experimentDir "razer-control-panel.service"),
    (Join-Path $experimentDir "crypto-dashboard.service"),
    (Join-Path $experimentDir "razer-shutdown-console.sh"),
    (Join-Path $experimentDir "razer-camera-launch.sh"),
    (Join-Path $experimentDir "razer-haptic-test.sh"),
    (Join-Path $experimentDir "razer-audio-test.sh"),
    $kmsBinary,
    $cameraBinary,
    $hapticBinary
)
if (!$SkipCryptoDashboard) {
    $copyFiles += @(
        $cryptoBinary,
        (Join-Path $CryptoDashboardPath "config.json"),
        $cryptoBundle
    )
}
& scp @sshOptions @copyFiles "${target}:/tmp/"
if ($LASTEXITCODE -ne 0) {
    throw "Failed to copy the control panel files"
}

$cryptoInstall = ""
$cryptoStart = ""
if (!$SkipCryptoDashboard) {
    $cryptoInstall = @"
printf '%s' "`$password" | sudo -S systemctl stop crypto-dashboard.service 2>/dev/null || true
printf '%s' "`$password" | sudo -S install -d -o klipper -g klipper -m 0750 /opt/crypto-dashboard
printf '%s' "`$password" | sudo -S install -m 0755 /tmp/crypto-dashboard-linux-arm64 /opt/crypto-dashboard/crypto-dashboard
printf '%s' "`$password" | sudo -S install -m 0600 -o klipper -g klipper /tmp/config.json /opt/crypto-dashboard/config.json
printf '%s' "`$password" | sudo -S tar -xzf /tmp/crypto-dashboard-assets.tar.gz -C /opt/crypto-dashboard
printf '%s' "`$password" | sudo -S install -d -o klipper -g klipper -m 0750 /opt/crypto-dashboard/data
printf '%s' "`$password" | sudo -S chown -R klipper:klipper /opt/crypto-dashboard/web /opt/crypto-dashboard/db /opt/crypto-dashboard/data
"@
    $cryptoStart = @"
printf '%s' "`$password" | sudo -S systemctl start crypto-dashboard.service
crypto_ready=0
for attempt in `$(seq 1 60); do
    if curl -fsS http://127.0.0.1:${cryptoPort}/api/v1/status 2>/dev/null | grep -q '"success":true'; then
        crypto_ready=1
        break
    fi
    sleep 1
done
if [ "`$crypto_ready" != "1" ]; then
    printf '%s' "`$password" | sudo -S journalctl -u crypto-dashboard.service --no-pager -n 80
    exit 1
fi
echo "Crypto Dashboard API is ready on port ${cryptoPort}."
systemctl --no-pager --full status crypto-dashboard.service
"@
}

$encodedPassword = [Convert]::ToBase64String(
    [Text.Encoding]::UTF8.GetBytes("$SudoPassword`n"))
$remote = @"
password=`$(printf '%s' '$encodedPassword' | base64 -d)
printf '%s' "`$password" | sudo -S install -m 0755 /tmp/razer-control-panel.py /usr/local/sbin/razer-control-panel
printf '%s' "`$password" | sudo -S install -m 0644 /tmp/razer-control-panel.service /etc/systemd/system/razer-control-panel.service
printf '%s' "`$password" | sudo -S install -m 0644 /tmp/crypto-dashboard.service /etc/systemd/system/crypto-dashboard.service
printf '%s' "`$password" | sudo -S install -m 0755 /tmp/razer-shutdown-console.sh /usr/local/sbin/razer-shutdown-console
printf '%s' "`$password" | sudo -S install -m 0755 /tmp/razer-kms-present-arm64 /usr/local/sbin/razer-kms-present
printf '%s' "`$password" | sudo -S install -m 0755 /tmp/razer-camera-preview-arm64 /usr/local/sbin/razer-camera-preview
printf '%s' "`$password" | sudo -S install -m 0755 /tmp/razer-haptic-ff-arm64 /usr/local/sbin/razer-haptic-ff
printf '%s' "`$password" | sudo -S install -m 0755 /tmp/razer-camera-launch.sh /usr/local/sbin/razer-camera-launch
printf '%s' "`$password" | sudo -S install -m 0755 /tmp/razer-haptic-test.sh /usr/local/sbin/razer-haptic-test
printf '%s' "`$password" | sudo -S install -m 0755 /tmp/razer-audio-test.sh /usr/local/sbin/razer-audio-test
if ! command -v media-ctl >/dev/null || ! command -v v4l2-ctl >/dev/null || ! command -v speaker-test >/dev/null; then
    printf '%s' "`$password" | sudo -S apt-get update
    printf '%s' "`$password" | sudo -S apt-get install -y v4l-utils alsa-utils
fi
printf '%s' "`$password" | sudo -S systemctl disable --now razer-panel-idle-blank.service
printf '%s' "`$password" | sudo -S systemctl disable --now getty@tty1.service
printf '%s' "`$password" | sudo -S systemctl daemon-reload
printf '%s' "`$password" | sudo -S systemctl enable razer-control-panel.service
printf '%s' "`$password" | sudo -S systemctl restart razer-control-panel.service
$cryptoInstall
$cryptoStart
systemctl --no-pager --full status razer-control-panel.service
"@
$remote = $remote.Replace("`r`n", "`n")

& ssh @sshOptions $target $remote
if ($LASTEXITCODE -ne 0) {
    throw "Failed to install the control panel service"
}

Remove-Item -Force -LiteralPath $kmsBinary -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath $cameraBinary -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath $hapticBinary -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath $cryptoBinary -ErrorAction SilentlyContinue
Remove-Item -Force -LiteralPath $cryptoBundle -ErrorAction SilentlyContinue
