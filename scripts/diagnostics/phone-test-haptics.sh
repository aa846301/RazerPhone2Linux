#!/usr/bin/env bash
set -Eeuo pipefail

if ! command -v fftest >/dev/null 2>&1; then
	echo "fftest is missing; install the Ubuntu joystick package." >&2
	exit 1
fi

event="${1:-}"
if [ -z "$event" ]; then
	for name in /sys/class/input/event*/device/name; do
		[ -r "$name" ] || continue
		if grep -qx 'spmi_haptics' "$name"; then
			event="/dev/input/$(basename "${name%/device/name}")"
			break
		fi
	done
fi

if [ -z "$event" ] || [ ! -c "$event" ]; then
	echo "spmi_haptics input device not found." >&2
	echo "Check: dmesg | grep -i haptic" >&2
	exit 1
fi

echo "Testing FF_RUMBLE on $event"
printf '0\n-1\n' | timeout 8s fftest "$event"
