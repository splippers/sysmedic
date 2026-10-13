# Safety and privacy

SysMedic works as root on other people's computers, with an AI assistant. This is how it keeps the customer's data safe, and what it stores.

## Write protection (`sysmedic-guard`)

- A udev rule makes **every disk except SysMedic's own read-only in the kernel** (`BLKROSET`) the moment it appears, including disks plugged in later. SysMedic's own disk is recognised by its labels (`SYSMEDIC_2404`, `FOG_AMB_PERSIST`) or as the disk the running system lives on.
- While a disk is locked, writes, read-write mounts, `fsck` repairs, `mkfs` and `dd` all fail ("Permission denied" or "read-only"), whoever runs them.
- The triage scan only reads: ext4 is mounted `ro,noload` (no journal replay), NTFS `ro`, checks run in no-change mode, and RAID/LVM are reported but never assembled. Tested: a writable test disk was byte-for-byte unchanged after a full boot, scan and AI session.

### Unlocking

`sysmedic-unlock /dev/X` (console 2, or menu 8):
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
| Reboot / power off / suspend the rescue machine, `dislocker`, `pip install`, the SAM/SECURITY hives | Refused outright (not offered for approval) | Denied in config |
| Write-mode disk tests and repairs (`badblocks -w/-n`, fsck without `-n`, mkfs, `dd` to a disk, partitioning, secure erase) | Refused outright | Denied in config |
| Downloading and running code (`git clone`, pip, wheels/scripts from PyPI or GitHub) | Refused outright | Denied in config |
| Reading customer files | Allowed (stays on the machine) | Asks outside SysMedic's folders |

The AI is also instructed **never to reproduce credentials** it finds (passwords, hashes, security-question answers, keys, tokens, including remnants in deleted/slack space). It reports them as "found, redacted". It saves its written reports in the session folder, keeps customer identifiers to what a report needs, and flags company-managed machines (Entra ID/Intune/domain), where you need the organisation's authorisation.

The AI is instructed not to shut down or reboot the rescue machine, never to suggest moving SysMedic's drive while running, not to call a machine virtual without `systemd-detect-virt`, and to record its own mistakes with `sysmedic-note --feedback`.

## What the cloud AI sees (`sysmedic-redact`)

**Why:** OpenCode Zen's free models (Big Pickle among them) state that data collected during the free period may be used to improve the model. So nothing identifying should reach them, and a model that never trains on data is the better choice when there's a paid key.

- **Cleaned on the laptop first.** Everything a cloud-AI command prints passes through `sysmedic-redact` before the cloud sees it. Identities become placeholders that keep their meaning, the same all visit: `USER_1`, `OWNER_NAME`, `PC_NAME`, `COMPANY_NAME`, `AD_DOMAIN`, `DOMAIN_SID`, `WDS_SERVER`, `SCCM_SERVER`, `WSUS_SERVER`, `DC_SERVER`, `PROXY_SERVER`, `FILE_SERVER_1`, `PRINT_SERVER_1`, `INTUNE_TENANT_ID`, `INTUNE_DEVICE_ID`, `INTUNE_ENROLLMENT_ID`, `EMAIL_1`, `PHONE_1`, `WIFI_1`, `MAC_1`, `PUBLIC_IP_1`, `SERIAL`, `PRODUCT_KEY`, `RECOVERY_KEY`, and `FILE_1` for the customer's own files (Documents, Desktop, Downloads, Pictures, OneDrive…). Private network addresses are kept: they identify no one and network diagnosis needs them.
- **Learned locally:** the names to look for come from the offline Windows registry (computer name, owner, organisation, profiles, domain and its short name, domain controller, Windows Update server, Intune/Entra enrolment, proxy), server names in Windows' hosts file (`dc1` → `DC_SERVER`), the customer's Linux home folders and the scan. It learns again within two minutes of a disk appearing or a BitLocker volume being unlocked. A learned name is caught however it's written: any capitals, inside a longer host name (`setup.<domain>` → `SERVER_1.AD_DOMAIN`), or with escaped dots in a search pattern. The mapping stays in memory on the laptop (`/run/sysmedic/redact.json`, root only). The engineer can see it: `sysmedic-redact --show`; the AI can't.
- **The customer's own folders are closed to the AI** (`C:\Users`, `/home`) until the engineer records the customer's explicit agreement: `sysmedic-consent users` (typed YES at the laptop, logged in the audit trail and the job notes; `sysmedic-consent revoke users` withdraws it). The AI can't record or fake it.
- **Every tool is cleaned, not just the shell:** a SysMedic plugin inside OpenCode passes each tool's result (reading a file, running a command) through the same cleaner before it's sent, and the file tools obey the same user-folder rule. OpenCode only logs a warning when it can't load a plugin, so the cloud AI doesn't start unless the plugin is present and in the current format (`sysmedic-ai-repair --check` shows it). Broad search tools (grep, glob, list) and web search are off; fetching a web page needs the engineer's approval. (OpenCode's own read tool has to stay: Zen's free tier refuses requests without it.)
- **Review bundles** (`claude-review.md`) are cleaned the same way.
- **Limits, honestly:** the cleaner replaces what it knows or can recognise. A name it has never seen, inside free text (a document title in an event log, a person's name in a file), can get through. Once the customer has agreed to their folders being read, a bare file name in a folder listing can't always be recognised as personal. The offline assistant (Qwen) keeps everything on the laptop: use it when that matters.

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
| Session folder (scans, audit, job, report, AI conversations) | `/mnt/persist/sessions/<time>-<model>/` | Yes: **in the vault** |
| Backups of customer files | `/mnt/persist/backups/` | Yes: **in the vault** |
| Serial numbers | `/mnt/persist/private/` (root-only) | Yes: **in the vault** |
| Console transcripts (output only) | recorded in memory, saved to `/mnt/persist/transcripts/` | Yes: **in the vault** |
| Review bundles | `claude-review.md` in the session + `/mnt/persist/claude-review/` | Yes: **in the vault** |
| The AI assistant's records (its conversations, the output of each command it ran, the engineer's prompts) | `/root/.local/share/opencode`, `/root/.local/state/opencode` | Yes: **in the vault** (`ai-data/`, `ai-state/`); its settings stay outside |
| SysMedic, offline AI models, virus signatures, `logs/` | SysMedic's drive, outside the vault | No |
| Wi-Fi networks you chose to remember (with passwords) | `networks/` in the vault | Yes: **in the vault**, only when you answer y |
| Other Wi-Fi passwords, BitLocker keys | **Never stored** | — |
| Cloud AI history | Wiped at each boot; a copy of the visit's conversation is kept in the session | Yes |

