# BCM4331 Fedora 43 Recovery Kit

Autonomous, deterministic recovery for Broadcom BCM4331 [14e4:4331] (Core 29).

## Technical Ground Truth
The proprietary Broadcom 'wl' driver is invalidated for Kernels 6.11 through 6.19. It suffers from Scan Error -22 (Invalid Argument) due to incompatible cfg80211 API calls. This kit enforces the open-source 'b43' driver path.

## User Guide

1. Preparation (Online)
Run the following to fetch the mandatory HT-PHY firmware blobs:
./prepare-bundle.sh

2. Execution (Target Machine)
Transfer the workspace via USB and run:
sudo ./fix-wifi.sh

## Logic Walkthrough
- Atomic Cleanup: Stops NetworkManager and wpa_supplicant to release Netlink locks.
- Sysfs Determinism: Detaches the PCI device (0000:02:00.0) from the bridge.
- Integrity: Validates firmware blobs are binaries (non-zero size and no HTML tags).
- Async Handling: 10s polling loop handles udev interface renaming latency.

## Verified References
- Kernel 6.11 API Change: https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=ea63773
- B43 HT-PHY Requirements: https://wireless.docs.kernel.org/en/users/drivers/b43#devicefirmware
- Hardware ID [14e4:4331]: https://pci-ids.ucw.cz/read/PC/14e4/4331
