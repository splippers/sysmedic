# Changelog

## 2026.10.04: Wi-Fi first, BitLocker from a phone, OpenCode as SysMedic

- **Network first:** the first screen at boot gets SysMedic online (`sysmedic-connect`): wired passes by itself, otherwise nearby Wi-Fi networks are listed and `nmtui` opens on Enter; skipping (or 60 s) carries on offline. The banner then shows how SysMedic is connected.
- **Wi-Fi passwords in RAM only** on both editions (NetworkManager keyfile path in `/run`); the deploy removes any saved on a drive before.
- **BitLocker web unlock** is back, rebuilt safely: `sysmedic-win bitlocker-web` (menu 6 → w). HTTPS with a per-run certificate, a secret QR link, read-only, Key ID shown, 5 wrong keys / 15 minutes and it stops, nothing logged. The old portal was removed in 2026.10.02 because it had no authentication. Tested against cryptsetup's BitLocker test volume: wrong link 404, wrong key refused, right key unlocked, link closed, key in no log.
- **OpenCode is SysMedic:** a default SysMedic agent whose prompt is SysMedic's instructions (replacing OpenCode's coding-assistant prompt; it answers "I'm SysMedic…"); Build/Plan agents off; auto-update and sharing off.
- **OpenCode looks like SysMedic:** SysMedic logo, a 16-colour console theme, rescue examples and tips (`build/opencode-brand.py`, applied by the deploy).
- **No more "Click to expand":** tool output starts fully expanded (it needed a mouse); read long output with Page Up/Down. Verified: all 40 lines of a 40-line output drawn.
- Console font: Terminus 11×22 in the **Vietnamese** set (full Latin plus the block and line-drawing characters; the Lat15 set chosen earlier lacked ▀ ▄ and garbled OpenCode's logo on the Linux console).
- The ISO build now mounts its base image if needed and **fails loudly** if xorriso fails (a failure had silently left the previous ISO in place during testing; the drives weren't affected).
- Correction: the OpenCode version is 1.18.34 (earlier notes said 2.0.22).

## 2026.10.04: deep Windows troubleshooting

- `sysmedic-win evtx`: ingests **every** event log (not only System) with curated rules for the logs that explain problems, an error sweep of all others, Windows' boot-time measurements and a Security summary. Takes exported `.evtx` files too.
- `sysmedic-win registry`: registry evidence: missing service/driver files, device filter drivers that don't exist, hijacks, Defender/Update policies and exclusions, crash-dump and paging settings, proxies, hosts redirects, recent installs.
- `sysmedic-win cbs`: CBS.log and archived CbsPersist logs (cabextract), dism.log, ReportingEvents.log and Panther: failing updates, decoded HRESULTs, component-store corruption, SFC/DISM results and a verdict with next steps.
- `sysmedic-win checkup`: all of it plus info/crashes/autoruns, saved as `windows-checkup-*.md` in the session folder. Menu 6 → c/e/r/s.
- The AI may run all four. Its instructions say to start "full check-up" requests with `checkup` and to correlate across sources.
- Test fixtures extended with planted registry and servicing problems.

## 2026.10.04: stick Wi-Fi and the offline assistant

**Stick Wi-Fi ("unavailable" on the Latitude 3410).** Root cause: the stick's live system stacked the stock Ubuntu `ubuntu-server` squashfs layer *on top of* SysMedic's own, so 4,890 stale stock files hid SysMedic's. That included `/etc/group` without the `netdev` group, so `wpa_supplicant` could never start ("Failed to determine group credentials") and NetworkManager had no supplicant for the Wi-Fi card.
- The stock layer's 19,580 files SysMedic lacked (Python libraries, git, vim, …) and its 129 package records are merged into the stick's system, without overwriting anything of SysMedic's. The stick now ships that layer empty (`build-iso.sh`).
- Missing system accounts restored (`syslog`, `crontab`, `landscape`), which also fixes rsyslog. The console font config is corrected (`staging/shared/etc/default/console-setup`).
- A stale `wpa_supplicant` override is removed. `staging/obsolete.txt` lists leftovers that `sysmedic-deploy` deletes.
- Verified in QEMU with a simulated Wi-Fi card: supplicant active, card ready to connect, no failed services.

**Offline assistant.** On the stick it uses `qwen2.5:3b`: the 7B took minutes to load over USB 2.0 and showed nothing meanwhile. A `thinking… m:ss` timer now shows until the first word (both editions).

## 2026.10.03: lessons from a Windows 11 audit

- The AI never reproduces credentials (passwords, security answers, keys, tokens) it finds; it reports them as found and redacted. It saves its reports in the session folder (so they're in the job record and review bundle) and flags company-managed devices.
- The self-check warns when SysMedic's own EFI partition is nearly full. The caddy's was 100% full (a 505 MB macOS recovery image), now moved to `/srv/sysmedic/macos-recovery/`.
- The version stamp covers the AI instructions and package lists as well as the shared files, dated by the last commit that changed them.

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
- OpenCode's stale Go-plan login removed: it caused "Reconnect OpenCode Console". The free tier needs no login.

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
