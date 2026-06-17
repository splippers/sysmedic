# SysMedic Recovery System — Roadmap

**Version:** 3.0 | **Date:** 2026-06-16 | **Authors:** Trillian + LAVE Big Pickles

---

## Vision

A single, live-boot USB drive that provides AI-powered troubleshooting (with sendable reports) for Windows, Mac, and Linux systems. Each boot inherits full context from prior sessions via the CraicKen mesh and git-tracked repo. The system evolves from a passive diagnostic toolbox into a proactive hardware validation + OS repair platform.

---

## Architecture

```
USB Stick (ISO9660 + writable persistence partition)
├── /casper/vmlinuz          — Ubuntu 24.04 LTS kernel
├── /casper/initrd           — initramfs
├── /casper/filesystem.squashfs — rootfs with SysMedic stack
├── /boot/grub/grub.cfg      — GRUB menu (UEFI + BIOS)
├── /opt/sysmedic/           — Rescue system + repair scripts
│   ├── menu.sh              — Interactive rescue menu (v3.0)
│   ├── WIKI.md              — Knowledge base + session log
│   ├── ROADMAP.md           — This file
│   ├── build-iso.sh         — ISO build pipeline (Tier 4)
│   ├── sysmedic-diagnose    — Quick health check entry point
│   ├── sysmedic-netcheck    — Network diagnostics
│   ├── scripts/             — All repair + diagnostic scripts
│   │   ├── preflight.sh         — Hardware detection + context gathering
│   │   ├── stress-test.sh       — 7-mode hardware burn-in suite (Tier 2)
│   │   ├── sysmedic-analyze.sh  — AI-Deep Analysis pipeline (Tier 3)
│   │   ├── sysmedic-persist.sh  — Session persistence engine
│   │   ├── sysmedic-update.sh   — Self-update via git + mesh
│   │   ├── smart-repair.sh      — Auto-detect & fix OS issues
│   │   ├── capture-restore.sh   — OS image capture/restore with LVM support
│   │   ├── craic-connect.sh     — CraicKen mesh telemetry
│   │   ├── craicken-sync.sh     — Wiki/knowledge sync
│   │   ├── wifi-connect.sh      — WiFi setup (WPS/password)
│   │   ├── bitlocker-unlock.sh  — BitLocker CLI unlock
│   │   ├── bitlocker-web.sh     — BitLocker web portal unlock
│   │   ├── bitlocker-web-unlock.py — Python web server for BitLocker
│   │   ├── install-ollama.sh    — Local AI model fallback
│   │   ├── sync-back.sh         — Backup sync helper
│   │   ├── linux-repair/        — 5 Linux repair scripts
│   │   ├── windows-repair/      — Windows repair scripts
│   │   └── macos-repair/        — macOS repair scripts
│   └── models/              — AI model data
└── writable partition (ext4) — PERSIST
    └── /root/sysmedic/       — Persistent session data
        ├── reports/          — All diagnostic reports
        ├── session/          — Session state + context
        ├── captures/         — OS image captures
        ├── scripts/          — User scripts
        └── updates/          — Update metadata
```

---

## Phase 1 — Core Stable (DONE)

### Milestone 1.1 — Boot & Startup
- [x] GRUB entries for standard UEFI, verbose, fallback modes
- [x] UK keyboard layout baked in
- [x] Network pre-flight with WiFi scan + WPS + ethernet fallback
- [x] Preflight hardware detection + structured context JSON

### Milestone 1.2 — AI Integration
- [x] OpenCode GO binary integration
- [x] Big Pickle default model (opencode/big-pickle)
- [x] Full tool permissions (edit, bash, read, glob, grep, write)
- [x] AI Rescue menu option with hardware context export
- [x] AI-Deep Analysis pipeline (Tier 3) — aggregate diagnostics for RCA

### Milestone 1.3 — Repair Scripts
- [x] GRUB reinstall + config repair (fix-grub.sh)
- [x] Initramfs/kernel panic recovery (fix-kernel-panic.sh)
- [x] fstab repair (fix-fstab.sh)
- [x] /boot cleanup (fix-boot.sh)
- [x] Chroot into installed Linux
- [x] Windows repair suite (BCD, NTFS, EFI, password reset)
- [x] macOS scan/mount/repair/recover
- [x] BitLocker unlock (CLI + Web portal)
- [x] Smart Repair — auto-detect & fix OS issues
- [x] OS Capture/Restore with LVM support

### Milestone 1.4 — Hardware Validation
- [x] 7-mode stress test suite (CPU, RAM, disk, temps, full burn-in)
- [x] SMART health + long test monitoring
- [x] Temperature monitoring with peak tracking
- [x] Quick sanity check (5-cycle multi-stress)

### Milestone 1.5 — Persistence & Updates
- [x] Session save/restore on boot device (/root/sysmedic/)
- [x] Cross-boot context inheritance
- [x] Git-based self-update with rollback
- [x] CraicKen mesh version manifest check

---

## Phase 2 — Smart Diagnostics (NEXT)

### Auto-Detect on Boot
- [ ] LAN autoscan on boot (detect target machines)
- [ ] Suggest repair path based on detected OS and symptoms
- [ ] Pre-flight intelligence: query CraicKen for target history
- [ ] Report target state to CraicKen before menu appears

