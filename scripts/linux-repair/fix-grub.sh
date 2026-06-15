#!/usr/bin/env bash
# SysMedic - Reinstall GRUB Bootloader
# Fixes: GRUB missing, corrupted, or pointing to wrong disk

set -uo pipefail

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'
BOLD='\033[1m'

info() { echo -e "  ${CYAN}[INFO]${NC}  $1"; }
ok()   { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC}   $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC}   $1"; }

echo -e "${BOLD}=== SysMedic: Reinstall GRUB ===${NC}\n"

# Find Linux systems
targets=()
for part in $(lsblk -dn -o NAME,TYPE | awk '$2=="part"{print "/dev/"$1}'); do
    fstype=$(blkid "$part" 2>/dev/null | grep -oP 'TYPE="\K[^"]+' || true)
    case "$fstype" in
        ext2|ext3|ext4)
            tmpmnt=$(mktemp -d)
            if mount -o ro "$part" "$tmpmnt" 2>/dev/null; then
                if [ -f "$tmpmnt/etc/os-release" ]; then
                    os_name=$(grep -oP '^PRETTY_NAME="\K[^"]+' "$tmpmnt/etc/os-release" 2>/dev/null || echo "Linux")
                    echo -e "  ${GREEN}[${#targets[@]}]${NC} $part → $os_name"
                    targets+=("$part")
                fi
                umount "$tmpmnt" 2>/dev/null
            fi
            rmdir "$tmpmnt" 2>/dev/null
            ;;
    esac
done

[ ${#targets[@]} -eq 0 ] && { fail "No Linux systems found"; exit 1; }

if [ ${#targets[@]} -eq 1 ]; then
    ROOT_PART="${targets[0]}"
else
    echo -ne "\n  Select target [0-$(( ${#targets[@]} - 1 ))]: "
    read -r idx
    ROOT_PART="${targets[$idx]}"
fi

# Find the disk to install GRUB on
ROOT_DEVNAME=$(echo "$ROOT_PART" | sed 's|/dev/||')
GRUB_DISK=$(lsblk -rno PKNAME "$ROOT_DEVNAME" 2>/dev/null || true)
GRUB_DISK="/dev/$GRUB_DISK"

echo -e "\n${BOLD}Target: $ROOT_PART${NC}"
echo -e "  GRUB will be installed to: ${BOLD}$GRUB_DISK${NC}"
echo ""
echo -ne "  Proceed? [y/N] "
read -r confirm
case "$confirm" in [Yy]*) ;; *) exit 0 ;; esac

# Mount root
WORK_DIR="/tmp/sysmedic-work"
mkdir -p "$WORK_DIR"
mount "$ROOT_PART" "$WORK_DIR"

# Find and mount boot if separate
BOOT_PART=""
for part in $(lsblk -rno NAME "$GRUB_DISK" 2>/dev/null | awk '{print "/dev/"$1}'); do
    [ "$part" = "$ROOT_PART" ] && continue
    fstype=$(blkid "$part" 2>/dev/null | grep -oP 'TYPE="\K[^"]+' || true)
    case "$fstype" in
        ext2|ext3|ext4)
            tmpmnt=$(mktemp -d)
            if mount -o ro "$part" "$tmpmnt" 2>/dev/null; then
                if ls "$tmpmnt/vmlinuz"* &>/dev/null; then
                    BOOT_PART="$part"
                    info "Mounting boot partition $part at /boot"
                    mount "$part" "$WORK_DIR/boot" 2>/dev/null || mkdir -p "$WORK_DIR/boot" && mount "$part" "$WORK_DIR/boot"
                fi
                umount "$tmpmnt" 2>/dev/null
            fi
            rmdir "$tmpmnt" 2>/dev/null
            ;;
    esac
done

# Find EFI partition if present
EFI_PART=""
for part in $(lsblk -rno NAME "$GRUB_DISK" 2>/dev/null | awk '{print "/dev/"$1}'); do
    fstype=$(blkid "$part" 2>/dev/null | grep -oP 'TYPE="\K[^"]+' || true)
    [ "$fstype" = "vfat" ] && { EFI_PART="$part"; break; }
done

if [ -n "$EFI_PART" ]; then
    info "EFI partition found: $EFI_PART"
    mkdir -p "$WORK_DIR/boot/efi"
    mount "$EFI_PART" "$WORK_DIR/boot/efi"
fi

# Bind mount for chroot
for dir in /dev /dev/pts /proc /sys /run; do
    mount --bind "$dir" "$WORK_DIR$dir"
done
cp /etc/resolv.conf "$WORK_DIR/etc/resolv.conf"

echo -e "\n${BOLD}=== INSTALLING GRUB ===${NC}"

if [ -n "$EFI_PART" ]; then
    # UEFI mode
    info "UEEFI mode detected"
    chroot "$WORK_DIR" bash -c "
        apt-get update -qq 2>/dev/null
        apt-get install -y -qq grub-efi-amd64 2>/dev/null || true
        grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=ubuntu --recheck 2>&1
        update-grub 2>&1 | tail -5
    "
else
    # BIOS/MBR mode
    info "BIOS/MBR mode detected"
    chroot "$WORK_DIR" bash -c "
        apt-get update -qq 2>/dev/null
        apt-get install -y -qq grub-pc 2>/dev/null || true
        grub-install $GRUB_DISK 2>&1
        update-grub 2>&1 | tail -5
    "
fi

# Cleanup
for dir in /run /sys /proc /dev/pts /dev; do
    umount "$WORK_DIR$dir" 2>/dev/null
done
[ -n "$EFI_PART" ] && umount "$WORK_DIR/boot/efi" 2>/dev/null
[ -n "$BOOT_PART" ] && umount "$WORK_DIR/boot" 2>/dev/null
umount "$WORK_DIR" 2>/dev/null
rmdir "$WORK_DIR" 2>/dev/null

echo ""
echo -e "${GREEN}${BOLD}=== GRUB REINSTALLED ===${NC}"
echo -e "  ${YELLOW}Reboot and test.${NC}"
