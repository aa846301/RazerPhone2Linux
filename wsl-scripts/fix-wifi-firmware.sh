#!/bin/bash
# fix-wifi-firmware.sh
# Run ON the Razer Phone 2 to diagnose and fix WCN3990/ath10k_snoc WiFi.
#
# Usage (on device):
#   sudo bash /root/fix-wifi-firmware.sh           # full fix
#   sudo bash /root/fix-wifi-firmware.sh --diag    # diagnostics only
#
# Deploy via: scp wsl-scripts/fix-wifi-firmware.sh klipper@192.168.137.133:/tmp/
# Then:        ssh klipper@... "echo klipper | sudo -S bash /tmp/fix-wifi-firmware.sh"

set -uo pipefail

DIAG_ONLY=0
[ "${1:-}" = "--diag" ] && DIAG_ONLY=1

log() { echo "[wifi-fix] $*"; }
ok()  { echo "[wifi-fix] OK: $*"; }
err() { echo "[wifi-fix] FAIL: $*" >&2; }

log "=== WCN3990 / ath10k_snoc WiFi Fix ==="
log "Kernel: $(uname -r)"

# ── 1. Check ath10k modules ────────────────────────────────────────────────
log ""
log "--- Module status ---"
lsmod | grep -E "ath10k|wcn|snoc" || echo "  (none loaded)"

log ""
log "--- dmesg ath10k tail ---"
dmesg | grep -iE "ath10k|snoc|wcn3990" | tail -30 || true

# ── 2. Check firmware files ─────────────────────────────────────────────────
log ""
log "--- ath10k firmware (WCN3990/hw1.0) ---"
ls -lh /lib/firmware/ath10k/WCN3990/hw1.0/ 2>/dev/null || log "  MISSING: /lib/firmware/ath10k/WCN3990/hw1.0/"

log ""
log "--- MPSS / WCSS modem firmware (qcom/sdm845) ---"
ls /lib/firmware/qcom/sdm845/ 2>/dev/null | head -20 || log "  MISSING: /lib/firmware/qcom/sdm845/"

log ""
log "--- remoteproc state ---"
for rp in /sys/class/remoteproc/*/; do
    name=$(cat "$rp/name" 2>/dev/null || echo "?")
    state=$(cat "$rp/state" 2>/dev/null || echo "?")
    fw=$(cat "$rp/firmware" 2>/dev/null || echo "?")
    log "  $name: state=$state fw=$fw"
done

# ── 3. wlan0 link state ────────────────────────────────────────────────────
log ""
log "--- Network interfaces ---"
ip -brief link

# ── 4. Fix phase (if not diag-only) ────────────────────────────────────────
if [ "$DIAG_ONLY" -eq 1 ]; then
    log ""
    log "Diagnostics only - exiting."
    exit 0
fi

log ""
log "=== Applying fixes ==="

# 4a. Ensure ath10k autoload
if [ ! -f /etc/modules-load.d/ath10k.conf ]; then
    log "Creating /etc/modules-load.d/ath10k.conf..."
    printf 'ath10k_core\nath10k_snoc\n' > /etc/modules-load.d/ath10k.conf
    ok "ath10k autoload configured"
else
    log "ath10k.conf already exists."
fi

# 4b. Try to load ath10k_snoc now
if ! lsmod | grep -q ath10k_snoc; then
    log "Loading ath10k_core..."
    modprobe ath10k_core 2>&1 || err "ath10k_core load failed"
    log "Loading ath10k_snoc..."
    modprobe ath10k_snoc 2>&1 || err "ath10k_snoc load failed"
    sleep 3
else
    log "ath10k_snoc already loaded."
fi

# 4c. Check wlan0 appeared
if ip link show wlan0 >/dev/null 2>&1; then
    ok "wlan0 is present"
    ip -brief addr show wlan0
else
    err "wlan0 NOT present after module load"
    log ""
    log "--- Recent ath10k dmesg ---"
    dmesg | grep -iE "ath10k|snoc|wcn3990" | tail -20
    log ""
    log "--- Firmware load errors ---"
    dmesg | grep -i "firmware" | tail -10
    log ""
    log "Possible causes:"
    log "  1. Missing /lib/firmware/ath10k/WCN3990/hw1.0/firmware-5.bin"
    log "  2. Missing /lib/firmware/ath10k/WCN3990/hw1.0/board.bin"
    log "  3. MPSS remoteproc not started (check: cat /sys/class/remoteproc/*/state)"
    log "  4. Kernel config: CONFIG_ATH10K_SNOC not enabled"
    log ""
    log "If firmware is missing, extract from Android ROM:"
    log "  See wsl-scripts/extract-fw-from-rom.sh"
    exit 1
fi

# 4d. Bring up wlan0 if down
wlan_state=$(ip -brief link show wlan0 | awk '{print $2}')
if [ "$wlan_state" != "UP" ]; then
    log "Bringing up wlan0..."
    ip link set wlan0 up 2>&1 || err "ip link set wlan0 up failed"
    sleep 1
fi

# 4e. NetworkManager check
if systemctl is-active --quiet NetworkManager; then
    log "NetworkManager active. Available WiFi:"
    nmcli dev wifi list 2>/dev/null | head -10 || true
else
    log "NetworkManager not active - starting..."
    systemctl start NetworkManager && sleep 2
fi

log ""
ok "WiFi fix complete. wlan0 is UP."
log "To connect: nmcli dev wifi connect \"<SSID>\" password \"<PASS>\""
log "Or run:     .\scripts\apply-fixes-ssh.ps1 -WifiConnect"
