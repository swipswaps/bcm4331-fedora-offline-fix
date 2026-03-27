#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# File: ./prepare-bundle.sh
# Senior Fedora Kernel Maintainer: Deterministic B43 Firmware Bundler (v33)
# -----------------------------------------------------------------------------
set -euo pipefail
# Target folder relative to root: ./offline_bundle/
REPO_DIR="./offline_bundle"
/usr/bin/mkdir -p "$REPO_DIR"
FW_URL="https://raw.githubusercontent.com/LibreELEC/wlan-firmware/master/firmware/b43"

/usr/bin/printf "=== Fetching HT-PHY Core 29 Firmware ===\n"
for f in ucode29_mimo.fw ht0initvals29.fw ht0bsinitvals29.fw; do
    /usr/bin/wget -q -O "$REPO_DIR/$f" "$FW_URL/$f"
done
/usr/bin/printf "✅ Bundle created in %s\n" "$REPO_DIR"