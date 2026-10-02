# Changelog

## 2026.10.02: two editions, one core

**Editions and build**
- The caddy SSD (installed, writable) and the USB stick (live, read-only) are now editions of one core.
- `build/sysmedic-deploy` installs shared files, edition files, the AI instructions, docs and package lists onto either drive. Both carry the same version stamp when their core matches.
- Plugging the stick into a running caddy collects its sessions automatically.

**Hardware testing**
- `sysmedic-hwtest` (menu 16): health report, CPU/cooling stress, RAM, disk self-test and read-only speed/surface scans, GPU, input, audio, battery and inventory. Results go into the job report.
- 42 hardware-testing packages on both editions (stress-ng, s-tui, memtester, rasdaemon, turbostat, fio, glmark2, nvtop, upower, evtest…).
- **MemTest86+ 7.00** in the boot menu of both editions, UEFI and BIOS.

**BitLocker**
- The console 2 banner lists the machine's BitLocker volumes with the exact unlock command and the recovery-key format.

**Wi-Fi**
- Fixed "no Wi-Fi" on kernel 7.0: Wi-Fi drivers are kept out of the initramfs, where newer drivers couldn't find firmware (Intel AX201 on a Latitude 3410).
- The scan reports drivers that couldn't load their firmware.
- Wi-Fi is joined with `nmtui` (menu 2, `wifi`).

**Network**
- About 60 network tools on both editions; listening/announcing services are masked.
- Public DNS fallback, and a "DNS broken" diagnosis.

**Offline AI**
- Read-only commands run immediately with full output streamed on TTY1. Enter = yes. Chained commands auto-run only if every part is read-only. Commands written in prose need an explicit `y`.
- Previously, Enter meant "No" and output was dimmed and cut to 60 lines.

**Session transcripts**
- Console transcripts, saved AI conversations, `sysmedic-note --feedback`, and `claude-review.md` bundled at shutdown.

**Self-check**
- The scan reports SysMedic's own USB link speed (a USB 2.0 port made the caddy about 10× slower in a field test).

**The merged caddy**
- Kernel 7.0 and the full toolkit.
- Credentials, old AI history, the always-on SSH and a bypassable auth gate removed.
- OpenCode updated to v2.0.22: the stale Go-plan login caused "Reconnect OpenCode Console". The free tier needs no login.

**Docs**
- Full documentation in `docs/`, installed on both drives (`sysmedic-help`).

## 2026.10.01: the rebuilt stick (phases 1–5)

- The stick made USB-bootable: hybrid MBR/GPT and an EFI partition. It had been unbootable from USB.
- Persistence partition; label-only mount, never the patient's disk.
- Secrets removed (API key, CraicKen token, WireGuard keys, Wi-Fi passwords).
- **Phase 1:** HWE kernel 7.0, full firmware, Secure Boot.
- **Phase 2:** the read-only triage scan.
- **Phase 3:** kernel write protection, `sysmedic-unlock` with backups, the audit trail, the offline assistant, cloud consent, OpenCode permissions.
- **Phase 4:** `sysmedic-win`: info, crashes, events, autoruns, ClamAV, BitLocker, update/hibernation/password fixes.
- **Phase 5:** job reports, job notes, the phone dashboard.

## 2026.06: v2.0–v3.0 (caddy)

- Multi-OS toolkit (28 menu options), BitLocker CLI and web unlock, Windows/Linux/macOS repair scripts.
- Stress-test and burn-in suite, partclone OS capture/restore, AI deep-analysis pipeline, GRUB theme, self-update.
