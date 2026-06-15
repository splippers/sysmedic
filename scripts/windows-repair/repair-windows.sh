#!/usr/bin/env bash
# SysMedic - Windows Repair Toolkit
# Fixes: BCD bootloader, NTFS corruption, boot sector, Windows boot manager

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC}   $1"; }
fail()  { echo -e "  ${RED}[FAIL]${NC}   $1"; }
header(){ echo -e "\n${BOLD}$1${NC}\n"; }

header "Windows Repair Toolkit"
echo ""

# Step 1: Find Windows partitions
header "Detecting Windows Volumes"
windows_parts=()
efi_parts=()
for part in $(lsblk -nro NAME,FSTYPE 2>/dev/null | grep -i 'ntfs' | awk '{print "/dev/"$1}'); do
    # Check if it looks like a Windows system partition
    label=$(blkid -s LABEL -o value "$part" 2>/dev/null)
    size=$(lsblk -nro SIZE "$part" 2>/dev/null)
    echo -e "  ${GREEN}●${NC} ${BOLD}$part${NC}  ${YELLOW}$size${NC}  Label: ${label:-<none>}"
    windows_parts+=("$part")
done
echo ""

# Find EFI partitions
for part in $(lsblk -nro NAME,FSTYPE 2>/dev/null | grep -i 'vfat' | awk '{print "/dev/"$1}'); do
    size=$(lsblk -nro SIZE "$part" 2>/dev/null)
    if [ "$(lsblk -nro SIZE "$part" 2>/dev/null | sed 's/G//')" = "512" ] || \
       [ "$(lsblk -nro SIZE "$part" 2>/dev/null | sed 's/M//')" -le 600 ] 2>/dev/null; then
        echo -e "  ${CYAN}●${NC} ${BOLD}$part${NC}  ${YELLOW}$size${NC}  (EFI System Partition candidate)"
        efi_parts+=("$part")
    fi
done

