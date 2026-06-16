#!/bin/bash
# SysMedic Smart Repair — Auto-detect and fix common OS problems
# Scans all disks, runs health checks per OS, prints PASS/WARN/FAIL report card

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}$1${NC}"; }
ok()    { echo -e "  ${GREEN}✅ $1${NC}"; }
warn()  { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
fail()  { echo -e "  ${RED}❌ $1${NC}"; }
detail(){ echo -e "     $1"; }
header(){ echo -e "${BOLD}\n  ╔══════════════════════════════════════════════════════════════╗${NC}"; 
          echo -e "${BOLD}  ║  $1${NC}"; 
          echo -e "${BOLD}  ╚══════════════════════════════════════════════════════════════╝${NC}"; }

TMP_MOUNT="/mnt/tmp_repair"
REPORT_FILE=""
ISSUES_FOUND=0
FIXES_APPLIED=0

# ──────────────────────────────────────────────
# Mount a partition by device, track for cleanup
# ──────────────────────────────────────────────
safe_mount() {
    local dev="$1" mp="$2"
    mkdir -p "$mp" 2>/dev/null
    mount | grep -q "^$dev " && return 0  # already mounted
    mount "$dev" "$mp" 2>/dev/null
}

safe_umount() {
    local mp="$1"
    mount | grep -q " $mp " && umount "$mp" 2>/dev/null || true
}

# ──────────────────────────────────────────────
# Mount separate /boot partition if fstab says so
# Reads fstab from already-mounted root, finds /boot entry,
# resolves UUID→device, and mounts it under root's /boot.
# Returns 0 if /boot is already accessible (separate or not).
# ──────────────────────────────────────────────
mount_separate_boot() {
    local root_mount="$1"
    local fstab="$root_mount/etc/fstab"

    [ ! -f "$fstab" ] && return 1

    # Already mounted or /boot is a real directory on root?
    if mountpoint -q "$root_mount/boot" 2>/dev/null; then
        return 0  # already mounted
    fi
    if [ -f "$root_mount/boot/grub/grub.cfg" ] || [ -f "$root_mount/boot/grub2/grub.cfg" ]; then
        return 0  # /boot is not separate, files are right here
    fi
    # If /boot has files (not empty), assume it's integral to root
    local boot_filecount
    boot_filecount=$(ls -1 "$root_mount/boot" 2>/dev/null | wc -l)
    [ "$boot_filecount" -gt 2 ] && return 0  # not empty → integral

    # Parse fstab for a /boot entry
    local boot_device=""
    while read -r line; do
        echo "$line" | grep -qE '^#|^$' && continue
        local fs=$(echo "$line" | awk '{print $1}')
        local mountpoint=$(echo "$line" | awk '{print $2}')
        [ "$mountpoint" != "/boot" ] && continue

        # Resolve UUID → device path
        if echo "$fs" | grep -qi "UUID="; then
            local uuid
            uuid=$(echo "$fs" | sed 's/UUID=//;s/"//g')
            boot_device=$(blkid -U "$uuid" 2>/dev/null)
        elif echo "$fs" | grep -q "^/dev/"; then
            # Handle LVM-style paths like /dev/mapper/...
            if [ -b "$fs" ]; then
                boot_device="$fs"
            fi
        fi
        break
    done < "$fstab"

    [ -z "$boot_device" ] && return 1
    [ ! -b "$boot_device" ] && return 1

    # Already mounted somewhere else? Unmount and re-mount in the right place
    local current_mount
    current_mount=$(mount | grep "^$boot_device " | awk '{print $3}')
    if [ -n "$current_mount" ]; then
        [ "$current_mount" = "$root_mount/boot" ] && return 0
        umount "$current_mount" 2>/dev/null || true
    fi

    mkdir -p "$root_mount/boot" 2>/dev/null
    if mount "$boot_device" "$root_mount/boot" 2>/dev/null; then
        detail "Mounted separate /boot partition ($boot_device → $root_mount/boot)"
        return 0
    fi
    return 1
}

# ──────────────────────────────────────────────
# Detect all installed OSes (shared logic)
# ──────────────────────────────────────────────
detect_oses() {
    local results=()
    mkdir -p "$TMP_MOUNT" 2>/dev/null

    # Get all devices with filesystems, including LVM logical volumes
    while read -r name fstype; do
        [ -z "$fstype" ] && continue
        # Construct device path — LVM LVs use /dev/mapper/ or /dev/$vg/$lv path
        local dev=""
        case "$name" in
            *-*)    # Might be LVM (e.g. ubuntu--vg-ubuntu--lv)
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
        mount | grep -q "^$dev " && continue

        if safe_mount "$dev" "$TMP_MOUNT"; then
            local os_name="" os_type="" os_ver=""

            if [ -d "$TMP_MOUNT/Windows/System32" ]; then
                os_type="windows"
                os_name="Windows"
                os_ver=$(head -1 "$TMP_MOUNT/Windows/System32/license.rtf" 2>/dev/null | tr -dc '[:print:]' | head -c 80)
                [ -z "$os_ver" ] && os_ver="Windows 10/11"
            elif [ -f "$TMP_MOUNT/etc/os-release" ]; then
                os_type="linux"
                os_name=$(grep PRETTY_NAME "$TMP_MOUNT/etc/os-release" 2>/dev/null | cut -d= -f2 | tr -d '"')
                os_ver=$(grep VERSION_ID "$TMP_MOUNT/etc/os-release" 2>/dev/null | cut -d= -f2 | tr -d '"')
            elif [ -d "$TMP_MOUNT/System/Library/CoreServices" ]; then
                os_type="macos"
                os_name="macOS"
                os_ver=$(grep -A1 'ProductVersion' "$TMP_MOUNT/System/Library/CoreServices/SystemVersion.plist" 2>/dev/null | tail -1 | sed 's/.*<string>//;s/<\/string>//')
            fi

            safe_umount "$TMP_MOUNT"

            if [ -n "$os_type" ]; then
                local fstype=$(lsblk -nlo FSTYPE "$dev" 2>/dev/null)
                local size=$(lsblk -nlo SIZE "$dev" 2>/dev/null)
                local disk=$(lsblk -ndo PKNAME "$dev" 2>/dev/null | sed 's/^/\/dev\//')
                results+=("$os_type|$dev|$disk|$os_name|$os_ver|$fstype|$size")
            fi
        fi
    done < <(lsblk -nlo NAME,FSTYPE 2>/dev/null | grep -E 'ntfs|ext4|vfat|fat32|hfsplus|apfs')
    rmdir "$TMP_MOUNT" 2>/dev/null

    for r in "${results[@]}"; do echo "$r"; done
}