## The encrypted vault (`sysmedic-vault`)

Everything above marked "in the vault" lives in an encrypted LUKS2 container on SysMedic's own drive (`/mnt/persist/vault.luks`; Argon2id; on the caddy it's in `/srv/sysmedic`). A lost drive gives away nothing without the passphrase.

- **One passphrase per drive,** typed on the first screen at boot. Hidden as you type; never logged, recorded or shown to the AI (both assistants are refused `sysmedic-vault`).
- **A recovery key** (8 groups of 6 digits) is made at setup and shown **once**, on a private console that isn't recorded. Write it down and keep it away from the drive. It opens the vault in place of the passphrase.
- **Not unlocked** (Enter at the prompt): SysMedic works as usual, but this visit is kept **in memory** and lost at shutdown. Nothing is ever written unencrypted. Unlock later with `sysmedic-vault unlock` (Alt+F2, or menu **V**): the visit so far moves into the vault.
- **While open,** console transcripts are saved every 30 s and the review bundle every 5 minutes, so a laptop that dies mid-job loses seconds, not the visit's record.
- **Forgotten passphrase *and* recovery key:** after three wrong tries the unlock screen offers **r = erase it and start again**, or run `sysmedic-vault reset`. Typing `ERASE` destroys the vault's keys, so everything in it is gone for good, then a new vault is set up.
- **Change the passphrase:** `sysmedic-vault passphrase`, with the current one or the recovery key (the recovery key keeps working).
- **First setup moves existing data in** (sessions, backups, serials, transcripts and bundles saved before encryption), then deletes the unencrypted copies and trims the drive. Flash memory can keep fragments of deleted data until they're overwritten, so a drive that held customer data before encryption should still be treated with care.
- **Deploys** back the vault up as the encrypted file: the build PC never holds a readable copy. To read a drive's vault on the build PC: `sudo sysmedic-vault mount FILE DIR` (read-only), then `sysmedic-vault umount DIR`.
- **The caddy collecting a stick's data** copies only into its own vault (unlocked), and asks for the stick's passphrase on Alt+F2: `sysmedic-collect`.

## Things that never happen by themselves

- No SSH server at boot.
- Services that would announce on a customer network (lldpd, hostapd, avahi, rpcbind) are masked.
- No telemetry and no "call home". Hardware-probe uploaders are deliberately not installed.
- The BitLocker web unlock (`sysmedic-win bitlocker-web`) runs only when the engineer starts it on a console: HTTPS, a secret link, read-only, and it stops by itself (unlock, 5 wrong keys, 15 minutes). The key is never stored or logged.
- Wi-Fi networks joined during a visit (and their passwords) live in RAM and are forgotten at shutdown, unless the engineer answers **y** to "Remember Wi-Fi … on this drive?": then they're saved in the encrypted vault only (never outside it, never with the vault locked). The AI is refused NetworkManager's files and the vault, and Wi-Fi passwords in command output are cleaned to `WIFI_PASSWORD`.
- The phone dashboard is view + notes only, token-protected, and plain HTTP on the local network (don't use it on untrusted networks).
