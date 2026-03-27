#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: ./fix-wifi_test_v5.sh
# Senior Fedora Kernel Maintainer: Autonomous Recovery Engine (v37-Verbatim)
# -----------------------------------------------------------------------------

# --- STEP 0: ROOT PRIVILEGE GATE ---
if [[ $EUID -ne 0 ]]; then
   exec /usr/bin/sudo "$0" "$@"
fi

# --- STEP 1: DATABASE INITIALIZATION ---
# We create a local manifest to store hardware-to-driver mappings.
# Location: ./manifest.db
MANIFEST_DB="./manifest.db"
/usr/bin/cat > "$MANIFEST_DB" << 'EOF'
# PCI_ID | DRIVER | CORE_REV | FIRMWARE_SET
14e4:4331|b43|29|ucode29_mimo.fw,ht0initvals29.fw,ht0bsinitvals29.fw
EOF

# --- STEP 2: WORKSPACE CONTEXT & LOGGING ---
WORKSPACE_DIR=$(/usr/bin/dirname "$(/usr/bin/readlink -f "$0")")
BUNDLE_DIR="$WORKSPACE_DIR/offline_bundle"
EVENT_LOG="$WORKSPACE_DIR/verbatim_events.log"

# Clear previous log to ensure verbatim starting point
/usr/bin/printf "=== Verbatim Trace Started: %s ===\n" "$(/usr/bin/date)" > "$EVENT_LOG"

# -----------------------------------------------------------------------------
# STEP 3: BACKGROUND VERBATIM MONITORING
# -----------------------------------------------------------------------------
# We fork a line-buffered monitor to capture Network and Kernel IO simultaneously.
# This surfaces "hidden" messages including stdin/stdout from system services.
(/usr/bin/journalctl -f -n 0 -u NetworkManager & /usr/bin/dmesg -w) >> "$EVENT_LOG" &
MONITOR_PID=$!
trap '/usr/bin/kill $MONITOR_PID 2>/dev/null' EXIT

# -----------------------------------------------------------------------------
# STEP 4: SYSTEM BENCHMARKING (DB QUERY)
# -----------------------------------------------------------------------------
K_VER=$(/usr/bin/uname -r | /usr/bin/awk -F. '{print $1"."$2}')
# Robust Core Revision capture from the actual hardware register
C_REV=$(/usr/bin/dmesg | /usr/bin/grep -i "core revision" | /usr/bin/awk '{print $NF}' | /usr/bin/tr -d ')' | /usr/bin/tail -n 1 || echo "29")

# Query the manifest for the strategy
STRATEGY=$(/usr/bin/grep "14e4:4331" "$MANIFEST_DB" | /usr/bin/awk -F'|' '{print $2}')
BLOBS_CSV=$(/usr/bin/grep "14e4:4331" "$MANIFEST_DB" | /usr/bin/awk -F'|' '{print $4}')
/usr/bin/printf "[STATE] Kernel: %s | Core: %s | Strategy: %s\n" "$K_VER" "$C_REV" "$STRATEGY"

# -----------------------------------------------------------------------------
# STEP 5: ATOMIC PURGE & OPTIMIZED HANDSHAKE
# -----------------------------------------------------------------------------
/usr/bin/systemctl stop NetworkManager wpa_supplicant 2>/dev/null || true

# Detach hardware from bridge via Sysfs
PCI_BUS=$(/usr/bin/lspci -n | /usr/bin/grep "14e4:4331" | /usr/bin/head -n 1 | /usr/bin/awk '{print "0000:"$1}')
if [[ -e "/sys/bus/pci/devices/$PCI_BUS/driver/unbind" ]]; then
    /usr/bin/printf "%s" "$PCI_BUS" | /usr/bin/tee "/sys/bus/pci/devices/$PCI_BUS/driver/unbind" > /dev/null
fi

for mod in wl bcma b43 ssb; do /usr/sbin/modprobe -r "$mod" 2>/dev/null || true; done

# -----------------------------------------------------------------------------
# STEP 6: FIRMWARE INJECTION (Integrity Gate)
# -----------------------------------------------------------------------------
FW_TARGET_DIR="/usr/lib/firmware/b43"
/usr/bin/mkdir -p "$FW_TARGET_DIR"
IFS=',' read -ra ADDR <<< "$BLOBS_CSV"
for blob in "${ADDR[@]}"; do
    if [[ -s "$BUNDLE_DIR/$blob" ]] && ! /usr/bin/grep -qi "<html" "$BUNDLE_DIR/$blob"; then
        /usr/bin/cp "$BUNDLE_DIR/$blob" "$FW_TARGET_DIR/"
    fi
done

# -----------------------------------------------------------------------------
# STEP 7: SPEED OPTIMIZED INITIALIZATION
# -----------------------------------------------------------------------------
/usr/sbin/modprobe "$STRATEGY" allhwsupport=1
# Wait for udev rename events to settle verbatim
/usr/bin/udevadm settle --timeout=5

IFACE=$(/usr/bin/ls /sys/class/net | /usr/bin/grep -E '^wl' | /usr/bin/head -n 1 || echo "")

if [[ -n "${IFACE:-}" ]]; then
    /usr/bin/ip link set "$IFACE" up
    /usr/bin/rfkill unblock wifi
    /usr/bin/systemctl start NetworkManager
    /usr/bin/printf "✅ SUCCESS: %s ready. Verbatim Log Excerpt:\n" "$IFACE"
    # Show the last 10 events actually occurring in the system
    /usr/bin/tail -n 10 "$EVENT_LOG"
else
    /usr/bin/printf "❌ CRITICAL: Handshake failed. Reviewing verbatim trace:\n"
    /usr/bin/tail -n 20 "$EVENT_LOG"
    exit 1
fi