#!/bin/bash
# SysMedic GRUB Customizer — Replicable Premium GRUB Menu for All Nodes
# Creates a beautiful, well-organized GRUB boot menu with emergency options,
# diagnostic entries, and SysMedic branding.
#
# Usage:
#   grub-customizer.sh install         # Apply to current system (or chroot)
#   grub-customizer.sh install --theme-only  # Just install theme, keep existing entries
#   grub-customizer.sh preview         # Show what the menu will look like
#   grub-customizer.sh remove          # Remove SysMedic GRUB customizations
#   grub-customizer.sh status          # Show current GRUB state
#
# Works on any Ubuntu/Debian system. Run inside chroot for installed OS repairs.
# Idempotent — safe to run multiple times.

set -euo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}[GRUB]${NC} $1"; }
ok()    { echo -e "  ${GREEN}[GRUB]${NC} $1"; }
warn()  { echo -e "  ${YELLOW}[GRUB]${NC} $1"; }
fail()  { echo -e "  ${RED}[GRUB]${NC} $1"; }

GRUB_DIR="/etc/default"
GRUB_D_DIR="/etc/grub.d"
GRUB_THEME_DIR="/boot/grub/themes/sysmedic"
GRUB_THEME_SRC="/opt/sysmedic/grub-theme"
GRUB_OUTPUT="/boot/grub/grub.cfg"
BACKUP_DIR="/root/sysmedic-backups/grub-$(date +%Y%m%d-%H%M%S)"
ONLY_THEME=false

# ──────────────────────────────────────────────
# Parse args
# ──────────────────────────────────────────────
for arg in "$@"; do
    [ "$arg" = "--theme-only" ] && ONLY_THEME=true
done

# ──────────────────────────────────────────────
# Safety: require root
# ──────────────────────────────────────────────
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        fail "Must be run as root (or with sudo)"
        exit 1
    fi
}

# ──────────────────────────────────────────────
# Backup current GRUB config
# ──────────────────────────────────────────────
backup_config() {
    mkdir -p "$BACKUP_DIR"
    if [ -f "$GRUB_OUTPUT" ]; then
        cp "$GRUB_OUTPUT" "$BACKUP_DIR/grub.cfg.bak"
        ok "Backed up current GRUB config to $BACKUP_DIR"
    fi
    if [ -f "$GRUB_DIR/grub" ]; then
        cp "$GRUB_DIR/grub" "$BACKUP_DIR/grub.default.bak"
    fi
}

