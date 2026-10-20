# Changelog

## Unreleased

- **Network discovery, listen-only (`sysmedic-discover`, rescue menu N).** Plug into a customer's port and see what the network says about itself without sending a single packet: which switch and port you are on, its VLAN, duplex and PoE (LLDP and CDP), the spanning-tree root, who hands out addresses (DHCP, with a warning for two servers), IPv6 routers, and a list of devices that announced themselves by ARP, DHCP, mDNS/Bonjour, UPnP or NetBIOS, with makers from the IEEE list. "Worth a look" flags a second DHCP server, a duplicate IP, half-duplex, a spanning-tree change or two roots. Listens 65 s by default (switches repeat every 30-60 s); `--pcap FILE` analyses a capture made elsewhere, `--json` for scripts, results are kept in the visit's session folder and audited. The AI may run it (it only listens). Parsers are plain Python with a test (`build/tests/test_discoverlib.py`, including damaged-frame fuzzing); also a SysMedic Forms window ("What network is this?"). Active scanning and SNMP are not built yet and will need the engineer's explicit go-ahead.

- **Wi-Fi setup now says which radio does which job, and the hotspot is 2.4 GHz.** The field-proven arrangement is a USB Wi-Fi dongle for the internet and the computer's own (PCIe/built-in) Wi-Fi for the phone hotspot, both on 2.4 GHz. The boot Wi-Fi screen, `wifi` (menu 13) and the hotspot guide show a panel for the radios found (two radios; a lone dongle; a lone built-in). With a dongle and a built-in radio, `wifi` sets the built-in radio aside while you pick a network, so the picker can only use the dongle; the hotspot takes it over when started (and gives it back when stopped). The hotspot planner now prefers the built-in radio and 2.4 GHz; 5 GHz only on request (`--band 5`). Also fixed from a real visit: the hotspot no longer fails when the dongle can't hold a client and an access point at once (idle client removed and restored), udev and NetworkManager leave `sm-ap` alone, hostapd's refused channel falls back to other channels then 2.4 GHz, and `on --internet` on a running hotspot restarts it instead of doing nothing; the gateway is always handed out, so toggling internet needs no lease renewal.

- **Optional internet for the hotspot (menu H option 7, `sysmedic-hotspot on --internet`).** Your phone can now reach the internet through the rescue computer's own link. It is asked for every time and never remembered; the AI can't start it. Traffic is NATed out as the rescue computer's, DNS goes to public resolvers, and the hotspot still can't reach the customer's network (private, link-local and CGNAT ranges are dropped) or use IPv6; the dashboard and AI terminal stay the only services on `10.42.0.1`. IP forwarding is turned on only while the hotspot is on and restored when it stops. Tested with a network namespace as the phone: without the flag the internet was blocked; with it 1.1.1.1 answered and a LAN host was refused; stopping removed both tables and put forwarding back. Not yet tried over real Wi-Fi.

