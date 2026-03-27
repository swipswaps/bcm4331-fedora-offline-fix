# BCM4331 Fedora 43 Autonomous Recovery Kit (v41)

## Architecture
- **Database Logic:** Hardware mapping via `./manifest.db`.
- **Verbatim Instrumentation:** Line-buffered logs in `./verbatim_handshake.log`.
- **Speed Benchmarking:** Optimized udev polling and discovery loops.

## Technical Ground Truth
As verified in system logs, the proprietary `wl` driver is broken for Kernel 6.11+ (**Scan Error -22**). This kit enforces the `b43` driver path.

## Usage
1. Prepare: `./prepare-bundle.sh`
2. Fix: `sudo ./fix-wifi.sh`
3. Audit: `./test-wifi.sh`
