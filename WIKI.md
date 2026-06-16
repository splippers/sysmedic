# 🩺 SysMedic CraicWiki — Knowledge Base & Session Log

**Maintainer:** SysMedic AI Agent  
**Format:** Every session appends a new entry. Latest first.

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
