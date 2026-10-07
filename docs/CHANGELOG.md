# Changelog

## 2026.10.07 (afternoon): graphics battery on the laptop's own screen

- **`sysmedic-gfx`**: `info` (GPUs, driver in use, real renderer, displays with panel identity), `display` (10 full-screen test patterns), `bench` (glmark2 OpenGL ES + vkmark Vulkan on screen), `stress MIN` (burn-in), `video` (VA-API decode). New tests `gpu-info`, `gpu-display`, `gpu-bench`, `gpu-stress`, `gpu-video` (slash commands, phone, AI: "check for dead pixels", "graphics burn-in", "vulkan benchmark").
- **Live telemetry panel** over the visuals: FPS with sparkline, GPU clock/load bars, temperature and power with history, CPU load/clock/temperature, throttling; read from the kernel (no vendor tools) and saved as CSV for the report. Results name scores, per-scene FPS, peaks, throttling and GPU hangs/resets.
- MangoHud (Ubuntu 24.04's 0.6.9) was tried for the overlay and dropped: it crashed glmark2 and didn't draw. Packages added: sway, foot, seatd, vkmark, glmark2-es2-wayland, kmscube, vainfo, intel-media-va-driver, mesa-va-drivers.

## 2026.10.07 (later): the offline AI obeys, and uses a discrete GPU when there is one

- **Obedience, enforced in code.** Declined commands, "No", "forget/drop X" and corrections are remembered for the conversation and enforced by SysMedic (re-offers are held back, and flagged and rewritten if they appear in text). "No" alone gets "OK." without a new suggestion. After a correction the model no longer sees its earlier plan, and in general only the last few exchanges. Its instructions now open with "the engineer is in charge: do exactly what the latest message asks, nothing more, no unasked offers". Replayed the 3410 session: after "These tests do not exist" it now says "Got it, I'll stick to known tests" instead of re-offering `memslot`.
- **GPU for the offline AI.** Ollama's Vulkan backend and Mesa's Vulkan drivers ship on all drives. `sysmedic-ai-device` picks a discrete GPU with ≥3.5 GiB (never built-in graphics, which measured 5× slower than the CPU), self-tests it after the model loads, and falls back to the CPU if it fails, stalls or is slow. Measured on a GTX 1650 with qwen2.5:3b: 319 tok/s reading the prompt against 24 on the CPU, replies at 40-49 tok/s against 10.

## 2026.10.07: real tools only, and memory testing

From the 3410 session at 23:00, where the offline AI offered `sysmedic-tests start memslot` and `mem` (neither existed), a malformed surface test, and said it would record the session without doing so:
- **The AIs can only use real tools.** The offline assistant checks every proposed command (installed program, real test name, correct `--disk` form, real `sysmedic-hwtest`/`sysmedic-win` subcommand); fakes go back to the model with the real list, and fakes in its prose are flagged and corrected. Both AIs' instructions now contain the generated test catalogue. In AI shells a missing command says "does not exist on this rescue system" and is logged. `sysmedic-tests` maps common guesses to real tests and suggests the closest name; `sysmedic-hwtest` fails (instead of printing help) on an unknown test.
- "Record/report/flag this" in the offline assistant saves SysMedic feedback. Direct test requests now show the test live (`sysmedic-tests watch`), so it doesn't look stuck.
- **Memory testing:** new tests `ram-modules` (each slot's module, speed, maker/part, ECC/EDAC errors per slot, SPD; how to find a bad SODIMM), `ram-stress` (stressapptest), `ram-speed` (mbw; spots a module that isn't working via single-channel bandwidth). Installed: stressapptest, mbw, tinymembench, lmbench, numactl, pcm, alongside memtester, MemTest86+ (boot menu), stress-ng, sysbench, edac-utils, rasdaemon, i2c-tools (decode-dimms). "I think I have a bad SODIMM" goes straight to `ram-modules`.

## 2026.10.06 (late): fixes from the 3410 test session

- **The offline assistant does what it's asked.** On the 3410 it ignored "test the GPU" four times and kept proposing a broken `mount` command. Plain requests for a test ("test the GPU", "check the battery", "how's the Wi-Fi") now run the matching SysMedic test directly (Enter = yes) and the model only explains the result; every message reminds the model to answer the latest request. New `/tests` and `/feedback TEXT` commands.
- **Graphics benchmark can't hang.** It ran for over an hour on the 3410 with nothing on screen (output was buffered and there was no time limit). It now runs 8 short scenes at 1280×720 (about 40 s), shows each scene's result as it goes, and stops after 150 s with "FAILED: stalled" plus any GPU driver errors from the kernel log. It warns when the score comes from software rendering (llvmpipe: no GPU driver in use) rather than the graphics chip.

## 2026.10.06 (evening): what the stick's AI found on the 3410

Seven problems in SysMedic's own tools, diagnosed by the AI with evidence, are fixed:
- `evtx` read only 111 of 429 logs (a wrong "empty log" size rule): it now reads every log and reports empty/unreadable ones by name. The skipped logs held the real root cause (Storport 524 NVMe command timeouts), which now has its own rule, as do ClassPnP 507/509.
- Storage errors name their **device** (vendor, model, serial's last 4): 732 of 733 "disk errors" were the SanDisk stick, not the laptop's NVMe.
- Code-integrity events are grouped **by file**; security-product components (FortiClient's AMSI DLL: 17,933 events) are labelled usually benign instead of reading like a compromise.
- The `cbs` verdict only gives upgrade-failure advice for 0xC19xxxxx codes actually present; 0x80070422 names the usual disabled services including System Restore, which the registry check now reports.
- The job report never says **fixed** unless a repair happened and the last scan could still see the system; otherwise "no longer detected; not confirmed fixed". It also states when no malware scan ran.
- A `fsck.vfat` volume-label-only mismatch is reported as cosmetic.

New, as the AI requested:
- **`sysmedic-win etl`**: Windows Update and other components' ETW traces, decoded with the vendored etl-parser (pure Python, Apache-2.0; with construct, MIT). Also in `checkup`, `/windows-traces`, and the phone Tests card.
- **More Windows log readers:** libesedb-utils, libscca-utils, libevt-utils, libregf-utils, liblnk-utils; a coverage table in WINDOWS-AND-BITLOCKER (perfmon/WMI repository: unsupported).
- More error codes decoded (0x8024401C, 0x80072EE6, 0x8024000C, 0x80070057, 0x800704CF).
- **Battery** on the phone dashboard (charge, health, cycles; worn batteries flagged).
- **No downloaded code:** the AI had cloned etl-parser from GitHub and fetched a wheel from PyPI to run as root. Both AIs are now blocked from `git clone`, pip and PyPI/GitHub downloads, and told to record missing tools as feedback instead; SysMedic ships vetted code.

## 2026.10.06 (later): BitLocker from the dashboard

- **One QR code:** the phone dashboard has a BitLocker card (volumes, locked/unlocked) with **Unlock from this phone**, which starts the encrypted unlock page and opens it at the address the phone already used. The key never touches the plain-HTTP dashboard. Verified in QEMU against a real BitLocker test volume: started, unlocked read-only, page closed itself, key in no log. Both AIs are blocked from the dashboard's secret and BitLocker endpoint.

## 2026.10.06 (later): lessons from the new caddy's first two 3410 visits

- **The offline AI ran a destructive disk test.** Qwen 7B proposed `badblocks -w` (overwrite test) on the customer's Windows partition, and `fsck -f`; both were approved at the prompt. The kernel write-protection refused every write, so **no data was touched**, but the AI then misread the refused writes as "multiple bad blocks". Now: write-mode badblocks, fsck-family repairs (anything without `-n`), mkfs, wipefs, shred, discard, `dd` to a disk, partitioning, secure erase, NVMe format, unlock and chntpw are **refused outright** by the offline assistant (not offered), and denied for OpenCode. Both are told a surface test is `sysmedic-tests start surface` (read-only) and that failed writes on a protected disk are not bad blocks. Rules checked to agree on OpenCode 1.18 and 2.0.
- **"No installed operating system found" after a rescan** (Windows was there): the scan tried to mount a partition `sysmedic-win` had already mounted. It now reads the existing mount and leaves it mounted.

## 2026.10.06: build from scratch, tests everywhere, a cleaner OpenCode, AI self-repair

- **Build from scratch:** `build/bootstrap.sh` (kit, fetch, stick-base, caddy) turns the stock Ubuntu 24.04.5 ISO into a stick or caddy, with pinned OpenCode 1.18.34, Ollama 0.23.4 and Qwen models; guide in [BUILDING](BUILDING.md). The ISO build accepts the stock ISO (installer layers left out, EFI image extracted); the stick's initramfs boots casper (`conf.d/default-boot-to-casper.conf`, now in the repo).
- **Tests everywhere:** `sysmedic-tests` catalogues 19 hardware and software tests, runs them in the background and records them in the job report. They're OpenCode slash commands (`/disk-test`, `/cpu-stress`, `/windows-checkup`, `/full-check`, `/tests`…), menu 16, and a Tests card on the phone dashboard (run, live output, stop).
- **A cleaner OpenCode:** no sidebar, thinking, timestamps, metadata, animations, tips or upsells; the `/` menu shows the tests instead of developer commands (still in Ctrl+P). On both 1.18 and 2.0.
- **AI self-repair:** `sysmedic-ai-repair` (menu 17) restores OpenCode and the offline AI to a known-good state and self-checks; boot points to it if OpenCode crashes at start.
- **Qwen only:** jonotron removed (repo, config, stick, caddies).
- **Caddy settings in the repo:** boot menu, Ethernet netplan, UK keyboard, persistence service, root's shell setup, the toolkit in `/opt/sysmedic` (it had drifted). The blacklist that left Realtek USB Wi-Fi dongles without a driver on kernel 7.0 is removed. More services that announce on networks are masked.
- The deploy stops with the failing line instead of silently, and handles a fresh system.

## 2026.10.05: lessons from a stick-vs-caddy run on the same Latitude 3410

Measured: the stick (Cruzer Blade) is a USB 2.0 drive, 25 MB/s sequential / 252 random IOPS; the caddy 276 MB/s / 1,768 IOPS. Loading the offline model: stick 253 s (3B, 1.9 GB), caddy 13.8 s (7B, 4.7 GB). With everything in RAM they're equal (same CPU, same cloud model).
- **The AI can't power the machine off.** It had rebooted or powered off in three sessions despite instructions. `reboot`, `poweroff`, `shutdown`, `halt`, `systemctl reboot|poweroff|…`, `init 0/6`, sysrq are now denied in OpenCode's config and refused outright by the offline assistant (not even offered for approval). The instructions say so explicitly.
- **No improvising:** `dislocker`, `pip install` and reading or copying the SAM/SECURITY hives are denied (the caddy's AI had unlocked BitLocker with dislocker, copied the hives to /tmp and tried to pip-install a parser). The instructions point at `sysmedic-win` instead. Rules checked against OpenCode's own matching logic (longest pattern wins) and the exact commands from that session.
- **OpenCode's settings now apply on the caddy too.** The caddy runs OpenCode **2.0.22** (the stick 1.18.34), and 2.x reads only `opencode.json`; it had been ignoring `config.json`, so on the caddy none of SysMedic's OpenCode settings applied (permissions, model, SysMedic agent). The file is now `opencode.json` (both versions read it; the old one is removed). Verified on 2.0.22: loads 167 rules, answers as SysMedic, blocks power commands and pip; rule outcomes checked to match on both versions (1.18: longest pattern wins; 2.0: last rule wins).
- **Branding on OpenCode 2.x:** bash output starts expanded and tool summaries aren't cut to 4 lines. Each patch now applies independently, so an already-branded binary still gets new ones.
- **Saved Wi-Fi passwords removed from netplan:** Ubuntu's NetworkManager had mirrored the caddy's networks into `/etc/netplan/90-NM-*.yaml` with their passwords. The deploy removes those; with networks kept in RAM, NetworkManager no longer writes them (verified).
- **Honest drive-speed advice:** the scan reads the drive's own USB version. A USB 2.0 drive is reported as such ("can't go faster in any port; use the caddy or a USB 3 stick") instead of "use a USB 3 port"; the port advice is kept for USB 3 drives on a slow link. The drive model is named.

## 2026.10.04: Wi-Fi first, BitLocker from a phone, OpenCode as SysMedic

- **Network first:** the first screen at boot gets SysMedic online (`sysmedic-connect`): wired passes by itself, otherwise nearby Wi-Fi networks are listed and `nmtui` opens on Enter; skipping (or 60 s) carries on offline. The banner then shows how SysMedic is connected.
- **Wi-Fi passwords in RAM only** on both editions (NetworkManager keyfile path in `/run`); the deploy removes any saved on a drive before.
- **BitLocker web unlock** is back, rebuilt safely: `sysmedic-win bitlocker-web` (menu 6 → w). HTTPS with a per-run certificate, a secret QR link, read-only, Key ID shown, 5 wrong keys / 15 minutes and it stops, nothing logged. The old portal was removed in 2026.10.02 because it had no authentication. Tested against cryptsetup's BitLocker test volume: wrong link 404, wrong key refused, right key unlocked, link closed, key in no log.
- **OpenCode is SysMedic:** a default SysMedic agent whose prompt is SysMedic's instructions (replacing OpenCode's coding-assistant prompt; it answers "I'm SysMedic…"); Build/Plan agents off; auto-update and sharing off.
- **OpenCode looks like SysMedic:** SysMedic logo, a 16-colour console theme, rescue examples and tips (`build/opencode-brand.py`, applied by the deploy).
- **No more "Click to expand":** tool output starts fully expanded (it needed a mouse); read long output with Page Up/Down. Verified: all 40 lines of a 40-line output drawn.
- Console font: Terminus 11×22 in the **Vietnamese** set (full Latin plus the block and line-drawing characters; the Lat15 set chosen earlier lacked ▀ ▄ and garbled OpenCode's logo on the Linux console).
- The ISO build now mounts its base image if needed and **fails loudly** if xorriso fails (a failure had silently left the previous ISO in place during testing; the drives weren't affected).
- OpenCode versions: the caddy runs 2.0.22 and the stick 1.18.34.

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
