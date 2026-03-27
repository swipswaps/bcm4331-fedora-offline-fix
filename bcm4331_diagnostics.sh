#!/usr/bin/env bash
# bcm4331_diagnostics.sh
# Collect deterministic system state for Broadcom BCM4331 Wi-Fi
# Outputs all info needed to later fix driver without guessing

set -euo pipefail

LOGDIR="$HOME/bcm4331_diag_logs"
mkdir -p "$LOGDIR"
echo "Diagnostic logs will be written to $LOGDIR"

# -----------------------------
# Step 1: PCI device info
echo "=== STEP 1: PCI devices (lspci) ===" | tee "$LOGDIR/step1_pci.log"
lspci -nnk | grep -iA4 "Network\|Wireless" | tee -a "$LOGDIR/step1_pci.log"

# -----------------------------
# Step 2: Kernel modules loaded
echo "=== STEP 2: Loaded kernel modules (lsmod) ===" | tee "$LOGDIR/step2_lsmod.log"
lsmod | tee -a "$LOGDIR/step2_lsmod.log"

# -----------------------------
# Step 3: Current driver info for BCM4331
echo "=== STEP 3: BCM4331 driver info (ethtool/modinfo) ===" | tee "$LOGDIR/step3_driver.log"
for module in wl b43 bcma; do
    if modinfo "$module" &>/dev/null; then
        echo "--- $module ---" | tee -a "$LOGDIR/step3_driver.log"
        modinfo "$module" | tee -a "$LOGDIR/step3_driver.log"
    else
        echo "--- $module not installed ---" | tee -a "$LOGDIR/step3_driver.log"
    fi
done

# -----------------------------
# Step 4: Network interfaces
echo "=== STEP 4: Network interfaces (ip link, iw dev) ===" | tee "$LOGDIR/step4_ifaces.log"
ip link | tee -a "$LOGDIR/step4_ifaces.log"
iw dev | tee -a "$LOGDIR/step4_ifaces.log"

# -----------------------------
# Step 5: Firmware files
echo "=== STEP 5: Firmware present ===" | tee "$LOGDIR/step5_firmware.log"
ls -l /lib/firmware/b43 | tee -a "$LOGDIR/step5_firmware.log"

# -----------------------------
# Step 6: Kernel ring buffer for wireless
echo "=== STEP 6: dmesg for wireless ===" | tee "$LOGDIR/step6_dmesg.log"
sudo dmesg | grep -i -E 'b43|wl|bcma|firmware' | tee -a "$LOGDIR/step6_dmesg.log"

# -----------------------------
# Step 7: akmods status
echo "=== STEP 7: akmods status ===" | tee "$LOGDIR/step7_akmods.log"
akmods --list | tee -a "$LOGDIR/step7_akmods.log"
akmods --kernels | tee -a "$LOGDIR/step7_akmods.log"

echo "=== Diagnostic complete. All logs in $LOGDIR ==="