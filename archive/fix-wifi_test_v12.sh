#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: fix-wifi_test_v10.sh  (UPGRADED - State-Aware, Non-Destructive)
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

# -------------------------
# HEALTH CHECK FUNCTION
# -------------------------
system_is_healthy() {
    nmcli -t -f DEVICE,STATE device | grep -q ":connected"
}

# -------------------------
# EARLY EXIT (CRITICAL)
# -------------------------
if system_is_healthy; then
    echo -e "${GREEN}→ System already healthy. No action required.${NC}"
    exit 0
fi

# -------------------------
# MANIFEST INIT
# -------------------------
if [[ ! -f "$MANIFEST_DB" ]]; then
    cat > "$MANIFEST_DB" << 'MANIFEST'
# PCI_ID:STRATEGY:MIN_KERNEL:MAX_KERNEL:BLOBS_CSV:NOTES
14e4:4331:b43:6.17:999:ucode29_mimo.fw,ht0initvals29.fw,ht0bsinitvals29.fw:b43 is reliable on 6.17–6.19
MANIFEST
    echo -e "${GREEN}✓ Created fresh manifest.db${NC}"
fi

# -------------------------
# TRACE LOGGING
# -------------------------
printf "=== Handshake Log %s ===\n" "$(date)" > "$TRACE_LOG"
(stdbuf -oL journalctl -f -n 0 & stdbuf -oL dmesg -w) >> "$TRACE_LOG" &
MONITOR_PID=$!
trap 'kill $MONITOR_PID 2>/dev/null' EXIT

# -------------------------
# DETERMINE DRIVER STRATEGY
# -------------------------
K_VER="$(uname -r | cut -d. -f1,2)"
DB_ENTRY=$(grep -E "^14e4:4331" "$MANIFEST_DB" | head -n1)
STRATEGY=$(echo "$DB_ENTRY" | cut -d: -f3)
BLOBS_CSV=$(echo "$DB_ENTRY" | cut -d: -f6)

echo -e "${YELLOW}→ Kernel $K_VER detected | Strategy: $STRATEGY${NC}"

# -------------------------
# SAFE DRIVER STATE CHECK
# -------------------------
if ! lsmod | grep -q "$STRATEGY"; then
    echo -e "${YELLOW}→ Loading driver: $STRATEGY${NC}"
    modprobe "$STRATEGY" allhwsupport=1
else
    echo -e "${GREEN}→ Driver already loaded: $STRATEGY${NC}"
fi

udevadm settle --timeout=5

# -------------------------
# FIRMWARE INJECTION (IDEMPOTENT)
# -------------------------
FW_TARGET_DIR="/usr/lib/firmware/b43"
mkdir -p "$FW_TARGET_DIR"

IFS=',' read -ra BLOBS <<< "$BLOBS_CSV"

for blob in "${BLOBS[@]}"; do
    if [[ -f "$BUNDLE_DIR/$blob" ]]; then
        if [[ ! -f "$FW_TARGET_DIR/$blob" ]] || ! cmp -s "$BUNDLE_DIR/$blob" "$FW_TARGET_DIR/$blob"; then
            cp "$BUNDLE_DIR/$blob" "$FW_TARGET_DIR/"
            echo -e "${GREEN}✓ Injected $blob${NC}"
        else
            echo -e "${YELLOW}→ $blob already up-to-date${NC}"
        fi
    else
        echo -e "${RED}❌ Missing firmware in bundle: $blob${NC}"
    fi
done

# -------------------------
# ENSURE NETWORKMANAGER IS RUNNING (SAFE)
# -------------------------
if ! systemctl is-active --quiet NetworkManager; then
    echo -e "${YELLOW}→ Starting NetworkManager${NC}"
    systemctl start NetworkManager
fi

# -------------------------
# INTERFACE DETECTION
# -------------------------
IFACE=""
for i in {1..10}; do
    IFACE=$(ls /sys/class/net 2>/dev/null | grep -E '^wl' | head -n1 || echo "")
    [[ -n "$IFACE" ]] && break
    sleep 0.8
done

if [[ -z "$IFACE" ]]; then
    echo -e "${RED}❌ No wireless interface detected${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Interface detected: $IFACE${NC}"

ip link set "$IFACE" up
rfkill unblock wifi

# -------------------------
# SCAN FOR NETWORKS
# -------------------------
echo -e "${YELLOW}Scanning for networks...${NC}"

SSID=""
for i in {1..12}; do
    SSID=$(nmcli -t -f SSID device wifi list 2>/dev/null | grep -v '^$' | head -n1 || echo "")
    [[ -n "$SSID" ]] && break
    sleep 1
done

if [[ -n "$SSID" ]]; then
    echo -e "${GREEN}✅ SUCCESS — Wi-Fi ready. First SSID seen: $SSID${NC}"
else
    echo -e "${YELLOW}⚠️ No SSIDs visible yet (may still be initializing)${NC}"
fi

# -------------------------
# TRACE OUTPUT
# -------------------------
grep "$IFACE" "$TRACE_LOG" | tail -n 12