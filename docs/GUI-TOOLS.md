# A graphical front end for every tool

Many people who use SysMedic are only comfortable in a **WIMP** environment (windows, icons, menus, pointer). The goal is that every console utility on the drive has a window to click, collected in **desktop folders**, so nobody has to type a command. Everything here is open source.

Status: **research and plan** (2026-10-18). Nothing below is installed yet except what the caddy desktop already has (labwc, waybar, fuzzel, Thunar, GNOME Disks, Mousepad, the Control Centre window). Package availability was checked against the Ubuntu 24.04 (noble) `main` + `universe` indexes; sizes are the packages' own installed size, before dependencies.

## Three tiers

| Tier | Meaning | How |
|---|---|---|
| **A** | A mature open-source GUI exists in Ubuntu 24.04 | Install it, add a launcher in a desktop folder |
| **B** | No suitable GUI exists | Build one: **SysMedic Forms** (below), a small GTK window generated from a spec file for each tool |
| **C** | Not a tool a person runs (library, daemon, driver, boot firmware) | No front end; shown, where useful, inside another tool |

### SysMedic Forms (the Tier B engine)

One small Python/GTK program (`python3-gi` is already on the drive) that reads a declarative spec per tool: a title, a plain-English description, the fields to show (disk picker, file picker, drop-down, tick box, number), how they become a command line, whether the tool is **read-only / changes things / destroys data**, and what to show while it runs. It gives every Tier B tool the same window: pickers for disks and files that list real devices by model and size, a Run button, a live output pane with a progress bar where the tool prints one, Stop, "Save the output to the job report", and for anything that writes a plain-English confirmation naming the disk. A spec is about 20 lines, so adding a tool is cheap and consistent, and the AI can write specs too. It also gives the approvals the AI asks for (`sysmedic-confirm`, `sysmedic-consent`) a proper dialog.

## The desktop folders