- **"How do I get my phone on the hotspot?" (menu H option 6, `sysmedic-hotspot guide`).** A step-by-step panel written for the radios this computer actually has. With two or more Wi-Fi radios it says which one carries the internet and which would host the phone (and how to pick another: `on --radio phyN --band 5|2.4`); with one it explains the shared channel and what to do when the regulatory rules block it (Ethernet or USB tethering for the internet, set the country, or a USB Wi-Fi adapter). Menu H also shows a hint when more than one radio is found. It never prints the hotspot password (that stays on option 5's private console), so the AI may run it.

## 2026.10.15 (later): the hospital mailbox

- **Rescue computers can ask Claude for help over the LAN.** A mailbox server on the build PC (`tools/mailbox`) takes redacted questions and findings from paired machines and returns replies; `sysmedic-hospital ask "…"` on the machine, `hospital inbox/reply` on the build PC. Per-machine tokens, HTTPS pinned to the server certificate, refuses unredacted-looking text, MCP endpoint included. The AI assistant may send and read; only the engineer pairs. See docs/HOSPITAL.md.
- **Swarm brainstorm.** Name each machine by its Service Tag, open a topic with `hospital swarm open`, and every paired SysMedic AI can join with `/swarm` through an MCP bridge (`sysmedic-hospital mcp`, configured in OpenCode): shared board, per-agent post caps, same redaction refusals. Probes of the mailbox by unpaired clients get a friendly 401 explaining how to pair.

## 2026.10.15: ChromeOS Flex, sound hardware, honest speaker test

- **ChromeOS and ChromeOS Flex are recognised.** A ChromeOS root slot (`ID=chromeos` / `CHROMEOS_RELEASE_*`) is a verified, read-only image: the scan no longer reports "no initramfs", "no grub.cfg" or "no Linux bootloader" for it, no longer flags it as full, and no longer offers GRUB or initramfs repairs, which would break its integrity check. It says what it is and how it is repaired instead. Found on a Surface Pro 3 running Flex.
- **Sound hardware is part of the scan.** It lists what the kernel found. A laptop with only HDMI/DisplayPort audio, or no sound card, gets a warning ("check Windows first"), and the speaker test lists the cards and kernel sound messages.
- **The speaker test no longer claims success it can't know.** `aplay` errors were thrown away and "Played" was printed regardless; a failed playback is now reported (exit 2).
- **Disk health wording:** a drive that passed SMART, remapped nothing and shows only the one "uncorrectable errors" counter is described with that context (and its own error-log count) and pointed at the read-only surface scan, instead of "surface damage".
- AI instructions (core.md) say never to repair a ChromeOS root slot like Linux.

## 2026.10.14 (night): 8 GB sticks, Service Tag in reviews, tester fixes

- **The stick edition fits on an 8 GB stick.** The stick only ever runs the 3B model, so drives under 14 GB get that model alone (about 3.8 GB used; the vault gets about 2 GB). Bigger drives keep both models. Tested by building and booting a 7.5 GB image, creating the vault, and starting the offline AI.
- **Review bundles name the laptop by Service Tag,** so two visits to the same model aren't mistaken for one machine. It is the only identifier let through the cleaning, and it's added after it.
- **`ntfsfix -n` in more spellings is allowed** for the AI (`-n`, `--no-action`, with `-d`).
- **Refused notes explained:** the command filter matches blocked words anywhere in a command line, including inside a `sysmedic-note` text. The AI's instructions now say to rewrite the note without tool names.
- Tested in a Secure Boot VM (v2026.10.14-3a4ae37b): RAID, access code and HTTPS, remote AI, hotspot, reboot persistence. Fixed on the way: `sysmedic-raid stop` counting the vault as busy, the remote-AI log holding the code, and `hotspot plan` ignoring the saved country.

## 2026.10.14 (evening): private hotspot, and your settings follow you

- **Private hotspot (menu H, `sysmedic-hotspot`).** A Wi-Fi network of its own from the rescue computer, so your phone or laptop reaches the dashboard and AI terminal without joining, or showing up on, the customer's network. The rescue computer is always `10.42.0.1` on it: bookmark `https://10.42.0.1:8443` (or `https://sysmedic.lan:8443`) once and it works at every customer. It serves only the dashboard (8443) and the AI terminal (8444); everything else is dropped by its own firewall table, nothing is forwarded to the customer's network, clients can't see each other, and the DHCP server hands out no gateway or internet DNS. Off by default, turns itself off after 30 minutes with nobody connected, and the AI can't start it (it can read `status` and `plan`).
- **It picks the best radio itself.** `sysmedic-hotspot plan` reads what each Wi-Fi chip can do: a radio that isn't carrying the internet link is preferred (a USB dongle, or the built-in one when the internet comes by Ethernet or phone USB tethering), on 5 GHz when the regulatory rules allow an access point there, else 2.4 GHz. One radio can usually be both client and access point, but only on the same channel, so the hotspot then follows the internet link's band; if that channel isn't allowed for an access point (common before a country is set) it says so and what to do. Tested here with virtual radios: the hotspot started on its own radio, a second virtual laptop joined with WPA2, got a DHCP lease, reached the dashboard port, ping and the `sysmedic.lan` name worked, every other port was refused, no routing, no internet DNS; stopping removed the interface, firewall table and processes, and the idle timer switched it off by itself. On this machine's real Intel chip it correctly reported that an access point can't share the internet link's 5 GHz channel under the world regulatory rules.
- **Your settings follow you (`sysmedic-hotspot setup`).** Hotspot name, password, band and country are kept in the vault (`engineer.json`) and are the same on every job, so your phone remembers the network. The password defaults to your access code or a random one. Locked vault: a fresh random hotspot per visit, nothing kept. The password is shown only on a private (unrecorded) console, and the cleaner masks it (`HOTSPOT_PASSWORD_1`).
- **The dashboard's HTTPS certificate is kept in the vault** (made once, ten years, for `10.42.0.1`, `sysmedic` and `sysmedic.lan`): your browser trusts one fingerprint everywhere instead of a new warning every boot. `sysmedic-hotspot show` prints the fingerprint to check once.

## 2026.10.14 (later): offline AI in the menu, your own access code, Linux RAID

- **Offline AI from the rescue menu (O).** Qwen on the machine itself, shared with the console and the phone's remote terminal, no internet needed. It starts Ollama if it isn't running and says so if it won't.
- **Your own remote access code (menu K).** For a laptop that can't read the QR code: `sysmedic-vault code new` picks five short random words (about 35 bits), or `code set` takes your own (10+ characters, typed twice, hidden). It is kept in the encrypted vault, so it survives reboots and is the same on every job. It opens the dashboard at `https://ADDRESS:8443` (a login page: type the code) and the remote AI terminal at `https://ADDRESS:8444/CODE/`. **HTTPS only:** the plain-HTTP dashboard port still accepts only the random per-boot secret, so the code never crosses the customer's network in clear text. Eight wrong tries from one address lock it out for ten minutes. The code is shown and entered on a private (unrecorded) console, the AI can't read the vault, and the cleaner masks the code (`ACCESS_CODE_1`) in anything the cloud AI sees. BitLocker's phone page keeps its own random link (it takes recovery keys). Locked vault or no code set: the random secret and QR code as before.
- **Linux RAID.** The scan now starts Linux software RAID (mdadm) and Intel IMSM firmware RAID **read-only**, then the LVM on top, and scans what is inside like any disk (before, RAID members were only listed and the data in them was never looked at). A degraded array is started with the disks that remain; a disk that dropped out earlier, with older data, is left out and reported. A mirror's filesystem is no longer scanned twice. New: `sysmedic-raid` (status, `assemble`, `stop`), menu L. Arrays and logical volumes are read-only devices; the kernel is told to start arrays read-only (`md_mod.start_ro=1`: on the kernel command line of both editions and in modprobe.d), so a dirty array no longer resyncs, i.e. writes to the customer's disks, the moment its disks appear. Tested with real arrays on loop devices (RAID 1 with LVM on top, one stale disk, one missing disk): the disk images were byte-for-byte unchanged. Not tested on hardware RAID (Intel RST) or with RAID 5/6; if the BIOS hides the drive (VMD/RAID mode), the scan says so and suggests AHCI.

## 2026.10.14: fixes from the stick's XPS 15 visit

From the Cruzer's evening visit (a Windows 11 XPS 15 that was mid-way through turning BitLocker off).

- **A failed BitLocker unlock says why.** Every failure was logged as "wrong key?", so six attempts with the owner's key gave no clue. The log, the console and the phone page now give cryptsetup's reason: the key doesn't match, the volume is part-way through encryption or decryption in Windows, or the format isn't supported. A well-formed key that doesn't fit gets only "wrong or missing parameters" from cryptsetup, which is now read as a wrong key. **Typos are caught before trying:** each 6-digit group of a real recovery key divides by 11, so a mistyped group is named ("typo in group 3").
- **Key ID shown everywhere you unlock:** `sysmedic-win bitlocker` shows the volume's Key ID before asking for the key, and the scan and `sysmedic-win` list show its first 8 characters, so the owner can pick the matching key at aka.ms/myrecoverykey (it was only on the phone page).
- **`sysmedic-win events --days N`** (default 60, as the scan). It ignored `--days` and counted all time without saying so, and the AI spent ten minutes trying to square its 529 with the scan's 185.
- **The AI can write its report even when the report mentions C:\Users.** A plain text write (`cat > file <<'EOF'` with a quoted terminator and nothing after it) is checked on its first line only; anything that can run or expand is still checked in full.
- **No disks found is no longer "No installed operating system".** Straight after boot the scan waits a few seconds (at most about 40) for the drive to appear; if none does, it says so and suggests the BIOS storage mode (RAID/VMD), which it names when it can see it.
- The stick's prompt says `root@sysmedic`, like the caddy, not `root@ubuntu-server`. The AI's instructions no longer offer the old `sync-back.sh` (sessions save themselves).

## 2026.10.13 (night): the cloud AI's privacy filter works again; AI conversations in the vault

From the caddy's afternoon visit (an XPS 15 left joined to a test domain).

- **The privacy filter inside OpenCode hadn't been running since OpenCode 2.** OpenCode 2 needs a new plugin format and only logs a warning when it can't load one, so OpenCode's own file tools (read and the others) sent file contents uncleaned, and the user-folder rule didn't apply to them. The shell route (`audit.sh`) was cleaned and refused as designed throughout. The plugin is rewritten for OpenCode 2 and tested against it (a file read reaches the model cleaned; a read under a user folder is refused, relative paths included). **The cloud AI no longer starts without it** (`sysmedic-ai-repair --check` shows it).
- **The AI's conversations are in the vault.** OpenCode kept its database, the output of every command the AI ran, and the engineer's prompts in plain folders on SysMedic's drive. They now live in the vault (`ai-data/`, `ai-state/`); what older versions left in plain folders moves in, and is deleted, when the vault next opens. Locked, they stay in memory like the visit. Its settings stay outside.
- **The cleaner learns again when a BitLocker volume is unlocked.** It only learned when its map was two minutes old, and every new placeholder refreshed the map, so in a busy visit it never learned the domain it had just made readable. It now also catches a domain's short name (`CORP\anna`), its domain controller (Group Policy, and `dc1` in the hosts file → `DC_SERVER`), names written with escaped dots (`grep 'corp\.example\.com'`), hosts inside the domain (`setup.<domain>` → `SERVER_1.AD_DOMAIN`, without hiding the word "setup" everywhere), and gives one placeholder to a computer name written in two cases.
- **`sysmedic-win reg-set` and `reg-delete`:** change or delete one offline registry value, once the partition is unlocked. The hive is copied to the session's backups first, the change is logged and read back, and the engineer approves each. `reged -I` couldn't delete (it writes the text `-`).
- **`ntfsfix -n` (read-only check) is allowed for the AI**, as its instructions always said; repairs stay blocked.
- **Unlock messages say what happens:** a whole-disk unlock no longer claims both "every partition becomes writable" and "its sibling partitions stay protected". Unlocking a BitLocker partition saves the open volume's NTFS metadata first, instead of "no metadata backup available for 'ntfs⏎BitLocker'". `sysmedic-guard status` shows an open BitLocker volume as read-only or WRITABLE, not "locked … unlocked".

## 2026.10.13 (evening): Wi-Fi remembered in the vault

- **The vault's passphrase is now the first screen**, before the network: unlocking it brings back the Wi-Fi networks saved in it, which join by themselves (the network check waits up to 20 s for them).
- **"Remember Wi-Fi … on this drive?"** after joining a network (first screen, `wifi`, menu 13): **y** saves it, password included, in the encrypted vault only; n (the default) keeps it in memory, forgotten at shutdown as before. With the vault locked nothing is saved. `sysmedic-vault networks` lists them; `sysmedic-vault networks forget NAME` drops one.
- **The AI can't reach Wi-Fi passwords:** NetworkManager's files, `nmcli --show-secrets` and the vault are refused in its shell and its file tools, and any Wi-Fi password in command output is cleaned to `WIFI_PASSWORD`.

## 2026.10.13 (afternoon): fixes from the caddy's morning visits

- **BitLocker repairs:** unlocking a partition for writing now makes its open BitLocker volume writable too (no key needed again), and `sysmedic-lock` makes it read-only again. Before, a volume first opened read-only (phone page, scan) stayed read-only whatever was unlocked, so repairs failed with "Read-only file system" and the engineer ended up unlocking the whole disk. `sysmedic-unlock` of the volume's `dm-` device unlocks its partition instead; `sysmedic-guard status` lists open BitLocker volumes.
- **Cleaning for the cloud AI no longer eats ordinary words:** a user path ran on past its end to the rest of the line (`…\thing.lnk  /run/sysmedic/…`), and each file name it hid was then hidden everywhere, so "Windows", "run" and "sysmedic" became `FILE_n` in reviews. Paths now end where Windows names must (no trailing space), file names are cleaned inside paths only, and the OneDrive *program* folder under AppData isn't treated as the customer's files.
- **Scan:** an unlocked BitLocker volume is reported as unlocked, not "get the key from the owner".
- **CPU stress test:** counts only the throttling during the test (the counter runs from power-on: 10169 on a Latitude 3410 that peaked at 83°C) and says whether it points at cooling (90°C and over) or at the firmware holding the CPU back (charger, battery, BIOS thermal setting).
- chkrootkit's daily self-check of SysMedic is off (false alarms, then a failed mail); `fuser` is installed; the "pam_lastlog" error on every console login is gone.

## 2026.10.13: what the cloud AI sees

From the field: OpenCode Zen's free models (Big Pickle included) may use data from the free period to improve the model, and customer data must never become training data.

- **`sysmedic-redact`:** every cloud-AI command's output is cleaned on the laptop before the cloud sees it. Role placeholders that keep the meaning (`USER_1`, `PC_NAME`, `COMPANY_NAME`, `AD_DOMAIN`, `WDS_SERVER`, `SCCM_SERVER`, `WSUS_SERVER`, `INTUNE_TENANT_ID`, `EMAIL_1`, `FILE_1`, …), learned locally from the offline registry; the map never leaves the laptop. Review bundles are cleaned too.
- **The customer's own folders are closed to the AI** until the engineer records the customer's agreement: `sysmedic-consent users`.
- **Every OpenCode tool's output is cleaned** by a SysMedic plugin (its read tool must stay: Zen's free tier refuses requests without it, found in testing); search tools and web search off; web fetches need approval. The plugin's library ships from the build kit, so it works offline.
- **The consent screen says it plainly:** the free model's provider may use what it sees; answering n keeps everything on the laptop (offline assistant).
- `sysmedic-note --help` shows help instead of saving "--help" as a job note.

