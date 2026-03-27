#!/usr/bin/env bash
# Deterministic Fix: Force-deploying wl driver for BCM4331 on Kernel 6.19.8
set -euo pipefail

# Role: Senior Fedora Kernel Maintainer
# Goal: Manual extraction and insertion of missing wl module

LOGDIR="$HOME/bcm4331_final_fix_logs"
mkdir -p "$LOGDIR"

echo "=== STEP 1: Locating the built driver RPM ==="
# Based on your logs, the RPM exists here:
KMOD_RPM="/var/cache/akmods/wl/kmod-wl-6.19.8-200.fc43.x86_64-6.30.223.271-61.fc43.x86_64.rpm"

if [[ ! -f "$KMOD_RPM" ]]; then
    echo "❌ Cached RPM not found. Regenerating..."
    sudo akmods --force --kernels "$(uname -r)"
fi

echo "=== STEP 2: Manually extracting module to filesystem ==="
# We bypass 'dnf install' because it falsely claims the package is present.
# We extract directly to / to ensure wl.ko.xz is placed in /lib/modules/
sudo rpm2cpio "$KMOD_RPM" | sudo cpio -idmv -D /

echo "=== STEP 3: Registering module with kernel ==="
sudo depmod -a "$(uname -r)"

echo "=== STEP 4: Verifying file placement ==="
# Deterministic check for the specific module file
MOD_PATH=$(find "/lib/modules/$(uname -r)" -name "wl.ko*" | head -n 1)
if [[ -z "$MOD_PATH" ]]; then
    echo "❌ Critical Failure: Module file still missing after extraction."
    exit 1
fi
echo "✅ Module found at: $MOD_PATH"

echo "=== STEP 5: Cleaning kernel stack and loading wl ==="
# Completely remove conflicting Broadcom drivers
sudo modprobe -r b43 bcma ssb wl 2>/dev/null || true
# Force load the newly placed module
sudo modprobe wl

echo "=== STEP 6: Final Interface Check ==="
# Dynamically detect if a wireless interface was created
IFACE=$(ip link | grep -E 'wl|wlan' | awk -F: '{print $2}' | tr -d ' ' | head -n 1)

if [[ -n "$IFACE" ]]; then
    echo "✅ SUCCESS: Wireless interface detected as: $IFACE"
    sudo ip link set "$IFACE" up
    nmcli device status
else
    echo "❌ FAILURE: Driver loaded but interface not created. Check 'sudo dmesg | grep wl'"
    sudo dmesg | grep -iE "wl|4331|broadcom" | tail -n 20
fi