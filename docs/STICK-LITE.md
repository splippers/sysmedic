# SysMedic Stick Lite

A cut-down stick edition for **4 GB USB sticks**. Everything on the normal stick that matters for a visit, minus the offline AI and the heavy extras, so the image fits and still leaves room for the encrypted vault, sessions and backups.

|  | Stick | **Stick Lite** |
|---|---|---|
| Image | 1.6 GB | **about 1.0 GB** |
| Smallest stick | 8 GB | **4 GB** (about 3.7 GiB usable) |
| AI | cloud (OpenCode) + offline (Ollama, qwen2.5) | **cloud only**: needs the internet and the customer's consent |
| Triage scan, write protection, audit, job report, phone dashboard | yes | yes |
| Windows toolkit, BitLocker, registry/evtx/CBS analysis | yes | yes |
| Network tools, hotspot, `sysmedic-discover`, Wi-Fi panel | yes | yes (no Wireshark/`tshark`; `tcpdump` stays) |
| Hardware tests | all | all except the 3D benchmarks (glmark2/vkmark), the GPU load monitors (`intel_gpu_top`, `radeontop`, `nvtop`), `s-tui`, `stressapptest`, tinymembench, lmbench, bonnie++ and the kernel perf tools (`turbostat`, `cpupower`) |
| Wi-Fi, Bluetooth, Intel/AMD graphics, storage firmware | yes | yes |
| Firmware dropped | | switch/NIC ASIC (Mellanox, Marvell Prestera, Netronome), Qualcomm SoC, NVIDIA GPU (the text console still works) |
| Secure Boot, UEFI and BIOS boot | yes | yes |

Without internet there is no AI on a Lite stick: the menu's offline option and `sysmedic-ask` say so, and everything else still works. Join Wi-Fi first (menu 13); the Wi-Fi screen explains which radio to use.

## Build and write (on the build PC)

```
./sysmedic-deploy --stick-lite-image     # sysmedic-lite.iso + stick-lite-test.img (boot-test in QEMU before writing)
./sysmedic-deploy --stick-lite /dev/sdX  # build and write a 4 GB stick; its sessions are backed up and restored
```

The full stick root (`root/`) is updated first as usual; the Lite root (`root-lite/`) is a trimmed copy of it, so the two can never drift. What is removed is listed in `build/lite/purge-packages.txt` and `build/lite/purge-firmware.txt` (the kit needs a `lite` symlink to `build/lite`). The build fails if the Lite ISO grows past 1.5 GB. The same smoke test runs on the trimmed root, and the written stick is verified byte for byte against the tested image like any other.

A Lite stick is marked by `/etc/sysmedic/lite` (the edition stays `stick`, so updates and the version string match the normal stick). The boot banner and menu say "stick lite edition".

## Windows exchange partition

A Lite stick also gets the exFAT `SM_EXCHANGE` partition (256 MiB, half the normal size, taken from the end of the data partition) with the Windows evidence collector: [EXCHANGE](EXCHANGE.md). `XCHG_MIB=0` builds a Lite stick without it.

## Limits

- Sticks sold as "4 GB" vary: 3.7 GiB is typical, and very slow USB 2 sticks make the first boot slow.
- Offline AI is not available. If you want it, use the 8 GB+ stick or the caddy.
- The cloud AI works only after the customer consents and the computer is online.
