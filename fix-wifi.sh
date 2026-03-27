#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: ./fix-wifi.sh
# Senior Fedora Kernel Maintainer: Autonomous Recovery Engine (v39)
# -----------------------------------------------------------------------------

# --- STEP 0: ROOT PRIVILEGE GATE ---
if [[ $EUID -ne 0 ]]; then
   exec /usr/bin/sudo "$0" "$@"
fi

# --- STEP 1: CONTEXT & DATABASE ---
MANIFEST_DB="./manifest.db"
WORKSPACE_DIR=$(/usr/bin/dirname "$(/usr/bin/readlink -f "$0")")
BUNDLE_DIR="$WORKSPACE_DIR/offline_bundle"
EVENT_LOG="$WORKSPACE_DIR/verbatim_events.log"

# --- STEP 2: BACKGROUND MONITORING ---
/usr/bin/printf "Verbatim monitor started.\n" > "$EVENT_LOG"
(/usr/bin/journalctl -f -n 0 -u NetworkManager & /usr/bin/dmesg -w) >> "$EVENT_LOG" &
MONITOR_PID=$!
trap '/usr/bin/kill $MONITOR_PID 2>/dev/null' EXIT

# --- STEP 3: DATABASE QUERY ---
K_VER=$(/usr/bin/uname -r | /usr/bin/awk -F. '{print $1"."$2}')
DB_ENTRY=$(/usr/bin/grep "14e4:4331" "$MANIFEST_DB" || echo "")
STRATEGY=$(/usr/bin/printf "%s" "$DB_ENTRY" | /usr/bin/awk -F: '{print $3}')
BLOBS_CSV=$(/usr/bin/printf "%s" "$DB_ENTRY" | /usr/bin/awk -F: '{print $5}')

# --- STEP 4: ATOMIC PURGE ---
/usr/bin/systemctl stop NetworkManager wpa_supplicant 2>/dev/null || true
PCI_BUS=$(/usr/bin/lspci -n | /usr/bin/grep "14e4:4331" | /usr/bin/head -n 1 | /usr/bin/awk '{print "0000:"$1}')
if [[ -e "/sys/bus/pci/devices/$PCI_BUS/driver/unbind" ]]; then
    /usr/bin/printf "%s" "$PCI_BUS" | /usr/bin/tee "/sys/bus/pci/devices/$PCI_BUS/driver/unbind" > /dev/null
fi
for mod in wl bcma b43 ssb; do /usr/sbin/modprobe -r "$mod" 2>/dev/null || true; done

# --- STEP 5: FIRMWARE INJECTION ---
FW_TARGET_DIR="/usr/lib/firmware/b43"
/usr/bin/mkdir -p "$FW_TARGET_DIR"
IFS=',' read -ra ADDR <<< "$BLOBS_CSV"
for blob in "${ADDR[@]}"; do
    if [[ -s "$BUNDLE_DIR/$blob" ]] && ! /usr/bin/grep -qi "<html" "$BUNDLE_DIR/$blob"; then
        /usr/bin/cp "$BUNDLE_DIR/$blob" "$FW_TARGET_DIR/"
    fi
done

# --- STEP 6: INITIALIZATION ---
/usr/sbin/modprobe "$STRATEGY" allhwsupport=1
/usr/bin/udevadm settle --timeout=5
IFACE=$(/usr/bin/ls /sys/class/net | /usr/bin/grep -E '^wl' | /usr/bin/head -n 1 || echo "")

# --- STEP 7: HANDSHAKE VALIDATION ---
if [[ -n "${IFACE:-}" ]]; then
    /usr/bin/ip link set "$IFACE" up
    /usr/bin/rfkill unblock wifi
    /usr/bin/systemctl start NetworkManager
    for i in {1..10}; do
        SSID=$(/usr/bin/nmcli -t -f SSID device wifi list | /usr/bin/grep -v "^$" | /usr/bin/head -n 1 || echo "")
        if [[ -n "$SSID" ]]; then
            /usr/bin/printf "✅ SUCCESS: %s ready. Handshake Log:\n" "$IFACE"
            break
        fi
        /usr/bin/sleep 1
    done
    /usr/bin/grep "$IFACE" "$EVENT_LOG" | /usr/bin/tail -n 10
fi