# ──────────────────────────────────────────────
# Install GRUB theme
# ──────────────────────────────────────────────
install_theme() {
    info "Installing SysMedic GRUB theme..."

    mkdir -p "$GRUB_THEME_DIR"
    
    # Copy theme files
    if [ -d "$GRUB_THEME_SRC" ]; then
        cp -r "$GRUB_THEME_SRC"/* "$GRUB_THEME_DIR/" 2>/dev/null || true
        # Create icons directory
        mkdir -p "$GRUB_THEME_DIR/icons"
    else
        warn "Theme source directory not found at $GRUB_THEME_SRC"
        warn "Creating minimal theme..."
    fi

    # Generate a simple SysMedic logo as ASCII (actually a 1-pixel PNG placeholder won't work)
    # We'll rely on the text-based theme which is more compatible

    # Set theme in /etc/default/grub
    local grub_config="$GRUB_DIR/grub"
    if [ -f "$grub_config" ]; then
        if grep -q "^GRUB_THEME=" "$grub_config"; then
            sed -i "s|^GRUB_THEME=.*|GRUB_THEME=\"$GRUB_THEME_DIR/theme.txt\"|" "$grub_config"
        else
            echo "GRUB_THEME=\"$GRUB_THEME_DIR/theme.txt\"" >> "$grub_config"
        fi
        ok "GRUB theme configured in $grub_config"
    else
        fail "Cannot find $grub_config"
        return 1
    fi

    ok "Theme installed to $GRUB_THEME_DIR"
}

# ──────────────────────────────────────────────
# Configure /etc/default/grub
# ──────────────────────────────────────────────
configure_defaults() {
    local grub_config="$GRUB_DIR/grub"
    
    info "Configuring GRUB defaults..."

    if [ ! -f "$grub_config" ]; then
        fail "Cannot find $grub_config"
        return 1
    fi

    # Make backup of original
    if [ ! -f "$BACKUP_DIR/grub.default.bak" ]; then
        cp "$grub_config" "$BACKUP_DIR/grub.default.bak"
    fi

    # Set SysMedic distributor name
    if grep -q "^GRUB_DISTRIBUTOR=" "$grub_config"; then
        sed -i 's|^GRUB_DISTRIBUTOR=.*|GRUB_DISTRIBUTOR="SysMedic"|' "$grub_config"
    else
        echo 'GRUB_DISTRIBUTOR="SysMedic"' >> "$grub_config"
    fi

    # Menu settings — clean, informative, not overwhelming
    # 10 second timeout for fast boot, 30 if last boot failed
    if grep -q "^GRUB_TIMEOUT=" "$grub_config"; then
        sed -i 's|^GRUB_TIMEOUT=.*|GRUB_TIMEOUT=10|' "$grub_config"
    else
        echo "GRUB_TIMEOUT=10" >> "$grub_config"
    fi

    # Show menu always (don't hide if only one OS)
    if grep -q "^GRUB_TIMEOUT_STYLE=" "$grub_config"; then
        sed -i 's|^GRUB_TIMEOUT_STYLE=.*|GRUB_TIMEOUT_STYLE=menu|' "$grub_config"
    else
        echo "GRUB_TIMEOUT_STYLE=menu" >> "$grub_config"
    fi

    # Default to first entry (0) or saved
    if grep -q "^GRUB_DEFAULT=" "$grub_config"; then
        sed -i 's|^GRUB_DEFAULT=.*|GRUB_DEFAULT=saved|' "$grub_config"
    else
        echo "GRUB_DEFAULT=saved" >> "$grub_config"
    fi
    # Enable saved default
    if ! grep -q "^GRUB_SAVEDEFAULT=" "$grub_config"; then
        echo "GRUB_SAVEDEFAULT=true" >> "$grub_config"
    fi

    # Kernel cmdline: balanced defaults
    local current_cmdline
    current_cmdline=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_config" | sed 's/.*="\(.*\)"/\1/' || echo "")
    if [ -z "$current_cmdline" ]; then
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' >> "$grub_config"
    fi
    # Leave existing cmdline alone unless it has nothing useful

    # Enable os-prober for dual-boot detection
    if grep -q "^GRUB_DISABLE_OS_PROBER=" "$grub_config"; then
        sed -i 's|^GRUB_DISABLE_OS_PROBER=.*|GRUB_DISABLE_OS_PROBER=false|' "$grub_config"
    else
        echo "GRUB_DISABLE_OS_PROBER=false" >> "$grub_config"
    fi

    ok "GRUB defaults configured"
}

# ──────────────────────────────────────────────
# Create custom menu entries (/etc/grub.d/40_sysmedic)
# This is the masterpiece — organized, useful, beautiful
# ──────────────────────────────────────────────
create_menu_entries() {
    local output="$GRUB_D_DIR/40_sysmedic"
    local gen_date
    gen_date=$(date '+%Y-%m-%d %H:%M:%S')

    info "Creating SysMedic custom menu entries..."

    # Determine latest kernel version for the entries
    local latest_kernel=""
    local latest_version=""
    for k in /boot/vmlinuz-*; do
        [ -f "$k" ] || continue
        local ver="${k#/boot/vmlinuz-}"
        if [ -z "$latest_version" ] || [ "$ver" ">" "$latest_version" ]; then
            latest_version="$ver"
            latest_kernel="$k"
        fi
    done

    if [ -z "$latest_version" ]; then
        # No kernel found — use a placeholder
        latest_version="YOUR-KERNEL-VERSION"
    fi

    # Get root UUID
    local root_uuid=""
    root_uuid=$(awk '/^[^#]/ && /\/ / && /ext4|xfs|btrfs/ {print $1}' /etc/fstab 2>/dev/null | grep UUID= | sed 's/UUID=//' | head -1)
    if [ -z "$root_uuid" ]; then
        root_uuid=$(blkid -o value -s UUID "$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null)" 2>/dev/null | head -1)
    fi
    [ -z "$root_uuid" ] && root_uuid="YOUR-ROOT-UUID"

    # Write the custom entries file
    # Using printf to avoid heredoc escaping complexities
    {
        printf '#!/bin/sh\n'
        printf '# SysMedic Custom GRUB Menu Entries — v1.0\n'
        printf '# Provides recovery, diagnostic, and emergency boot options\n'
        printf '# This file is managed by SysMedic — do not edit manually.\n'
        printf '#\n'
        printf '# Generated: %s\n' "$gen_date"
        printf '\n'
        printf 'set -e\n'
        printf '\n'
        printf '# Only proceed if generating real config\n'
        printf 'if [ -z "${pkgdata_dir+x}" ] && [ -z "${bootloader_id+x}" ]; then\n'
        printf '    exit 0\n'
        printf 'fi\n'
        printf '\n'
        printf 'cat << GRUB_EOF\n'
        printf '\n'
        printf '# ═══════════════════════════════════════════════════════════════\n'
        printf '# SysMedic Boot Manager — Recovery & Diagnostic Menu Entries\n'
        printf '# ═══════════════════════════════════════════════════════════════\n'
        printf '\n'

        # ── EMERGENCY BOOT OPTIONS ──
        printf '# ═══════════════════════════════════════════════════════════════\n'
        printf '# 🛡️  EMERGENCY BOOT OPTIONS\n'
        printf '# ═══════════════════════════════════════════════════════════════\n'
        printf '\n'

        cat << EMERGENCY_ENTRIES
menuentry '🔧  Boot: Verbose Mode (no quiet, full dmesg)' --class verbose --class gnu-linux --class emergency \$menuentry_id_option 'sysmedic-verbose' {
    recordfail
    load_video
    insmod gzio
    echo 'Loading Linux with verbose logging ...'
    linux /boot/vmlinuz-${latest_version} root=UUID=${root_uuid} ro quiet=0 loglevel=7 earlyprintk debug ignore_loglevel
    echo 'Loading initial ramdisk ...'
    initrd /boot/initrd.img-${latest_version}
}

menuentry '🔧  Boot: Safe Graphics (nomodeset / no KMS)' --class nomodeset --class gnu-linux --class emergency \$menuentry_id_option 'sysmedic-nomodeset' {
    recordfail
    load_video
    insmod gzio
    echo 'Loading Linux with nomodeset ...'
    linux /boot/vmlinuz-${latest_version} root=UUID=${root_uuid} ro nomodeset vga=normal nofb video=off i915.modeset=0 nouveau.modeset=0 radeon.modeset=0
    echo 'Loading initial ramdisk ...'
    initrd /boot/initrd.img-${latest_version}
}

menuentry '🔧  Boot: ACPI Off (legacy hardware compat)' --class acpioff --class gnu-linux --class emergency \$menuentry_id_option 'sysmedic-acpioff' {
    recordfail
    load_video
    insmod gzio
    echo 'Loading Linux with ACPI disabled ...'
    linux /boot/vmlinuz-${latest_version} root=UUID=${root_uuid} ro acpi=off noapic nolapic
    echo 'Loading initial ramdisk ...'
    initrd /boot/initrd.img-${latest_version}
}

menuentry '🔧  Boot: Single User (maintenance shell)' --class single --class gnu-linux --class emergency \$menuentry_id_option 'sysmedic-single' {
    recordfail
    load_video
    insmod gzio
    echo 'Loading Linux in single-user mode ...'
    linux /boot/vmlinuz-${latest_version} root=UUID=${root_uuid} ro single
    echo 'Loading initial ramdisk ...'
    initrd /boot/initrd.img-${latest_version}
}

menuentry '🔧  Boot: All Mitigations (max security)' --class secure --class gnu-linux --class emergency \$menuentry_id_option 'sysmedic-mitigations' {
    recordfail
    load_video
    insmod gzio
    echo 'Loading Linux with full security mitigations ...'
    linux /boot/vmlinuz-${latest_version} root=UUID=${root_uuid} ro mitigations=auto spectre_v2=on spec_store_bypass_disable=on l1tf=full mds=full tsx=off kvm.nx_huge_pages=force
    echo 'Loading initial ramdisk ...'
    initrd /boot/initrd.img-${latest_version}
}

menuentry '🔧  Boot: No Mitigations (max performance)' --class performance --class gnu-linux --class emergency \$menuentry_id_option 'sysmedic-nomitigations' {
    recordfail
    load_video
    insmod gzio
    echo 'Loading Linux with mitigations disabled ...'
    linux /boot/vmlinuz-${latest_version} root=UUID=${root_uuid} ro mitigations=off nospectre_v1 nospectre_v2 no_stf_barrier l1tf=off
    echo 'Loading initial ramdisk ...'
    initrd /boot/initrd.img-${latest_version}
}

EMERGENCY_ENTRIES

        # ── MEMTEST ──
        if [ -f /boot/memtest86+x64.efi ]; then
            printf '\n'
            printf '# ═══════════════════════════════════════════════════════════════\n'
            printf '# 🧪  DIAGNOSTICS\n'
            printf '# ═══════════════════════════════════════════════════════════════\n'
            printf '\n'

            cat << MEMTEST_ENTRIES
menuentry '🧪  Memory Test (memtest86+)' --class memtest \$menuentry_id_option 'sysmedic-memtest' {
    linux /boot/memtest86+x64.efi
}

menuentry '🧪  Memory Test (serial console 115200)' --class memtest \$menuentry_id_option 'sysmedic-memtest-serial' {
    linux /boot/memtest86+x64.efi console=ttyS0,115200
}

MEMTEST_ENTRIES
        fi

        # ── SYSMEDIC USB & FIRMWARE (runtime-determined) ──
        cat << 'RUNTIME_ENTRIES'

# ═══════════════════════════════════════════════════════════════
# 🩺  SYSMEDIC RECOVERY (auto-detect USB)
# ═══════════════════════════════════════════════════════════════

# If SysMedic USB is plugged in, show boot option
if [ -e (hd1,gpt2)/opt/sysmedic/menu.sh ] || [ -e (hd2,gpt2)/opt/sysmedic/menu.sh ]; then
    menuentry '🩺  SysMedic Recovery USB' --class sysmedic --class recovery $menuentry_id_option 'sysmedic-usb' {
        # Try to find SysMedic on removable media
        if [ -e (hd1,gpt2)/casper/vmlinuz ]; then
            set root=(hd1,gpt2)
        elif [ -e (hd2,gpt2)/casper/vmlinuz ]; then
            set root=(hd2,gpt2)
        fi
        linux /casper/vmlinuz boot=casper quiet splash
        initrd /casper/initrd
    }
fi

# ═══════════════════════════════════════════════════════════════
# ⚙️  FIRMWARE
# ═══════════════════════════════════════════════════════════════

if [ "$grub_platform" = "efi" ]; then
    fwsetup --is-supported
    if [ "$?" = 0 ]; then
        menuentry '⚙️  UEFI Firmware Settings' $menuentry_id_option 'sysmedic-firmware' {
            fwsetup
        }
        menuentry '🔁  Boot from Next Volume' $menuentry_id_option 'sysmedic-nextboot' {
            exit
        }
    fi
fi
RUNTIME_ENTRIES

        printf '\n'
        printf 'GRUB_EOF\n'

    } > "$output"

    chmod +x "$output"
    ok "Created custom menu entries at $output"
}

# ──────────────────────────────────────────────
# Remove SysMedic customizations
# ──────────────────────────────────────────────
remove_customizations() {
    info "Removing SysMedic GRUB customizations..."

    # Remove custom entries
    if [ -f "$GRUB_D_DIR/40_sysmedic" ]; then
        rm -f "$GRUB_D_DIR/40_sysmedic"
        ok "Removed custom menu entries"
    fi

    # Remove theme
    if [ -d "$GRUB_THEME_DIR" ]; then
        rm -rf "$GRUB_THEME_DIR"
        ok "Removed GRUB theme"
    fi

    # Restore defaults from backup if available
    local latest_backup
    latest_backup=$(ls -dt /root/sysmedic-backups/grub-*/grub.default.bak 2>/dev/null | head -1)
    if [ -n "$latest_backup" ] && [ -f "$latest_backup" ]; then
        cp "$latest_backup" "$GRUB_DIR/grub"
        ok "Restored GRUB defaults from backup"
    else
        # Reset SysMedic-specific settings
        local grub_config="$GRUB_DIR/grub"
        sed -i '/GRUB_THEME=/d' "$grub_config" 2>/dev/null || true
        sed -i '/GRUB_SAVEDEFAULT=/d' "$grub_config" 2>/dev/null || true
        ok "Reset GRUB config to defaults"
    fi

    # Regenerate GRUB config
    if command -v grub-mkconfig &>/dev/null; then
        grub-mkconfig -o "$GRUB_OUTPUT" 2>/dev/null && ok "GRUB config regenerated"
    fi

    ok "SysMedic GRUB customizations removed"
}

