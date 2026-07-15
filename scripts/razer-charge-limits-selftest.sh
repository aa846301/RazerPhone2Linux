#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY_SCRIPT="$PROJECT_DIR/rootfs-scripts/razer-charge-limits.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/power/BAT0" "$TEST_ROOT/power/USB0" "$TEST_ROOT/state"
printf 'Battery\n' > "$TEST_ROOT/power/BAT0/type"
printf 'USB\n' > "$TEST_ROOT/power/USB0/type"

run_policy() {
    RAZER_POWER_SUPPLY_ROOT="$TEST_ROOT/power" \
    RAZER_CHARGE_STATE_FILE="$TEST_ROOT/state/policy" \
    RAZER_CHARGE_ONCE=1 \
        bash "$POLICY_SCRIPT" >/dev/null
}

assert_behaviour() {
    local expected="$1"
    local actual

    actual="$(cat "$TEST_ROOT/power/USB0/charge_behaviour")"
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: expected charge_behaviour=%s, got %s\n' \
            "$expected" "$actual" >&2
        exit 1
    fi
}

printf '80\n' > "$TEST_ROOT/power/BAT0/capacity"
printf 'auto\n' > "$TEST_ROOT/power/USB0/charge_behaviour"
run_policy
assert_behaviour inhibit-charge

printf '40\n' > "$TEST_ROOT/power/BAT0/capacity"
run_policy
assert_behaviour auto

printf 'suspended\n' > "$TEST_ROOT/state/policy"
printf '60\n' > "$TEST_ROOT/power/BAT0/capacity"
run_policy
assert_behaviour inhibit-charge

printf 'auto\n' > "$TEST_ROOT/state/policy"
run_policy
assert_behaviour auto

printf 'PASS: razer charge-limit policy uses charge_behaviour correctly\n'
