#!/usr/bin/env bash
# SysMedic - Fix Oversized /boot Partition
#
# Problem: FOG image clones the source machine's partition layout,
# leaving /boot at 700G+ instead of ~1GB. This wastes disk and can
# cause kernel/GRUB issues.
#
# Solution: Shrink /boot to 1GB while preserving all kernels/initrds.
# Steps:
#   1. Boot from this USB
#   2. Detect the target system's partitions
#   3. Back up /boot contents
#   4. Shrink /boot partition to 1GB
#   5. Recreate ext4, restore files
#   6. Update /etc/fstab
#   7. Chroot into target, regenerate initramfs, update GRUB
#   8. Reboot

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

info() { echo -e "  ${CYAN}[INFO]${NC}  $1"; }
ok()   { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC}   $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC}   $1"; }

##############################################################################

# Step 1: Find all Linux systems
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
                    boot_size=$(du -sh "$tmpmnt/boot" 2>/dev/null | awk '{print $1}' || echo "N/A")
                    echo -e "  ${GREEN}[${#targets[@]}]${NC} $part → $os_name (root /boot: $boot_size)"
                    targets+=("$part")
                fi
                umount "$tmpmnt" 2>/dev/null
            fi
            rmdir "$tmpmnt" 2>/dev/null
            ;;
    esac
done

