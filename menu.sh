#!/bin/bash
# SysMedic Recovery Menu — v3.0 with hierarchical sub-menus

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
SCRIPTS="/opt/sysmedic/scripts"

# ──────────────────────────────────────────────
# Submenu helpers
# ──────────────────────────────────────────────
show_header() {
    local title="$1"
    clear
    echo ""
    echo -e "${BOLD}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}  ║  $title${NC}"
    echo -e "${BOLD}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

pause() {
    echo ""
    read -p "  Press Enter..."
}

confirm_yes() {
    local prompt="${1:-Are you sure? Type 'YES' to confirm: }"
    read -p "  $prompt" confirm
    [ "$confirm" = "YES" ]
}
# ──────────────────────────────────────────────

# ──────────────────────────────────────────────
# Submenu: Diagnostics
# ──────────────────────────────────────────────
menu_diagnostics() {
    while true; do
        show_header "  DIAGNOSTICS"
        echo "  1)  OpenCode AI Rescue (preflight + context)"
        echo "  2)  Quick diagnostics"
        echo "  3)  Scan partitions & detect installed OSes"
        echo "  4)  Smart Repair — auto-detect & fix OS issues"
        echo "  5)  Stress Test / Burn-In Suite — CPU, RAM, disk, temps"
        echo "  6)  AI Deep Analysis — aggregate all diagnostics for AI root cause analysis"
        echo ""
        echo "  0)  Back to main menu"
        echo ""
        read -p "  Choice [0-6]: " choice
        echo ""

        case "$choice" in
            1)
                show_header "  OPEnCODE AI RESCUE"
                if [ -x "$SCRIPTS/preflight.sh" ]; then
                    bash "$SCRIPTS/preflight.sh"
                fi
                if command -v opencode &>/dev/null; then
                    export SYSMEDIC_CONTEXT="/tmp/sysmedic-context.json"
                    eval "$(python3 << 'PYEOF' 2>/dev/null
import json, shlex
with open('/tmp/sysmedic-context.json') as f:
    d = json.load(f)
s = d.get('system', {})
c = d.get('cpu', {})
m = d.get('memory', {})
sb = d.get('secure_boot', {})
oses = d.get('detected_oses', [])
disks = d.get('disks', [])
def esc(v):
    return shlex.quote(str(v))
print(f'SYS_VENDOR={esc(s.get("vendor", ""))}')
print(f'SYS_PRODUCT={esc(s.get("product", ""))}')
print(f'SYS_SERIAL={esc(s.get("serial", ""))}')
print(f'SYS_BIOS={esc(s.get("bios_version", ""))}')
print(f'SYS_BIOS_DATE={esc(s.get("bios_date", ""))}')
print(f'CPU_MODEL={esc(c.get("model", "")[:65])}')
print(f'MEM_GB={esc(m.get("total_gb", "?"))}')
print(f'SB_STATUS={esc(sb.get("mokutil", ""))}')
os_list = '; '.join([f'{o.get("name","?")} on {o.get("device","?")}' for o in oses])
print(f'OS_LIST={esc(os_list)}')
disk_parts = [f'{d.get("device","?")} {d.get("size","?")} {d.get("type","?")} ({d.get("smart","?")})' for d in disks[:2]]
print(f'DISK_LIST={esc("; ".join(disk_parts))}')
PYEOF
)"
                    echo -e "  ${CYAN}Make:${NC}        $SYS_VENDOR"
                    echo -e "  ${CYAN}Model:${NC}       $SYS_PRODUCT"
                    echo -e "  ${CYAN}Serial:${NC}      $SYS_SERIAL"
                    echo -e "  ${CYAN}BIOS:${NC}        $SYS_BIOS ($SYS_BIOS_DATE)"
                    echo -e "  ${CYAN}CPU:${NC}         $CPU_MODEL"
                    echo -e "  ${CYAN}RAM:${NC}         $MEM_GB GB"
                    echo -e "  ${CYAN}Secure Boot:${NC} $SB_STATUS"
                    [ -n "$OS_LIST" ] && echo -e "  ${CYAN}OS:${NC}          $OS_LIST"
                    [ -n "$DISK_LIST" ] && echo -e "  ${CYAN}Disks:${NC}      $DISK_LIST"
                    echo ""
                    echo -e "  ${YELLOW}Press ENTER to launch SysMedic${NC}"
                    read -r
                    opencode
                else
                    echo -e "  ${RED}OpenCode not found — try mounting persistence partition first${NC}"
                    pause
                fi
                ;;
            2)
                show_header "  QUICK DIAGNOSTICS"
                if command -v sysmedic-diagnose &>/dev/null; then
                    sysmedic-diagnose
                else
                    echo -e "${BOLD}CPU:${NC}"; lscpu | grep "Model name" | head -1
                    echo -e "${BOLD}Memory:${NC}"; free -h
                    echo -e "${BOLD}Disks:${NC}"; lsblk -o NAME,SIZE,TYPE,FSTYPE
                    echo -e "${BOLD}Network:${NC}"; ip -4 addr show | grep inet
                fi
                pause
                ;;
            3)
                show_header "  PARTITION & OS SCAN"
                echo -e "${BOLD}=== Block Devices ===${NC}"
                lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT 2>/dev/null | grep -v loop
                echo ""
                echo -e "${BOLD}=== Installed Operating Systems ===${NC}"
                for part in $(lsblk -nr -o NAME,FSTYPE 2>/dev/null | grep -E 'ext4|ntfs|hfsplus|apfs|xfs|btrfs' | awk '{print $1}'); do
                    dev="/dev/$part"
                    mkdir -p /mnt/tmp_os_scan 2>/dev/null
                    if mount "$dev" /mnt/tmp_os_scan 2>/dev/null; then
                        if [ -f /mnt/tmp_os_scan/etc/os-release ]; then
                            echo "  🐧 Linux: $(grep PRETTY_NAME /mnt/tmp_os_scan/etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"') on $dev"
                        elif [ -d /mnt/tmp_os_scan/Windows/System32 ]; then
                            echo "  Windows detected on $dev"
                        elif [ -d /mnt/tmp_os_scan/System/Library/CoreServices ]; then
                            echo "  macOS detected on $dev"
                        elif [ -d /mnt/tmp_os_scan/Library ]; then
                            echo "  macOS (data volume) detected on $dev"
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
                pause
                ;;
            4)
                show_header "  SMART REPAIR"
                bash "$SCRIPTS/smart-repair.sh"
                ;;
            5)
                bash "$SCRIPTS/stress-test.sh"
                ;;
            6)
                show_header "  AI DEEP ANALYSIS"
                echo -e "  ${CYAN}This will:${NC}"
                echo "  1) Scan all drives for SMART health issues"
                echo "  2) Collect recent stress test results"
                echo "  3) Analyze kernel logs for errors (dmesg)"
                echo "  4) Check detected OS installations for issues"
                echo "  5) Probe bootloader integrity"
                echo "  6) Generate structured JSON for AI root cause analysis"
                echo ""
                echo "  Then optionally launch OpenCode with the full analysis."
                echo ""
                echo "  1)  Run analysis (quick — skip long tests)"
                echo "  2)  Run analysis (full — includes all checks)"
                echo "  3)  Run analysis + launch AI (quick)"
                echo "  4)  Run analysis + launch AI (full)"
                echo "  0)  Cancel"
                echo ""
                read -p "  Choose [0-4]: " ai_opt
                case "$ai_opt" in
                    1) bash "$SCRIPTS/sysmedic-analyze.sh" --quick ;;
                    2) bash "$SCRIPTS/sysmedic-analyze.sh" ;;
                    3) bash "$SCRIPTS/sysmedic-analyze.sh" --quick --ai ;;
                    4) bash "$SCRIPTS/sysmedic-analyze.sh" --ai ;;
                esac
                pause
                ;;
            0)  break ;;
            *)  echo -e "  ${RED}Invalid choice${NC}"; sleep 1 ;;
        esac
    done
}

