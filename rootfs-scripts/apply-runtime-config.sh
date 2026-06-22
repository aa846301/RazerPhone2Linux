#!/bin/bash
# Idempotent runtime configuration overlay for the Razer Phone 2 rootfs.
#
# This script runs inside the target rootfs. Keep package installation out of
# this file so validation refreshes can update an existing image without
# replaying apt/dpkg in a QEMU chroot.

set -euo pipefail

if [ ! -x /usr/local/bin/usb-gadget-setup.sh ]; then
    echo "ERROR: /usr/local/bin/usb-gadget-setup.sh is missing or not executable"
    exit 1
fi

# NetworkManager owns WiFi. The USB gadget has a static address and must not be
# reconfigured by NetworkManager during boot.
mkdir -p /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/10-unmanaged-usb-gadget.conf << 'NM_USB_EOF'
[keyfile]
unmanaged-devices=interface-name:usb0
NM_USB_EOF

# ath10k_snoc may receive an invalid MAC from WLAN firmware and otherwise picks
# a new random address each boot. A device-specific factory MAC can be supplied
# through /etc/razerphone2linux/device.env; never bake one phone's MAC into a
# public image.
if [ -f /etc/razerphone2linux/device.env ]; then
    # shellcheck disable=SC1091
    source /etc/razerphone2linux/device.env
fi

