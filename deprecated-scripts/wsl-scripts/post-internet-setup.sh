#!/bin/bash
# post-internet-setup.sh
# Run this on the Razer Phone 2 once USB NCM internet sharing is active.
# Usage:
#   bash /root/post-internet-setup.sh          # Phase 1-4 (internet + packages + WiFi + KIAUH helper)
#   bash /root/post-internet-setup.sh --helix  # Phase 5 (install HelixScreen after Moonraker is active)
#   bash /root/post-internet-setup.sh --helixscreen
#   bash /root/post-internet-setup.sh --klipperscreen  # legacy alias for --helix

LOGFILE=/root/setup-helix.log
exec > >(tee -a "$LOGFILE") 2>&1

log() { echo "[$(date '+%H:%M:%S')] $*"; }

USB_PROXY_URL="${USB_PROXY_URL:-http://localhost:3128/}"

enable_usb_proxy() {
    export http_proxy="$USB_PROXY_URL"
    export https_proxy="$USB_PROXY_URL"
    export HTTP_PROXY="$USB_PROXY_URL"
    export HTTPS_PROXY="$USB_PROXY_URL"

    mkdir -p /etc/apt/apt.conf.d
    cat > /etc/apt/apt.conf.d/95usb-ncm-proxy <<APTPROXYEOF
Acquire::http::Proxy "$USB_PROXY_URL";
Acquire::https::Proxy "$USB_PROXY_URL";
APTPROXYEOF
}

proxy_online() {
    curl -fsSI --connect-timeout 5 --max-time 15 -x "$USB_PROXY_URL" https://example.com >/dev/null 2>&1
}

# ── Phase 5: Install HelixScreen ──────────────────────────────
install_helix() {
    log "=== Phase 5: Installing HelixScreen ==="

    if ! systemctl is-active --quiet moonraker 2>/dev/null; then
        log "WARNING: moonraker.service not active."
        log "  Please install and start Klipper + Moonraker first."
        exit 1
    fi
    log "Moonraker is active."

    enable_usb_proxy
    export DEBIAN_FRONTEND=noninteractive
    log "Installing HelixScreen dependencies..."
    apt-get update -q
    apt-get install -y --no-install-recommends \
        curl \
        ca-certificates \
        libturbojpeg

    log "Running HelixScreen one-line installer..."
    curl -sSL https://raw.githubusercontent.com/prestonbrown/helixscreen/main/scripts/install.sh | sh

    log "=== Phase 6: Configuring HelixScreen for Razer Phone 2 display ==="

    HELIX_CFG=""
    for f in \
        /home/klipper/helixscreen/config/settings.json \
        /home/klipper/printer_data/config/helixscreen/settings.json \
        /opt/helixscreen/config/settings.json \
        /root/helixscreen/config/settings.json; do
        [ -f "$f" ] && HELIX_CFG="$f" && break
    done

    if [ -n "$HELIX_CFG" ]; then
        python3 - "$HELIX_CFG" <<'PYEOF'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text())

data["active_printer_id"] = data.get("active_printer_id", "default")
data["wizard_completed"] = True
data["wifi_expected"] = False
data.setdefault("display", {})
data["display"]["drm_device"] = ""

printers = data.setdefault("printers", {})
default = printers.setdefault("default", {})
default["moonraker_host"] = "127.0.0.1"
default["moonraker_port"] = 7125
default["moonraker_api_key"] = False

path.write_text(json.dumps(data, indent=2, sort_keys=False) + "\n")
PYEOF
        chown klipper:klipper "$HELIX_CFG" 2>/dev/null || true
        log "Settings updated: $HELIX_CFG"
    else
        log "WARNING: HelixScreen settings.json path not found."
    fi

    if systemctl cat helixscreen >/dev/null 2>&1; then
        mkdir -p /etc/systemd/system/helixscreen.service.d
        cat > /etc/systemd/system/helixscreen.service.d/fbdev.conf <<'OVERRIDEEOF'
