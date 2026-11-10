#!/bin/bash
# Install Phosh as the fallback desktop WITHOUT letting any service start or take the display during install.
set -e
exec > /tmp/phosh-install.log 2>&1
printf '#!/bin/sh\nexit 101\n' | sudo tee /usr/sbin/policy-rc.d >/dev/null
sudo chmod 755 /usr/sbin/policy-rc.d
trap 'sudo rm -f /usr/sbin/policy-rc.d' EXIT
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  phosh phoc phosh-osk-stub gnome-control-center gnome-console network-manager-gnome \
  phosh-mobile-settings gnome-settings-daemon upower iio-sensor-proxy || \
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends phosh phoc phosh-osk-stub gnome-control-center gnome-console
# Never auto-start: the hub session owns the display; phosh is started only as fallback.
for u in phosh.service gdm.service gdm3.service lightdm.service greetd.service; do
  sudo systemctl disable "$u" 2>/dev/null || true
done
systemctl list-unit-files --no-pager | grep -E "^(phosh|gdm|gdm3|lightdm|greetd)" || true
dpkg -l phosh phoc phosh-osk-stub gnome-control-center 2>/dev/null | grep ^ii | awk '{print $2, $3}'
echo "phosh install exit=0"
