# SysMedic capabilities

Everything SysMedic can do, by area. Commands run as root on SysMedic's console. Where a capability is edition-specific, it's marked **(caddy)** or **(stick)**; everything else is on both.

---

## 1. Boot and platform

- **Ubuntu 24.04 LTS, kernel 7.0 (HWE)** with full `linux-firmware`: current Wi-Fi (Intel, Realtek, MediaTek, Qualcomm/Atheros), Intel/AMD/NVIDIA graphics, NVMe, Intel VMD/RAID.
- **UEFI with Secure Boot on** (Canonical-signed shim, GRUB and kernel) and **legacy BIOS**.
- Wi-Fi drivers are kept out of the initramfs, so they load from the full firmware set (see [NETWORK](NETWORK.md)).
- **Boot menu:** SysMedic, verbose boot, safe graphics (`nomodeset`), **MemTest86+ 7.00** (UEFI: Secure Boot must be off; BIOS: always), boot from internal disk, UEFI firmware settings. **(caddy)** also keeps the older 6.8 kernel under *Advanced options* as a fallback.
- Two auto-login consoles: **tty1** runs the rescue flow, **tty2** is the engineer console. A UK keyboard layout is set.
- **Self-check:** the scan reports SysMedic's own USB link speed and warns at USB 2.0 ("power off, then use a USB 3 port/cable").
- **Edition and version** are shown in the boot banner, scan header, menu, job reports and review bundles (`/etc/sysmedic/{edition,version}`).

## 2. Triage scan (`sysmedic-scan`, runs at boot)

