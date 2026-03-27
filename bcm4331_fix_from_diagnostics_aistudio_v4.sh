cat > fix-wifi.sh << 'EOF'
#!/usr/bin/env bash
# Senior Fedora Kernel Maintainer: Deterministic BCM4331 Recovery
set -euo pipefail

[[ $EUID -ne 0 ]] && echo "Error: Must run as root." && exit 1

TARGET_KERNEL="6.19.8-200.fc43.x86_64"
CURRENT_KERNEL=$(uname -r)

echo "=== Step 1: Kernel & Devel Alignment ==="
if [[ "$CURRENT_KERNEL" != "$TARGET_KERNEL" ]]; then
    echo "Kernel mismatch. Ensuring $TARGET_KERNEL is default..."
    dnf install -y kernel-$TARGET_KERNEL kernel-devel-$TARGET_KERNEL kernel-headers
    grub2-set-default "Fedora ($TARGET_KERNEL) 43"
    grub2-mkconfig -o /boot/grub2/grub.cfg
    echo "Rebooting into target kernel. Please re-run this script after reboot."
    reboot
    exit 0
fi

echo "=== Step 2: Build Environment Check ==="
# Only install if not present to maintain idempotency
dnf install -y akmod-wl rpm2cpio cpio kernel-devel-$(uname -r)

echo "=== Step 3: Module Verification & Manual Injection ==="
MOD_FILE=$(find "/lib/modules/$CURRENT_KERNEL" -name "wl.ko*" | head -n 1)

if [[ -z "$MOD_FILE" ]]; then
    echo "Module binary missing. Locating cached RPM..."
    KMOD_RPM=$(find /var/cache/akmods/wl/ -name "kmod-wl-$CURRENT_KERNEL*.rpm" | head -n 1)
    
    if [[ -z "$KMOD_RPM" ]]; then
        echo "RPM missing in cache. Forcing rebuild..."
        akmods --force --kernels "$CURRENT_KERNEL"
        KMOD_RPM=$(find /var/cache/akmods/wl/ -name "kmod-wl-$CURRENT_KERNEL*.rpm" | head -n 1)
    fi
    
    if [[ -n "$KMOD_RPM" ]]; then
        echo "Deterministic Injection: Extracting $KMOD_RPM to /..."
        rpm2cpio "$KMOD_RPM" | cpio -idmv -D /
        depmod -a "$CURRENT_KERNEL"
    else
        echo "Critical failure: akmods could not build the driver."
        exit 1
    fi
else
    echo "Module binary already exists. Skipping build."
fi

echo "=== Step 4: Conflict Purge and Load ==="
# Stop services that may lock the driver stack
systemctl stop NetworkManager || true

# Purge conflicting drivers
modprobe -r b43 bcma ssb wl 2>/dev/null || true

# Load deterministic driver
if modprobe wl; then
    echo "✅ Driver 'wl' loaded successfully."
else
    echo "❌ Failed to load 'wl'. Check 'dmesg | grep wl'."
    exit 1
fi

echo "=== Step 5: Interface Activation ==="
systemctl start NetworkManager
sleep 2
IFACE=$(ip link | grep -E 'wl|wlan' | awk -F: '{print $2}' | tr -d ' ' | head -n 1)

if [[ -n "$IFACE" ]]; then
    echo "✅ SUCCESS: Interface $IFACE is ready."
    ip link set "$IFACE" up
    nmcli device status
else
    echo "❌ Driver loaded but no interface found. Check 'sudo dmesg | grep 4331'."
fi
EOF

chmod +x *.sh