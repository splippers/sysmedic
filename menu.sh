#!/bin/bash
# SysMedic Recovery Menu — v2.0 with multi-OS repair toolkit

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
SCRIPTS="/opt/sysmedic/scripts"

while true; do
    clear
    echo ""
    echo -e "${BOLD}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}  ║      🩺  SysMedic Recovery System  v2.1             ║${NC}"
    echo -e "${BOLD}  ║      Hardware-aware · Mesh-connected                ║${NC}"
    echo -e "${BOLD}  ╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}  ║  DIAGNOSTICS                                        ║${NC}"
    echo -e "${BOLD}  ║   1)  OpenCode AI Rescue (preflight + context)      ║${NC}"
    echo -e "${BOLD}  ║   2)  Quick diagnostics (sysmedic-diagnose)         ║${NC}"
    echo -e "${BOLD}  ║   3)  Scan partitions & detect installed OSes       ║${NC}"
    echo -e "${BOLD}  ╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}  ║  NETWORKING                                         ║${NC}"
    echo -e "${BOLD}  ║   4)  WiFi Connect (WPS / Password)                 ║${NC}"
    echo -e "${BOLD}  ║   5)  CraicKen Telemetry (call home)                ║${NC}"
    echo -e "${BOLD}  ╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}  ║  LINUX REPAIR                                       ║${NC}"
    echo -e "${BOLD}  ║   6)  Fix GRUB bootloader                           ║${NC}"
    echo -e "${BOLD}  ║   7)  Fix corrupt initramfs (kernel panic)          ║${NC}"
    echo -e "${BOLD}  ║   8)  Fix /etc/fstab (wrong UUIDs)                  ║${NC}"
    echo -e "${BOLD}  ║   9)  Fix oversized /boot (clean old kernels)       ║${NC}"
    echo -e "${BOLD}  ║  10)  Chroot into Linux installation                ║${NC}"
    echo -e "${BOLD}  ╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}  ║  BITLOCKER                                          ║${NC}"
    echo -e "${BOLD}  ║  11)  Unlock BitLocker:  [C] CLI  [W] Web portal     ║${NC}"
    echo -e "${BOLD}  ╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}  ║  WINDOWS REPAIR                                     ║${NC}"
    echo -e "${BOLD}  ║  12)  Diagnose Windows (logs, BSOD, updates, drivers) ║${NC}"
    echo -e "${BOLD}  ║  13)  Fix Windows Update / driver corruption          ║${NC}"
    echo -e "${BOLD}  ║  14)  NTFS check & repair (ntfsfix)                   ║${NC}"
    echo -e "${BOLD}  ║  15)  Fix Windows BCD bootloader                       ║${NC}"
    echo -e "${BOLD}  ║  16)  Fix NTFS boot sector                             ║${NC}"
    echo -e "${BOLD}  ║  17)  Reset Windows password (chntpw)                 ║${NC}"
    echo -e "${BOLD}  ║  18)  Restore Windows EFI boot manager                ║${NC}"
    echo -e "${BOLD}  ║  19)  Mount Windows partition (read/write)            ║${NC}"
    echo -e "${BOLD}  ║  20)  Recover data from Windows                       ║${NC}"
    echo -e "${BOLD}  ╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}  ║  macOS REPAIR                                       ║${NC}"
    echo -e "${BOLD}  ║  21)  Scan for macOS volumes (HFS+ / APFS)          ║${NC}"
    echo -e "${BOLD}  ║  22)  Mount macOS volumes (read-write/read-only)    ║${NC}"
    echo -e "${BOLD}  ║  23)  Repair HFS+/APFS volumes                      ║${NC}"
    echo -e "${BOLD}  ║  24)  Recover data from macOS                       ║${NC}"
    echo -e "${BOLD}  ╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}  ║  UTILITIES                                          ║${NC}"
    echo -e "${BOLD}  ║  25)  Full system diagnostic report                 ║${NC}"
    echo -e "${BOLD}  ║  26)  Clone/rescue drive (ddrescue)                 ║${NC}"
    echo -e "${BOLD}  ║  27)  Drop to shell (exit to return)                ║${NC}"
    echo -e "${BOLD}  ║  28)  Reboot                                         ║${NC}"
    echo -e "${BOLD}  ║   0)  Shutdown                                       ║${NC}"
    echo -e "${BOLD}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -ne "  ${CYAN}Choice [0-28]:${NC} "
    read choice
    echo ""

    case "$choice" in
        1)  clear
            # Run preflight to gather hardware context + mesh sync
            if [ -x "$SCRIPTS/preflight.sh" ]; then
                bash "$SCRIPTS/preflight.sh"
                echo ""
            fi
            # Launch AI with context available
            if command -v opencode &>/dev/null; then
                export SYSMEDIC_CONTEXT="/tmp/sysmedic-context.json"
                echo -e "  ${GREEN}Launching OpenCode AI with full hardware context...${NC}\n"
                opencode
            else
                echo "OpenCode not found — try mounting persistence partition first"
                read -p "Press Enter..."
            fi
            ;;

        2)  clear
            if command -v sysmedic-diagnose &>/dev/null; then
                sysmedic-diagnose
            else
                echo "sysmedic-diagnose not found — running quick diagnostic..."
                echo ""
                echo -e "${BOLD}CPU:${NC}"; lscpu | grep "Model name" | head -1
                echo -e "${BOLD}Memory:${NC}"; free -h
                echo -e "${BOLD}Disks:${NC}"; lsblk -o NAME,SIZE,TYPE,FSTYPE
                echo -e "${BOLD}Network:${NC}"; ip -4 addr show | grep inet
            fi
            read -p "Press Enter..."
            ;;

        3)  clear
            echo -e "${BOLD}=== Partition & OS Scan ===${NC}\n"
            lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT 2>/dev/null | grep -v loop
            echo ""
            echo -e "${BOLD}=== Installed Operating Systems ===${NC}"
            for part in $(lsblk -nr -o NAME,FSTYPE 2>/dev/null | grep -E 'ext4|ntfs|hfsplus|apfs|xfs|btrfs' | awk '{print $1}'); do
                dev="/dev/$part"
                mkdir -p /mnt/tmp_os_scan
                if mount "$dev" /mnt/tmp_os_scan 2>/dev/null; then
                    if [ -f /mnt/tmp_os_scan/etc/os-release ]; then
                        echo "  🐧 Linux: $(grep PRETTY_NAME /mnt/tmp_os_scan/etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"') on $dev"
                    elif [ -d /mnt/tmp_os_scan/Windows/System32 ]; then
                        echo "  🪟 Windows detected on $dev"
                    elif [ -d /mnt/tmp_os_scan/System/Library/CoreServices ]; then
                        echo "  🍎 macOS detected on $dev"
                    elif [ -d /mnt/tmp_os_scan/Library ]; then
                        echo "  🍎 macOS (data volume) detected on $dev"
                    fi
                    umount /mnt/tmp_os_scan 2>/dev/null
                fi
            done
            rmdir /mnt/tmp_os_scan 2>/dev/null
            echo ""
            echo -e "${BOLD}=== SMART Status ===${NC}"
            for disk in nvme0n1 sda sdb sdc; do
                [ -b "/dev/$disk" ] || continue
                if command -v smartctl &>/dev/null; then
                    echo "  $disk: $(smartctl -H /dev/$disk 2>/dev/null | grep -E 'SMART overall-health|PASSED|FAILED' | head -1)"
                fi
            done
            read -p "Press Enter..."
            ;;

        4)  clear
            [ -x "$SCRIPTS/wifi-connect.sh" ] && bash "$SCRIPTS/wifi-connect.sh" || echo "WiFi script not found"
            read -p "Press Enter..."
            ;;

        5)  clear
            echo -e "${BOLD}CraicKen Mesh Options${NC}"
            echo ""
            echo "  1) Connect & telemetry (register + diagnostics to mesh)"
            echo "  2) Sync knowledge (push session log + wiki to CraicKen)"
            echo "  0) Back"
            echo ""
            read -p "  Choose: " ck_opt
            case "$ck_opt" in
                1) [ -x "$SCRIPTS/craic-connect.sh" ] && bash "$SCRIPTS/craic-connect.sh" || echo "Script not found" ;;
                2) [ -x "$SCRIPTS/craicken-sync.sh" ] && bash "$SCRIPTS/craicken-sync.sh" || echo "Script not found" ;;
            esac
            read -p "Press Enter..."
            ;;

        6)  clear
            [ -x "$SCRIPTS/linux-repair/fix-grub.sh" ] && bash "$SCRIPTS/linux-repair/fix-grub.sh" || echo "Script not found"
            read -p "Press Enter..."
            ;;

        7)  clear
            [ -x "$SCRIPTS/linux-repair/fix-kernel-panic.sh" ] && bash "$SCRIPTS/linux-repair/fix-kernel-panic.sh" || echo "Script not found"
            read -p "Press Enter..."
            ;;

        8)  clear
            [ -x "$SCRIPTS/linux-repair/fix-fstab.sh" ] && bash "$SCRIPTS/linux-repair/fix-fstab.sh" || echo "Script not found"
            read -p "Press Enter..."
            ;;

        9)  clear
            [ -x "$SCRIPTS/linux-repair/fix-boot.sh" ] && bash "$SCRIPTS/linux-repair/fix-boot.sh" || echo "Script not found"
            read -p "Press Enter..."
            ;;

        10) clear
            echo -e "${BOLD}=== Chroot into Linux ===${NC}\n"
            echo "Available partitions:"
            lsblk -o NAME,SIZE,TYPE,FSTYPE 2>/dev/null | grep -E 'ext4|ext3|xfs|btrfs|NAME'
            echo ""
            read -p "  Enter Linux root partition (e.g. /dev/sda2): " linux_part
            read -p "  Enter EFI partition if separate (e.g. /dev/sda1, or leave blank): " efi_part
            echo ""
            
            mkdir -p /mnt/linux
            if mount "$linux_part" /mnt/linux 2>/dev/null; then
                ok=1
                # Mount essential filesystems
                mount --bind /dev /mnt/linux/dev 2>/dev/null
                mount --bind /proc /mnt/linux/proc 2>/dev/null
                mount --bind /sys /mnt/linux/sys 2>/dev/null
                
                if [ -n "$efi_part" ]; then
                    mkdir -p /mnt/linux/boot/efi
                    mount "$efi_part" /mnt/linux/boot/efi 2>/dev/null && \
                        echo "  EFI partition mounted"
                fi
                
                echo -e "\n  ${GREEN}Entering chroot. Type 'exit' to return.${NC}\n"
                chroot /mnt/linux /bin/bash 2>/dev/null || chroot /mnt/linux /bin/sh 2>/dev/null
                
                # Cleanup
                umount /mnt/linux/boot/efi 2>/dev/null
                umount /mnt/linux/dev 2>/dev/null
                umount /mnt/linux/proc 2>/dev/null
                umount /mnt/linux/sys 2>/dev/null
                umount /mnt/linux 2>/dev/null
                echo -e "\n  ${GREEN}Unmounted and back to SysMedic${NC}"
            else
                echo "  ${RED}Could not mount $linux_part${NC}"
            fi
            read -p "Press Enter..."
            ;;

        11) clear
            echo -e "${BOLD}BitLocker Unlock Methods${NC}"
            echo ""
            echo "  [C] CLI mode     — Type/paste the key directly in this terminal"
            echo "                     (works even without network)"
            echo ""
            echo "  [W] Web portal   — Starts a web server on port 8080"
            echo "                     Open http://<this-ip>:8080 from your phone/laptop"
            echo "                     Paste the key there + get diagnostics"
            echo ""
            read -p "  Choose [C/W]: " bl_method
            case "$bl_method" in
                c|C) bash "$SCRIPTS/bitlocker-unlock.sh" ;;
                w|W) bash "$SCRIPTS/bitlocker-web.sh" ;;
                *)   echo "Invalid choice" ;;
            esac
            read -p "Press Enter..."
            ;;

        12) clear
            [ -x "$SCRIPTS/windows-repair/diagnose-windows.sh" ] && bash "$SCRIPTS/windows-repair/diagnose-windows.sh" || echo "Script not found"
            read -p "Press Enter..."
            ;;

        13) clear
            [ -x "$SCRIPTS/windows-repair/repair-updates.sh" ] && bash "$SCRIPTS/windows-repair/repair-updates.sh" || echo "Script not found"
            read -p "Press Enter..."
            ;;

        14) clear
            bash "$SCRIPTS/windows-repair/repair-windows.sh"
            read -p "Press Enter..."
            ;;

        15) clear
            # BCD repair (from repair-windows.sh option 2)
            bash "$SCRIPTS/windows-repair/repair-windows.sh" 2>/dev/null <<< "2"
            read -p "Press Enter..."
            ;;

        16) clear
            bash "$SCRIPTS/windows-repair/repair-windows.sh" 2>/dev/null <<< "3"
            read -p "Press Enter..."
            ;;

        17) clear
            bash "$SCRIPTS/windows-repair/repair-windows.sh" 2>/dev/null <<< "4"
            read -p "Press Enter..."
            ;;

        18) clear
            bash "$SCRIPTS/windows-repair/repair-windows.sh" 2>/dev/null <<< "6"
            read -p "Press Enter..."
            ;;

        19) clear
            bash "$SCRIPTS/windows-repair/repair-windows.sh" 2>/dev/null <<< "5"
            read -p "Press Enter..."
            ;;

        20) clear
            bash "$SCRIPTS/windows-repair/recover-windows.sh"
            read -p "Press Enter..."
            ;;

        21) clear
            [ -x "$SCRIPTS/macos-repair/scan-macos.sh" ] && bash "$SCRIPTS/macos-repair/scan-macos.sh" || echo "Script not found"
            read -p "Press Enter..."
            ;;

        22) clear
            [ -x "$SCRIPTS/macos-repair/mount-macos.sh" ] && bash "$SCRIPTS/macos-repair/mount-macos.sh" || echo "Script not found"
            read -p "Press Enter..."
            ;;

        23) clear
            [ -x "$SCRIPTS/macos-repair/repair-macos.sh" ] && bash "$SCRIPTS/macos-repair/repair-macos.sh" || echo "Script not found"
            read -p "Press Enter..."
            ;;

        24) clear
            [ -x "$SCRIPTS/macos-repair/recover-macos.sh" ] && bash "$SCRIPTS/macos-repair/recover-macos.sh" || echo "Script not found"
            read -p "Press Enter..."
            ;;

        25) clear
            echo -e "${BOLD}=== Full System Diagnostic Report ===${NC}\n"
            REPORT="/root/reports/diagnostic_$(date +%Y%m%d_%H%M%S).txt"
            mkdir -p /root/reports
            {
                echo "==========================================="
                echo " SysMedic Diagnostic Report"
                echo " Generated: $(date)"
                echo " Hostname: $(hostname)"
                echo " Kernel: $(uname -a)"
                echo "==========================================="
                echo ""
                echo "=== CPU ==="
                lscpu 2>/dev/null | grep -E 'Model name|CPU\(s\)|Thread|Core|MHz|Architecture'
                echo ""
                echo "=== Memory ==="
                free -h
                echo ""
                echo "=== Block Devices ==="
                lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT 2>/dev/null
                echo ""
                echo "=== SMART Status ==="
                for disk in nvme0n1 sda sdb sdc; do
                    [ -b "/dev/$disk" ] || continue
                    smartctl -H /dev/$disk 2>/dev/null | grep -E 'SMART overall-health|PASSED|FAILED|Device Error'
                done
                echo ""
                echo "=== Mounted Filesystems ==="
                mount | grep -v tmpfs | grep -v devtmpfs | grep -v proc | grep -v sysfs
                echo ""
                echo "=== Network ==="
                ip addr show 2>/dev/null | grep -E 'inet |link/ether'
                echo ""
                echo "=== Battery ==="
                for bat in /sys/class/power_supply/BAT*; do
                    [ -d "$bat" ] && cat "$bat/uevent" 2>/dev/null
                done
                echo ""
                echo "=== Detected OSes ==="
                for part in $(lsblk -nr -o NAME,FSTYPE 2>/dev/null | grep -E 'ext4|ntfs|hfsplus|apfs|xfs|btrfs' | awk '{print $1}'); do
                    dev="/dev/$part"
                    mkdir -p /mnt/tmp_diag
                    mount "$dev" /mnt/tmp_diag 2>/dev/null || continue
                    if [ -f /mnt/tmp_diag/etc/os-release ]; then
                        echo "  Linux: $(grep PRETTY_NAME /mnt/tmp_diag/etc/os-release | cut -d= -f2 | tr -d '\"') on $dev"
                    elif [ -d /mnt/tmp_diag/Windows/System32 ]; then
                        echo "  Windows on $dev"
                    elif [ -d /mnt/tmp_diag/System/Library/CoreServices ]; then
                        echo "  macOS on $dev"
                    fi
                    umount /mnt/tmp_diag 2>/dev/null
                done
            } > "$REPORT"
            cat "$REPORT" | more
            echo ""
            echo -e "  ${GREEN}Report saved to: $REPORT${NC}"
            read -p "Press Enter..."
            ;;

        26) clear
            echo -e "${BOLD}=== Drive Clone / Rescue ===${NC}\n"
            echo "Available disks:"
            lsblk -o NAME,SIZE,TYPE,MODEL 2>/dev/null | grep -E 'disk|NAME'
            echo ""
            echo "  1) Clone entire disk (ddrescue)"
            echo "  2) Clone single partition (ddrescue)"
            echo "  3) Verify and recover (ddrescue + mapfile)"
            echo ""
            read -p "  Choose [1-3] or 0 to cancel: " clone_opt
            case "$clone_opt" in
                1)
                    read -p "  Source disk (e.g. /dev/sda): " src
                    read -p "  Target disk (e.g. /dev/sdb): " dst
                    echo ""
                    echo -e "  ${YELLOW}WARNING: This will DESTROY all data on $dst!${NC}"
                    read -p "  Are you sure? Type 'YES' to confirm: " confirm
                    if [ "$confirm" = "YES" ]; then
                        echo -e "\n  ${CYAN}Starting ddrescue clone...${NC}"
                        ddrescue --verbose --force "$src" "$dst" "/root/reports/ddrescue_$(basename $src)_mapfile.log"
                        echo ""
                        echo "  Done. Mapfile saved to /root/reports/"
                    fi
                    ;;
                2)
                    read -p "  Source partition (e.g. /dev/sda1): " src
                    read -p "  Target file (/root/recovered.img): " dst
                    dst="${dst:-/root/recovered.img}"
                    echo -e "\n  ${CYAN}Starting ddrescue...${NC}"
                    ddrescue --verbose "$src" "$dst" "/root/reports/ddrescue_part_mapfile.log"
                    echo ""
                    echo "  Image saved to $dst"
                    ;;
                3)
                    read -p "  Source device (e.g. /dev/sdc): " src
                    read -p "  Target device/file: " dst
                    ddrescue --verbose --retry-passes=3 "$src" "$dst" "/root/reports/ddrescue_retry_mapfile.log"
                    echo ""
                    echo "  Retry passes complete. Check /root/reports/ for log"
                    ;;
            esac
            read -p "Press Enter..."
            ;;

        27) clear
            echo -e "${YELLOW}Dropping to shell. Type 'exit' to return to menu.${NC}\n"
            cd /
            bash
            ;;

        28) echo "Rebooting..."; reboot ;;

        0)  echo "Shutting down..."; poweroff ;;

        *)  echo "Invalid choice"; sleep 1 ;;
    esac
done
