#!/usr/bin/env bash
# Senior Fedora Kernel Maintainer: Total Offline Recovery (v12)
set -euo pipefail
[[ $EUID -ne 0 ]] && echo "Error: Must run as root." && exit 1
BUNDLE_DIR="./offline_bundle"
TARGET_KERNEL="6.19.8-200.fc43.x86_64"
CURRENT_KERNEL=$(uname -r)

echo "=== Step 1: Kernel Alignment (Offline) ==="
if [[ "$CURRENT_KERNEL" != "$TARGET_KERNEL" ]]; then
    dnf --offline localinstall -y "$BUNDLE_DIR"/kernel-"$TARGET_KERNEL"*.rpm "$BUNDLE_DIR"/kernel-devel-"$TARGET_KERNEL"*.rpm
    grub2-set-default "Fedora ($TARGET_KERNEL) 43"
    grub2-mkconfig -o /boot/grub2/grub.cfg
    echo "✅ Rebooting to $TARGET_KERNEL. Re-run this script after reboot."
    reboot
    exit 0
fi

echo "=== Step 2: Deterministic Injection ==="
MOD_FILE=$(find "/lib/modules/$CURRENT_KERNEL" -name "wl.ko*" | head -n 1)
if [[ -z "$MOD_FILE" ]]; then
    KMOD_RPM=$(find "$BUNDLE_DIR" -name "akmod-wl*.rpm" | head -n 1)
    rpm2cpio "$KMOD_RPM" | cpio -idmv -D /
    depmod -a "$CURRENT_KERNEL"
fi

echo "=== Step 3: Service Reset & Verification ==="
systemctl stop NetworkManager || true
modprobe -r b43 bcma ssb wl 2>/dev/null || true
modprobe wl
systemctl start NetworkManager
sleep 10
nmcli device wifi rescan || true
nmcli device wifi list

echo "=== Step 6: Ensuring Persistence (Reboot-Proofing) ==="
# Blacklist conflicting open-source drivers
echo -e "blacklist b43\nblacklist bcma\nblacklist ssb" | sudo tee /etc/modprobe.d/bcm4331-blacklist.conf
# Force-load wl module on boot
echo "wl" | sudo tee /etc/modules-load.d/wl.conf
echo "✅ Persistence configured. Offline fix will survive next reboot."
