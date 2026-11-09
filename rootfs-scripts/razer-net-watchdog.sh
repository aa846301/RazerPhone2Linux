#!/bin/bash
# razer-net-watchdog: keep the phone reachable over WiFi without a human.
#
# Why (2026-11-09): after a forced reset the phone booted with no WLAN and
# left no journal at all (I/O likely stalled), staying unreachable for over
# an hour until the user pressed power. razer-wifi-ready only waits for
# wlan0 and then gives up.
#
# Escalation while WiFi is down (default timings, seconds of continuous
# failure after the boot grace period):
#   RECONNECT (120s)  nmcli radio on + device connect, every check
#   RELOAD    (300s)  reload ath10k_snoc once
#   REBOOT    (480s)  graceful `systemctl reboot` (stops MSS cleanly)
#   FORCE     (720s)  sysrq-b, only if the graceful reboot did not happen
#
# The main loop uses only bash builtins and sysfs/procfs reads, so it keeps
# running when disk I/O is stuck (external commands are started in the
# background and never waited on). Status goes to /dev/kmsg so it reaches
# the journal and the ramoops console.
#
# Boot-loop guard: at most MAX_REBOOTS watchdog reboots in a row without a
# successful connection; after that it only keeps trying to reconnect.
# Disable completely with /etc/razerphone2linux/no-net-watchdog or the
# kernel parameter razer.netwd=0.
set -u

CONF=/etc/razerphone2linux/net-watchdog.conf
[ -r "$CONF" ] && . "$CONF"
GRACE=${GRACE:-180}
INTERVAL=${INTERVAL:-20}
T_RECONNECT=${T_RECONNECT:-120}
T_RELOAD=${T_RELOAD:-300}
T_REBOOT=${T_REBOOT:-480}
T_FORCE=${T_FORCE:-720}
OK_RESET=${OK_RESET:-600}      # connected this long -> clear reboot counter
MAX_REBOOTS=${MAX_REBOOTS:-3}
IFACE=${IFACE:-wlan0}
STATE=${STATE:-/var/lib/razer-net-watchdog/reboots}
DRYRUN=${DRYRUN:-0}

log() { echo "razer-net-watchdog: $*" > /dev/kmsg 2>/dev/null || echo "razer-net-watchdog: $*"; }

[ -e /etc/razerphone2linux/no-net-watchdog ] && { log "disabled by flag file"; exit 0; }
read -r cmdline < /proc/cmdline
case " $cmdline " in *" razer.netwd=0 "*) log "disabled by cmdline"; exit 0 ;; esac

# builtin sleep: read with timeout on a fd that never delivers data
FIFO=/run/razer-net-watchdog.fifo
[ -p "$FIFO" ] || { rm -f "$FIFO"; mkfifo -m 600 "$FIFO"; }
exec 9<> "$FIFO"
nap() { read -r -t "$1" -u 9 _ 2>/dev/null; return 0; }

uptime_s() { local u; read -r u _ < /proc/uptime; echo "${u%%.*}"; }

net_ok() {
    local st
    [ -r "/sys/class/net/$IFACE/operstate" ] || return 1
    read -r st < "/sys/class/net/$IFACE/operstate"
    [ "$st" = up ] || return 1
    # default route through IFACE (dest 00000000 in /proc/net/route)
    local ifn dest _rest
    while read -r ifn dest _rest; do
        [ "$ifn" = "$IFACE" ] && [ "$dest" = 00000000 ] && return 0
    done < /proc/net/route
    return 1
}

reboots=0
mkdir -p "${STATE%/*}" 2>/dev/null
[ -r "$STATE" ] && read -r reboots < "$STATE"
reboots=${reboots:-0}
log "start (grace ${GRACE}s, previous watchdog reboots in a row: $reboots, dryrun=$DRYRUN)"

while [ "$(uptime_s)" -lt "$GRACE" ]; do nap "$INTERVAL"; done

down_since=0 ok_since=0 reloaded=0 rebooted_at=0
while :; do
    now=$(uptime_s)
    if net_ok; then
        if [ "$down_since" -ne 0 ]; then
            log "$IFACE back after $((now - down_since))s"
            down_since=0 reloaded=0 rebooted_at=0
        fi
        [ "$ok_since" -eq 0 ] && ok_since=$now
        if [ "$reboots" -ne 0 ] && [ $((now - ok_since)) -ge "$OK_RESET" ]; then
            reboots=0
            echo 0 > "$STATE" 2>/dev/null &
            log "connected ${OK_RESET}s, reboot counter cleared"
        fi
    else
        ok_since=0
        if [ "$down_since" -eq 0 ]; then
            down_since=$now
            log "$IFACE down (operstate/default route missing)"
        fi
        d=$((now - down_since))
        if [ "$d" -ge "$T_RECONNECT" ]; then
            log "reconnect attempt (down ${d}s)"
            [ "$DRYRUN" = 1 ] || { nmcli radio wifi on >/dev/null 2>&1; nmcli device connect "$IFACE" >/dev/null 2>&1; } &
        fi
        if [ "$d" -ge "$T_RELOAD" ] && [ "$reloaded" -eq 0 ]; then
            reloaded=1
            log "reloading ath10k_snoc (down ${d}s)"
            [ "$DRYRUN" = 1 ] || { modprobe -r ath10k_snoc; nap 3; modprobe ath10k_snoc; } >/dev/null 2>&1 &
        fi
        if [ "$d" -ge "$T_REBOOT" ] && [ "$rebooted_at" -eq 0 ]; then
            if [ "$reboots" -ge "$MAX_REBOOTS" ]; then
                log "down ${d}s but $reboots watchdog reboots in a row already; not rebooting again"
                rebooted_at=-1
            else
                rebooted_at=$now
                reboots=$((reboots + 1))
                echo "$reboots" > "$STATE" 2>/dev/null &
                log "graceful reboot #$reboots (down ${d}s)"
                [ "$DRYRUN" = 1 ] || systemctl reboot >/dev/null 2>&1 &
            fi
        fi
        if [ "$rebooted_at" -gt 0 ] && [ "$d" -ge "$T_FORCE" ]; then
            log "graceful reboot did not happen; sysrq-b (down ${d}s)"
            if [ "$DRYRUN" != 1 ]; then
                echo s > /proc/sysrq-trigger 2>/dev/null
                nap 2
                echo b > /proc/sysrq-trigger 2>/dev/null
            fi
            rebooted_at=-1
        fi
    fi
    nap "$INTERVAL"
done
