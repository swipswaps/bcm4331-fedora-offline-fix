#!/usr/bin/env bash
# Senior Fedora Kernel Maintainer: Deterministic BCM4331 Recovery (Full Feature)
# Target: BCM4331 [14e4:4331] on Fedora 43
set -euo pipefail

[[ $EUID -ne 0 ]] && echo "Error: Must run as root (sudo)." && exit 1

TARGET_KERNEL="6.19.8-200.fc43.x86_64"
CURRENT_KERNEL=$(uname -r)

echo "=== Step 1: Kernel & Devel Alignment ==="
# Citation: https://fedoraproject.org/wiki/Kernel
if [[ "$CURRENT_KERNEL" != "$TARGET_KERNEL" ]]; then
    echo "Alignment Needed. Installing $TARGET_KERNEL..."
    dnf install -y kernel-$TARGET_KERNEL kernel-devel-$TARGET_KERNEL kernel-headers
    grub2-set-default "Fedora ($TARGET_KERNEL) 43"
    grub2-mkconfig -o /boot/grub2/grub.cfg
    echo "Rebooting into target kernel. Please re-run this script after reboot."
    reboot
    exit 0
fi

echo "=== Step 2: Build Environment & Package Enforcement ==="
# Ensures dependencies are present regardless of previous DNF state
# Citation: https://rpmfusion.org/Howto/Broadcom
dnf install -y akmod-wl rpm2cpio cpio kernel-devel-$(uname -r) kernel-headers-$(uname -r)

echo "=== Step 3: Module Verification & Extraction ==="
# Physical check for the binary to resolve the 'Phantom Install' bug
MOD_FILE=$(find "/lib/modules/$CURRENT_KERNEL" -name "wl.ko*" | head -n 1)

if [[ -z "$MOD_FILE" ]]; then
    echo "Module binary missing from filesystem. Checking akmod cache..."
    KMOD_RPM=$(find /var/cache/akmods/wl/ -name "kmod-wl-$CURRENT_KERNEL*.rpm" | head -n 1)
    
    if [[ -z "$KMOD_RPM" ]]; then
        echo "RPM missing. Forcing akmods rebuild..."
        akmods --force --kernels "$CURRENT_KERNEL"
        KMOD_RPM=$(find /var/cache/akmods/wl/ -name "kmod-wl-$CURRENT_KERNEL*.rpm" | head -n 1)
    fi
    
    if [[ -n "$KMOD_RPM" ]]; then
        echo "Deterministic Injection: Extracting $KMOD_RPM to /..."
        # Citation: https://man7.org/linux/man-pages/man8/rpm2cpio.8.html
        rpm2cpio "$KMOD_RPM" | cpio -idmv -D /
        depmod -a "$CURRENT_KERNEL"
    else
        echo "Critical failure: Driver build failed. Check 'journalctl -u akmods'."
        exit 1
    fi
else
    echo "Verified: Module binary present at $MOD_FILE."
fi

echo "=== Step 4: Purge Conflicts & Load Driver ==="
# Stop NetworkManager to release hardware locks
nmcli networking off || true
# Purge open-source drivers that conflict with BCM4331
# Citation: https://wireless.docs.kernel.org/en/users/drivers/b43#Known_issues
modprobe -r b43 bcma ssb wl 2>/dev/null || true

if modprobe wl; then
    echo "✅ Driver 'wl' loaded successfully."
else
    echo "❌ Failed to load 'wl'. Check 'dmesg | grep wl'."
    exit 1
fi

echo "=== Step 5: Network Re-Activation ==="
nmcli networking on
systemctl restart NetworkManager
echo "Waiting for NetworkManager to initialize interface..."
sleep 5

# Dynamic Detection of newly created wireless interface
IFACE=$(ip link | grep -E 'wl|wlan' | awk -F: '{print $2}' | tr -d ' ' | head -n 1)

if [[ -n "$IFACE" ]]; then
    echo "✅ SUCCESS: Interface $IFACE is ready."
    echo "Restoring previous connections..."
    nmcli device set "$IFACE" autoconnect yes
    # Attempt to connect to the last used SSID
    nmcli device connect "$IFACE" || echo "Note: If connection fails, run 'nmcli device wifi connect SSID password PWD'"
    nmcli device status
else
    echo "❌ Driver loaded but interface not created. Check 'sudo dmesg | grep 4331'."
fi