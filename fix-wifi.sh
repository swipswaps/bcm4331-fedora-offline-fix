#!/usr/bin/env bash
set -uo pipefail

[[ $EUID -ne 0 ]] && echo "Error: Must run as root." && exit 1

function restore_services() {
    systemctl start NetworkManager 2>/dev/null || true
}
trap restore_services EXIT

PCI_ADDR="0000:02:00.0"
FW_DIR="/lib/firmware/b43"
FW_URL="https://raw.githubusercontent.com/LibreELEC/wlan-firmware/master/firmware/b43"
FILES=("ucode29_mimo.fw" "ht0initvals29.fw" "ht0bsinitvals29.fw")

echo "=== STEP 1: Driver and Conflict Purge ==="
systemctl stop NetworkManager 2>/dev/null || true
for mod in wl bcma b43 ssb; do
    modprobe -r "$mod" 2>/dev/null || true
done

echo "=== STEP 2: Deterministic Firmware Validation ==="
mkdir -p "$FW_DIR"
for file in "${FILES[@]}"; do
    TARGET="$FW_DIR/$file"
    [[ ! -f "$TARGET" ]] && wget -q -O "$TARGET" "$FW_URL/$file"
    if grep -qiE "<html|<!DOCTYPE" "$TARGET" 2>/dev/null; then
        rm -f "$TARGET"
        wget -q -O "$TARGET" "$FW_URL/$file"
    fi
done

echo "=== STEP 3: Kernel Handshake ==="
modprobe b43 allhwsupport=1

# Loop to allow for kernel device renaming (wlan0 -> wlp2s0b1)
echo "Waiting for kernel to instantiate interface..."
MAX_RETRIES=10
IFACE=""
for ((i=1; i<=MAX_RETRIES; i++)); do
    IFACE=$(ls /sys/class/net | grep -E '^wl' | head -n 1)
    [[ -n "$IFACE" ]] && break
    sleep 1
done

if [[ -z "$IFACE" ]]; then
    echo "Attempting Sysfs Force-Bind..."
    echo "14e4 4331" > /sys/bus/pci/drivers/b43/new_id 2>/dev/null || true
    echo "$PCI_ADDR" > /sys/bus/pci/drivers/b43/bind 2>/dev/null || true
    sleep 2
    IFACE=$(ls /sys/class/net | grep -E '^wl' | head -n 1)
fi

echo "=== STEP 4: Radio Calibration & SSID Recovery ==="
if [[ -n "$IFACE" ]]; then
    ip link set "$IFACE" up
    rfkill unblock all
    systemctl start NetworkManager
    nmcli radio wifi on
    echo "Waiting for hardware calibration..."
    sleep 5
    echo "✅ SUCCESS: $IFACE is active. SSID list follows:"
    nmcli -t -f SSID device wifi list | grep -v "^$" | head -n 5
else
    echo "❌ CRITICAL FAILURE: No interface detected."
    dmesg | grep -iE "b43|bcma" | tail -n 15
    exit 1
fi

echo "=== STEP 5: Persistence ==="
echo -e "blacklist bcma\nblacklist ssb\nblacklist wl" > /etc/modprobe.d/bcm4331-autofix.conf
echo "b43" > /etc/modules-load.d/b43.conf