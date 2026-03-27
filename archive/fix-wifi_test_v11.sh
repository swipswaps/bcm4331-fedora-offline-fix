# -----------------------------------------------------------------------------
# File: fix-wifi.sh  (v42-full - Full Database + Upgrade UX)
# -----------------------------------------------------------------------------

set -euo pipefail
if [[ $EUID -ne 0 ]]; then exec sudo "$0" "$@"; fi

WORKSPACE_DIR="$(dirname "$(readlink -f "$0")")"
MANIFEST_DB="$WORKSPACE_DIR/manifest.db"
BUNDLE_DIR="$WORKSPACE_DIR/offline_bundle"
TRACE_LOG="$WORKSPACE_DIR/verbatim_handshake.log"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

# Create enhanced manifest if missing
if [[ ! -f "$MANIFEST_DB" ]]; then
    cat > "$MANIFEST_DB" << 'MANIFEST'
# PCI_ID:STRATEGY:MIN_KERNEL:MAX_KERNEL:BLOBS_CSV:NOTES
14e4:4331:b43:6.17:999:ucode29_mimo.fw,ht0initvals29.fw,ht0bsinitvals29.fw:b43 is reliable on 6.17–6.19
MANIFEST
    echo -e "${GREEN}✓ Created fresh manifest.db${NC}"
fi

# --- Background trace (real-time, line-buffered) ---
printf "=== Handshake Log %s ===\n" "$(date)" > "$TRACE_LOG"
(stdbuf -oL journalctl -f -n 0 & stdbuf -oL dmesg -w) >> "$TRACE_LOG" &
MONITOR_PID=$!
trap 'kill $MONITOR_PID 2>/dev/null' EXIT

K_VER="$(uname -r | cut -d. -f1,2)"
DB_ENTRY=$(grep -E "^14e4:4331" "$MANIFEST_DB" | head -n1)
STRATEGY=$(echo "$DB_ENTRY" | cut -d: -f3)
MIN_K=$(echo "$DB_ENTRY" | cut -d: -f4)
MAX_K=$(echo "$DB_ENTRY" | cut -d: -f5)
BLOBS_CSV=$(echo "$DB_ENTRY" | cut -d: -f6)

echo -e "${YELLOW}→ Kernel $K_VER detected | Strategy: $STRATEGY${NC}"

# Atomic purge
systemctl stop NetworkManager wpa_supplicant 2>/dev/null || true
for mod in wl bcma b43 ssb; do modprobe -r "$mod" 2>/dev/null || true; done

# Firmware injection (idempotent)
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
    fi
done

# Load driver
modprobe "$STRATEGY" allhwsupport=1
udevadm settle --timeout=5

# Interface detection with retry
IFACE=""
for i in {1..10}; do
    IFACE=$(ls /sys/class/net 2>/dev/null | grep -E '^wl' | head -n1 || echo "")
    [[ -n "$IFACE" ]] && break
    sleep 0.8
done

if [[ -n "$IFACE" ]]; then
    ip link set "$IFACE" up
    rfkill unblock wifi
    systemctl start NetworkManager

    echo -e "${GREEN}✅ Interface $IFACE is UP${NC}"
    echo -e "${YELLOW}Scanning for networks...${NC}"

    for i in {1..12}; do
        SSID=$(nmcli -t -f SSID device wifi list 2>/dev/null | grep -v '^$' | head -n1 || echo "")
        [[ -n "$SSID" ]] && break
        sleep 1
    done

    if [[ -n "$SSID" ]]; then
        echo -e "${GREEN}✅ SUCCESS — Wi-Fi ready. First SSID seen: $SSID${NC}"
    else
        echo -e "${YELLOW}⚠️  Interface up but no SSIDs visible yet${NC}"
    fi

    grep "$IFACE" "$TRACE_LOG" | tail -n 12
else
    echo -e "${RED}❌ No interface — check $TRACE_LOG${NC}"
    exit 1
fi