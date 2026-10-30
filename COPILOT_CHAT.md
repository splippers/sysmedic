# COPILOT_CHAT

A hand-over of the Claude Code session called "SysMedic" for whoever (Copilot or a person) picks the work up next. Written 2026-10-30. Everything below is in the repository; nothing here depends on that chat.

## What Copilot asked for

"Review the SysMedic README, ROADMAP, build scripts, partition layouts, safety/privacy documentation and tests, then add this design direction": a Windows-safe USB presentation (Windows sees only one exchange partition), a SysMedic exchange partition with `SYSMEDIC.ID`, `README.txt`, `collector/`, `INBOX/`, `EXPORT/`, a read-only Windows evidence collector, encrypted portable snapshots (existing standards, no new crypto, distinct from the LUKS vault), provenance, privacy/consent (no call-home, offline, nothing collected on insert), a future VNA boundary, doc/roadmap/changelog updates, tests, commit and push.

## Answers, in short

| Question | Answer | Where |
|---|---|---|
| Current partition layouts? | Stick: 1 ISO9660, 2 EFI, 3 gap (both 1 and 3 are *basic data*), 4 `FOG_AMB_PERSIST` ext4. Caddy: 1 ESP `SYSMEDIC`, 2 `sysmedic-root` ext4. | `build/make-stick.sh`, `build/bootstrap.sh`, docs/EXCHANGE.md |
| What would Windows show today? | Drive letters and a "format this disk" prompt for the stick's ISO and gap partitions. | docs/EXCHANGE.md section 1 |
| How is it hidden? | GPT attribute bits 62 + 63 on the basic-data partitions that are not the exchange one. Types, starts, sizes, numbers untouched, so UEFI/Secure Boot/BIOS boot are unaffected. | `build/xchg_layout.py` |
| Exchange filesystem? | exFAT, label `SM_EXCHANGE`, always the last partition (512 MiB stick, 256 MiB Lite, 1 GiB caddy). Native on Windows, kernel driver on Linux, no 4 GB limit, no proprietary or FUSE code. | docs/EXCHANGE.md |
| Snapshot encryption? | **age** (X25519 + ChaCha20-Poly1305). The customer's machine only holds the public key; the private key stays on the SysMedic drive, passphrase-protected. Rejected: BitLocker To Go/VeraCrypt (Windows driver/admin), zip/7z passwords, hand-built .NET AES. | docs/EXCHANGE.md section 5 |
| Collector? | `tools/windows-collector/SysMedic-Collect.ps1`, PowerShell 5.1, lists what it will read and needs `YES`, no network code, evidence in memory, only ciphertext written, refuses to run without a recipient key or `age.exe`. | tools/windows-collector/ |
| Provenance? | `manifest.json` in the container: snapshot id, collector name/version/script hash, times, consent, source machine, per-file SHA-256, failures, omissions, configuration. Raw evidence, findings and conclusions are kept in separate places. | docs/EXCHANGE.md section 4 |
| Linux side? | `sysmedic-snapshot init / list / import / verify`. Import writes read-only `raw/` plus `import.json` into the visit folder (so inside the vault). | `build/staging/shared/usr/local/sbin/sysmedic-snapshot` |
| VNA? | Not built. The boundary is the imported `raw/` directory and `import.json`. | docs/EXCHANGE.md section 7 |

## Done and where

- Commit `87a211e` (pushed to `origin/master`): exchange partition, `xchg_layout.py`, `make-stick.sh`/`bootstrap.sh`/`sysmedic-deploy` changes, collector, `sysmedic-snapshot`, `age` in the shared packages, `build/tests/test_exchange.py` (42 tests), docs (EXCHANGE, README, ROADMAP, SAFETY-AND-PRIVACY, BUILDING, EDITIONS-AND-DEPLOY, STICK-LITE, CAPABILITIES, HARDWARE-TESTING, CHANGELOG).
- Following commit (this one): quiet stick boot. The user also asked to "lose the brief error at boot time where it says path or file not found" on the stick. Cause: Ubuntu's casper scripts in the initramfs (`can't open /dev/sr0: No medium found`, `GPT PMBR size mismatch`, `apt-cdrom` errors, `passwd`/`chown` warnings). Fix: `nopersistent` on the GRUB entries plus the initramfs hook `build/staging/shared/etc/initramfs-tools/hooks/zz-sysmedic-quiet-boot`; test `build/tests/test_quietboot.py` (10). Details in docs/CHANGELOG.md.

## How it was tested

- `python3 build/tests/test_exchange.py` (42, one skipped for lack of PowerShell), `python3 build/tests/test_quietboot.py` (10), `python3 build/tests/test_discoverlib.py`, `python3 tools/telemetry/test_hub.py`: all pass.
- A real Lite image built with the new layout: `fsck.exfat` clean, ext4 persistence clean, mounts, boots in QEMU under UEFI Secure Boot and BIOS.
- The full stick image rebuilt with the quiet-boot hook: the hook edits are present in the produced initrd; booted in QEMU (UEFI Secure Boot) with fast screen captures: GRUB, login, SysMedic screen, with none of the earlier error lines.

## Not verified (needs real hardware or Windows)

- Windows 10/11 showing only `SM_EXCHANGE` and never offering to format anything; `SysMedic-Collect.ps1` running (it was read and bracket-checked, never executed: no PowerShell was available); antivirus/SmartScreen behaviour on `age.exe`. Procedure: docs/HARDWARE-TESTING.md, "Exchange partition on real Windows".
- Boot on real UEFI (Secure Boot on and off) and legacy-BIOS machines after both changes; the quiet boot on real hardware (only QEMU so far).
- `age.exe` is fetched by `tools/windows-collector/fetch-age.sh` against a SHA-256 pinned from the v1.2.1 release at the time; that stops changed downloads, it doesn't prove authenticity. Cross-check by building age from source at the tag.

## Not changed (deliberately)

- No existing drive was touched. The stick gains the exchange partition when it is rewritten (`sysmedic-deploy --stick`, which saves and restores `INBOX`, `EXPORT`, `SYSMEDIC.ID`); caddies when rebuilt. There is no automatic migration for existing caddies because it would mean shrinking their customer-bearing root filesystem (manual steps are in docs/EXCHANGE.md section 8).
- The `.hushlogin` option, which hides Ubuntu's login notice on the stick, was not applied: it isn't an error, and the user asked about the error.

## Follow-ups (also in ROADMAP.md)

1. Real Windows 10/11 validation of the exchange partition and collector.
2. `sysmedic-snapshot analyse`: `raw/` to `findings/` to the job report (kept apart from the evidence).
3. Safe offline migration for existing caddies; `EXPORT/` writing; optionally signed collectors.
4. Deliberate, offline "export to VNA" from an imported snapshot.
5. Housekeeping noticed on the way: README and ROADMAP said the persistence partition and caddy were unencrypted (the LUKS vault shipped on 2026-10-12): corrected in this work; the ROADMAP encryption item now says to keep validating the vault on real hardware.

## Working rules this session followed

Never write to a drive without the engineer's say-so (none was written); customer-data disks stay write-protected; no credentials passed through the shell; no call-home or telemetry; push only to the existing remote and branch, no force-push.
