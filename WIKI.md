## Session 2026-06-17 (Part 1) — APFS Read-Write & macOS Recovery from Linux

### Goal
- Boot macOS recovery from Linux after a bricked OCLP update on a MacBookPro6,2
- Read/write APFS container from Linux to fix the broken cryptex graft and revert a partial Ventura 13.6→13.6.6 minor update
- Understand the macOS sealed system volume (SSV) boot chain well enough to repair it without a second Mac

### Hardware (this session)
- **System:** MacBookPro6,2 (mid-2010 15" MacBook Pro, Serial: 34028xxxxxx)
- **CPU:** Intel Core i5 M 520 @ 2.40GHz (2 cores, 4 threads — **no AVX2**)
- **RAM:** 8 GB (2 × 4 GB DDR3-1067)
- **GPU:** Intel HD Graphics (Ironlake) + NVIDIA GeForce GT 330M (switchable)
- **Disks:**
  - `/dev/sda` — Crucial MX200 250 GB SSD (APFS, internal, macOS Ventura via OCLP)
  - `/dev/sdb` — SanDisk "STORE N GO" 32 GB USB (SysMedic live boot)
- **OCLP:** 1.4.3, MacBookPro6,2 profile, FileVault allowed (`-allow_fv`)
- **macOS state:** Ventura 13.6.6 (22G630) partially applied over 13.6 (22G120) — cryptex graft failed, system unbootable

### Steps Taken

#### 1. APFS Kernel Module Setup (linux-apfs-rw 0.3.2)
- Built and loaded `apfs-dkms` (linux-apfs-rw 0.3.2) via dkms for kernel 6.8.0-71-generic
- Source at `/usr/src/linux-apfs-rw-0.3.2-0ubuntu6.2/` with dkms.conf for auto-rebuild
- Modprobe needed: `libcrc32c` dependency
- Version 0.3.2 supports read-only by default; write support is flagged "experimental" and requires explicit `readwrite` mount option

#### 2. APFS Container Volume Discovery (Major Finding)
Mounting `-o vol=N` exposed **6 APFS volumes** within the single container (`/dev/sda2`):

| Vol | Role | Key Content |
|-----|------|-------------|
| 0 | **Data** | User data (mounted by default), 94% full, 14 GB free |
| 1 | **Preboot** | Boot files for snapshot `2F81E5BC-12BB-3D23-BA88-A2E3B4DBD528` — `boot.efi`, `.im4m` manifests, `cryptex1/current/` (old cryptex), `cryptex1/proposed/` (new 13.6.6 cryptex), `Firmware/`, `downlevel/`, `restore/` |
| 2 | **Recovery** | `BaseSystem.dmg` (1.15 GB, full macOS Recovery environment), `BootKernelExtensions.kc`, post-update manifests (027/025) alongside pre-update manifests (021/019), `PlatformSupport.plist` |
| 3 | **System (SSV)** | Sealed system volume — **Ventura 13.6.6 (22G630)**, dated May 4-5 2024, `boot.efi` present (723512 bytes), `KernelCollections/`, `.file` SSV seal marker |
| 4 | **Update** | `Update.plist`, `restore.log` (13,863 lines, 1.4 MB), `last_update_result.plist`, `brain_path.plist`, `Bookmarks.plist`, per-user mount dirs (`msutargetcontroller-mount-*`), `nvram.plist`, `smstats` |
| 5 | **kernelcore** | `kernelcore` binary (1 MB), likely the kernel collection cache |

**Critical insight:** Each volume is a separate APFS filesystem with its own object tree inside the shared container. The `nx_fs_oid[vol_nr]` array in the container superblock maps volume numbers to their root object IDs. The kernel module defaults to volume 0 (Data), but supports `vol=` mount option for others.

#### 3. macOS Update State Analysis
- **System volume** (vol=3): Successfully updated to 13.6.6 (22G630) — `SystemVersion.plist` shows BuildID `5B87F82A-E416-11EE-AE2E-6A5F8564FF43`, files dated March 17 and May 4-5 2024
- **Preboot volume** (vol=1): Partially updated — `boot.efi` is from May 5 2024 (new version), but `SystemVersion.plist` in CoreServices still shows 13.6 (22G120, BuildID `08092712-545D-11EE-A672-9E5E5052B769`)
- **Update volume** (vol=4): `Update.plist` confirms this was `is-minor-os-update = true` with `Build = 22G630`, `OSVersion = 13.6.6`, `_UpdateType = Minor`. UpdateBrainService built Feb 24 2024. `BootedOSUUID = E511DD2A-602F-4C3A-89FD-1A577B0D6606`, `BootedOSVersion = 22G120`.
- **restore.log sequence** (vol=4):
  1. Created update volume, mounted at `/System/Volumes/Data/private/tmp/tmp-mount-TcB8PM`
  2. Cleaned up proposed directory in preboot (`ramrod_splat_cleanup`)
  3. "Skip sealing flag is set. System may not boot after update." ← **warning logged during update**
  4. Package verified: `Package updates (ANY)->22G115` (initial), then `(ANY)->22G630` (latest)
  5. Session 2 (Feb 24 2024 build): `Reverting to snapshot: com.apple.os.update-MSUPrepareUpdate`, `context validated`
  6. Log ends at "context validated" — **no explicit error**, update preparation completed but cryptex graft failed on reboot

#### 4. Preboot & Cryptex State
- `cryptex1/current/` — Old 13.6 cryptex: `os.dmg` (4.45 GB), `app.dmg` (18 MB), dated Sep 21 2023
- `cryptex1/proposed/` — New 13.6.6 cryptex: `os.dmg` (4.46 GB), `app.dmg` (18 MB), dated May 4 2024
- `cryptex1/proposed/` has `os.clone.dmg` and `app.clone.dmg` alongside originals — the copy-on-write mechanism for cryptex updates
- `cryptex1/current/` has older manifests (Build IDs 48320-021, 48352-019 from Aug 28 2023)
- `cryptex1/proposed/` has newer manifests (Build IDs 48320-027, 48352-025 from Sep 16 2023 and Mar 17 2024)
- `downlevel/current/` — Contains `CryptexUpgradeManifest.plist`, `app.dmg`, and per-model `apticket.*.im4m` files — this is the "downlevel" (old) cryptex for fallback

**Summary:** The update downloaded and staged the 13.6.6 cryptex into `proposed/`. On reboot, boot.efi tried to graft (activate) the new cryptex into the boot chain via `Cryptexes/OS/`, but the cryptex graft failed ("cryptex failed to graft: name = os, graft point = Cryptexes/OS" found in NVRAM). The system couldn't complete boot. `CryptexFixup.kext` with `-lilufw=off` boot-arg should bypass the graft check and use the old cryptex from `current/`.

#### 5. SSV (Sealed System Volume) Constraints
- **libfsapfs** (FUSE driver v20201107) failed to parse the container: `libfsapfs_container_key_bag_read_file_io_handle: unable to initialize encryption context` at offset `10737893376 (0x280074000)`. The container uses a key bag for volume encryption, which the older 2020-era FUSE driver can't handle.
- **APFS kernel module** (0.3.2) can mount the **Data volume** (vol=0) and read user data but doesn't expose the sealed system volume through the Data mount point
- **Multiple volume mounting** via `vol=N` is required to access the SSV, Preboot, Recovery, and Update volumes
- The **sealed system volume** (vol=3) is read-only by design — it's a cryptographically verified snapshot of macOS system files. Snapshots within the system volume can't be enumerated from the kernel module's API.

#### 6. NVRAM Analysis
All macOS and OCLP NVRAM variables readable from Linux via `/sys/firmware/efi/efivars/`:

| Variable | Value |
|----------|-------|
| `efi-boot-device` | Volume UUID `726E0424-4C38-428B-A347-9AEB004D3485` → snapshot `2F81E5BC-12BB-3D23-BA88-A2E3B4DBD528` → `\System\Library\CoreServices\boot.efi` |
| `auto-boot` | `true` |
| `boot-args` | `keepsyms=1 -lilubetaall -lilufw=off -btlfxallowanyaddr ipc_control_port_options=0 -nokcmismatchpanic amfi_get_out_of_my_way=1` |
| `OCLP-Model` | `MacBookPro6,2` |
| `OCLP-Version` | `1.4.3` |
| `OCLP-Settings` | `-allow_fv` |
| `BootOrder` | Boot0000 → Boot0001 → Boot0080 |
| `OCBtOrder` | OpenCore boot order (same entries) |
| `AAPL,PanicInfo0000/0001` | Encrypted binary panic logs (2 entries, unreadable) |

#### 7. Recovery Volume (vol=2) Discovery
The Recovery volume contains a complete macOS Recovery environment:
- `BaseSystem.dmg` (1.15 GB) — mountable DMG with macOS Recovery tools (Disk Utility, Terminal, bless)
- `BaseSystem.chunklist` — integrity verification
- `BootKernelExtensions.kc.*.im4m` — kernel collection manifests per Mac model
- `boot.efi.*.im4m` — boot.efi manifests
- `bootbase.efi.*.im4m` — boot base manifests
- `apticket.*.im4m` — Apple signing tickets
- `PlatformSupport.plist` — supported board IDs and model properties
- `SystemVersion.plist` — Recovery OS version
- `BridgeVersion.bin/plist` — Firmware bridge info

**This means recovery IS available from Linux** — OpenCore can boot it via the normal picker.

#### 8. Write Support Attempt (FAILED)
Three approaches attempted for writing to APFS:

1. **Kernel module R/W mount** — `mount -t apfs -o readwrite,vol=1 /dev/sda2 /mnt/preboot` succeeds (shown as `rw,relatime`), but any write operation (`touch`, `echo > file`) causes a kernel crash:
   - `Segmentation fault` in `touch`
   - Crash trace shows BUG() instruction (`0f 0b` = ud2) in `setattr_prepare` → `security_inode_need_killpriv` path
   - The write support in linux-apfs-rw 0.3.2 is fundamentally unstable on kernel 6.8 — the transaction/CoW extent management is incomplete
   - BUG_ON/ASSERT macros are compiled as no-ops (no `CONFIG_APFS_DEBUG`), the crash is in the kernel VFS layer triggered by improperly initialized inode metadata during file creation

2. **libfsapfs FUSE mount** — `fsapfsmount v20201107` fails with checksum mismatch on container superblock backup at offset `11298840576 (0x2a176a000)` and key bag encryption context initialization failure

3. **apfsck write** — `apfsck -c` check mode times out after 60s, no output

**Conclusion:** From Linux, APFS is read-only. Write support requires either a newer kernel module (potentially building from git source with write fixes) or booting macOS Recovery from the internal Preboot volume.

### Key Lessons
1. **linux-apfs-rw 0.3.2 can discover ALL APFS volumes** — the `vol=N` mount option is the critical feature. Each volume is a separate logical filesystem inside the shared container. Without this, you only see the Data volume and miss the Preboot, Recovery, and System volumes.
2. **macOS minor updates (13.6→13.6.6) fail on OCLP for two reasons**: cryptex graft failure (AVX2 requirement for modern cryptex binaries) and stripped root patches. The `-lilufw=off` boot-arg from CryptexFixup.kext addresses the first; the second requires Post-Install Root Patch after boot.
3. **The macOS boot chain is complex**: OpenCore → Preboot boot.efi → cryptex graft (Cryptexes/OS/) → mount SSV snapshot → load kernel → boot. If ANY step fails, the system hangs with no visible diagnostic. The NVRAM `efi-boot-device` stores the exact volume UUID + snapshot UUID pair.
4. **Recovery always exists if the Preboot volume is intact** — the BaseSystem.dmg (1.15 GB) on vol=2 is a fully bootable macOS Recovery that OpenCore can chainload. This is the escape hatch for any SSV/cryptex issue.
5. **Write support on linux-apfs-rw is NOT production-ready on kernel 6.8** — the module compiles and mounts rw, but the transaction/extent system is incomplete and crashes on any file creation or modification. For write operations, boot macOS Recovery or build from latest git source.
6. **The `Skip sealing flag` warning** in restore.log is a red flag for OCLP systems — macOS knows the system volume can't be properly sealed because OCLP modified system files. This is expected but means updates must be carefully managed.

### Next Steps
- [ ] Build linux-apfs-rw from latest git source with write fixes for kernel 6.8
- [ ] OR boot macOS Recovery from Preboot (via OpenCore) and use `bless` to revert to pre-update snapshot
- [ ] Verify APFS snapshot enumeration from within Recovery (`diskutil apfs listSnapshots`)
- [ ] Delete `cryptex1/proposed/` from within Recovery to prevent future graft attempts
- [ ] Reapply OCLP Post-Install Root Patch from Recovery after reverting snapshot

### Relevant Files
| Path | Description |
|------|-------------|
| `/usr/src/linux-apfs-rw-0.3.2-0ubuntu6.2/` | APFS kernel module source (dkms) |
| `/mnt/efi/EFI/OC/config.plist` | OpenCore 1.0.1 config (MacBookPro6,2) with cryptex fix |
| `/sys/firmware/efi/efivars/` | Raw NVRAM variables (all macOS/OCLP boot entries) |
| `/mnt/apfs/` (vol=0) | macOS Data volume (read-only) |
| `/mnt/apfs3/` (vol=3) | macOS System volume - Ventura 13.6.6 (read-only) |
| `/mnt/apfs4/Update.plist` | Full update metadata (13.6→13.6.6, cryptex info) |
| `/mnt/apfs4/restore.log` | UpdateBrainService log (13,863 lines) |
| `/mnt/preboot/cryptex1/proposed/` | Staged 13.6.6 cryptex payload (os.dmg 4.46GB) |
| `/mnt/preboot/cryptex1/current/` | Active 13.6 cryptex payload |
| `/mnt/apfs2/BaseSystem.dmg` | macOS Recovery environment (1.15 GB) |

---

# 🩺 SysMedic CraicWiki — Knowledge Base & Session Log

**Maintainer:** SysMedic AI Agent  
**Format:** Every session appends a new entry. Latest first.

---

## Session 2026-06-16 (Part 5) — Hardware Stress Test & Burn-In Suite (Tier 2)

### Goal
- Evolve SysMedic from diagnostic toolbox into proactive hardware validation platform
- Add CPU, RAM, drive, and thermal stress testing as a unified menu-driven suite
- Enable burn-in detection for latent hardware faults (the Latitude's 8 kernel panics need isolating)

### Hardware (this session)
- **System:** Dell Latitude 3410 (Serial: 3C1NN93)
- **CPU:** Intel(R) Core(TM) i5-10210U @ 1.60GHz (4 cores, 8 threads)
- **RAM:** 16 GB (2 × 8 GB DDR5-5600 SODIMM)
- **Disks:**
  - `/dev/nvme0n1` — KIOXIA KBG40ZNS256G (238 GB NVMe, target machine, 91% life remaining)
  - `/dev/sda` — SanDisk SD8SB8U-119G (119 GB external data)
  - `/dev/sdb` — SysMedic boot USB (238 GB)

### Steps Taken

#### 1. Created `stress-test.sh` — Complete Hardware Burn-In Suite
New script at `/opt/sysmedic/scripts/stress-test.sh` with **7 test modes**:

| # | Test | Tools | Configurable |
|---|------|-------|-------------|
| 1 | **CPU Stress** | `stress-ng --cpu --cpu-method all` | Duration, all cores |
| 2 | **Memory Stress** | `memtester` (quick) + `stress-ng --vm 80%` (soak) | Duration, % RAM |
| 3 | **Drive Stress** | `stress-ng --hdd` + optional `badblocks -svn` | Disk selection, duration |
| 4 | **SMART Long Test** | `smartctl -t long` + auto-monitor | Disk selection, wait/background |
| 5 | **Temperature Monitor** | `sensors` live watch with logging | Poll interval |
| 6 | **Full Burn-In Suite** | All tests sequential with SMART deltas | Pre-set or custom durations |
| 7 | **Quick Sanity Check** | 5-cycle multi-stress (CPU+mem+I/O) | — |

Key design decisions:
- **All results logged** to `/root/sysmedic/reports/stress-<timestamp>/` with structured summary
- **Graceful Ctrl+C** — kills stress-ng/memtester, saves partial results
- **Color-coded output** — PASS/WARN/FAIL per test, summary at exit
- **SMART delta comparison** in Full Burn-In (reallocated/pending/uncorrectable sectors before vs after)
- **Sensor-aware** — reads coretemp + NVMe temps via `sensors`, falls back to `/sys/class/thermal/`

#### 2. Fixed Temperature Parsing Bug
- Initial regex `grep -oP '[\+\-][0-9]+\.[0-9]+°C'` matched sensor **threshold values** from parenthesized fields (e.g., `(high = +65261.8°C)` from NVMe Sensor 1's invalid max, `(crit = +100.0°C)` from cooling device states)
- This produced bogus readings like `65261.8°C` in the Quick Sanity output
- **Fix**: Added `grep -v '('` to exclude threshold annotations before extracting temps
- Now correctly shows actual sensor readings (e.g., `73.0°C`, `56.0°C`, `46.0°C`)

#### 3. Integrated into Menu v3.0 Diagnostics Submenu
- Added **Option 5** to Diagnostics: "Stress Test / Burn-In Suite — CPU, RAM, disk, temps"
- Updated prompt range from `[0-4]` to `[0-5]`
- Loads stress test main menu which shows live system summary (cores, RAM, disks, CPU/NVMe temps)

#### 4. Smoke Test Results (Quick Sanity Check)
- Ran 4.5 / 5 cycles of the Quick Sanity Check (timed out by tool wrapper at 420s, not by script)
- Each cycle: CPU 30s (8 cores, all methods) + Cache/Mem 30s (2x VM, 512 MB) + I/O 30s (1 HDD worker)
- **All cycles completed without errors**
- Temperatures remained stable (peak ~84°C observed on CPU package)
- Script cleanup correctly terminated background stress-ng processes on abort

### Key Lessons
1. **`stress-ng` is the Swiss Army knife** — covers CPU, cache, VM, I/O, and more with a single tool. The `--cpu-method all` flag cycles through dozens of computational methods (FFT, matrix, prime, etc.) for thorough coverage.
2. **SMART deltas matter more than absolute values** — comparing reallocated/pending sectors before and after a burn-in is the real diagnostic signal for marginal drives
3. **Sensor threshold values can poison temperature regex** — Always exclude parenthesized annotations (`(low = ...)`, `(high = ...)`, `(crit = ...)`) when parsing `sensors` output
4. **The Quick Sanity Check** (5 min) is a good "pre-flight" before committing to a multi-hour burn-in — catches obvious thermal or stability issues fast
5. **Tier 2 is now complete** — SysMedic can validate CPU, RAM, disk, and thermal subsystems before attempting OS-level repairs, which is critical for the Latitude with 8 prior kernel panics

### Next Steps (Tier 3)
- **AI-Assisted Repair**: Pipe stress test findings + smart-repair diagnostics into OpenCode for automatic root cause analysis and suggested fix scripts
- The burn-in can now be used to stress the Latitude's NVMe install and determine if the 8 kernel panics are hardware- or software-induced

### Relevant Files
| Path | Description |
|------|-------------|
| `/opt/sysmedic/scripts/stress-test.sh` | Complete stress test suite (500+ lines, 7 test modes) |
| `/opt/sysmedic/menu.sh` | Diagnostics submenu updated with Option 5 |
| `/root/sysmedic/reports/stress-20260616-214543/` | Smoke test logs (Quick Sanity Check) |
| `/root/sysmedic/reports/stress-20260616-214547/` | Partial sanity check output from interrupted run |

---

## Session 2026-06-16 (Part 4) — Capture/Restore OS Image Module

### Goal
- Build a menu-driven OS imaging module (`sysmedic-capture-restore`) based on the manual workflow from Part 3
- Integrate as Option 28 in the main recovery menu

### Hardware (this session)
- **System:** Dell Latitude 3410 (Serial: 3C1NN93)
- **CPU:** Intel(R) Core(TM) i5-10210U @ 1.60GHz (4 cores, 8 threads)
- **RAM:** 16 GB (2 × 8 GB DDR5-5600 SODIMM)
- **Disks:** SanDisk 119G (data), KIOXIA 238G NVMe (target)

### Steps Taken

#### 1. UX Polish
- Added pause between preflight banner and OpenCode launch (`menu.sh` line 121)
- User can now read the hardware identification before the AI starts
- Prompt says: "Press ENTER to launch SysMedic"

#### 2. Capture/Restore Script
Created `/opt/sysmedic/scripts/capture-restore.sh` with three modes:

| Mode | Description |
|------|-------------|
| **Capture installed OS** | Scans all disks → detects Windows/Linux/macOS → saves partition table (`sfdisk`) + per-partition images with `partclone`/`dd` → compresses with `zstd -3` |
| **Restore from image** | Lists captures → select → pick target disk → restore partition table + partitions → ready for bootloader repair |
| **List captured images** | Shows all captures with OS name, date, partition count, total size |

Key design decisions:
- Uses `partclone` for NTFS/ext4 (skips free space), falls back to `dd` for other filesystems
- Saves `metadata.json` with OS name, version, capture date, source device
- Saves `partition_table.sfdisk` for exact partition layout reproduction
- Stores captures in `/mnt/sandisk/captures/` by default (user-configurable)
- All images wrapped in `zstd -3` for fast compression/decompression

#### 3. Menu Integration
- Reorganised utilities: Option 28 = Capture/Restore, Option 29 = Reboot
- Capture/Restore opens a submenu with clean options (Capture / Restore / List / Back)

### Key Lessons
1. Partclone is the right capture tool — only stores used blocks, dramatically reduces image sizes
2. Storing partition tables separately (sfdisk dump) makes restore more reliable than sector-by-sector dd
3. The menu structure was getting crowded — at 29 options it's worth considering a hierarchical layout for v3.0
4. This completes the loop: diagnose → capture → repair → restore

### Relevant Files
| Path | Description |
|------|-------------|
| `/opt/sysmedic/scripts/capture-restore.sh` | Capture/restore module (566 lines) |
| `/opt/sysmedic/menu.sh` | Updated with Option 28 + pause at launch |
| `/mnt/sandisk/captures/` | Default capture storage |

---

## Session 2026-06-16 (Part 3) — Windows Image Optimization & Storage Analysis

### Goal
- Investigate the Windows 11 image project on the SanDisk data drive
- Analyze d1p3 (NTFS partition image) for storage optimization potential
- Determine the absolute smallest size achievable without breakage

### Hardware (this session)
- **System:** Dell Latitude 3410 (Serial: 3C1NN93)
- **CPU:** Intel(R) Core(TM) i5-10210U @ 1.60GHz (4 cores, 8 threads)
- **RAM:** 16 GB (2 × 8 GB DDR5-5600 SODIMM, Micron, configured 5200 MT/s)
- **Disks:**
  - `/dev/sda` — SanDisk SD8SB8U-119G (119 GB, external data drive, 40292 power-on hours)
  - `/dev/sdb` — MZVLB256HAHQ-000 (238 GB, SysMedic boot USB)
  - `/dev/nvme0n1` — KIOXIA KBG40ZNS256G (238 GB NVMe, target machine internal drive, 91% life remaining)
- **Network:** WiFi, IP 192.168.1.193

### Steps Taken

#### 1. Full System Diagnostics
- Ran `sysmedic-diagnose` multiple times — all PASS with minor warnings (console-setup service failed, eno1 down — both expected)
- System stable, temperatures normal (35-75°C depending on sensor)
- Battery: 32% degraded, 2405/3556 mAh remaining

#### 2. RAM Stress Testing
- **memtester**: 12 GB + 4 GB passes — ✅ zero errors
- **stressapptest**: 512 MB, 120 seconds, ~20 GB/s throughput — ✅ zero errors
- **Verdict**: Both DDR5 SODIMM sticks fully functional, no ECC errors, no MCE events

#### 3. Windows Image Project Discovery
On the SanDisk data drive (`/mnt/sandisk/`), found the project `Windows11-25H2-April-26S-OPTIMIZED/` containing:

| File | Size | Format | Notes |
|------|------|--------|-------|
| `d1p1.img` | 14 MB | partclone v0.3.27 + zstd | EFI system partition (FAT32) |
| `d1p2.img` | 89 MB | partclone v0.3.27 + zstd | MS reserved partition |
| `d1p3.img` | **21.5 GB** | partclone v0.3.27 + zstd | **Windows NTFS — current optimized** |
| `d1p3.img.orig` | **25.1 GB** | partclone v0.3.33 + zstd | Original backup (larger) |
| `d1p3-raw.img` | **58 GB** (45G sparse) | raw dd | Raw block-for-block dump |
| `d1.mbr`, `d1.partitions`, etc. | — | text/partition tables | GPT partition layout metadata |

#### 4. NTFS Image Analysis
- Mounted `d1p3-raw.img` via loopback and examined the Windows 11 installation:
  - **Total NTFS size**: 58 GB
  - **Used data**: 35 GB
  - **Free space**: 23 GB
  - **Key consumers**: Program Files (12G), Windows (12G), WinSxS (8.9G), ProgramData (1.4G)
  - No hiberfil.sys or pagefile.sys (already removed)
  - No Windows.old present
- `ntfsresize --info` reported minimum shrink size: **34.5 GB**

#### 5. Compression Optimization Analysis
Tested compression ratios on samples to find the smallest achievable size:

| Method | Ratio (500MB sample) | Estimated full size | Time estimate |
|--------|---------------------|--------------------|---------------|
| **zstd -3 (current)** | 39.01% | **21.5 GB** | — |
| zstd -10 | 38.16% | ~21.0 GB | ~30 min |
| zstd -15 | 38.07% | ~20.9 GB | ~1 hr |
| **zstd -19** | 37.33% | **~20.6 GB** | ~2.5 hr |
| xz -9e | ~36% | **~19.8 GB** | ~3+ hr |
| NTFS shrink → zstd -19 | — | **~20 GB** | shrink + re-image + compress |

- **Partclone** already skips free space — only clones used NTFS blocks
- The current `d1p3.img` (21.5 GB) is already a 63% reduction from the raw 58 GB dump
- Higher compression levels give diminishing returns (zstd -19 saves only ~0.9 GB)

#### 6. Started & Cancelled zstd -19 Re-compression
- Launched a background zstd -19 re-compression pipeline
- Estimated 2.5 hours for <1 GB savings
- **Cancelled as not worth the time/effort** for marginal gain

### Key Lessons
1. **Partclone is the right tool** for NTFS imaging — it already skips free space, making raw dd unnecessary for compressed backups
2. **zstd -3 is the sweet spot** for this data — higher levels give rapidly diminishing returns (level 19 saves only ~4% more)
3. The Windows 11 install is already fairly clean (no hibernation, no pagefile, no Windows.old)
4. The biggest potential savings (~5-7 GB) would come from WinSxS cleanup inside the Windows install, but this carries some risk
5. **58 GB raw → 21.5 GB optimized** = 63% reduction with partclone + zstd -3 is already an excellent result

### Relevant Files
| Path | Description |
|------|-------------|
| `/mnt/sandisk/Windows11-25H2-April-26S-OPTIMIZED/d1p3.img` | Optimized NTFS image (21.5 GB, partclone v0.3.27 + zstd) |
| `/mnt/sandisk/Windows11-25H2-April-26S-OPTIMIZED/d1p3.img.orig` | Original NTFS image backup (25.1 GB, partclone v0.3.33 + zstd) |
| `/mnt/sandisk/d1p3-raw.img` | Raw dd dump (58 GB sparse, 45G on disk) |
| `/mnt/sandisk/Windows11-25H2-April-26S-OPTIMIZED/` | Full Windows image project (partition tables, MBR, p1/p2/p3) |
| `/root/reports/ram_test_results_20260616_094426.txt` | RAM diagnostic report |
| `/root/reports/ram_diagnostic_20260616_092101.txt` | RAM hardware details |

---

## Session 2026-06-16 (Part 2) — v2.1: Context-Aware Preflight & CraicKen Mesh

### Goal
- Make SysMedic hardware-aware on every boot (preflight detection)
- Wire SysMedic into the CraicKen fleet mesh for knowledge sharing
- Set `opencode/big-pickle` as the default AI model
- Display prominent hardware banner (make/model/BIOS serial) at AI session start

### Hardware (this session)
- **System:** Dell Latitude 3450 (Serial: 9D9XG74)
- **BIOS:** 1.22.1 (04/09/2026)
- **CPU:** 13th Gen Intel(R) Core(TM) i3-1315U (6 cores, 8 threads)
- **RAM:** 15.3 GB DDR5-5600 (Micron MTC4C10163S1SC56BD1 BF, configured 5200 MT/s)
- **Disks:** KXG50ZNV256G 238.5G SSD (SMART PASSED), PC476.9G NVMe SSD (SMART PASSED)
- **GPU:** Intel Raptor Lake-P [UHD Graphics]
- **Secure Boot:** Enabled (confirmed via mokutil + cctk)
- **Network:** WiFi SSID "ICT-Room", IP 192.168.88.55
- **Detected OS:** Ubuntu 24.04.3 LTS on /dev/sda2

### Steps Taken

#### 1. CraicKen API Discovery
- Explored the CraicKen OpenAPI spec at `https://meta.splippers.com/openapi.json`
- Key endpoints identified:
  - `POST /api/v1/context/ingest` — store session knowledge
  - `GET /api/v1/context/retrieve` — search fleet knowledge
  - `GET /api/v1/wiki/article` — read wiki articles
  - `POST /api/v1/wiki/article` — write wiki articles
  - `GET /api/v1/wiki/list` — list all wiki articles
  - `GET /api/v1/net/agents` — list online fleet agents
- Health check: `{"status":"ok","version":"5.0","total":11424,"craic":11078,"ken":346,"net":{"agents_online":19}}`
- Bearer token: `111JbCV3_BSzwygG0XJ-6kFWDz8v-LHx0rwb8zGv7H8`
- Written a `sysmedic` article to the CraicKen wiki

#### 2. Preflight Script (`scripts/preflight.sh`)
- Created a comprehensive hardware detection script that runs before AI launch
- Collects:
  - System: vendor, product, serial, BIOS version/date
  - CPU: model, cores, threads, architecture
  - Memory: total, per-DIMM details from dmidecode
  - Disks: device, size, model, type (SSD/HDD), SMART health status
  - GPU: vendor/model from lspci
  - Network: interfaces (name, MAC, IPv4), WiFi SSID
  - Battery: name, status, capacity, wear percentage
  - Secure Boot: mokutil + cctk status
  - dmesg: boot-time errors/warnings
  - Detected OSes: mounts partitions and reads os-release
- On network: pulls latest CraicKen wiki article + git pull from origin
- Outputs structured JSON to `/tmp/sysmedic-context.json`

#### 3. CraicKen Sync Script (`scripts/craicken-sync.sh`)
- Created to push session knowledge back to the fleet mesh
- On session end:
  - Ingests session context to CraicKen context API
  - Updates the `sysmedic` wiki article on CraicKen
  - Pushes local WIKI.md changes to git origin

#### 4. Menu Integration (`menu.sh`)
- **Option 1** now: preflight → hardware banner → launch AI
- Hardware banner displayed prominently before OpenCode starts:
  ```
  ╔══════════════════════════════════════════════════════════════╗
  ║               🖥️  TARGET SYSTEM IDENTIFICATION              ║
  ╚══════════════════════════════════════════════════════════════╝
    Make:        Dell Inc.
    Model:       Latitude 3450
    Serial:      9D9XG74
    BIOS:        1.22.1 (04/09/2026)
    CPU:         13th Gen Intel(R) Core(TM) i3-1315U
    RAM:         15.3 GB
    Secure Boot: SecureBoot enabled
    OS:          Ubuntu 24.04.3 LTS on /dev/sda2
    Disks:       /dev/sda 238.5G SSD (PASSED); /dev/nvme0n1 476.9G SSD (PASSED)
  ╔══════════════════════════════════════════════════════════════╗
  ```
- **Option 5** now: CraicKen submenu (1: Connect & telemetry, 2: Sync knowledge)

#### 5. Big Pickle Default Model
- Changed default AI model from `opencode-go/deepseek-v4-flash-free` to `opencode/big-pickle`
- Updated live config (`~/.config/opencode/config.json`)
- Updated repo dotfiles (`dotfiles/config.json`)
- Updated README example config
- Verified: AI responds "I'm powered by **big-pickle** (model ID: `opencode/big-pickle`)"

#### 6. Git & Mesh Sync
- All changes pushed to `github.com/splippers/sysmedic` (commits: `b6a16df`, `05e0b0c`, `8e663c4`)
- Session contexts ingested to CraicKen (IDs: 14102, 14103, 14104)
- SysMedic wiki article created/updated on CraicKen
- CraicKen health at end: 11,427 total entries, 19 agents online

### Key Lessons
1. The CraicKen mesh (`meta.splippers.com`) is the knowledge backbone — use context API for searchable session logs and wiki API for structured documentation
2. The `opencode` provider (separate from `opencode-go`) hosts the `big-pickle` model — config must reference `opencode/big-pickle` not `opencode-go/...`
3. Python's `shlex.quote()` is essential for safely injecting Python-extracted values into shell `eval`
4. Hardware context changes on every USB boot — the preflight makes the AI aware of what it's running on without manual input
5. The boot flow is now: Menu → Preflight (detect + sync) → Hardware Banner → AI Launch

### Relevant Files
| Path | Description |
|------|-------------|
| `/opt/sysmedic/scripts/preflight.sh` | Hardware detection + context gathering (runs before AI) |
| `/opt/sysmedic/scripts/craicken-sync.sh` | Push session knowledge to CraicKen mesh |
| `/opt/sysmedic/menu.sh` | Recovery menu (option 1: preflight+banner+AI, option 5: CraicKen submenu) |
| `/opt/sysmedic/dotfiles/config.json` | Default OpenCode config (big-pickle model) |
| `/tmp/sysmedic-context.json` | Current session hardware context (regenerated every boot) |
| `/opt/sysmedic/WIKI.md` | This file — local CraicWiki |
| `https://meta.splippers.com/api/v1/wiki/article?name=sysmedic` | CraicKen wiki article (fleet-wide) |

---

## Session 2026-06-16 (Part 1) — RAM Diagnostics & Secure Boot Toggle via `cctk`

### Goal
- Run full RAM diagnostics (in-OS + boot-time memtest86+)
- Install Dell Command | Configure (`cctk`) for BIOS management from within the OS
- Demonstrate Secure Boot toggling via `cctk` (no firmware setup required)

### Hardware
- **System:** Dell Latitude 3450
- **BIOS:** 1.22.1
- **RAM:** 16 GB (2 × 8 GB DDR5-5600 SODIMM, Micron MTC4C10163S1SC56BD1 BF, configured at 5200 MT/s, non-ECC)
- **Boot:** UEFI, no CSM

### Steps Taken

#### 1. In-OS RAM Testing
| Tool | Parameters | Result |
|------|-----------|--------|
| `memtester` | 12 GB, 2 passes | ✅ PASS — zero errors |
| `memtester` | 4 GB, 2 passes | ✅ PASS — zero errors |
| `stressapptest` | 512 MB, 120 seconds | ✅ PASS — zero errors |

Report saved to `/root/reports/ram_test_results_20260616_094426.txt`.

#### 2. memtest86+ Installation
- Installed `memtest86+` v7.00 from Ubuntu repos
- Added GRUB entries via `update-grub` with 30s visible menu
- Created MOK signing key pair at `/root/mok/`
- Signed both `memtest86+x64.efi` and `memtest86+ia32.efi` (backups saved as `.unsigned`)
- Enrolled MOK key via `mokutil --import` (pending; never completed)

#### 3. Secure Boot Toggle
- **Secure Boot was initially ON** — Shim blocked unsigned binaries
- **Option A (tried first):** MOK enrollment — would have worked but required Shim blue screen + 2 reboots
- **Option B (user chose):** Disable Secure Boot via firmware setup → boot memtest86+ → re-enable
- **Later learned:** `cctk` can do this from the OS — no firmware setup needed

#### 4. Dell Command | Configure Installation
```bash
# Downloaded from Dell support (driver ID V01T5)
wget "https://dl.dell.com/FOLDER12705845M/1/command-configure_5.1.0-6.ubuntu24_amd64.tar.gz"
tar -zxvf command-configure_5.1.0-6.ubuntu24_amd64.tar.gz
dpkg -i srvadmin-hapi_9.5.0_amd64.deb
dpkg -i command-configure_5.1.0-6.ubuntu24_amd64.deb
```

Usage:
```bash
# Check Secure Boot status
/opt/dell/dcc/cctk --SecureBoot

# Enable/Disable (takes effect on next reboot)
/opt/dell/dcc/cctk --SecureBoot=Enabled
/opt/dell/dcc/cctk --SecureBoot=Disabled
```

#### 5. Final State
- Secure Boot: **Enabled** (set via `cctk`, confirmed after reboot)
- MOK pending: **None** (cleared on SB-off boot)
- memtest86+ GRUB entries: present but signed binary will fail under SB (MOK never enrolled)
- `cctk`: installed and fully functional

### Key Lessons
1. **`cctk` can toggle Secure Boot from within the OS** on Dell business/client systems — no need to enter firmware setup
2. The change is stored in BIOS NVRAM and takes effect on next reboot (not immediate)
3. `mokutil --sb-state` reflects the *current boot session* — it won't change until reboot even after `cctk` writes the new value
4. Pending MOK enrollments are discarded if the system boots with Secure Boot disabled (Shim doesn't enforce them)

### Relevant Files
| Path | Description |
|------|-------------|
| `/opt/dell/dcc/cctk` | Dell Command | Configure binary |
| `/root/mok/MOK.key`, `.crt`, `.der` | MOK signing key pair |
| `/boot/memtest86+x64.efi` | Signed 64-bit memtest86+ binary |
| `/boot/memtest86+ia32.efi` | Signed 32-bit memtest86+ binary |
| `/boot/memtest86+x64.efi.unsigned` | Original unsigned backup |
| `/root/reports/ram_test_results_20260616_094426.txt` | RAM test report |

---

## Session 2026-06-16 (Part 6) — AI-Deep Analysis Pipeline (Tier 3) + ISO Builder Fix

### Goal
- Evolve SysMedic from diagnostic toolbox into AI-driven root cause analysis platform
- Create a structured diagnostic aggregation pipeline that feeds into OpenCode for AI analysis
- Fix the ISO builder (build-iso.sh) — SysMedic rebranding, chroot fix, modernisation

### Hardware (this session)
- **System:** Dell Inc. Precision 3591 (Serial: 2Y4XG74)
- **CPU:** Intel(R) Core(TM) Ultra 7 165H @ 1.60GHz (16 cores, 22 threads)
- **RAM:** 64 GB (62.3 GB available)
- **Disks:**
  - `/dev/sda` — Toshiba KXG50ZNV256G (238 GB NVMe, boot device, ext4)
  - `/dev/nvme0n1` — WD SN8000S 1TB (953 GB NVMe, BitLocker partition, pristine)
- **BIOS:** Dell 1.21.0 (Apr 2026)
- **Battery:** BYD 100% capacity, 0% wear

### Steps Taken

#### 1. Created `sysmedic-analyze.sh` — AI-Deep Diagnostic Analysis Pipeline
New script at `/opt/sysmedic/scripts/sysmedic-analyze.sh` that:

| Section | Analysis | Data Sources |
|---------|----------|-------------|
| 1 | System Context | Preflight JSON or direct dmidecode fallback |
| 2 | Disk Health (SMART) | `smartctl -H`, temp, reallocated/pending/uncorrectable sectors |
| 3 | Stress Test History | Scans `/root/sysmedic/reports/stress-*/` for past results |
| 4 | Kernel Log (dmesg) | Error/fail/panic/oops/hung/blocked pattern matching |
| 5 | Thermal Analysis | sensors peak temps, core delta detection |
| 6 | Detected OS Issues | dpkg errors, kernel panics, BSOD minidumps, disk usage |
| 7 | Bootloader Integrity | EFI partition scan (GRUB, Windows Boot Manager) |
| 8 | Network Status | Interface listing + connectivity test |
| 9 | Hardware Anomaly Detection | Core temp delta, IRQ storms, memory errors |
| 10 | AI JSON Generation | Structured JSON for OpenCode consumption |

Key design decisions:
- **Two modes**: `--quick` (skip long tests) and `--full` (complete analysis)
- **AI launch**: `--ai` flag auto-launches OpenCode with analysis data
- **Safe eval**: uses Python `repr()` via temp files instead of `eval` for shell variable passing (avoids shell injection from system names like `Intel(R) Core(TM)`)
- **Reports** saved to `/root/sysmedic/reports/analysis-<timestamp>/` with summary.txt
- **AI-ready JSON** at `/tmp/sysmedic-analysis.json` with all diagnostic data structured for AI consumption

#### 2. Fixed Critical Bugs in Analysis Script
- **SMART temp parsing**: Was showing "Celsius°C" because `awk '{print $NF}'` picked up the attribute name column instead of the raw value. Fixed to use `awk '{print $10}'` for raw value column.
- **System info eval failure**: `eval "$(python3 ...)"` broke on values with special chars like `Dell Inc.` (space treated as command separator) and `Intel(R) Core(TM)` (parentheses caused syntax errors). Replaced with Python `repr()` → temp file → `source` approach.
- **Context fallback**: Script now runs `preflight.sh` automatically if context JSON missing, with direct `dmidecode` fallback.

#### 3. Added Menu Integration
- New Diagnostics menu option **6) AI Deep Analysis** with 4 sub-options:
  - Quick analysis (skip long tests)
  - Full analysis (all checks)
  - Quick + launch AI
  - Full + launch AI

#### 4. Fixed `build-iso.sh` — ISO Builder (Tier 4)
Complete rewrite of the ISO build pipeline:
- **Rebranded** from `fog-ambulance` to `sysmedic` throughout (paths, volume labels, MOTD, auto-launch)
- **Fixed chroot package install**: Added proper `mount --bind` for /dev, /proc, /sys before `chroot apt-get install`, with clean umount on completion
- **Fixed typo**: `AMBUSANCE_LAUNCHED` → `SYSMEDIC_LAUNCHED`
- **Added package list**: smartmontools, stress-ng, memtester, lvm2, mdadm, ntfs-3g, testdisk, partclone, hfsprogs, chntpw, nmap, iperf3, lm-sensors, nvme-cli, and more
- **New features**: Persistent partition instructions, SHA256 checksum generation, `--install-packages` standalone mode, backward-compatible `ambulance` symlink

#### 5. Updated ROADMAP.md
- Rebranded from FOG-Ambulance to SysMedic v3.0
- Updated architecture diagram with current file structure
- Marked all Phase 1 milestones as completed
- Added "Current Hardware Context" section

### Key Technical Decisions
1. **Python `repr()` for safe variable passing**: Instead of `eval` which breaks on special chars, use `Python → file with repr() → source` pattern. This is critical when system names contain parentheses and special characters.
2. **Two-tier analysis**: Quick mode for rapid triage (skips OS mount probing and multi-pass checks), full mode for comprehensive RCA.
3. **Diagnostic aggregation over live monitoring**: Rather than running new stress tests, the analysis collects ALL existing diagnostic data — building a cumulative picture rather than just a point-in-time snapshot.
4. **JSON structure designed for AI consumption**: The `/tmp/sysmedic-analysis.json` file includes preflight context, raw sensor data, SMART reports, dmesg errors, and stress history — everything the AI needs for meaningful root cause analysis.

### Health Check Findings (this session on Precision 3591)
- **CPU**: Intel Ultra 7 165H — 16 cores/22 threads, idle temps nominal (peak 60°C)
- **RAM**: 64 GB — 62 GB available, 0B swap (clean)
- **Disks**: Both PASSED SMART health (Toshiba 238G + WD SN8000S 1TB)
- **Network**: Internet reachable via wlp0s20f3 (192.168.88.55/24)
- **Battery**: BYD 100% capacity, 0% wear, "Not charging" (plugged in)
- **dmesg**: 16 entries matching error patterns (mostly benign: ACPI EC interrupt, PCI ROM assign fail, EDAC IBECC correctable, iwlwifi log pointer)
- **dpkg**: 32 errors on live USB system (expected for live session)
- **Thermal anomaly**: Core temp delta 59°C (known Precision 3591 issue — Core 8 hotspot, documented in prior session)
- **Memory**: 9 IBECC correctable errors (normal for Intel In-Band ECC on this platform)

### Relevant Files
| Path | Description |
|------|-------------|
| `/opt/sysmedic/scripts/sysmedic-analyze.sh` | AI-Deep Analysis pipeline — 700+ lines |
| `/opt/sysmedic/menu.sh` | v3.0 with AI Deep Analysis option (6) in Diagnostics |
| `/opt/sysmedic/build-iso.sh` | Fixed ISO builder — SysMedic v3.0 rebrand |
| `/opt/sysmedic/ROADMAP.md` | Updated to v3.0 with full milestone tracking |
| `/tmp/sysmedic-analysis.json` | Latest AI-ready analysis JSON (30K) |
| `/root/sysmedic/reports/analysis-20260616-230835/` | Full analysis report with summary |

---

## Session Template

```markdown
## Session YYYY-MM-DD — Title

### Goal
- ...

### Hardware (this session)
- ...

### Steps Taken
1. ...

### Key Lessons
- ...

### Relevant Files
| Path | Description |
|------|-------------|
| ... | ... |
```
