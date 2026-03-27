#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: fix-wifi_test_v31.sh (HARDENED + FULL FEATURE PRESERVATION)
# -----------------------------------------------------------------------------

set -euo pipefail
set +m

# -------------------------
# SINGLE INSTANCE LOCK
# -------------------------
exec 9>/tmp/fix-wifi.lock
flock -n 9 || {
    echo "Another instance is running. Exiting."
    exit 1
}

# -------------------------
# ROOT ESCALATION
# -------------------------
if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi

# -------------------------
# PORTABLE PATH RESOLUTION
# -------------------------
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACE_LOG="$WORKSPACE_DIR/verbatim_handshake.log"

TRACE_PID=""

# -------------------------
# TIMEOUT SETTINGS
# -------------------------
CMD_TIMEOUT_SHORT=2

# -------------------------
# LOGGING
# -------------------------
log_milestone() {
    local msg="$1"
    echo "→ MILESTONE: $msg"
    echo "→ MILESTONE: $msg" >> "$TRACE_LOG"
}

# -------------------------
# CLEANUP (PROCESS GROUP SAFE)
# -------------------------
cleanup() {
    log_milestone "CLEANUP_START"
    kill 0 2>/dev/null || true
    log_milestone "CLEANUP_END"
}

trap cleanup EXIT INT TERM

# -------------------------
# TRACE STREAM
# -------------------------
start_trace_stream() {
    {
        echo "=== TRACE START $(date) ==="
        timeout -k 1s "$CMD_TIMEOUT_SHORT" journalctl -n 50 --no-pager 2>/dev/null || echo "journal unavailable" >> "$TRACE_LOG"
        echo ""
        timeout -k 1s "$CMD_TIMEOUT_SHORT" dmesg | tail -n 50 2>/dev/null || true
        echo "=== TRACE END $(date) ==="
    } >> "$TRACE_LOG" &
}

# -------------------------
# HEALTH CHECK (ROBUST)
# -------------------------
system_is_healthy() {
    local status
    status="$(timeout -k 1s "$CMD_TIMEOUT_SHORT" nmcli -t -f DEVICE,STATE device 2>/dev/null || true)"

    echo "$status" | awk -F: '$2 ~ /connected/ && $1 != "lo" {found=1} END{exit !found}'
}

# -------------------------
# REPORT
# -------------------------
format_report() {
    echo ""
    echo "======================================"
    echo "      NETWORK HEALTH REPORT"
    echo "======================================"

    timeout -k 1s "$CMD_TIMEOUT_SHORT" nmcli device status 2>/dev/null || echo "nmcli device status unavailable"
    timeout -k 1s "$CMD_TIMEOUT_SHORT" nmcli connection show --active 2>/dev/null || echo "nmcli connections unavailable"
    timeout -k 1s "$CMD_TIMEOUT_SHORT" ip route 2>/dev/null || echo "ip route unavailable"

    timeout -k 1s 1s iw dev 2>/dev/null || echo "iw unavailable"

    lsmod | grep -E "b43|cfg80211|mac80211|ssb|bcma" || true

    echo ""
    echo "Firmware check:"
    for fw in \
        /usr/lib/firmware/b43/ucode29_mimo.fw \
        /usr/lib/firmware/b43/ht0initvals29.fw \
        /usr/lib/firmware/b43/ht0bsinitvals29.fw
    do
        [[ -f "$fw" ]] && echo "OK: $fw" || echo "MISSING: $fw"
    done

    uname -r

    timeout -k 1s "$CMD_TIMEOUT_SHORT" nmcli dev show 2>/dev/null | grep DNS || true

    echo "======================================"
}

# -------------------------
# MAIN LOGIC
# -------------------------
main() {
    log_milestone "DIAGNOSTIC_START"

    start_trace_stream

    STATUS="$(timeout -k 1s "$CMD_TIMEOUT_SHORT" nmcli -t -f DEVICE,STATE device 2>/dev/null || echo "timeout")"

    log_milestone "DECISION_EVALUATION"

    echo "=== CURRENT STATUS ==="
    echo "$STATUS"

    if echo "$STATUS" | awk -F: '$2 ~ /connected/ && $1 != "lo" {found=1} END{exit !found}'; then

        log_milestone "network=connected"

        echo "SYSTEM STATUS: HEALTHY"

        format_report

        log_milestone "EXIT | CONNECTED (REPORT COMPLETE)"

        return 0
    else
        log_milestone "network=degraded"
        log_milestone "RECOVERY_INIT"

        echo "→ Decision: RECOVERY"

        return 1
    fi
}

main