# ──────────────────────────────────────────────
# Submenu: Networking
# ──────────────────────────────────────────────
menu_networking() {
    while true; do
        show_header "  NETWORKING"
        echo "  1)  Wi-Fi connect (nmtui)"
        echo ""
        echo "  0)  Back to main menu"
        echo ""
        read -p "  Choice [0-1]: " choice
        echo ""

        case "$choice" in
            1)
                show_header "  WIFI CONNECT"
                /usr/local/bin/wifi
                pause
                ;;
            0)  break ;;
            *)  echo -e "  ${RED}Invalid choice${NC}"; sleep 1 ;;
        esac
    done
}

# ──────────────────────────────────────────────
# Submenu: Linux Repair
# ──────────────────────────────────────────────
menu_linux() {
    while true; do
        show_header "  LINUX REPAIR"
        echo "  1)  Fix GRUB bootloader"
        echo "  2)  Fix corrupt initramfs (kernel panic)"
        echo "  3)  Fix /etc/fstab (wrong UUIDs)"
        echo "  4)  Fix oversized /boot (clean old kernels)"
        echo "  5)  Chroot into Linux installation"
        echo ""
        echo "  0)  Back to main menu"
        echo ""
        read -p "  Choice [0-5]: " choice
        echo ""

        case "$choice" in
            1)  show_header "  FIX GRUB";           [ -x "$SCRIPTS/linux-repair/fix-grub.sh" ] && bash "$SCRIPTS/linux-repair/fix-grub.sh" || echo -e "  ${RED}Script not found${NC}"; pause ;;
            2)  show_header "  FIX INITRAMFS";      [ -x "$SCRIPTS/linux-repair/fix-kernel-panic.sh" ] && bash "$SCRIPTS/linux-repair/fix-kernel-panic.sh" || echo -e "  ${RED}Script not found${NC}"; pause ;;
            3)  show_header "  FIX FSTAB";          [ -x "$SCRIPTS/linux-repair/fix-fstab.sh" ] && bash "$SCRIPTS/linux-repair/fix-fstab.sh" || echo -e "  ${RED}Script not found${NC}"; pause ;;
            4)  show_header "  CLEAN /BOOT";        [ -x "$SCRIPTS/linux-repair/fix-boot.sh" ] && bash "$SCRIPTS/linux-repair/fix-boot.sh" || echo -e "  ${RED}Script not found${NC}"; pause ;;
            5)
                show_header "  CHROOT INTO LINUX"
                echo "Available partitions:"
                lsblk -o NAME,SIZE,TYPE,FSTYPE 2>/dev/null | grep -E 'ext4|ext3|xfs|btrfs|NAME'
                echo ""
                read -p "  Enter Linux root partition (e.g. /dev/sda2): " linux_part
                read -p "  Enter EFI partition if separate (e.g. /dev/sda1, or leave blank): " efi_part
                echo ""

                mkdir -p /mnt/linux
                if mount "$linux_part" /mnt/linux 2>/dev/null; then
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
                    umount /mnt/linux/boot/efi 2>/dev/null
                    umount /mnt/linux/dev 2>/dev/null
                    umount /mnt/linux/proc 2>/dev/null
                    umount /mnt/linux/sys 2>/dev/null
                    umount /mnt/linux 2>/dev/null
                    echo -e "\n  ${GREEN}Unmounted and back to SysMedic${NC}"
                else
                    echo -e "  ${RED}Could not mount $linux_part${NC}"
                fi
                pause
                ;;
            0)  break ;;
            *)  echo -e "  ${RED}Invalid choice${NC}"; sleep 1 ;;
        esac
    done
}

