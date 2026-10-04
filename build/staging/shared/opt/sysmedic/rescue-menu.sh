#!/bin/bash
# SysMedic Rescue Menu

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'

EDITION=$(cat /etc/sysmedic/edition 2>/dev/null || echo unknown)
VERSION=$(cat /etc/sysmedic/version 2>/dev/null || echo dev)

while true; do
    clear
    echo ""
    echo -e "${BOLD}  ╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}  ║   🚑  SysMedic Rescue System   ║${NC}"
    echo -e "${BOLD}  ╠══════════════════════════════════════╣${NC}"
    echo -e "${BOLD}  ║  1) OpenCode AI Rescue Assistant    ║${NC}"
    echo -e "${BOLD}  ║  2) Wi-Fi connect (nmtui)           ║${NC}"
    echo -e "${BOLD}  ║  3) Save session log to USB         ║${NC}"
    echo -e "${BOLD}  ║  4) Triage scan (read-only)          ║${NC}"
    echo -e "${BOLD}  ║  5) Fix Linux boot (GRUB/initramfs)  ║${NC}"
    echo -e "${BOLD}  ║  6) Windows tools (BitLocker, BSOD…)  ║${NC}"
    echo -e "${BOLD}  ║  7) Fix macOS (HFS+/APFS)            ║${NC}"
    echo -e "${BOLD}  ║  8) Backup data                       ║${NC}"
    echo -e "${BOLD}  ║  9) Drop to shell (exit when done)   ║${NC}"
    echo -e "${BOLD}  ║ 10) Reboot                            ║${NC}"
    echo -e "${BOLD}  ║ 11) Unlock a partition for repair     ║${NC}"
    echo -e "${BOLD}  ║ 12) Write-protect all disks again     ║${NC}"
    echo -e "${BOLD}  ║ 13) Job report (for the customer)     ║${NC}"
    echo -e "${BOLD}  ║ 14) Phone dashboard (QR code)         ║${NC}"
    echo -e "${BOLD}  ║ 15) Advanced toolkit (stress test,    ║${NC}"
    echo -e "${BOLD}  ║     OS imaging, macOS, Windows extras)║${NC}"
    echo -e "${BOLD}  ║ 16) Hardware tests (CPU, RAM, disk,   ║${NC}"
    echo -e "${BOLD}  ║     GPU, battery, keyboard, audio)    ║${NC}"
    echo -e "${BOLD}  ║  0) Shutdown                          ║${NC}"
    echo -e "${BOLD}  ╚══════════════════════════════════════╝${NC}"
    echo -e "  ${CYAN}SysMedic ${EDITION} edition · v${VERSION}${NC}"
    echo ""
    echo -ne "  ${CYAN}Choice [0-16]:${NC} "
    read choice
    echo ""
    
    case "$choice" in
        1)
            clear
            if command -v opencode &>/dev/null; then
                SYSMEDIC_AI=opencode BASH_ENV=/etc/sysmedic/audit.sh opencode
            else
                echo "OpenCode not found"
                read -p "Press Enter..."
            fi
            ;;
        2)
            clear
            /usr/local/bin/wifi
            read -p "Press Enter..."
            ;;
        3)
            clear
            [ -x "/opt/sysmedic/scripts/sync-back.sh" ] && /opt/sysmedic/scripts/sync-back.sh || echo "sync-back script not found"
            read -p "Press Enter..."
            ;;
        4)
            clear
            /usr/local/bin/sysmedic-scan
            echo ""
            read -p "Press Enter..."
            ;;
        5)
            clear
            echo -e "${BOLD}=== Linux Boot Repair ===${NC}\n"
            echo "Select a script:"
            echo "  1) Fix GRUB bootloader"
            echo "  2) Fix corrupt initramfs (kernel panic)"
            echo "  3) Fix /etc/fstab (wrong UUIDs)"
            echo "  4) Fix oversized /boot"
            echo ""
            read -p "  Choose [1-4]: " lfix
            case "$lfix" in
                1) [ -x "/opt/sysmedic/scripts/linux-repair/fix-grub.sh" ] && bash /opt/sysmedic/scripts/linux-repair/fix-grub.sh || echo "Script not found" ;;
                2) [ -x "/opt/sysmedic/scripts/linux-repair/fix-kernel-panic.sh" ] && bash /opt/sysmedic/scripts/linux-repair/fix-kernel-panic.sh || echo "Script not found" ;;
                3) [ -x "/opt/sysmedic/scripts/linux-repair/fix-fstab.sh" ] && bash /opt/sysmedic/scripts/linux-repair/fix-fstab.sh || echo "Script not found" ;;
                4) [ -x "/opt/sysmedic/scripts/linux-repair/fix-boot.sh" ] && bash /opt/sysmedic/scripts/linux-repair/fix-boot.sh || echo "Script not found" ;;
            esac
            read -p "Press Enter..."
            ;;
        6)
            while true; do
                clear
                echo -e "${BOLD}=== Windows ===${NC}\n"
                /usr/local/bin/sysmedic-win
                echo ""
                echo "  1) System info (version, Fast Startup, pending updates, accounts)"
                echo "  2) Blue-screen crashes explained"
                echo "  3) Event log: disk, hardware, power and service problems"
                echo "  4) Autostart programs (suspicious ones flagged)"
                echo "  5) Malware scan (ClamAV)"
                echo ""
                echo "  c) Full check-up: everything below + the above, saved as a report"
                echo "  e) All event logs (apps, updates, drivers, Defender, boot times…)"
                echo "  r) Registry evidence (missing drivers/services, hijacks, policies)"
                echo "  s) Updates & servicing (CBS, DISM, Windows Update, upgrade logs)"
                echo ""
                echo "  6) Unlock a BitLocker volume (recovery key)"
                echo "  7) Roll back a half-installed update"
                echo "  8) Clear hibernation / Fast Startup lock"
                echo "  9) Reset a local account password"
                echo "  0) Back"
                echo ""
                read -p "  Choose: " w
                case "$w" in
                    1) /usr/local/bin/sysmedic-win info ;;
                    2) /usr/local/bin/sysmedic-win crashes ;;
                    3) /usr/local/bin/sysmedic-win events | less -R ;;
                    4) /usr/local/bin/sysmedic-win autoruns | less -R ;;
                    5) /usr/local/bin/sysmedic-win malware ;;
                    c|C) /usr/local/bin/sysmedic-win checkup 2>&1 | less -R ;;
                    e|E) /usr/local/bin/sysmedic-win evtx | less -R ;;
                    r|R) /usr/local/bin/sysmedic-win registry | less -R ;;
                    s|S) /usr/local/bin/sysmedic-win cbs | less -R ;;
                    6|7|8|9)
                        read -p "  Partition (e.g. /dev/nvme0n1p3): " part
                        case "$w" in
                            6) /usr/local/bin/sysmedic-win bitlocker "$part" ;;
                            7) /usr/local/bin/sysmedic-win fix-update "$part" ;;
                            8) /usr/local/bin/sysmedic-win fix-hibernation "$part" ;;
                            9) /usr/local/bin/sysmedic-win reset-password "$part" ;;
                        esac ;;
                    0|"") break ;;
                esac
                read -p "  Press Enter..."
            done
            ;;
        7)
            clear
            echo -e "${BOLD}=== macOS Repair ===${NC}\n"
            echo "HFS+ volumes can be mounted and repaired:"
            echo "  modprobe hfsplus && mount -t hfsplus -o force,rw /dev/sdXN /mnt/mac"
            echo ""
            echo "APFS requires apfs-fuse or macOS Recovery (Cmd+R at boot)"
            read -p "Press Enter..."
            ;;
        8)
            clear
            echo -e "${BOLD}=== Data Backup ===${NC}\n"
            if [ -d /mnt/persist ]; then
                echo "Persistence partition is mounted at /mnt/persist"
                echo "Available space: $(df -h /mnt/persist | tail -1 | awk '{print $4}')"
                echo ""
                echo "To backup: mount /dev/sdXN /mnt/target && rsync -av /mnt/target/ /mnt/persist/backups/"
            else
                echo "Persistence partition NOT mounted (looking for label FOG_AMB_PERSIST)"
                echo "Retry with: mount-persist"
            fi
            read -p "Press Enter..."
            ;;
        9)
            clear
            echo -e "${YELLOW}Dropping to shell. Type 'exit' or 'menu' to return.${NC}\n"
            cd /
            bash
            ;;
        10)
            echo "Rebooting..."
            reboot
            ;;
        11)
            clear
            /usr/local/sbin/sysmedic-guard status
            echo ""
            read -p "  Partition to unlock (e.g. /dev/nvme0n1p3), blank to cancel: " dev
            [ -n "$dev" ] && /usr/local/sbin/sysmedic-unlock "$dev"
            read -p "Press Enter..."
            ;;
        12)
            clear
            /usr/local/sbin/sysmedic-lock
            read -p "Press Enter..."
            ;;
        13)
            clear
            /usr/local/bin/sysmedic-report --print | less -R
            ;;
        14)
            clear
            /usr/local/bin/sysmedic-dash
            read -p "Press Enter..."
            ;;
        15)
            clear
            if [ "$EDITION" = caddy ] && [ -x /opt/sysmedic/menu.sh ]; then
                echo -e "${YELLOW}Tools that write to the customer's disks need the partition unlocked first (Alt+F2: sysmedic-unlock /dev/X).${NC}"
                sleep 2
                bash /opt/sysmedic/menu.sh
            else
                echo ""
                echo "  The advanced toolkit (stress tests, OS image capture/restore, macOS repair,"
                echo "  data carving) is on the SysMedic caddy edition. Use the caddy for this job."
                read -p "  Press Enter..."
            fi
            ;;
        16)
            clear
            /usr/local/bin/sysmedic-hwtest
            ;;
        0)
            echo "Shutting down..."
            poweroff
            ;;
        *)
            echo "Invalid choice"
            sleep 1
            ;;
    esac
done