Read-only by design: filesystems are mounted `ro` (ext4 with `noload`, so even the journal isn't replayed), checks run in no-change mode, and RAID/LVM members are reported but never assembled. Results go to the session as `summary.txt` and `scan.json`, with a history of every re-scan.

| Area | What it checks |
|---|---|
| System | Make/model, CPU (AVX for the cloud AI), RAM, UEFI/BIOS, Secure Boot |
| SysMedic's drive | USB link speed (warns at USB 2.0) |
| Disk health | SMART/NVMe: overall health, reallocated/pending/uncorrectable sectors, media errors, wear %, NVMe critical warnings, power-on hours. A failing disk gets "image it first" with the `ddrescue` command |
| Filesystems | ext2/3/4 (state, error count, `e2fsck -n`), NTFS (dirty flag), FAT, exFAT; free space under 5% |
| Linux | OS name; `/etc/fstab` entries pointing at missing disks (critical unless `nofail`); kernels without an initramfs; missing `grub.cfg`; missing GRUB/shim on the EFI partition |
| Windows | Version (Windows 11 shown correctly); hibernated / Fast Startup; half-installed update (`pending.xml`); blue-screen crashes with decoded stop codes and the dominant pattern; disk, hardware and power-loss events (last 60 days); suspicious autostarts; WinRE disabled; missing boot manager or BCD |
| macOS | HFS+ volumes and macOS version |
| Encryption | BitLocker (with the exact unlock command) and LUKS volumes |
| Network | Adapters and drivers, internet reachability, **"internet works but DNS is broken"**, Wi-Fi adapters without a driver, **drivers that couldn't load their firmware** |
| Safety | Which customer disks are write-protected or unlocked |

Re-run any time: `sysmedic-scan` (or menu 4). The job report compares the first and last scan.

## 3. Safety layer

Details: [SAFETY-AND-PRIVACY](SAFETY-AND-PRIVACY.md)

- **`sysmedic-guard`:** every disk except SysMedic's own is set read-only in the kernel (block-layer `BLKROSET`) as it appears, including drives plugged in later. Writes, read-write mounts, `fsck` repairs and `mkfs` all fail.
- **`sysmedic-unlock /dev/X`** (console only, never the AI): asks for a reason and the typed device name, then backs up first (partition table; ext4 metadata via `e2image`; NTFS metadata via `ntfsclone`; small FAT partitions in full). Only that partition is unlocked. **`sysmedic-lock`** re-protects everything. **`sysmedic-guard status`** shows the state.
- **Audit trail:** every console command, every AI command (tagged), unlocks with reasons and backup paths, consent, refusals, BitLocker unlocks (key never recorded), repairs and notes go to the session's `audit.log`.
- **AI limits:** the AI can't unlock, can't run BitLocker or repair commands, and needs approval for anything that isn't a read-only diagnostic. Cloud use needs customer consent.

## 4. AI assistants

Details: [AI-ASSISTANTS](AI-ASSISTANTS.md)

- **Cloud: OpenCode with Big Pickle** (OpenCode Zen free tier, no login). It starts by explaining the scan and proposing a plan. Read-only diagnostics run without prompts, file reads outside SysMedic's folders ask first, and unlock/bypass commands are blocked. Full tool output is shown, not collapsed.
- **Offline: `sysmedic-ask`** (Ollama, `qwen2.5:7b` on 12 GB+ RAM, otherwise `qwen2.5:3b`). The short prompt is pre-loaded at boot, so the first answer takes about a minute on CPU. Read-only commands run straight away with **full output streamed live on the console**; others ask (Enter = yes). Commands the model writes in its text need an explicit `y`. There's a time limit per command, and Ctrl-C stops just the current command.
- Both know which edition they're on, the field lessons, and the tool list. They record limitations with `sysmedic-note --feedback`.

## 5. Windows (`sysmedic-win`, menu 6)

Details: [WINDOWS-AND-BITLOCKER](WINDOWS-AND-BITLOCKER.md)

- Read-only: `info`, `crashes`, `events`, `autoruns`, `malware` (ClamAV; signatures on the drive, updated when online).
- Deep troubleshooting (read-only): `evtx` (**every** event log: curated rules plus an error sweep, boot times, Security summary), `registry` (missing service/driver files, broken device filters, hijacks, protection/update policies, recent installs), `cbs` (CBS/CbsPersist, DISM, Windows Update and upgrade logs: failing updates, decoded HRESULTs, corruption, SFC, a verdict). `checkup` runs everything and saves `windows-checkup-*.md` in the session. `evtx`/`cbs` also take exported files.
- Engineer only: `bitlocker` (48-digit recovery key or password; read-only unless `--rw`), `fix-update`, `fix-hibernation`, `reset-password` (local accounts, `chntpw`).
- Also: chntpw, hivex tools, evtxexport, cabextract, ntfs-3g/ntfsfix, wimlib **(caddy)**, dislocker.

## 6. Hardware testing (`sysmedic-hwtest`, menu 16)

Details: [HARDWARE-TESTING](HARDWARE-TESTING.md)

`report` (temperatures, fans, throttling, battery wear, SMART, machine-check/ECC/PCIe errors) · `cpu` (stress-ng + temperatures) · `ram` (memtester; full test via MemTest86+ at boot) · `disk` (SMART self-test + read-only speed/latency) · `surface` (read-only badblocks) · `gpu` (glmark2) · `input` · `audio` · `battery` · `inventory`. Results go into the job report.

Tools: stress-ng, s-tui, stress, sysbench, memtester, MemTest86+, rasdaemon, edac-utils, lm-sensors, turbostat, cpupower, cpuid, msr-tools, fio, ioping, bonnie++, badblocks, hdparm, sdparm, smartctl, nvme, f3, sg3-utils, lsscsi, glmark2-es2-drm, mesa-utils, vulkan-tools, intel-gpu-tools, radeontop, nvtop, upower, acpi, evtest, libinput-tools, alsa-utils, v4l-utils, bluez, usbutils, pciutils, dmidecode, lshw, hwinfo, inxi, edid-decode, read-edid, fwupd, powertop, sysstat, iotop-c.

**(caddy)** also has the long burn-in suite in the advanced toolkit (menu 15).

## 7. Network

Details: [NETWORK](NETWORK.md)

- **Wi-Fi:** `wifi` / menu 2 runs NetworkManager's `nmtui` picker. Connections aren't saved on the drive.
- **Diagnosis:** ping, arping, tracepath, traceroute, mtr, dig, nslookup, whois, ip, ss, ethtool, iw, nmcli, wavemon, iperf3/iperf, speedtest-cli, curl, fping, hping3.
- **Capture:** tcpdump, tshark, termshark, ngrep, iftop, nload, bmon, nethogs, iptraf-ng.
- **LAN and services:** nmap, ncat, arp-scan, nbtscan, avahi-utils, smbclient, cifs-utils, nfs-common, snmp, lldpd, ndisc6, ipcalc, sipcalc, lftp, tnftp, telnet, tftp-hpa, socat, netcat, bridge-utils, vlan, hostapd, dnsmasq-base.
- **Serial and BMC:** minicom, picocom, ipmitool.
- **DNS fallback:** public resolvers are used alongside the site's DNS. A broken site DNS is reported as a finding.
- Services that would announce on a customer network (lldpd, hostapd, avahi, rpcbind) stay off until started deliberately.

## 8. Data recovery and disks

- Both: ddrescue, testdisk, photorec, sgdisk/gdisk, sfdisk, mdadm, lvm2, cryptsetup, e2fsprogs, ntfs-3g, exfatprogs, dosfstools, hfsprogs (`fsck.hfsplus`).
- **(caddy):** safecopy, fsarchiver, partclone (OS image capture/restore in the advanced toolkit), ext4magic, extundelete, foremost, scalpel, nwipe (certified wipe), btrfs-progs, xfsprogs, f2fs-tools, APFS read-only (`fsapfsmount`, `apfsck`), dislocker.
- Linux boot repair scripts (menu 5): GRUB, initramfs, fstab, oversized `/boot`.
- macOS (menu 7, and in the caddy's advanced toolkit): HFS+ read-write, APFS read-only, data recovery.

## 9. Malware and security

- ClamAV (Windows triage via `sysmedic-win malware`; `clamscan` directly). Signatures live on the drive and update when online.
- Autorun persistence analysis (Run keys, services, scheduled tasks, startup folders).
- **(caddy):** yara, chkrootkit, rkhunter (point them at a mounted Linux root).

## 10. Job workflow

- **Job report** (`sysmedic-report`, menu 13): a self-contained HTML report (print to PDF) plus text: summary, job and machine, fixed / still needs attention, work performed (from the audit trail), AI use and consent, hardware test results, backups, notes, signatures, and the full audit trail.
- **Notes:** `sysmedic-note "…"`; job details with `sysmedic-note --job customer=… job_ref=… engineer=… contact=… complaint=…`.
- **Phone dashboard** (`sysmedic-dash`, menu 14): QR code on tty2. Live status and findings, write protection, the job form, notes, and generating/downloading the report. Token-protected; **no repairs or unlocks**.
- **Session folder** per boot (`/mnt/persist/sessions/<time>-<model>/`): scans, audit log, job, report, backups, AI conversations.

## 11. Improving SysMedic

Details: [IMPROVING-SYSMEDIC](IMPROVING-SYSMEDIC.md)

- **Transcripts** of tty1/tty2 (output only, never keystrokes) and every AI conversation.
- **`claude-review.md`** per visit (also built at shutdown): feedback, findings before/after, audit trail, conversations, transcripts, and tools the AI wanted but didn't have.
- **`sysmedic-note --feedback "…"`** for things SysMedic should do better.
- **(caddy)** plugging the stick into a running caddy **collects the stick's sessions** automatically.

## 12. Command summary

| Command | What |
|---|---|
| `menu` | Rescue menu |
| `sysmedic-scan` | Re-run the triage scan |
| `sysmedic-ask` | Offline AI assistant |
| `opencode` | Cloud AI assistant |
| `sysmedic-guard status` · `sysmedic-unlock /dev/X` · `sysmedic-lock` | Write protection |
| `sysmedic-win …` | Windows toolkit |
| `sysmedic-hwtest …` | Hardware tests |
| `wifi` | Join Wi-Fi (nmtui) |
| `sysmedic-report` | Job report |
| `sysmedic-note "…"` / `--job` / `--feedback` | Notes |
| `sysmedic-dash` | Phone dashboard QR code |
| `sysmedic-transcript` | Bundle this visit for review |
| `sysmedic-collect` **(caddy)** | Collect sessions from a SysMedic stick |
| `sysmedic-help` | These docs, on the drive |
