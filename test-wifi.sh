#!/usr/bin/env bash
set -euo pipefail
echo "=== BCM4331 Diagnostic State (b43) ==="
KERNEL=$(uname -r); PCI_ID="14e4:4331"
lspci -n | grep -q "$PCI_ID" && echo "[PASS] Hardware found." || (echo "[FAIL] Hardware missing." && exit 1)
lsmod | grep -q "^b43 " && echo "[PASS] Driver 'b43' loaded." || echo "[FAIL] Driver 'b43' not loaded."
[[ -f /lib/firmware/b43/ucode29_mimo.fw ]] && echo "[PASS] Firmware: ucode29 found." || echo "[FAIL] Firmware missing."
[[ -f /lib/firmware/b43/ht0initvals29.fw ]] && echo "[PASS] Firmware: ht0initvals found." || echo "[FAIL] Firmware missing."
[[ -f /etc/modprobe.d/bcm4331-autofix.conf ]] && echo "[PASS] Persistence: Blacklist active." || echo "[FAIL] No Blacklist."
