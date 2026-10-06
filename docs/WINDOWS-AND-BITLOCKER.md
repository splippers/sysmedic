# Windows and BitLocker (`sysmedic-win`, menu 6)

Works on an offline Windows installation from SysMedic. Without a partition argument, every Windows installation found is used.

## Read-only (the AI may run these)

| Command | Shows |
|---|---|
| `sysmedic-win` | Windows installations and BitLocker volumes (locked or unlocked) |
| `sysmedic-win info [PART]` | Version (Windows 11 shown correctly), edition, computer name, last clean shutdown, **Fast Startup / hibernated now**, pending at next boot (half-installed update, servicing reboot, file replacements), WinRE available/disabled, user profiles with last use, free space |
| `sysmedic-win crashes [PART]` | Every minidump with its **stop code decoded** into the usual cause, plus the pattern (e.g. "2 of 3 crashes are 0x124: hardware") |
| `sysmedic-win events [PART]` | The System event log grouped: unexpected restarts, blue screens, disk errors (7/51/153, NTFS 55/98), WHEA hardware errors, failed updates, service failures, **new services installed** (persistence) |
| `sysmedic-win autoruns [PART]` | Run/RunOnce (machine and per user), auto-start services outside Windows, scheduled tasks, startup folders. **Suspicious** entries are flagged with the reason: a Windows system name outside System32, running from AppData/ProgramData/Temp, encoded PowerShell, remote scripts |
| `sysmedic-win malware [PART] [--full]` | ClamAV on autostart files and user/program-data folders (`--full`: the whole volume). Signatures are on the drive and updated when online |

The boot scan includes the important parts of all of these automatically.

## Deep troubleshooting: event logs, registry, servicing

For "what's wrong with this Windows", start with **`sysmedic-win checkup`** (menu 6 → c). It runs everything below plus `info`, `crashes` and `autoruns`, prints it, and saves it as `windows-checkup-<partition>.md` in the session folder. From there it goes into the job report and the review bundle. All of it is read-only.

