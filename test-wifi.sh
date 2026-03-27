#!/usr/bin/env bash
set -euo pipefail

echo "=== BCM4331 Diagnostic State ==="
KERNEL=$(uname -r)
PCI_ID="14e4:4331"

# Check Hardware
if lspci -n | grep -q "$PCI_ID"; then
    echo "[PASS] Hardware $PCI_ID found."
else
    echo "[FAIL] Hardware $PCI_ID not detected."
    exit 1
fi

# Check for Binary Object
MOD_FILE=$(find "/lib/modules/$KERNEL" -name "wl.ko*" | head -n 1)
if [[ -n "$MOD_FILE" ]]; then
    echo "[PASS] Driver binary found at $MOD_FILE"
else
    echo "[FAIL] Driver binary missing from /lib/modules (Phantom Install Detected)"
fi

# Check for running conflict
if lsmod | grep -q "bcma"; then
    echo "[WARN] Conflict 'bcma' is currently active and locking the radio."
fi
