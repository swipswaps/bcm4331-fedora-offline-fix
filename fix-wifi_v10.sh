#!/usr/bin/env bash
# Senior Fedora Kernel Maintainer: BCM4331 Deterministic Hard Reset (v9)
set -euo pipefail

[[ $EUID -ne 0 ]] && echo "Error: Must run as root (sudo)." && exit 1

CURRENT_KERNEL=$(uname -r)

echo "=== Step 1: Binary Verification ==="
# Ensure the file we manually injected is still present
MOD_FILE=$(find "/lib/modules/$CURRENT_KERNEL" -name "wl.ko*" | head -n 1)
if [[ -z "$MOD_FILE" ]]; then
    echo "⚠️ Driver missing. Re-injecting from cache..."
    KMOD_RPM=$(find /var/cache/akmods/wl/ -name "kmod-wl-$CURRENT_KERNEL*.rpm" | head -n 1)
    rpm2cpio "$KMOD_RPM" | cpio -idmv -D /
    depmod -a "$CURRENT_KERNEL"
fi

echo "=== Step 2: Service and Driver Flush ==="
# Stop the entire network stack to release hardware locks
# Ref: https://networkmanager.dev/docs/api/latest/nmcli.html
systemctl stop NetworkManager
systemctl stop wpa_supplicant
modprobe -r wl b43 bcma ssb 2>/dev/null || true

# Load the verified driver
modprobe wl
echo "✅ Driver 'wl' reloaded."

echo "=== Step 3: Radio and Service Restoration ==="
# Unblock hardware/software kills (Ref: https://man7.org/linux/man-pages/man8/rfkill.8.html)
rfkill unblock wifi
rfkill unblock all

# Start services in the specific order required for Broadcom STA
systemctl start wpa_supplicant
systemctl start NetworkManager

echo "Waiting 15 seconds for BCM4331 Radio Calibration..."
sleep 15

echo "=== Step 4: Deterministic SSID Discovery ==="
IFACE=$(ip link | grep -E 'wl|wlan' | awk -F: '{print $2}' | tr -d ' ' | head -n 1)

if [[ -n "$IFACE" ]]; then
    ip link set "$IFACE" up || true
    nmcli radio wifi on
    
    echo "Scanning for SSIDs..."
    nmcli device wifi rescan || true
    sleep 5
    
    # Check for actual SSID results (excluding headers)
    if nmcli -f SSID device wifi list | grep -v "^SSID" | grep -q "[[:alnum:]]"; then
        echo "✅ SUCCESS: Networks discovered."
        nmcli device wifi list
        echo -e "\n👉 ACTION: Run 'sudo nmcli device wifi connect SSID password PWD'"
    else
        echo "❌ Radio active but no SSIDs found. Hardware may be out of range."
        nmcli device status
    fi
else
    echo "❌ Critical: Interface wlp2s0 missing after hard reset."
    dmesg | grep -iE "wl|broadcom|4331" | tail -n 20
fi