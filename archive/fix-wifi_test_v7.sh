#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: ./fix-wifi.sh
# Senior Fedora Kernel Maintainer: Autonomous Recovery Engine (v40-Database)
# -----------------------------------------------------------------------------

# --- STEP 0: ROOT PRIVILEGE GATE ---
if [[ $EUID -ne 0 ]]; then
   exec /usr/bin/sudo "$0" "$@"
fi

# --- STEP 1: CONTEXT & LOGGING ---
# Absolute path resolution for workspace files
WORKSPACE_DIR=$(/usr/bin/dirname "$(/usr/bin/readlink -f "$0")")
MANIFEST_DB="$WORKSPACE_DIR/manifest.db"
TRACE_LOG="$WORKSPACE_DIR/verbatim_handshake.log"

# Initialization of the manifest database if missing
if [[ ! -f "$MANIFEST_DB" ]]; then
    /usr/bin/printf "14e4:4331:b43:29:ucode29_mimo.fw,ht0initvals29.fw,ht0bsinitvals29.fw\n" > "$MANIFEST_DB"
fi

# -----------------------------------------------------------------------------
# STEP 2: BACKGROUND TRACE ENGINE (Verbatim Events)
# -----------------------------------------------------------------------------
# Use stdbuf to force line-buffering for real-time visibility.
/usr/bin/printf "=== Verbatim Handshake Log: %s ===\n" "$(/usr/bin/date)" > "$TRACE_LOG"
(/usr/bin/stdbuf -oL /usr/bin/journalctl -f -n 0 & /usr/bin/stdbuf -oL /usr/bin/dmesg -w) >> "$TRACE_LOG" &
MONITOR_PID=$!
trap '/usr/bin/kill $MONITOR_PID 2>/dev/null' EXIT

# -----------------------------------------------------------------------------
# STEP 3: DATABASE QUERY & ATOMIC PURGE
# -----------------------------------------------------------------------------
K_VER=$(/usr/bin/uname -r | /usr/bin/awk -F. '{print $1"."$2}')
DB_ENTRY=$(/usr/bin/grep "14e4:4331" "$MANIFEST_DB")
STRATEGY=$(/usr/bin/printf "%s" "$DB_ENTRY" | /usr/bin/awk -F: '{print $3}')
BLOBS_CSV=$(/usr/bin/printf "%s" "$DB_ENTRY" | /usr/bin/awk -F: '{print $5}')

/usr/bin/systemctl stop NetworkManager wpa_supplicant 2>/dev/null || true

# Releasing hardware from bridge drivers
PCI_BUS=$(/usr/bin/lspci -n | /usr/bin/grep "14e4:4331" | /usr/bin/head -n 1 | /usr/bin/awk '{print "0000:"$1}')
if [[ -e "/sys/bus/pci/devices/$PCI_BUS/driver/unbind" ]]; then
    /usr/bin/printf "%s" "$PCI_BUS" | /usr/bin/tee "/sys/bus/pci/devices/$PCI_BUS/driver/unbind" > /dev/null
fi
for mod in wl bcma b43 ssb; do /usr/sbin/modprobe -r "$mod" 2>/dev/null || true; done

# -----------------------------------------------------------------------------
# STEP 4: FIRMWARE INJECTION & HANDSHAKE
# -----------------------------------------------------------------------------
FW_TARGET_DIR="/usr/lib/firmware/b43"
/usr/bin/mkdir -p "$FW_TARGET_DIR"
IFS=',' read -ra ADDR <<< "$BLOBS_CSV"
for blob in "${ADDR[@]}"; do
    /usr/bin/cp "$WORKSPACE_DIR/offline_bundle/$blob" "$FW_TARGET_DIR/" 2>/dev/null || true
done

/usr/sbin/modprobe "$STRATEGY" allhwsupport=1
/usr/bin/udevadm settle --timeout=5

# Polling for udev name (Predictable Interface Names)
IFACE=""
for i in {1..5}; do
    IFACE=$(/usr/bin/ls /sys/class/net | /usr/bin/grep -E '^wl' | /usr/bin/head -n 1 || echo "")
    [[ -n "$IFACE" ]] && break
    sleep 1
done

# -----------------------------------------------------------------------------
# STEP 5: RADIO BENCHMARKING
# -----------------------------------------------------------------------------
if [[ -n "$IFACE" ]]; then
    /usr/bin/ip link set "$IFACE" up
    /usr/bin/rfkill unblock wifi
    /usr/bin/systemctl start NetworkManager
    
    /usr/bin/printf "✅ interface %s up. Discovering SSIDs...\n" "$IFACE"
    for i in {1..10}; do
        SSID=$(/usr/bin/nmcli -t -f SSID device wifi list | /usr/bin/grep -v "^$" | /usr/bin/head -n 1 || echo "")
        if [[ -n "$SSID" ]]; then
            /usr/bin/printf "✅ Handshake Complete. SSID Seen: %s\n" "$SSID"
            break
        fi
        sleep 1
    done
    # Filter the trace log specifically for the active interface to show hidden messages
    /usr/bin/grep "$IFACE" "$TRACE_LOG" | /usr/bin/tail -n 10
else
    /usr/bin/printf "❌ FAILED: Check dmesg.\n"
    exit 1
fi