#!/usr/bin/env bash
# SysMedic - Recover Data from macOS Volumes
# Copies user data from HFS+/APFS to a target drive

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC}   $1"; }
fail()  { echo -e "  ${RED}[FAIL]${NC}   $1"; }
header(){ echo -e "\n${BOLD}$1${NC}\n"; }

header "macOS Data Recovery"
echo ""

# Step 1: Find target drive for backup
info "Scanning for backup destinations..."
echo ""
echo -e "  ${BOLD}Available drives:${NC}"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null | grep -v loop
echo ""

# Step 2: Let user pick a recovery target
read -p "  Mount target backup drive to /mnt/recover? [y/N]: " do_mount
if [ "$do_mount" = "y" ] || [ "$do_mount" = "Y" ]; then
    read -p "  Enter target device (e.g. /dev/sda1): " target_dev
    mkdir -p /mnt/recover
    if mount "$target_dev" /mnt/recover 2>/dev/null; then
        ok "Target mounted at /mnt/recover"
    else
        fail "Could not mount $target_dev"
        exit 1
    fi
else
    # Try persistence partition
    if [ -d /mnt/persist ]; then
        mkdir -p /mnt/persist/recovered_mac
        TARGET="/mnt/persist/recovered_mac"
        info "Using persistence partition: $TARGET"
    else
        fail "No recovery target available"
        echo "  Mount a USB drive first, then re-run this script"
        exit 1
    fi
fi

# Step 3: Mount all macOS volumes
header "Mounting macOS Volumes"
MOUNT_BASE="/mnt/mac"
mkdir -p "$MOUNT_BASE"

# HFS+
for dev in $(lsblk -nro NAME,FSTYPE 2>/dev/null | grep -E 'hfs|hfsplus' | awk '{print "/dev/"$1}'); do
    label=$(blkid -s LABEL -o value "$dev" 2>/dev/null)
    label="${label:-untitled}"
    mp="${MOUNT_BASE}/hfs_${label}"
    mkdir -p "$mp"
    mount -t hfsplus -o force,rw "$dev" "$mp" 2>/dev/null && ok "Mounted $dev → $mp" || fail "Could not mount $dev"
done

# APFS
for dev in $(lsblk -nro NAME 2>/dev/null | grep -v loop | awk '{print "/dev/"$1}'); do
    if fsapfsinfo "$dev" 2>/dev/null | grep -q "APFS"; then
        label=$(fsapfsinfo "$dev" 2>/dev/null | grep "volume name" | head -1 | cut -d: -f2 | xargs)
        label="${label:-apfs}"
        mp="${MOUNT_BASE}/apfs_${label}"
        mkdir -p "$mp"
        fsapfsmount "$dev" "$mp" 2>/dev/null && ok "Mounted $dev → $mp (ro)" || fail "Could not mount $dev"
    fi
done

# Step 4: Find and recover user data
header "Recovering User Data"
TARGET="${TARGET:-/mnt/recover}"
found_data=0

for mac_dir in "$MOUNT_BASE"/*/; do
    [ -d "$mac_dir" ] || continue
    vol_label=$(basename "$mac_dir")
    
    # Look for macOS user data locations
    for src in \
        "$mac_dir/Users" \
        "$mac_dir/Home" \
        "$mac_dir/private/var/root" \
        "$mac_dir/private/var/db/dslocal" \
        "$mac_dir/Library/Application Support"; do
        if [ -d "$src" ]; then
            rel_path="${src#$mac_dir}"
            target_subdir="${TARGET}/${vol_label}${rel_path}"
            mkdir -p "$target_subdir"
            
            echo -e "  ${CYAN}Copying ${src#$mac_dir} from $vol_label...${NC}"
            rsync -ah --progress "$src/" "$target_subdir/" 2>/dev/null && \
                ok "Copied → $target_subdir" || \
                warn "Partial copy to $target_subdir"
            found_data=1
        fi
    done
    
    # Also grab common user-visible folders at root
    for dir in "Desktop" "Documents" "Downloads" "Pictures" "Movies" "Music"; do
        find "$mac_dir" -maxdepth 4 -type d -name "$dir" 2>/dev/null | while read -r found_dir; do
            rel="${found_dir#$mac_dir}"
            target="${TARGET}/${vol_label}${rel}"
            mkdir -p "$(dirname "$target")"
            echo -e "  ${CYAN}Found $dir — copying...${NC}"
            rsync -ah --progress "$found_dir/" "$target/" 2>/dev/null
            ok "Copied → $target"
            found_data=1
        done
    done
done

# Step 5: Summary
echo ""
header "Recovery Complete"
if [ "$found_data" -eq 1 ]; then
    ok "Data recovered to: $TARGET"
    echo -e "  Size: $(du -sh "$TARGET" 2>/dev/null | cut -f1)"
else
    warn "No macOS user data found"
    echo "  The volumes may be empty or the data is in a non-standard location"
    echo "  Try mounting manually and browsing:"
    echo "    ls -la $MOUNT_BASE/"
fi

# Cleanup hint
echo ""
info "To unmount: umount -R $MOUNT_BASE"
info "To eject target: umount $TARGET"
