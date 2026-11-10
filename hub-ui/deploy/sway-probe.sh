#!/bin/bash
# Try sway output bring-up variants; report whether DSI-1 commits. Each run lasts ~6 s.
pgrep -a razer-panel-col && echo "colortest still running"
cat > /tmp/sway-probe.conf <<'EOF'
output DSI-1 transform 90 scale 2
xwayland disable
exec sleep 4 && swaymsg exit
EOF
for v in "default" "WLR_DRM_NO_MODIFIERS=1" "WLR_DRM_NO_ATOMIC=1" "WLR_RENDERER=pixman"; do
  envs="LIBSEAT_BACKEND=seatd WLR_NO_HARDWARE_CURSORS=1"
  [ "$v" != default ] && envs="$envs $v"
  timeout 20 env $envs dbus-run-session -- sway -d -c /tmp/sway-probe.conf > /tmp/sway-probe.log 2>&1
  rc=$?
  echo "== $v rc=$rc: $(grep -cE 'failed test|Failed to commit' /tmp/sway-probe.log) commit failures"
  grep -E "Failed|failed|error|Modifier|format|DRM_FORMAT|Swapchain|Choosing|EGL|GL_RENDERER" /tmp/sway-probe.log | grep -vE "EDID|xkb|libinput" | head -8 | cut -c1-220
done
