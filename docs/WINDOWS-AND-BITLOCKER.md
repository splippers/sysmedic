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

## Engineer only (console; refused for the AI)

| Command | Does |
|---|---|
| `sysmedic-win bitlocker DEV [--rw]` | Unlock BitLocker with the recovery key or user password |
| `sysmedic-win fix-update PART` | Roll back a half-installed update: renames `WinSxS\pending.xml` (copy kept in backups). The official route, if WinRE works, is `dism /image:C:\ /cleanup-image /revertpendingactions` |
| `sysmedic-win fix-hibernation PART` | Discard hibernation / Fast Startup state so the volume can be written. Loses unsaved open work, not files. Better, if Windows boots: Shift + Shut down |
| `sysmedic-win reset-password PART` | Blank a **local** account password (`chntpw`; SAM backed up first). Microsoft accounts: account.live.com/password/reset. Only with the owner's authorisation |

All repairs need the partition unlocked first (`sysmedic-unlock`), and they say so if you forget. A hibernated volume silently mounts read-only under ntfs-3g; SysMedic detects this and tells you to run `fix-hibernation` first.

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
