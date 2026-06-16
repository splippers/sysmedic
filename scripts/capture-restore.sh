#!/bin/bash
# SysMedic Capture/Restore — OS image capture & restore module
# Captures installed OSes with partition tables, compresses with zstd
# Restores to disk with partition table + bootloader repair

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}$1${NC}"; }
ok()    { echo -e "  ${GREEN}✅ $1${NC}"; }
warn()  { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
fail()  { echo -e "  ${RED}❌ $1${NC}"; }
header(){ echo -e "${BOLD}\n  ╔══════════════════════════════════════════════════════════════╗${NC}"; 
          echo -e "${BOLD}  ║  $1${NC}"; 
          echo -e "${BOLD}  ╚══════════════════════════════════════════════════════════════╝${NC}"; }

DEFAULT_CAPTURE_DIR="/mnt/sandisk/captures"
TMP_MOUNT="/mnt/tmp_capture"

# ──────────────────────────────────────────────
# Detect installed OSes across all block devices
# ──────────────────────────────────────────────
detect_oses() {
    local results=()
    local index=0
    mkdir -p "$TMP_MOUNT" 2>/dev/null

    for dev in $(lsblk -nlo NAME,FSTYPE 2>/dev/null | grep -E 'ntfs|ext4|vfat|fat32|hfsplus|apfs' | awk '{print "/dev/"$1}'); do
        # Skip partitions that are already mounted
        mount | grep -q "^$dev " && continue

        if mount "$dev" "$TMP_MOUNT" 2>/dev/null; then
            local os_name="" os_type="" os_ver="" disk=""
            disk=$(lsblk -ndo PKNAME "$dev" 2>/dev/null | sed 's/^/\/dev\//')

            # Check for Windows
            if [ -d "$TMP_MOUNT/Windows/System32" ]; then
                os_type="windows"
                os_name="Windows"
                # Try to get version from Software registry (basic check)
                if [ -f "$TMP_MOUNT/Windows/System32/license.rtf" ]; then
                    os_ver=$(head -1 "$TMP_MOUNT/Windows/System32/license.rtf" 2>/dev/null | tr -dc '[:print:]' | head -c 80)
                fi
                [ -z "$os_ver" ] && os_ver="Windows 10/11"
            # Check for Linux
            elif [ -f "$TMP_MOUNT/etc/os-release" ]; then
                os_type="linux"
                os_name=$(grep PRETTY_NAME "$TMP_MOUNT/etc/os-release" 2>/dev/null | cut -d= -f2 | tr -d '"')
                os_ver=$(grep VERSION_ID "$TMP_MOUNT/etc/os-release" 2>/dev/null | cut -d= -f2 | tr -d '"')
            # Check for macOS
            elif [ -d "$TMP_MOUNT/System/Library/CoreServices" ]; then
                os_type="macos"
                os_name="macOS"
                if [ -f "$TMP_MOUNT/System/Library/CoreServices/SystemVersion.plist" ]; then
                    os_ver=$(grep -A1 'ProductVersion' "$TMP_MOUNT/System/Library/CoreServices/SystemVersion.plist" 2>/dev/null | tail -1 | sed 's/.*<string>//;s/<\/string>//')
                fi
            fi

            umount "$TMP_MOUNT" 2>/dev/null

            if [ -n "$os_type" ]; then
                local fstype=$(lsblk -nlo FSTYPE "$dev" 2>/dev/null)
                local size=$(lsblk -nlo SIZE "$dev" 2>/dev/null)
                results+=("$index|$dev|$disk|$os_name|$os_ver|$fstype|$size|$os_type")
                index=$((index + 1))
            fi
        fi
    done
    rmdir "$TMP_MOUNT" 2>/dev/null

    # Return the array
    for r in "${results[@]}"; do
        echo "$r"
    done
}

# ──────────────────────────────────────────────
# Find all partitions belonging to a disk
# ──────────────────────────────────────────────
get_disk_partitions() {
    local disk="$1"
    lsblk -nlo NAME,TYPE,FSTYPE,SIZE "$disk" 2>/dev/null | grep " part " | awk '{print "/dev/"$1, $3, $4}'
}

# ──────────────────────────────────────────────
# Detect disk from a partition
# ──────────────────────────────────────────────
get_parent_disk() {
    local dev="$1"
    local basename=$(basename "$dev")
    # Remove trailing digits to get parent
    local parent=$(echo "$basename" | sed 's/[0-9]*$//' | sed 's/p[0-9]*$//')
    # Handle NVMe naming (nvme0n1p1 → nvme0n1)
    parent=$(echo "$parent" | sed 's/p$//')
    echo "/dev/$parent"
}

# ──────────────────────────────────────────────
# Show capture directory selection
# ──────────────────────────────────────────────
select_capture_dir() {
    local current_dir="$1"
    echo ""
    info "Capture storage directory"
    echo "  Current: $current_dir"
    echo ""
    echo "  Available mount points:"
    df -h 2>/dev/null | grep -E '^/dev/' | awk '{printf "    %-15s %8s free  %s\n", $1, $4, $6}'
    echo ""
    read -p "  Press Enter to use current, or type new path: " new_dir
    if [ -n "$new_dir" ]; then
        mkdir -p "$new_dir" 2>/dev/null
        if [ -d "$new_dir" ]; then
            echo "$new_dir"
        else
            warn "Cannot create directory, using default"
            echo "$current_dir"
        fi
    else
        echo "$current_dir"
    fi
}

# ──────────────────────────────────────────────
# Capture an OS
# ──────────────────────────────────────────────
capture_os() {
    header "  CAPTURE INSTALLED OS"

    info "Scanning for installed operating systems..."
    sleep 1
    mapfile -t oses < <(detect_oses)

    if [ ${#oses[@]} -eq 0 ]; then
        fail "No installed OSes detected"
        read -p "  Press Enter..."
        return
    fi

    echo ""
    echo -e "  ${BOLD}Detected OSes:${NC}"
    echo "  ────────────────────────────────────"
    for entry in "${oses[@]}"; do
        IFS='|' read -r idx dev disk name ver fstype size otype <<< "$entry"
        printf "  [%d]  %-12s %-8s  %s %s  (%s, %s)\n" "$idx" "$name" "$size" "$ver" "$fstype" "$dev"
    done
    echo ""

    read -p "  Select OS to capture [0-$((${#oses[@]}-1))]: " sel
    if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -ge "${#oses[@]}" ]; then
        fail "Invalid selection"
        read -p "  Press Enter..."
        return
    fi

    IFS='|' read -r idx dev disk name ver fstype size otype <<< "${oses[$sel]}"

    echo ""
    echo -e "  Selected: ${BOLD}$name ($ver)${NC} on $dev"
    echo ""

    # Get capture directory
    CAPTURE_DIR=$(select_capture_dir "$DEFAULT_CAPTURE_DIR")
    mkdir -p "$CAPTURE_DIR" 2>/dev/null

    # Create dated capture name
    local date_str=$(date +%Y-%m-%d)
    local safe_name=$(echo "$name $ver" | tr -c '[:alnum:]._-' '_' | head -c 40)
    local hostname=$(cat "$TMP_MOUNT/etc/hostname" 2>/dev/null || echo "unknown")
    local capture_name="${date_str}_${safe_name}"
    local capture_path="${CAPTURE_DIR}/${capture_name}"

    if [ -d "$capture_path" ]; then
        warn "Capture directory already exists: $capture_path"
        read -p "  Overwrite? [y/N]: " ovr
        if [ "$ovr" != "y" ] && [ "$ovr" != "Y" ]; then
            info "Capture cancelled"
            read -p "  Press Enter..."
            return
        fi
        rm -rf "${capture_path:?}"/*
    fi
    mkdir -p "$capture_path"

    echo ""
    info "Capturing $name to: $capture_path"
    echo ""

    # Get the parent disk for partition table
    local parent_disk=$(get_parent_disk "$dev")
    echo "  Parent disk: $parent_disk"

    # Save partition table
    echo ""
    info "Saving partition table..."
    sfdisk -d "$parent_disk" > "${capture_path}/partition_table.sfdisk" 2>/dev/null
    if [ $? -eq 0 ]; then
        ok "Partition table saved (${capture_path}/partition_table.sfdisk)"
    else
        warn "Could not save partition table (try running as root)"
    fi

    # Also save fdisk -l output for human reading
    fdisk -l "$parent_disk" > "${capture_path}/fdisk_output.txt" 2>/dev/null

    # Find all partitions on the same disk
    mapfile -t partitions < <(lsblk -nlo NAME,TYPE,FSTYPE,SIZE "$parent_disk" 2>/dev/null | grep " part " | awk '{print $1, $3, $4}')
    local part_count=0

    for part_entry in "${partitions[@]}"; do
        local part_dev="/dev/$(echo $part_entry | awk '{print $1}')"
        local part_fs=$(echo $part_entry | awk '{print $2}')
        local part_size=$(echo $part_entry | awk '{print $3}')
        local part_num=$(echo "$part_dev" | grep -oP '\d+$' || echo "unknown")
        local part_label="part${part_num}"

        # Skip if it's the EFI partition or MSR — still capture them but with appropriate labels
        if [ "$part_fs" = "vfat" ] || [ "$part_fs" = "fat32" ]; then
            part_label="${part_label}_EFI"
        elif [ "$part_fs" = "ntfs" ]; then
            part_label="${part_label}_Windows"
        elif [ "$part_fs" = "ext4" ]; then
            part_label="${part_label}_Linux"
        elif [ "$part_fs" = "hfsplus" ] || [ "$part_fs" = "apfs" ]; then
            part_label="${part_label}_macOS"
        else
            part_label="${part_label}_${part_fs}"
        fi

        echo ""
        info "Partition $part_num: $part_dev ($part_fs, $part_size)"
        local image_file="${capture_path}/${part_label}.img"

        case "$part_fs" in
            ntfs)
                echo "  → Using partclone.ntfs"
                partclone.ntfs -c -s "$part_dev" -o - 2>/dev/null | zstd -3 -o "${image_file}.zst" 2>/dev/null
                if [ $? -eq 0 ]; then
                    ok "Captured NTFS → $(ls -lh "${image_file}.zst" | awk '{print $5}')"
                else
                    warn "partclone.ntfs had issues, falling back to dd"
                    dd if="$part_dev" bs=4M status=none | zstd -3 -o "${image_file}.zst" 2>/dev/null
                    ok "Captured via dd → $(ls -lh "${image_file}.zst" | awk '{print $5}')"
                fi
                ;;
            ext4)
                echo "  → Using partclone.ext4"
                partclone.ext4 -c -s "$part_dev" -o - 2>/dev/null | zstd -3 -o "${image_file}.zst" 2>/dev/null
                if [ $? -eq 0 ]; then
                    ok "Captured ext4 → $(ls -lh "${image_file}.zst" | awk '{print $5}')"
                else
                    warn "partclone.ext4 failed, falling back to dd"
                    dd if="$part_dev" bs=4M status=none | zstd -3 -o "${image_file}.zst" 2>/dev/null
                    ok "Captured via dd → $(ls -lh "${image_file}.zst" | awk '{print $5}')"
                fi
                ;;
            vfat|fat32)
                echo "  → Using dd (FAT32/VFAT)"
                dd if="$part_dev" bs=4M status=none | zstd -3 -o "${image_file}.zst" 2>/dev/null
                ok "Captured EFI/FAT → $(ls -lh "${image_file}.zst" | awk '{print $5}')"
                ;;
            hfsplus)
                echo "  → Using dd (HFS+)"
                dd if="$part_dev" bs=4M status=none | zstd -3 -o "${image_file}.zst" 2>/dev/null
                ok "Captured HFS+ → $(ls -lh "${image_file}.zst" | awk '{print $5}')"
                ;;
            *)
                echo "  → Using dd (raw)"
                dd if="$part_dev" bs=4M status=none | zstd -3 -o "${image_file}.zst" 2>/dev/null
                ok "Captured raw → $(ls -lh "${image_file}.zst" | awk '{print $5}')"
                ;;
        esac
        part_count=$((part_count + 1))
    done

    # Save metadata
    cat > "${capture_path}/metadata.json" << JSON
{
    "capture_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "os": "$name",
    "os_version": "$ver",
    "os_type": "$otype",
    "source_device": "$dev",
    "source_disk": "$parent_disk",
    "partition_count": $part_count,
    "tool": "sysmedic-capture v1.0",
    "compression": "zstd -3",
    "capture_tool": "partclone / dd"
}
JSON

    echo ""
    echo "  ──────────────────────────────────────"
    ok "Capture complete!"
    echo "  Location: $capture_path"
    echo "  Contents:"
    ls -lh "$capture_path" | awk '{print "    " $NF " (" $5 ")"}'
    echo ""
    info "To restore later, use 'Restore from image' in this menu"
    read -p "  Press Enter..."
}

# ──────────────────────────────────────────────
# List captured images
# ──────────────────────────────────────────────
list_captures() {
    local search_dir="${1:-$DEFAULT_CAPTURE_DIR}"

    if [ ! -d "$search_dir" ]; then
        fail "No capture directory found at: $search_dir"
        echo "  Available mount points:"
        df -h 2>/dev/null | grep -E '^/dev/' | awk '{printf "    %-15s %8s free  %s\n", $1, $4, $6}'
        read -p "  Enter capture directory path: " search_dir
        [ -z "$search_dir" ] && return
    fi

    # Find all capture directories
    local captures=()
    for dir in "$search_dir"/*/; do
        [ -d "$dir" ] || continue
        [ -f "${dir}/metadata.json" ] || continue
        captures+=("$dir")
    done

    if [ ${#captures[@]} -eq 0 ]; then
        warn "No captures found in $search_dir"
        echo "  Looking for directories with metadata.json"
        read -p "  Press Enter..."
        return
    fi

    header "  CAPTURED IMAGES"

    local index=0
    for dir in "${captures[@]}"; do
        local name=$(basename "$dir")
        local os=""
        local date=""
        local size=""
        local parts=""

        if [ -f "${dir}/metadata.json" ]; then
            os=$(grep -o '"os": "[^"]*"' "${dir}/metadata.json" | head -1 | cut -d'"' -f4)
            date=$(grep -o '"capture_date": "[^"]*"' "${dir}/metadata.json" | head -1 | cut -d'"' -f4 | cut -dT -f1)
            parts=$(grep -o '"partition_count": [0-9]*' "${dir}/metadata.json" | head -1 | cut -d' ' -f2)
            size=$(du -sh "$dir" 2>/dev/null | awk '{print $1}')
        fi
        printf "  [%d]  %s | %s | %s parts | %s\n" "$index" "${os:-?}" "${date:-?}" "${parts:-?}" "${size:-?}"
        echo -e "       ${CYAN}${name}${NC}"
        index=$((index + 1))
    done
    echo ""

    # Return paths for use by calling function
    if [ "$2" = "return" ]; then
        for dir in "${captures[@]}"; do
            echo "$dir"
        done
    fi
}

# ──────────────────────────────────────────────
# Restore a captured image
# ──────────────────────────────────────────────
restore_capture() {
    header "  RESTORE OS IMAGE"

    # First, let user select capture directory
    local cap_dir="${1:-$DEFAULT_CAPTURE_DIR}"
    if [ ! -d "$cap_dir" ]; then
        warn "Default capture directory not found: $cap_dir"
        echo "  Available mount points:"
        df -h 2>/dev/null | grep -E '^/dev/' | awk '{printf "    %-15s %8s free  %s\n", $1, $4, $6}'
        read -p "  Enter capture directory path: " cap_dir
        [ -z "$cap_dir" ] && return
    fi

    # List captures and let user pick
    mapfile -t captures < <(list_captures "$cap_dir" "return")
    if [ ${#captures[@]} -eq 0 ]; then
        return
    fi

    read -p "  Select capture to restore [0-$((${#captures[@]}-1))]: " sel
    if ! [[ "$sel" =~ ^[0-9]+$ ]] || [ "$sel" -ge "${#captures[@]}" ]; then
        fail "Invalid selection"
        read -p "  Press Enter..."
        return
    fi

    local selected="${captures[$sel]}"
    local name=$(basename "$selected")

    echo ""
    echo -e "  Selected: ${BOLD}$name${NC}"
    echo "  Contents:"
    ls -lh "$selected" | awk '{print "    " $NF " (" $5 ")"}'

    # Read metadata
    if [ -f "${selected}/metadata.json" ]; then
        echo ""
        echo "  Metadata:"
        grep -o '"[^"]*": "[^"]*"' "${selected}/metadata.json" | while read line; do
            echo "    $line"
        done
    fi

    echo ""
    warn "RESTORING WILL OVERWRITE A DISK!"
    echo ""
    echo "  Available target disks:"
    lsblk -d -o NAME,SIZE,MODEL 2>/dev/null | grep -v loop | awk '{printf "    /dev/%-8s %8s  %s\n", $1, $2, $3}'
    echo ""
    read -p "  Target disk (e.g. /dev/sda): " target_disk

    if [ ! -b "$target_disk" ]; then
        fail "Not a valid block device: $target_disk"
        read -p "  Press Enter..."
        return
    fi

    echo ""
    warn "This will DESTROY ALL DATA on $target_disk"
    read -p "  Are you sure? Type the disk name (e.g. sda) to confirm: " confirm
    if [ "$confirm" != "$(basename $target_disk)" ]; then
        info "Restore cancelled"
        read -p "  Press Enter..."
        return
    fi

    # Restore partition table if available
    echo ""
    if [ -f "${selected}/partition_table.sfdisk" ]; then
        info "Restoring partition table to $target_disk..."
        sfdisk "$target_disk" < "${selected}/partition_table.sfdisk" 2>/dev/null
        if [ $? -eq 0 ]; then
            ok "Partition table restored"
            partprobe "$target_disk" 2>/dev/null || true
            sleep 2
        else
            fail "Failed to restore partition table"
            read -p "  Press Enter..."
            return
        fi
    else
        warn "No partition table found — partitioning not restored"
        info "You will need to create partitions manually"
    fi

    # Restore each partition image
    echo ""
    for img in "$selected"/*.zst; do
        [ -f "$img" ] || continue
        local base=$(basename "$img" .zst)
        local part_label=$(echo "$base" | sed 's/\.img$//')

        echo ""
        info "Restoring $part_label..."

        # Determine which partition device to use
        # We need to figure out which partition corresponds to this image
        # Try matching by partition number in the filename
        local part_num=$(echo "$part_label" | grep -oP 'part\d+' | grep -oP '\d+')
        if [ -n "$part_num" ]; then
            local target_part="${target_disk}${part_num}"
            # For NVMe: /dev/nvme0n1p1
            [ -b "${target_part}" ] || target_part="${target_disk}p${part_num}"
        else
            warn "Could not determine partition number from filename"
            continue
        fi

        if [ ! -b "$target_part" ]; then
            warn "Target partition $target_part does not exist — skipping"
            continue
        fi

        echo "  → Target: $target_part"
        echo "  → Decompressing and restoring..."

        # Detect if this was a partclone image or dd image by trying partclone restore first
        local restored=0
        if echo "$part_label" | grep -qiE "ntfs|windows"; then
            zstd -dc "$img" 2>/dev/null | partclone.ntfs -r -o "$target_part" - 2>/dev/null
            restored=$?
        elif echo "$part_label" | grep -qiE "linux|ext4"; then
            zstd -dc "$img" 2>/dev/null | partclone.ext4 -r -o "$target_part" - 2>/dev/null
            restored=$?
        elif echo "$part_label" | grep -qiE "efi|fat"; then
            zstd -dc "$img" 2>/dev/null | dd of="$target_part" bs=4M status=none 2>/dev/null
            restored=$?
        else
            # Try partclone generic, fall back to dd
            zstd -dc "$img" 2>/dev/null | partclone.restore -o "$target_part" - 2>/dev/null
            restored=$?
            if [ $restored -ne 0 ]; then
                zstd -dc "$img" 2>/dev/null | dd of="$target_part" bs=4M status=none 2>/dev/null
                restored=$?
            fi
        fi

        if [ $restored -eq 0 ]; then
            ok "$part_label restored to $target_part"
        else
            warn "$part_label had restore issues (exit code: $restored)"
        fi
    done

    echo ""
    echo "  ──────────────────────────────────────"
    ok "Restore complete!"
    echo ""
    info "You may need to fix the bootloader to boot from the restored disk."
    echo "  For Linux: Use menu option 6 (Fix GRUB bootloader)"
    echo "  For Windows: Use menu option 15 (Fix Windows BCD bootloader)"
    read -p "  Press Enter..."
}

# ──────────────────────────────────────────────
# Interactive menu
# ──────────────────────────────────────────────
interactive_menu() {
    while true; do
        clear
        header "  OS IMAGE CAPTURE / RESTORE"

        echo -e "  ${BOLD}1)  Capture installed OS${NC}"
        echo "       Scans all disks for installed operating systems"
        echo "       and saves partition table + images with compression"
        echo ""
        echo -e "  ${BOLD}2)  Restore from image${NC}"
        echo "       Lists captured images and restores to a target disk"
        echo "       Includes partition table & bootloader prep"
        echo ""
        echo -e "  ${BOLD}3)  List captured images${NC}"
        echo "       Shows all captures with OS, date, size"
        echo ""
        echo -e "  ${BOLD}0)  Back to main menu${NC}"
        echo ""
        read -p "  Choice [0-3]: " subchoice

        case "$subchoice" in
            1) capture_os ;;
            2) restore_capture ;;
            3) list_captures "$DEFAULT_CAPTURE_DIR"; read -p "  Press Enter..." ;;
            0) break ;;
            *) warn "Invalid choice"; sleep 1 ;;
        esac
    done
}

# ──────────────────────────────────────────────
# Main entry point
# ──────────────────────────────────────────────
case "${1:-}" in
    capture|-c|--capture)   capture_os ;;
    restore|-r|--restore)   restore_capture "${2:-}" ;;
    list|-l|--list)         list_captures "${2:-$DEFAULT_CAPTURE_DIR}";;
    *)                      interactive_menu ;;
esac
