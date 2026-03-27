#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -ne 0 ]] && echo "Error: Use sudo." && exit 1
BUNDLE_DIR="./offline_bundle"; TARGET_KERNEL="6.19.8-200.fc43.x86_64"; CURRENT_KERNEL=$(uname -r)
if [[ "$CURRENT_KERNEL" != "$TARGET_KERNEL" ]]; then
    dnf --offline localinstall -y "$BUNDLE_DIR"/kernel-"$TARGET_KERNEL"*.rpm "$BUNDLE_DIR"/kernel-devel-"$TARGET_KERNEL"*.rpm
    grub2-set-default "Fedora ($TARGET_KERNEL) 43"; grub2-mkconfig -o /boot/grub2/grub.cfg
    echo "Rebooting to $TARGET_KERNEL. Re-run this script after reboot."; reboot; exit 0
fi
dnf --offline localinstall -y "$BUNDLE_DIR"/akmod-wl*.rpm "$BUNDLE_DIR"/kernel-headers*.rpm "$BUNDLE_DIR"/rpm2cpio*.rpm "$BUNDLE_DIR"/cpio*.rpm "$BUNDLE_DIR"/mokutil*.rpm
MOD_FILE=$(find "/lib/modules/$CURRENT_KERNEL" -name "wl.ko*" | head -n 1)
if [[ -z "$MOD_FILE" ]]; then
    KMOD_RPM=$(find "$BUNDLE_DIR" -name "akmod-wl*.rpm" | head -n 1)
    rpm2cpio "$KMOD_RPM" | cpio -idmv -D /; depmod -a "$CURRENT_KERNEL"
fi
modprobe -r b43 bcma ssb wl 2>/dev/null || true
modprobe wl
echo -e "blacklist b43\nblacklist bcma\nblacklist ssb" | tee /etc/modprobe.d/bcm4331-blacklist.conf
echo "wl" | tee /etc/modules-load.d/wl.conf
systemctl restart NetworkManager; sleep 5
IFACE=$(ip link | grep -E 'wl|wlan' | awk -F: '{print $2}' | tr -d ' ' | head -n 1)
[[ -n "$IFACE" ]] && echo "✅ SUCCESS: $IFACE is active." || echo "❌ FAILED: Check dmesg."
