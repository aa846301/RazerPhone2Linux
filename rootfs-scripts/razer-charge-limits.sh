#!/bin/bash
set -euo pipefail

START="${RAZER_CHARGE_START_PERCENT:-40}"
STOP="${RAZER_CHARGE_STOP_PERCENT:-80}"

log() {
    printf 'razer-charge-limits: %s\n' "$*" >&2
}

write_if_present() {
    local path="$1"
    local value="$2"

    if [ -w "$path" ]; then
        printf '%s\n' "$value" > "$path"
        log "set $path=$value"
        return 0
    fi
    return 1
}

applied=0
for psy in /sys/class/power_supply/*; do
    [ -d "$psy" ] || continue

    write_if_present "$psy/charge_control_start_threshold" "$START" && applied=1
    write_if_present "$psy/charge_control_end_threshold" "$STOP" && applied=1
    write_if_present "$psy/charge_stop_threshold" "$STOP" && applied=1
    write_if_present "$psy/input_suspend_threshold" "$STOP" && applied=1
done

if [ "$applied" -eq 0 ]; then
    log "no writable threshold sysfs found; kernel charging still uses DTS safety limits"
fi