# ──────────────────────────────────────────────
# Submenu: Windows Repair & BitLocker
# ──────────────────────────────────────────────
menu_windows() {
    while true; do
        show_header "  WINDOWS REPAIR & BITLOCKER"
        echo -e "  ${BOLD}── BitLocker ──${NC}"
        echo "  1)  Unlock BitLocker (CLI mode)"
        echo "  2)  Unlock BitLocker (Web portal)"
        echo ""
        echo -e "  ${BOLD}── Windows Repair ──${NC}"
        echo "  3)  Diagnose Windows (logs, BSOD, updates, drivers)"
        echo "  4)  Fix Windows Update / driver corruption"
        echo "  5)  NTFS check & repair (ntfsfix)"
        echo "  6)  Fix Windows BCD bootloader"
        echo "  7)  Fix NTFS boot sector"
        echo "  8)  Reset Windows password (chntpw)"
        echo "  9)  Restore Windows EFI boot manager"
        echo "  10) Mount Windows partition (read/write)"
        echo "  11) Recover data from Windows"
        echo ""
        echo "  0)  Back to main menu"
        echo ""
        read -p "  Choice [0-11]: " choice
        echo ""

        case "$choice" in
            1|2)
                show_header "  BITLOCKER UNLOCK"
                echo "  [C] CLI mode     — Type/paste the key directly in this terminal"
                echo "                     (works even without network)"
                echo ""
                echo "  (The old web portal was removed: it accepted keys from anyone on the network.)"
                echo ""
                read -p "  Choose [C/W]: " bl_method
                case "$bl_method" in
                    c|C) bash "$SCRIPTS/bitlocker-unlock.sh" ;;
                    w|W) echo "  The web portal was removed (it had no login). Use: sysmedic-win bitlocker /dev/X" ;;
                    *)   echo -e "  ${RED}Invalid choice${NC}" ;;
                esac
                pause
                ;;
            3)  show_header "  DIAGNOSE WINDOWS";      [ -x "$SCRIPTS/windows-repair/diagnose-windows.sh" ] && bash "$SCRIPTS/windows-repair/diagnose-windows.sh" || echo -e "  ${RED}Script not found${NC}"; pause ;;
            4)  show_header "  FIX WINDOWS UPDATE";    [ -x "$SCRIPTS/windows-repair/repair-updates.sh" ] && bash "$SCRIPTS/windows-repair/repair-updates.sh" || echo -e "  ${RED}Script not found${NC}"; pause ;;
            5)  show_header "  NTFS CHECK & REPAIR";   bash "$SCRIPTS/windows-repair/repair-windows.sh"; pause ;;
            6)  show_header "  FIX BCD BOOTLOADER";    bash "$SCRIPTS/windows-repair/repair-windows.sh" 2>/dev/null <<< "2"; pause ;;
            7)  show_header "  FIX NTFS BOOT SECTOR";  bash "$SCRIPTS/windows-repair/repair-windows.sh" 2>/dev/null <<< "3"; pause ;;
            8)  show_header "  RESET WINDOWS PASSWORD"; bash "$SCRIPTS/windows-repair/repair-windows.sh" 2>/dev/null <<< "4"; pause ;;
            9)  show_header "  RESTORE EFI BOOT MANAGER"; bash "$SCRIPTS/windows-repair/repair-windows.sh" 2>/dev/null <<< "6"; pause ;;
            10) show_header "  MOUNT WINDOWS PARTITION"; bash "$SCRIPTS/windows-repair/repair-windows.sh" 2>/dev/null <<< "5"; pause ;;
            11) show_header "  RECOVER WINDOWS DATA";  [ -x "$SCRIPTS/windows-repair/recover-windows.sh" ] && bash "$SCRIPTS/windows-repair/recover-windows.sh" || echo -e "  ${RED}Script not found${NC}"; pause ;;
            0)  break ;;
            *)  echo -e "  ${RED}Invalid choice${NC}"; sleep 1 ;;
        esac
    done
}

