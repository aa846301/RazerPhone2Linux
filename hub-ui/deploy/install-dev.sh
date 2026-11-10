#!/bin/bash
# Development install on the phone: backlight udev rule, runner, sway config; then (re)start the kiosk session
# as a transient user unit "hub-sway" (stop with: systemctl --user stop hub-sway).
set -e
cd ~/hub-ui/deploy
sudo install -m 0644 90-razer-hub-backlight.rules /etc/udev/rules.d/90-razer-hub-backlight.rules
sudo udevadm control --reload
sudo udevadm trigger -s backlight -c add
sudo install -m 0755 hub-ui-run /usr/local/bin/hub-ui-run
sudo install -D -m 0644 50-razer-hub-powerkey.conf /etc/systemd/logind.conf.d/50-razer-hub-powerkey.conf
# Make logind pick up the new power key policy now (SIGHUP reload; restart as fallback), then verify it.
sudo systemctl kill -s HUP systemd-logind; sleep 1
pk() { busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager HandlePowerKey; }
if ! pk | grep -q '"ignore"'; then sudo systemctl restart systemd-logind; sleep 2; fi
echo "logind HandlePowerKey: $(pk)"
mkdir -p ~/.config/razer-hub
install -m 0644 sway-hub.conf ~/.config/razer-hub/sway.conf
# Hub <-> Phosh debug desktop switch, and the "back to hub" launcher shown in Phosh.
sudo install -m 0755 razer-desktop /usr/local/sbin/razer-desktop
sudo install -m 0644 razer-hub-return.desktop /usr/share/applications/razer-hub-return.desktop
# Speakers: hub orientation has the earpiece end on the left, so swap the PipeWire speaker channels.
install -D -m 0644 51-razer-speaker-swap.lua ~/.config/wireplumber/main.lua.d/51-razer-speaker-swap.lua
# PipeWire (user session) needs /dev/snd access.
id -nG | grep -qw audio || sudo usermod -aG audio "$USER"
ls -la /sys/class/backlight/*/brightness
install -D -m 0644 hub-sway.service ~/.config/systemd/user/hub-sway.service
systemctl --user daemon-reload
# The old framebuffer panel holds DRM master; stop it for this session.
sudo systemctl stop razer-control-panel 2>/dev/null || true
systemctl --user restart hub-sway
sleep 8
systemctl --user is-active hub-sway
pgrep -a hub-ui | head -3
tail -5 ~/.local/state/razer-hub/hub-ui.log 2>/dev/null
for f in /sys/class/backlight/*/bl_power /sys/class/backlight/*/brightness; do echo "$f=$(cat $f)"; done
