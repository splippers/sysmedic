# Testing (`sysmedic-tests`, menu 2, OpenCode slash commands, phone dashboard)

## Every test, three ways to run it

`sysmedic-tests` is one catalogue of SysMedic's hardware **and** software tests. Each runs in the background, its output is kept in the session (`tests/`), and it ends up in the job report. All are read-only for the customer's disks.

| Run it from | How |
|---|---|
| **The AI (OpenCode)** | Type `/` for the menu: `/health`, `/cpu-stress`, `/ram-test`, `/ram-modules`, `/ram-stress`, `/ram-speed`, `/disk-test`, `/surface-scan`, `/gpu-test`, `/battery`, `/inventory`, `/input-test`, `/audio-test`, `/scan`, `/network-check`, `/windows-checkup`, `/windows-events`, `/windows-registry`, `/windows-updates`, `/windows-crashes`, `/autoruns`, `/malware-scan`, plus **`/full-check`** (health, scan, battery, network, Windows check-up), **`/tests`** (the list) and **`/test-status`**. The AI starts the test, waits, and explains the result |
| **The phone** | The dashboard's **Tests** card (QR code on console 2): Run buttons, a disk picker, live output, Stop |
| **The console** | Menu 2 (`sysmedic-tests menu`): pick a test and watch it live; or `sysmedic-tests start TEST [--disk /dev/X] [--minutes N]`, `status`, `log TEST`, `wait TEST`, `stop TEST|all`, `list`, `disks` |

Tests that need a person: **input** (press keys, move and click for 60 s: the events appear on screen or the phone) and **audio** (listen to left/right, speak when it records). Long tests (RAM, surface scan, malware scan) keep running in the background; check them with `/test-status`, menu 2 → s, or the phone. A full RAM test is MemTest86+ from the boot menu.

## The hardware tools (`sysmedic-hwtest`)

On both editions. Results are appended to the session's `hwtest.log` and appear in the job report under **Hardware tests**.

| Command | What it does | Time |
|---|---|---|
| `sysmedic-hwtest report` | **Read-only health summary:** temperatures and fans (lm-sensors), CPU and throttle counters, battery wear, SMART health and temperature per disk, machine-check / ECC / PCIe errors (rasdaemon + kernel log) | seconds |
| `sysmedic-hwtest cpu [MIN]` | CPU and cooling stress (stress-ng on all cores, all methods), temperatures every 15 s, throttle count after | 5 min default |
| `sysmedic-hwtest ram` | memtester on 80% of free memory, 1 pass | minutes |
| `sysmedic-hwtest ram-modules` | Each slot: module size, type, rated/running speed, maker, part number; ECC/EDAC error counts per slot; SPD via decode-dimms where readable | 10 s |
| `sysmedic-hwtest ram-stress [MIN]` | stressapptest on 75% of free memory from every core (default 5 min from the menu/AI, 10 direct) | minutes |
| `sysmedic-hwtest ram-speed` | Bandwidth with mbw (tinymembench and lmbench for manual runs): two modules but single-channel speed = one not working | 1 min |
| `sysmedic-hwtest disk DEV` | SMART short self-test, then **read-only** fio: sequential read for 30 s, random 4k latency for 15 s | ~3 min |
| `sysmedic-hwtest surface DEV` | **Read-only** badblocks surface scan | hours on big disks |
| `sysmedic-hwtest gpu` | glmark2 3D benchmark without a desktop (DRM) | ~2 min |
| `sysmedic-hwtest input` | Keyboard, touchpad and buttons (libinput debug-events) | interactive |
| `sysmedic-hwtest audio` | Speakers left/right, then a 5 s microphone recording played back | ~15 s |
| `sysmedic-hwtest battery` | Design vs full capacity, cycles, adapter (upower, acpi) | seconds |
| `sysmedic-hwtest inventory` | Full inventory (inxi; serials hidden) | seconds |

