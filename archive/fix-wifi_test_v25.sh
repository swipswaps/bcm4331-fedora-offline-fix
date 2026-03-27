#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: fix-wifi_test_v25.sh (FULLY SAFE + CONTROLLED LIFECYCLE)
# -----------------------------------------------------------------------------

set -euo pipefail
set +m

if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi

WORKSPACE_DIR="$(dirname "$(readlink -f "$0")")"
TRACE_LOG="$WORKSPACE_DIR/verbatim_handshake.log"

TRACE_PID=""

log_milestone() {
    local msg="$1"
    echo "→ MILESTONE: $msg"
    echo "→ MILESTONE: $msg" >> "$TRACE_LOG"
}

cleanup() {
    log_milestone "CLEANUP_START"

    if [[ -n "${TRACE_PID:-}" ]]; then
        kill "$TRACE_PID" 2>/dev/null || true
        wait "$TRACE_PID" 2>/dev/null || true
    fi

    log_milestone "CLEANUP_END"
}

trap cleanup EXIT

# -------------------------
# TRACE (SAFE + TRACKED)
# -------------------------
start_trace_stream() {
    {
        {
            echo "=== TRACE START $(date) ==="
            timeout 2s journalctl -n 50 --no-pager 2>/dev/null || true
            echo ""
            timeout 2s dmesg | tail -n 50 2>/dev/null || true
            echo "=== TRACE END $(date) ==="
        } >> "$TRACE_LOG"
    } &

    TRACE_PID=$!
}

system_is_healthy() {
    nmcli -t -f DEVICE,STATE device | grep -q ":connected"
}

format_report() {
    echo ""
    echo "======================================"
    echo "      NETWORK HEALTH REPORT"
    echo "======================================"

    nmcli device status
    nmcli connection show --active
    ip route | column -t
    iw dev 2>/dev/null || echo "iw not available"
    lsmod | grep -E 'b43|cfg80211|mac80211|ssb|bcma' || true
    ls -lh /usr/lib/firmware/b43 2>/dev/null || true
    uname -r
    nmcli dev show | grep DNS || true

    echo "======================================"
}

log_milestone "DIAGNOSTIC_START"

start_trace_stream

STATUS="$(nmcli -t -f DEVICE,STATE device)"

log_milestone "DECISION_EVALUATION"

echo "=== CURRENT STATUS ==="
echo "$STATUS"

if echo "$STATUS" | grep -q ":connected"; then

    log_milestone "network=connected"

    echo "SYSTEM STATUS: HEALTHY"

    format_report

    log_milestone "EXIT | CONNECTED (REPORT COMPLETE)"

    wait 2>/dev/null || true
    exit 0

else
    log_milestone "network=degraded"
    log_milestone "RECOVERY_INIT"

    echo "→ Decision: RECOVERY"

    wait 2>/dev/null || true
    exit 1
fi