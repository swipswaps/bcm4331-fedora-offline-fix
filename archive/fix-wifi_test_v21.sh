#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: fix-wifi_test_v21.sh  (Fully Non-Blocking + Hard-Terminate Safe)
# -----------------------------------------------------------------------------

set -euo pipefail
if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi

WORKSPACE_DIR="$(dirname "$(readlink -f "$0")")"
MANIFEST_DB="$WORKSPACE_DIR/manifest.db"
BUNDLE_DIR="$WORKSPACE_DIR/offline_bundle"
TRACE_LOG="$WORKSPACE_DIR/verbatim_handshake.log"

log_milestone() {
    local msg="$1"
    echo "→ MILESTONE: $msg"
    echo "→ MILESTONE: $msg" >> "$TRACE_LOG"
}

TRACE_PID=0

start_trace_stream() {
    (
        setsid bash -c '
            {
                echo "=== TRACE START $(date) ==="
                timeout 2s journalctl -n 50 --no-pager 2>/dev/null || true
                echo ""
                timeout 2s dmesg | tail -n 50 2>/dev/null || true
                echo "=== TRACE END $(date) ==="
            } >> "'"$TRACE_LOG"'"
        ' &
    ) >/dev/null 2>&1 &
    TRACE_PID=$!
}

stop_trace_stream() {
    if [[ "$TRACE_PID" -ne 0 ]]; then
        kill -TERM "$TRACE_PID" 2>/dev/null || true
        sleep 0.05
        kill -KILL "$TRACE_PID" 2>/dev/null || true
    fi
}

trap 'stop_trace_stream' EXIT

system_is_healthy() {
    nmcli -t -f DEVICE,STATE device | grep -q ":connected"
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

    log_milestone "EXIT | CONNECTED (REPORT COMPLETE)"

    stop_trace_stream
    exit 0

else
    log_milestone "network=degraded"
    log_milestone "RECOVERY_INIT"

    echo "→ Decision: RECOVERY"
fi