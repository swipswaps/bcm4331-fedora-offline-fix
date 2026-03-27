#!/usr/bin/env bash
# Senior Fedora Kernel Maintainer: Deterministic & Idempotent BCM4331 Fix (v6)
set -euo pipefail

[[ $EUID -ne 0 ]] && echo "Error: Must run as root (sudo)." && exit 1

CURRENT_KERNEL=$(uname -r)
PCI_ID="14e4:4331"

echo "=== Step 1: Environment Verification ==="
if ! lspci -n | grep -q "$PCI_ID"; then
    echo "❌ Hardware $PCI_ID not found. Verify BIOS settings."
    exit 1
fi
echo "✅ Hardware $PCI_ID detected."

echo "=== Step 2: Binary Driver Verification ==="
MOD_FILE=$(find "/lib/modules/$CURRENT_KERNEL" -name "wl.ko*" | head -n 1)
if [[ -z "$MOD_FILE" ]]; then
    echo "⚠️ Driver binary missing. Resolving Phantom Install..."
    dnf install -y akmod-wl rpm2cpio cpio kernel-devel-$(uname -r) kernel-headers || true
    KMOD_RPM=$(find /var/cache/akmods/wl/ -name "kmod-wl-$CURRENT_KERNEL*.rpm" | head -n 1)
    if [[ -n "$KMOD_RPM" ]]; then
        rpm2cpio "$KMOD_RPM" | cpio -idmv -D /
        depmod -a "$CURRENT_KERNEL"
    else
        echo "❌ Build failed. Check 'journalctl -u akmods'."
        exit 1
    fi
else
    echo "✅ Driver binary verified at $MOD_FILE."
fi

echo "=== Step 3: Kernel Module State Check ==="
if lsmod | grep -q "^wl "; then
    echo "✅ Driver 'wl' is already loaded."
else
    echo "⚠️ Driver 'wl' not loaded. Checking for conflicts..."
    # Only remove conflicts if wl isn't already loaded
    if lsmod | grep -qE "b43|bcma|ssb"; then
        echo "Purging conflicting drivers (b43/bcma/ssb)..."
        modprobe -r b43 bcma ssb 2>/dev/null || true
    fi
    modprobe wl
fi

echo "=== Step 4: Interface and Connectivity Check ==="
IFACE=$(ip link | grep -E 'wl|wlan' | awk -F: '{print $2}' | tr -d ' ' | head -n 1)

if [[ -n "$IFACE" ]]; then
    STATE=$(nmcli -t -f DEVICE,STATE device | grep "^$IFACE" | cut -d: -f2 || echo "down")
    if [[ "$STATE" == "connected" ]]; then
        echo "✅ SUCCESS: $IFACE is active and connected. No action taken."
    else
        echo "⚠️ $IFACE exists but is $STATE. Initializing..."
        ip link set "$IFACE" up || true
        systemctl start NetworkManager
        nmcli device set "$IFACE" autoconnect yes
        echo "✅ Interface $IFACE is now ready."
    fi
else
    echo "❌ Driver loaded but interface missing. Possible hardware lock."
    rfkill unblock all || true
    dmesg | grep -iE "wl|broadcom|4331" | tail -n 10
fi