Folders on the desktop (a file-manager desktop such as `pcmanfm --desktop`, which draws icons and folders; labwc itself doesn't), each a real directory of `.desktop` launchers so they also appear in the launcher (fuzzel) and the panel:

1. **Start here**: Control Centre (scan, tests, report), AI assistant, Help
2. **Disks and files**: partitions, health, space, files, hex, archives
3. **Recover and clone**: undelete, carve, imaging, backup, secure erase
4. **Windows**: check-up, BitLocker, accounts, event logs, registry, updates
5. **Network and Wi-Fi**: connect, scan, capture, speed, hotspot, remote
6. **Hardware**: information, sensors, firmware, USB, audio, camera, battery
7. **Stress and benchmarks**: CPU, memory, disk, GPU, network
8. **Security**: malware, rootkits, signatures
9. **Hospital and AI**: ask for help, swarm, offline AI
10. **Settings**: vault, access code, hotspot password, clock, updates

## Part 1: SysMedic's own tools

| Tool | Front end | Tier | Folder |
|---|---|---|---|
| `sysmedic-scan` (triage scan) | Control Centre scan page (exists) | A* | Start here |
| `sysmedic-tests`, `sysmedic-hwtest` | Control Centre tests page (exists); a Forms picker for the console menu | A* | Stress and benchmarks |
| `sysmedic-win` (check-up, BitLocker, fixes) | Control Centre Windows page (exists) | A* | Windows |
| `sysmedic-report`, `sysmedic-note`, `sysmedic-transcript` | Control Centre notes and report (exists) | A* | Start here |
| `sysmedic-dash` | It is the Control Centre | A* | Start here |
| `sysmedic-du` (what fills each disk) | **Baobab** (sunburst), or QDirStat (treemap, can clean up) | A | Disks and files |
| `sysmedic-raid` | GNOME Disks (shows and assembles md RAID) plus a Forms wrapper for assemble/stop | A+B | Disks and files |
| `sysmedic-ask`, `sysmedic-ai-session`, `sysmedic-ai-launch`, `sysmedic-ai-remote`, `sysmedic-ai-repair`, `sysmedic-ai-device` | The AI window (exists, in a terminal): move into a GTK chat window with the same backend; repair/device as Forms | B | Hospital and AI |
| `sysmedic-hospital` (`join`, `pair`, `send`, `read`) | Forms: a PIN box and an Ask Claude window | B | Hospital and AI |
| `sysmedic-redact` | Forms: pick a file, see the cleaned copy side by side | B | Hospital and AI |
| `sysmedic-connect`, `wifi` | **nm-applet / nm-connection-editor** (`network-manager-gnome`) | A | Network and Wi-Fi |
| `sysmedic-hotspot` (on, off, plan, guide, setup, show) | Forms: a hotspot window with the radio plan, Start, Start with internet, Stop, and a QR code for the phone | B | Network and Wi-Fi |
| `sysmedic-clock` | Forms: three clocks and a Fix button | B | Settings |
| `sysmedic-vault`, `sysmedic-consent`, `sysmedic-guard`, `sysmedic-confirm`, `sysmedic-remote-ai` | Forms: vault unlock and setup, access code, saved networks, consents | B | Settings |
| `sysmedic-update`, `sysmedic-gfx`, `sysmedic-help`, `ambulance`, `mount-persist`, `start-ollama` | Forms (update, graphics mode), help as HTML in the Control Centre; the rest are plumbing (C) | B / C | Settings, Start here |

\* already a GUI: the Control Centre is the phone dashboard in a window.

## Part 2: Disks, files and recovery

| CLI | GUI front end (Ubuntu 24.04 package) | Tier | Folder |
|---|---|---|---|
| `smartctl` (smartmontools), `nvme-cli` | **GSmartControl** (`gsmartcontrol`, 1 MB); GNOME Disks also shows SMART and NVMe health | A | Disks and files |
| `parted`, `fdisk`, `mkfs`, `e2fsprogs`, `exfatprogs`, `ntfs-3g`, `hfsprogs` | **GParted** (`gparted`, 1 MB) for partitions; GNOME Disks (installed) | A | Disks and files |
| `hdparm`, `sdparm`, `sg3-utils`, `lsscsi` | GNOME Disks (drive settings, power, write cache) for the common cases; Forms for the rest | A+B | Disks and files |
| `ncdu`, `du` | **Baobab**, **QDirStat** (`qdirstat`), **Filelight** | A | Disks and files |
| `mc`, `tree`, `lsof`, `psmisc`, `pv`, `jq` | **Thunar** (installed) for files; `lsof`/`fuser` as a Forms "What is using this disk?"; the rest are helpers (C) | A+B | Disks and files |
| `p7zip-full`, `zstd`, `lz4`, `cabextract`, `wimtools` | **Xarchiver** or **File Roller**; Thunar archive plugin. `wimtools` (WIM images) as Forms | A+B | Disks and files |
| `rsync`, `rclone`, `sshfs`, `lftp`, `tnftp`, `smbclient`, `cifs-utils`, `nfs-common` | **Thunar + gvfs** (`gvfs-backends`) for SMB, SFTP, FTP; **Rclone Browser** (`rclone-browser`); **FileZilla** (`filezilla`, 6 MB); a Forms "Copy a folder" for rsync | A+B | Disks and files |
| hex editing of disks and files | **GHex** (`ghex`), **Okteta**, **wxHexEditor** (`wxhexeditor`, made for whole disks) | A | Disks and files |
| `testdisk`, `photorec` | **No Qt/GTK build in noble** (`qphotorec` isn't packaged). Forms wrapper: pick a disk, pick file types, pick a destination, then run `photorec /d ... /cmd` unattended, with the output pane | B | Recover and clone |
| `foremost`, `scalpel`, `extundelete`, `ext4magic` | `autopsy` exists in noble but is the old browser-based Autopsy 2, so it is not recommended. Forms wrappers | B | Recover and clone |
| `ddrescue` (`gddrescue`), `safecopy` | **ddrescueview** (`ddrescueview`, 3 MB) shows the map graphically; the run itself is a Forms window with a live map | A+B | Recover and clone |
| `partclone`, `fsarchiver`, `partimage`, `clonezilla` | No maintained GUI in noble (`qt-fsarchiver` is gone). Forms: "Back up a disk / restore a backup" over partclone and fsarchiver with a destination picker | B | Recover and clone |
| `nwipe` | GNOME Disks can overwrite a disk; Forms "Erase a disk" over `nwipe --autonuke` with a loud confirmation | A+B | Recover and clone |
| `f3` (fake-capacity check), `badblocks`, `e2fsck` | Forms: "Is this USB stick real?", "Check this disk for bad blocks" | B | Disks and files |
| `chntpw`, `python3-hivex`, `reglookup`, `regripper` | Forms: "Windows accounts" (list, unlock, clear a password) and a registry browser on `hivex`; **RegRipper** (`regripper`) for reports | B | Windows |
| `libevtx-utils`, `libesedb-utils`, `libscca-utils`, `libevt-utils`, `libregf-utils`, `liblnk-utils` (Windows logs, Prefetch, shortcuts) | Forms: an event-log viewer built on `evtxexport` with filters; the others as "Windows artefacts" exports. Also in the Control Centre's Windows page | B | Windows |
| `dislocker`, `libfsapfs-utils`, `apfsprogs` | Forms: "Unlock BitLocker / open an APFS disk" (the Control Centre already unlocks BitLocker) | A*+B | Windows |
| `cryptsetup`, `mokutil`, `efibootmgr` | Forms: "Unlock an encrypted disk", "Secure Boot status", "Boot entries" (list, reorder, remove). GRUB Customizer and Boot-Repair are not in noble | B | Disks and files |

## Part 3: Network and Wi-Fi

| CLI | GUI front end | Tier | Folder |
|---|---|---|---|
| `nmcli`, `network-manager`, `wpasupplicant` | **nm-applet** and **nm-connection-editor** (`network-manager-gnome`, 2 MB) | A | Network and Wi-Fi |
| `wavemon`, `iw`, `wireless-tools` | **LinSSID** (`linssid`, 1 MB): scans and graphs channels. `wpagui` for supplicant debugging | A | Network and Wi-Fi |
| `nmap`, `ncat`, `hping3`, `arp-scan`, `nbtscan`, `fping`, `ndisc6` | **Zenmap** (`zenmap`, 1 MB) or **nmapsi4** (`nmapsi4`) for nmap; Forms "Who is on this network?" over `arp-scan`, `nbtscan` and `fping` | A+B | Network and Wi-Fi |
| `tshark`, `tcpdump`, `termshark`, `ngrep` | **Wireshark** (`wireshark`, 10 MB with Qt) | A | Network and Wi-Fi |
| `iftop`, `nethogs`, `nload`, `bmon`, `iptraf-ng`, `vnstat`, `jnettop` | **EtherApe** (`etherape`) for live traffic, **GNOME System Monitor**'s network graph; Forms for per-process (`nethogs`) | A+B | Network and Wi-Fi |
| `iperf3`, `iperf`, `speedtest-cli` | Forms: "Speed test" (internet) and "Speed between two computers", with a graph | B | Network and Wi-Fi |
| `ping`, `traceroute`, `mtr`, `tracepath`, `dig` (`dnsutils`), `whois`, `ipcalc`, `sipcalc`, `ethtool`, `net-tools`, `arping` | **GNOME Network Tool** (`gnome-nettool`, 2 MB): ping, traceroute, lookup, whois, port scan, netstat. `mtr` has an X11 mode. Forms for `ethtool` (link speed and duplex) and the calculators | A+B | Network and Wi-Fi |
| `ssh` (`openssh-client`), `telnet`, `ncat` | **Remmina** (`remmina`) for RDP, VNC and SSH; **GNOME Connections** | A | Network and Wi-Fi |
| `minicom`, `picocom`, `ipmitool` | **GtkTerm** (`gtkterm`) or **CuteCom** (`cutecom`) for serial consoles; Forms for `ipmitool` (power, sensors, event log of a server's BMC) | A+B | Network and Wi-Fi |
| `lldpd`, `snmp`, `tftp-hpa`, `socat`, `bridge-utils`, `vlan`, `avahi-utils` | Forms ("Which switch port am I on?" from LLDP, an SNMP walker, a TFTP fetch); the rest are plumbing (C) | B / C | Network and Wi-Fi |
| `hostapd`, `dnsmasq-base` | Run by the hotspot (see Part 1) | C | |
| bluetooth (`bluez`) | **Blueman** (`blueman`, 3 MB) | A | Hardware |
| `ttyd` (browser terminal for the AI) | Plumbing (C) | C | |

## Part 4: Hardware, power, stress and benchmarks

| CLI | GUI front end | Tier | Folder |
|---|---|---|---|
| `lshw`, `hwinfo`, `inxi`, `dmidecode`, `lspci` / `lsusb` (`pciutils`, `usbutils`), `edid-decode`, `read-edid`, `cpuid`, `msr-tools`, `i2c-tools` | **lshw-gtk** (`lshw-gtk`), **HardInfo** (`hardinfo`), **CPU-X** (`cpu-x`, 3 MB: CPU-Z for Linux), **USBView** (`usbview`) | A | Hardware |
| `lm-sensors`, `s-tui`, `psensor`-style monitors, `edac-utils`, `rasdaemon` | **Psensor** (`psensor`: temperatures and fans on a graph), **xsensors**; Forms for the memory error log | A+B | Hardware |
| `upower`, `acpi`, `powertop` | **GNOME Power Statistics** (`gnome-power-manager`); battery health also in the Control Centre; Forms for `powertop` | A+B | Hardware |
| `fwupd` | **GNOME Firmware** (`gnome-firmware`, a GTK front end for fwupd) | A | Hardware |
| `alsa-utils` (`aplay`, `speaker-test`, `alsamixer`) | **PulseAudio Volume Control** (`pavucontrol`), **QasMixer** (`qasmixer`); a Forms "Test the speakers" (the honest speaker test already exists) | A+B | Hardware |
| `v4l-utils` | **qv4l2** (`qv4l2`: controls and test picture) or **Guvcview** (`guvcview`), **Cheese** (`cheese`) for a webcam | A | Hardware |
| `evtest`, `libinput-tools` | Forms: "Test the keyboard, touchpad and touchscreen" (a window that lights up each key or touch) | B | Hardware |
| `stress-ng`, `stress`, `stressapptest`, `memtester`, `memtest86+`, `mbw`, `tinymembench`, `lmbench`, `numactl`, `pcm` | Forms "Stress test": CPU, memory (with `stressapptest`) and a bandwidth test, with a live temperature graph; MemTest86+ stays a boot entry (and a "Restart into memory test" button) | B | Stress and benchmarks |
| `fio`, `bonnie++`, `ioping`, `iotop-c`, `sysstat`, `sysbench` | **KDiskMark** (`kdiskmark`: CrystalDiskMark for Linux, uses fio), GNOME Disks benchmark; Forms for latency (`ioping`) and `sysbench` | A+B | Stress and benchmarks |
| `glmark2`, `vkmark`, `kmscube`, `mesa-utils`, `vulkan-tools`, `vainfo`, `intel-gpu-tools`, `radeontop`, `nvtop` | These already open on-screen windows (glmark2, vkmark, glxgears, vkcube). GNOME System Monitor for load; Forms "Graphics test" (the existing `gpu-bench`) and a driver/acceleration report | A+B | Stress and benchmarks |
| `htop`, `btop`, `iotop`, `strace` | **GNOME System Monitor** (`gnome-system-monitor`, 3 MB) or **Xfce Task Manager** | A | Hardware |
| `dmesg`, `journalctl`, `ksystemlog` | **GNOME Logs** (`gnome-logs`) or **KSystemLog** (`ksystemlog`) | A | Hardware |
| `sg3-utils`, `lsscsi`, `i2c-tools`, `msr-tools` | Engineer tools: Forms behind an "Engineer" lock, or left as plumbing | B / C | Hardware |

## Part 5: Security

| CLI | GUI front end | Tier | Folder |
|---|---|---|---|
| `clamscan`, `freshclam` (`clamav`) | **ClamTk** (`clamtk`, under 1 MB, a graphical front end for ClamAV) | A | Security |
| `rkhunter`, `chkrootkit`, `yara` | No GUI. Forms: "Check for rootkits" and "Scan with YARA rules" with a findings list | B | Security |
| `ufw`/`nft` (the hotspot's firewall is its own) | **Gufw** (`gufw`) only if a firewall is ever offered to the customer; not planned | A | |

## Part 6: What isn't a tool

`plymouth*` (boot splash), `linux-tools-generic-hwe`, `*-driver` and `mesa-*` packages, `libinput`, firmware, `edac`/`rasdaemon` services, `hostapd`/`dnsmasq` (run by the hotspot), `ttyd` and `tmux` (carry the AI terminal), `sway` and `seatd` (the graphics test), `wpasupplicant`, `i2c`/`msr` kernel modules: nobody runs these directly, so they need no front end. A few appear inside Tier A and B windows as the engine.

## Not covered by any open-source GUI, so SysMedic builds it (Tier B list)

PhotoRec and TestDisk; ddrescue's live run; partclone and fsarchiver backup and restore; secure erase; foremost, scalpel and the ext undelete tools; chntpw and the Windows account tools; the Windows log and registry readers (the `libevtx`/`hivex` family); rkhunter, chkrootkit and YARA; the arp-scan / nbtscan / LLDP / SNMP / TFTP / iperf / speedtest group; the stress and benchmark runners; keyboard and touchpad testing; `efibootmgr`, `mokutil`, `cryptsetup`; hotspot, vault, clock, hospital, update and every other SysMedic setting.

## Cost and where it fits

- A rough estimate, not measured: the Tier A packages add about **70 to 100 MB** of installed size before their dependencies (GTK libraries are already present; the Qt ones, Wireshark, KDiskMark, QDirStat, Okteta and ksystemlog, would add a Qt runtime of about **100 to 150 MB**). Choosing the GTK option wherever there's a choice (GParted, GSmartControl, Baobab, Xarchiver, GNOME Logs, System Monitor, GNOME Firmware) avoids most of it.
- The graphical desktop is **caddy-only today** (the stick has no desktop). A WIMP desktop on the 8 GB stick is a decision on its own: see below.

## Plan

1. **SysMedic Forms**, plus the desktop-folder skeleton and `pcmanfm --desktop`, in QEMU with a graphical display.
2. **Tier A**, folder by folder: install, add launchers, and check each opens and runs on the live image in QEMU.
3. **Tier B**, highest value first: PhotoRec/TestDisk, ddrescue, backup and restore, secure erase, Windows accounts and logs, hotspot, stress tests.
4. A **launcher test** that fails the build if any CLI in `packages/*.txt` and `usr/local/bin` has no front end or an explicit "not a tool" entry.
5. Offer the desktop on the **stick** if the size and the boot-time memory allow.

## Open decisions

- Does the **stick** get the desktop too? The 8 GB sticks have little room, and a desktop adds memory pressure on 4 GB machines.
- **GTK or Qt?** GTK keeps the image smaller; Qt (Wireshark, KDiskMark, QDirStat) gives the best tools for those jobs.
- **Engineer lock:** keep the destructive Forms windows (erase, partition, clear a Windows password) behind the engineer's unlock, as the CLI tools already are.
