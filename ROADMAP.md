# SysMedic roadmap

**Current:** 2026.10.02. Two editions (caddy and stick) from one build kit. See [docs/CHANGELOG.md](docs/CHANGELOG.md).

## Done

- Bootable on UEFI (Secure Boot) and BIOS, kernel 7.0 with full firmware
- Read-only triage scan with plain-English findings
- Kernel write protection, engineer-only unlock with backups, audit trail
- Cloud (free Big Pickle, consent-gated) and offline (qwen2.5) assistants with approvals
- Windows toolkit including BitLocker unlock and update/hibernation/password fixes
- Hardware testing suite plus MemTest86+ on both editions
- Network toolkit, nmtui Wi-Fi, DNS fallback, firmware-failure diagnosis
- Job reports, phone dashboard, session transcripts, review bundles, stick → caddy collection
- `sysmedic-deploy` keeps both editions in step; docs on both drives
- Windows-safe USB presentation: a Windows-readable exFAT exchange partition (`SM_EXCHANGE`) on new sticks, Lite sticks and caddy builds, with the ISO/gap partitions hidden from Windows; read-only Windows evidence collector with consent prompt; encrypted (age) portable snapshots with provenance; `sysmedic-snapshot init/import/verify`; tests in `build/tests/test_exchange.py`. See [docs/EXCHANGE.md](docs/EXCHANGE.md)
- Reproducible builds from scratch (stock Ubuntu 24.04.5 ISO → stick or caddy): `build/bootstrap.sh`, [docs/BUILDING.md](docs/BUILDING.md)

## Next

1. **Real-hardware validation** of `sysmedic-win checkup` on real Windows 10/11 installs (event-log volume and timing, CBS archive sizes).
2. **Real-hardware validation** on more machines (Wi-Fi on kernel 7.0, Secure Boot, AI speed on real CPUs). The review bundles will show what breaks.
3. **Encryption of SysMedic's own storage:** the LUKS vault (`sysmedic-vault`, since 2026-10-12) now holds customer data on both editions, unlocked by passphrase at boot. Keep validating it on real hardware and bring anything still outside it inside (see [docs/SAFETY-AND-PRIVACY.md](docs/SAFETY-AND-PRIVACY.md)). This is separate from the snapshot encryption below.
4. **Opt-in, key-only SSH** for a remote colleague: session-scoped, shown on screen, audited.
5. **Offline accuracy:** give the offline model the findings as a numbered list it must cite, and prefer 7B where RAM allows.
6. **Leaner OpenCode prompt** for offline use, or a SysMedic agent profile with fewer tools.
7. **A passive network diagnosis** command (link → IP → gateway → DNS → internet, with a verdict).
8. **APFS read-write**, once a driver builds on current kernels.

Windows exchange follow-ups (after the priorities above; none of this blocks them):

9. **Real Windows validation** of the exchange partition and collector (Windows 10 and 11, several USB ports; procedure in [docs/HARDWARE-TESTING.md](docs/HARDWARE-TESTING.md)).
10. **Analysis from a snapshot:** `sysmedic-snapshot analyse` turning `raw/` into `findings/` and feeding the job report, kept separate from the evidence.
11. **Migration for existing drives:** a safe offline way to add the exchange partition to caddies already in use; `EXPORT/` writing (reports handed back); optional signed collectors.
12. **VNA hand-off:** a deliberate, offline "export to Virtual Network Admin" from an imported snapshot. Only after 10; no cloud dependency.

## Not planned

- Building a Windows BCD from Linux (use WinRE).
- Telemetry or call-home of any kind (the Windows collector included: it is offline and only runs when a person starts it).
- A Windows repair tool: the collector reads evidence and changes nothing.
- Repairs from the phone dashboard.
