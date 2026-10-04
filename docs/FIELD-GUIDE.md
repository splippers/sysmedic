# Field guide: a visit with SysMedic

From boot to sign-off. On the drive: `sysmedic-help field`.

## 1. Before you boot

- **Power the machine off first.** Then plug SysMedic in. The caddy goes in a **USB 3 port** (often blue or marked SS) with a USB 3 cable. On a USB 2.0 port everything runs about 10× slower, and the boot scan will warn you.
- **Never unplug or move SysMedic while it's running.** On the caddy, the whole system runs from that drive.
- For network access, plug in Ethernet or turn on **USB tethering** on your phone, or join Wi-Fi on the first screen.
- Boot from USB: the boot-menu key is usually F12 (Dell, Lenovo), F9 (HP), Esc or F8 (ASUS), or hold Option (Mac).

## 2. The boot menu

| Entry | Use |
|---|---|
| SysMedic Rescue (default) | Normal start |
| verbose boot | See kernel messages if it hangs |
| safe graphics | Black or garbled screen (`nomodeset`) |
| Memory test (MemTest86+) | Full RAM test. On UEFI, turn Secure Boot off first |
| Boot from internal disk / UEFI Firmware Settings | Leave SysMedic |

**(caddy)** *Advanced options* also has the older 6.8 kernel, if a machine misbehaves on 7.0.

## 3. What happens at boot (console 1)

1. Console 1 (tty1) and console 2 (tty2) log in automatically. **Both are recorded** for later review (output only, never keystrokes).
2. **Network first.** If Ethernet or tethering is already online, this passes by itself. Otherwise it lists the Wi-Fi networks nearby: press **Enter** to pick one (password asked there; kept in memory only, forgotten at shutdown) or **s** to carry on offline. It continues offline by itself after 60 s.
3. The banner shows the **edition and version** and how SysMedic is connected, e.g. `caddy edition · v2026.10.04-…` · `Network: online via wlp0s20f3 (Wi-Fi "Office")`.
4. The **triage scan** runs (read-only, under a minute). Findings are ordered critical → warning → note → OK, each with a next step.
5. The **phone dashboard** address appears (QR code on console 2).
6. **Cloud AI consent:** if there's internet, you're asked whether the customer consents. Only **y** enables the cloud AI; anything else, or no answer within 60 s, means offline.
7. Press **Enter** to start the assistant, or **m** for the rescue menu.

Low RAM: the cloud AI needs 4 GB and an AVX-capable CPU, and the offline AI needs 6 GB. Below that you get the rescue menu instead.

## 4. The two consoles

- **Console 1 (`Alt+F1`): the assistant.** Ask it things like *"why won't this boot?"*, *"check the network"* or *"is the disk failing?"*. Read-only checks run straight away and show their full output; anything else shows you the command first (Enter = run, n = skip, e = edit).
- **Console 2 (`Alt+F2`): you.** Unlocks, BitLocker, repairs and notes happen here. Its banner lists:
  - the write-protection commands
  - **every BitLocker volume on the machine with the exact command to type**, and the recovery-key format
  - `sysmedic-help`, and the dashboard QR code

## 5. The rescue menu (`menu`)

| # | |
|---|---|
| 1 | OpenCode AI assistant |
| 2 | **Wi-Fi connect (nmtui)** |
| 3 | Save session log to USB |
| 4 | Triage scan (re-run) |
| 5 | Fix Linux boot: GRUB, initramfs, fstab, oversized /boot |
| 6 | **Windows tools**: info, crashes, events, autoruns, malware, BitLocker, update rollback, hibernation, password |
| 7 | macOS (HFS+/APFS) |
| 8 | Backup data |
| 9 | Shell |
| 11 / 12 | **Unlock a partition / write-protect all again** |
| 13 | **Job report** |
| 14 | **Phone dashboard** (QR code) |
| 15 | Advanced toolkit **(caddy)**: stress/burn-in, OS imaging, macOS, extra Windows repairs. On the stick it tells you to use the caddy |
| 16 | **Hardware tests** |
| 10 / 0 | Reboot / shut down |

