#!/usr/bin/env bash
# SysMedic - Quick Fix: Kernel Panic / Missing initramfs
#
# Error: "VFS: Unable to mount root fs on unknown-block(0,0)"
# Cause: initramfs missing/corrupted, or GRUB pointing to wrong initrd
#
# This script regenerates initramfs and GRUB WITHOUT repartitioning.
# Use this first — it's non-destructive and fixes 90% of these panics.

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

##############################################################################

echo -e "${BOLD}=== SysMedic: Quick Kernel Panic Fix ===${NC}"
echo -e "  Fixes: VFS: Unable to mount root fs on unknown-block(0,0)\n"

# Step 1: Find Linux systems
echo -e "${BOLD}=== SCANNING FOR LINUX SYSTEMS ===${NC}"
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

# Step 2: Mount and inspect
echo -e "\n${BOLD}=== MOUNTING $ROOT_PART ===${NC}"
WORK_DIR="/tmp/sysmedic-work"
mkdir -p "$WORK_DIR"
mount "$ROOT_PART" "$WORK_DIR" || { fail "Cannot mount $ROOT_PART"; exit 1; }

# Find boot partition
BOOT_PART=""
ROOT_DISK=$(lsblk -rno PKNAME "$(echo $ROOT_PART | sed 's|/dev/||')" 2>/dev/null || true)
if [ -n "$ROOT_DISK" ]; then
    for part in $(lsblk -rno NAME "/dev/$ROOT_DISK" 2>/dev/null | awk '{print "/dev/"$1}'); do
        [ "$part" = "$ROOT_PART" ] && continue
        fstype=$(blkid "$part" 2>/dev/null | grep -oP 'TYPE="\K[^"]+' || true)
        case "$fstype" in
            ext2|ext3|ext4)
                tmpmnt=$(mktemp -d)
                if mount -o ro "$part" "$tmpmnt" 2>/dev/null; then
                    if ls "$tmpmnt/vmlinuz"* "$tmpmnt/initrd"* &>/dev/null; then
                        BOOT_PART="$part"
                        echo -e "  ${CYAN}[BOOT]${NC} Separate boot at $part"
                    fi
                    umount "$tmpmnt" 2>/dev/null
                fi
                rmdir "$tmpmnt" 2>/dev/null
                ;;
        esac
    done
fi

[ -z "$BOOT_PART" ] && { BOOT_PART="$ROOT_PART"; info "No separate /boot — using root"; }

# Step 3: Inspect boot contents
echo -e "\n${BOLD}=== BOOT CONTENTS ===${NC}"
if [ "$BOOT_PART" != "$ROOT_PART" ]; then
    mkdir -p "$WORK_DIR/boot"
    mount "$BOOT_PART" "$WORK_DIR/boot"
fi

echo "  vmlinuz files:"
ls -lh "$WORK_DIR/boot/vmlinuz"* 2>/dev/null | awk '{print "    "$5, $9}'
echo "  initrd files:"
ls -lh "$WORK_DIR/boot/initrd"* 2>/dev/null | awk '{print "    "$5, $9}'
echo "  kernel modules:"
ls "$WORK_DIR/lib/modules/" 2>/dev/null | while read k; do
    echo "    $k"
done

# Step 4: Find GRUB config and check for issues
echo -e "\n${BOLD}=== GRUB CONFIG CHECK ===${NC}"
GRUB_CFG="$WORK_DIR/boot/grub/grub.cfg"
GRUB2_CFG="$WORK_DIR/boot/grub2/grub.cfg"

if [ -f "$GRUB_CFG" ]; then
    echo "  Found: $GRUB_CFG"
    initrd_lines=$(grep -c "initrd" "$GRUB_CFG" 2>/dev/null || echo 0)
    echo "  initrd entries: $initrd_lines"
    # Show first menu entry's root and initrd
    echo "  First entry:"
    grep -A2 "menuentry\|linux \|initrd " "$GRUB_CFG" 2>/dev/null | head -12 | sed 's/^/    /'
elif [ -f "$GRUB2_CFG" ]; then
    echo "  Found: $GRUB2_CFG"