## 2026.10.12 (late): customer data encrypted, battery on the menu

- **SysMedic branding on the AI screen:** a SysMedic bar across the top (cyan SYSMEDIC block, the assistant in use, then the machine, vault state, battery and time), on the laptop and in the phone's remote AI terminal; the OpenCode theme in SysMedic's cyan and blue (agent label, borders, headings, links; red only for errors). The console now gets SysMedic's full 16-colour palette through tmux: it had been squeezed to 8 colours, so dim text vanished and bright colours were dulled.
- **Secure Boot advice names the exact setting** for the machine's maker (Dell, Lenovo, HP, Surface; generic otherwise), from the firmware's own identification.
- **Boot entries left by older SysMedic drives** ("Ubuntu", pointing at a SysMedic drive or at a disk that isn't connected) are listed by the scan with the commands to remove them (engineer only; SysMedic never writes to the firmware itself).
- **Battery on the rescue menu:** charge, charging state and health (with cycle count) under the live strip, yellow when worn (under 80%) or low, red when it needs replacing (under 60%) or at 15% on battery. Same reading as the phone dashboard (`power.py`).

- **Encrypted vault** (`sysmedic-vault`): sessions, backups, serial numbers, console transcripts and review bundles live in a LUKS2 container on SysMedic's drive (caddy and stick). SysMedic, the offline AI and the virus signatures stay outside it, so booting and the offline AI need no passphrase.
- **First screen:** the drive's passphrase. Skip it and SysMedic still works, with this visit kept in memory only (said in the scan, menu and console 2) until `sysmedic-vault unlock`. Nothing is written unencrypted any more.
- **Setup** (offered at boot the first time, or menu **V**): a passphrase and a one-time recovery key, shown on a private console so it never lands in a transcript. Data from before is moved in and the unencrypted copies deleted.
- **Forgotten passphrase and recovery key:** after three wrong tries, **r** erases the vault (typed `ERASE`) and sets up a new one (`sysmedic-vault reset`).
- **Saved as it goes:** while the vault is open, transcripts every 30 s and the review bundle every 5 minutes. In testing, shutdown unmounted the vault before its save step ran, so the record no longer depends on a clean shutdown; a dying battery loses seconds.
- **Deploys** back up the stick's vault still encrypted; the caddy collects a stick's data only into its own unlocked vault (and asks for the stick's passphrase). Both AI assistants are refused the vault.

## 2026.10.12 (night): Beethoven and a volume control

- **Speaker test with more music** (field request): besides *Ode to Joy* (left, right, both), the *Moonlight Sonata* (deep bass: rattle), *Für Elise* (treble: crackle) and the *Fifth Symphony* (loud attacks: distortion), then the sweep. All synthesised on the drive; each part is levelled so the test itself never clips (clipping would sound like a damaged speaker).
- **Volume control while it plays:** ↑/↓ or +/−, m to mute, space for the next piece, q to stop. From the Tests menu it runs at the keyboard; the phone and the AI play the whole programme. Checked in QEMU by recording the virtual sound card: the level follows the keys, and mute is silent. It also fixes the old fixed 80% setting, which failed silently on cards whose volume control has no mute switch.

## 2026.10.12 (evening): Secure Boot on Secured-core laptops; the boot menu is back

- **Boot menu restored** (fd3e19b): the silent-boot GRUB (forced 1920×1080, theme, hidden 1-second menu) hung before the menu on firmware without that video mode. Back to the plain 8-second menu, on the caddy and the stick.
- **The scan explains a Secure Boot refusal.** A Dell Pro 13 Plus wouldn't boot SysMedic with Secure Boot on: its firmware trusts only Windows (Dell's "Enable Microsoft UEFI CA" is off, as on many Secured-core laptops), so it rejects every third-party bootloader. A shim signed with Microsoft's 2023 CA wouldn't help, because that CA isn't trusted either. The scan now reads the firmware's trust list and names the BIOS setting, with the BitLocker catch (changing it means one recovery-key prompt).
- **The caddy no longer writes to the machine's firmware.** Booted from a laptop's boot menu, the caddy's shim ran Ubuntu's fallback helper (fbx64.efi). That helper added an "Ubuntu" boot entry to the customer's firmware and put it first in the boot order, on every machine. Deploys now put GRUB on the USB boot path and remove the helper. Tested in QEMU with Secure Boot: before, a new "Ubuntu" entry appeared first in the boot order; after, the firmware's entries were unchanged. Machines already visited may still have a stale "Ubuntu" entry; it's harmless, and can be removed in the BIOS boot settings.
- **The stick has a UK keyboard too** (it was US; field request). Deploys rebuild the console's cached keymap when the layout changes. `mokutil` (Secure Boot state and keys) is now on the stick as well.
- **Graphics tests say which console they're on:** "console 3; back here early: Ctrl+Alt+F2, back to the test: Alt+F3" (field request: the switch wasn't obvious).
- **BitLocker warning:** with Secure Boot off and a BitLocker volume present, the scan says to turn Secure Boot back on before Windows starts, otherwise Windows asks for the recovery key.

