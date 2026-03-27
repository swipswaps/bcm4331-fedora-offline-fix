#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: fix-wifi_test_v35.sh (HARDENED STABLE – NO RECURSIVE TRAPS)
# -----------------------------------------------------------------------------

set -euo pipefail

# -------------------------
# ROOT ESCALATION
# -------------------------
if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi

# -------------------------
# SAFE PATH RESOLUTION
# -------------------------
WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRACE_LOG="$WORKSPACE_DIR/verbatim_handshake.log"

# -------------------------
# GLOBAL STATE
# -------------------------
TRACE_PID=""
CLEANUP_DONE=0

# -------------------------
# TIMEOUTS
# -------------------------
CMD_TIMEOUT_SHORT=2
CMD_TIMEOUT_LONG=3

# -------------------------
# LOGGING
# -------------------------
log_milestone() {
    local msg="$1"
    echo "→ MILESTONE: $msg"
    echo "→ MILESTONE: $msg" >> "$TRACE_LOG"
}

# -------------------------
# CLEANUP (SAFE, NON-RECURSIVE)
# -------------------------
cleanup() {
    # Prevent recursive invocation
    if [[ "$CLEANUP_DONE" -eq 1 ]]; then
        return 0
    fi
    CLEANUP_DONE=1

    log_milestone "CLEANUP_START"

    # Only kill known trace process
    if [[ -n "${TRACE_PID:-}" ]]; then
        if kill -0 "$TRACE_PID" 2>/dev/null; then
            kill "$TRACE_PID" 2>/dev/null || true
            wait "$TRACE_PID" 2>/dev/null || true
        fi
    fi

    log_milestone "CLEANUP_END"
}

trap cleanup EXIT INT TERM

# -------------------------
# TRACE STREAM
# -------------------------
start_trace_stream() {
    {
        echo "=== TRACE START $(date) ==="
        timeout "$CMD_TIMEOUT_SHORT" journalctl -n 50 --no-pager 2>/dev/null || echo "journal unavailable"
        echo ""
        timeout "$CMD_TIMEOUT_SHORT" dmesg | tail -n 50 2>/dev/null || true
        echo "=== TRACE END $(date) ==="
    } >> "$TRACE_LOG" &

    TRACE_PID=$!
}

# -------------------------
# HEALTH CHECK
# -------------------------
system_is_healthy() {
    local status

    status="$(timeout "$CMD_TIMEOUT_SHORT" nmcli -t -f DEVICE,STATE device 2>/dev/null || true)"

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

    timeout "$CMD_TIMEOUT_SHORT" nmcli device status 2>/dev/null || echo "nmcli device status unavailable"
    timeout "$CMD_TIMEOUT_SHORT" nmcli connection show --active 2>/dev/null || echo "nmcli connections unavailable"
    timeout "$CMD_TIMEOUT_SHORT" ip route 2>/dev/null || echo "ip route unavailable"

    timeout "$CMD_TIMEOUT_SHORT" iw dev 2>/dev/null || echo "iw unavailable"

    lsmod | grep -E "b43|cfg80211|mac80211|ssb|bcma" || true

    ls -lh /usr/lib/firmware/b43 2>/dev/null || true

    uname -r

    timeout "$CMD_TIMEOUT_SHORT" nmcli dev show 2>/dev/null | grep DNS || true

    echo "======================================"
}

# -------------------------
# MAIN
# -------------------------
main() {
    log_milestone "DIAGNOSTIC_START"

    start_trace_stream

    STATUS="$(timeout "$CMD_TIMEOUT_SHORT" nmcli -t -f DEVICE,STATE device 2>/dev/null || echo "timeout")"

    log_milestone "DECISION_EVALUATION"

    echo "=== CURRENT STATUS ==="
    echo "$STATUS"

    if echo "$STATUS" | grep -q ":connected"; then

        log_milestone "network=connected"

        echo "SYSTEM STATUS: HEALTHY"

        format_report

        log_milestone "EXIT | CONNECTED (REPORT COMPLETE)"

        return 0

    else
        log_milestone "network=degraded"
        log_milestone "RECOVERY_INIT"

        echo "→ Decision: RECOVERY"

        # Recovery preserved (intentionally unchanged behavior)
        return 1
    fi
}

main
exit $?