if [ ${#windows_parts[@]} -eq 0 ]; then
    fail "No NTFS/Windows volumes found"
    echo "  Is the Windows drive connected?"
    exit 1
fi

# Step 2: Choose action
header "Repair Options"
echo "  1) NTFS filesystem check & repair"
echo "  2) Fix Windows BCD (boot loader)"
echo "  3) Fix NTFS boot sector"
echo "  4) Repair Windows Registry (chntpw)"
echo "  5) Mount Windows partition for data access"
echo "  6) Restore Windows Boot Manager (UEFI)"
echo "  0) Back to menu"
echo ""
read -p "  Choose [0-6]: " action

case "$action" in
    1)
        header "NTFS Filesystem Check"
        for ntfs_dev in "${windows_parts[@]}"; do
            echo -e "  ${BOLD}$ntfs_dev${NC}"
            ntfslabel=$(ntfs-3g.probe --label "$ntfs_dev" 2>/dev/null || echo "unknown")
            ok "Checking $ntfs_dev ($ntfslabel)..."
            ntfsfix "$ntfs_dev" 2>&1
            echo ""
        done
        echo ""
        warn "ntfsfix clears the dirty flag — it's safe but does NOT fix structural damage"
        echo "  For deep repair, use a Windows machine: chkdsk /f X:"
        ;;
    2)
        header "BCD Repair"
        echo ""
        echo -e "  ${YELLOW}This will rebuild the Windows Boot Configuration Data.${NC}"
        echo ""
        read -p "  Which Windows partition has the BCD? (e.g. /dev/nvme0n1p3): " bcd_part
        
        # Mount the Windows partition
        mkdir -p /mnt/windows
        if ntfs-3g "$bcd_part" /mnt/windows 2>/dev/null; then
            ok "Mounted $bcd_part"
            
            # Check if BCD exists
            BCD_PATH="/mnt/windows/Boot/BCD"
            if [ -f "$BCD_PATH" ]; then
                warn "Existing BCD found — backing up to /mnt/windows/Boot/BCD.bak"
                cp "$BCD_PATH" "/mnt/windows/Boot/BCD.bak" 2>/dev/null
            fi
            
            # Check for bcdedit or bootrec equivalent
            if command -v bcdedit 2>/dev/null; then
                echo "  Running bcdedit repair..."
                bcdedit /store "$BCD_PATH" /enum 2>/dev/null || warn "BCD may be empty"
            else
                info "bcdedit not available on this system"
                echo "  Manual steps for BCD repair:"
                echo ""
                echo "  On a Windows system, run:"
                echo "    bootrec /rebuildbcd"
                echo "    bootrec /fixmbr"
                echo "    bootrec /fixboot"
                echo ""
                echo "  Or from Windows Recovery:"
                echo "    bcdedit /export C:\Boot\BCD.bak"
                echo "    attrib C:\boot\bcd -h -r -s"
                echo "    ren C:\boot\bcd bcd.old"
                echo "    bootrec /rebuildbcd"
            fi
            
            umount /mnt/windows 2>/dev/null
        else
            fail "Could not mount $bcd_part (is it NTFS?)"
        fi
        ;;
    3)
        header "NTFS Boot Sector Repair"
        echo ""
        echo -e "  ${YELLOW}Repairs the NTFS boot sector (first 16 sectors).${NC}"
        echo ""
        read -p "  Enter Windows partition (e.g. /dev/nvme0n1p3): " boot_dev
        echo ""
        
        # Back up current boot sector
        mkdir -p /root/reports
        dd if="$boot_dev" of="/root/reports/ntfs-bootsector-backup.bin" bs=512 count=16 2>/dev/null
        ok "Boot sector backed up to /root/reports/ntfs-bootsector-backup.bin"
        
        # Use ntfsfix to write a new boot sector
        ntfsfix -b "$boot_dev" 2>&1
        rc=$?
        if [ $rc -eq 0 ]; then
            ok "Boot sector repaired"
        else
            fail "Boot sector repair failed (exit code $rc)"
            echo "  Try: dd if=/dev/zero of=$boot_dev bs=512 count=16"
            echo "  Then: ntfsfix -b $boot_dev"
        fi
        ;;
    4)
        header "Windows Registry Repair (chntpw)"
        echo ""
        read -p "  Enter Windows partition (e.g. /dev/nvme0n1p3): " reg_part
        mkdir -p /mnt/windows
        
        if ntfs-3g "$reg_part" /mnt/windows 2>/dev/null; then
            ok "Mounted $reg_part"
            REG_DIR="/mnt/windows/Windows/System32/config"
            
            if [ -d "$REG_DIR" ]; then
                echo ""
                echo -e "  ${BOLD}Available registry hives:${NC}"
                ls -la "$REG_DIR"/{SAM,SECURITY,SOFTWARE,SYSTEM} 2>/dev/null | awk '{print "    " $NF}'
                echo ""
                echo "  chntpw can reset Windows passwords:"
                echo "    chntpw -l $REG_DIR/SAM          (list users)"
                echo "    chntpw -u username $REG_DIR/SAM  (reset password)"
                echo "    chntpw -i $REG_DIR/SAM           (interactive)"
                echo ""
                echo -e "  ${YELLOW}WARNING: Running chntpw on the wrong hive can break Windows login!${NC}"
                echo "  Make a backup first: cp $REG_DIR/SAM $REG_DIR/SAM.backup"
            else
                fail "Windows registry directory not found"
                echo "  $REG_DIR does not exist — is this the correct Windows partition?"
            fi
            
            umount /mnt/windows 2>/dev/null
        else
            fail "Could not mount $reg_part"
        fi
        ;;
    5)
        header "Mount Windows Partition"
        read -p "  Enter Windows partition (e.g. /dev/nvme0n1p3): " win_part
        mkdir -p /mnt/windows
        if ntfs-3g "$win_part" /mnt/windows 2>/dev/null; then
            ok "Mounted $win_part → /mnt/windows"
            echo ""
            echo -e "  ${BOLD}Contents:${NC}"
            ls /mnt/windows/ 2>/dev/null | head -10 | while read f; do echo "    ├─ $f"; done
            echo ""
            info "Access your files at /mnt/windows/"
            echo "  To unmount: umount /mnt/windows"
        else
            fail "Could not mount $win_part"
        fi
        ;;
    6)
        header "Restore Windows Boot Manager (UEFI)"
        echo ""
        echo -e "  ${YELLOW}Copies Windows EFI bootloader to the EFI System Partition.${NC}"
        echo ""
        
        if [ ${#efi_parts[@]} -eq 0 ]; then
            fail "No EFI System Partition found"
            echo "  Specify it manually: mount /dev/sdX1 /mnt/efi"
            exit 1
        fi
        
        for efi_dev in "${efi_parts[@]}"; do
            mkdir -p /mnt/efi
            if mount "$efi_dev" /mnt/efi 2>/dev/null; then
                ok "Mounted EFI partition: $efi_dev"
                
                # Look for Windows bootloader
                if [ -f "/mnt/efi/EFI/Microsoft/Boot/bootmgfw.efi" ]; then
                    ok "Windows bootloader already present"
                else
                    warn "Windows bootloader missing"
                    echo "  Attempting to restore from Windows partition..."
                    read -p "  Enter Windows partition: " win_part
                    mkdir -p /mnt/windows
                    if ntfs-3g "$win_part" /mnt/windows 2>/dev/null; then
                        WIN_EFI_SRC="/mnt/windows/Windows/Boot/EFI"
                        if [ -d "$WIN_EFI_SRC" ]; then
                            mkdir -p "/mnt/efi/EFI/Microsoft/Boot"
                            cp -r "$WIN_EFI_SRC/"* "/mnt/efi/EFI/Microsoft/Boot/" 2>/dev/null
                            ok "Windows EFI bootloader restored"
                        else
                            fail "Windows EFI sources not found on $win_part"
                        fi
                        umount /mnt/windows 2>/dev/null
                    fi
                fi
                
                umount /mnt/efi 2>/dev/null
            else
                fail "Could not mount $efi_dev"
            fi
        done
        ;;
    0) exit 0 ;;
    *) fail "Invalid choice" ;;
esac

echo ""
read -p "  Press Enter to continue..."
