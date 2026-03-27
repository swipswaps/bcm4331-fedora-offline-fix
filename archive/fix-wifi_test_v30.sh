#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: fix-wifi_test_v26.sh (STABLE + NON-BLOCKING + SAFE CONTROL FLOW)
# -----------------------------------------------------------------------------

set -euo pipefail
set +m

if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi

WORKSPACE_DIR="$(dirname "$(readlink -f "$0" 2>/dev/null || echo "$PWD/$0")")"
TRACE_LOG="$WORKSPACE_DIR/verbatim_handshake.log"

TRACE_PID=""

# -------------------------
# GLOBAL TIMEOUTS
# -------------------------
CMD_TIMEOUT_SHORT=2
CMD_TIMEOUT_LONG=3

log_milestone() {
    local msg="$1"
    echo "→ MILESTONE: $msg"
    echo "→ MILESTONE: $msg" >> "$TRACE_LOG"
}

cleanup() {
    log_milestone "CLEANUP_START"

    if [[ -n "${TRACE_PID:-}" ]]; then
        if kill -0 "$TRACE_PID" 2>/dev/null; then
            kill "$TRACE_PID" 2>/dev/null || true
            wait "$TRACE_PID" 2>/dev/null || true
        fi
    fi

    log_milestone "CLEANUP_END"
}

trap cleanup EXIT INT TERM

start_trace_stream() {
    {
        {
            echo "=== TRACE START $(date) ==="
            timeout "$CMD_TIMEOUT_SHORT" journalctl -n 50 --no-pager 2>/dev/null || true
            echo ""
            timeout "$CMD_TIMEOUT_SHORT" dmesg | tail -n 50 2>/dev/null || true
            echo "=== TRACE END $(date) ==="
        } >> "$TRACE_LOG"
    } &

    TRACE_PID=$!
}

system_is_healthy() {
    local status

    status="$(timeout "$CMD_TIMEOUT_SHORT" nmcli -t -f DEVICE,STATE device 2>/dev/null || true)"

    # Require at least one non-loopback interface connected
    echo "$status" | grep -Ev "^lo:" | grep -q ":connected"
}

format_report() {
    echo ""
    echo "======================================"
    echo "      NETWORK HEALTH REPORT"
    echo "======================================"

    timeout "$CMD_TIMEOUT_SHORT" nmcli device status 2>/dev/null || echo "nmcli device status unavailable"
    timeout "$CMD_TIMEOUT_SHORT" nmcli connection show --active 2>/dev/null || echo "nmcli connections unavailable"
    timeout "$CMD_TIMEOUT_SHORT" ip route 2>/dev/null || echo "ip route unavailable"

    timeout 1s iw dev 2>/dev/null || echo "iw unavailable or timed out"

    lsmod | grep -E "b43|cfg80211|mac80211|ssb|bcma" || true
    ls -lh /usr/lib/firmware/b43 2>/dev/null || true

    uname -r
    timeout "$CMD_TIMEOUT_SHORT" nmcli dev show 2>/dev/null | grep DNS || true

    echo "======================================"
}

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

        # Recovery logic would go here (intentionally preserved behavior)
        return 1
    fi
}

main
exit $?