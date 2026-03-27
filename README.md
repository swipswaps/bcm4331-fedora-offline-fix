# BCM4331 Fedora 43 Deterministic Recovery Kit

Autonomous, idempotent recovery for **Broadcom BCM4331 [14e4:4331]** cards on Fedora 43.

## Why this exists
- **Kernel 6.11+ API Breakage:** The proprietary Broadcom `wl` (STA) driver is fundamentally broken for kernels above 6.10. It loads but cannot scan for SSIDs (Error -22). 
- **Firmware Gaps:** Fedora's `b43-openfwwf` package is incomplete for Core 29 (BCM4331), lacking the High-Throughput (HT) initialization blobs.
- **Udev Latency:** Predictable network naming causes a race condition where the interface is not immediately available after the module loads.

## Logic of the Fix
1. **Source of Truth:** Enforces the Open Source `b43` driver.
2. **Firmware Injection:** Deterministically fetches the verified HT-PHY Core 29 blobs from the LibreELEC mirror.
3. **Adaptive Detection:** Uses a 10-second polling loop to handle `systemd-udevd` interface renaming.
4. **Persistence:** Blacklists `bcma`, `ssb`, and `wl` in `/etc/modprobe.d/` to prevent hardware hijacking.

## Usage
1. **Prepare:** On a machine with internet, run `./prepare-bundle.sh`.
2. **Transfer:** Move the `offline_bundle` folder and scripts to the target machine.
3. **Fix:** Run `sudo ./fix-wifi.sh` (or `sudo ./fix-wifi-offline.sh` if no internet).

## Verified References
* **Hardware ID [14e4:4331]:** https://pci-ids.ucw.cz/read/PC/14e4/4331
* **B43 HT-PHY Requirements:** https://wireless.docs.kernel.org/en/users/drivers/b43#devicefirmware
* **Kernel 6.11 Scan Results Change:** https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=ea63773
