# Safety and privacy

SysMedic works as root on other people's computers, with an AI assistant. This is how it keeps the customer's data safe, and what it stores.

## Write protection (`sysmedic-guard`)

- A udev rule makes **every disk except SysMedic's own read-only in the kernel** (`BLKROSET`) the moment it appears, including disks plugged in later. SysMedic's own disk is recognised by its labels (`SYSMEDIC_2404`, `FOG_AMB_PERSIST`) or as the disk the running system lives on.
- While a disk is locked, writes, read-write mounts, `fsck` repairs, `mkfs` and `dd` all fail ("Permission denied" or "read-only"), whoever runs them.
- The triage scan only reads: ext4 is mounted `ro,noload` (no journal replay), NTFS `ro`, checks run in no-change mode, and RAID/LVM are reported but never assembled. Tested: a writable test disk was byte-for-byte unchanged after a full boot, scan and AI session.

### Unlocking

`sysmedic-unlock /dev/X` (console 2, or menu 11):
1. **It refuses** if called by the AI (`SYSMEDIC_AI` set, or OpenCode/sysmedic-ask/Ollama as an ancestor process), or if not on a real console (a recorded console is accepted only after checking, via `/proc`, that its recorder sits on a VT).
2. It asks **why** (goes in the audit log) and for the **device name typed back**.
3. It **backs up first** into the session's `backups/`: the partition table (`sfdisk -d`), ext4 metadata (`e2image -Q`), NTFS metadata (`ntfsclone --metadata`), or a full zstd copy of FAT/small partitions.
4. It unlocks **that partition only**. Its siblings stay locked.

`sysmedic-lock` locks everything again. Kernel limitation: while a partition is unlocked, the whole-disk node (e.g. `/dev/nvme0n1`) is also writable, and the unlock message says so.

**Scope:** this stops mistakes and an over-eager AI. It's not a sandbox against a root process deliberately setting out to bypass it.

## The AI's limits

| | Offline (`sysmedic-ask`) | Cloud (OpenCode) |
|---|---|---|
| Read-only diagnostics | Run straight away, output shown in full | Allow-listed: run without asking |
| Anything else | Shown first (Enter = run, n = skip, e = edit) | Asks |
| Commands written in prose | Need an explicit `y` | n/a |
| Chains (`&&`, `\|\|`, `;`, `\|`) | Auto-run only if every part is read-only | Pattern rules |
| Unlock / blockdev / hdparm / BitLocker / repairs / chntpw / nwipe / mkfs | Refused by the tools themselves | Denied in config, and refused by the tools |
| Reading customer files | Allowed (stays on the machine) | Asks outside SysMedic's folders |

The AI is also instructed **never to reproduce credentials** it finds (passwords, hashes, security-question answers, keys, tokens, including remnants in deleted/slack space). It reports them as "found, redacted". It saves its written reports in the session folder, keeps customer identifiers to what a report needs, and flags company-managed machines (Entra ID/Intune/domain), where you need the organisation's authorisation.

The AI is instructed not to shut down or reboot the rescue machine, never to suggest moving SysMedic's drive while running, not to call a machine virtual without `systemd-detect-virt`, and to record its own mistakes with `sysmedic-note --feedback`.

## Customer consent and the cloud

- With internet, SysMedic asks **"Does the customer consent to cloud AI? [y/N]"**. Only `y` enables it, and the answer is recorded in the audit log and the job report.
- The cloud model sees the scan and the output of commands it runs. **Serial numbers are kept out of what the AI reads** (they go to a separate private file).
- No API keys or logins are stored on the drives; the free tier needs none.

## The audit trail

Each visit's `audit.log` records, with timestamps:
- every console command (tagged with the console)
- every AI command (`[ai:ask]` or `[ai:opencode]`)
- consent
- unlocks, with reason and backup path
- locks and refusals
- BitLocker unlocks (key **not** recorded)
- Windows repairs and malware scans
- notes, dashboard access, and report generation

## What's stored, and where

| Data | Location | Contains customer data? |
|---|---|---|
| Session folder (scans, audit, job, report, backups, AI conversations) | `/mnt/persist/sessions/<time>-<model>/` (caddy: `/srv/sysmedic/sessions/`) | Yes |
| Serial numbers | `/mnt/persist/private/` (root-only) | Yes |
| Console transcripts (output only) | `/mnt/persist/transcripts/` | Yes |
| Review bundles | `claude-review.md` in the session + `/mnt/persist/claude-review/` | Yes |
| Wi-Fi passwords, BitLocker keys | **Never stored** | — |
| Cloud AI history | Wiped at each boot; a copy of the visit's conversation is kept in the session | Yes |

**Encryption:** the stick's persistence partition and the caddy are **not encrypted**. A lost drive exposes the above. Treat the drives as customer-data media.

## Things that never happen by themselves

- No SSH server at boot.
- Services that would announce on a customer network (lldpd, hostapd, avahi, rpcbind) are masked.
- No telemetry and no "call home". Hardware-probe uploaders are deliberately not installed.
- The BitLocker web unlock (`sysmedic-win bitlocker-web`) runs only when the engineer starts it on a console: HTTPS, a secret link, read-only, and it stops by itself (unlock, 5 wrong keys, 15 minutes). The key is never stored or logged.
- Wi-Fi networks joined during a visit (and their passwords) live in RAM only and are forgotten at shutdown.
- The phone dashboard is view + notes only, token-protected, and plain HTTP on the local network (don't use it on untrusted networks).
