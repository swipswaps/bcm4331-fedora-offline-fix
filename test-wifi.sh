#!/usr/bin/env bash
set -euo pipefail

echo "=== BCM4331 Diagnostic State ==="
KERNEL=$(uname -r)
PCI_ID="14e4:4331"

# 1. Check Hardware
lspci -n | grep -q "$PCI_ID" && echo "[PASS] Hardware $PCI_ID found." || (echo "[FAIL] Hardware not detected." && exit 1)

# 2. Check for Binary Object
MOD_FILE=$(find "/lib/modules/$KERNEL" -name "wl.ko*" | head -n 1)
[[ -n "$MOD_FILE" ]] && echo "[PASS] Driver binary found at $MOD_FILE" || echo "[FAIL] Driver binary missing."

# 3. Check for Active Driver
lsmod | grep -q "^wl " && echo "[PASS] Driver 'wl' is currently loaded." || echo "[FAIL] Driver 'wl' is not loaded."

# 4. Check for Persistence (Blacklist)
[[ -f /etc/modprobe.d/bcm4331-blacklist.conf ]] && echo "[PASS] Persistence: Conflicts are blacklisted." || echo "[FAIL] Persistence: No blacklist found."

# 5. Check for Persistence (Auto-load)
[[ -f /etc/modules-load.d/wl.conf ]] && echo "[PASS] Persistence: 'wl' configured to auto-load." || echo "[FAIL] Persistence: 'wl' not in modules-load.d."