# ──────────────────────────────────────────────
# Submenu: macOS Repair
# ──────────────────────────────────────────────
menu_macos() {
    while true; do
        show_header "  MACOS REPAIR"
        echo "  1)  Scan for macOS volumes (HFS+ / APFS)"
        echo "  2)  Mount macOS volumes (read-write/read-only)"
        echo "  3)  Repair HFS+/APFS volumes"
        echo "  4)  Recover data from macOS"
        echo ""
        echo "  0)  Back to main menu"
        echo ""
        read -p "  Choice [0-4]: " choice
        echo ""

        case "$choice" in
            1)  show_header "  SCAN MACOS VOLUMES";  [ -x "$SCRIPTS/macos-repair/scan-macos.sh" ] && bash "$SCRIPTS/macos-repair/scan-macos.sh" || echo -e "  ${RED}Script not found${NC}"; pause ;;
            2)  show_header "  MOUNT MACOS VOLUMES"; [ -x "$SCRIPTS/macos-repair/mount-macos.sh" ] && bash "$SCRIPTS/macos-repair/mount-macos.sh" || echo -e "  ${RED}Script not found${NC}"; pause ;;
            3)  show_header "  REPAIR MACOS VOLUMES";[ -x "$SCRIPTS/macos-repair/repair-macos.sh" ] && bash "$SCRIPTS/macos-repair/repair-macos.sh" || echo -e "  ${RED}Script not found${NC}"; pause ;;
            4)  show_header "  RECOVER MACOS DATA";  [ -x "$SCRIPTS/macos-repair/recover-macos.sh" ] && bash "$SCRIPTS/macos-repair/recover-macos.sh" || echo -e "  ${RED}Script not found${NC}"; pause ;;
            0)  break ;;
            *)  echo -e "  ${RED}Invalid choice${NC}"; sleep 1 ;;
        esac
    done
}

