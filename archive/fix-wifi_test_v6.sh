#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: ./fix-wifi_test_v6.sh
# Senior Fedora Kernel Maintainer: Autonomous Recovery Engine (v38-Handshake)
# -----------------------------------------------------------------------------

# --- STEP 0: ROOT PRIVILEGE GATE ---
if [[ $EUID -ne 0 ]]; then
   exec /usr/bin/sudo "$0" "$@"
fi

# --- STEP 1: DATABASE INITIALIZATION ---
# We externalize the data to ./manifest.db for seamless upgrades.
MANIFEST_DB="./manifest.db"
/usr/bin/printf "14e4:4331:b43:29:ucode29_mimo.fw,ht0initvals29.fw,ht0bsinitvals29.fw\n" > "$MANIFEST_DB"

# --- STEP 2: WORKSPACE CONTEXT & LOGGING ---
WORKSPACE_DIR=$(/usr/bin/dirname "$(/usr/bin/readlink -f "$0")")
BUNDLE_DIR="$WORKSPACE_DIR/offline_bundle"
EVENT_LOG="$WORKSPACE_DIR/verbatim_events.log"

/usr/bin/printf "Handshake monitor initiated. Logs: ./verbatim_events.log\n" > "$EVENT_LOG"

# -----------------------------------------------------------------------------
# STEP 3: BACKGROUND VERBATIM MONITORING (Filtered)
# -----------------------------------------------------------------------------
# Fork background monitor to capture only the relevant wireless handshake.
(/usr/bin/journalctl -f -n 0 -u NetworkManager & /usr/bin/dmesg -w) >> "$EVENT_LOG" &
MONITOR_PID=$!
trap '/usr/bin/kill $MONITOR_PID 2>/dev/null' EXIT

# -----------------------------------------------------------------------------
# STEP 4: SYSTEM BENCHMARKING (DB PARSE)
# -----------------------------------------------------------------------------
K_VER=$(/usr/bin/uname -r | /usr/bin/awk -F. '{print $1"."$2}')
# Query the manifest for the strategy based on PCI ID
DB_ENTRY=$(/usr/bin/grep "14e4:4331" "$MANIFEST_DB" || echo "")
STRATEGY=$(/usr/bin/printf "%s" "$DB_ENTRY" | /usr/bin/awk -F: '{print $3}')
BLOBS_CSV=$(/usr/bin/printf "%s" "$DB_ENTRY" | /usr/bin/awk -F: '{print $5}')

/usr/bin/printf "[STATE] Kernel: %s | Strategy: %s\n" "$K_VER" "$STRATEGY"

# -----------------------------------------------------------------------------
# STEP 5: ATOMIC PURGE & FIRMWARE INJECTION
# -----------------------------------------------------------------------------
/usr/bin/systemctl stop NetworkManager wpa_supplicant 2>/dev/null || true
PCI_BUS=$(/usr/bin/lspci -n | /usr/bin/grep "14e4:4331" | /usr/bin/head -n 1 | /usr/bin/awk '{print "0000:"$1}')
if [[ -e "/sys/bus/pci/devices/$PCI_BUS/driver/unbind" ]]; then
    /usr/bin/printf "%s" "$PCI_BUS" | /usr/bin/tee "/sys/bus/pci/devices/$PCI_BUS/driver/unbind" > /dev/null
fi
for mod in wl bcma b43 ssb; do /usr/sbin/modprobe -r "$mod" 2>/dev/null || true; done

FW_TARGET_DIR="/usr/lib/firmware/b43"
/usr/bin/mkdir -p "$FW_TARGET_DIR"
IFS=',' read -ra ADDR <<< "$BLOBS_CSV"
for blob in "${ADDR[@]}"; do
    if [[ -s "$BUNDLE_DIR/$blob" ]] && ! /usr/bin/grep -qi "<html" "$BUNDLE_DIR/$blob"; then
        /usr/bin/cp "$BUNDLE_DIR/$blob" "$FW_TARGET_DIR/"
    fi
done

# -----------------------------------------------------------------------------
# STEP 6: OPTIMIZED INITIALIZATION
# -----------------------------------------------------------------------------
/usr/sbin/modprobe "$STRATEGY" allhwsupport=1
/usr/bin/udevadm settle --timeout=5
IFACE=$(/usr/bin/ls /sys/class/net | /usr/bin/grep -E '^wl' | /usr/bin/head -n 1 || echo "")

# -----------------------------------------------------------------------------
# STEP 7: VERBATIM HANDSHAKE VALIDATION
# -----------------------------------------------------------------------------
if [[ -n "${IFACE:-}" ]]; then
    /usr/bin/ip link set "$IFACE" up
    /usr/bin/rfkill unblock wifi
    /usr/bin/systemctl start NetworkManager
    /usr/bin/printf "✅ Interface %s initialized. Monitoring Handshake...\n" "$IFACE"
    
    # Speed Benchmark: Instead of arbitrary sleep, we loop until SSID results appear
    for i in {1..10}; do
        SSID_FOUND=$(/usr/bin/nmcli -t -f SSID device wifi list | /usr/bin/grep -v "^$" | /usr/bin/head -n 1 || echo "")
        if [[ -n "$SSID_FOUND" ]]; then
            /usr/bin/printf "✅ Handshake Successful. First SSID discovered: %s\n" "$SSID_FOUND"
            break
        fi
        /usr/bin/printf "Waiting for radio calibration... (%ds)\n" "$i"
        sleep 1
    done

    /usr/bin/printf "=== Verbatim Handshake Excerpt ===\n"
    # Filter log to only show activity related to the specific interface
    /usr/bin/grep "$IFACE" "$EVENT_LOG" | /usr/bin/tail -n 10
else
    /usr/bin/printf "❌ CRITICAL: Interface failed to initialize.\n"
    exit 1
fi