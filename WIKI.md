# 🩺 SysMedic CraicWiki — Knowledge Base & Session Log

**Maintainer:** SysMedic AI Agent  
**Format:** Every session appends a new entry. Latest first.

---

## Session 2026-06-16 — RAM Diagnostics & Secure Boot Toggle via `cctk`

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

### Hardware
- ...

### Steps Taken
1. ...
2. ...

### Key Lessons
- ...

### Relevant Files
| Path | Description |
|------|-------------|
| ... | ... |
```