### AI-Deep Integration (Tier 3 — CORE DONE)
- [x] sysmedic-analyze.sh — aggregate all diagnostics into structured JSON
- [x] Auto-run preflight if context missing
- [x] SMART health + anomaly detection across all drives
- [x] Kernel log analysis (dmesg error patterns)
- [x] OS-specific issue detection (dpkg, BSOD minidumps, journal)
- [x] Bootloader integrity check (GRUB, Windows EFI)
- [x] Thermal analysis with delta detection
- [ ] Auto-suggest fix scripts based on analysis findings
- [ ] Submit analysis to CraicKen with fix recommendations
- [ ] Integrate analysis results into OpenCode auto-prompt

### Self-Update Improvements
- [ ] On boot, check portal for updated scripts
- [ ] Pull latest repair scripts from mesh automatically
- [ ] Version-stamp WIKI.md and check for updates

---

## Phase 3 — Fleet Mode (FUTURE)

### Multi-Host Rescue
- [ ] Fix one host, move to next via USB
- [ ] Maintain queue of targets in CraicKen
- [ ] Track which hosts are fixed, which need attention

### CraicKen Integration
- [ ] Every repair logged as ken entry (source, timestamp, outcome)
- [ ] CraicKen agent can dispatch SysMedic to new targets
- [ ] Fleet-wide repair history available on any boot

### Remote Triage
- [ ] CraicKen agent detects dead host via heartbeat gap
- [ ] Creates rescue ticket with symptoms + last known state
- [ ] Ambulance pulls ticket on boot, goes straight to work

---

## Build Pipeline

### Local Build
```bash
# From SysMedic git repo:
sudo bash build-iso.sh --build
sudo bash build-iso.sh --write /dev/sdX
```

### Flash to USB
```bash
lsblk  # Identify USB device (e.g. /dev/sdb)
sudo bash build-iso.sh --write /dev/sdb
# Then create writable persistence partition:
sudo parted /dev/sdb mkpart primary ext4 4GB 100%
sudo mkfs.ext4 -L SYSMEDIC_PERSIST /dev/sdb5
```

---

## Repair Scripts Catalog

### Linux Repair (menu.sh → 3)
| Script | Purpose |
|--------|---------|
| fix-grub.sh | Reinstall GRUB + regenerate grub.cfg |
| fix-kernel-panic.sh | Analyze panic logs + create workaround GRUB entry |
| fix-fstab.sh | Backup + repair /etc/fstab mount entries |
| fix-boot.sh | Clean old kernels from /boot |
| chroot (built-in) | Chroot into installed Linux for manual repair |

### Windows Repair (menu.sh → 4)
| Script | Purpose |
|--------|---------|
| diagnose-windows.sh | Scan Windows logs, BSOD dumps, updates, drivers |
| repair-updates.sh | Fix Windows Update / driver corruption |
| repair-windows.sh | NTFS check, BCD fix, boot sector, password reset, EFI restore |
| recover-windows.sh | Data recovery from Windows partitions |

### macOS Repair (menu.sh → 5)
| Script | Purpose |
|--------|---------|
| scan-macos.sh | Detect HFS+/APFS volumes |
| mount-macos.sh | Mount macOS read-write/read-only |
| repair-macos.sh | fsck_hfs / fsck_apfs repair |
| recover-macos.sh | Data recovery from macOS |

### Diagnostics (menu.sh → 1)
| Option | Purpose |
|--------|---------|
| OpenCode AI Rescue | Launch AI with full hardware context |
| Quick diagnostics | CPU, memory, disk, network overview |
| Partition & OS scan | Detect all installed OSes + SMART status |
| Smart Repair | Auto-detect + fix OS boot issues |
| Stress Test Suite | 7-mode hardware burn-in |
| AI Deep Analysis | Aggregate all diagnostics → AI root cause analysis |

---

## Version History

| Date | Author | Changes |
|------|--------|---------|
| 2026-06-16 | Trillian + LAVE | v3.0: AI-Deep Analysis pipeline, updated build-iso.sh, SysMedic rebranding |
| 2026-06-16 | SysMedic AI | v2.1→v3.0: stress test suite, session persistence, self-update, CraicWiki integration |
| 2026-06-13 | Trillian + LAVE | Initial roadmap — 3 phases, CraicKen integration |

---

## CraicKen API

```
Endpoint:  https://meta.splippers.com
Token:     111JbCV3_BSzwygG0XJ-6kFWDz8v-LHx0rwb8zGv7H8
Ingest:    POST /api/v1/context/ingest
Retrieve:  GET /api/v1/context/retrieve?q=<query>&kind=ken&limit=5
Wiki:      GET /api/v1/wiki/article/<name>
```

## Current Hardware Context

- **Primary test machine:** Dell Precision 3591 (2Y4XG74)
  - Intel Core Ultra 7 165H (16C/22T)
  - 64 GB DDR5-5600 RAM
  - WD SN8000S 1TB NVMe + Toshiba KXG50ZNV256G
  - BIOS 1.21.0 (latest, Apr 2026)
  - **Known issue:** Core 8 thermal anomaly (23°C delta from sibling P-cores, peak 100°C)
- **Previous session hardware:** Dell Latitude 3410 (3C1NN93)
  - Intel i5-10210U (4C/8T), 16 GB DDR4
  - KIOXIA KBG40ZNS256G NVMe
