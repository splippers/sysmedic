#!/usr/bin/env bash
# SysMedic - ISO Build Pipeline
# Builds a custom Ubuntu 24.04 Live USB with SysMedic recovery tools
#
# Usage: ./build-iso.sh [--download] [--build] [--write /dev/sdX]
#
# Requires: xorriso, mksquashfs, 10GB+ free space

set -uo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

info() { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}   $1"; }
fail() { echo -e "${RED}[FAIL]${NC}   $1"; }

AMBULANCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${AMBULANCE_DIR}/iso-work"
ISO_DIR="${WORK_DIR}/iso"
SQUASH_DIR="${WORK_DIR}/squashfs-root"

ISO_URL="https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso"
ISO_FILE="${WORK_DIR}/ubuntu-24.04.3-live-server-amd64.iso"

##############################################################################

step_download() {
    header "STEP 1: Downloading Ubuntu 24.04 LTS ISO"

    if [ -f "$ISO_FILE" ] && [ "$(stat -c%s "$ISO_FILE" 2>/dev/null)" -gt 1000000000 ]; then
        ok "ISO already exists ($(du -h "$ISO_FILE" | cut -f1))"
        return 0
    fi

    info "Downloading from Ubuntu releases..."
    mkdir -p "$WORK_DIR"

    # Try multiple mirrors
    local mirrors=(
        "https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso"
        "https://cdimage.ubuntu.com/ubuntu/releases/24.04/release/ubuntu-24.04.3-live-server-amd64.iso"
    )

    for url in "${mirrors[@]}"; do
        info "Trying: $url"
        if wget -O "$ISO_FILE" --progress=bar:force "$url" 2>&1; then
            if [ -f "$ISO_FILE" ] && [ "$(stat -c%s "$ISO_FILE")" -gt 1000000000 ]; then
                ok "Download complete: $(du -h "$ISO_FILE" | cut -f1)"
                return 0
            fi
        fi
        warn "Download failed from this mirror"
    done

    # Fallback: try torrent or ask user
    fail "All mirrors failed. Please download manually:"
    echo "  $ISO_URL"
    echo "  and place at: $ISO_FILE"
    return 1
}

##############################################################################

step_extract() {
    header "STEP 2: Extracting ISO"

    if [ -d "$ISO_DIR" ] && [ -f "$ISO_DIR/.disk/info" ]; then
        ok "ISO already extracted"
        return 0
    fi

    mkdir -p "$ISO_DIR"
    info "Mounting and extracting ISO..."

    # Method 1: Mount and copy (cleanest)
    local mount_point
    mount_point=$(mktemp -d)

    if mount -o loop,ro "$ISO_FILE" "$mount_point" 2>/dev/null; then
        info "Copying ISO contents..."
        rsync -a "$mount_point/" "$ISO_DIR/"
        umount "$mount_point"
        rmdir "$mount_point"
        ok "ISO extracted"
    else
        # Method 2: Use 7z or bsdtar
        rmdir "$mount_point"
        if command -v 7z &>/dev/null; then
            info "Using 7z to extract..."
            7z x -o"$ISO_DIR" "$ISO_FILE"
        elif command -v bsdtar &>/dev/null; then
            info "Using bsdtar to extract..."
            bsdtar -xf "$ISO_DIR" -C "$ISO_DIR"
        else
            # Method 3: Use xorriso
            info "Using xorriso to extract..."
            xorriso -osirrox on -indev "$ISO_FILE" -extract / "$ISO_DIR"
        fi
        ok "ISO extracted"
    fi

    # Verify extraction
    if [ ! -f "$ISO_DIR/.disk/info" ]; then
        warn ".disk/info not found — checking structure..."
        ls "$ISO_DIR" | head -20
    fi
}

##############################################################################

step_unsquash() {
    header "STEP 3: Unsquashing Root Filesystem"

    local squashfs
    squashfs=$(find "$ISO_DIR" -name "filesystem.squashfs" -type f 2>/dev/null | head -1)

    if [ -z "$squashfs" ]; then
        # Server ISOs use a different structure
        squashfs=$(find "$ISO_DIR" -name "*.squashfs" -type f 2>/dev/null | head -1)
    fi

    if [ -z "$squashfs" ]; then
        fail "No squashfs found in ISO"
        ls -la "$ISO_DIR"/casper/ 2>/dev/null || true
        return 1
    fi

    if [ -d "$SQUASH_DIR" ] && [ -f "$SQUASH_DIR/etc/os-release" ]; then
        ok "Squashfs already unsquashed"
        return 0
    fi

    info "Unsquashing: $squashfs"
    info "Size: $(du -h "$squashfs" | cut -f1)"

    mksquashfs 2>/dev/null # Just check it exists
    unsquashfs -d "$SQUASH_DIR" "$squashfs"

    if [ -f "$SQUASH_DIR/etc/os-release" ]; then
        os_name=$(grep -oP '^PRETTY_NAME="\K[^"]+' "$SQUASH_DIR/etc/os-release" 2>/dev/null || echo "Ubuntu")
        ok "Rootfs ready: $os_name"
    else
        warn "Rootfs may be incomplete"
    fi
}