if [[ "${RAZER_WLAN_MAC:-}" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] &&
   [ "$RAZER_WLAN_MAC" != "00:00:00:00:00:00" ]; then
    mkdir -p /etc/systemd/network
    cat > /etc/systemd/network/10-wlan0-mac.link << WLAN_LINK_EOF
[Match]
OriginalName=wlan0

[Link]
MACAddress=${RAZER_WLAN_MAC}
WLAN_LINK_EOF

    # NetworkManager must not randomise the MAC for scans or connections.
    cat > /etc/NetworkManager/conf.d/20-wlan-mac.conf << NM_WLAN_EOF
[device-wlan-rand]
match-device=interface-name:wlan0
wifi.scan-rand-mac-address=no

[connection-wlan-mac]
match-device=interface-name:wlan0
wifi.cloned-mac-address=${RAZER_WLAN_MAC}
NM_WLAN_EOF
else
    rm -f /etc/systemd/network/10-wlan0-mac.link
    rm -f /etc/NetworkManager/conf.d/20-wlan-mac.conf
fi

systemctl enable NetworkManager 2>/dev/null || true

cat > /etc/systemd/system/razer-wifi-ready.service <<'WIFI_READY_EOF'
[Unit]
Description=Wait for Razer Phone 2 WiFi before starting HelixScreen
Wants=NetworkManager.service tqftpserv.service rmtfs.service
After=systemd-modules-load.service NetworkManager.service tqftpserv.service rmtfs.service
Before=helixscreen.service

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/razer-wifi-ready
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
WIFI_READY_EOF
systemctl enable razer-wifi-ready.service 2>/dev/null || true

cat > /etc/systemd/system/resizefs.service << 'RESIZE_EOF'
[Unit]
Description=Expand root filesystem to fill partition
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/bash -c 'exec /usr/sbin/resize2fs $(findmnt -nvo SOURCE /)'
ExecStartPost=/usr/bin/systemctl disable resizefs.service
RemainAfterExit=true

[Install]
WantedBy=default.target
RESIZE_EOF
systemctl enable resizefs.service 2>/dev/null || true

cat > /etc/systemd/system/serial-getty@ttyMSM0.service << 'UART_EOF'
[Unit]
Description=Serial Console on ttyMSM0 (UART Debug)

[Service]
ExecStart=-/usr/sbin/agetty -L 115200 ttyMSM0 xterm-256color
Type=idle
Restart=always
RestartSec=0

[Install]
WantedBy=multi-user.target
UART_EOF
systemctl enable serial-getty@ttyMSM0.service 2>/dev/null || true

cat > /etc/systemd/system/serial-getty@ttyGS0.service << 'USB_EOF'
[Unit]
Description=Serial Console on ttyGS0 (USB Gadget)

[Service]
ExecStart=-/usr/sbin/agetty -L 115200 ttyGS0 xterm-256color
Type=idle
Restart=always
RestartSec=0

[Install]
WantedBy=multi-user.target
USB_EOF
systemctl enable serial-getty@ttyGS0.service 2>/dev/null || true

cat > /etc/systemd/system/usb-gadget.service << 'GADGET_SERVICE_EOF'
[Unit]
Description=USB ACM serial + NCM ethernet gadget
DefaultDependencies=no
After=systemd-modules-load.service local-fs.target
Before=sysinit.target
Before=serial-getty@ttyGS0.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/usb-gadget-setup.sh

[Install]
WantedBy=sysinit.target
GADGET_SERVICE_EOF
systemctl enable usb-gadget.service 2>/dev/null || true

mkdir -p /etc/systemd/system/serial-getty@ttyGS0.service.d
cat > /etc/systemd/system/serial-getty@ttyGS0.service.d/after-usb-gadget.conf << 'GADGET_DROPIN_EOF'
[Unit]
After=usb-gadget.service
Wants=usb-gadget.service
GADGET_DROPIN_EOF

cat > /etc/modules-load.d/razer-aura.conf << 'MODULES_EOF'
# Razer Phone 2 kernel modules
# Keep MDSS/DSI/MSM DRM out of the default path. The practical display path is
# bootloader framebuffer -> simpledrm/fbdev -> HelixScreen.
# WiFi
qcom_sysmon
qcom_q6v5_mss
ath10k_core
ath10k_snoc
# Touchscreen
rmi_i2c
MODULES_EOF

rm -f /etc/modprobe.d/razer-late-modem-test.conf

cat > /etc/modprobe.d/razer-no-kernel-pdmapper.conf << 'PDM_BLACKLIST_EOF'
# Follow the SDM845 userspace pd-mapper path. Keep the in-kernel mapper out if
# a future config accidentally builds it again.
blacklist qcom_pd_mapper
install qcom_pd_mapper /bin/false
PDM_BLACKLIST_EOF

cat > /usr/local/sbin/razer-wifi-late-start << 'LATE_WIFI_EOF'
#!/bin/sh
set -eu

MSS=""

if ! lsmod | grep -q '^qcom_q6v5_mss '; then
    modprobe qcom_q6v5_mss
fi
sleep 1

for r in /sys/class/remoteproc/remoteproc*; do
    [ -e "$r/name" ] || continue
    if [ "$(cat "$r/name" 2>/dev/null || true)" = "4080000.remoteproc" ]; then
        MSS="$r"
        break
    fi
done

if [ -z "$MSS" ]; then
    echo "MSS_NOT_FOUND"
    exit 3
fi

echo disabled > "$MSS/recovery" 2>/dev/null || true
systemctl reset-failed rmtfs.service 2>/dev/null || true
systemctl restart rmtfs.service 2>/dev/null || true
sleep 2

state="$(cat "$MSS/state" 2>/dev/null || true)"
echo "MSS state before=$state"

if [ "$state" != "running" ]; then
    echo start > "$MSS/state" || true
fi

sleep 2
echo "MSS state after start=$(cat "$MSS/state" 2>/dev/null || true)"

echo "=== load ath10k ==="
modprobe ath10k_core || true
modprobe ath10k_snoc || true

for i in 1 2 3 4 5 6 7 8; do
    echo "=== poll $i ==="
    cat "$MSS/name" "$MSS/state" "$MSS/recovery" 2>/dev/null || true
    ip -br link
    ls -la /sys/class/ieee80211 2>/dev/null || true
    qrtr-lookup 2>/dev/null | grep -E '(^ *69|WLFW|wlan|Service|  *66|  *43|  *14|  *64|4096)' || true
    sleep 5
done

echo "=== rmtfs ==="
journalctl -u rmtfs -b --no-pager | tail -120 || true

echo "=== tqftpserv ==="
journalctl -u tqftpserv -b --no-pager | tail -120 || true

echo "=== dmesg tail ==="
dmesg --time-format=iso |
    egrep -i 'remoteproc|q6v5|mpss|mba|modem|fatal|crash|ipa|ath10k|wlan|wifi|wlfw|qrtr|tftp|servreg|pd_mapper|rmtfs|glink|firmware' |
    tail -220
LATE_WIFI_EOF
chmod 0755 /usr/local/sbin/razer-wifi-late-start

if [ -f /usr/lib/firmware/qcom/sdm845/Razer/aura/wlanmdsp.mbn ]; then
    mkdir -p /usr/lib/firmware/qcom/sdm845 /lib/firmware/qcom/sdm845
    ln -sfn Razer/aura/wlanmdsp.mbn /usr/lib/firmware/qcom/sdm845/wlanmdsp.mbn
    ln -sfn Razer/aura/wlanmdsp.mbn /lib/firmware/qcom/sdm845/wlanmdsp.mbn

    mkdir -p /lib/firmware/image /readonly/firmware /readonly/vendor/firmware /readonly/vendor/firmware_mnt/image
    ln -sfn ../qcom/sdm845/Razer/aura/wlanmdsp.mbn /lib/firmware/image/wlanmdsp.mbn
    for jsn in modemr.jsn modemuw.jsn; do
        if [ -f "/usr/lib/firmware/qcom/sdm845/Razer/aura/$jsn" ]; then
            cp -f "/usr/lib/firmware/qcom/sdm845/Razer/aura/$jsn" "/lib/firmware/image/$jsn"
        fi
    done
    ln -sfn /lib/firmware/image /readonly/firmware/image
    ln -sfn /lib/firmware/qcom/sdm845/Razer/aura/wlanmdsp.mbn /readonly/vendor/firmware/wlanmdsp.mbn
    ln -sfn /lib/firmware/qcom/sdm845/Razer/aura/wlanmdsp.mbn /readonly/vendor/firmware_mnt/image/wlanmdsp.mbn
fi

if [ -x /usr/bin/tqftpserv ] || [ -x /usr/local/bin/tqftpserv ]; then
    if [ ! -f /etc/systemd/system/tqftpserv.service ] &&
       [ ! -f /usr/lib/systemd/system/tqftpserv.service ] &&
       [ ! -f /lib/systemd/system/tqftpserv.service ]; then
        cat > /etc/systemd/system/tqftpserv.service <<'TQFTP_SERVICE_EOF'
[Unit]
Description=QRTR TFTP service
After=qrtr-ns.service
Wants=qrtr-ns.service

[Service]
ExecStart=/usr/bin/tqftpserv
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
TQFTP_SERVICE_EOF
    fi
    systemctl enable tqftpserv.service 2>/dev/null || true
fi

if [ -x /usr/local/bin/pd-mapper ]; then
    cat > /etc/systemd/system/pd-mapper.service <<'PDM_SERVICE_EOF'
[Unit]
Description=Qualcomm Protection Domain Mapper
After=systemd-modules-load.service
Before=rmtfs.service tqftpserv.service

[Service]
ExecStart=/usr/local/bin/pd-mapper
Restart=always
RestartSec=1

[Install]
WantedBy=multi-user.target
PDM_SERVICE_EOF
    systemctl enable pd-mapper.service 2>/dev/null || true
else
    echo "WARNING: /usr/local/bin/pd-mapper missing; userspace pd-mapper service not installed"
fi

if [ -x /usr/local/bin/rmtfs-razer-test ]; then
    mkdir -p /etc/systemd/system/rmtfs.service.d
    cat > /etc/systemd/system/rmtfs.service.d/razer-nvdef.conf <<'RMTFS_RAZER_EOF'
[Service]
ExecStart=
ExecStart=/usr/local/bin/rmtfs-razer-test -r -P -s -v
RMTFS_RAZER_EOF
    if [ "${RAZER_MSS_DIAG_MANUAL:-0}" = "1" ]; then
        mkdir -p /etc/razerphone2linux
        cat > /etc/razerphone2linux/mss-diagnostic-mode <<'MSS_DIAG_EOF'
RAZER_MSS_DIAG_MANUAL=1
rmtfs.service is intentionally disabled.
Use /usr/local/sbin/razer-wifi-late-start or a controlled evidence script over SSH.
MSS_DIAG_EOF
        systemctl disable rmtfs.service 2>/dev/null || true
        systemctl reset-failed rmtfs.service 2>/dev/null || true
    else
        rm -f /etc/razerphone2linux/mss-diagnostic-mode 2>/dev/null || true
        systemctl enable rmtfs.service 2>/dev/null || true
    fi
fi

if [ -f /etc/systemd/system/helixscreen.service ]; then
    mkdir -p /etc/systemd/system/helixscreen.service.d
    cat > /etc/systemd/system/helixscreen.service.d/razer-wifi-ready.conf <<'HELIX_WIFI_EOF'
[Unit]
Wants=razer-wifi-ready.service NetworkManager.service
After=razer-wifi-ready.service NetworkManager.service
HELIX_WIFI_EOF

    cat > /etc/systemd/system/helixscreen.service.d/razer-fbdev.conf <<'HELIX_OVERRIDE_EOF'
[Service]
Environment="HELIX_DISPLAY_BACKEND=fbdev"
Environment="HELIX_DISPLAY_ROTATION=90"
Environment="HELIX_COLOR_SWAP_RB=1"
Environment="HELIX_TOUCH_DEVICE=/dev/input/event0"
Environment="HELIX_MOUSE_DEVICE="
HELIX_OVERRIDE_EOF

    cat > /etc/systemd/system/helixscreen.service.d/razer-keep-fbcon.conf <<'HELIX_FBCON_EOF'
[Service]
Environment="HELIX_KEEP_FBCON=1"
ExecStartPre=
ExecStartPre=/bin/sh -c 'systemctl stop display-sleep.service 2>/dev/null || true'
ExecStartPre=+/home/klipper/helixscreen/config/ensure-polkit-rule.sh klipper
ExecStartPre=+/bin/sh -c 'u=klipper; g=klipper; [ "$$u" != "root" ] && chown -Rh "$$u:$$g" "/home/klipper/helixscreen" 2>/dev/null || true'
ExecStartPre=+/bin/sh -c 'echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null || true'
HELIX_FBCON_EOF

    cat > /etc/systemd/system/helixscreen.service.d/razer-no-kd-graphics.conf <<'HELIX_NO_KD_EOF'
[Service]
AmbientCapabilities=
AmbientCapabilities=CAP_SYS_BOOT
HELIX_NO_KD_EOF

    if [ -f /home/klipper/helixscreen/bin/helix-launcher.sh ]; then
        cp -n /home/klipper/helixscreen/bin/helix-launcher.sh \
            /home/klipper/helixscreen/bin/helix-launcher.sh.before-razer-keep-fbcon 2>/dev/null || true
        python3 - <<'HELIX_PATCH_EOF'
from pathlib import Path

p = Path('/home/klipper/helixscreen/bin/helix-launcher.sh')
s = p.read_text()
old = '''# Unbind the kernel console from the framebuffer so it doesn't paint text
# over the UI. This affects vtcon1 (the fbcon driver); vtcon0 is the dummy.
for vtcon in /sys/class/vtconsole/vtcon*/bind; do
    [ -f "$vtcon" ] && echo 0 > "$vtcon" 2>/dev/null || true
done
'''
new = '''# Unbind the kernel console from the framebuffer so it doesn't paint text
# over the UI. This affects vtcon1 (the fbcon driver); vtcon0 is the dummy.
# Razer Phone 2 simplefb bring-up needs fbcon kept bound to preserve physical
# bootloader scanout while HelixScreen uses /dev/fb0.
if [ "${HELIX_KEEP_FBCON:-0}" != "1" ]; then
    for vtcon in /sys/class/vtconsole/vtcon*/bind; do
        [ -f "$vtcon" ] && echo 0 > "$vtcon" 2>/dev/null || true
    done
fi
'''
if 'HELIX_KEEP_FBCON' not in s and old in s:
    p.write_text(s.replace(old, new))
HELIX_PATCH_EOF
        chown klipper:klipper /home/klipper/helixscreen/bin/helix-launcher.sh 2>/dev/null || true
        chmod 0755 /home/klipper/helixscreen/bin/helix-launcher.sh
    fi

    if [ -f /home/klipper/helixscreen/config/settings.json ]; then
        python3 - <<'HELIX_SETTINGS_EOF'
import json
from pathlib import Path

p = Path('/home/klipper/helixscreen/config/settings.json')
data = json.loads(p.read_text())
data['dark_mode'] = False
# WiFi works now (MSS fih_nv share + HOST_CAP skip + tqftpserv v1.2), so let
# HelixScreen show and manage WiFi instead of hiding it.
data['wifi_expected'] = True
display = data.setdefault('display', {})
display['rotate'] = 90
display['rotation_probed'] = True
display['dim_sec'] = 86400
display['sleep_sec'] = 86400
display['dim_brightness'] = 100
p.write_text(json.dumps(data, indent=2) + '\n')
HELIX_SETTINGS_EOF
        chown klipper:klipper /home/klipper/helixscreen/config/settings.json 2>/dev/null || true
    fi

    systemctl mask display-sleep.service 2>/dev/null || true
    systemctl enable helixscreen.service 2>/dev/null || true
fi

cat > /usr/local/bin/razer-display-keepalive.sh <<'DISPLAY_KEEPALIVE_EOF'
#!/bin/bash
set -euo pipefail

# Keep the bootloader scanout path visible while MDSS/DSI remains disabled.
# Safety rule: do not raise panel backlight or WLED brightness automatically.
# The live device has shown unsafe full-brightness behavior when PMI8998 WLED is
# exposed without Razer-specific limits. Backlight tests must be explicit,
# manual, low brightness, and short lived.
if [ -w /sys/class/graphics/fb0/blank ]; then
    echo 0 > /sys/class/graphics/fb0/blank || true
fi
DISPLAY_KEEPALIVE_EOF
chmod 0755 /usr/local/bin/razer-display-keepalive.sh

cat > /etc/systemd/system/razer-display-keepalive.service <<'DISPLAY_SERVICE_EOF'
[Unit]
Description=Keep Razer bootloader framebuffer visible
After=systemd-udev-settle.service
Before=helixscreen.service
Wants=systemd-udev-settle.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/razer-display-keepalive.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
DISPLAY_SERVICE_EOF
systemctl enable razer-display-keepalive.service 2>/dev/null || true

systemctl disable apt-daily.timer 2>/dev/null || true
systemctl disable apt-daily-upgrade.timer 2>/dev/null || true
systemctl disable fstrim.timer 2>/dev/null || true

systemctl daemon-reload 2>/dev/null || true
