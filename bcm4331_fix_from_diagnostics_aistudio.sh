#!/usr/bin/env bash
# Deterministic Fix: Manual Installation of akmod-built driver
set -euo pipefail

echo "=== Searching for the RPM built by akmods ==="
# akmods builds an RPM but often fails to install it in 'race condition' scenarios
KMOD_RPM=$(find /var/cache/akmods/wl/ -name "kmod-wl-$(uname -r)*.rpm" | head -n 1)

if [[ -z "$KMOD_RPM" ]]; then
    echo "❌ No built RPM found. Retrying build..."
    sudo akmods --force --kernels $(uname -r)
    KMOD_RPM=$(find /var/cache/akmods/wl/ -name "kmod-wl-$(uname -r)*.rpm" | head -n 1)
fi

if [[ -n "$KMOD_RPM" ]]; then
    echo "✅ Found built module RPM: $KMOD_RPM"
    echo "=== Forcing installation of the module package ==="
    sudo dnf install -y "$KMOD_RPM"
else
    echo "❌ Build failed to produce an RPM. Checking local files..."
    # Fallback: Find the raw .ko file if the RPM failed
    KO_FILE=$(find /var/cache/akmods/ -name "wl.ko*" | head -n 1)
    if [[ -n "$KO_FILE" ]]; then
        sudo mkdir -p /lib/modules/$(uname -r)/extra/wl/
        sudo cp "$KO_FILE" /lib/modules/$(uname -r)/extra/wl/
    else
        echo "❌ Critical Failure: wl.ko was never compiled."
        exit 1
    fi
fi

echo "=== Updating module dependencies ==="
sudo depmod -a $(uname -r)

echo "=== Unloading conflicts and loading wl ==="
sudo modprobe -r b43 bcma ssb wl 2>/dev/null || true
sudo modprobe wl

echo "=== Final Verification ==="
if ip link show | grep -E 'wl|wlan'; then
    echo "✅ SUCCESS: Wireless interface is visible."
    nmcli device status
else
    echo "❌ FAILURE: Interface still not found. Check 'sudo dmesg | grep wl'"
fi