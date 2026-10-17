#!/bin/bash
# SysMedic Rescue Menu

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'

. /usr/local/lib/sysmedic/ui.sh 2>/dev/null || { ui_banner() { echo "== $1 =="; }; ui_section() { echo "-- $1 --"; }; ui_info() { echo "  $1"; }; ui_warn() { echo "  ! $1"; }; }
opt() { printf '  %s%3s%s  %s%s\n' "${_U_ACC:-}" "$1" "${_U_N:-}" "$2" "${3:+  ${_U_D:-}$3${_U_N:-}}"; }
ask() { echo; read -r -p "  ${_U_ACC:-}❯${_U_N:-} $1 " "$2"; }
pause() { echo; read -r -p "  ${_U_D:-}Enter to go back${_U_N:-} " _; }
EDITION=$(cat /etc/sysmedic/edition 2>/dev/null || echo unknown)
VERSION=$(cat /etc/sysmedic/version 2>/dev/null || echo dev)

while true; do
    clear
    python3 /usr/local/lib/sysmedic/menuview.py 2>/dev/null || {
        echo "  SysMedic rescue menu (v${VERSION}): 1 AI · 2 Wi-Fi · 3 save logs · 4 scan · 5 Linux boot · 6 Windows · 7 macOS"
        echo "  8 backup · 9 shell · 10 reboot · 11 unlock · 12 protect · 13 report · 14 phone · 15 toolkit · 16 tests · 17 repair AI · 0 off"; }
    keys="D, O, L, H, K, R, V"; command -v labwc >/dev/null && keys="$keys, G"; [ "$EDITION" = caddy ] && keys="$keys, U"
    echo -ne "  ${CYAN}❯${NC} Choose a number${keys:+ or $keys}: "
    read choice
    echo ""
    
    case "$choice" in
        5)
            clear
            if command -v opencode &>/dev/null; then
                t0=$(date +%s)
                tmux -f /etc/sysmedic/tmux.conf new-session -A -s ai-cloud "/usr/local/bin/sysmedic-ai-session cloud"
                rc=$?
                [ "$rc" != 0 ] && [ $(( $(date +%s) - t0 )) -lt 30 ] && \
                    { echo ""; echo "  OpenCode stopped straight away (exit $rc). Repair it with option 6."; read -p "  Press Enter..."; }
            else
                echo "OpenCode not found"
                read -p "Press Enter..."
            fi
            ;;
        o|O)
            clear
            if curl -sf --max-time 3 http://127.0.0.1:11434/api/version >/dev/null || /usr/local/sbin/start-ollama >/dev/null 2>&1; then
                tmux -f /etc/sysmedic/tmux.conf new-session -A -s ai-offline "/usr/local/bin/sysmedic-ai-session offline"
            else
                ui_warn "The offline AI isn't running and didn't start" "repair it with option 6, or check: sysmedic-ai-repair --check"
                read -p "  Press Enter..."
            fi
            ;;
        l|L)
            clear
            /usr/local/bin/sysmedic-raid assemble
            echo
            ui_info "Next" "scan what is inside: option 1 · stop and unplug safely: sysmedic-raid stop (Alt+F2)"
            pause
            ;;
        h|H)
            clear
            ui_banner "Private hotspot" "a Wi-Fi network of its own for your phone or laptop: nothing on the customer's network, and a bookmark that always works"
            /usr/local/sbin/sysmedic-hotspot status
            [ "$(ls /sys/class/ieee80211 2>/dev/null | wc -l)" -gt 1 ] && ui_info "More than one Wi-Fi radio found" "one carries the internet, another can host your phone: option 6 explains how"
            ui_section "Choose"
            opt 1 "Start the hotspot" "uses a radio of its own if there is one"
            opt 2 "Stop it"
            opt 3 "What would it use?" "radios, bands, and why"
            opt 4 "My hotspot name, password, band and country" "kept in the vault: follows you from job to job"
            opt 5 "Show the password and bookmarks" "on a private console"
            opt 6 "How do I get my phone on it?" "step by step, for the radios in this computer"
            opt 7 "Start it WITH internet for my phone" "through this computer's own link; the customer's network stays out of reach"
            opt 0 "Back"
            ask "Choose:" hc
            case "$hc" in
                1) /usr/local/sbin/sysmedic-hotspot on ;;
                2) /usr/local/sbin/sysmedic-hotspot off ;;
                3) /usr/local/sbin/sysmedic-hotspot plan ;;
                4) /usr/local/sbin/sysmedic-hotspot setup ;;
                5) /usr/local/sbin/sysmedic-hotspot show ;;
                6) /usr/local/sbin/sysmedic-hotspot guide ;;
                7) ui_warn "Your phone's traffic will leave through this customer's internet connection" "as this computer's. Only do this if that is acceptable here."
                   read -r -p "  Start it with internet? [y/N] " yn
                   [ "${yn,,}" = y ] && /usr/local/sbin/sysmedic-hotspot on --internet ;;
            esac
            pause
            ;;
        k|K)
            clear
            ui_banner "Remote access code" "your own code for the dashboard and AI terminal, for a laptop that can't scan the QR code"
            /usr/local/sbin/sysmedic-vault code status
            case "$(cat /run/sysmedic/vault.state 2>/dev/null)" in
                open)
                    ui_section "Choose"
                    opt n "New code: random words" "easy to read out; saved in the vault"
                    opt s "Set my own code" "typed twice, hidden"
                    opt v "Show the code" "on a private console"
                    opt c "Clear it" "back to a random secret every boot"
                    opt 0 "Back"
                    ask "Choose:" kc
                    case "$kc" in
                        n|N) /usr/local/sbin/sysmedic-vault code new ;;
                        s|S) /usr/local/sbin/sysmedic-vault code set ;;
                        v|V) /usr/local/sbin/sysmedic-vault code show ;;
                        c|C) /usr/local/sbin/sysmedic-vault code clear ;;
                    esac ;;
                *) ui_info "Unlock the vault first (menu V)" "the code is kept inside it, so it survives reboots without being readable" ;;
            esac
            pause
            ;;
        13)
            clear
            /usr/local/bin/wifi
            read -p "Press Enter..."
            ;;
        14)
            clear
            [ -x "/opt/sysmedic/scripts/sync-back.sh" ] && /opt/sysmedic/scripts/sync-back.sh || echo "sync-back script not found"
            read -p "Press Enter..."
            ;;
        1)
            clear
            /usr/local/bin/sysmedic-scan
            echo ""
            read -p "Press Enter..."
            ;;
        11)
            clear
            ui_banner "Linux boot repair" "writes to the customer's disk: unlock the partition first on Alt+F2 (sysmedic-unlock)"
            ui_section "Repairs"
            opt 1 "Fix the GRUB bootloader"
            opt 2 "Rebuild a corrupt initramfs" "kernel panic at boot"
            opt 3 "Fix /etc/fstab" "wrong or changed UUIDs"
            opt 4 "Fix an over-full /boot"
            opt 0 "Back"
            ask "Choose:" lfix
            case "$lfix" in
                1) [ -x "/opt/sysmedic/scripts/linux-repair/fix-grub.sh" ] && bash /opt/sysmedic/scripts/linux-repair/fix-grub.sh || echo "Script not found" ;;
                2) [ -x "/opt/sysmedic/scripts/linux-repair/fix-kernel-panic.sh" ] && bash /opt/sysmedic/scripts/linux-repair/fix-kernel-panic.sh || echo "Script not found" ;;
                3) [ -x "/opt/sysmedic/scripts/linux-repair/fix-fstab.sh" ] && bash /opt/sysmedic/scripts/linux-repair/fix-fstab.sh || echo "Script not found" ;;
                4) [ -x "/opt/sysmedic/scripts/linux-repair/fix-boot.sh" ] && bash /opt/sysmedic/scripts/linux-repair/fix-boot.sh || echo "Script not found" ;;
                *) continue ;;
            esac
            pause
            ;;
        7)
            while true; do
                clear
                ui_banner "Windows tools" "read-only unless noted · works on the offline installation"
                /usr/local/bin/sysmedic-win
                ui_section "Look"
                opt 1 "System info" "version, Fast Startup, pending updates, accounts"
                opt 2 "Blue screens and crash reports" "dumps and Windows Error Reporting, explained"
                opt 3 "Event log problems" "disk, hardware, power, services"
                opt 4 "Autostart programs" "suspicious ones flagged"
                opt 5 "Malware scan" "ClamAV"
                ui_section "Deep evidence"
                opt c "Full check-up" "everything here in one report, saved in the session"
                opt e "All event logs" "apps, updates, drivers, Defender, boot times"
                opt r "Registry evidence" "missing drivers/services, hijacks, policies"
                opt s "Updates & servicing" "CBS, DISM, Windows Update, upgrade logs"
                opt t "Traces (ETL)" "Windows Update and other components' failure codes"
                opt b "Boot configuration (BCD)" "entries, hypervisor, test-signing, Safe Mode"
                ui_section "Unlock & repair"
                opt 6 "Unlock BitLocker here" "recovery key typed on this console"
                opt w "Unlock BitLocker from a phone" "the key is typed there: secure link + QR"
                opt 7 "Roll back a half-installed update" "writes: unlock the partition first"
                opt 8 "Clear the hibernation / Fast Startup lock" "writes"
                opt 9 "Reset a local account password" "writes"
                opt 0 "Back"
                ask "Choose:" w
                case "$w" in
                    1) /usr/local/bin/sysmedic-win info ;;
                    2) /usr/local/bin/sysmedic-win crashes ;;
                    3) /usr/local/bin/sysmedic-win events | less -R ;;
                    4) /usr/local/bin/sysmedic-win autoruns | less -R ;;
                    5) /usr/local/bin/sysmedic-win malware ;;
                    w|W) /usr/local/bin/sysmedic-win bitlocker-web ;;
                    c|C) /usr/local/bin/sysmedic-win checkup 2>&1 | less -R ;;
                    e|E) /usr/local/bin/sysmedic-win evtx | less -R ;;
                    r|R) /usr/local/bin/sysmedic-win registry | less -R ;;
                    s|S) /usr/local/bin/sysmedic-win cbs | less -R ;;
                    t|T) /usr/local/bin/sysmedic-win etl | less -R ;;
                    b|B) /usr/local/bin/sysmedic-win bcd | less -R ;;
                    6|7|8|9)
                        read -p "  Partition (e.g. /dev/nvme0n1p3): " part
                        case "$w" in
                            6) /usr/local/bin/sysmedic-win bitlocker "$part" ;;
                            7) /usr/local/bin/sysmedic-win fix-update "$part" ;;
                            8) /usr/local/bin/sysmedic-win fix-hibernation "$part" ;;
                            9) /usr/local/bin/sysmedic-win reset-password "$part" ;;
                        esac ;;
                    0|"") break ;;
                    *) continue ;;
                esac
                pause
            done
            ;;
        12)
            clear
            ui_banner "macOS" "HFS+ and APFS"
            ui_section "HFS+ (older Macs)"
            ui_info "Mount and repair from here" "modprobe hfsplus && mount -t hfsplus -o force,rw /dev/sdXN /mnt/mac (unlock the partition first)"
            ui_section "APFS (2017 and later)"
            ui_info "Read with apfs-fuse, or repair from macOS Recovery" "Cmd+R at boot on Intel Macs; hold the power button on Apple silicon"
            pause
            ;;
        10)
            clear
            ui_banner "Back up data" "copies the customer's files to SysMedic's drive before any repair"
            if mountpoint -q /mnt/persist; then
                ui_ok "SysMedic's drive is ready" "$(df -h /mnt/persist | tail -1 | awk '{print $4}') free at /mnt/persist/backups"
                ui_section "How"
                ui_info "Mount the customer's partition read-only, then copy" \
                        "mkdir -p /mnt/target && mount -o ro /dev/sdXN /mnt/target && rsync -a --info=progress2 /mnt/target/Users/ /mnt/persist/backups/"
                ui_info "Or ask the AI assistant: \"back up the user folders from C:\"" "it proposes the commands; you approve each one"
            else
                ui_warn "SysMedic's data partition isn't mounted" "retry with: mount-persist"
            fi
            pause
            ;;
        16)
            clear
            echo -e "${YELLOW}Dropping to shell. Type 'exit' or 'menu' to return.${NC}\n"
            cd /
            bash
            ;;
        17)
            echo "Rebooting..."
            reboot
            ;;
        8)
            clear
            /usr/local/sbin/sysmedic-guard status
            echo ""
            read -p "  Partition to unlock (e.g. /dev/nvme0n1p3), blank to cancel: " dev
            [ -n "$dev" ] && /usr/local/sbin/sysmedic-unlock "$dev"
            read -p "Press Enter..."
            ;;
        9)
            clear
            /usr/local/sbin/sysmedic-lock
            read -p "Press Enter..."
            ;;
        3)
            clear
            /usr/local/bin/sysmedic-report --print | less -R
            ;;
        4)
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
        2)
            clear
            /usr/local/bin/sysmedic-tests menu
            ;;
        6)
            clear
            /usr/local/bin/sysmedic-ai-repair
            read -p "  Press Enter..."
            ;;
        g|G)
            if command -v labwc >/dev/null && [ -x /usr/local/bin/sysmedic-desktop ]; then
                /usr/local/bin/sysmedic-desktop
            else
                clear; ui_info "The graphical desktop isn't on this drive" "it's on the caddy edition; this drive has the console tools"; pause
            fi
            ;;
        r|R)
            clear
            if [ -e /run/sysmedic/remote-ai.on ]; then
                /usr/local/sbin/sysmedic-remote-ai off
            else
                ui_banner "Remote AI" "the AI assistants in the phone dashboard's AI card"
                ui_info "Every change either AI wants to make will need a keypress on THIS keyboard" "console 12 pops up with the exact command; a sniffed or stolen link can ask, never approve"
                ask "Turn remote AI on? [y/N]" yn
                [ "$yn" = y ] || [ "$yn" = Y ] && /usr/local/sbin/sysmedic-remote-ai on
            fi
            pause
            ;;
        v|V)
            clear
            ui_banner "Encrypted vault" "sessions, backups and transcripts on this drive, encrypted (LUKS2)"
            /usr/local/sbin/sysmedic-vault status
            case "$(cat /run/sysmedic/vault.state 2>/dev/null)" in
                ram) /usr/local/sbin/sysmedic-vault unlock ;;
                none|ram-none) /usr/local/sbin/sysmedic-vault setup ;;
            esac
            pause
            ;;
        d|D)
            clear
            /usr/local/bin/sysmedic-du
            pause
            ;;
        u|U)
            clear
            if [ "$EDITION" = caddy ]; then
                /usr/local/sbin/sysmedic-update apply
                VERSION=$(cat /etc/sysmedic/version 2>/dev/null || echo dev)
            else
                echo "  The stick is updated from the build PC (sysmedic-deploy --stick)."
            fi
            read -p "  Press Enter..."
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
