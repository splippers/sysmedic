# FOG-Ambulance Rescue System — Roadmap

**Version:** 1.0 | **Date:** 2026-06-13 | **Authors:** Trillian + LAVE Big Pickles

---

## Vision

A single, live-boot USB drive that provides AI-powered troubleshooting (with sendable reports) for Windows, Mac, and Linux systems. Each boot inherits full context from prior sessions via the CraicKen mesh and git-tracked repo.

---

## Architecture

```
USB Stick (ISO9660 + writable persistence partition)
├── /casper/vmlinuz          — Ubuntu 24.04 LTS kernel
├── /casper/initrd           — initramfs
├── /casper/filesystem.squashfs — rootfs with OpenCode GO + Ollama
├── /boot/grub/grub.cfg      — GRUB menu (UEFI + BIOS, 5 boot modes)
├── /opt/fog-ambulance/      — Rescue system + repair scripts
│   ├── menu.sh              — Interactive rescue menu
│   ├── WIKI.md              — Knowledge base
│   ├── FOG-AMBULANCE-AGENT.md — OpenCode agent instructions
│   ├── scripts/
│   │   ├── preflight.sh     — Network auto-config
│   │   ├── craic-connect.sh — CraicKen telemetry
│   │   ├── wifi-connect.sh  — WiFi setup (WPS/password)
│   │   ├── rebuild-iso.sh   — ISO builder
│   │   └── linux-repair/    — 9 repair scripts
│   └── opencode-config/     — GO API key + auth + account
└── writable partition (ext4) — FOG_AMB_PERSIST
    ├── models/               — Ollama GGUF models
    ├── logs/                 — Session logs
    └── craic/                — CraicKen cache
```

---

## Phase 1 — Core Stable (CURRENT)

### Milestone 1.1 — Boot Reliability
- [x] GRUB entries for standard UEFI, verbose, HP Deskpro (edd+noapic), ACPI-free, memtest
- [x] UK keyboard baked in
- [x] Network pre-flight with WiFi scan + WPS + ethernet fallback

### Milestone 1.2 — AI Stack
- [x] OpenCode GO binary in squashfs
- [x] Big Pickle default model (opencode/big-pickle)
- [x] JonotronV3 offline fallback via Ollama
- [x] Full tool permissions (edit, bash, read, glob, grep, write)
- [x] Agent instructions from FOG-AMBULANCE-AGENT.md

### Milestone 1.3 — Startup Routines
- [x] CRAICKEN endpoint: `http://192.168.1.100:8042` (VIP, floats MARVIN/EDDIE)
- [x] Bearer token: `111JbCV3_BSzwygG0XJ-6kFWDz8v-LHx0rwb8zGv7H8`
- [ ] Menu option 1 auto-runs preflight + opencode in one shot
- [ ] Preflight checks for auth.json before launch
- [ ] rebuild-iso.sh copies auth.json + account.json into squashfs

### Milestone 1.4 — Repair Scripts
- [x] fix-dpkg.sh — Broken package state recovery
- [x] fix-docker.sh — Docker health + container restart
- [x] fix-network.sh — Network config backup/inspection
- [x] fix-rollback.sh — Apt history inspection + kernel downgrade
- [x] fix-grub.sh — GRUB reinstall + config repair
- [x] fix-fstab.sh — Filesystem table repair
- [x] fix-boot.sh — Boot sector repair
- [x] fix-kernel-panic.sh — Panic log analysis + workaround
- [x] scan.sh — Partition + OS auto-detection

---

## Phase 2 — Smart Ambulance (NEXT)

### Auto-Detect on Boot
- [ ] nmap scan of LAN on boot (192.168.1.0/24)
- [ ] Detect Vroomfondel (192.168.1.3) status — ping/ARP/port scan
- [ ] Report target state to CraicKen before menu appears
- [ ] Suggest repair path based on detected OS and symptoms

### Pre-Flight Intelligence
- [ ] Is the target reachable? SSH? What OS?
- [ ] Check Docker daemon, container states
- [ ] Inspect dpkg status for broken packages
- [ ] Report all findings as ken entries before user intervention

