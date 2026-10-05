# SysMedic

**An AI-assisted rescue system for field engineers.** Boot a broken PC from SysMedic. In about a minute it tells you, in plain English, what's wrong with the machine. An AI assistant then helps you fix it, while the customer's disks stay protected against any write you haven't explicitly allowed.

SysMedic runs on Ubuntu 24.04 with the 7.0 HWE kernel. It boots on UEFI (with Secure Boot on) and legacy BIOS machines.

---

## Two editions, one core

| | **Caddy edition**: the workshop | **Stick edition**: the grab-bag |
|---|---|---|
| Medium | NVMe SSD in a USB 3 enclosure, installed Ubuntu (writable) | USB stick, live image (read-only squashfs, clean every boot) |
| Toolkit | Everything, plus deep recovery, imaging, burn-in suite, macOS repair | Triage, network, Windows/BitLocker, hardware tests, basic recovery |
| Offline AI | qwen2.5 7B on machines with 12 GB+ RAM, otherwise 3B | 3B (loads fast over USB 2.0; 7B on request) |
| Storage | ~200 GB free for disk images and sessions | persistence partition for sessions, backups and models |
| Best for | Bench jobs, long repairs, data recovery | Quick diagnosis, the bag, machines you'd rather not plug the caddy into |

Both editions share the same core: scan, safety layer, assistants, Windows toolkit, hardware tests, reports, dashboard and transcripts. They're built from this repo by `build/sysmedic-deploy`, which stamps both with the same version (e.g. `2026.10.02-42668268`) when their core matches. The version shows in the boot banner and the menu.

---

## What it does

- **Triage scan at boot** (read-only): disk health (SMART/NVMe), filesystems, installed OSes, boot setup (EFI/BCD/GRUB/fstab/initramfs), BitLocker/LUKS, Windows crashes, event-log errors and suspicious autostarts, network and DNS, missing firmware, and SysMedic's own USB link speed. Every finding comes with a next step.
- **Kernel write protection.** Every disk except SysMedic's own is read-only from the moment it appears. Writes need `sysmedic-unlock` on a console, which asks for a reason, takes backups first and is audited. The AI can't unlock.
- **AI assistants:**
  - **Cloud** (OpenCode with the free Big Pickle model, no login), running as SysMedic: its own agent, logo and console theme, with full command output (no mouse needed). Used only after the customer consents.
  - **Offline** (`sysmedic-ask`, local qwen2.5 via Ollama). Read-only checks run straight away with full output on screen; anything else is shown to you first.
- **Windows toolkit** (`sysmedic-win`): version and state, blue-screen stop codes decoded, event-log analysis, autoruns with suspicious entries flagged, a ClamAV malware scan, **deep troubleshooting** (every event log, registry evidence, CBS/DISM/Windows Update logs, one-command check-up report), and **BitLocker unlock with the recovery key**, on the console or typed on a phone/laptop over a secure link. It can also roll back a stuck update, clear Fast Startup hibernation, and reset a local password.
- **Hardware testing** (`sysmedic-hwtest`): health report, CPU/cooling stress, RAM (memtester, and MemTest86+ from the boot menu), disk self-tests and read-only speed/surface scans, GPU, keyboard/touchpad, audio, battery wear and inventory.
- **Network toolkit:** ~60 tools, from ping/dig/mtr to tcpdump/tshark, iperf3, SMB/NFS, SNMP and Wi-Fi survey. Wi-Fi is offered on the first screen at boot (`nmtui`); passwords stay in RAM.
- **Job reports:** a plain-English report per visit (found → fixed → still to do, work performed, backups, notes, sign-off), printable to PDF.
- **Phone dashboard:** live findings, write-protection state, job notes and the report, on your phone via QR code. View and notes only; no repairs from the phone.
- **Session transcripts:** every console and AI conversation is recorded and bundled into `claude-review.md` for improving SysMedic later.

Full list: **[docs/CAPABILITIES.md](docs/CAPABILITIES.md)**

---

## Quick start (field)

