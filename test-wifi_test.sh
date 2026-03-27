#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: ./test-wifi.sh
# Senior Fedora Kernel Maintainer: System Integrity Auditor (v34)
# -----------------------------------------------------------------------------
set -uo pipefail
/usr/bin/printf "=== BCM4331 Status Report ===\n"
/usr/bin/lspci -n | /usr/bin/grep -q "14e4:4331" && /usr/bin/printf "[PASS] Hardware\n" || /usr/bin/printf "[FAIL] Hardware\n"
[[ -s "/usr/lib/firmware/b43/ucode29_mimo.fw" ]] && /usr/bin/printf "[PASS] Firmware\n" || /usr/bin/printf "[FAIL] Firmware\n"
/usr/bin/lsmod | /usr/bin/grep -q "^b43 " && /usr/bin/printf "[PASS] Driver b43 active\n" || /usr/bin/printf "[FAIL] Driver b43 not loaded\n"