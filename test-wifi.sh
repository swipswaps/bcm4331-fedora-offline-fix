#!/usr/bin/env bash
set -euo pipefail
echo "=== BCM4331 Diagnostic State ==="
KERNEL=$(uname -r); PCI_ID="14e4:4331"
lspci -n | grep -q "$PCI_ID" && echo "[PASS] Hardware found." || (echo "[FAIL] Hardware missing." && exit 1)
MOD_FILE=$(find "/lib/modules/$KERNEL" -name "wl.ko*" | head -n 1)
[[ -n "$MOD_FILE" ]] && echo "[PASS] Driver binary found." || echo "[FAIL] Driver binary missing."
lsmod | grep -q "^wl " && echo "[PASS] Driver 'wl' loaded." || echo "[FAIL] Driver 'wl' not loaded."
[[ -f /etc/modprobe.d/bcm4331-blacklist.conf ]] && echo "[PASS] Persistence: Blacklist." || echo "[FAIL] No Blacklist."
[[ -f /etc/modules-load.d/wl.conf ]] && echo "[PASS] Persistence: Auto-load." || echo "[FAIL] No Auto-load config."
if [ -d /sys/firmware/efi ]; then
    mokutil --sb-state 2>/dev/null || echo "mokutil not installed."
fi
