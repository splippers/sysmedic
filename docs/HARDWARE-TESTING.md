# Hardware testing (`sysmedic-hwtest`, menu 16)

On both editions. Results are appended to the session's `hwtest.log` and appear in the job report under **Hardware tests**.

| Command | What it does | Time |
|---|---|---|
| `sysmedic-hwtest report` | **Read-only health summary:** temperatures and fans (lm-sensors), CPU and throttle counters, battery wear, SMART health and temperature per disk, machine-check / ECC / PCIe errors (rasdaemon + kernel log) | seconds |
| `sysmedic-hwtest cpu [MIN]` | CPU and cooling stress (stress-ng on all cores, all methods), temperatures every 15 s, throttle count after | 5 min default |
| `sysmedic-hwtest ram` | memtester on 80% of free memory, 1 pass | minutes |
| `sysmedic-hwtest disk DEV` | SMART short self-test, then **read-only** fio: sequential read for 30 s, random 4k latency for 15 s | ~3 min |
| `sysmedic-hwtest surface DEV` | **Read-only** badblocks surface scan | hours on big disks |
| `sysmedic-hwtest gpu` | glmark2 3D benchmark without a desktop (DRM) | ~2 min |
| `sysmedic-hwtest input` | Keyboard, touchpad and buttons (libinput debug-events) | interactive |
| `sysmedic-hwtest audio` | Speakers left/right, then a 5 s microphone recording played back | ~15 s |
| `sysmedic-hwtest battery` | Design vs full capacity, cycles, adapter (upower, acpi) | seconds |
| `sysmedic-hwtest inventory` | Full inventory (inxi; serials hidden) | seconds |

**Full RAM test:** reboot and choose **Memory test (MemTest86+)** in the boot menu. On UEFI, Secure Boot must be off for MemTest86+. Run at least one full pass; errors mean faulty RAM, so test one module at a time to find it.

None of the disk tests write. They're safe on a customer's disk even while it's unlocked.

## Reading the results

| You see | It usually means |
|---|---|
| Temperature past ~95 °C, or throttling during `cpu` | Cooling: dust, dried thermal paste, a failed fan |
| Machine switches off under `cpu` | Power delivery or overheating (or a failing battery on a laptop) |
| stress-ng failure / errors | CPU, RAM or power instability |
| memtester or MemTest86+ errors | Faulty RAM (reseat, then test modules one at a time) |
| SMART FAILED, pending or uncorrectable sectors, NVMe critical warning | The disk is failing: **image it first** with ddrescue |
| Very low read speed or high latency | A dying disk, a bad cable/port, or a USB 2.0 link |
| Machine-check / WHEA / ECC errors | Hardware: CPU, RAM or motherboard. Matches Windows 0x124 crashes |
| Battery capacity under 70% of design | Worn battery |

## The tools behind it (all installed)

- **CPU / cooling:** stress-ng, s-tui, stress, sysbench, turbostat, cpupower, cpuid, msr-tools, lm-sensors (`sensors`), powertop
- **RAM:** memtester, MemTest86+ 7.00 (boot menu), rasdaemon (`ras-mc-ctl --summary`), edac-utils (`edac-util`)
- **Disks:** smartctl, nvme, fio, ioping, bonnie++, badblocks, hdparm, sdparm, sg3-utils, lsscsi, f3 (fake-capacity USB/SD check), iostat, iotop-c
- **GPU / display:** glmark2-es2-drm, glxinfo (mesa-utils), vkcube/vulkaninfo, intel_gpu_top, radeontop, nvtop, edid-decode, get-edid
- **Peripherals:** upower, acpi, evtest, libinput, speaker-test/aplay/arecord, v4l2-ctl, bluetoothctl, lsusb, lspci
- **Inventory and firmware:** inxi, hwinfo, lshw, dmidecode, fwupdmgr

**(caddy)** also has the long burn-in suite in the advanced toolkit (menu 15).

Through a USB-NVMe adapter (e.g. Realtek RTL9210), NVMe error-log entries are truncated by the bridge. Trust *media errors*, *spare* and *critical warning* instead.
