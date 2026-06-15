# SysMedic - Partition & OS Scanner
# SysMedic - Partition & OS Scanner
# Detects all partitions, filesystems, and installed operating systems

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

echo -e "${BOLD}=== BLOCK DEVICES ===${NC}"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL 2>/dev/null | grep -v loop
echo ""

echo -e "${BOLD}=== PARTITION TABLES ===${NC}"
for disk in $(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print "/dev/"$1}'); do
    echo -e "\n  ${BOLD}$disk${NC}:"
    sudo fdisk -l "$disk" 2>/dev/null | grep -E "^Disk|^\s*Device|^\s*/dev"
done
echo ""

echo -e "${BOLD}=== FILESYSTEM DETAILS ===${NC}"
for part in $(lsblk -dn -o NAME,TYPE | awk '$2=="part"{print "/dev/"$1}'); do
    label=$(sudo blkid "$part" 2>/dev/null | grep -oP 'LABEL="\K[^"]+' || echo "(none)")
    uuid=$(sudo blkid "$part" 2>/dev/null | grep -oP 'UUID="\K[^"]+' || echo "(none)")
    fstype=$(sudo blkid "$part" 2>/dev/null | grep -oP 'TYPE="\K[^"]+' || echo "(unknown)")
    echo -e "  ${BOLD}$part${NC}  type=$fstype  label=$label  uuid=$uuid"
done
echo ""

echo -e "${BOLD}=== DETECTED OPERATING SYSTEMS ===${NC}"
os_found=0
for part in $(lsblk -dn -o NAME,TYPE | awk '$2=="part"{print "/dev/"$1}'); do
    fstype=$(sudo blkid "$part" 2>/dev/null | grep -oP 'TYPE="\K[^"]+' || true)
    case "$fstype" in
        ext2|ext3|ext4|btrfs|xfs)
            tmpmnt=$(mktemp -d)
            sudo mount -o ro "$part" "$tmpmnt" 2>/dev/null
            if [ $? -eq 0 ]; then
                # Check for Linux OS
                if [ -f "$tmpmnt/etc/os-release" ]; then
                    os_found=$((os_found+1))
                    os_name=$(grep -oP '^PRETTY_NAME="\K[^"]+' "$tmpmnt/etc/os-release" 2>/dev/null || echo "Unknown Linux")
                    hostname=$(cat "$tmpmnt/etc/hostname" 2>/dev/null || echo "(none)")
                    echo -e "  ${GREEN}[LINUX]${NC} $part → $os_name (hostname: $hostname)"
                    # Check boot
                    boot_size=$(du -sh "$tmpmnt/boot" 2>/dev/null | awk '{print $1}' || echo "N/A")
                    echo -e "           /boot size: $boot_size"
                    # Check fstab
                    echo -e "           fstab entries: $(grep -c '^[^#]' "$tmpmnt/etc/fstab" 2>/dev/null || echo 0)"
                fi
                # Check for Windows
                if [ -d "$tmpmnt/Windows" ]; then
                    os_found=$((os_found+1))
                    echo -e "  ${GREEN}[WIN]${NC}   $part → Windows detected"
                    # Check boot
                    [ -d "$tmpmnt/EFI" ] && echo -e "           UEFI boot: yes"
                    [ -d "$tmpmnt/Boot" ] && echo -e "           Legacy boot: yes"
                fi
                sudo umount "$tmpmnt" 2>/dev/null
            fi
            rmdir "$tmpmnt" 2>/dev/null
            ;;
        vfat)
            tmpmnt=$(mktemp -d)
            sudo mount -o ro "$part" "$tmpmnt" 2>/dev/null
            if [ $? -eq 0 ]; then
                if [ -d "$tmpmnt/EFI" ]; then
                    echo -e "  ${YELLOW}[EFI]${NC}   $part → EFI System Partition (bootable)"
                    # List boot entries
                    sudo find "$tmpmnt" -name '*.efi' -maxdepth 4 2>/dev/null | while read efi; do
                        echo -e "           $(echo $efi | sed "s|$tmpmnt||")"
                    done
                fi
                sudo umount "$tmpmnt" 2>/dev/null
            fi
            rmdir "$tmpmnt" 2>/dev/null
            ;;
        ntfs)
            tmpmnt=$(mktemp -d)
            sudo mount -o ro "$part" "$tmpmnt" 2>/dev/null
            if [ $? -eq 0 ]; then
                if [ -d "$tmpmnt/Windows" ]; then
                    os_found=$((os_found+1))
                    echo -e "  ${GREEN}[WIN]${NC}   $part → Windows detected (NTFS)"
                fi
                sudo umount "$tmpmnt" 2>/dev/null
            fi
            rmdir "$tmpmnt" 2>/dev/null
            ;;
    esac
done

[ $os_found -eq 0 ] && warn "No operating systems detected"
echo ""
echo -e "${BOLD}=== SWAP ===${NC}"
swapon --show 2>/dev/null || info "No active swap"
echo ""
echo -e "${BOLD}=== LVM ===${NC}"
sudo pvs 2>/dev/null || info "No physical volumes"
sudo vgs 2>/dev/null || info "No volume groups"
sudo lvs 2>/dev/null || info "No logical volumes"
