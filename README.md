# BCM4331 Fedora 43 Offline Recovery Kit

Deterministic, idempotent recovery for Broadcom BCM4331 cards on Fedora 43.

## Verified References
* **Hardware ID:** https://pci-ids.ucw.cz/read/PC/14e4/4331
* **Driver Standard:** Proprietary `wl` (STA) for N-PHY MIMO support. https://wireless.docs.kernel.org/en/users/drivers/b43
* **Deployment Method:** Manual `rpm2cpio` injection to bypass `akmods` race conditions. https://fedoraproject.org/wiki/Akmods

## Usage
1. **Prepare:** On a machine with internet, run `./prepare-bundle.sh`.
2. **Transfer:** Move the folder to the target machine via USB.
3. **Fix:** Run `sudo ./fix-wifi-offline.sh`.
