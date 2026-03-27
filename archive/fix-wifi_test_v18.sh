#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: fix-wifi_test_v18.sh  (Non-Blocking + Human-Readable + Full Feature Retained)
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
# SAFE TRACE SNAPSHOT (NO HANG)
# -------------------------
TRACE_PID=0

start_trace_stream() {
    {
        echo "=== TRACE START $(date) ==="
        echo "--- LAST JOURNAL ENTRIES ---"
        journalctl -n 50 --no-pager 2>/dev/null || true

        echo ""
        echo "--- LAST KERNEL MESSAGES ---"
        dmesg | tail -n 50 2>/dev/null || true

        echo "=== TRACE END $(date) ==="
    } >> "$TRACE_LOG" &
    TRACE_PID=$!
}

stop_trace_stream() {
    if [[ "$TRACE_PID" -ne 0 ]]; then
        kill "$TRACE_PID" 2>/dev/null || true
    fi
}

trap 'stop_trace_stream' EXIT

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

echo "=== DIAGNOSTIC SNAPSHOT START ===" >> "$TRACE_LOG"
echo "Timestamp: $(date)" >> "$TRACE_LOG"
echo "Kernel: $(uname -r)" >> "$TRACE_LOG"

nmcli -t -f DEVICE,STATE device >> "$TRACE_LOG" 2>/dev/null || true
ip route >> "$TRACE_LOG" 2>/dev/null || true

echo "=== DIAGNOSTIC SNAPSHOT END ===" >> "$TRACE_LOG"

# Start trace (safe snapshot, non-blocking)
start_trace_stream

# -------------------------
# STATUS + DECISION
# -------------------------
STATUS="$(nmcli -t -f DEVICE,STATE device)"

log_milestone "DECISION_EVALUATION"

echo "=== CURRENT STATUS ==="
echo "$STATUS"

echo "$STATUS" >> "$TRACE_LOG"

# -------------------------
# HUMAN-READABLE REPORT FUNCTION
# -------------------------
format_report() {
    echo ""
    echo "======================================"
    echo "      NETWORK HEALTH REPORT"
    echo "======================================"

    echo ""
    echo "📡 INTERFACES"
    nmcli device status

    echo ""
    echo "🌐 ACTIVE CONNECTIONS"
    nmcli connection show --active

    echo ""
    echo "🧭 ROUTING TABLE"
    ip route | column -t

    echo ""
    echo "📶 WIRELESS DETAILS"
    iw dev 2>/dev/null || echo "iw not available"

    echo ""
    echo "🧱 LOADED DRIVERS"
    lsmod | grep -E 'b43|cfg80211|mac80211|ssb|bcma' || true

    echo ""
    echo "📁 FIRMWARE FILES"
    ls -lh /usr/lib/firmware/b43 2>/dev/null || true

    echo ""
    echo "🖥 KERNEL"
    uname -r

    echo ""
    echo "📊 DNS"
    nmcli dev show | grep DNS || true

    echo ""
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

    exit 0

else
    log_milestone "network=degraded"
    log_milestone "RECOVERY_INIT"

    echo "→ Decision: RECOVERY"
fi

# -------------------------
# MANIFEST INIT
# -------------------------
if [[ ! -f "$MANIFEST_DB" ]]; then
    cat > "$MANIFEST_DB" << 'MANIFEST'
# PCI_ID:STRATEGY:MIN_KERNEL:MAX_KERNEL:BLOBS_CSV:NOTES
14e4:4331:b43:6.17:999:ucode29_mimo.fw,ht0initvals29.fw,ht0bsinitvals29.fw:b43 is reliable on 6.17–6.19
MANIFEST
fi

# -------------------------
# DRIVER STRATEGY
# -------------------------
K_VER="$(uname -r | cut -d. -f1,2)"
DB_ENTRY=$(grep -E "^14e4:4331" "$MANIFEST_DB" | head -n1)
STRATEGY=$(echo "$DB_ENTRY" | cut -d: -f3)
BLOBS_CSV=$(echo "$DB_ENTRY" | cut -d: -f6)

echo -e "${YELLOW}→ Kernel $K_VER | Strategy: $STRATEGY${NC}"

# -------------------------
# DRIVER LOAD
# -------------------------
if ! lsmod | grep -q "$STRATEGY"; then
    modprobe "$STRATEGY" allhwsupport=1
fi

udevadm settle --timeout=5

# -------------------------
# FIRMWARE
# -------------------------
FW_TARGET_DIR="/usr/lib/firmware/b43"
mkdir -p "$FW_TARGET_DIR"

IFS=',' read -ra BLOBS <<< "$BLOBS_CSV"

for blob in "${BLOBS[@]}"; do
    if [[ -f "$BUNDLE_DIR/$blob" ]]; then
        if [[ ! -f "$FW_TARGET_DIR/$blob" ]] || ! cmp -s "$BUNDLE_DIR/$blob" "$FW_TARGET_DIR/$blob"; then
            cp "$BUNDLE_DIR/$blob" "$FW_TARGET_DIR/"
        fi
    fi
done

# -------------------------
# NETWORKMANAGER
# -------------------------
if ! systemctl is-active --quiet NetworkManager; then
    systemctl start NetworkManager
fi

# -------------------------
# INTERFACE
# -------------------------
IFACE=""
for i in {1..10}; do
    IFACE=$(ls /sys/class/net 2>/dev/null | grep -E '^wl' | head -n1 || echo "")
    [[ -n "$IFACE" ]] && break
    sleep 0.8
done

[[ -z "$IFACE" ]] && exit 1

ip link set "$IFACE" up
rfkill unblock wifi

# -------------------------
# SCAN
# -------------------------
echo -e "${YELLOW}Scanning...${NC}"

SSID=""
for i in {1..12}; do
    SSID=$(nmcli -t -f SSID device wifi list 2>/dev/null | grep -v '^$' | head -n1 || echo "")
    [[ -n "$SSID" ]] && break
    sleep 1
done

if [[ -n "$SSID" ]]; then
    echo -e "${GREEN}✅ Wi-Fi ready: $SSID${NC}"
else
    echo -e "${YELLOW}⚠️ No SSIDs visible yet${NC}"
fi