# ──────────────────────────────────────────────
# Submenu: Utilities
# ──────────────────────────────────────────────
menu_utilities() {
    while true; do
        show_header "  UTILITIES"
        echo "  1)  Clone/rescue drive (ddrescue)"
        echo "  2)  Capture/Restore OS image"
        echo ""
        echo "  0)  Back to main menu"
        echo ""
        read -p "  Choice [0-2]: " choice
        echo ""

        case "$choice" in
            1)
                show_header "  DRIVE CLONE / RESCUE"
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
                        if confirm_yes; then
                            echo -e "\n  ${CYAN}Starting ddrescue clone...${NC}"
                            ddrescue --verbose --force "$src" "$dst" "/root/reports/ddrescue_$(basename $src)_mapfile.log"
                            echo -e "\n  Done. Mapfile saved to /root/reports/"
                        fi
                        ;;
                    2)
                        read -p "  Source partition (e.g. /dev/sda1): " src
                        read -p "  Target file [/root/recovered.img]: " dst
                        dst="${dst:-/root/recovered.img}"
                        echo -e "\n  ${CYAN}Starting ddrescue...${NC}"
                        ddrescue --verbose "$src" "$dst" "/root/reports/ddrescue_part_mapfile.log"
                        echo -e "\n  Image saved to $dst"
                        ;;
                    3)
                        read -p "  Source device (e.g. /dev/sdc): " src
                        read -p "  Target device/file: " dst
                        ddrescue --verbose --retry-passes=3 "$src" "$dst" "/root/reports/ddrescue_retry_mapfile.log"
                        echo -e "\n  Retry passes complete. Check /root/reports/ for log"
                        ;;
                esac
                pause
                ;;
            2)
                show_header "  CAPTURE / RESTORE OS IMAGE"
                bash "$SCRIPTS/capture-restore.sh"
                ;;
            0)  break ;;
            *)  echo -e "  ${RED}Invalid choice${NC}"; sleep 1 ;;
        esac
    done
}