##############################################################################

step_customize() {
    header "STEP 4: Customizing Root Filesystem"

    # Copy Ambulance scripts into the live system
    local target_dir="${SQUASH_DIR}/opt/fog-ambulance"

    info "Installing Ambulance scripts to $target_dir"
    mkdir -p "$target_dir"
    cp -a "${AMBULANCE_DIR}/menu.sh" "$target_dir/"
    cp -a "${AMBULANCE_DIR}/scripts/" "$target_dir/"
    chmod +x "$target_dir/menu.sh"
    find "$target_dir/scripts" -name "*.sh" -exec chmod +x {} \;

    # Create desktop entry / shortcut
    mkdir -p "${SQUASH_DIR}/usr/local/bin"
    cat > "${SQUASH_DIR}/usr/local/bin/ambulance" << 'SCRIPT'
#!/usr/bin/env bash
exec bash /opt/fog-ambulance/menu.sh "$@"
SCRIPT
    chmod +x "${SQUASH_DIR}/usr/local/bin/ambulance"

    # Add to motd (message of the day) for live session
    cat > "${SQUASH_DIR}/etc/update-motd.d/99-fog-ambulance" << 'MOTD'
#!/bin/sh
echo ""
echo "  === FOG Ambulance Recovery System ==="
echo "  Run 'ambulance' to start the recovery menu"
echo ""
MOTD
    chmod +x "${SQUASH_DIR}/etc/update-motd.d/99-fog-ambulance"

    # Pre-install useful tools in the live system
    info "Pre-installing recovery tools..."
    chroot "$SQUASH_DIR" bash -c "
        apt-get update -qq 2>/dev/null
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
            parted e2fsprogs gdisk lvm2 mdadm \
            testdisk photorec ntfs-3g dosfstools \
            network-manager iproute2 ethtool \
            rsync curl wget vim nano \
            2>/dev/null || true
    " 2>&1 | tail -5

    # Configure auto-boot into Ambulance (via grub cfg modification)
    info "Configuring auto-launch..."

    # Modify the live session's default shell behavior
    # Add ambulance launch to .bashrc for ubuntu user
    cat >> "${SQUASH_DIR}/home/ubuntu/.bashrc" << 'BASHRC'

# FOG Ambulance auto-launch
if [ -t 0 ] && [ -z "$AMBUSANCE_LAUNCHED" ]; then
    echo ""
    echo -e "\033[1;36m  === FOG Ambulance Recovery System ===\033[0m"
    echo -e "\033[1;33m  Starting recovery menu in 5 seconds...\033[0m"
    echo -e "  Press Ctrl+C to cancel and use shell."
    echo ""
    sleep 5
    export AMBUSANCE_LAUNCHED=1
    exec bash /opt/fog-ambulance/menu.sh
fi
BASHRC

    # Also add to root's profile
    cat >> "${SQUASH_DIR}/root/.profile" << 'PROFILE'

# FOG Ambulance auto-launch for root
if [ -t 0 ] && [ -z "$AMBUSANCE_LAUNCHED" ]; then
    echo ""
    echo -e "\033[1;36m  === FOG Ambulance Recovery System ===\033[0m"
    export AMBUSANCE_LAUNCHED=1
    exec bash /opt/fog-ambulance/menu.sh
fi
PROFILE

    ok "Customization complete"
}

##############################################################################

step_resquash() {
    header "STEP 5: Resquashing Root Filesystem"

    local squashfs
    squashfs=$(find "$ISO_DIR" -name "filesystem.squashfs" -type f 2>/dev/null | head -1)
    if [ -z "$squashfs" ]; then
        squashfs=$(find "$ISO_DIR" -name "*.squashfs" -type f 2>/dev/null | head -1)
    fi

    if [ -z "$squashfs" ]; then
        fail "Cannot find original squashfs path"
        return 1
    fi

    local squashfs_dir
    squashfs_dir=$(dirname "$squashfs")

    # Backup original
    if [ ! -f "${squashfs}.bak" ]; then
        info "Backing up original squashfs..."
        mv "$squashfs" "${squashfs}.bak"
    fi

    info "Creating new squashfs at $squashfs"
    info "This will take several minutes..."

    mksquashfs "$SQUASH_DIR" "$squashfs" \
        -b 1048576 \
        -comp xz \
        -Xdict-size 100% \
        -noappend \
        -e boot

    ok "New squashfs: $(du -h "$squashfs" | cut -f1)"
}

