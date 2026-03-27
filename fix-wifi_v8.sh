#!/usr/bin/env bash
# Senior Fedora Kernel Maintainer: Deterministic BCM4331 Final Fix (v8)
set -euo pipefail

[[ $EUID -ne 0 ]] && echo "Error: Must run as root (sudo)." && exit 1

CURRENT_KERNEL=$(uname -r)
PCI_ID="14e4:4331"

echo "=== Step 1: Binary & Driver Enforcement ==="
# Verify module exists; extract if missing (Ref: https://fedoraproject.org/wiki/Akmods)
MOD_FILE=$(find "/lib/modules/$CURRENT_KERNEL" -name "wl.ko*" | head -n 1)
if [[ -z "$MOD_FILE" ]]; then
    KMOD_RPM=$(find /var/cache/akmods/wl/ -name "kmod-wl-$CURRENT_KERNEL*.rpm" | head -n 1)
    if [[ -n "$KMOD_RPM" ]]; then
        rpm2cpio "$KMOD_RPM" | cpio -idmv -D /
        depmod -a "$CURRENT_KERNEL"
    fi
fi

# Force load wl and purge conflicts (Ref: https://rpmfusion.org/Howto/Broadcom)
if ! lsmod | grep -q "^wl "; then
    modprobe -r b43 bcma ssb wl 2>/dev/null || true
    modprobe wl
fi
echo "✅ Driver 'wl' active."

echo "=== Step 2: Active Radio Sync ==="
# Broadcom 'wl' often requires a hard radio toggle to initialize the scan engine
nmcli radio wifi off
sleep 1
nmcli radio wifi on
echo "Restarting NetworkManager to sync with wpa_supplicant..."
systemctl restart NetworkManager
sleep 5

echo "=== Step 3: Deterministic Scan Verification ==="
IFACE=$(ip link | grep -E 'wl|wlan' | awk -F: '{print $2}' | tr -d ' ' | head -n 1)

if [[ -n "$IFACE" ]]; then
    ip link set "$IFACE" up || true
    echo "Performing active scan on $IFACE..."
    nmcli device wifi rescan || true
    sleep 3
    
    # Filter out headers and empty results to verify real data
    NETWORKS=$(nmcli --terse --fields SSID device wifi list | grep -v "^$" | wc -l)
    
    if [[ "$NETWORKS" -gt 0 ]]; then
        echo "✅ SUCCESS: $NETWORKS networks discovered."
        nmcli -f SSID,SIGNAL,BARS device wifi list | head -n 10
        
        STATE=$(nmcli -t -f DEVICE,STATE device | grep "^$IFACE" | cut -d: -f2)
        if [[ "$STATE" != "connected" ]]; then
            echo -e "\n👉 RUN THIS COMMAND TO FINALIZE CONNECTION:"
            echo "sudo nmcli device wifi connect 'YOUR_SSID' password 'YOUR_PASSWORD'"
        else
            echo "✅ SUCCESS: Interface is already connected."
        fi
    else
        echo "❌ Radio active but no networks found."
        echo "Checking for Hardware Block (RF-KILL)..."
        rfkill unblock all
        echo "Retry 'nmcli device wifi list' in 10 seconds."
    fi
else
    echo "❌ Interface missing. Check 'sudo dmesg | grep wl'."
    exit 1
fi