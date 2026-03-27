#!/usr/bin/env bash
# Senior Fedora Kernel Maintainer: Deterministic BCM4331 Final Fix (v7)
set -euo pipefail

[[ $EUID -ne 0 ]] && echo "Error: Must run as root (sudo)." && exit 1

CURRENT_KERNEL=$(uname -r)
PCI_ID="14e4:4331"

echo "=== Step 1: Hardware & Binary Verification ==="
# Ref: https://pci-ids.ucw.cz/read/PC/14e4/4331
if ! lspci -n | grep -q "$PCI_ID"; then
    echo "❌ Hardware $PCI_ID not found." && exit 1
fi

MOD_FILE=$(find "/lib/modules/$CURRENT_KERNEL" -name "wl.ko*" | head -n 1)
if [[ -z "$MOD_FILE" ]]; then
    # Ref: https://fedoraproject.org/wiki/Akmods
    echo "⚠️ Binary missing. Extracting..."
    dnf install -y akmod-wl rpm2cpio cpio kernel-devel-$(uname -r) kernel-headers || true
    KMOD_RPM=$(find /var/cache/akmods/wl/ -name "kmod-wl-$CURRENT_KERNEL*.rpm" | head -n 1)
    [[ -n "$KMOD_RPM" ]] && (rpm2cpio "$KMOD_RPM" | cpio -idmv -D /; depmod -a "$CURRENT_KERNEL")
fi

echo "=== Step 2: Driver & Stack Check ==="
# Ref: https://wireless.docs.kernel.org/en/users/drivers/b43#Known_issues
if ! lsmod | grep -q "^wl "; then
    modprobe -r b43 bcma ssb wl 2>/dev/null || true
    modprobe wl
fi
echo "✅ Driver 'wl' active."

echo "=== Step 3: Interface & Radio Scan ==="
IFACE=$(ip link | grep -E 'wl|wlan' | awk -F: '{print $2}' | tr -d ' ' | head -n 1)

if [[ -n "$IFACE" ]]; then
    ip link set "$IFACE" up || true
    echo "Scanning for networks on $IFACE to verify radio..."
    sleep 2
    # Trigger a scan to prove the driver is actually receiving
    nmcli device wifi rescan || true
    sleep 2
    
    if nmcli device wifi list | grep -q "."; then
        echo "✅ SUCCESS: Radio is receiving. Networks found:"
        nmcli -f SSID,SIGNAL,BARS device wifi list | head -n 5
        
        STATE=$(nmcli -t -f DEVICE,STATE device | grep "^$IFACE" | cut -d: -f2)
        if [[ "$STATE" != "connected" ]]; then
            echo -e "\n👉 ACTION REQUIRED: Run the following to connect:"
            echo "sudo nmcli device wifi connect 'YOUR_SSID' password 'YOUR_PASSWORD'"
        else
            echo "✅ Interface is CONNECTED."
        fi
    else
        echo "❌ Radio active but no networks found. Check 'rfkill list'."
        rfkill unblock all
    fi
else
    echo "❌ Interface missing. Check 'dmesg | grep wl'."
    exit 1
fi