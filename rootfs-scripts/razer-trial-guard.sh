#!/bin/bash
# Reboot a kexec trial boot back into boot_a unless it is confirmed in time.
# A trial boot carries razer.trial=<seconds> on the kernel cmdline (added by
# razer-kexec-trial). Confirm with: touch /run/razer-trial-ok
set -euo pipefail

GRACE=$(sed -nE 's/(^|.* )razer\.trial=([0-9]+)( .*|$)/\2/p' /proc/cmdline)
if [ -z "$GRACE" ]; then
    exit 0
fi

logger -t razer-trial-guard "trial boot: waiting ${GRACE}s for /run/razer-trial-ok"
deadline=$(( $(date +%s) + GRACE ))
while [ "$(date +%s)" -lt "$deadline" ]; do
    if [ -e /run/razer-trial-ok ]; then
        logger -t razer-trial-guard "trial confirmed"
        exit 0
    fi
    sleep 5
done

logger -t razer-trial-guard "trial not confirmed; rebooting to boot_a"
sync
systemctl reboot
