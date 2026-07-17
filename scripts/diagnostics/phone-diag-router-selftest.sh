#!/usr/bin/env bash
set -u

DIAG_ROUTER="${DIAG_ROUTER:-/tmp/diag-router}"
DIAG_CAPTURE="${DIAG_CAPTURE:-/tmp/diag-capture}"
LOG_DIR="/tmp/diag-router-selftest-$(date +%Y%m%d-%H%M%S)"

mkdir -p "$LOG_DIR"
pkill -x diag-router 2>/dev/null || true

ulimit -c unlimited 2>/dev/null || true
stdbuf -oL -eL "$DIAG_ROUTER" >"$LOG_DIR/router.log" 2>&1 &
router_pid=$!
echo "$router_pid" >"$LOG_DIR/router.pid"
sleep 1

"$DIAG_CAPTURE" -F -d 2 >"$LOG_DIR/capture.log" 2>&1
capture_status=$?
echo "$capture_status" >"$LOG_DIR/capture.status"
sleep 1

if kill -0 "$router_pid" 2>/dev/null; then
    router_status="running"
    kill "$router_pid" 2>/dev/null || true
    wait "$router_pid" 2>/dev/null || true
else
    wait "$router_pid"
    router_status=$?
fi
echo "$router_status" >"$LOG_DIR/router.status"

echo "LOG_DIR=$LOG_DIR"
echo "capture_status=$capture_status"
echo "router_status=$router_status"
echo "=== router.log ==="
cat "$LOG_DIR/router.log"
echo "=== capture.log ==="
cat "$LOG_DIR/capture.log"