# ──────────────────────────────────────────────
# Submenu: System
# ──────────────────────────────────────────────
menu_system() {
    while true; do
        show_header "  SYSTEM"
        echo "  1)  Drop to shell (exit to return)"
        echo "  2)  Reboot"
        echo "  3)  Persistence status (session save/restore)"
        echo "  4)  Check for updates"
        echo ""
        echo "  0)  Back to main menu"
        echo ""
        read -p "  Choice [0-4]: " choice
        echo ""

        case "$choice" in
            1)
                echo -e "${YELLOW}Dropping to shell. Type 'exit' to return to menu.${NC}\n"
                cd /
                bash
                ;;
            2)
                # Save session before reboot
                [ -x "$SCRIPTS/sysmedic-persist.sh" ] && bash "$SCRIPTS/sysmedic-persist.sh" save "reboot"
                echo "Rebooting..."
                reboot
                ;;
            3)
                show_header "  PERSISTENCE"
                bash "$SCRIPTS/sysmedic-persist.sh" status
                echo ""
                echo "  Options:"
                echo "  1)  Save session now"
                echo "  2)  Show previous session"
                echo "  0)  Back"
                echo ""
                read -p "  Choose: " persist_opt
                case "$persist_opt" in
                    1) bash "$SCRIPTS/sysmedic-persist.sh" save "manual" ;;
                    2) bash "$SCRIPTS/sysmedic-persist.sh" prev ;;
                esac
                pause
                ;;
            4)
                show_header "  UPDATE CHECK"
                bash "$SCRIPTS/sysmedic-update.sh" update
                pause
                ;;
            0)  break ;;
            *)  echo -e "  ${RED}Invalid choice${NC}"; sleep 1 ;;
        esac
    done
}

# ──────────────────────────────────────────────
# Main Menu
# ──────────────────────────────────────────────
while true; do
    clear
    echo ""
    echo -e "${BOLD}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}  ║      🩺  SysMedic Recovery System  v3.0             ║${NC}"
    echo -e "${BOLD}  ║      Hardware-aware · Mesh-connected                ║${NC}"
    echo -e "${BOLD}  ╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}  ║  1)  Diagnostics                             ${BOLD}║${NC}"
    echo -e "${BOLD}  ║      AI Rescue · Quick diag · OS scan · Smart Repair ${BOLD}║${NC}"
    echo -e "${BOLD}  ║                                                    ${BOLD}║${NC}"
    echo -e "${BOLD}  ║  2)  Networking                              ${BOLD}║${NC}"
    echo -e "${BOLD}  ║      Networking                          ${BOLD}║${NC}"
    echo -e "${BOLD}  ║                                                    ${BOLD}║${NC}"
    echo -e "${BOLD}  ║  3)  Linux Repair                            ${BOLD}║${NC}"
    echo -e "${BOLD}  ║      GRUB · initramfs · fstab · /boot · chroot      ${BOLD}║${NC}"
    echo -e "${BOLD}  ║                                                    ${BOLD}║${NC}"
    echo -e "${BOLD}  ║  4)  Windows Repair & BitLocker              ${BOLD}║${NC}"
    echo -e "${BOLD}  ║      Unlock · Diagnose · BCD · NTFS · Password      ${BOLD}║${NC}"
    echo -e "${BOLD}  ║                                                    ${BOLD}║${NC}"
    echo -e "${BOLD}  ║  5)  macOS Repair                            ${BOLD}║${NC}"
    echo -e "${BOLD}  ║      Scan · Mount · Repair · Recover                ${BOLD}║${NC}"
    echo -e "${BOLD}  ║                                                    ${BOLD}║${NC}"
    echo -e "${BOLD}  ║  6)  Utilities                               ${BOLD}║${NC}"
    echo -e "${BOLD}  ║      ddrescue Clone · Capture/Restore Image         ${BOLD}║${NC}"
    echo -e "${BOLD}  ║                                                    ${BOLD}║${NC}"
    echo -e "${BOLD}  ║  7)  System                                  ${BOLD}║${NC}"
    echo -e "${BOLD}  ║      Shell · Reboot · Persist · Updates              ${BOLD}║${NC}"
    echo -e "${BOLD}  ╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}  ║  0)  Shutdown                                       ${BOLD}║${NC}"
    echo -e "${BOLD}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -ne "  ${CYAN}Choice [0-7]:${NC} "
    read choice
    echo ""

    # Save choice locally, then unset to prevent submenu variable leakage
    _main_choice="$choice"
    unset choice
    case "$_main_choice" in
        1)  menu_diagnostics ;;
        2)  menu_networking ;;
        3)  menu_linux ;;
        4)  menu_windows ;;
        5)  menu_macos ;;
        6)  menu_utilities ;;
        7)  menu_system ;;
        0)  echo "Shutting down..."; poweroff ;;
        *)  echo -e "  ${RED}Invalid choice${NC}"; sleep 1 ;;
    esac
done