if [ ${#targets[@]} -eq 0 ]; then
    fail "No Linux systems found"
    exit 1
fi

# Step 2: User selects target
echo ""
if [ ${#targets[@]} -eq 1 ]; then
    ROOT_PART="${targets[0]}"
    info "Auto-selected: $ROOT_PART"
else
    echo -ne "  Select target [0-$(( ${#targets[@]} - 1 ))]: "
    read -r idx
    ROOT_PART="${targets[$idx]}"
fi

# Step 3: Identify boot partition
echo -e "\n${BOLD}=== IDENTIFYING BOOT PARTITION ===${NC}"

ROOT_PARTNAME=$(echo "$ROOT_PART" | sed 's|/dev/||')
# Find the disk
ROOT_DISK=$(lsblk -rno PKNAME "$ROOT_PARTNAME" 2>/dev/null || true)

BOOT_PART=""
if [ -n "$ROOT_DISK" ]; then
    # Look for a separate /boot partition on the same disk
    for part in $(lsblk -rno NAME "/dev/$ROOT_DISK" 2>/dev/null | awk '{print "/dev/"$1}'); do
        [ "$part" = "$ROOT_PART" ] && continue
        fstype=$(blkid "$part" 2>/dev/null | grep -oP 'TYPE="\K[^"]+' || true)
        case "$fstype" in
            ext2|ext3|ext4)
                tmpmnt=$(mktemp -d)
                if mount -o ro "$part" "$tmpmnt" 2>/dev/null; then
                    # Check for boot files (vmlinuz, initrd)
                    if ls "$tmpmnt/vmlinuz"* "$tmpmnt/initrd"* &>/dev/null; then
                        boot_size=$(du -sh "$tmpmnt" 2>/dev/null | awk '{print $1}')
                        echo -e "  ${GREEN}[BOOT]${NC} $part (size: $boot_size)"
                        BOOT_PART="$part"
                    fi
                    umount "$tmpmnt" 2>/dev/null
                fi
                rmdir "$tmpmnt" 2>/dev/null
                ;;
        esac
    done
fi

if [ -z "$BOOT_PART" ]; then
    # /boot is inside root
    BOOT_PART="$ROOT_PART"
    info "No separate /boot partition found — /boot is inside root at $ROOT_PART"
    NEED_SHRINK=0
else
    boot_size_raw=$(blkid -s TYPE -o value "$BOOT_PART" 2>/dev/null)
    boot_total=$(lsblk -bno SIZE "$BOOT_PART" 2>/dev/null)
    boot_gb=$(( boot_total / 1073741824 ))
    info "Separate /boot at $BOOT_PART (${boot_gb}GB)"
    if [ "$boot_gb" -gt 5 ]; then
        NEED_SHRINK=1
        warn "/boot is ${boot_gb}GB — will shrink to 1GB"
    else
        NEED_SHRINK=0
        ok "/boot size is reasonable"
    fi
fi

# Step 4: Confirm action
echo ""
echo -e "${RED}${BOLD}WARNING: This will repartition your disk!${NC}"
echo "  Root: $ROOT_PART"
echo "  Boot: $BOOT_PART"
[ "$NEED_SHRINK" -eq 1 ] && echo "  Action: Shrink /boot from ${boot_gb}GB to 1GB"
echo ""
echo -ne "  Proceed? [y/N] "
read -r confirm
case "$confirm" in [Yy]*) ;; *) echo "Cancelled"; exit 0 ;; esac

# Step 5: Mount root
echo -e "\n${BOLD}=== MOUNTING ROOT ===${NC}"
WORK_DIR="/tmp/sysmedic-work"
mkdir -p "$WORK_DIR"
mount "$ROOT_PART" "$WORK_DIR"
ok "Root mounted at $WORK_DIR"

# Step 6: Backup boot contents
echo -e "\n${BOLD}=== BACKING UP /boot ===${NC}"
BACKUP_DIR=$(mktemp -d)

if [ "$BOOT_PART" != "$ROOT_PART" ]; then
    # Separate boot partition
    mkdir -p /tmp/boot-mount
    mount "$BOOT_PART" /tmp/boot-mount
    cp -a /tmp/boot-mount/* "$BACKUP_DIR/"
    umount /tmp/boot-mount
    rmdir /tmp/boot-mount
else
    cp -a "$WORK_DIR/boot/"* "$BACKUP_DIR/"
fi

backup_count=$(ls "$BACKUP_DIR" | wc -l)
ok "Backed up $backup_count boot files to $BACKUP_DIR"
du -sh "$BACKUP_DIR"

# Step 7: Shrink boot partition if needed
if [ "$NEED_SHRINK" -eq 1 ]; then
    echo -e "\n${BOLD}=== RESIZING /BOOT TO 1GB ===${NC}"

    # Get disk and partition number
    boot_devname=$(echo "$BOOT_PART" | sed 's|/dev/||')
    boot_disk=$(lsblk -rno PKNAME "$boot_devname" 2>/dev/null)
    boot_partnum=$(lsblk -rno MAJ:MIN "$boot_devname" 2>/dev/null | cut -d: -f2 || echo "$boot_devname" | grep -oP '[0-9]+$')

    info "Disk: /dev/$boot_disk  Partition: $boot_partnum"

    # Get partition start sector (must preserve this!)
    boot_start=$(fdisk -l "/dev/$boot_disk" 2>/dev/null | grep "^/dev/${boot_devname}" | awk '{print $2}')
    info "Boot partition starts at sector: $boot_start"

    # Calculate new end sector (1GB = ~2097152 sectors of 512 bytes)
    boot_end=$(( boot_start + 2097152 ))
    info "New boot partition will end at sector: $boot_end"

    # Unmount root too
    umount "$WORK_DIR"

    # Repartition
    info "Repartitioning /dev/$boot_disk partition $boot_partnum..."
    sfdisk "/dev/$boot_disk" <<EOF 2>&1 | tee /tmp/sfdisk-output.log
delete $boot_partnum
write
EOF

    # Small delay for kernel to register
    sleep 2
    partprobe "/dev/$boot_disk" 2>/dev/null || true
    sleep 1

    # Recreate partition
    sfdisk "/dev/$boot_disk" <<EOF 2>&1 | tee -a /tmp/sfdisk-output.log
${boot_start},${boot_end},L,83
write
EOF

    sleep 2
    partprobe "/dev/$boot_disk" 2>/dev/null || true
    sleep 2

    # Find the new partition device (might be same or different)
    # Re-find boot partition by start sector
    NEW_BOOT_PART=$(lsblk -rno NAME "/dev/$boot_disk" 2>/dev/null | while read name; do
        start=$(fdisk -l "/dev/$boot_disk" 2>/dev/null | grep "^/dev/${name}" | awk '{print $2}')
        [ "$start" = "$boot_start" ] && echo "/dev/$name"
    done)

    if [ -z "$NEW_BOOT_PART" ]; then
        # Fallback: same name
        NEW_BOOT_PART="$BOOT_PART"
    fi

    info "New boot partition: $NEW_BOOT_PART"

    # Create ext4 filesystem
    info "Creating ext4 filesystem..."
    mkfs.ext4 -L "boot" "$NEW_BOOT_PART"

    # Mount and restore
    mkdir -p /tmp/boot-mount
    mount "$NEW_BOOT_PART" /tmp/boot-mount
    cp -a "$BACKUP_DIR"/* /tmp/boot-mount/
    umount /tmp/boot-mount
    rmdir /tmp/boot-mount

    ok "/boot resized to 1GB and files restored"

    # Update fstab if partition UUID changed
    new_uuid=$(blkid -s UUID -o value "$NEW_BOOT_PART")
    info "New boot UUID: $new_uuid"

    # Mount root again for fstab update
    mount "$ROOT_PART" "$WORK_DIR"

    # Find old boot UUID in fstab
    old_uuid=$(grep '/boot' "$WORK_DIR/etc/fstab" 2>/dev/null | grep -oP 'UUID=\K[^ ]+' || true)
    if [ -n "$old_uuid" ] && [ "$old_uuid" != "$new_uuid" ]; then
        info "Updating fstab: $old_uuid → $new_uuid"
        sed -i "s|UUID=${old_uuid}|UUID=${new_uuid}|g" "$WORK_DIR/etc/fstab"
        ok "fstab updated"
    fi

    BOOT_PART="$NEW_BOOT_PART"
else
    # No resize needed, but mount root was already done
    if [ "$BOOT_PART" != "$ROOT_PART" ]; then
        mkdir -p "$WORK_DIR/boot"
        mount "$BOOT_PART" "$WORK_DIR/boot"
    fi
fi

# Step 8: Chroot and regenerate initramfs + GRUB
echo -e "\n${BOLD}=== ENTERING CHROOT ===${NC}"

# Bind mount for chroot
for dir in /dev /dev/pts /proc /sys /run; do
    mount --bind "$dir" "$WORK_DIR$dir"
done

# Copy DNS resolution
cp /etc/resolv.conf "$WORK_DIR/etc/resolv.conf"

# Run initramfs regeneration
info "Regenerating initramfs..."
chroot "$WORK_DIR" bash -c '
    # Find current kernel version
    KERNEL=$(ls /lib/modules/ | sort -V | tail -1)
    echo "Kernel: $KERNEL"

    # Regenerate initramfs for this kernel
    echo "Running update-initramfs..."
    update-initramfs -c -k "$KERNEL" -v 2>&1 | tail -5

    # Also regenerate for all kernels
    echo "Running update-initramfs -u -k all..."
    update-initramfs -u -k all 2>&1 | tail -5

    # Check result
    echo "Boot contents:"
    ls -la /boot/vmlinuz* /boot/initrd* 2>/dev/null
'

# Update GRUB
echo ""
info "Updating GRUB..."
chroot "$WORK_DIR" bash -c '
    update-grub 2>&1 | tail -10
'

# Cleanup chroot
for dir in /run /sys /proc /dev/pts /dev; do
    umount "$WORK_DIR$dir" 2>/dev/null
done

# Unmount boot if separate
if [ "$BOOT_PART" != "$ROOT_PART" ]; then
    umount "$WORK_DIR/boot" 2>/dev/null
fi

# Unmount root
umount "$WORK_DIR"

# Cleanup
rm -rf "$WORK_DIR" "$BACKUP_DIR"

echo ""
echo -e "${GREEN}${BOLD}=== REPAIR COMPLETE ===${NC}"
echo ""
echo "  The following was done:"
[ "$NEED_SHRINK" -eq 1 ] && echo "  ✓ /boot shrunk from ${boot_gb}GB to 1GB"
echo "  ✓ initramfs regenerated"
echo "  ✓ GRUB updated"
[ "${old_uuid:-}" != "${new_uuid:-}" ] && echo "  ✓ fstab updated with new boot UUID"
echo ""
echo -e "  ${YELLOW}You can now reboot the target machine.${NC}"
echo ""
echo -ne "  Reboot? [y/N] "
read -r rb
case "$rb" in [Yy]*) reboot ;; *) echo "Done";; esac