[Service]
Environment="HELIX_DISPLAY_BACKEND=fbdev"
OVERRIDEEOF
        systemctl daemon-reload
        systemctl restart helixscreen || true
        sleep 2
        log "HelixScreen status: $(systemctl is-active helixscreen)"
    else
        log "WARNING: helixscreen.service not found after installer."
    fi

    log ""
    log "================================================================"
    log " HelixScreen installation complete!"
    log " Service: systemctl status helixscreen"
    log " Logs:    journalctl -u helixscreen -n 80"
    log " Check display: ls -la /dev/fb*"
    log "================================================================"
    exit 0
}

case "${1:-}" in
    --helix|--helixscreen|--klipperscreen)
        install_helix
        ;;
esac

# ── Phase 1: Wait for internet ─────────────────────────────────
log "=== Phase 1: Waiting for internet (USB NCM ICS) ==="
enable_usb_proxy
ONLINE=0
for i in $(seq 1 30); do
    if ping -c1 -W2 8.8.8.8 >/dev/null 2>&1 || proxy_online; then
        ONLINE=1; break
    fi
    log "  No internet yet ($i/30)... Is Windows ICS enabled, or is the USB proxy tunnel active at $USB_PROXY_URL?"
    sleep 5
done

if [ "$ONLINE" -eq 0 ]; then
    log "ERROR: No internet after 150s."
    log ""
    log "On Windows, either enable ICS or keep the SSH reverse proxy tunnel active:"
    log "  1. Open 'Network Connections' (ncpa.cpl)"
    log "  2. Right-click your WiFi adapter -> Properties -> Sharing tab"
    log "  3. Check: 'Allow other network users to connect through this...'"
    log "  4. Select the 'Remote NDIS' or 'CDC NCM' adapter from the dropdown"
    log "  5. Or run: ssh -R 3128:127.0.0.1:3128 klipper@<phone-usb-ip>"
    exit 1
fi
log "Internet OK!"

# ── Phase 2: Install packages ─────────────────────────────────
log "=== Phase 2: Installing required packages ==="
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    linux-firmware \
    git \
    curl \
    wget \
    ca-certificates \
    python3-venv \
    python3-pip \
    network-manager \
    libturbojpeg
log "Packages installed."

# ── Phase 3: Try WiFi ─────────────────────────────────────────
log "=== Phase 3: Trying WiFi (CimforceTw-Guest) ==="
modprobe ath10k_snoc 2>/dev/null || true
sleep 3
nmcli device wifi rescan 2>/dev/null || true
sleep 5

if nmcli device wifi connect "CimforceTw-Guest" password "61828630" 2>&1; then
    log "WiFi connected!"
    sleep 3
    IP=$(ip -4 addr show wlan0 2>/dev/null | grep -oP '(?<=inet )\S+' | head -1 || true)
    log "wlan0 IP: ${IP:-pending}"
else
    log "WiFi not available yet (firmware may need a reboot after linux-firmware install)."
    log "Continuing via USB NCM..."
fi

# ── Phase 4: KIAUH setup ──────────────────────────────────────
log "=== Phase 4: Setting up KIAUH ==="
cd /root
if [ ! -d kiauh ]; then
    git clone https://github.com/dw-0/kiauh.git
fi
log "KIAUH ready at /root/kiauh"

log ""
log "================================================================"
log " NEXT STEPS (run interactively):"
log ""
log " 1. Install Klipper + Moonraker:"
log "      /root/kiauh/kiauh.sh"
log "    In menu: 1) Install -> 1) Klipper (Python 3, 1 instance)"
log "             1) Install -> 2) Moonraker"
log "             Q to quit"
log ""
log " 2. After Moonraker is active, install HelixScreen:"
log "      bash /root/post-internet-setup.sh --helix"
log "================================================================"
log ""
log "Log saved to: $LOGFILE"
