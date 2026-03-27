## Architecture

### Key Components

- `fix-wifi.sh`  
  → **Primary execution entrypoint (latest stable version)**  
  → Points to the most recent validated version (`fix-wifi_test_v26.sh`)

- `fix-wifi_test_vXX.sh`  
  → Versioned snapshots of iterative improvements  
  → Each version represents a controlled experimental improvement

- `prepare-bundle_test.sh`  
  → Prepares system state for testing or diagnostics

- `test-wifi_test.sh`  
  → Validation and regression test harness

---

## Current Stable Version


fix-wifi_test_v26.sh


This version includes:

- Hard timeout enforcement on all system calls
- Safe NetworkManager interaction
- Non-blocking diagnostics
- Kernel-safe driver inspection
- Deterministic exit behavior
- Clean milestone logging

---

## Behavior Guarantees

This system is designed to:

- ❌ Never hang indefinitely  
- ❌ Never require manual interruption (Ctrl-C)  
- ❌ Avoid unsafe kernel calls  
- ✅ Survive system reboots  
- ✅ Recover from transient driver/network failures  
- ✅ Improve UX through deterministic outputs  
- ✅ Remain observable and auditable  

---

## Design Principles

### 1. Deterministic Execution

All potentially blocking commands are wrapped with:


timeout <N> <command>


This guarantees:
- bounded runtime
- no kernel/netlink stalls

---

### 2. State-Driven Logic

The system operates using:

- network state detection
- connection validation
- driver inspection

Actions are only taken when required.

---

### 3. Driver Awareness

Supports Broadcom (b43) stack:

- `b43`
- `ssb`
- `bcma`
- `mac80211`

Firmware detection is included for validation.

---

### 4. Safe Network Interaction

Uses:

- `nmcli` (NetworkManager CLI)
- `ip route`
- `iw dev` (with timeout)

---

## Usage

### Make executable

```bash
chmod +x fix-wifi.sh
Run
sudo ./fix-wifi.sh
Expected Output

The script outputs structured milestones:

→ MILESTONE: DIAGNOSTIC_START
→ MILESTONE: DECISION_EVALUATION
→ MILESTONE: network=connected
→ MILESTONE: CLEANUP_START
→ MILESTONE: EXIT | CONNECTED
Known Hardware Notes
Broadcom 4331 (b43)
Only supports 2.4 GHz
Firmware must be correctly loaded
May exhibit temporary netlink delays (handled via timeout)
Development Notes
Versioning is strictly additive
No destructive removal of prior versions
Each version must remain runnable independently
fix-wifi.sh always points to latest stable version
Repository Hygiene
All historical versions are preserved
Untracked files are intentionally kept for auditability
No forced cleanup of version history
Authentication

This repository uses GitHub CLI (gh) for authentication

Password authentication is deprecated and must not be used.

License

(Define your license here, e.g., MIT, Apache 2.0, etc.)