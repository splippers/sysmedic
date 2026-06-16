#!/usr/bin/env bash
# SysMedic — ISO Build Pipeline (Tier 4)
# Builds a custom Ubuntu 24.04 Live USB with SysMedic recovery tools baked in.
#
# Usage: ./build-iso.sh [--download] [--build] [--write /dev/sdX]
#
# Requires: xorriso, mksquashfs, unsquashfs, 15GB+ free space
# Optional: apt-cache for package pre-install in chroot

set -uo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'

info() { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()   { echo -e "${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC}   $1"; }
fail() { echo -e "${RED}[FAIL]${NC}   $1"; }

SYSMEDIC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${SYSMEDIC_DIR}/iso-work"
ISO_DIR="${WORK_DIR}/iso"
SQUASH_DIR="${WORK_DIR}/squashfs-root"

ISO_URL="https://releases.ubuntu.com/24.04/ubuntu-24.04.3-desktop-amd64.iso"
ISO_FILE="${WORK_DIR}/ubuntu-24.04.3-desktop-amd64.iso"

# Packages to pre-install in the live ISO (in addition to what Ubuntu ships)
# SysMedic uses: smartctl, stress-ng, memtester, dmidecode, lvm2, mdadm, ntfs-3g, etc.
EXTRA_PACKAGES=(
    smartmontools
    stress-ng
    memtester
    lvm2
    mdadm
    ntfs-3g
    testdisk
    partclone
    hfsprogs
    apfs-fuse
    chntpw
    nmap
    iperf3
    ethtool
    dmidecode
    lm-sensors
    nvme-cli
    rsync
    curl
    wget
    vim
    nano
    tmux
    iftop
    nethogs
)

##############################################################################

step_download() {
    header "STEP 1: Downloading Ubuntu 24.04 LTS Desktop ISO"

    if [ -f "$ISO_FILE" ] && [ "$(stat -c%s "$ISO_FILE" 2>/dev/null)" -gt 1000000000 ]; then
        ok "ISO already exists ($(du -h "$ISO_FILE" | cut -f1))"
        return 0
    fi

    info "Downloading from Ubuntu releases..."
    mkdir -p "$WORK_DIR"

    local mirrors=(
        "https://releases.ubuntu.com/24.04/ubuntu-24.04.3-desktop-amd64.iso"
        "https://releases.ubuntu.com/24.04/ubuntu-24.04.3-live-server-amd64.iso"
        "https://cdimage.ubuntu.com/ubuntu/releases/24.04/release/ubuntu-24.04.3-desktop-amd64.iso"
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

    local mount_point
    mount_point=$(mktemp -d)

    if mount -o loop,ro "$ISO_FILE" "$mount_point" 2>/dev/null; then
        info "Copying ISO contents..."
        rsync -a "$mount_point/" "$ISO_DIR/"
        umount "$mount_point"
        rmdir "$mount_point"
        ok "ISO extracted"
    else
        rmdir "$mount_point"
        if command -v xorriso &>/dev/null; then
            info "Using xorriso to extract..."
            xorriso -osirrox on -indev "$ISO_FILE" -extract / "$ISO_DIR" 2>&1 | tail -5
        elif command -v bsdtar &>/dev/null; then
            info "Using bsdtar to extract..."
            bsdtar -xf "$ISO_FILE" -C "$ISO_DIR"
        else
            fail "Cannot extract ISO — need xorriso, bsdtar, or mount support"
            return 1
        fi
        ok "ISO extracted"
    fi

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

    if ! command -v unsquashfs &>/dev/null; then
        fail "unsquashfs not found — install squashfs-tools"
        return 1
    fi

    info "Unsquashing: $squashfs ($(du -h "$squashfs" | cut -f1))"

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
    header "STEP 4: Customizing Root Filesystem — SysMedic v3"

    local target_dir="${SQUASH_DIR}/opt/sysmedic"

    # ── 4a. Copy SysMedic scripts ──
    info "Installing SysMedic to ${target_dir}"
    mkdir -p "$target_dir"
    cp -a "${SYSMEDIC_DIR}/menu.sh" "$target_dir/"
    cp -a "${SYSMEDIC_DIR}/sysmedic-diagnose" "$target_dir/" 2>/dev/null || true
    cp -a "${SYSMEDIC_DIR}/sysmedic-netcheck" "$target_dir/" 2>/dev/null || true
    cp -a "${SYSMEDIC_DIR}/scripts/" "$target_dir/"
    cp -a "${SYSMEDIC_DIR}/WIKI.md" "$target_dir/" 2>/dev/null || true
    cp -a "${SYSMEDIC_DIR}/ROADMAP.md" "$target_dir/" 2>/dev/null || true

    chmod +x "$target_dir/menu.sh"
    find "$target_dir/scripts" -name "*.sh" -exec chmod +x {} \;

    # ── 4b. Create symlink in PATH ──
    mkdir -p "${SQUASH_DIR}/usr/local/bin"
    cat > "${SQUASH_DIR}/usr/local/bin/sysmedic" << 'SCRIPT'
#!/usr/bin/env bash
exec bash /opt/sysmedic/menu.sh "$@"
SCRIPT
    chmod +x "${SQUASH_DIR}/usr/local/bin/sysmedic"

    # Also create 'ambulance' as alias for backward compatibility
    ln -sf /usr/local/bin/sysmedic "${SQUASH_DIR}/usr/local/bin/ambulance" 2>/dev/null || true

    # ── 4c. MOTD banner ──
    mkdir -p "${SQUASH_DIR}/etc/update-motd.d"
    cat > "${SQUASH_DIR}/etc/update-motd.d/99-sysmedic" << 'MOTD'
#!/bin/sh
echo ""
echo "  ====== SysMedic Recovery System ======"
echo "  Run 'sysmedic' to start the recovery menu"
echo "  Run 'sysmedic-diagnose' for quick health check"
echo ""
MOTD
    chmod +x "${SQUASH_DIR}/etc/update-motd.d/99-sysmedic"

    # ── 4d. Auto-launch in ubuntu user's profile ──
    cat >> "${SQUASH_DIR}/home/ubuntu/.bashrc" << 'BASHRC'

# SysMedic auto-launch
if [ -t 0 ] && [ -z "${SYSMEDIC_LAUNCHED:-}" ]; then
    echo ""
    echo -e "\033[1;36m  ====== SysMedic Recovery System ======\033[0m"
    echo -e "\033[1;33m  Starting recovery menu in 5 seconds...\033[0m"
    echo -e "  Press Ctrl+C to cancel and use shell."
    echo ""
    sleep 5
    export SYSMEDIC_LAUNCHED=1
    exec bash /opt/sysmedic/menu.sh
fi
BASHRC

    # Also for root
    cat >> "${SQUASH_DIR}/root/.profile" << 'PROFILE'

# SysMedic auto-launch for root
if [ -t 0 ] && [ -z "${SYSMEDIC_LAUNCHED:-}" ]; then
    echo ""
    echo -e "\033[1;36m  ====== SysMedic Recovery System ======\033[0m"
    export SYSMEDIC_LAUNCHED=1
    exec bash /opt/sysmedic/menu.sh
fi
PROFILE

    # ── 4e. Copy over auth config if it exists ──
    if [ -d "${SYSMEDIC_DIR}/auth" ]; then
        info "Copying auth configuration..."
        cp -a "${SYSMEDIC_DIR}/auth" "$target_dir/"
    fi

    # ── 4f. Optionally pre-install extra packages via proper chroot ──
    info "Extra packages can be pre-installed now."
    echo ""
    echo "  SysMedic needs these tools available in the live environment:"
    echo "    - smartctl (smartmontools) — disk health checks"
    echo "    - stress-ng — CPU/RAM/disk stress testing"
    echo "    - memtester — memory diagnostics"
    echo "    - lvm2, mdadm — storage management"
    echo "    - ntfs-3g, testdisk — NTFS/data recovery"
    echo "    - dmidecode, lm-sensors, nvme-cli — hardware detection"
    echo "    - nmap, iperf3, iftop — network diagnostics"
    echo "    - partclone — OS imaging"
    echo ""
    echo "  These require network access and ~200 MB download."
    echo -n "  Pre-install packages into ISO? [y/N]: "
    read -r do_install

    if [[ "$do_install" =~ ^[yY] ]]; then
        install_packages_in_chroot
    else
        info "Skipping package pre-install."
        info "NOTE: The live system can install them at runtime via:"
        info "  sudo apt-get install -y smartmontools stress-ng memtester"
        echo ""
    fi

    ok "SysMedic customization complete"
}

##############################################################################

install_packages_in_chroot() {
    info "Setting up chroot for package installation..."

    # Bind-mount necessary filesystems
    mount --bind /dev "$SQUASH_DIR/dev" 2>/dev/null || warn "Could not bind /dev"
    mount --bind /proc "$SQUASH_DIR/proc" 2>/dev/null || warn "Could not bind /proc"
    mount --bind /sys "$SQUASH_DIR/sys" 2>/dev/null || warn "Could not bind /sys"

    # Handle resolv.conf for network access inside chroot
    if [ -f /etc/resolv.conf ]; then
        cp /etc/resolv.conf "$SQUASH_DIR/etc/resolv.conf" 2>/dev/null || true
    fi

    info "Updating package lists inside chroot..."
    if chroot "$SQUASH_DIR" apt-get update -qq 2>/dev/null; then
        info "Installing packages: ${EXTRA_PACKAGES[*]}"
        if chroot "$SQUASH_DIR" env DEBIAN_FRONTEND=noninteractive \
            apt-get install -y -qq "${EXTRA_PACKAGES[@]}" 2>&1 | tail -10; then
            ok "Package installation complete"
        else
            warn "Some packages may have failed to install"
            warn "The live system can install missing packages at runtime via apt"
        fi
    else
        warn "apt-get update failed in chroot — skipping package installation"
        warn "Install packages at runtime: apt-get install -y smartmontools stress-ng memtester ..."
    fi

    # Clean apt cache to save space
    chroot "$SQUASH_DIR" apt-get clean 2>/dev/null || true

    # Clean up bind mounts
    umount "$SQUASH_DIR/dev" 2>/dev/null || true
    umount "$SQUASH_DIR/proc" 2>/dev/null || true
    umount "$SQUASH_DIR/sys" 2>/dev/null || true
    rm -f "$SQUASH_DIR/etc/resolv.conf" 2>/dev/null || true
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
        cp "$squashfs" "${squashfs}.bak"
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

    local output_iso="${WORK_DIR}/sysmedic-ubuntu-24.04-amd64.iso"

    info "Building ISO with xorriso..."

    # Update ISO volume label
    local xorriso_opts=(
        -as mkisofs
        -r
        -V "SYSMEDIC_2404"
        --volatile-identifier "SYSMEDIC"
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
    efi_img=$(find "$ISO_DIR" -name "efi.img" -type f 2>/dev/null | head -1)
    if [ -z "$efi_img" ]; then
        efi_img=$(find "$ISO_DIR" -name "boot*.efi" -type f 2>/dev/null | head -1)
    fi
    if [ -n "$efi_img" ]; then
        xorriso_opts+=(-e "$efi_img" -no-emul-boot)
    fi

    xorriso_opts+=(-o "$output_iso")
    xorriso_opts+=("$ISO_DIR")

    xorriso "${xorriso_opts[@]}" 2>&1 | tail -10

    if [ -f "$output_iso" ] && [ "$(stat -c%s "$output_iso")" -gt 1000000000 ]; then
        ok "ISO created: $(du -h "$output_iso" | cut -f1)"
        info "Location: $output_iso"

        # Create SHA256 checksum
        sha256sum "$output_iso" > "${output_iso}.sha256"
        ok "SHA256: $(cut -d' ' -f1 < "${output_iso}.sha256")"
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

    local output_iso="${WORK_DIR}/sysmedic-ubuntu-24.04-amd64.iso"
    if [ ! -f "$output_iso" ]; then
        # Try alternate name
        output_iso=$(ls -t "${WORK_DIR}"/*.iso 2>/dev/null | head -1)
        if [ -z "$output_iso" ]; then
            fail "No ISO found. Build it first with --build"
            return 1
        fi
    fi

    info "Writing ISO to $device..."
    dd if="$output_iso" of="$device" bs=4M status=progress oflag=sync
    sync

    ok "Write complete"
    info "Verify with: lsblk $device"
    info "Then create writable persistence partition:"
    echo "  sudo parted $device mkpart primary ext4 4GB 100%"
    echo "  sudo mkfs.ext4 -L SYSMEDIC_PERSIST ${device}5"
}

##############################################################################

header() {
    echo -e "\n${BOLD}═══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════${NC}\n"
}

cleanup() {
    info "Cleaning up mount points..."
    for mp in $(mount | grep "iso-work" | awk '{print $3}' 2>/dev/null); do
        umount "$mp" 2>/dev/null
    done
    # Also clean up any chroot mounts
    for mp in "${SQUASH_DIR}/dev" "${SQUASH_DIR}/proc" "${SQUASH_DIR}/sys"; do
        umount "$mp" 2>/dev/null || true
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
    --install-packages)
        # Standalone: install packages into an already-unsquashed rootfs
        if [ ! -d "$SQUASH_DIR" ]; then
            fail "Unsquash first: $0 --unsquash"
            exit 1
        fi
        install_packages_in_chroot
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
        echo -e "  ISO: ${WORK_DIR}/sysmedic-ubuntu-24.04-amd64.iso"
        echo -e "  Write with: $0 --write /dev/sdX"
        ;;
    --clean)
        cleanup
        rm -rf "$WORK_DIR"
        ok "Cleaned"
        ;;
    *)
        echo "SysMedic ISO Builder v3.0"
        echo ""
        echo "Usage: $0 <action>"
        echo ""
        echo "Actions:"
        echo "  --download        Download Ubuntu 24.04 ISO"
        echo "  --extract         Extract ISO contents"
        echo "  --unsquash        Unsquash root filesystem"
        echo "  --customize       Add SysMedic scripts and tools (prompts for package install)"
        echo "  --install-packages Install extra packages into rootfs (requires chroot setup)"
        echo "  --resquash        Resquash modified rootfs"
        echo "  --repack          Repack into new ISO"
        echo "  --build           Full build (all steps, prompts for package install)"
        echo "  --all             Same as --build"
        echo "  --write /dev/sdX  Write ISO to USB device"
        echo "  --clean           Remove all work files"
        echo ""
        echo "Typical workflow:"
        echo "  sudo $0 --build"
        echo "  sudo $0 --write /dev/sdX"
        echo ""
        echo "Build requirements:"
        echo "  - xorriso, squashfs-tools, rsync, wget"
        echo "  - 15 GB free space"
        echo "  - Network access for ISO download and optional package install"
        ;;
esac
