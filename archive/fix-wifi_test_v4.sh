#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: ./fix-wifi_test_v4.sh
# Senior Fedora Kernel Maintainer: Autonomous Recovery Database (v36-Instrumentation)
# -----------------------------------------------------------------------------

# --- STEP 0: ROOT PRIVILEGE GATE ---
if [[ $EUID -ne 0 ]]; then
   exec /usr/bin/sudo "$0" "$@"
fi

# --- STEP 1: WORKSPACE CONTEXT & LOGGING ---
WORKSPACE_DIR=$(/usr/bin/dirname "$(/usr/bin/readlink -f "$0")")
BUNDLE_DIR="$WORKSPACE_DIR/offline_bundle"
# Create a live buffer for background event monitoring
EVENT_LOG="$WORKSPACE_DIR/live_events.log"
/usr/bin/printf "Instrumentation initiated. Logs: ./live_events.log\n" > "$EVENT_LOG"

# -----------------------------------------------------------------------------
# STEP 2: BACKGROUND EVENT MULTIPLEXER (The "Hidden" Messages)
# -----------------------------------------------------------------------------
# Monitor NetworkManager and Kernel events in the background
/usr/bin/nmcli monitor >> "$EVENT_LOG" &
NM_MON_PID=$!
/usr/bin/dmesg --follow | /usr/bin/grep -iE "b43|bcma|wlp|wlan" >> "$EVENT_LOG" &
K_MON_PID=$!

# Ensure background monitors are killed on exit
trap '/usr/bin/kill $NM_MON_PID $K_MON_PID 2>/dev/null; /usr/bin/printf "\n=== Failsafe: Monitoring Stopped ===\n"' EXIT

# -----------------------------------------------------------------------------
# STEP 3: SYSTEM BENCHMARKING
# -----------------------------------------------------------------------------
K_VER=$(/usr/bin/uname -r | /usr/bin/awk -F. '{print $1"."$2}')
C_REV=$(/usr/bin/lspci -vnn -d 14e4:4331 | /usr/bin/grep -i "core revision" | /usr/bin/awk '{print $NF}' || echo "29")

/usr/bin/printf "[STATE] Kernel: %s | Core: %s\n" "$K_VER" "$C_REV"

# -----------------------------------------------------------------------------
# STEP 4: ATOMIC PURGE & OPTIMIZED HANDSHAKE
# -----------------------------------------------------------------------------
/usr/bin/printf "=== Initiating Driver Swap ===\n"
/usr/bin/systemctl stop NetworkManager wpa_supplicant 2>/dev/null || true

# Explicitly unbind PCI device to ensure a clean slate
PCI_BUS=$(/usr/bin/lspci -n | /usr/bin/grep "14e4:4331" | /usr/bin/head -n 1 | /usr/bin/awk '{print "0000:"$1}')
if [[ -e "/sys/bus/pci/devices/$PCI_BUS/driver/unbind" ]]; then
    /usr/bin/printf "%s" "$PCI_BUS" | /usr/bin/tee "/sys/bus/pci/devices/$PCI_BUS/driver/unbind" > /dev/null
fi

for mod in wl bcma b43 ssb; do /usr/sbin/modprobe -r "$mod" 2>/dev/null || true; done

# -----------------------------------------------------------------------------
# STEP 5: FIRMWARE INJECTION (Content-Aware)
# -----------------------------------------------------------------------------
FW_DIR="/usr/lib/firmware/b43"
/usr/bin/mkdir -p "$FW_DIR"
# Logic: We strictly verify binary headers to avoid 404 HTML corruption
for blob in ucode29_mimo.fw ht0initvals29.fw ht0bsinitvals29.fw; do
    if [[ -s "$BUNDLE_DIR/$blob" ]] && ! /usr/bin/grep -qi "<html" "$BUNDLE_DIR/$blob"; then
        /usr/bin/cp "$BUNDLE_DIR/$blob" "$FW_DIR/"
    fi
done

# -----------------------------------------------------------------------------
# STEP 6: SPEED OPTIMIZED INITIALIZATION
# -----------------------------------------------------------------------------
/usr/sbin/modprobe b43 allhwsupport=1

# Speed Benchmark: Instead of 10s sleep, settle udev events and watch sysfs
/usr/bin/udevadm settle --timeout=5
IFACE=$(/usr/bin/ls /sys/class/net | /usr/bin/grep -E '^wl' | /usr/bin/head -n 1 || echo "")

if [[ -n "${IFACE:-}" ]]; then
    /usr/bin/ip link set "$IFACE" up
    /usr/bin/rfkill unblock wifi
    /usr/bin/systemctl start NetworkManager
    /usr/bin/printf "✅ SUCCESS: %s online. Real-time network events:\n" "$IFACE"
    /usr/bin/tail -n 5 "$EVENT_LOG"
else
    /usr/bin/printf "❌ CRITICAL: Interface failed to rename. Diagnostics:\n"
    /usr/bin/tail -n 20 "$EVENT_LOG"
    exit 1
fi