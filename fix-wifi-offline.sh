#!/usr/bin/env bash
# Senior Fedora Kernel Maintainer: Total Offline Recovery (v20-Offline)
set -euo pipefail
[[ $EUID -ne 0 ]] && echo "Error: Use sudo." && exit 1

FW_DIR="/lib/firmware/b43"
BUNDLE_DIR="./offline_bundle"

function restore() { systemctl start NetworkManager 2>/dev/null || true; }
trap restore EXIT

echo "=== STEP 1: Purging Conflicts ==="
dnf --offline remove -y akmod-wl broadcom-wl || true
for mod in wl bcma b43 ssb; do modprobe -r "$mod" 2>/dev/null || true; done

echo "=== STEP 2: Injecting Offline Firmware ==="
mkdir -p "$FW_DIR"
if [[ -d "$BUNDLE_DIR" ]]; then
    cp "$BUNDLE_DIR"/*.fw "$FW_DIR/"
else
    echo "❌ ERROR: $BUNDLE_DIR not found. Run prepare-bundle.sh on an online machine first."
    exit 1
fi

echo "=== STEP 3: Initializing b43 ==="
modprobe b43 allhwsupport=1
for ((i=1; i<=10; i++)); do
    IFACE=$(ls /sys/class/net | grep -E '^wl' | head -n 1)
    [[ -n "$IFACE" ]] && break
    sleep 1
done

echo "=== STEP 4: Verification ==="
if [[ -n "${IFACE:-}" ]]; then
    ip link set "$IFACE" up
    rfkill unblock all
    systemctl restart NetworkManager
    echo "✅ SUCCESS: $IFACE active. Scanning SSIDs..."
    sleep 5
    nmcli device wifi list
else
    echo "❌ FAILED: Interface not found."
fi

echo -e "blacklist bcma\nblacklist ssb\nblacklist wl" > /etc/modprobe.d/bcm4331-autofix.conf