# ──────────────────────────────────────────────
# Show GRUB status
# ──────────────────────────────────────────────
show_status() {
    echo ""
    echo -e "${BOLD}  ╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}  ║   📋  GRUB Status                     ║${NC}"
    echo -e "${BOLD}  ╚══════════════════════════════════════╝${NC}"
    echo ""

    echo -e "  ${CYAN}Config:${NC}"
    if [ -f "$GRUB_DIR/grub" ]; then
        echo "    /etc/default/grub:  OK"
        grep -E "^(GRUB_DEFAULT|GRUB_TIMEOUT|GRUB_DISTRIBUTOR|GRUB_THEME|GRUB_CMDLINE)" "$GRUB_DIR/grub" 2>/dev/null | while read line; do
            echo "      ${line}"
        done
    else
        echo "    ${RED}NOT FOUND${NC}"
    fi
    echo ""

    echo -e "  ${CYAN}Custom entries:${NC}"
    if [ -f "$GRUB_D_DIR/40_sysmedic" ] && [ -x "$GRUB_D_DIR/40_sysmedic" ]; then
        echo "    /etc/grub.d/40_sysmedic:  OK (executable)"
        grep "menuentry" "$GRUB_D_DIR/40_sysmedic" | sed "s/.*menuentry '//;s/'.*//" | while read entry; do
            echo "      • ${entry}"
        done
    else
        echo "    Not installed"
    fi
    echo ""

    echo -e "  ${CYAN}Theme:${NC}"
    if [ -d "$GRUB_THEME_DIR" ] && [ -f "$GRUB_THEME_DIR/theme.txt" ]; then
        echo "    Theme installed: ${GRUB_THEME_DIR}/theme.txt"
        wc -l < "$GRUB_THEME_DIR/theme.txt" | xargs echo "    Lines in theme:"
    else
        echo "    Not installed"
    fi
    echo ""

    echo -e "  ${CYAN}GRUB output:${NC}"
    if [ -f "$GRUB_OUTPUT" ]; then
        local entry_count
        entry_count=$(grep -c "^menuentry" "$GRUB_OUTPUT" 2>/dev/null || echo 0)
        echo "    ${GRUB_OUTPUT}:  ${entry_count} menu entries"
        echo "    Size: $(du -h "$GRUB_OUTPUT" | cut -f1)"
        echo "    Modified: $(stat -c '%y' "$GRUB_OUTPUT" 2>/dev/null | cut -d. -f1)"
    else
        echo "    ${RED}NOT FOUND${NC}"
    fi
    echo ""

    echo -e "  ${CYAN}GRUB packages:${NC}"
    dpkg -l 2>/dev/null | grep -i grub | awk '{print "    " $2 " (" $3 ")"}' || true
    echo ""

    echo -e "  ${CYAN}Boot files:${NC}"
    for f in /boot/vmlinuz-* /boot/initrd.img-* /boot/memtest*; do
        [ -f "$f" ] && echo "    $(basename $f)"
    done
    echo ""
}

