# Sync hub-ui sources to the phone, build release there, and restart the UI (the runner relaunches it).
param([string]$Phone = "klipper@192.168.10.206")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    scp -q Cargo.toml build.rs "${Phone}:hub-ui/"
    scp -q src\*.rs "${Phone}:hub-ui/src/"
    scp -q ui\*.slint "${Phone}:hub-ui/ui/"
    scp -q deploy\* "${Phone}:hub-ui/deploy/"
    ssh $Phone @'
cd ~/hub-ui && find . -path ./target -prune -o -type f -print | xargs sed -i 's/\r$//'
if nice ~/.cargo/bin/cargo build --release 2>/tmp/hub-ui-build.log; then
  pkill -x hub-ui; sleep 4; pgrep -a hub-ui || echo "hub-ui not running"
  tail -3 "$XDG_RUNTIME_DIR/hub-ui.log" 2>/dev/null
else
  grep -E "^(error|warning)|-->" /tmp/hub-ui-build.log | head -30
fi
'@
} finally { Pop-Location }
