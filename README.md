# BCM4331 Fedora 43 Deterministic Recovery Kit (v24)

## Overview
This tool automates the recovery of Broadcom BCM4331 [14e4:4331] cards. It bypasses the broken proprietary `wl` driver (Scan Error -22 on Kernel 6.11+) and enforces the open-source `b43` driver with validated HT-PHY firmware blobs.

## Logic Walkthrough
- **Atomic Cleanup:** Stops `NetworkManager` and `wpa_supplicant` to release netlink locks.
- **Hardware Release:** Uses `sysfs` unbind to detach the card from the `bcma` bridge.
- **Integrity Filter:** Inspects firmware blobs for HTML tags to detect corrupted 404 downloads.
- **Async Handling:** Polls the system for 10s to account for `systemd-udevd` interface renaming latency.

## Usage
1. Run `./prepare-bundle.sh` (Online).
2. Run `sudo ./fix-wifi.sh` (Target Machine).

## References
- Scan Error -22: https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=ea63773
- B43 Firmware Set: https://wireless.docs.kernel.org/en/users/drivers/b43#devicefirmware
