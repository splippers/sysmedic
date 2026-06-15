#!/usr/bin/env bash
# SysMedic - Fix /etc/fstab
# Detects broken fstab entries (wrong UUIDs, missing devices) and repairs them

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

echo -e "${BOLD}=== SysMedic: Fix /etc/fstab ===${NC}\n"

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

WORK_DIR="/tmp/sysmedic-work"
mkdir -p "$WORK_DIR"
mount "$ROOT_PART" "$WORK_DIR"

echo -e "\n${BOLD}=== CURRENT FSTAB ===${NC}"
cat -n "$WORK_DIR/etc/fstab" 2>/dev/null | sed 's/^/  /'

# Build list of all available partitions and their UUIDs
echo -e "\n${BOLD}=== AVAILABLE PARTITIONS ===${NC}"
declare -A partition_map
while IFS= read -r line; do
    dev=$(echo "$line" | cut -d: -f1)
    uuid=$(echo "$line" | grep -oP 'UUID="\K[^"]+' || true)
    label=$(echo "$line" | grep -oP 'LABEL="\K[^"]+' || true)
    fstype=$(echo "$line" | grep -oP 'TYPE="\K[^"]+' || true)
    echo -e "  ${GREEN}$dev${NC}  uuid=$uuid  type=$fstype  label=$label"
    [ -n "$uuid" ] && partition_map["$uuid"]="$dev"
done < <(blkid 2>/dev/null)

# Analyze fstab
echo -e "\n${BOLD}=== FSTAB ANALYSIS ===${NC}"
broken=0
fixed_fstab=""

while IFS= read -r line; do
    # Skip comments and blank lines
    echo "$line" | grep -qP '^\s*#|^\s*$' && { echo "  OK (comment/blank): $(echo "$line" | head -c 60)"; continue; }

    # Check if it uses UUID
    uuid=$(echo "$line" | grep -oP 'UUID=\K[^ ]+' || true)
    if [ -n "$uuid" ]; then
        if [ -n "${partition_map[$uuid]:-}" ]; then
            echo "  ${GREEN}OK${NC}     UUID=$uuid → ${partition_map[$uuid]}"
        else
            echo "  ${RED}BROKEN${NC} UUID=$uuid (no such partition found)"
            broken=$((broken+1))
        fi
    else
        mount_point=$(echo "$line" | awk '{print $2}')
        device=$(echo "$line" | awk '{print $1}')
        echo "  ${YELLOW}CHECK${NC}  device=$device → mount=$mount_point (non-UUID entry)"
    fi
done < "$WORK_DIR/etc/fstab"

echo ""
if [ "$broken" -eq 0 ]; then
    ok "fstab looks valid"
    umount "$WORK_DIR"; rmdir "$WORK_DIR"
    exit 0
fi

warn "$broken broken UUID reference(s) found"
echo -ne "\n  Attempt auto-repair? [y/N] "
read -r confirm
case "$confirm" in [Yy]*) ;; *) umount "$WORK_DIR"; rmdir "$WORK_DIR"; exit 0 ;; esac

# Auto-repair: find the correct UUID for each broken entry
# Strategy: match by mount point type (/ = root, /boot = boot partition, etc.)
echo -e "\n${BOLD}=== REPAIRING ===${NC}"

root_uuid=$(blkid "$ROOT_PART" 2>/dev/null | grep -oP 'UUID="\K[^"]+' || true)

new_fstab=""
while IFS= read -r line; do
    echo "$line" | grep -qP '^\s*#|^\s*$' && { new_fstab+="$line"$'\n'; continue; }

    uuid=$(echo "$line" | grep -oP 'UUID=\K[^ ]+' || true)
    mount_point=$(echo "$line" | awk '{print $2}')

    if [ -n "$uuid" ] && [ -z "${partition_map[$uuid]:-}" ]; then
        # Find correct UUID based on mount point
        correct_uuid=""
        case "$mount_point" in
            /) correct_uuid="$root_uuid" ;;
            /boot|/boot/efi)
                # Find boot/efi partition on same disk
                root_devname=$(echo "$ROOT_PART" | sed 's|/dev/||')
                root_disk=$(lsblk -rno PKNAME "$root_devname" 2>/dev/null || true)
                for part in $(lsblk -rno NAME "/dev/$root_disk" 2>/dev/null | awk '{print "/dev/"$1}'); do
                    [ "$part" = "$ROOT_PART" ] && continue
                    part_type=$(blkid "$part" 2>/dev/null | grep -oP 'TYPE="\K[^"]+' || true)
                    if [ "$mount_point" = "/boot/efi" ] && [ "$part_type" = "vfat" ]; then
                        correct_uuid=$(blkid -s UUID -o value "$part" 2>/dev/null || true)
                        break
                    elif [ "$mount_point" = "/boot" ] && [[ "$part_type" =~ ext[234] ]]; then
                        tmpmnt=$(mktemp -d)
                        if mount -o ro "$part" "$tmpmnt" 2>/dev/null; then
                            if ls "$tmpmnt/vmlinuz"* &>/dev/null; then
                                correct_uuid=$(blkid -s UUID -o value "$part" 2>/dev/null || true)
                            fi
                            umount "$tmpmnt" 2>/dev/null
                        fi
                        rmdir "$tmpmnt" 2>/dev/null
                    fi
                done
                ;;
        esac

        if [ -n "$correct_uuid" ]; then
            new_line=$(echo "$line" | sed "s|UUID=${uuid}|UUID=${correct_uuid}|")
            info "Fixed: $mount_point UUID=${uuid:0:8}... → UUID=${correct_uuid:0:8}..."
            new_fstab+="$new_line"$'\n'
        else
            warn "Could not find correct UUID for $mount_point — preserving original"
            new_fstab+="$line"$'\n'
        fi
    else
        new_fstab+="$line"$'\n'
    fi
done < "$WORK_DIR/etc/fstab"

# Write new fstab
echo "$new_fstab" > "$WORK_DIR/etc/fstab"

echo ""
echo -e "${BOLD}=== NEW FSTAB ===${NC}"
cat -n "$WORK_DIR/etc/fstab" 2>/dev/null | sed 's/^/  /'

# Cleanup
umount "$WORK_DIR" 2>/dev/null
rmdir "$WORK_DIR" 2>/dev/null

echo ""
echo -e "${GREEN}${BOLD}=== DONE ===${NC}"
echo "  fstab has been repaired."
echo "  If /boot UUID was changed, also run fix-kernel-panic.sh to update GRUB."
