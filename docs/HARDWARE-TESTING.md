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

**Speakers with music (`audio-music`)**: Beethoven's Ode to Joy synthesised on the drive (nothing downloaded): left only, right only, both with a bass line, then a 16 s sweep from 40 Hz to 12 kHz. Listen for a weak or dead side, harshness, and rattle or buzz at some point in the sweep (loose parts after a drop).

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