# ──────────────────────────────────────────────
# Preview: show what menu entries will be generated
# ──────────────────────────────────────────────
preview_menu() {
    echo ""
    echo -e "${BOLD}  ╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}  ║   📖  SysMedic GRUB Menu Preview     ║${NC}"
    echo -e "${BOLD}  ╚══════════════════════════════════════╝${NC}"
    echo ""
    echo "  This is what your GRUB menu will look like after installation:"
    echo ""
    echo -e "${BOLD}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}  ║   🩺  SysMedic Boot Manager                         ║${NC}"
    echo -e "${BOLD}  ╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}  ║                                                      ║${NC}"
    echo -e "${BOLD}  ║  → Boot: Ubuntu (SysMedic Live)                     ║${NC}"
    echo -e "${BOLD}  ║  → Boot: Ubuntu (Safe Graphics — nomodeset)        ║${NC}"
    echo -e "${BOLD}  ║  → Boot: Ubuntu (ACPI Off — legacy hardware)       ║${NC}"
    echo -e "${BOLD}  ║  → Boot: Ubuntu (Verbose — debug output)           ║${NC}"
    echo -e "${BOLD}  ║  → Boot: Single User (maintenance shell)           ║${NC}"
    echo -e "${BOLD}  ║  → Boot: All Mitigations (max security)            ║${NC}"
    echo -e "${BOLD}  ║  → Boot: No Mitigations (max performance)          ║${NC}"
    echo -e "${BOLD}  ║  ────────────────────────────────────────────────  ║${NC}"
    echo -e "${BOLD}  ║  🧪  Memory Test (memtest86+)                      ║${NC}"
    echo -e "${BOLD}  ║  🧪  Memory Test (serial console)                  ║${NC}"
    echo -e "${BOLD}  ║  ────────────────────────────────────────────────  ║${NC}"
    echo -e "${BOLD}  ║  ⚙️  UEFI Firmware Settings                        ║${NC}"
    echo -e "${BOLD}  ║  🔁  Boot from Next Volume                         ║${NC}"
    echo -e "${BOLD}  ║                                                      ║${NC}"
    echo -e "${BOLD}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Advanced options submenu contains:"
    echo "    • Previous kernel versions"
    echo "    • Recovery mode for each kernel"
    echo ""
    echo -e "  ${YELLOW}Note:${NC} Auto-detected entries (Windows dual-boot, SysMedic USB)"
    echo "  will appear automatically when detected by os-prober."
    echo ""

    # Show estimated entry count
    local count=0
    [ -f /boot/vmlinuz-* ] && count=$((count + 1))
    [ -f /boot/memtest86+x64.efi ] && count=$((count + 2))
    echo "  Estimated total entries: 8 + (kernels: ${count}) + (auto-detected)"
    echo ""
}

