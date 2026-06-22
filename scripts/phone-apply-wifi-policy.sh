#!/bin/sh
set -eu

cat > /etc/modules-load.d/razer-aura.conf << 'MODULES_EOF'
# Razer Phone 2 kernel modules
# Keep MDSS/DSI/MSM DRM out of the default path. The practical display path is
# bootloader framebuffer -> simpledrm/fbdev -> HelixScreen.
# WiFi/MSS
qcom_sysmon
qcom_q6v5_mss
ath10k_core
ath10k_snoc
# Touchscreen
rmi_i2c
MODULES_EOF

rm -f /etc/modprobe.d/razer-late-modem-test.conf
cat > /etc/modprobe.d/razer-no-kernel-pdmapper.conf << 'PDM_BLACKLIST_EOF'
blacklist qcom_pd_mapper
install qcom_pd_mapper /bin/false
PDM_BLACKLIST_EOF

systemctl daemon-reload 2>/dev/null || true
systemctl enable pd-mapper.service 2>/dev/null || true
systemctl enable rmtfs.service 2>/dev/null || true

echo "wifi policy updated"
echo "=== /etc/modules-load.d/razer-aura.conf ==="
cat /etc/modules-load.d/razer-aura.conf
echo "=== pd-mapper enabled ==="
systemctl is-enabled pd-mapper.service 2>/dev/null || true
echo "=== rmtfs enabled ==="
systemctl is-enabled rmtfs.service 2>/dev/null || true
