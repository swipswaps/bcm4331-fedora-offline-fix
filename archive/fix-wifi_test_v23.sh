#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: fix-wifi_test_v22.sh
# -----------------------------------------------------------------------------

set -euo pipefail
set +m

if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi

WORKSPACE_DIR="$(dirname "$(readlink -f "$0")")"
TRACE_LOG="$WORKSPACE_DIR/verbatim_handshake.log"

log_milestone() {
    local msg="$1"
    echo "→ MILESTONE: $msg"
    echo "→ MILESTONE: $msg" >> "$TRACE_LOG"
}

start_trace_stream() {
    setsid bash -c '
        {
            echo "=== TRACE START $(date) ==="
            timeout 2s stdbuf -oL journalctl -n 50 --no-pager 2>/dev/null || true
            echo ""
            timeout 2s stdbuf -oL dmesg | tail -n 50 2>/dev/null || true
            echo "=== TRACE END $(date) ==="
        } >> "'"$TRACE_LOG"'"
    ' </dev/null >/dev/null 2>&1 & disown
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

    exit 0

else
    log_milestone "network=degraded"
    log_milestone "RECOVERY_INIT"

    echo "→ Decision: RECOVERY"
fi