### Self-Update
- [ ] On boot, check portal (http://192.168.1.65:8088) for updated scripts
- [ ] Pull latest repair scripts automatically
- [ ] Version-stamp WIKI.md and check for updates

---

## Phase 3 — Fleet Mode (FUTURE)

### Multi-Host Rescue
- [ ] Fix one host, move to next via USB
- [ ] Maintain queue of targets in CraicKen
- [ ] Track which hosts are fixed, which need attention

### CraicKen Integration
- [ ] Every repair logged as ken entry (source, timestamp, outcome)
- [ ] CraicKen agent can dispatch ambulance to new targets
- [ ] Fleet-wide repair history available on any boot

### Remote Triage
- [ ] CraicKen agent detects dead host via heartbeat gap
- [ ] Creates rescue ticket with symptoms + last known state
- [ ] Ambulance pulls ticket on boot, goes straight to work

---

## Build Pipeline

### Local Build (Trillian/Ballee-JOG)
```bash
# Current: /opt/fog-ambulance/ on Trillian
# Upstream: /mnt/SANDIEGO/Projects/fog-ambulance/
sudo bash scripts/rebuild-iso.sh --all
```

### Remote Build (LAVE)
```bash
# LAVE pipeline builds fully-baked 3.1GB ISO
# Includes GO API key, all configs, all repair scripts
# Served via portal at http://192.168.1.65:8088/
```

### Flash to USB
```bash
# Identify USB (Cruzer Blade 14GB)
lsblk
# Flash ISO (replace sdb with actual device)
sudo dd if=fog-ambulance-ubuntu-24.04-amd64.iso of=/dev/sdb bs=4M status=progress
# Recreate writable partition in remaining space
sudo parted /dev/sdb mkpart primary ext4 3200MB 100%
sudo mkfs.ext4 -L FOG_AMB_PERSIST /dev/sdb5
```

---

## Deployment Targets

### Priority 1: Vroomfondel (192.168.1.3)
- **Status:** Dark — no ping, no ARP, all ports closed
- **Symptoms:** Dead after bad update — likely boot-level failure (kernel/GRUB/initramfs) or failed dpkg
- **Services:** Minecraft + BeamNG servers on Ubuntu
- **Plan:** Boot from ambulance USB, run fix-dpkg.sh + fix-grub.sh + fix-boot.sh

### Future Targets
- Any fleet host that stops heartbeating on CraicKen
- Windows/Mac machines with boot failures (scripts TBD)

---

## Chat Channel

```
LAVE Big Pickle:  http://192.168.1.65:8088/chat
Post as:          fog-ambulance
Portal:           http://192.168.1.65:8088/
  Upload:         curl -F "file=@FILE" http://192.168.1.65:8088/upload
  Download:       curl -o FILE http://192.168.1.65:8088/files/FILE
```

---

## CraicKen API

```
Endpoint:  http://192.168.1.100:8042 (VIP — MARVIN master, EDDIE backup)
Token:     111JbCV3_BSzwygG0XJ-6kFWDz8v-LHx0rwb8zGv7H8
Ingest:    POST /api/v1/context/ingest  {"text":"...","source":"fog-ambulance","kind":"ken","tags":"repair,fleet"}
Retrieve:  GET /api/v1/context/retrieve?q=<query>&kind=ken&limit=5
```

---

## Version History

| Date | Author | Changes |
|------|--------|---------|
| 2026-06-13 | Trillian + LAVE | Initial roadmap — 3 phases, 9 repair scripts, CraicKen integration |

## First Boot Flow

1. **Insert USB + power on** — BIOS/UEFI boots from USB
2. **GRUB menu** appears with 5 boot modes (standard, verbose, HP Deskpro fix, ACPI-free, memtest)
3. **Ubuntu live environment loads** (squashfs + overlayfs)
4. **Network pre-flight** runs automatically:
   - Tries ethernet DHCP (3s timeout)
   - If no internet, offers WiFi scan or offline mode
   - Reports IP and connectivity status
5. **Smart diagnosis** (Phase 2) probes the LAN:
   - nmap scan of 192.168.1.0/24
   - Check CraicKen for target history (falls back to local scan if offline)
   - Rank repair path based on findings
6. **Rescue menu** appears with options:
   - 1) OpenCode AI Rescue (auto-launch with context from CraicKen)
   - 2-4) Network, CraicKen, Partition tools
   - 5) Linux repair submenu (9 scripts)
   - 6-11) Windows/macOS/backup/diag/shell/reboot/shutdown
7. **Select option 1** → OpenCode starts with Big Pickle model (GO API key) or JonotronV3 fallback (local Ollama)

### CraicKen Unreachable Fallback
If the CraicKen VIP (192.168.1.100:8042) is unreachable:
- Fall back to local nmap scan of LAN
- Inspect /mnt/persist/craic/ cache for last known state
- Offer offline mode with local Ollama + cached repair scripts

---

## Repair Scripts Catalog

### fix-dpkg.sh
- Inspects /var/log/apt/history.log for partial upgrades
- Runs `dpkg --configure -a` and `apt-get install -f`
- Attempts to downgrade known-bad packages

### fix-docker.sh
- Checks Docker daemon status
- Inspects container states (running/exited/restarting)
- Attempts restart of failed containers

### fix-network.sh
- Backs up /etc/netplan/ and /etc/network/interfaces
- Inspects current network config
- Restores from backup if requested

### fix-rollback.sh
- Inspects apt history for upgrade timestamps
- Offers kernel downgrade option
- Lists available old kernels in /boot

### fix-grub.sh
- Reinstalls GRUB to MBR/EFI partition
- Regenerates grub.cfg
- Detects dual-boot configs

### fix-fstab.sh
- Backs up /etc/fstab
- Attempts to mount all entries
- Comments out failing entries

### fix-boot.sh
- Repairs boot sector (Windows MBR or Linux GRUB)
- Checks EFI partition for missing bootloaders

### fix-kernel-panic.sh
- Inspects /var/log/kern.log for panic traces
- Suggests boot parameter workarounds
- Creates GRUB entry with fix flags

### scan.sh
- Scans all disks for partitions and OS signatures
- Detects Linux, Windows, macOS installs
- Reports filesystem health

### smart-diagnose.sh (Phase 2)
- Probes target via ping/SSH/HTTP
- Queries CraicKen for last known state
- Ranks repair path based on findings
- Logs diagnosis back to CraicKen