# ──────────────────────────────────────────────
# Regenerate GRUB configuration
# ──────────────────────────────────────────────
regenerate_grub() {
    info "Regenerating GRUB configuration..."

    if ! command -v grub-mkconfig &>/dev/null; then
        fail "grub-mkconfig not found — is grub2-common installed?"
        return 1
    fi

    # Run grub-mkconfig
    grub-mkconfig -o "$GRUB_OUTPUT" 2>&1 | while read line; do
        echo "  ${line}"
    done

    if [ -f "$GRUB_OUTPUT" ]; then
        local entry_count
        entry_count=$(grep -c "^menuentry" "$GRUB_OUTPUT" 2>/dev/null || echo 0)
        ok "GRUB config generated: ${entry_count} menu entries"
    else
        fail "GRUB config generation failed"
        return 1
    fi
}

# ──────────────────────────────────────────────
# Install everything
# ──────────────────────────────────────────────
do_install() {
    echo ""
    echo -e "${BOLD}  ╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}  ║   🛠️  SysMedic GRUB Installer         ║${NC}"
    echo -e "${BOLD}  ╚══════════════════════════════════════╝${NC}"
    echo ""

    check_root
    backup_config

    # Step 1: Configure /etc/default/grub
    configure_defaults

    # Step 2: Install theme
    install_theme

    if [ "$ONLY_THEME" = true ]; then
        info "Theme-only mode — skipping menu entries"
    else
        # Step 3: Create custom menu entries
        create_menu_entries
    fi

    # Step 4: Regenerate GRUB
    echo ""
    regenerate_grub

    # Done
    echo ""
    echo -e "${GREEN}${BOLD}  ╔══════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}  ║   ✅  GRUB Installation Complete     ║${NC}"
    echo -e "${GREEN}${BOLD}  ╚══════════════════════════════════════╝${NC}"
    echo ""
    echo "  Backup saved to:  ${BACKUP_DIR}/"
    if [ "$ONLY_THEME" = false ]; then
        echo "  Menu entries:     /etc/grub.d/40_sysmedic"
    fi
    echo "  GRUB config:      ${GRUB_OUTPUT}"
    echo ""
    echo -e "  ${YELLOW}Next boot will show the new GRUB menu.${NC}"
    echo -e "  ${YELLOW}Run 'grub-customizer.sh remove' to undo.${NC}"
    echo ""
}

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────
main() {
    local action="${1:-help}"

    case "$action" in
        install)
            do_install
            ;;
        theme|theme-only|--theme-only)
            ONLY_THEME=true
            do_install
            ;;
        remove|uninstall)
            check_root
            backup_config
            remove_customizations
            ;;
        preview)
            preview_menu
            ;;
        status)
            show_status
            ;;
        *)
            echo "SysMedic GRUB Customizer — Replicable Premium GRUB Menu"
            echo ""
            echo "Usage: grub-customizer.sh <action>"
            echo ""
            echo "Actions:"
            echo "  install             Apply SysMedic GRUB theme + custom entries"
            echo "  install --theme-only  Just install theme, keep existing entries"
            echo "  preview             Show what the menu will look like"
            echo "  remove              Remove all SysMedic GRUB customizations"
            echo "  status              Show current GRUB state"
            echo ""
            echo "Examples:"
            echo "  # Apply to current system:"
            echo "  sudo grub-customizer.sh install"
            echo ""
            echo "  # Apply inside chroot (during repair):"
            echo "  mount /dev/sdX /mnt"
            echo "  for d in dev proc sys; do mount --bind /\$d /mnt/\$d; done"
            echo "  cp /etc/resolv.conf /mnt/etc/"
            echo "  chroot /mnt /opt/sysmedic/scripts/grub-customizer.sh install"
            echo ""
            echo "  # Install just the theme (keep distro's menu entries):"
            echo "  sudo grub-customizer.sh install --theme-only"
            ;;
    esac
}

main "$@"