## 2026.10.12: what fills a disk

From the field: a "disk full" job meant the AI hand-writing `du` loops for half an hour, and Docker's images couldn't be cleaned from the rescue boot.

- **`sysmedic-du`** (menu **D**, the desktop menu, and both assistants): every customer filesystem with how full it is, then a read-only analysis of the one you pick. It shows a folder tree, each user's share, the biggest folders and files, and **space you could get back** in four groups: safe to delete (caches, temp files, Windows Update downloads), the owner decides (rubbish bin and Recycle Bin, games, AI models, downloads), clean from the machine's own system (Docker/containerd images, snaps, the hibernation file, Windows.old, restore points), and keep (swap and page files, WinSxS, Docker volumes). Each item says how to clean it. About a minute for 5 million files.
- **Drill down** folder by folder with `ncdu` in read-only mode (it can't delete): offered after the analysis, or `sysmedic-du browse /dev/X`. ncdu is now on the stick too.
- The analysis is saved to the session (`disk-usage-<partition>.txt` and `.json`). The scan's "almost full" finding points to it.
- **Containers:** Docker and containerd images can only be pruned by their own daemon, so the analysis lists them under "clean from the machine's own system" with the commands for the booted machine, and keeps Docker volumes (real data) apart.
- The menu table in the field guide matches the current menu again.

## 2026.10.11 (night): test either GPU on hybrid laptops

From the field: on an Intel + NVIDIA laptop the graphics tests only ever used the Intel chip, and a vkmark warning was taken for a failed Vulkan test.

- **`--gpu N`** for `gpu-bench`, `gpu-stress` and `gpu-video` (`sysmedic-tests start gpu-bench --gpu 2`, `sysmedic-gfx --gpu 2 bench`). The chosen GPU renders (Mesa's DRI_PRIME for OpenGL, MESA_VK_DEVICE_SELECT for Vulkan, its render node for VA-API), and the picture still appears on the laptop's screen. `sysmedic-tests gpus` / `sysmedic-gfx gpus` number them; 1 is the GPU driving the screen.
- **Phone dashboard and console menu** offer a GPU choice for those tests when the machine has more than one.
- **`sysmedic-gfx info` checks each GPU can render.** One whose driver or firmware isn't working falls back to software (llvmpipe) and is reported as "can't render". The results say so too if a test asked for one GPU but ran on another.
- **Telemetry follows the GPU under test.** It used to read whichever GPU was `card0`, which on hybrid laptops is often the idle discrete one, so clocks and temperatures were missing.
- **vkmark's "apiVersion has value of 0" line** is now labelled as harmless. vkmark 2017.08 doesn't set the field, and newer Vulkan stacks complain; the scores are valid.

## 2026.10.11 (evening): the clock, and sign-in safety

From the field: a laptop whose hardware clock was 10 hours slow made every secure connection fail (the cloud AI, apt, signatures), and the scan blamed DNS. Another visit's "performance fix" left a Linux machine without a login screen.

- **`sysmedic-clock`** shows SysMedic's clock, the machine's hardware clock and the real time. The real time comes from plain-HTTP Date headers, so it works where NTP is blocked and where HTTPS fails because of the clock. Once online (first screen or `wifi`), SysMedic **corrects its own clock automatically**; the customer's hardware clock is never touched except by `sysmedic-clock fix --rtc`. That command is engineer only: it asks Windows (local time, with the zone) or not (UTC). A hardware clock a whole number of hours out is recognised as Windows local time, which is normal.
- **The scan names the real cause** when the cloud isn't reachable: SysMedic's clock, DNS, HTTPS blocked (sign-in page, proxy, firewall), or no internet. It also reports **"This machine's hardware clock is … slow"** (a likely flat CMOS battery when it's months out).
- **NTP sync is off** (systemd-timesyncd masked): a synced Linux clock gets copied into the hardware clock every 11 minutes in UTC, which put Windows machines an hour out after a visit and erased the evidence.
- **The scan checks Linux sign-in:** PAM or nsswitch still using sssd while sssd is disabled is reported as critical (account checks fail and the login screen may not appear), with the clean fix.
- **The assistants:** sign-in files are one system (change them as a whole, in a chroot, with backups, then re-scan); one agreed change at a time instead of bundled "fixes"; "certificate not yet valid" means the clock. Writing the hardware clock is blocked for both.
- **Boot:** the splash hand-off service is gone. It ran a second scan before the network and clock were ready (so the visit's folder got the wrong date) and wrote to the first console while it was in use. The Plymouth theme and quiet GRUB stay.
- **ttyd's own service is masked** (it ran a local login terminal); the remote AI starts its own ttyd when the engineer turns it on.
- Deploys now also remove obsolete *symlinks* (an enable link points at an absolute path, so the old check missed it).
- `util-linux-extra` added (`hwclock`).

## 2026.10.11: boot fixes, and a smoke test before every deploy

The 9 October caddy deploy broke two things on every boot. Fixed and tested in QEMU on both editions:
- **The triage scan crashed at boot** (`TypeError: main() takes 0 positional arguments`), so no session folder or review bundle was written. The new timing helper (`--time` on the Python tools) now works with tools whose `main()` takes no arguments, and logging the timing can never stop a tool.
- **The cloud assistant wouldn't start on the caddy** (`Unrecognized flag: --model`): OpenCode 2.x has no `--model`. The model comes from `opencode.json`, as it always did.
- **The Wi-Fi first screen and the animated logo are back.** The splash-screen change had taken them out of the boot sequence, so machines without Ethernet started offline. GRUB's quiet boot and the Plymouth theme stay.
- **The stick image builds again:** `build-iso.sh` finds the GRUB theme in the repo.
- **Smoke test in `sysmedic-deploy`** (caddy, stick image, `--self`): after installing, every script must parse, the tools must start without a traceback, and every flag SysMedic passes to `opencode` must exist in that drive's own OpenCode (1.18 and 2.x differ). It fails the deploy loudly instead of shipping a drive that won't boot cleanly. Checked against both of the bugs above.
- The offline assistant keeps its tested instructions; a longer rewrite was dropped because it slowed the first reply on CPU and ruled out the clock fixes.

## 2026.10.08 (late): menu in order, and a graphical desktop (prototype)

- **The rescue menu is numbered in reading order**, card by card: 1 scan · 2 tests · 3 job report · 4 phone dashboard · 5 AI · 6 repair the AI · 7 Windows tools · 8 unlock · 9 re-protect · 10 backup · 11 Linux boot · 12 macOS · 13 Wi-Fi · 14 save logs · U update · G desktop · 15 toolkit · 16 shell · 17 reboot · 0 shut down. Guides and messages updated.
- **G: graphical desktop** (caddy; prototype), only when chosen: labwc windows in SysMedic Night, a panel (SYSMEDIC, Control Centre, AI, terminal, files, disks, rescue menu, open windows, RAM/network/clock, ⇦ Console), the **Control Centre** window (the dashboard on the laptop's screen), the AI assistant this visit's consent allows, a launcher with SysMedic's tools first, and a right-click menu of everything. Keyboard: Super+M menu, Super+Space launcher, Super+Return terminal, Super+A AI, Super+C Control Centre, Super+E files, Super+Q close, Alt+Tab. Needs 4 GB RAM and a graphics device; quitting returns to the rescue menu; disks stay write-protected as everywhere.

## 2026.10.08 (night): the phone dashboard, submenus and the assistant's input

- **Phone dashboard in SysMedic Night**: gradient SYSMEDIC wordmark, live strip (CPU temperature, memory, load, clock), ✔ ▲ ✖ ● on findings, monospace figures, glowing cards with spaced cyan headings; a matching light variant for daylight.
- **Submenus restyled** (Windows tools, Linux boot repair, macOS, backup): banner, grouped sections, highlighted keys with dim notes. The Windows tools menu now also offers **t** traces (ETL) and **b** boot configuration (BCD).
- **Typing while the offline AI answers no longer prints over its reply**: keys are kept, unprinted, and appear at the next prompt.

## 2026.10.08 (evening): the console goes high-tech

- **SysMedic Night palette** for every console (`/etc/sysmedic/vtrgb`, applied at boot by setvtrgb): navy-black background, soft text, cyan and blue accents, gentle green/amber/red for status.
- **SYSMEDIC in block letters** (half blocks, cyan→blue) on the first screen, revealed behind a scan line, and at the top of the menu with a live strip: CPU temperature, memory, load, clock.
- **The rescue menu** is a screen, not a list: logo and live strip, the machine at a glance (scan chips, Windows, BitLocker locked/unlocked, network, where the AI runs, update available), then the options as grouped cards in two columns (Diagnose & test · AI · Windows & disks · Other systems · Connect & save · Tools & power). Numbers are unchanged.
- **The scan shows its progress live**: system ✔ drive ✔ disks ✔ health ✔ filesystems ✔ boot ✔ network ✔, then the time it took.

## 2026.10.08 (later): SysMedic looks the part

- **Its own console font**, `Vietnamese-SysMedic22x11` (`build/make-console-font.py`): Terminus 11×22 plus the symbols SysMedic draws — ✔ ✖ ✓ ● ▲ ▼ ⚠ □ ► ❯ and the full ▁▂▃▄▅▆▇█ sparkline set. No stock console font had them (✔ printed as "V", ▲ as an arrow, ● as a speck). Loaded through console-setup's normal codeset path (`FONTFACE="SysMedic"`): `FONT="file"` garbled capitals and digits on this kernel.
- **One look everywhere** (`lib/sysmedic/ui.py` and `ui.sh`): a ▌SysMedic banner, sections with a rule, coloured ✔ ▲ ✖ ● ► marks with dim detail lines and → next steps, and summary chips (✖ 0 critical ▲ 1 warning ● 2 notes ✔ 4 OK). Applied to the first screen, the triage scan, the engineer console, the offline assistant, tests (list, status, run markers, results), hardware tests, sysmedic-win, graphics results and the AI self-check.
- The phone dashboard's QR code is drawn with half blocks: half the height, so the engineer console's commands are visible above it (the console has no scrollback).

## 2026.10.08: what the Samsung caddy and the stick saw on 7 October

Ten sessions (Dell Pro 13 Plus ×5, Latitude 3450 ×2, Precision 3571 drop inspection, …). Fixed:
- **Rescans lost Windows when the AI had it mounted.** The scan skipped any already-mounted partition, so after the AI mounted `C:` at `/mnt/win`, the job report's rescan said "No installed operating system found". Mounted partitions are now read through their existing mount (left mounted; the filesystem check is skipped for them). Reproduced on the stick system before and after.
- **Microsoft Defender flagged as suspicious** (`MDCoreSvc`, `WinDefend` "run from a user-writable folder"): Defender's admin-only folders in ProgramData are no longer treated as user-writable; service names that are `@…dll,-NNN` resource strings are no longer shown.
- **Firmware is the engineer's.** The AI refreshed firmware metadata online and looked at writing UEFI variables to enable Secure Boot (it didn't). Both AIs are now blocked from flashing (`fwupdmgr` install/update…, `fwupdtool`, `flashrom`), boot-entry changes (`efibootmgr` writes), writing efivarfs, and Secure Boot key changes (`mokutil`); reading stays allowed.
- `sysmedic-win` commands take a BitLocker partition directly once it's unlocked (the AI kept passing `/dev/nvme0n1p3`).
- The RAM test's log was 600 KB of memtester spinner; it now keeps only finished lines.
- "Save session log" (menu 3) wrote a separate `session-…-sysmedic` folder; it now adds its logs to the visit's session.

New, from what the AI had to do by hand:
- **`firmware` test**: BIOS version, Secure Boot on/off (and Setup Mode) with how to turn it on, TPM, firmware updates available from LVFS (reports only), UEFI boot entries.
- **`sysmedic-win reg`**: read any registry key/value (it took the AI ~40 `hivexsh` attempts to read a few service and policy values).
- **`sysmedic-win bcd`**: the Windows boot configuration decoded (it spent 10 minutes on this by hand for a HYPERVISOR_ERROR case).
- **`sysmedic-win crashes`** also reads Windows Error Reporting's kept reports (blue screens, LiveKernelEvents) and LiveKernelReports, and names HYPERVISOR_ERROR, 0x141/0x117/0x193 graphics resets and 0x144 USB 3.
- **`audio-music` test** (the AI's suggestion for drop-damaged laptops): Beethoven's Ode to Joy, synthesised on the spot, left / right / both with bass, then a 40 Hz–12 kHz sweep for rattles and buzz.

## 2026.10.07 (evening): caddies update themselves from GitHub

- **`sysmedic-update`** (menu **U**): check, apply, rollback, status. Signed releases from the public `splippers/sysmedic-releases`; the private repo and its history stay private and no credential is stored on a caddy. Boot-time check (timer) and an "Update available" line in the menu.
- **`sysmedic-deploy --release [--publish]`** builds, secret-scans, signs and publishes; **`--self`** installs a release on the running caddy.
- Removed the old `scripts/sysmedic-update.sh`, which carried a hard-coded CraicKen token onto every caddy (`/opt/sysmedic/scripts`); deploys now delete it.

## 2026.10.07 (afternoon): graphics battery on the laptop's own screen

- **`sysmedic-gfx`**: `info` (GPUs, driver in use, real renderer, displays with panel identity), `display` (10 full-screen test patterns), `bench` (glmark2 OpenGL ES + vkmark Vulkan on screen), `stress MIN` (burn-in), `video` (VA-API decode). New tests `gpu-info`, `gpu-display`, `gpu-bench`, `gpu-stress`, `gpu-video` (slash commands, phone, AI: "check for dead pixels", "graphics burn-in", "vulkan benchmark").
- **Live telemetry panel** over the visuals: FPS with sparkline, GPU clock/load bars, temperature and power with history, CPU load/clock/temperature, throttling; read from the kernel (no vendor tools) and saved as CSV for the report. Results name scores, per-scene FPS, peaks, throttling and GPU hangs/resets.
- MangoHud (Ubuntu 24.04's 0.6.9) was tried for the overlay and dropped: it crashed glmark2 and didn't draw. Packages added: sway, foot, seatd, vkmark, glmark2-es2-wayland, kmscube, vainfo, intel-media-va-driver, mesa-va-drivers.

## 2026.10.07 (later): the offline AI obeys, and uses a discrete GPU when there is one

- **Obedience, enforced in code.** Declined commands, "No", "forget/drop X" and corrections are remembered for the conversation and enforced by SysMedic (re-offers are held back, and flagged and rewritten if they appear in text). "No" alone gets "OK." without a new suggestion. After a correction the model no longer sees its earlier plan, and in general only the last few exchanges. Its instructions now open with "the engineer is in charge: do exactly what the latest message asks, nothing more, no unasked offers". Replayed the 3410 session: after "These tests do not exist" it now says "Got it, I'll stick to known tests" instead of re-offering `memslot`.
- **GPU for the offline AI.** Ollama's Vulkan backend and Mesa's Vulkan drivers ship on all drives. `sysmedic-ai-device` picks a discrete GPU with ≥3.5 GiB (never built-in graphics, which measured 5× slower than the CPU), self-tests it after the model loads, and falls back to the CPU if it fails, stalls or is slow. Measured on a GTX 1650 with qwen2.5:3b: 319 tok/s reading the prompt against 24 on the CPU, replies at 40-49 tok/s against 10.

## 2026.10.07: real tools only, and memory testing

From the 3410 session at 23:00, where the offline AI offered `sysmedic-tests start memslot` and `mem` (neither existed), a malformed surface test, and said it would record the session without doing so:
- **The AIs can only use real tools.** The offline assistant checks every proposed command (installed program, real test name, correct `--disk` form, real `sysmedic-hwtest`/`sysmedic-win` subcommand); fakes go back to the model with the real list, and fakes in its prose are flagged and corrected. Both AIs' instructions now contain the generated test catalogue. In AI shells a missing command says "does not exist on this rescue system" and is logged. `sysmedic-tests` maps common guesses to real tests and suggests the closest name; `sysmedic-hwtest` fails (instead of printing help) on an unknown test.
- "Record/report/flag this" in the offline assistant saves SysMedic feedback. Direct test requests now show the test live (`sysmedic-tests watch`), so it doesn't look stuck.
- **Memory testing:** new tests `ram-modules` (each slot's module, speed, maker/part, ECC/EDAC errors per slot, SPD; how to find a bad SODIMM), `ram-stress` (stressapptest), `ram-speed` (mbw; spots a module that isn't working via single-channel bandwidth). Installed: stressapptest, mbw, tinymembench, lmbench, numactl, pcm, alongside memtester, MemTest86+ (boot menu), stress-ng, sysbench, edac-utils, rasdaemon, i2c-tools (decode-dimms). "I think I have a bad SODIMM" goes straight to `ram-modules`.

## 2026.10.06 (late): fixes from the 3410 test session

- **The offline assistant does what it's asked.** On the 3410 it ignored "test the GPU" four times and kept proposing a broken `mount` command. Plain requests for a test ("test the GPU", "check the battery", "how's the Wi-Fi") now run the matching SysMedic test directly (Enter = yes) and the model only explains the result; every message reminds the model to answer the latest request. New `/tests` and `/feedback TEXT` commands.
- **Graphics benchmark can't hang.** It ran for over an hour on the 3410 with nothing on screen (output was buffered and there was no time limit). It now runs 8 short scenes at 1280×720 (about 40 s), shows each scene's result as it goes, and stops after 150 s with "FAILED: stalled" plus any GPU driver errors from the kernel log. It warns when the score comes from software rendering (llvmpipe: no GPU driver in use) rather than the graphics chip.

## 2026.10.06 (evening): what the stick's AI found on the 3410

Seven problems in SysMedic's own tools, diagnosed by the AI with evidence, are fixed:
- `evtx` read only 111 of 429 logs (a wrong "empty log" size rule): it now reads every log and reports empty/unreadable ones by name. The skipped logs held the real root cause (Storport 524 NVMe command timeouts), which now has its own rule, as do ClassPnP 507/509.
- Storage errors name their **device** (vendor, model, serial's last 4): 732 of 733 "disk errors" were the SanDisk stick, not the laptop's NVMe.
- Code-integrity events are grouped **by file**; security-product components (FortiClient's AMSI DLL: 17,933 events) are labelled usually benign instead of reading like a compromise.
- The `cbs` verdict only gives upgrade-failure advice for 0xC19xxxxx codes actually present; 0x80070422 names the usual disabled services including System Restore, which the registry check now reports.
- The job report never says **fixed** unless a repair happened and the last scan could still see the system; otherwise "no longer detected; not confirmed fixed". It also states when no malware scan ran.
- A `fsck.vfat` volume-label-only mismatch is reported as cosmetic.

New, as the AI requested:
- **`sysmedic-win etl`**: Windows Update and other components' ETW traces, decoded with the vendored etl-parser (pure Python, Apache-2.0; with construct, MIT). Also in `checkup`, `/windows-traces`, and the phone Tests card.
- **More Windows log readers:** libesedb-utils, libscca-utils, libevt-utils, libregf-utils, liblnk-utils; a coverage table in WINDOWS-AND-BITLOCKER (perfmon/WMI repository: unsupported).
- More error codes decoded (0x8024401C, 0x80072EE6, 0x8024000C, 0x80070057, 0x800704CF).
- **Battery** on the phone dashboard (charge, health, cycles; worn batteries flagged).
- **No downloaded code:** the AI had cloned etl-parser from GitHub and fetched a wheel from PyPI to run as root. Both AIs are now blocked from `git clone`, pip and PyPI/GitHub downloads, and told to record missing tools as feedback instead; SysMedic ships vetted code.

## 2026.10.06 (later): BitLocker from the dashboard

- **One QR code:** the phone dashboard has a BitLocker card (volumes, locked/unlocked) with **Unlock from this phone**, which starts the encrypted unlock page and opens it at the address the phone already used. The key never touches the plain-HTTP dashboard. Verified in QEMU against a real BitLocker test volume: started, unlocked read-only, page closed itself, key in no log. Both AIs are blocked from the dashboard's secret and BitLocker endpoint.

## 2026.10.06 (later): lessons from the new caddy's first two 3410 visits

- **The offline AI ran a destructive disk test.** Qwen 7B proposed `badblocks -w` (overwrite test) on the customer's Windows partition, and `fsck -f`; both were approved at the prompt. The kernel write-protection refused every write, so **no data was touched**, but the AI then misread the refused writes as "multiple bad blocks". Now: write-mode badblocks, fsck-family repairs (anything without `-n`), mkfs, wipefs, shred, discard, `dd` to a disk, partitioning, secure erase, NVMe format, unlock and chntpw are **refused outright** by the offline assistant (not offered), and denied for OpenCode. Both are told a surface test is `sysmedic-tests start surface` (read-only) and that failed writes on a protected disk are not bad blocks. Rules checked to agree on OpenCode 1.18 and 2.0.
- **"No installed operating system found" after a rescan** (Windows was there): the scan tried to mount a partition `sysmedic-win` had already mounted. It now reads the existing mount and leaves it mounted.

## 2026.10.06: build from scratch, tests everywhere, a cleaner OpenCode, AI self-repair

- **Build from scratch:** `build/bootstrap.sh` (kit, fetch, stick-base, caddy) turns the stock Ubuntu 24.04.5 ISO into a stick or caddy, with pinned OpenCode 1.18.34, Ollama 0.23.4 and Qwen models; guide in [BUILDING](BUILDING.md). The ISO build accepts the stock ISO (installer layers left out, EFI image extracted); the stick's initramfs boots casper (`conf.d/default-boot-to-casper.conf`, now in the repo).
- **Tests everywhere:** `sysmedic-tests` catalogues 19 hardware and software tests, runs them in the background and records them in the job report. They're OpenCode slash commands (`/disk-test`, `/cpu-stress`, `/windows-checkup`, `/full-check`, `/tests`…), menu 16, and a Tests card on the phone dashboard (run, live output, stop).
- **A cleaner OpenCode:** no sidebar, thinking, timestamps, metadata, animations, tips or upsells; the `/` menu shows the tests instead of developer commands (still in Ctrl+P). On both 1.18 and 2.0.
- **AI self-repair:** `sysmedic-ai-repair` (menu 17) restores OpenCode and the offline AI to a known-good state and self-checks; boot points to it if OpenCode crashes at start.
- **Qwen only:** jonotron removed (repo, config, stick, caddies).
- **Caddy settings in the repo:** boot menu, Ethernet netplan, UK keyboard, persistence service, root's shell setup, the toolkit in `/opt/sysmedic` (it had drifted). The blacklist that left Realtek USB Wi-Fi dongles without a driver on kernel 7.0 is removed. More services that announce on networks are masked.
- The deploy stops with the failing line instead of silently, and handles a fresh system.

## 2026.10.05: lessons from a stick-vs-caddy run on the same Latitude 3410

Measured: the stick (Cruzer Blade) is a USB 2.0 drive, 25 MB/s sequential / 252 random IOPS; the caddy 276 MB/s / 1,768 IOPS. Loading the offline model: stick 253 s (3B, 1.9 GB), caddy 13.8 s (7B, 4.7 GB). With everything in RAM they're equal (same CPU, same cloud model).
- **The AI can't power the machine off.** It had rebooted or powered off in three sessions despite instructions. `reboot`, `poweroff`, `shutdown`, `halt`, `systemctl reboot|poweroff|…`, `init 0/6`, sysrq are now denied in OpenCode's config and refused outright by the offline assistant (not even offered for approval). The instructions say so explicitly.
- **No improvising:** `dislocker`, `pip install` and reading or copying the SAM/SECURITY hives are denied (the caddy's AI had unlocked BitLocker with dislocker, copied the hives to /tmp and tried to pip-install a parser). The instructions point at `sysmedic-win` instead. Rules checked against OpenCode's own matching logic (longest pattern wins) and the exact commands from that session.
- **OpenCode's settings now apply on the caddy too.** The caddy runs OpenCode **2.0.22** (the stick 1.18.34), and 2.x reads only `opencode.json`; it had been ignoring `config.json`, so on the caddy none of SysMedic's OpenCode settings applied (permissions, model, SysMedic agent). The file is now `opencode.json` (both versions read it; the old one is removed). Verified on 2.0.22: loads 167 rules, answers as SysMedic, blocks power commands and pip; rule outcomes checked to match on both versions (1.18: longest pattern wins; 2.0: last rule wins).
- **Branding on OpenCode 2.x:** bash output starts expanded and tool summaries aren't cut to 4 lines. Each patch now applies independently, so an already-branded binary still gets new ones.
- **Saved Wi-Fi passwords removed from netplan:** Ubuntu's NetworkManager had mirrored the caddy's networks into `/etc/netplan/90-NM-*.yaml` with their passwords. The deploy removes those; with networks kept in RAM, NetworkManager no longer writes them (verified).
- **Honest drive-speed advice:** the scan reads the drive's own USB version. A USB 2.0 drive is reported as such ("can't go faster in any port; use the caddy or a USB 3 stick") instead of "use a USB 3 port"; the port advice is kept for USB 3 drives on a slow link. The drive model is named.

## 2026.10.04: Wi-Fi first, BitLocker from a phone, OpenCode as SysMedic

- **Network first:** the first screen at boot gets SysMedic online (`sysmedic-connect`): wired passes by itself, otherwise nearby Wi-Fi networks are listed and `nmtui` opens on Enter; skipping (or 60 s) carries on offline. The banner then shows how SysMedic is connected.
- **Wi-Fi passwords in RAM only** on both editions (NetworkManager keyfile path in `/run`); the deploy removes any saved on a drive before.
- **BitLocker web unlock** is back, rebuilt safely: `sysmedic-win bitlocker-web` (menu 6 → w). HTTPS with a per-run certificate, a secret QR link, read-only, Key ID shown, 5 wrong keys / 15 minutes and it stops, nothing logged. The old portal was removed in 2026.10.02 because it had no authentication. Tested against cryptsetup's BitLocker test volume: wrong link 404, wrong key refused, right key unlocked, link closed, key in no log.
- **OpenCode is SysMedic:** a default SysMedic agent whose prompt is SysMedic's instructions (replacing OpenCode's coding-assistant prompt; it answers "I'm SysMedic…"); Build/Plan agents off; auto-update and sharing off.
- **OpenCode looks like SysMedic:** SysMedic logo, a 16-colour console theme, rescue examples and tips (`build/opencode-brand.py`, applied by the deploy).
- **No more "Click to expand":** tool output starts fully expanded (it needed a mouse); read long output with Page Up/Down. Verified: all 40 lines of a 40-line output drawn.
- Console font: Terminus 11×22 in the **Vietnamese** set (full Latin plus the block and line-drawing characters; the Lat15 set chosen earlier lacked ▀ ▄ and garbled OpenCode's logo on the Linux console).
- The ISO build now mounts its base image if needed and **fails loudly** if xorriso fails (a failure had silently left the previous ISO in place during testing; the drives weren't affected).
- OpenCode versions: the caddy runs 2.0.22 and the stick 1.18.34.

## 2026.10.04: deep Windows troubleshooting

- `sysmedic-win evtx`: ingests **every** event log (not only System) with curated rules for the logs that explain problems, an error sweep of all others, Windows' boot-time measurements and a Security summary. Takes exported `.evtx` files too.
- `sysmedic-win registry`: registry evidence: missing service/driver files, device filter drivers that don't exist, hijacks, Defender/Update policies and exclusions, crash-dump and paging settings, proxies, hosts redirects, recent installs.
- `sysmedic-win cbs`: CBS.log and archived CbsPersist logs (cabextract), dism.log, ReportingEvents.log and Panther: failing updates, decoded HRESULTs, component-store corruption, SFC/DISM results and a verdict with next steps.
- `sysmedic-win checkup`: all of it plus info/crashes/autoruns, saved as `windows-checkup-*.md` in the session folder. Menu 6 → c/e/r/s.
- The AI may run all four. Its instructions say to start "full check-up" requests with `checkup` and to correlate across sources.
- Test fixtures extended with planted registry and servicing problems.

## 2026.10.04: stick Wi-Fi and the offline assistant

**Stick Wi-Fi ("unavailable" on the Latitude 3410).** Root cause: the stick's live system stacked the stock Ubuntu `ubuntu-server` squashfs layer *on top of* SysMedic's own, so 4,890 stale stock files hid SysMedic's. That included `/etc/group` without the `netdev` group, so `wpa_supplicant` could never start ("Failed to determine group credentials") and NetworkManager had no supplicant for the Wi-Fi card.
- The stock layer's 19,580 files SysMedic lacked (Python libraries, git, vim, …) and its 129 package records are merged into the stick's system, without overwriting anything of SysMedic's. The stick now ships that layer empty (`build-iso.sh`).
- Missing system accounts restored (`syslog`, `crontab`, `landscape`), which also fixes rsyslog. The console font config is corrected (`staging/shared/etc/default/console-setup`).
- A stale `wpa_supplicant` override is removed. `staging/obsolete.txt` lists leftovers that `sysmedic-deploy` deletes.
- Verified in QEMU with a simulated Wi-Fi card: supplicant active, card ready to connect, no failed services.

**Offline assistant.** On the stick it uses `qwen2.5:3b`: the 7B took minutes to load over USB 2.0 and showed nothing meanwhile. A `thinking… m:ss` timer now shows until the first word (both editions).

## 2026.10.03: lessons from a Windows 11 audit

- The AI never reproduces credentials (passwords, security answers, keys, tokens) it finds; it reports them as found and redacted. It saves its reports in the session folder (so they're in the job record and review bundle) and flags company-managed devices.
- The self-check warns when SysMedic's own EFI partition is nearly full. The caddy's was 100% full (a 505 MB macOS recovery image), now moved to `/srv/sysmedic/macos-recovery/`.
- The version stamp covers the AI instructions and package lists as well as the shared files, dated by the last commit that changed them.

## 2026.10.02: two editions, one core

**Editions and build**
- The caddy SSD (installed, writable) and the USB stick (live, read-only) are now editions of one core.
- `build/sysmedic-deploy` installs shared files, edition files, the AI instructions, docs and package lists onto either drive. Both carry the same version stamp when their core matches.
- Plugging the stick into a running caddy collects its sessions automatically.

**Hardware testing**
- `sysmedic-hwtest` (menu 16): health report, CPU/cooling stress, RAM, disk self-test and read-only speed/surface scans, GPU, input, audio, battery and inventory. Results go into the job report.
- 42 hardware-testing packages on both editions (stress-ng, s-tui, memtester, rasdaemon, turbostat, fio, glmark2, nvtop, upower, evtest…).
- **MemTest86+ 7.00** in the boot menu of both editions, UEFI and BIOS.

**BitLocker**
- The console 2 banner lists the machine's BitLocker volumes with the exact unlock command and the recovery-key format.

**Wi-Fi**
- Fixed "no Wi-Fi" on kernel 7.0: Wi-Fi drivers are kept out of the initramfs, where newer drivers couldn't find firmware (Intel AX201 on a Latitude 3410).
- The scan reports drivers that couldn't load their firmware.
- Wi-Fi is joined with `nmtui` (menu 2, `wifi`).

**Network**
- About 60 network tools on both editions; listening/announcing services are masked.
- Public DNS fallback, and a "DNS broken" diagnosis.

**Offline AI**
- Read-only commands run immediately with full output streamed on TTY1. Enter = yes. Chained commands auto-run only if every part is read-only. Commands written in prose need an explicit `y`.
- Previously, Enter meant "No" and output was dimmed and cut to 60 lines.

**Session transcripts**
- Console transcripts, saved AI conversations, `sysmedic-note --feedback`, and `claude-review.md` bundled at shutdown.

**Self-check**
- The scan reports SysMedic's own USB link speed (a USB 2.0 port made the caddy about 10× slower in a field test).

**The merged caddy**
- Kernel 7.0 and the full toolkit.
- Credentials, old AI history, the always-on SSH and a bypassable auth gate removed.
- OpenCode's stale Go-plan login removed: it caused "Reconnect OpenCode Console". The free tier needs no login.

**Docs**
- Full documentation in `docs/`, installed on both drives (`sysmedic-help`).

## 2026.10.01: the rebuilt stick (phases 1–5)

- The stick made USB-bootable: hybrid MBR/GPT and an EFI partition. It had been unbootable from USB.
- Persistence partition; label-only mount, never the patient's disk.
- Secrets removed (API key, CraicKen token, WireGuard keys, Wi-Fi passwords).
- **Phase 1:** HWE kernel 7.0, full firmware, Secure Boot.
- **Phase 2:** the read-only triage scan.
- **Phase 3:** kernel write protection, `sysmedic-unlock` with backups, the audit trail, the offline assistant, cloud consent, OpenCode permissions.
- **Phase 4:** `sysmedic-win`: info, crashes, events, autoruns, ClamAV, BitLocker, update/hibernation/password fixes.
- **Phase 5:** job reports, job notes, the phone dashboard.

## 2026.06: v2.0–v3.0 (caddy)

- Multi-OS toolkit (28 menu options), BitLocker CLI and web unlock, Windows/Linux/macOS repair scripts.
- Stress-test and burn-in suite, partclone OS capture/restore, AI deep-analysis pipeline, GRUB theme, self-update.
