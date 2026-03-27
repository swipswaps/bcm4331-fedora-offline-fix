#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: fix-wifi_test_v19.sh  (Non-Blocking + Deterministic Exit + Hardened Trace)
# -----------------------------------------------------------------------------

set -euo pipefail
if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi

WORKSPACE_DIR="$(dirname "$(readlink -f "$0")")"
MANIFEST_DB="$WORKSPACE_DIR/manifest.db"
BUNDLE_DIR="$WORKSPACE_DIR/offline_bundle"
TRACE_LOG="$WORKSPACE_DIR/verbatim_handshake.log"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_milestone() {
    local msg="$1"
    echo "→ MILESTONE: $msg"
    echo "→ MILESTONE: $msg" >> "$TRACE_LOG"
}

# -------------------------
# TRACE CONTROL (NON-BLOCKING + TIMEOUT SAFE)
# -------------------------
TRACE_PID=0

start_trace_stream() {
    (
        {
            echo "=== TRACE START $(date) ==="

            timeout 2s journalctl -n 50 --no-pager 2>/dev/null || true

            echo ""
            timeout 2s dmesg | tail -n 50 2>/dev/null || true

            echo "=== TRACE END $(date) ==="
        } >> "$TRACE_LOG"
    ) &
    TRACE_PID=$!
}

# ❗ FIX: no wait, no blocking
stop_trace_stream() {
    if [[ "$TRACE_PID" -ne 0 ]]; then
        kill "$TRACE_PID" 2>/dev/null || true
    fi
}

# ❗ FIX: trap does NOT wait
trap 'kill "$TRACE_PID" 2>/dev/null || true' EXIT

# -------------------------
# HEALTH CHECK
# -------------------------
system_is_healthy() {
    nmcli -t -f DEVICE,STATE device | grep -q ":connected"
}

# -------------------------
# DIAGNOSTIC SNAPSHOT
# -------------------------
log_milestone "DIAGNOSTIC_START"

{
    echo "=== DIAGNOSTIC SNAPSHOT START ==="
    echo "Timestamp: $(date)"
    echo "Kernel: $(uname -r)"

    nmcli -t -f DEVICE,STATE device 2>/dev/null || true
    ip route 2>/dev/null || true

    echo "=== DIAGNOSTIC SNAPSHOT END ==="
} >> "$TRACE_LOG"

start_trace_stream

STATUS="$(nmcli -t -f DEVICE,STATE device)"

log_milestone "DECISION_EVALUATION"

echo "=== CURRENT STATUS ==="
echo "$STATUS"
echo "$STATUS" >> "$TRACE_LOG"

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

if echo "$STATUS" | grep -q ":connected"; then

    log_milestone "network=connected"

    echo ""
    echo "======================================"
    echo " SYSTEM STATUS: HEALTHY"
    echo "======================================"

    format_report

    log_milestone "EXIT | CONNECTED (REPORT COMPLETE)"

    stop_trace_stream

    exit 0

else
    log_milestone "network=degraded"
    log_milestone "RECOVERY_INIT"

    echo "→ Decision: RECOVERY"
fi

# -------------------------
# REMAINDER OF YOUR SCRIPT UNCHANGED
# -------------------------