| Command | Reads | Finds |
|---|---|---|
| `sysmedic-win evtx [PART\|FILES] [--days N] [--curated]` | **Every** `.evtx` in `winevt\Logs` (default: last 30 days) | Curated rules for System, Application, Security, Setup and the operational logs that explain problems: Windows Update, device/driver install (Kernel-PnP), boot/shutdown performance, Defender, Code Integrity, Task Scheduler, Wi-Fi, Remote Desktop, PowerShell. Then an **error sweep of every other log**. Output is grouped by meaning with counts, first/last time and example details, plus Windows' own boot-time measurements. `--curated` skips the sweep (faster) |
| `sysmedic-win registry [PART] [--days N]` | SYSTEM, SOFTWARE, each user's NTUSER.DAT, the hosts file | Services and drivers set to start whose file is **missing** (a missing boot driver means INACCESSIBLE_BOOT_DEVICE), **device-class filter drivers that aren't installed** (no keyboard, disk or DVD after uninstalling software), core services disabled (Windows Update, BITS, Defender, firewall…), Winlogon Shell/Userinit and IFEO hijacks (including the `sethc`/`utilman` logon backdoor), AppInit DLLs, non-standard LSA packages, WDigest clear-text logons, Defender off by policy and broad exclusions, updates off or pointed at WSUS, UAC off, servicing reboots/exclusive sessions pending, crash dumps off, no paging file, Intel RST boot mode, per-user proxies and lockdown policies, hosts redirects. Also **what changed recently** (software installed, third-party services/drivers, Run keys) to line up with when the trouble started |
| `sysmedic-win cbs [PART\|CBS.log\|FOLDER] [--days N]` | `Logs\CBS\CBS.log` + the newest archived `CbsPersist_*.log/.cab`, `Logs\DISM\dism.log`, `SoftwareDistribution\ReportingEvents.log`, Panther `setuperr.log` (feature upgrades) | A **verdict with next steps**, failing updates (KB, how many times, error code), servicing errors grouped by HRESULT **with their meaning** (0x800f081f, 0x800f0831, 0x80073712, 0x800f0922, 0x80070643, 0xC1900101 …), component-store corruption lines, SFC results (repaired / couldn't repair) and DISM's detected/repaired counts, failed servicing sessions |

| `sysmedic-win etl [PART\|FILES\|FOLDER] [--days N]` | ETW traces (`.etl`) under `Windows\Logs`, `System32\LogFiles`, `SoftwareDistribution`, `Panther` (default: last 7 days) | Failure codes from Windows Update, waasmedic, SIH, NetSetup and other components, **with timestamps** (e.g. a network outage window) and meanings, plus per-file decode coverage. Uses the vendored, pure-Python etl-parser (Apache-2.0); traces from providers without embedded metadata can't be decoded and are listed as such |

`evtx` reads **every** event log (it says how many were empty or unreadable), names the **device** behind each storage error (vendor, model, last 4 digits of the serial: so a USB stick isn't mistaken for the internal disk), and groups code-integrity events **by file**, labelling known security-product components (e.g. FortiClient's AMSI DLL) as usually benign.

### Which Windows logs SysMedic reads

| Format | Reader | Status |
|---|---|---|
| Event logs `.evtx` | `sysmedic-win evtx` (evtxexport) | Full |
| ETW traces `.etl` | `sysmedic-win etl` (etl-parser) | Most; providers without embedded metadata are listed as undecodable |
| Text logs (CBS, DISM, Panther, ReportingEvents) | `sysmedic-win cbs` | Full |
| Registry hives | `sysmedic-win registry` (hivex); SAM/SECURITY deliberately never read | Full |
| ESE databases `.edb` (Windows Update DataStore, search index) | `esedbexport`, `esedbinfo` (libesedb-utils) | Tools available, no SysMedic report yet |
| Prefetch `.pf` | `sccainfo` (libscca-utils) | Tools available, no SysMedic report yet |
| Classic `.evt`, shortcuts `.lnk`, raw registry | libevt-utils, liblnk-utils, libregf-utils | Tools available |
| Crash dumps `.dmp` | `sysmedic-win crashes` (stop code from the header) | Partial: no full dump analysis |
| Perfmon `.blg`, WMI repository | — | **Unsupported**: no Linux reader exists |

`evtx`, `etl` and `cbs` also take files: `.evtx` files or a folder of them, or a `CBS.log`/`dism.log`. That covers logs exported from a machine that's still running, or from a backup.

**Privacy:** event fields and registry values whose names suggest secrets are dropped. SAM and SECURITY are never read. For the Security log, only who/where/what is shown (account names, logon type, source address), never anything credential-like.

**Reading the results together:** a failing update (`cbs`), corruption lines (`cbs`) and disk errors (`evtx`) together point at the disk, not Windows: check SMART before repairing Windows. Line the registry's recent changes up with the date the event errors began.

**What SysMedic can't do from Linux:** run DISM/SFC itself. The `cbs` verdict gives the commands for Windows or WinRE: `DISM /Online /Cleanup-Image /RestoreHealth` with a source (`/Source:wim:X:\sources\install.wim:1 /LimitAccess`) when 0x800f081f appears; `sfc /scannow /offbootdir=C:\ /offwindir=C:\Windows` from WinRE; and an in-place repair upgrade as the last step before a reinstall.

## Engineer only (console; refused for the AI)

| Command | Does |
|---|---|
| `sysmedic-win bitlocker DEV [--rw]` | Unlock BitLocker with the recovery key or user password |
| `sysmedic-win fix-update PART` | Roll back a half-installed update: renames `WinSxS\pending.xml` (copy kept in backups). The official route, if WinRE works, is `dism /image:C:\ /cleanup-image /revertpendingactions` |
| `sysmedic-win fix-hibernation PART` | Discard hibernation / Fast Startup state so the volume can be written. Loses unsaved open work, not files. Better, if Windows boots: Shift + Shut down |
| `sysmedic-win reset-password PART` | Blank a **local** account password (`chntpw`; SAM backed up first). Microsoft accounts: account.live.com/password/reset. Only with the owner's authorisation |

All repairs need the partition unlocked first (`sysmedic-unlock`), and they say so if you forget. A hibernated volume silently mounts read-only under ntfs-3g; SysMedic detects this and tells you to run `fix-hibernation` first.

## BitLocker from a phone or laptop (`sysmedic-win bitlocker-web`, menu 6 → w, or the phone dashboard)

**From the phone dashboard (one QR code for everything):** when the machine has BitLocker volumes, the dashboard shows a **BitLocker** card with each volume locked or unlocked and an **Unlock from this phone** button. It starts the encrypted unlock page and opens it on the phone; the key is typed there, never on the dashboard (which is plain HTTP). The AI can't use this: it's blocked from the dashboard's secret and its BitLocker endpoint.

**From the console:**

For when the recovery key is with someone else (the customer, their IT admin) or on your phone. You start it on the console; it shows a QR code and a link. Whoever has the key opens it on a phone or laptop **on the same network**, picks the drive (its **Key ID** is shown, to match the right key at aka.ms/myrecoverykey) and types the key.

- **HTTPS** with a certificate made for this run, so the key never crosses the network in clear text. The browser warns that it's self-signed; the console shows the certificate's fingerprint to compare.
- A **secret link** (in the QR code); any other address gets "not found".
- **Read-only** unlock only. For repairs, use the console route below.
- Stops by itself after unlocking, after **5 wrong keys**, after 30 bad requests, or after **15 minutes**; Ctrl-C stops it.
- The key goes straight to cryptsetup. It's never stored, logged or shown, and requests aren't logged. The audit trail records start, each attempt's result and the requesting address.
- Engineer-only, like every unlock: the AI can't start it.
- Same network only. It doesn't open anything to the internet.

## BitLocker step by step

1. Console 2 (`Alt+F2`). The banner lists the BitLocker volumes and the exact line, e.g.
   `sysmedic-win bitlocker /dev/nvme0n1p3`
2. Type it. At the hidden **Key:** prompt, type the **48-digit recovery key**: 8 groups of 6 digits, e.g. `123456-234567-345678-456789-567890-678901-789012-890123`. Dashes and spaces are optional. A BitLocker user password also works.
3. The key comes from the owner: **aka.ms/myrecoverykey** (Microsoft account), Entra ID / Active Directory, or a printout. It's used once and **never shown, stored, logged or recorded** (the console transcript records output only).
4. Result: `/dev/mapper/bitlocker-<partition>`, **read-only**, with files at `/run/sysmedic/win/bitlocker-<partition>`. Then run `sysmedic-win info /dev/mapper/bitlocker-…`, or copy data to `/mnt/persist/backups` or an external disk.
5. For repairs: `sysmedic-unlock` the partition, close the read-only mapping (`cryptsetup close bitlocker-<partition>`), then `sysmedic-win bitlocker DEV --rw`.
6. Close when done: `cryptsetup close bitlocker-<partition>`.

Unlocking uses `cryptsetup`'s BitLocker support (dislocker is also installed). Tested against cryptsetup's real BitLocker test volumes: decryption matches their checksums.

## Not handled from Linux

- **Building a BCD** from scratch: use WinRE (`bcdboot C:\Windows /s S: /f UEFI`). SysMedic reports whether WinRE is available.
- Microsoft-account passwords, TPM-only BitLocker without a key, and Windows-internal repairs (`sfc`, `DISM`, `chkdsk /f`): use WinRE or install media.
