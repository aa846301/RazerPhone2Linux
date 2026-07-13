#!/bin/bash
set -euo pipefail

START="${RAZER_CHARGE_START_PERCENT:-40}"
STOP="${RAZER_CHARGE_STOP_PERCENT:-80}"
POLL_SECONDS="${RAZER_CHARGE_POLL_SECONDS:-30}"
POWER_SUPPLY_ROOT="${RAZER_POWER_SUPPLY_ROOT:-/sys/class/power_supply}"
RUN_ONCE="${RAZER_CHARGE_ONCE:-0}"
STATE_FILE="${RAZER_CHARGE_STATE_FILE:-/var/lib/razer-charge-limits/state}"
IIO_ROOT="${RAZER_IIO_ROOT:-/sys/bus/iio/devices}"
USBIN_PRESENT_RAW_MIN="${RAZER_USBIN_PRESENT_RAW_MIN:-100}"

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

charger_is_present() {
    local charger="$1"
    local label raw raw_path voltage_now

    voltage_now="$(cat "$charger/voltage_now" 2>/dev/null || echo 0)"
    if [[ "$voltage_now" =~ ^[0-9]+$ ]] && [ "$voltage_now" -gt 0 ]; then
        return 0
    fi

    for label in "$IIO_ROOT"/iio:device*/in_voltage*_label; do
        [ -r "$label" ] || continue
        [ "$(cat "$label")" = "usbin_v" ] || continue
        raw_path="${label%_label}_raw"
        raw="$(cat "$raw_path" 2>/dev/null || echo 0)"
        [[ "$raw" =~ ^[0-9]+$ ]] && [ "$raw" -ge "$USBIN_PRESENT_RAW_MIN" ]
        return
    done

    # Without an RRADC channel, retrying Charging is safer than leaving a
    # reconnected adapter suspended in the 40-80 hysteresis band.
    return 0
}

if ! [[ "$START" =~ ^[0-9]+$ && "$STOP" =~ ^[0-9]+$ ]] ||
        [ "$START" -ge "$STOP" ] || [ "$STOP" -gt 100 ]; then
    log "invalid thresholds: start=$START stop=$STOP"
    exit 1
fi

log "policy active: resume at <=${START}%, suspend at >=${STOP}%"

policy_state="charging"
if [ -r "$STATE_FILE" ]; then
    saved_state="$(cat "$STATE_FILE")"
    case "$saved_state" in
        charging|suspended) policy_state="$saved_state" ;;
    esac
fi

while true; do
    battery="$(find_supply Battery || true)"
    charger="$(find_supply USB || true)"

    if [ -n "$battery" ] && [ -r "$battery/capacity" ] &&
            [ -n "$charger" ] && [ -w "$charger/status" ]; then
        capacity="$(cat "$battery/capacity")"
        status="$(cat "$charger/status")"
        charger_present=0
        if charger_is_present "$charger"; then
            charger_present=1
        fi

        if [[ "$capacity" =~ ^[0-9]+$ ]]; then
            if [ "$capacity" -ge "$STOP" ]; then
                if [ "$policy_state" != "suspended" ]; then
                    policy_state="suspended"
                    save_state "$policy_state"
                fi
                if [ "$charger_present" = "1" ] && [ "$status" != "Discharging" ]; then
                    # qcom_smbx maps POWER_SUPPLY_STATUS_UNKNOWN to USB input suspend.
                    printf 'Unknown\n' > "$charger/status"
                    log "capacity=${capacity}%: charging suspended"
                fi
            elif [ "$capacity" -le "$START" ]; then
                if [ "$policy_state" != "charging" ]; then
                    policy_state="charging"
                    save_state "$policy_state"
                fi
                if [ "$charger_present" = "1" ] && [ "$status" != "Charging" ]; then
                    printf 'Charging\n' > "$charger/status"
                    log "capacity=${capacity}%: charging resumed"
                fi
            elif [ "$policy_state" = "charging" ] &&
                    [ "$charger_present" = "1" ] && [ "$status" != "Charging" ]; then
                printf 'Charging\n' > "$charger/status"
                log "capacity=${capacity}%: charging resumed after reconnect"
            elif [ "$policy_state" = "suspended" ] &&
                    [ "$charger_present" = "1" ] && [ "$status" != "Discharging" ]; then
                printf 'Unknown\n' > "$charger/status"
                log "capacity=${capacity}%: charging remains suspended"
            fi
        else
            log "ignoring invalid capacity '$capacity'"
        fi
    elif [ "$RUN_ONCE" = "1" ]; then
        log "charger or battery power supply is unavailable"
    fi

    [ "$RUN_ONCE" = "1" ] && break
    sleep "$POLL_SECONDS"
done