**Firmware (`firmware`)**: BIOS version and date, Secure Boot state (and Setup Mode: keys cleared) with the setup-screen steps to turn it on, TPM presence and version, firmware updates available from LVFS (reports only; installing is the engineer's), UEFI boot entries.

**Speakers with music (`audio-music`)**: Beethoven, synthesised on the drive (nothing downloaded or bundled; all public domain), each piece chosen to show a different fault:

| Piece | Listen for |
|---|---|
| *Ode to Joy*: left only, right only, then both with a bass line | a weak or dead side |
| *Moonlight Sonata*, opening: slow octaves deep in the bass | rattle or buzz under the low notes |
| *Für Elise*: quick high notes | harsh, crackling or muffled treble |
| *Symphony No. 5*, opening: loud, sudden chords | distortion or rattle on the big notes |
| Sweep 40 Hz → 12 kHz (16 s) | the point where a loose part buzzes |

On the console (Tests menu, or `sysmedic-hwtest audio-music`) you pick pieces and change the volume while they play: **↑/↓** (or +/−) in 5% steps, **m** mute, **space** next, **q** stop. Try a suspect speaker quiet and loud: rattle often only starts above a certain volume. The phone dashboard and the AI play the whole programme (about 80 s) at 80%; `--track moonlight,fifth` and `--volume 60` choose.

**Graphics battery (`sysmedic-gfx`, also tests `gpu-info`, `gpu-display`, `gpu-bench`, `gpu-stress`, `gpu-video`):**

| Command | What it does | Time |
|---|---|---|
| `sysmedic-gfx info` | Each GPU and the **driver in use** (none = not working), the real OpenGL renderer (warns on software rendering), Vulkan devices, video memory; every display output, connected or not, with the panel's maker, model and size from its EDID | 5 s |
| `sysmedic-gfx display` | Full-screen patterns on the laptop's panel: white, black, red, green, blue, 50% grey, grey ramp, colour bars, 1-pixel checkerboard, edge frame. Dead/stuck pixels, backlight bleed, mura, banding, blur, missing edges. Space = next, q = quit, 8 s each otherwise | 90 s |
| `sysmedic-gfx bench` | On the laptop's screen: 14 glmark2 OpenGL ES scenes then 6 vkmark Vulkan scenes, with SysMedic's **live telemetry panel** (FPS with history, GPU clock and load, temperature, power, CPU load and clock, throttling). Afterwards: both scores, FPS per scene, peak temperature and power, GPU clock range, throttling, GPU hangs/resets from the kernel log | 3 min |
| `sysmedic-gfx stress [MIN]` | Burn-in: heavy scenes (terrain, refract, jellyfish, shadow) in a loop with the same panel; reports each scene's FPS first-to-last (a drop = heat throttling), peak temperature, throttling and any GPU hang | 10 min |
| `sysmedic-gfx video` | Hardware video decode/encode the GPU offers (VA-API: H.264, HEVC, VP9, AV1…) | 5 s |

On-screen tests run in a minimal display server (sway) on a spare console and switch back when done; the telemetry is read straight from the kernel (Intel, AMD, nouveau), and saved per run as `gfx/…/telemetry.csv` in the session. Started from the phone or the AI, they still appear on the laptop's screen.

**Full RAM test:** reboot and choose **Memory test (MemTest86+)** in the boot menu. On UEFI, Secure Boot must be off for MemTest86+. Run at least one full pass; errors mean faulty RAM, so test one module at a time to find it.

None of the disk tests write. They're safe on a customer's disk even while it's unlocked.

## Reading the results

| You see | It usually means |
|---|---|
| Temperature past ~95 °C, or throttling during `cpu` | Cooling: dust, dried thermal paste, a failed fan |
| Machine switches off under `cpu` | Power delivery or overheating (or a failing battery on a laptop) |
| stress-ng failure / errors | CPU, RAM or power instability |
| memtester, stressapptest or MemTest86+ errors | Faulty RAM (reseat, then test modules one at a time) |
| EDAC corrected/uncorrected count on one slot (`ram-modules`) | That slot's module is failing |
| Two modules fitted, bandwidth about half of normal (`ram-speed`) | One module or slot isn't working |
| SMART FAILED, pending or uncorrectable sectors, NVMe critical warning | The disk is failing: **image it first** with ddrescue |
| Very low read speed or high latency | A dying disk, a bad cable/port, or a USB 2.0 link |
| Machine-check / WHEA / ECC errors | Hardware: CPU, RAM or motherboard. Matches Windows 0x124 crashes |
| Battery capacity under 70% of design | Worn battery |

## The tools behind it (all installed)

- **CPU / cooling:** stress-ng, s-tui, stress, sysbench, turbostat, cpupower, cpuid, msr-tools, lm-sensors (`sensors`), powertop
- **RAM:** memtester, stressapptest, MemTest86+ 7.00 (boot menu), mbw, tinymembench, lmbench, numactl, pcm (Intel memory bandwidth), stress-ng and sysbench memory stressors, rasdaemon (`ras-mc-ctl --summary`), edac-utils (`edac-util`), dmidecode, decode-dimms (i2c-tools)
- **Disks:** smartctl, nvme, fio, ioping, bonnie++, badblocks, hdparm, sdparm, sg3-utils, lsscsi, f3 (fake-capacity USB/SD check), iostat, iotop-c
- **GPU / display:** glmark2-es2-drm, glxinfo (mesa-utils), vkcube/vulkaninfo, intel_gpu_top, radeontop, nvtop, edid-decode, get-edid
- **Peripherals:** upower, acpi, evtest, libinput, speaker-test/aplay/arecord, v4l2-ctl, bluetoothctl, lsusb, lspci
- **Inventory and firmware:** inxi, hwinfo, lshw, dmidecode, fwupdmgr

**(caddy)** also has the long burn-in suite in the advanced toolkit (menu 15).

Through a USB-NVMe adapter (e.g. Realtek RTL9210), NVMe error-log entries are truncated by the bridge. Trust *media errors*, *spare* and *critical warning* instead.

## Exchange partition on real Windows (not automated)

QEMU and the unit tests prove the partition layout and the snapshot round trip; only real Windows shows how Windows treats the drive. Do this on a **new or rewritten** stick or a rebuilt caddy (older ones have no exchange partition), with a spare stick if you can, and record results in the Dev Channel.

1. **What Windows sees.** Plug the drive into a Windows 10 and a Windows 11 machine (a USB 2 and a USB 3 port each). Pass: exactly one new drive appears, labelled `SM_EXCHANGE`, with `SYSMEDIC.ID`, `README.txt`, `collector`, `INBOX`, `EXPORT`. No "You need to format the disk" prompt, no second drive letter, no extra drive. In *Disk Management* the other partitions may show as unknown/healthy, without letters; do not touch them. Repeat with the drive in a caddy enclosure and a hub (Tosh-style) as well as direct.
2. **Nothing happens on insert.** No window opens on its own, nothing runs, nothing is written to the Windows machine's disk (check Autoplay does not launch the collector).
3. **The listing.** Run `collector\Run-SysMedic-Collector.cmd` (as administrator and as a normal user). Pass: the list of what will be gathered appears first; anything but `YES` stops with "Nothing was collected"; `-ListOnly` (run `SysMedic-Collect.ps1 -ListOnly` from PowerShell) shows the list and stops.
4. **Refusals.** On a drive without `recipient=` in `SYSMEDIC.ID`, or with `age.exe` removed: the collector stops before collecting anything and says why.
5. **Collection.** After `sysmedic-snapshot init` on SysMedic, run the collector for real. Pass: `INBOX` gets one `.smsnap.age` and one `.envelope.json`; the file is not readable as text or a zip; no new files appear in the Windows machine's temp folder or user folders; Windows shows nothing in Event Viewer beyond the PowerShell/process events. On Windows 10 and 11, with antivirus active, note any SmartScreen/Defender prompts for `age.exe` or the script.
6. **Round trip.** Boot SysMedic from the same drive on another machine; `sysmedic-snapshot list`, then `import` with the passphrase: `integrity: OK`, `raw/evidence/*.json` readable and complete, the manifest's `failures`/`omissions` match what you expect (e.g. BitLocker status empty without administrator).
7. **Boot regression after the layout change** (this is the boot behaviour that must not change): boot the same drive on a UEFI machine with Secure Boot on, a UEFI machine with it off, and a legacy-BIOS machine; and after a Windows insert/eject, boot it again.
8. **Cleanup behaviour.** Eject normally, then re-plug: no "scan and fix" prompt for `SM_EXCHANGE`; exFAT has no journal, so also check an unclean removal during an idle moment.

A pass on 1-3 and 7 is the minimum before relying on the exchange partition; 5-6 before trusting the collector on a customer's machine.
