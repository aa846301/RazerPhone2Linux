#!/usr/bin/env bash
set -Eeuo pipefail

for tool in aplay speaker-test; do
	command -v "$tool" >/dev/null 2>&1 || {
		echo "$tool is missing; install alsa-utils." >&2
		exit 1
	}
done

echo "Detected ALSA playback devices:"
aplay -l

pcm="${1:-}"
if [ -z "$pcm" ]; then
	device=$(aplay -l | sed -n 's/^card \([0-9][0-9]*\):.*device \([0-9][0-9]*\):.*/\1,\2/p' | head -n1)
	[ -n "$device" ] || {
		echo "No ALSA playback PCM found." >&2
		echo "Check: dmesg | grep -Ei 'adsp|slim|wcd934|snd|audio'" >&2
		exit 1
	}
	pcm="plughw:$device"
fi

echo "Playing one stereo 440 Hz test pass through $pcm"
speaker-test -D "$pcm" -c 2 -t sine -f 440 -l 1
