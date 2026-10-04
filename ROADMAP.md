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

## Next

1. **Real-hardware validation** of `sysmedic-win checkup` on real Windows 10/11 installs (event-log volume and timing, CBS archive sizes).
2. **Real-hardware validation** on more machines (Wi-Fi on kernel 7.0, Secure Boot, AI speed on real CPUs). The review bundles will show what breaks.
3. **Encryption:** LUKS for the stick's persistence partition and the caddy's data, unlocked by passphrase at boot. Both drives hold customer data unencrypted today.
4. **Opt-in, key-only SSH** for a remote colleague: session-scoped, shown on screen, audited.
5. **Offline accuracy:** give the offline model the findings as a numbered list it must cite, and prefer 7B where RAM allows.
6. **Leaner OpenCode prompt** for offline use, or a SysMedic agent profile with fewer tools.
7. **A passive network diagnosis** command (link → IP → gateway → DNS → internet, with a verdict).
8. **APFS read-write**, once a driver builds on current kernels.
9. **Reproducible stick builds** from the stock Ubuntu ISO (today the build starts from the maintained `root/`).

## Not planned

- Building a Windows BCD from Linux (use WinRE).
- Telemetry or call-home of any kind.
- Repairs from the phone dashboard.