##############################################################################

step_repack() {
    header "STEP 6: Repacking ISO"

    local output_iso="${WORK_DIR}/fog-ambulance-ubuntu-24.04-amd64.iso"

    info "Building ISO with xorriso..."

    # Find the boot files
    local boot_img
    boot_img=$(find "$ISO_DIR" -name "boot.img" -type f 2>/dev/null | head -1)

    local xorriso_opts=(
        -as mkisofs
        -r
        -V "FOG_AMBULANCE_2404"
        --volatile-identifier "FOG AMBULANCE"
        -cache-inodes
        -J
        -l
        -b isolinux/isolinux.bin
        -c isolinux/boot.cat
        -no-emul-boot
        -boot-load-size 4
        -boot-info-table
        -eltorito-alt-boot
    )

    # Add EFI boot if available
    local efi_img
    efi_img=$(find "$ISO_DIR" -name "efi.img" -o -name "boot*.efi" -type f 2>/dev/null | head -1)
    if [ -n "$efi_img" ]; then
        xorriso_opts+=(-e "$efi_img" -no-emul-boot)
    fi

    xorriso_opts+=(-o "$output_iso")
    xorriso_opts+=("$ISO_DIR")

    xorriso "${xorriso_opts[@]}" 2>&1 | tail -10

    if [ -f "$output_iso" ] && [ "$(stat -c%s "$output_iso")" -gt 1000000000 ]; then
        ok "ISO created: $(du -h "$output_iso" | cut -f1)"
        info "Location: $output_iso"
    else
        fail "ISO creation may have failed"
        return 1
    fi
}

##############################################################################

step_write() {
    local device="${1:-}"

    if [ -z "$device" ]; then
        fail "Usage: $0 --write /dev/sdX"
        return 1
    fi

    if [ ! -b "$device" ]; then
        fail "$device is not a block device"
        return 1
    fi

    header "WRITING ISO TO $device"
    warn "THIS WILL ERASE EVERYTHING ON $device"
    echo ""
    lsblk "$device"
    echo ""
    echo -ne "  ${RED}Are you absolutely sure?${NC} Type YES: "
    read -r confirm

    if [ "$confirm" != "YES" ]; then
        info "Cancelled"
        return 0
    fi

    local output_iso="${WORK_DIR}/fog-ambulance-ubuntu-24.04-amd64.iso"
    if [ ! -f "$output_iso" ]; then
        fail "ISO not found. Build it first with --build"
        return 1
    fi

    info "Writing ISO to $device..."
    dd if="$output_iso" of="$device" bs=4M status=progress oflag=sync
    sync

    ok "Write complete"
    info "Verify with: lsblk $device"
}

##############################################################################

header() {
    echo -e "\n${BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════${NC}\n"
}

cleanup() {
    info "Cleaning up mount points..."
    # Unmount anything left mounted
    for mp in $(mount | grep "iso-work" | awk '{print $3}'); do
        umount "$mp" 2>/dev/null
    done
}

##############################################################################

# Main
ACTION="${1:-all}"

case "$ACTION" in
    --download|download)
        step_download
        ;;
    --extract|extract)
        step_download
        step_extract
        ;;
    --unsquash|unsquash)
        step_extract
        step_unsquash
        ;;
    --customize|customize)
        step_customize
        ;;
    --resquash|resquash)
        step_resquash
        ;;
    --repack|repack)
        step_repack
        ;;
    --build|build)
        step_download
        step_extract
        step_unsquash
        step_customize
        step_resquash
        step_repack
        ;;
    --write)
        step_write "${2:-}"
        ;;
    --all)
        step_download
        step_extract
        step_unsquash
        step_customize
        step_resquash
        step_repack
        echo ""
        echo -e "${GREEN}${BOLD}BUILD COMPLETE${NC}"
        echo -e "  ISO: ${WORK_DIR}/fog-ambulance-ubuntu-24.04-amd64.iso"
        echo -e "  Write with: $0 --write /dev/sdX"
        ;;
    --clean)
        cleanup
        rm -rf "$WORK_DIR"
        ok "Cleaned"
        ;;
    *)
        echo "FOG Ambulance ISO Builder"
        echo ""
        echo "Usage: $0 <action>"
        echo ""
        echo "Actions:"
        echo "  --download    Download Ubuntu 24.04 ISO"
        echo "  --extract     Extract ISO contents"
        echo "  --unsquash    Unsquash root filesystem"
        echo "  --customize   Add Ambulance scripts and tools"
        echo "  --resquash    Resquash modified rootfs"
        echo "  --repack      Repack into new ISO"
        echo "  --build       Full build (all steps)"
        echo "  --write /dev/sdX  Write ISO to USB device"
        echo "  --clean       Remove all work files"
        ;;
esac
