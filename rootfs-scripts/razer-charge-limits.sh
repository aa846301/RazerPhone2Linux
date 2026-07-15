#!/bin/bash
set -euo pipefail

START="${RAZER_CHARGE_START_PERCENT:-40}"
STOP="${RAZER_CHARGE_STOP_PERCENT:-80}"
POLL_SECONDS="${RAZER_CHARGE_POLL_SECONDS:-30}"
POWER_SUPPLY_ROOT="${RAZER_POWER_SUPPLY_ROOT:-/sys/class/power_supply}"
RUN_ONCE="${RAZER_CHARGE_ONCE:-0}"
STATE_FILE="${RAZER_CHARGE_STATE_FILE:-/var/lib/razer-charge-limits/state}"

log() {
    printf 'razer-charge-limits: %s\n' "$*" >&2
}

find_supply() {
    local wanted_type="$1"
    local psy

    for psy in "$POWER_SUPPLY_ROOT"/*; do
        [ -r "$psy/type" ] || continue
        if [ "$(cat "$psy/type")" = "$wanted_type" ]; then
            printf '%s\n' "$psy"
            return 0
        fi
    done
    return 1
}

save_state() {
    mkdir -p "$(dirname "$STATE_FILE")"
    printf '%s\n' "$1" > "$STATE_FILE"
}

if ! [[ "$START" =~ ^[0-9]+$ && "$STOP" =~ ^[0-9]+$ ]] ||
        [ "$START" -ge "$STOP" ] || [ "$STOP" -gt 100 ]; then
    log "invalid thresholds: start=$START stop=$STOP"
    exit 1
fi

log "policy active: auto at <=${START}%, inhibit charge at >=${STOP}%"

policy_state="auto"
if [ -r "$STATE_FILE" ]; then
    saved_state="$(cat "$STATE_FILE")"
    case "$saved_state" in
        auto|inhibit-charge) policy_state="$saved_state" ;;
        charging) policy_state="auto" ;;
        suspended) policy_state="inhibit-charge" ;;
    esac
fi

while true; do
    battery="$(find_supply Battery || true)"
    charger="$(find_supply USB || true)"

    if [ -n "$battery" ] && [ -r "$battery/capacity" ] &&
            [ -n "$charger" ] && [ -r "$charger/charge_behaviour" ] &&
            [ -w "$charger/charge_behaviour" ]; then
        capacity="$(cat "$battery/capacity")"
        behaviour="$(cat "$charger/charge_behaviour")"

        if [[ "$capacity" =~ ^[0-9]+$ ]]; then
            if [ "$capacity" -ge "$STOP" ]; then
                if [ "$policy_state" != "inhibit-charge" ]; then
                    policy_state="inhibit-charge"
                    save_state "$policy_state"
                fi
                if [ "$behaviour" != "inhibit-charge" ]; then
                    printf 'inhibit-charge\n' > "$charger/charge_behaviour"
                    log "capacity=${capacity}%: battery charging inhibited; USB input retained"
                fi
            elif [ "$capacity" -le "$START" ]; then
                if [ "$policy_state" != "auto" ]; then
                    policy_state="auto"
                    save_state "$policy_state"
                fi
                if [ "$behaviour" != "auto" ]; then
                    printf 'auto\n' > "$charger/charge_behaviour"
                    log "capacity=${capacity}%: automatic charging resumed"
                fi
            elif [ "$behaviour" != "$policy_state" ]; then
                printf '%s\n' "$policy_state" > "$charger/charge_behaviour"
                log "capacity=${capacity}%: restored ${policy_state} policy"
            fi
        else
            log "ignoring invalid capacity '$capacity'"
        fi
    elif [ "$RUN_ONCE" = "1" ]; then
        log "charger charge_behaviour or battery capacity is unavailable"
    fi

    [ "$RUN_ONCE" = "1" ] && break
    sleep "$POLL_SECONDS"
done
