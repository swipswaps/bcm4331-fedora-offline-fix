#!/usr/bin/env bash
# bcm4331_final_fix.sh - Correct fix for BCM4331 on Fedora 43
set -euo pipefail

echo "=== BCM4331 Wi-Fi final fix (proprietary wl driver) ==="

# 1. Make sure we are on the kernel that already has the wl module built
CURRENT_KERNEL=$(uname -r)
if [[ "$CURRENT_KERNEL" == "6.17.7-300.fc43.x86_64" ]]; then
    echo "You are on the old kernel (6.17.7). The wl module is built for 6.19.8."
    echo "Rebooting into the newer kernel now..."
    sudo reboot
    exit 0
fi

echo "Running kernel is $CURRENT_KERNEL — wl module should be available."

# 2. Ensure everything is installed (idempotent)
echo "Ensuring RPM Fusion and akmod-wl are present..."
sudo dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-43.noarch.rpm || true
sudo dnf install -y akmod-wl kernel-devel-$(uname -r) kernel-headers-$(uname -r)

# 3. Rebuild modules just in case
echo "Rebuilding akmod-wl..."
sudo akmods --force
sudo dracut --force -q

# 4. Remove any conflicting open drivers
echo "Removing conflicting open drivers..."
sudo modprobe -r b43 bcma ssb wl 2>/dev/null || true

# 5. Load the proprietary wl driver
echo "Loading wl driver..."
sudo modprobe wl

# 6. Verify
echo "=== Verification ==="
nmcli device status
ip link show | grep -E 'wl|wlan' || echo "No wireless interface yet — check dmesg"
sudo dmesg | tail -n 30 | grep -E 'wl|b43|broadcom' || true

echo ""
echo "If you now see a wl* or wlan* interface, your Wi-Fi is fixed."
echo "Run 'nmcli device wifi list' to scan networks."