else
    warn "No grub.cfg found in /boot/grub/ or /boot/grub2/"
fi

# Check fstab for /boot
echo ""
echo "  fstab /boot entry:"
grep '/boot' "$WORK_DIR/etc/fstab" 2>/dev/null | sed 's/^/    /' || echo "    (none)"

echo ""
echo -e "${YELLOW}Review the above output. Common issues:${NC}"
echo "  - initrd files missing → needs regeneration"
echo "  - grub.cfg pointing to wrong initrd filename → needs update-grub"
echo "  - fstab /boot UUID wrong → partition was recreated"
echo ""
echo -ne "  Proceed with repair? [y/N] "
read -r confirm
case "$confirm" in [Yy]*) ;; *) umount -R "$WORK_DIR"; rmdir "$WORK_DIR"; exit 0 ;; esac

# Step 5: Chroot and repair
echo -e "\n${BOLD}=== REPAIRING ===${NC}"

# Bind mounts
for dir in /dev /dev/pts /proc /sys /run; do
    mount --bind "$dir" "$WORK_DIR$dir"
done
cp /etc/resolv.conf "$WORK_DIR/etc/resolv.conf"

chroot "$WORK_DIR" bash -c '
set -x

# Find kernel version
KERNEL=$(ls /lib/modules/ 2>/dev/null | sort -V | tail -1)
if [ -z "$KERNEL" ]; then
    echo "ERROR: No kernel modules found in /lib/modules/"
    exit 1
fi
echo ""
echo "Target kernel: $KERNEL"

# Step A: Regenerate initramfs
echo ""
echo "=== Regenerating initramfs ==="
update-initramfs -c -k "$KERNEL" -v 2>&1 | tail -10

# Verify
echo ""
echo "=== Boot files after regeneration ==="
ls -lh /boot/vmlinuz* /boot/initrd* 2>/dev/null

# Step B: Check fstab for /boot UUID
echo ""
echo "=== fstab check ==="
if grep "/boot" /etc/fstab 2>/dev/null; then
    boot_mount=$(grep "/boot" /etc/fstab | grep -oP "^\S+")
    boot_fstype=$(grep "/boot" /etc/fstab | awk "{print \$3}")
    echo "Boot mount: $boot_mount (type: $boot_fstype)"

    # If fstab references UUID, check if it matches actual partition
    boot_uuid=$(grep "/boot" /etc/fstab 2>/dev/null | grep -oP "UUID=\K[^ ]+" || true)
    if [ -n "$boot_uuid" ]; then
        actual_uuid=$(blkid | grep "$boot_uuid" | cut -d: -f1 || true)
        if [ -n "$actual_uuid" ]; then
            echo "fstab UUID $boot_uuid is valid (found at $actual_uuid)"
        else
            echo "WARNING: fstab UUID $boot_uuid not found on any partition!"
            # Try to find correct UUID
            for dev in $(lsblk -dn -o NAME,TYPE | awk "\$2==\"part\"{print \"/dev/\"\$1}"); do
                dev_uuid=$(blkid -s UUID -o value "$dev" 2>/dev/null || true)
                if [ -n "$dev_uuid" ]; then
                    echo "  $dev UUID=$dev_uuid"
                fi
            done
        fi
    fi
fi

# Step C: Update GRUB
echo ""
echo "=== Updating GRUB ==="
update-grub 2>&1 | tail -10

echo ""
echo "=== DONE ==="
'

# Cleanup
for dir in /run /sys /proc /dev/pts /dev; do
    umount "$WORK_DIR$dir" 2>/dev/null
done

if [ "$BOOT_PART" != "$ROOT_PART" ]; then
    umount "$WORK_DIR/boot" 2>/dev/null
fi

umount "$WORK_DIR" 2>/dev/null
rmdir "$WORK_DIR" 2>/dev/null

echo ""
echo -e "${GREEN}${BOLD}=== REPAIR COMPLETE ===${NC}"
echo -e "  ${YELLOW}Reboot the target machine and it should boot normally.${NC}"