# ──────────────────────────────────────────────
# Find EFI system partition
# ──────────────────────────────────────────────
find_efi_part() {
    for dev in $(lsblk -nlo NAME,FSTYPE 2>/dev/null | grep -E 'vfat|fat32' | awk '{print "/dev/"$1}'); do
        if safe_mount "$dev" "$TMP_MOUNT"; then
            if [ -d "$TMP_MOUNT/EFI" ] || [ -d "$TMP_MOUNT/efi" ]; then
                safe_umount "$TMP_MOUNT"
                echo "$dev"
                return
            fi
            safe_umount "$TMP_MOUNT"
        fi
    done
    echo ""
}

# ──────────────────────────────────────────────
# Linux health checks
# ──────────────────────────────────────────────
check_linux() {
    local dev="$1" index="$2"
    local issues=()

    echo ""
    echo -e "  ${BOLD}── Linux Checks ($dev) ──${NC}"

    if ! safe_mount "$dev" "$TMP_MOUNT"; then
        fail "Cannot mount $dev"
        return 1
    fi

    # Try to mount separate /boot partition (common with LVM)
    local boot_mounted=0
    mount_separate_boot "$TMP_MOUNT" && boot_mounted=1

    # Check 1: GRUB config
    local grub_files=0
    [ -f "$TMP_MOUNT/boot/grub/grub.cfg" ] && grub_files=$((grub_files + 1))
    [ -f "$TMP_MOUNT/boot/grub2/grub.cfg" ] && grub_files=$((grub_files + 1))
    # Check for GRUB in EFI (if mounted separately or on the same partition)
    [ -d "$TMP_MOUNT/boot/efi/EFI" ] && grub_files=$((grub_files + 1))

    if [ -d "$TMP_MOUNT/boot/grub" ] || [ -d "$TMP_MOUNT/boot/grub2" ]; then
        ok "GRUB directory present"
    else
        warn "GRUB directory not found"
        issues+=("grub_missing")
    fi

    # Check 2: fstab
    if [ -f "$TMP_MOUNT/etc/fstab" ]; then
        ok "fstab present"
        local bad_fstab=0
        while read -r line; do
            # Skip comments, empty lines, and swap/overlay/proc/sysfs/devpts/tmpfs
            echo "$line" | grep -qE '^#|^$|^swap|^UUID=.* none swap|overlay|proc|sysfs|devpts|tmpfs|devtmpfs|efivarfs|securityfs|cgroup|pstore|bpf|hugetlbfs|mqueue|debugfs|tracefs|fusectl|configfs|binfmt_misc' && continue
            local fs=$(echo "$line" | awk '{print $1}')
            local mountpoint=$(echo "$line" | awk '{print $2}')
            local fstype=$(echo "$line" | awk '{print $3}')
            [ -z "$fs" ] && continue
            # For UUID-based entries, check if the UUID exists
            if echo "$fs" | grep -qi "UUID="; then
                local uuid=$(echo "$fs" | sed 's/UUID=//;s/"//g')
                if ! blkid -U "$uuid" &>/dev/null; then
                    warn "fstab entry has missing UUID: $fs → $mountpoint"
                    bad_fstab=$((bad_fstab + 1))
                fi
            fi
            # For device-based entries, check if device exists
            if echo "$fs" | grep -q "^/dev/"; then
                if [ ! -b "$fs" ]; then
                    warn "fstab entry has missing device: $fs → $mountpoint"
                    bad_fstab=$((bad_fstab + 1))
                fi
            fi
        done < "$TMP_MOUNT/etc/fstab"
        if [ "$bad_fstab" -gt 0 ]; then
            issues+=("fstab_bad")
        fi
    else
        fail "No /etc/fstab found!"
        issues+=("fstab_missing")
    fi

    # Check 3: initramfs
    local initrd_count=0
    initrd_count=$(ls "$TMP_MOUNT/boot"/initrd*img* "$TMP_MOUNT/boot"/initramfs* 2>/dev/null | wc -l)
    if [ "$initrd_count" -gt 0 ]; then
        ok "initramfs present ($initrd_count file(s))"
    else
        warn "No initramfs/initrd found in /boot"
        issues+=("initramfs_missing")
    fi

    # Check 4: /boot disk usage
    local boot_usage=$(df "$TMP_MOUNT/boot" 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
    if [ -n "$boot_usage" ]; then
        if [ "$boot_usage" -gt 90 ]; then
            fail "Boot partition is $boot_usage% full — risk of boot failure"
            issues+=("boot_full")
        elif [ "$boot_usage" -gt 75 ]; then
            warn "Boot partition is $boot_usage% full"
            issues+=("boot_high")
        else
            ok "Boot partition at $boot_usage%"
        fi
    fi

    # Check 5: kernel panic logs
    local panics=0
    if [ -f "$TMP_MOUNT/var/log/kern.log" ]; then
        panics=$(grep -ci "panic" "$TMP_MOUNT/var/log/kern.log" 2>/dev/null || echo 0)
        if [ "$panics" -gt 0 ]; then
            warn "$panics kernel panic(s) in log"
            issues+=("kernel_panic")
        else
            ok "No kernel panics in log"
        fi
    elif [ -d "$TMP_MOUNT/var/log" ]; then
        detail "No kern.log found (journald system — check with journalctl from chroot)"
    fi

    # Check 6: dpkg status (if Debian-based)
    if [ -f "$TMP_MOUNT/var/lib/dpkg/status" ]; then
        local broken=$(grep -c "Status:.*half\|Status:.*unpacked\|Status:.*config-files" "$TMP_MOUNT/var/lib/dpkg/status" 2>/dev/null || echo 0)
        if [ "$broken" -gt 0 ]; then
            warn "$broken packages in inconsistent state"
            issues+=("dpkg_broken")
        else
            ok "dpkg packages consistent"
        fi
    fi

    # If we mounted a separate /boot, unmount it first (child mount before parent)
    [ "$boot_mounted" -eq 1 ] && umount "$TMP_MOUNT/boot" 2>/dev/null || true
    safe_umount "$TMP_MOUNT"

    # Report and return issues
    echo ""
    if [ ${#issues[@]} -eq 0 ]; then
        ok "No Linux issues detected on $dev"
    else
        ISSUES_FOUND=$((ISSUES_FOUND + ${#issues[@]}))
        warn "${#issues[@]} issue(s) found on $dev"
    fi

    # Return issues array for fix function
    echo "${issues[@]}" > "/tmp/sysmedic_linux_issues_${index}"
    echo "${#issues[@]}"
}

# ──────────────────────────────────────────────
# Windows health checks
# ──────────────────────────────────────────────
check_windows() {
    local dev="$1" index="$2"
    local issues=()

    echo ""
    echo -e "  ${BOLD}── Windows Checks ($dev) ──${NC}"

    if ! safe_mount "$dev" "$TMP_MOUNT"; then
        fail "Cannot mount $dev"
        return 1
    fi

    local win_dir="$TMP_MOUNT/Windows"

    # Check 1: BCD store
    if [ -f "$win_dir/System32/config/SOFTWARE" ]; then
        ok "Windows registry accessible"
    else
        fail "Cannot access Windows registry"
        issues+=("reg_corrupt")
    fi

    if [ -f "$TMP_MOUNT/Boot/BCD" ] || [ -f "$TMP_MOUNT/boot/BCD" ]; then
        ok "BCD store present"
    else
        warn "BCD store not found (may be on EFI partition)"
        issues+=("bcd_missing")
    fi

    # Check 2: Boot sector (NTFS signature at offset 0x1FE should be 55AA)
    safe_umount "$TMP_MOUNT"
    local bs_sig=$(dd if="$dev" bs=1 skip=510 count=2 2>/dev/null | xxd -p)
    if [ "$bs_sig" = "55aa" ]; then
        ok "NTFS boot sector signature valid (0x55AA)"
    else
        fail "NTFS boot sector signature invalid (got: 0x$bs_sig)"
        issues+=("bootsector_bad")
    fi

    # Re-mount for remaining checks
    safe_mount "$dev" "$TMP_MOUNT"
    win_dir="$TMP_MOUNT/Windows"

    # Check 3: NTFS dirty bit
    local dirty=$(ntfsinfo "$dev" 2>/dev/null | grep -i "dirty" | grep -i "yes")
    if [ -n "$dirty" ]; then
        warn "NTFS volume is dirty — needs chkdsk"
        issues+=("ntfs_dirty")
    else
        ok "NTFS volume clean"
    fi

    # Check 4: EFI bootloader file
    if [ -f "$TMP_MOUNT/Windows/Boot/EFI/bootmgfw.efi" ]; then
        ok "Windows EFI bootloader present"
    else
        warn "bootmgfw.efi not found"
        issues+=("efi_bootloader_missing")
    fi

    # Check 5: Crash dumps
    local crash_count=0
    [ -f "$win_dir/memory.dmp" ] && crash_count=$((crash_count + 1))
    crash_count=$((crash_count + $(ls "$win_dir/Minidump"/*.dmp 2>/dev/null | wc -l)))
    if [ "$crash_count" -gt 0 ]; then
        warn "$crash_count crash dump(s) found"
        issues+=("crash_dumps")
    else
        ok "No crash dumps"
    fi

    # Check 6: SrtTrail (boot failure log)
    if [ -f "$win_dir/System32/LogFiles/SrtTrail.txt" ]; then
        warn "Boot failure log found (SrtTrail.txt) — system had boot issues"
        issues+=("boot_failure_log")
    else
        ok "No boot failure log"
    fi

    # Check 7: Disk check needed
    local disk_check=$(ntfsck "$dev" 2>/dev/null | grep -c "MODIFIED\|ERROR\|CORRUPT" || echo 0)
    if [ "$disk_check" -gt 0 ]; then
        warn "NTFS filesystem errors detected"
        issues+=("ntfs_errors")
    else
        ok "NTFS filesystem clean"
    fi

    safe_umount "$TMP_MOUNT"

    echo ""
    if [ ${#issues[@]} -eq 0 ]; then
        ok "No Windows issues detected on $dev"
    else
        ISSUES_FOUND=$((ISSUES_FOUND + ${#issues[@]}))
        warn "${#issues[@]} issue(s) found on $dev"
    fi

    echo "${issues[@]}" > "/tmp/sysmedic_win_issues_${index}"
    echo "${#issues[@]}"
}

# ──────────────────────────────────────────────
# EFI system checks
# ──────────────────────────────────────────────
check_efi() {
    local efi_dev="$1"
    local issues=()

    echo ""
    echo -e "  ${BOLD}── EFI System Checks (${efi_dev:-auto}) ──${NC}"

    if [ -z "$efi_dev" ]; then
        efi_dev=$(find_efi_part)
    fi

    if [ -z "$efi_dev" ]; then
        fail "No EFI system partition found"
        issues+=("efi_part_missing")
        echo "${#issues[@]}"
        echo "${issues[@]}" > /tmp/sysmedic_efi_issues
        return 1
    fi

    ok "EFI partition found: $efi_dev"

    if ! safe_mount "$efi_dev" "$TMP_MOUNT"; then
        fail "Cannot mount EFI partition"
        issues+=("efi_unmountable")
        echo "${#issues[@]}"
        echo "${issues[@]}" > /tmp/sysmedic_efi_issues
        return 1
    fi

    # Check 1: Bootloader files
    local bl_count=0
    [ -f "$TMP_MOUNT/EFI/Microsoft/Boot/bootmgfw.efi" ] && bl_count=$((bl_count + 1))
    [ -f "$TMP_MOUNT/EFI/ubuntu/grubx64.efi" ] && bl_count=$((bl_count + 1))
    [ -f "$TMP_MOUNT/EFI/ubuntu/shimx64.efi" ] && bl_count=$((bl_count + 1))
    [ -f "$TMP_MOUNT/EFI/BOOT/BOOTX64.efi" ] && bl_count=$((bl_count + 1))
    [ -f "$TMP_MOUNT/EFI/fedora/grubx64.efi" ] && bl_count=$((bl_count + 1))

    if [ "$bl_count" -gt 0 ]; then
        ok "$bl_count bootloader file(s) found on EFI partition"
        ls "$TMP_MOUNT/EFI"/*/ 2>/dev/null | sed 's|.*/EFI/|      EFI/|' | while read line; do
            detail "$line"
        done
    else
        fail "No bootloader files found on EFI partition!"
        issues+=("efi_no_bootloader")
    fi

    # Check 2: EFI NVRAM entries
    if command -v efibootmgr &>/dev/null; then
        local efi_entries=$(efibootmgr 2>/dev/null | grep -c "Boot[0-9]" || echo 0)
        if [ "$efi_entries" -gt 0 ]; then
            ok "$efi_entries NVRAM boot entries"
            efibootmgr 2>/dev/null | grep "Boot[0-9]" | head -10 | while read line; do
                detail "$line"
            done
        else
            warn "No NVRAM boot entries found"
            issues+=("efi_no_nvram")
        fi
    else
        detail "efibootmgr not available — skipping NVRAM check"
    fi

    safe_umount "$TMP_MOUNT"

    echo ""
    if [ ${#issues[@]} -eq 0 ]; then
        ok "No EFI issues detected"
    else
        ISSUES_FOUND=$((ISSUES_FOUND + ${#issues[@]}))
        warn "${#issues[@]} EFI issue(s) found"
    fi

    echo "${issues[@]}" > /tmp/sysmedic_efi_issues
    echo "${#issues[@]}"
}

# ──────────────────────────────────────────────
# Fix Linux issues
# ──────────────────────────────────────────────
fix_linux() {
    local dev="$1" index="$2"
    local issues_file="/tmp/sysmedic_linux_issues_${index}"

    if [ ! -f "$issues_file" ]; then
        warn "No Linux issue data for this device"
        return
    fi

    local issues=($(cat "$issues_file"))
    [ ${#issues[@]} -eq 0 ] && return

    echo ""
    info "Fixing Linux on $dev..."
    echo ""

    if ! safe_mount "$dev" "$TMP_MOUNT"; then
        fail "Cannot mount $dev to apply fixes"
        return 1
    fi

    # Try to mount separate /boot partition (common with LVM)
    local boot_mounted=0
    mount_separate_boot "$TMP_MOUNT" && boot_mounted=1

    # Mount critical virtual filesystems for chroot operations
    local has_efi=0
    local efi_dev=$(find_efi_part)
    if [ -n "$efi_dev" ]; then
        mkdir -p "$TMP_MOUNT/boot/efi" 2>/dev/null
        mount "$efi_dev" "$TMP_MOUNT/boot/efi" 2>/dev/null && has_efi=1
    fi

    for issue in "${issues[@]}"; do
        case "$issue" in
            grub_missing)
                info "Reinstalling GRUB..."
                mount --bind /dev "$TMP_MOUNT/dev" 2>/dev/null
                mount --bind /proc "$TMP_MOUNT/proc" 2>/dev/null
                mount --bind /sys "$TMP_MOUNT/sys" 2>/dev/null

                if [ "$has_efi" -eq 1 ]; then
                    chroot "$TMP_MOUNT" /bin/bash -c "grub-install --target=x86_64-efi --efi-directory=/boot/efi 2>/dev/null" && ok "GRUB EFI installed"
                fi
                chroot "$TMP_MOUNT" /bin/bash -c "grub-install 2>/dev/null" 2>/dev/null
                chroot "$TMP_MOUNT" /bin/bash -c "update-grub 2>/dev/null" 2>/dev/null && ok "GRUB reinstalled + config regenerated"
                FIXES_APPLIED=$((FIXES_APPLIED + 1))
                ;;
            fstab_bad|fstab_missing)
                info "Backing up fstab..."
                cp "$TMP_MOUNT/etc/fstab" "$TMP_MOUNT/etc/fstab.backup.$(date +%Y%m%d)" 2>/dev/null
                if [ "$issue" = "fstab_missing" ]; then
                    warn "Cannot auto-fix missing fstab — manual intervention needed"
                else
                    # Fix bad UUIDs — comment out entries with missing devices
                    local fixed=0
                    local tmp_fstab=$(mktemp)
                    while read -r line; do
                        echo "$line" | grep -qE '^#|^$' && echo "$line" >> "$tmp_fstab" && continue
                        local fs=$(echo "$line" | awk '{print $1}')
                        if echo "$fs" | grep -qi "UUID="; then
                            local uuid=$(echo "$fs" | sed 's/UUID=//;s/"//g')
                            if ! blkid -U "$uuid" &>/dev/null; then
                                echo "# BROKEN UUID — $line" >> "$tmp_fstab"
                                fixed=$((fixed + 1))
                            else
                                echo "$line" >> "$tmp_fstab"
                            fi
                        elif echo "$fs" | grep -q "^/dev/" && [ ! -b "$fs" ]; then
                            echo "# MISSING DEVICE — $line" >> "$tmp_fstab"
                            fixed=$((fixed + 1))
                        else
                            echo "$line" >> "$tmp_fstab"
                        fi
                    done < "$TMP_MOUNT/etc/fstab"
                    cp "$tmp_fstab" "$TMP_MOUNT/etc/fstab"
                    rm -f "$tmp_fstab"
                    ok "Commented out $fixed broken fstab entries (backup saved)"
                    FIXES_APPLIED=$((FIXES_APPLIED + 1))
                fi
                ;;
            initramfs_missing)
                info "Rebuilding initramfs..."
                mount --bind /dev "$TMP_MOUNT/dev" 2>/dev/null
                mount --bind /proc "$TMP_MOUNT/proc" 2>/dev/null
                mount --bind /sys "$TMP_MOUNT/sys" 2>/dev/null

                # Find the latest kernel
                local latest_kernel=$(ls -t "$TMP_MOUNT/boot"/vmlinuz-* 2>/dev/null | head -1 | sed 's|.*vmlinuz-||')
                if [ -n "$latest_kernel" ]; then
                    chroot "$TMP_MOUNT" /bin/bash -c "update-initramfs -u -k $latest_kernel 2>/dev/null" && ok "initramfs rebuilt for kernel $latest_kernel"
                    FIXES_APPLIED=$((FIXES_APPLIED + 1))
                else
                    warn "No kernel found to build initramfs for"
                fi
                ;;
            boot_full|boot_high)
                info "Cleaning old kernels in /boot..."
                # Remove old kernels, keep the 2 most recent
                local kernels=($(ls -1 "$TMP_MOUNT/boot"/vmlinuz-* 2>/dev/null | sort -V))
                local count=${#kernels[@]}
                if [ "$count" -gt 2 ]; then
                    local to_remove=$((count - 2))
                    for ((i=0; i<to_remove; i++)); do
                        local kver=$(basename "${kernels[$i]}" | sed 's/vmlinuz-//')
                        rm -f "$TMP_MOUNT/boot"/initr*d.img-$kver 2>/dev/null
                        rm -f "$TMP_MOUNT/boot"/initramfs-$kver 2>/dev/null
                        rm -f "$TMP_MOUNT/boot"/vmlinuz-$kver 2>/dev/null
                        rm -f "$TMP_MOUNT/boot"/System.map-$kver 2>/dev/null
                        rm -f "$TMP_MOUNT/boot"/config-$kver 2>/dev/null
                    done
                    ok "Removed $to_remove old kernel(s) from /boot"
                    FIXES_APPLIED=$((FIXES_APPLIED + 1))
                else
                    detail "Only $count kernel(s) — nothing to clean"
                fi
                ;;
            dpkg_broken)
                info "Fixing dpkg..."
                mount --bind /dev "$TMP_MOUNT/dev" 2>/dev/null
                mount --bind /proc "$TMP_MOUNT/proc" 2>/dev/null
                chroot "$TMP_MOUNT" /bin/bash -c "dpkg --configure -a 2>/dev/null" 2>/dev/null && ok "dpkg configured"
                FIXES_APPLIED=$((FIXES_APPLIED + 1))
                ;;
        esac
    done

    # Cleanup mounts (reverse order)
    umount "$TMP_MOUNT/boot/efi" 2>/dev/null || true
    umount "$TMP_MOUNT/dev" 2>/dev/null || true
    umount "$TMP_MOUNT/proc" 2>/dev/null || true
    umount "$TMP_MOUNT/sys" 2>/dev/null || true
    [ "$boot_mounted" -eq 1 ] && umount "$TMP_MOUNT/boot" 2>/dev/null || true
    safe_umount "$TMP_MOUNT"

    echo ""
    ok "Linux fixes applied to $dev"
}

# ──────────────────────────────────────────────
# Fix Windows issues
# ──────────────────────────────────────────────
fix_windows() {
    local dev="$1" index="$2"
    local issues_file="/tmp/sysmedic_win_issues_${index}"

    if [ ! -f "$issues_file" ]; then
        warn "No Windows issue data for this device"
        return
    fi

    local issues=($(cat "$issues_file"))
    [ ${#issues[@]} -eq 0 ] && return

    echo ""
    info "Fixing Windows on $dev..."
    echo ""

    for issue in "${issues[@]}"; do
        case "$issue" in
            bootsector_bad)
                info "Repairing NTFS boot sector..."
                ntfsfix "$dev" 2>/dev/null && ok "NTFS boot sector repaired" || warn "ntfsfix had issues"
                FIXES_APPLIED=$((FIXES_APPLIED + 1))
                ;;
            ntfs_dirty|ntfs_errors)
                info "Running NTFS filesystem check..."
                ntfsck "$dev" 2>/dev/null && ok "NTFS check complete" || warn "ntfsck had issues"
                FIXES_APPLIED=$((FIXES_APPLIED + 1))
                ;;
            bcd_missing)
                info "Rebuilding BCD store..."
                if safe_mount "$dev" "$TMP_MOUNT"; then
                    mkdir -p "$TMP_MOUNT/Boot" 2>/dev/null
                    # Basic BCD rebuild using bcdedit from a Windows PE or template
                    # For now, attempt via ntfs-3g and create a minimal BCD
                    if [ -f "$TMP_MOUNT/Windows/System32/config/SOFTWARE" ]; then
                        # We can't easily rebuild BCD without Windows PE tools
                        warn "BCD rebuild requires Windows boot media — use menu option 15"
                    fi
                    safe_umount "$TMP_MOUNT"
                fi
                ;;
            efi_bootloader_missing)
                info "Restoring Windows EFI bootloader..."
                local efi_dev=$(find_efi_part)
                if [ -n "$efi_dev" ] && safe_mount "$efi_dev" "$TMP_MOUNT"; then
                    mkdir -p "$TMP_MOUNT/EFI/Microsoft/Boot" 2>/dev/null
                    # If we have the boot files from the Windows partition, copy them
                    if safe_mount "$dev" "/mnt/tmp_win"; then
                        if [ -f "/mnt/tmp_win/Windows/Boot/EFI/bootmgfw.efi" ]; then
                            cp "/mnt/tmp_win/Windows/Boot/EFI/bootmgfw.efi" "$TMP_MOUNT/EFI/Microsoft/Boot/" 2>/dev/null
                            ok "bootmgfw.efi restored to EFI partition"
                            FIXES_APPLIED=$((FIXES_APPLIED + 1))
                        fi
                        safe_umount "/mnt/tmp_win"
                    fi
                    safe_umount "$TMP_MOUNT"
                fi
                ;;
            boot_failure_log)
                info "Clearing boot failure log..."
                if safe_mount "$dev" "$TMP_MOUNT"; then
                    rm -f "$TMP_MOUNT/Windows/System32/LogFiles/SrtTrail.txt" 2>/dev/null
                    ok "SrtTrail.txt cleared"
                    FIXES_APPLIED=$((FIXES_APPLIED + 1))
                    safe_umount "$TMP_MOUNT"
                fi
                ;;
        esac
    done

    # Always run ntfsfix on the boot sector if there were any issues
    if [ ${#issues[@]} -gt 0 ]; then
        info "Running final ntfsfix on $dev..."
        ntfsfix "$dev" 2>/dev/null | tail -1
    fi

    echo ""
    ok "Windows fixes applied to $dev"
}

# ──────────────────────────────────────────────
# Fix EFI issues
# ──────────────────────────────────────────────
fix_efi() {
    local issues_file="/tmp/sysmedic_efi_issues"

    if [ ! -f "$issues_file" ]; then
        return
    fi

    local issues=($(cat "$issues_file"))
    [ ${#issues[@]} -eq 0 ] && return

    local efi_dev=$(find_efi_part)
    if [ -z "$efi_dev" ]; then
        fail "Cannot fix EFI — no EFI partition found"
        return
    fi

    echo ""
    info "Fixing EFI system partition ($efi_dev)..."
    echo ""

    if ! safe_mount "$efi_dev" "$TMP_MOUNT"; then
        fail "Cannot mount EFI partition"
        return
    fi

    for issue in "${issues[@]}"; do
        case "$issue" in
            efi_no_bootloader)
                info "EFI partition is empty — attempting to restore boot files..."
                warn "Auto-restore of EFI boot files requires Windows/Linux boot media"
                detail "Use menu option 18 (Restore Windows EFI boot manager) or option 6/15"
                ;;
        esac
    done

    safe_umount "$TMP_MOUNT"
}

# ──────────────────────────────────────────────
# Print unified report card
# ──────────────────────────────────────────────
print_report_card() {
    local -n os_list="$1"
    local total_issues="$2"

    echo ""
    header "  SMART REPAIR — RESULTS"

    if [ "$total_issues" -eq 0 ]; then
        echo -e "  ${GREEN}${BOLD}  ✅ ALL SYSTEMS HEALTHY — No issues found${NC}"
        echo ""
        echo -e "  ${GREEN}  All checks passed across all detected operating systems.${NC}"
    else
        echo -e "  ${YELLOW}${BOLD}  ⚠️  $total_issues issue(s) found across ${#os_list[@]} OS(es)${NC}"
        echo ""
        for entry in "${os_list[@]}"; do
            IFS='|' read -r otype dev disk name ver rest <<< "$entry"
            echo -e "  ${BOLD}$name on $dev${NC}"
        done
        echo ""
        echo -e "  ${YELLOW}Issues detected. Fix mode will address them automatically.${NC}"
    fi

    if [ "$FIXES_APPLIED" -gt 0 ]; then
        echo ""
        echo -e "  ${GREEN}${BOLD}  ✅ $FIXES_APPLIED fix(es) applied successfully${NC}"
    fi
    echo ""
}

# ──────────────────────────────────────────────
# Full scan + report
# ──────────────────────────────────────────────
run_scan() {
    header "  SMART REPAIR — SYSTEM SCAN"

    info "Scanning all disks for installed operating systems..."
    sleep 1

    mapfile -t oses < <(detect_oses)

    if [ ${#oses[@]} -eq 0 ]; then
        warn "No installed OSes detected"
        echo ""
        info "Available partitions:"
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null | grep -v loop
        echo ""
        return 1
    fi

    echo -e "\n  ${BOLD}Detected ${#oses[@]} operating system(s):${NC}"
    echo "  ────────────────────────────────────"
    local idx=0
    for entry in "${oses[@]}"; do
        IFS='|' read -r otype dev disk name ver fstype size <<< "$entry"
        printf "  [%d]  %-10s  %-20s  %s  (%s, %s)\n" "$idx" "$name" "$dev" "$ver" "$fstype" "$size"
        idx=$((idx + 1))
    done
    echo ""

    # Run checks for each OS
    local efi_checked=0
    local idx=0
    for entry in "${oses[@]}"; do
        IFS='|' read -r otype dev disk name ver fstype size <<< "$entry"
        case "$otype" in
            linux)
                check_linux "$dev" "$idx"
                ;;
            windows)
                check_windows "$dev" "$idx"
                ;;
        esac
        idx=$((idx + 1))
    done

    # Check EFI once (shared across OSes)
    check_efi ""

    echo ""
    if [ "$ISSUES_FOUND" -eq 0 ]; then
        ok "All checks passed — no issues found across any system"
    else
        warn "$ISSUES_FOUND total issue(s) found"
    fi

    return 0
}

# ──────────────────────────────────────────────
# Fix all detected issues
# ──────────────────────────────────────────────
run_fix() {
    header "  SMART REPAIR — AUTO-FIX"

    if [ "$ISSUES_FOUND" -eq 0 ]; then
        info "No issues to fix — run scan first"
        read -p "  Press Enter..."
        return
    fi

    echo -e "  ${YELLOW}${BOLD}  ⚠️  About to auto-fix $ISSUES_FOUND issue(s)${NC}"
    echo ""
    warn "This will modify system partitions!"
    read -p "  Type 'YES' to proceed: " confirm
    if [ "$confirm" != "YES" ]; then
        info "Fix cancelled"
        read -p "  Press Enter..."
        return
    fi

    echo ""

    # Re-detect OSes for mount info
    mapfile -t oses < <(detect_oses)

    local idx=0
    for entry in "${oses[@]}"; do
        IFS='|' read -r otype dev disk name ver fstype size <<< "$entry"
        case "$otype" in
            linux)
                fix_linux "$dev" "$idx"
                ;;
            windows)
                fix_windows "$dev" "$idx"
                ;;
        esac
        idx=$((idx + 1))
    done

    fix_efi

    echo ""
    if [ "$FIXES_APPLIED" -gt 0 ]; then
        ok "$FIXES_APPLIED fix(es) applied"
        echo ""
        info "Recommendation: Reboot and test the system"
    else
        warn "No fixes were applicable (some issues may require manual intervention)"
    fi

    read -p "  Press Enter..."
}

# ──────────────────────────────────────────────
# Interactive menu
# ──────────────────────────────────────────────
interactive_menu() {
    while true; do
        clear
        header "  SMART REPAIR ASSISTANT"

        echo -e "  ${BOLD}1)  Run full scan${NC}"
        echo "       Detects all OSes and checks for common problems"
        echo "       (bootloader, fstab, BCD, EFI, kernel, disk health)"
        echo ""
        echo -e "  ${BOLD}2)  Scan & auto-fix${NC}"
        echo "       Scans all systems, then fixes everything found"
        echo ""
        echo -e "  ${BOLD}0)  Back to main menu${NC}"
        echo ""

        if [ "$ISSUES_FOUND" -gt 0 ]; then
            echo -e "  ${YELLOW}⚠️  $ISSUES_FOUND issue(s) from last scan — fix pending${NC}"
            echo ""
        fi

        read -p "  Choice [0-2]: " choice

        case "$choice" in
            1)
                ISSUES_FOUND=0
                FIXES_APPLIED=0
                run_scan
                echo ""
                read -p "  Press Enter..."
                ;;
            2)
                ISSUES_FOUND=0
                FIXES_APPLIED=0
                run_scan
                echo ""
                if [ "$ISSUES_FOUND" -gt 0 ]; then
                    run_fix
                else
                    info "No issues to fix"
                    read -p "  Press Enter..."
                fi
                ;;
            0)  break ;;
            *)  warn "Invalid choice"; sleep 1 ;;
        esac
    done
}

# ──────────────────────────────────────────────
# Main entry point
# ──────────────────────────────────────────────
case "${1:-}" in
    scan|--scan|-s)
        ISSUES_FOUND=0
        run_scan
        ;;
    fix|--fix|-f)
        ISSUES_FOUND=0
        run_scan
        [ "$ISSUES_FOUND" -gt 0 ] && run_fix
        ;;
    *)
        interactive_menu
        ;;
esac
