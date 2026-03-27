#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: fix-wifi_test_v26.sh (FULLY NON-BLOCKING + HARD TIME BOUNDARIES)
# -----------------------------------------------------------------------------

set -euo pipefail
set +m

if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi

WORKSPACE_DIR="$(dirname "$(readlink -f "$0")")"
TRACE_LOG="$WORKSPACE_DIR/verbatim_handshake.log"

TRACE_PID=""

# -------------------------
# GLOBAL EXECUTION TIMEOUT (PREVENT ANY HANG)
# -------------------------
SCRIPT_TIMEOUT_SEC=10

timeout "$SCRIPT_TIMEOUT_SEC" bash -c '
    # -------------------------
    # INNER SCRIPT START
    # -------------------------

    log_milestone() {
        local msg="$1"
        echo "→ MILESTONE: $msg"
        echo "→ MILESTONE: $msg" >> "'"$TRACE_LOG"'"
    }

    cleanup() {
        log_milestone "CLEANUP_START"

        if [[ -n "${TRACE_PID:-}" ]]; then
            kill "$TRACE_PID" 2>/dev/null || true
            wait "$TRACE_PID" 2>/dev/null || true
        fi

        log_milestone "CLEANUP_END"
    }

    trap cleanup EXIT INT TERM

    start_trace_stream() {
        {
            {
                echo "=== TRACE START $(date) ==="
                timeout 1s journalctl -n 50 --no-pager 2>/dev/null || true
                echo ""
                timeout 1s dmesg | tail -n 50 2>/dev/null || true
                echo "=== TRACE END $(date) ==="
            } >> "'"$TRACE_LOG"'"
        } &

        TRACE_PID=$!
    }

    system_is_healthy() {
        timeout 2s nmcli -t -f DEVICE,STATE device 2>/dev/null | grep -q ":connected"
    }

    format_report() {
        echo ""
        echo "======================================"
        echo "      NETWORK HEALTH REPORT"
        echo "======================================"

        timeout 2s nmcli device status 2>/dev/null || echo "nmcli device status unavailable"
        timeout 2s nmcli connection show --active 2>/dev/null || echo "nmcli connections unavailable"
        timeout 2s ip route | column -t 2>/dev/null || echo "ip route unavailable"

        timeout 1s iw dev 2>/dev/null || echo "iw unavailable or timed out"

        lsmod | grep -E "b43|cfg80211|mac80211|ssb|bcma" || true
        ls -lh /usr/lib/firmware/b43 2>/dev/null || true

        uname -r
        timeout 2s nmcli dev show 2>/dev/null | grep DNS || true

        echo "======================================"
    }

    log_milestone "DIAGNOSTIC_START"

    start_trace_stream

    STATUS="$(timeout 2s nmcli -t -f DEVICE,STATE device 2>/dev/null || echo "timeout")"

    log_milestone "DECISION_EVALUATION"

    echo "=== CURRENT STATUS ==="
    echo "$STATUS"

    if echo "$STATUS" | grep -q ":connected"; then

        log_milestone "network=connected"

        echo "SYSTEM STATUS: HEALTHY"

        format_report

        log_milestone "EXIT | CONNECTED (REPORT COMPLETE)"

        exit 0

    else
        log_milestone "network=degraded"
        log_milestone "RECOVERY_INIT"

        echo "→ Decision: RECOVERY"

        exit 1
    fi

'
EXIT_CODE=$?

# Final guard
exit "$EXIT_CODE"