## 6. A typical repair

1. **Read the scan.** If a disk is failing, **image it first**: `ddrescue /dev/X /path/on/external/disk.img /path/disk.map`.
2. **Diagnose.** Use the assistant, `sysmedic-win …` for Windows, and `sysmedic-hwtest report` for hardware.
3. **Unlock only what you'll change** (console 2):
   ```
   sysmedic-unlock /dev/nvme0n1p3      # asks why, then the device name; backs up first
   ```
4. **Repair.** For example `sysmedic-win fix-hibernation /dev/nvme0n1p3`, then `sysmedic-win fix-update /dev/nvme0n1p3`, or fsck, or GRUB.
5. **Lock again:** `sysmedic-lock`.
6. **Confirm:** `sysmedic-scan`. The fixed findings should be gone.
7. **Notes and job details:**
   ```
   sysmedic-note --job customer="Acme Ltd" job_ref=J-1042 engineer=Sam complaint="Won't finish updating"
   sysmedic-note "Advised RAM check: two WHEA crashes this week"
   ```
8. **Job report:** menu 13 (or `sysmedic-report`). It re-scans, then writes `report.html` and `report.txt`, to open on the phone dashboard or print to PDF.
9. **Shut down cleanly** (menu 0). The visit is bundled into `claude-review.md`.

## 7. BitLocker

On console 2 the banner shows, for example:
```
sysmedic-win bitlocker /dev/nvme0n1p3      (237G, Basic data partition)
```
Type that line, then the **48-digit recovery key** (8 groups of 6 digits; dashes and spaces optional) at the hidden prompt. It's never shown, stored, logged or recorded. The owner finds it at **aka.ms/myrecoverykey** or from their IT admin. The volume opens **read-only**; for repairs, run `sysmedic-unlock` on the partition first and add `--rw`. More: [WINDOWS-AND-BITLOCKER](WINDOWS-AND-BITLOCKER.md).

**Key with someone else?** Run `sysmedic-win bitlocker-web` (menu 6 → w). The customer or their IT admin scans the QR code with a phone or laptop on the same network and types the key there. It's HTTPS with a secret link, unlocks read-only, and stops by itself after unlocking, 5 wrong keys or 15 minutes.

## 8. Wi-Fi

The first screen at boot offers Wi-Fi. Later, `wifi` (menu 2) opens NetworkManager's picker: choose the network, type the password, press Esc to leave. Networks and passwords are kept in memory only and forgotten at shutdown; nothing is saved on the drive. WPS isn't supported. If no Wi-Fi adapter appears, the scan says why (usually a missing driver or firmware); use Ethernet or phone tethering.

## 9. Phone dashboard

Scan the QR code on console 2 (or run `sysmedic-dash`). The phone must be on the same network (the same Wi-Fi, or USB tethering). It shows live findings, which disks are locked, the job form, notes, and the report. It can't repair or unlock anything. Anyone with the link can see the visit's findings, so don't share it.

## 10. Troubleshooting

| Symptom | Do this |
|---|---|
| Everything slow; scan warns "USB 2.0" | Power off, move SysMedic to a USB 3 port/cable |
| Black screen after boot | Boot menu → *safe graphics* |
| No Wi-Fi adapter | Check the scan for "couldn't load its firmware"; use Ethernet/tethering; **(caddy)** try the 6.8 kernel under Advanced options |
| Cloud AI won't start / asks to "connect to the console" | Check internet; the free tier needs no login. Use the offline assistant meanwhile |
| Offline AI slow | Normal on CPU: about a minute to the first answer, faster afterwards |
| "Permission denied" or "read-only" writing to a disk | Working as intended: `sysmedic-unlock /dev/X` on console 2 |
| Windows volume only mounts read-only | Windows is hibernated: `sysmedic-win fix-hibernation`, or shut Windows down fully |
| Something SysMedic should do better | `sysmedic-note --feedback "…"` |
