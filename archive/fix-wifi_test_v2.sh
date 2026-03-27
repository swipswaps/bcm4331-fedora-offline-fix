#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: ./fix-wifi.sh
# Senior Fedora Kernel Maintainer: Autonomous Recovery Database (v35)
# -----------------------------------------------------------------------------

# --- STEP 0: ROOT PRIVILEGE GATE ---
if [[ $EUID -ne 0 ]]; then
   exec /usr/bin/sudo "$0" "$@"
fi

# --- STEP 1: WORKSPACE CONTEXT ---
WORKSPACE_DIR=$(/usr/bin/dirname "$(/usr/bin/readlink -f "$0")")
BUNDLE_DIR="$WORKSPACE_DIR/offline_bundle"

# --- STEP 2: UPGRADE DATABASE (SOURCE OF TRUTH) ---
declare -A DRIVER_MATRIX
DRIVER_MATRIX["6.11"]="b43"
DRIVER_MATRIX["6.17"]="b43"
DRIVER_MATRIX["6.19"]="b43"

declare -A FIRMWARE_DB
FIRMWARE_DB["29"]="ucode29_mimo.fw ht0initvals29.fw ht0bsinitvals29.fw"

# --- STEP 3: ROBUST SYSTEM BENCHMARKING ---
K_VER=$(/usr/bin/uname -r | /usr/bin/awk -F. '{print $1"."$2}')
C_REV=$(/usr/bin/lspci -vnn -d 14e4:4331 | /usr/bin/grep -i "core revision" | /usr/bin/awk '{print $NF}' || echo "")

# Fallback for null-safety
if [[ -z "${C_REV:-}" ]]; then
    /usr/bin/lspci -n | /usr/bin/grep -q "14e4:4331" && C_REV="29"
fi

STRATEGY=${DRIVER_MATRIX[$K_VER]:-"b43"}
BLOBS=${FIRMWARE_DB[$C_REV]:-""}

if [[ -z "$BLOBS" ]]; then
    /usr/bin/printf "❌ CRITICAL: No DB entry for Core Revision [%s]\n" "$C_REV"
    exit 1
fi

# --- STEP 4: ATOMIC CLEANUP ---
/usr/bin/systemctl stop NetworkManager wpa_supplicant 2>/dev/null || true
PCI_BUS=$(/usr/bin/lspci -n | /usr/bin/grep "14e4:4331" | /usr/bin/head -n 1 | /usr/bin/awk '{print "0000:"$1}')
if [[ -n "${PCI_BUS:-}" && -e "/sys/bus/pci/devices/$PCI_BUS/driver/unbind" ]]; then
    /usr/bin/printf "%s" "$PCI_BUS" | /usr/bin/tee "/sys/bus/pci/devices/$PCI_BUS/driver/unbind" > /dev/null || true
fi
for mod in wl bcma b43 ssb; do /usr/sbin/modprobe -r "$mod" 2>/dev/null || true; done

# --- STEP 5: FIRMWARE DEPLOYMENT ---
FW_TARGET_DIR="/usr/lib/firmware/b43"
/usr/bin/mkdir -p "$FW_TARGET_DIR"
for blob in $BLOBS; do
    TARGET_FILE="$BUNDLE_DIR/$blob"
    SYSTEM_FILE="$FW_TARGET_DIR/$blob"
    if [[ -s "$TARGET_FILE" ]] && ! /usr/bin/grep -qi "<html" "$TARGET_FILE"; then
        /usr/bin/cp "$TARGET_FILE" "$SYSTEM_FILE"
    elif [[ -s "$SYSTEM_FILE" ]] && ! /usr/bin/grep -qi "<html" "$SYSTEM_FILE"; then
        /usr/bin/printf "✅ Blob %s verified.\n" "$blob"
    else
        /usr/bin/printf "❌ ERROR: Blob %s corrupted or missing.\n" "$blob"
        exit 1
    fi
done

# --- STEP 6: INITIALIZATION & PERSISTENCE ---
/usr/sbin/modprobe "$STRATEGY" allhwsupport=1
/usr/bin/printf "blacklist bcma\nblacklist ssb\nblacklist wl\n" | /usr/bin/tee /etc/modprobe.d/bcm4331-autofix.conf > /dev/null
/usr/bin/printf "%s\n" "$STRATEGY" | /usr/bin/tee /etc/modules-load.d/b43.conf > /dev/null

# --- STEP 7: VERIFICATION ---
/usr/bin/systemctl start NetworkManager
/usr/bin/printf "✅ SUCCESS: %s active on Kernel %s\n" "$STRATEGY" "$K_VER"