#!/usr/bin/env bash
# Senior Fedora Kernel Maintainer: Deterministic BCM4331 Recovery (v4)
set -euo pipefail

[[ $EUID -ne 0 ]] && echo "Error: Must run as root (sudo)." && exit 1

CURRENT_KERNEL=$(uname -r)

echo "=== Step 1: Binary Verification ==="
MOD_FILE=$(find "/lib/modules/$CURRENT_KERNEL" -name "wl.ko*" | head -n 1)

if [[ -n "$MOD_FILE" ]]; then
    echo "✅ Verified: Driver binary present at $MOD_FILE."
else
    echo "⚠️ Module missing. Attempting resilient dependency install..."
    # Use generic kernel-headers to avoid the naming error encountered in v3
    dnf install -y akmod-wl rpm2cpio cpio kernel-devel-$(uname -r) kernel-headers || true
    
    KMOD_RPM=$(find /var/cache/akmods/wl/ -name "kmod-wl-$CURRENT_KERNEL*.rpm" | head -n 1)
    if [[ -n "$KMOD_RPM" ]]; then
        rpm2cpio "$KMOD_RPM" | cpio -idmv -D /
        depmod -a "$CURRENT_KERNEL"
    else
        echo "❌ Critical failure: No binary found and build failed."
        exit 1
    fi
fi

echo "=== Step 2: Purge Conflicts & Load Driver ==="
# Citation: https://wireless.docs.kernel.org/en/users/drivers/b43#Known_issues
# Force detachment of the hardware from the open-source stack
nmcli networking off || true
modprobe -r b43 bcma ssb wl 2>/dev/null || true

if modprobe wl; then
    echo "✅ Driver 'wl' loaded successfully."
else
    echo "❌ Failed to load 'wl'. Check 'dmesg | grep wl'."
    exit 1
fi

echo "=== Step 3: Network Re-Activation ==="
nmcli networking on
systemctl restart NetworkManager
echo "Waiting for NetworkManager..."
sleep 5

# Detect interface
IFACE=$(ip link | grep -E 'wl|wlan' | awk -F: '{print $2}' | tr -d ' ' | head -n 1)

if [[ -n "$IFACE" ]]; then
    echo "✅ SUCCESS: Interface $IFACE is ready."
    nmcli device set "$IFACE" autoconnect yes
    nmcli device status
else
    echo "❌ Driver loaded but interface not created. Check 'sudo dmesg | grep 4331'."
    sudo dmesg | grep -iE "wl|broadcom|4331" | tail -n 20
fi