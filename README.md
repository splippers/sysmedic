# 🩺 SysMedic — AI-Powered System Recovery Agent

**SysMedic** is a bootable Ubuntu 24.04 USB rescue environment powered by [OpenCode](https://opencode.chat/) AI. It provides a complete multi-OS repair toolkit for diagnosing and fixing Windows, Linux, and macOS systems — all from a single bootable USB stick, operable entirely from the framebuffer console.

---

## Quick Start

1. Boot from the USB
2. At the shell prompt, type:
   ```
   sysmedic-menu
   ```
3. Choose from 28 tools covering diagnostics, WiFi, BitLocker unlock, Windows/macOS/Linux repair

---

## What It Can Do

### BitLocker
- **CLI unlock** — paste a 48-digit recovery key, user password, or BEK file
- **Web unlock portal** — spins up a LAN webserver (port 8080). Open the page on your phone, paste the recovery key from AD/AAD, and the drive unlocks automatically. After unlock, it runs deep diagnostics.

### Windows Repair (12-20)
| Option | What it fixes |
|--------|--------------|
| 12 | Diagnose Windows — reads EVTX logs, minidumps, CBS/DISM logs, identifies BSOD BugCheck codes with explanations |
| 13 | Fix Windows Update — reset cache, clear SoftwareDistribution, DISM/SFC offline analysis, re-register WU DLLs |
| 14 | NTFS check & repair (ntfsfix) |
| 15 | Fix BCD bootloader |
| 16 | Fix NTFS boot sector |
| 17 | Reset Windows password (chntpw) |
| 18 | Restore Windows EFI boot manager |
| 19 | Mount Windows partition (read/write) |
| 20 | Recover data from Windows |

### macOS Repair (21-24)
- **Scan** — detect HFS+ and APFS volumes
- **Mount** — HFS+ read-write, APFS read-only via fsapfsmount
- **Repair** — fsck.hfsplus (HFS+), apfsck (APFS)
- **Recover** — copy user data to external drive

### Linux Repair (6-10)
- Fix GRUB bootloader
- Fix corrupt initramfs (kernel panic)
- Fix /etc/fstab (wrong UUIDs)
- Fix oversized /boot (clean old kernels)
- Chroot into Linux installation

### Utilities
- Full system diagnostic report
- Drive clone/rescue (ddrescue with retry passes)
- WiFi/WPS connection
- OpenCode AI assistant

---

## How to Build This System From Scratch

### Prerequisites
- Ubuntu 24.04 LTS Live USB (booted into "Try Ubuntu" mode)
- Internet connection (WiFi or Ethernet)
- About 15 minutes

### Step 1: Install Base Dependencies

```bash
# System updates
sudo apt-get update && sudo apt-get upgrade -y

# Essential tools
sudo apt-get install -y \
    git curl wget smartmontools lshw \
    ntfs-3g chntpw testdisk photorec \
    extundelete ddrescue \
    hfsplus hfsutils hfsprogs \
    apfsprogs libfsapfs-utils \
    dislocker \
    python3 python3-pip

# Windows EVTX log parser
sudo apt-get install -y python3-evtx libevtx-utils

# Kernel modules for HFS+
sudo modprobe hfsplus
echo "hfsplus" | sudo tee -a /etc/modules

# Networking tools
sudo apt-get install -y wpasupplicant wireless-tools nmap netcat-openbsd

# tmux + utilities
sudo apt-get install -y tmux rsync
```

### Step 2: Install OpenCode AI Agent

```bash
# Download OpenCode (check https://opencode.chat for latest version)
curl -sSf https://opencode.chat/install.sh | sh

# Or manually: download the binary for Linux amd64
# and place it in /usr/local/bin/opencode

# Configure OpenCode for SysMedic
mkdir -p ~/.config/opencode
```

Create `~/.config/opencode/config.json`:
```json
{
  "provider": "opencode-go",
  "model": "deepseek-v4-flash-free",
  "system_prompt": "You are SysMedic, an expert system recovery and hardware diagnostics AI..."
}
```

Create `~/.config/opencode/tui.json`:
```json
{
  "mouse": false,
  "dynamic_details_max_lines": 999999
}
```

### Step 3: Set Up API Key

```bash
# Create auth.json (replace with your key)
mkdir -p ~/.local/share/opencode
cat > ~/.local/share/opencode/auth.json << 'EOF'
{
  "opencode-go": {
    "type": "api",
    "key": "sk-your-api-key-here"
  }
}
EOF

cat > ~/.local/share/opencode/account.json << 'EOF'
{"user": {}, "accounts": {}}
EOF
```

### Step 4: Get the SysMedic Scripts

```bash
git clone https://github.com/splippers/sysmedic.git /opt/sysmedic

# Or if you're building from this repo:
cd /opt/sysmedic
```

### Step 5: Install Dotfiles and Symlinks

```bash
# Copy dotfiles
cp /opt/sysmedic/dotfiles/.bashrc ~/
cp /opt/sysmedic/dotfiles/.profile ~/
cp /opt/sysmedic/dotfiles/.tmux.conf ~/
cp /opt/sysmedic/dotfiles/config.json ~/.config/opencode/
cp /opt/sysmedic/dotfiles/tui.json ~/.config/opencode/

# Create launcher symlinks
ln -sf /opt/sysmedic/menu.sh /usr/local/bin/ambulance
ln -sf /opt/sysmedic/menu.sh /usr/local/bin/sysmedic-menu
ln -sf /opt/sysmedic/scripts/wifi-connect.sh /usr/local/bin/wifi

# Make scripts executable
chmod +x /opt/sysmedic/menu.sh
chmod +x /opt/sysmedic/scripts/*.sh
chmod +x /opt/sysmedic/scripts/*.py
chmod +x /opt/sysmedic/scripts/linux-repair/*.sh
chmod +x /opt/sysmedic/scripts/macos-repair/*.sh
chmod +x /opt/sysmedic/scripts/windows-repair/*.sh
chmod +x /opt/sysmedic/sysmedic-diagnose
```

### Step 6: Environment Setup

Add to `~/.bashrc` or `~/.profile`:

```bash
# Prevent OpenCode from overriding the terminal title
export OPENCODE_DISABLE_TERMINAL_TITLE=1

# Set keyboard to UK layout
export KEYBOARD=gb

# Terminal title
export PS1='\[\e]0;SysMedic\a\]\u@\h:\w\$ '
```

### Step 7: Tmux Configuration

`~/.tmux.conf`:
```
set -g mouse on
set -g status-bg colour235
set -g status-fg white
set -g status-left '#[fg=green]#S #[fg=blue]SysMedic'
set -g status-right '#[fg=yellow]%H:%M'
set -g default-terminal 'screen-256color'
```

### Step 8: Persistence (Optional but Recommended)

If you created a persistence partition when making the USB:

```bash
# Mount persistence
mkdir -p /mnt/persist
mount /dev/sdX2 /mnt/persist   # adjust device

# Create reports directory
mkdir -p /mnt/persist/reports
ln -sf /mnt/persist/reports /root/reports
```

---

## Project Structure

```
/opt/sysmedic/
├── menu.sh                       # Main recovery menu (28 options)
├── sysmedic-diagnose             # Quick diagnostic script
├── sysmedic-netcheck             # Network check script
├── .gitignore
├── scripts/
│   ├── bitlocker-unlock.sh       # CLI BitLocker unlock
│   ├── bitlocker-web-unlock.py   # Web portal BitLocker unlock + diagnostics
│   ├── bitlocker-web.sh          # Wrapper for web portal
│   ├── wifi-connect.sh           # WiFi/WPS setup
│   ├── craic-connect.sh          # Telemetry callback
│   ├── install-ollama.sh         # Local LLM installer
│   ├── sync-back.sh              # Backup sync script
│   ├── linux-repair/
│   │   ├── fix-grub.sh
│   │   ├── fix-kernel-panic.sh
│   │   ├── fix-fstab.sh
│   │   └── fix-boot.sh
│   ├── macos-repair/
│   │   ├── scan-macos.sh
│   │   ├── mount-macos.sh
│   │   ├── repair-macos.sh
│   │   └── recover-macos.sh
│   └── windows-repair/
│       ├── diagnose-windows.sh   # EVTX/minidump/CBS log collector
│       ├── repair-windows.sh     # NTFS/BCD/boot/chntpw/EFI toolkit
│       ├── repair-updates.sh     # Windows Update repair
│       └── recover-windows.sh    # Data recovery from Windows
├── dotfiles/
│   ├── .bashrc
│   ├── .profile
│   ├── .tmux.conf
│   ├── config.json               # OpenCode config
│   └── tui.json                  # OpenCode TUI config
├── usr-local-bin/
│   ├── ambulance                  # Symlink to menu.sh
│   ├── sysmedic-menu              # Symlink to menu.sh
│   └── wifi                       # Symlink to wifi-connect.sh
└── auth/
    ├── auth.sh                    # Auth setup script
    └── auth.token.example         # Template (not actual keys)
```

---

## Architecture: How the Web BitLocker Portal Works

```
┌──────────────────┐       ┌──────────────────────┐
│   Client Machine  │       │   Tech's Phone/Laptop │
│   (SysMedic USB)  │       │   (Browser)           │
│                   │       │                       │
│  python3 http.    │◄─────►│  http://192.168.x.x:  │
│  server :8080     │ HTTP  │       8080            │
│                   │       │                       │
│  dislocker -V     │       │  Paste recovery key   │
│  /dev/sdX -pKEY   │       │  → POST /unlock       │
│                   │       │                       │
│  evtxexport →     │       │  See diagnostics:     │
│  parse .evtx      │       │  • BSOD codes decoded │
│  strings →        │       │  • WU error codes     │
│  extract BugCheck │       │  • Driver issues      │
│  grep CBS.log     │       │  • Crash timeline     │
└──────────────────┘       └──────────────────────┘
```

---

## Error Code Decoders (Built In)

The diagnostics page automatically decodes these Windows error codes:

| Code | Meaning |
|------|---------|
| `0x80073701` | Component store corrupt — run DISM |
| `0xc1900101` | Feature update rollback — driver issue |
| `0x800f081f` | CBS corrupt — run SFC + DISM |
| `0x000000d1` | DRIVER_IRQL — network/storage driver |
| `0x00000133` | DPC_WATCHDOG — NVMe/SATA driver |
| `0x00000116` | VIDEO_TDR — graphics driver timeout |
| `0x00000124` | MACHINE_CHECK — CPU/cache/memory hardware |

Full decoder tables in `bitlocker-web-unlock.py` and `repair-updates.sh`.

---

## License

MIT — use freely, fork wildly, save machines.