1. **Power off** the machine. Plug in SysMedic (the caddy into a **USB 3 / SS port**). Boot from it (F12 / Esc / Option).
2. Read the **triage scan**. Answer the cloud-AI consent question. Press Enter to start the assistant.
3. **Console 2** (`Alt+F2`) is your engineer console. Unlock partitions, BitLocker and repairs happen here. Its banner lists the BitLocker volumes found, with the exact command to type.
4. `menu` opens the rescue menu: Wi-Fi (2), triage (4), Windows tools (6), unlock/lock (11/12), job report (13), phone dashboard (14), hardware tests (16).
5. Finish with `sysmedic-lock`, the **job report** (menu 13), and a clean shutdown.

Step by step: **[docs/FIELD-GUIDE.md](docs/FIELD-GUIDE.md)**. On the drive itself: `sysmedic-help`.

---

## Documentation

| | |
|---|---|
| [CAPABILITIES](docs/CAPABILITIES.md) | Everything SysMedic can do, by area, with commands |
| [FIELD-GUIDE](docs/FIELD-GUIDE.md) | A visit from boot to sign-off; consoles, menu, troubleshooting |
| [SAFETY-AND-PRIVACY](docs/SAFETY-AND-PRIVACY.md) | Write protection, unlock, audit trail, AI permissions, consent, what's stored where |
| [WINDOWS-AND-BITLOCKER](docs/WINDOWS-AND-BITLOCKER.md) | `sysmedic-win`: diagnosis, BitLocker, repairs |
| [HARDWARE-TESTING](docs/HARDWARE-TESTING.md) | `sysmedic-hwtest` and the tools behind it; reading results |
| [NETWORK](docs/NETWORK.md) | Network toolkit, Wi-Fi, DNS fallback |
| [AI-ASSISTANTS](docs/AI-ASSISTANTS.md) | Cloud and offline AI, approvals, models, limits |
| [BUILDING](docs/BUILDING.md) | **Build a stick or caddy from scratch** (Ubuntu ISO → SysMedic), test in QEMU |
| [EDITIONS-AND-DEPLOY](docs/EDITIONS-AND-DEPLOY.md) | Caddy vs stick, the build kit, `sysmedic-deploy`, versions, testing |
| [IMPROVING-SYSMEDIC](docs/IMPROVING-SYSMEDIC.md) | Transcripts, `claude-review.md`, feedback, collecting sessions |
| [CHANGELOG](docs/CHANGELOG.md) · [ROADMAP](ROADMAP.md) | History and what's next |

---

## Repository layout

```
build/                      the build kit: the source of truth for both editions
  sysmedic-deploy           install onto the caddy, or build and write the stick
  build-iso.sh, make-stick.sh, vm.py
  staging/shared/           files installed identically on both editions (root-relative paths)
  staging/editions/         per-edition files (caddy: stick-session collector)
  staging/agent/            AI instructions: core + per-edition toolkit section
  staging/packages/         package lists (shared, caddy, stick) and services kept off
  staging/iso/              the stick's boot menu (GRUB)
  tests/                    fixture generators for the QEMU tests
docs/                       documentation (also installed on both drives)
menu.sh, scripts/, ...      the caddy's advanced toolkit (option 15): stress/burn-in, imaging, macOS, extra Windows repairs
```

## Status and known limits

- Tested extensively in QEMU, including Secure Boot, BIOS, simulated faults and real BitLocker/registry/event-log fixtures. **Early real-hardware testing so far** (Dell Latitude 3410, Dell Pro 13 Plus).
- The offline 3B model makes factual slips. Tool output is always on screen; trust it over the summary. The cloud model and the 7B model are better.
- APFS is read-only (the read-write driver doesn't build on kernel 7.0). WPS isn't supported (use `nmtui`). Building a BCD from Linux isn't attempted (use WinRE).
- The persistence partition and the caddy aren't encrypted. A lost drive exposes customer reports and backups.

## License

MIT. Use freely, fork wildly, save machines.
