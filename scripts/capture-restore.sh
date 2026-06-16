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

DEFAULT_CAPTURE_DIR="/root/sysmedic/captures"
TMP_MOUNT="/mnt/tmp_capture"

# ──────────────────────────────────────────────
# Detect installed OSes across all block devices
# ──────────────────────────────────────────────
detect_oses() {
    local results=()
    local index=0
    mkdir -p "$TMP_MOUNT" 2>/dev/null

    while read -r name fstype; do
        [ -z "$fstype" ] && continue
        local dev=""
        case "$name" in
            *-*)    # LVM or multi-part name
                if [ -b "/dev/mapper/$name" ]; then
                    dev="/dev/mapper/$name"
                elif [ -b "/dev/$name" ]; then
                    dev="/dev/$name"
                else
                    continue
                fi
                ;;
            *)
                dev="/dev/$name"
                ;;
        esac
        [ ! -b "$dev" ] && continue
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
    done < <(lsblk -nlo NAME,FSTYPE 2>/dev/null | grep -E 'ntfs|ext4|vfat|fat32|hfsplus|apfs')
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
    # Use lsblk tree output (works for LVM mapper → PV → disk)
    local pkname
    pkname=$(lsblk -nlpo NAME,PKNAME 2>/dev/null | grep -F "$dev " | awk '{print $2}')
    if [ -n "$pkname" ] && [ -b "$pkname" ]; then
        # pkname is the immediate parent (e.g., /dev/nvme0n1p3 for an LV)
        # Check if it has a grandparent (i.e., it's a partition)
        local grandparent
        grandparent=$(lsblk -nlpo NAME,PKNAME 2>/dev/null | grep -F "$pkname " | awk '{print $2}')
        if [ -n "$grandparent" ] && [ -b "$grandparent" ]; then
            echo "$grandparent"
        else
            echo "$pkname"
        fi
    elif echo "$dev" | grep -q "/mapper/"; then
        # Fallback for LVM: get PV from lvm tools, then strip to disk
        local pv_dev
        pv_dev=$(pvs --noheadings -o pv_name 2>/dev/null | head -1 | sed 's/^ *//')
        if [ -n "$pv_dev" ]; then
            # PV is usually a partition (e.g., /dev/nvme0n1p3) — strip to get disk
            local pv_base=$(basename "$pv_dev")
            local disk_name=$(echo "$pv_base" | sed 's/p[0-9]*$//' | sed 's/[0-9]*$//')
            echo "/dev/$disk_name"
        else
            echo ""
        fi
    else
        # Regular partition → strip trailing digits/NVMe suffix
        local basename=$(basename "$dev")
        local result=$(echo "$basename" | sed 's/p[0-9]*$//' | sed 's/[0-9]*$//')
        echo "/dev/$result"
    fi
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

    # ── Capture LVM logical volumes if the OS lives on one ──
    local lvm_vg=""
    local lvm_lv_count=0
    if command -v lvs &>/dev/null; then
        local lv_path_raw=""
        lv_path_raw=$(lvdisplay "$dev" 2>/dev/null | grep "LV Path" | awk '{print $3}')
        if [ -n "$lv_path_raw" ]; then
            lvm_vg=$(lvdisplay "$dev" 2>/dev/null | grep "VG Name" | awk '{print $3}')
            info "Detected LVM — capturing logical volumes in VG '$lvm_vg'"
            echo ""

            # Back up LVM metadata
            vgcfgbackup -f "${capture_path}/lvm_${lvm_vg}.vgcfg" "$lvm_vg" 2>/dev/null
            if [ $? -eq 0 ]; then
                ok "LVM metadata saved (${capture_path}/lvm_${lvm_vg}.vgcfg)"
            fi

            # List all LVs in this VG
            while read -r lv_path lv_size; do
                [ -z "$lv_path" ] && continue
                local lv_basename=$(basename "$lv_path")
                local lv_label="lvm_${lv_basename}"
                echo ""
                info "LVM LV: $lv_path ($lv_size)"
                local image_file="${capture_path}/${lv_label}.img"

                # Attempt partclone first for compressible FS capture
                echo "  → Capturing logical volume..."
                partclone.ext4 -c -s "$lv_path" -o - 2>/dev/null | zstd -3 -o "${image_file}.zst" 2>/dev/null
                if [ ${PIPESTATUS[0]} -eq 0 ]; then
                    ok "Captured LV ($(ls -lh "${image_file}.zst" | awk '{print $5}'))"
                else
                    warn "partclone failed, falling back to dd"
                    dd if="$lv_path" bs=4M status=none | zstd -3 -o "${image_file}.zst" 2>/dev/null
                    ok "Captured LV via dd ($(ls -lh "${image_file}.zst" | awk '{print $5}'))"
                fi
                lvm_lv_count=$((lvm_lv_count + 1))
            done < <(lvs --noheadings -o lv_path,lv_size --select "vg_name=${lvm_vg}" 2>/dev/null | sed 's/^ *//')
        fi
    fi

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
    "lvm": $( [ -n "$lvm_vg" ] && echo "true" || echo "false" ),
    "lvm_vg": "${lvm_vg:-}",
    "lvm_lv_count": $lvm_lv_count,
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

    # ── Set up LVM if the capture used it ──
    local has_lvm=false
    local lvm_vg=""
    if [ -f "${selected}/metadata.json" ]; then
        has_lvm=$(grep -o '"lvm": true' "${selected}/metadata.json" &>/dev/null && echo true || echo false)
        lvm_vg=$(grep -o '"lvm_vg": "[^"]*"' "${selected}/metadata.json" 2>/dev/null | cut -d'"' -f4)
    fi

    if [ "$has_lvm" = "true" ] && [ -n "$lvm_vg" ] && command -v lvm &>/dev/null; then
        echo ""
        info "Setting up LVM for VG '$lvm_vg'..."
        # Find the LVM PV partition (typically an sda3/nvme0n1p3 with no FS or LVM type)
        local pv_dev=""
        while read -r pv_candidate; do
            [ -z "$pv_candidate" ] && continue
            local pv_fs=$(lsblk -nlo FSTYPE "$pv_candidate" 2>/dev/null)
            # LVM PVs show no filesystem, or have type 'LVM2_member'
            if [ -z "$pv_fs" ] || [ "$pv_fs" = "LVM2_member" ]; then
                # Check if partition type in sfdisk dump indicates LVM
                if grep -q "$(basename $pv_candidate).*LVM\|$(basename $pv_candidate).*8e\|$(basename $pv_candidate).*E6D6D379" "${selected}/fdisk_output.txt" 2>/dev/null; then
                    pv_dev="$pv_candidate"
                    break
                fi
                # Fallback: use first partition with no FS
                [ -z "$pv_dev" ] && pv_dev="$pv_candidate"
            fi
        done < <(lsblk -nlo NAME,TYPE "$target_disk" 2>/dev/null | awk '/ part /{print "/dev/"$1}')

        if [ -n "$pv_dev" ] && [ -b "$pv_dev" ]; then
            echo "  → Initializing PV on $pv_dev..."
            pvcreate -ff "$pv_dev" 2>/dev/null
            # Restore VG metadata if backed up
            if [ -f "${selected}/lvm_${lvm_vg}.vgcfg" ]; then
                echo "  → Restoring VG '$lvm_vg' from backup..."
                vgcfgrestore "$lvm_vg" -f "${selected}/lvm_${lvm_vg}.vgcfg" 2>/dev/null
                # If vgcfgrestore fails (e.g. new disk geometry), create VG manually
                if [ $? -ne 0 ]; then
                    echo "  → vgcfgrestore failed — creating VG manually"
                    vgcreate "$lvm_vg" "$pv_dev" 2>/dev/null
                    # Create LVs with correct sizes from metadata
                    if [ -f "${selected}/metadata.json" ]; then
                        local lv_count=$(grep -o '"lvm_lv_count": [0-9]*' "${selected}/metadata.json" | grep -oP '\d+')
                        if [ "$lv_count" -gt 0 ]; then
                            # Get VG free space and distribute
                            local vg_free=$(vgs --noheadings -o vg_free --units b "$lvm_vg" 2>/dev/null | sed 's/ *//g')
                            local each_size=$(( $(echo "$vg_free" | sed 's/B//') / lv_count ))
                            # Create LVs from the capture file names
                            for lv_img in "$selected"/lvm_*.img.zst; do
                                [ -f "$lv_img" ] || continue
                                local lv_name=$(basename "$lv_img" .img.zst | sed 's/lvm_//')
                                lvcreate -L ${each_size}B -n "$lv_name" "$lvm_vg" 2>/dev/null
                            done
                        fi
                    fi
                fi
            else
                echo "  → No VG backup found — creating VG '$lvm_vg' on $pv_dev"
                vgcreate "$lvm_vg" "$pv_dev" 2>/dev/null
            fi
            # Activate all LVs
            vgchange -ay "$lvm_vg" 2>/dev/null
            ok "LVM set up — VG '$lvm_vg' active"
            sleep 1
        else
            warn "Could not identify LVM PV partition on $target_disk"
            info "You may need to set up LVM manually after restore"
        fi
    fi

    # Restore each partition/LV image
    echo ""
    for img in "$selected"/*.zst; do
        [ -f "$img" ] || continue
        local base=$(basename "$img" .zst)
        local part_label=$(echo "$base" | sed 's/\.img$//')

        echo ""
        info "Restoring $part_label..."

        # Handle LVM logical volumes
        if echo "$part_label" | grep -q "^lvm_"; then
            local lv_name=$(echo "$part_label" | sed 's/^lvm_//')
            local target_lv=""
            # Find the LV device path
            if [ -n "$lvm_vg" ]; then
                target_lv="/dev/${lvm_vg}/${lv_name}"
                [ ! -b "$target_lv" ] && target_lv="/dev/mapper/${lvm_vg}-${lv_name}"
            fi
            if [ -n "$target_lv" ] && [ -b "$target_lv" ]; then
                echo "  → Target LV: $target_lv"
                echo "  → Decompressing and restoring..."
                local restored=0
                zstd -dc "$img" 2>/dev/null | partclone.ext4 -r -o "$target_lv" - 2>/dev/null
                restored=$?
                if [ $restored -ne 0 ]; then
                    zstd -dc "$img" 2>/dev/null | dd of="$target_lv" bs=4M status=none 2>/dev/null
                    restored=$?
                fi
                if [ $restored -eq 0 ]; then
                    ok "LVM LV $lv_name restored to $target_lv"
                else
                    warn "LVM LV $lv_name had restore issues (exit code: $restored)"
                fi
            else
                warn "LVM LV $lv_name target not found — LV may not have been created"
            fi
            continue
        fi

        # Regular partition image — determine target device
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
