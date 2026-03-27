#!/usr/bin/env bash
# Senior Fedora Kernel Maintainer: Deterministic Binary Bundler
set -euo pipefail
REPO_DIR="./offline_bundle"
mkdir -p "$REPO_DIR"
echo "=== Downloading Deterministic Binaries for BCM4331 ==="
dnf download --destdir="$REPO_DIR" --resolve \
    kernel-6.19.8-200.fc43.x86_64 \
    kernel-devel-6.19.8-200.fc43.x86_64 \
    kernel-headers akmod-wl broadcom-wl rpm2cpio cpio
echo "✅ Bundle created in $REPO_DIR"
