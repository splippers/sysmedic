# ~/.profile: executed by Bourne-compatible login shells.

if [ "$BASH" ]; then
  if [ -f ~/.bashrc ]; then
    . ~/.bashrc
  fi
fi

mesg n 2> /dev/null || true

# Session transcript: record consoles 1 and 2 to the SysMedic drive. Output only:
# keystrokes are not logged, so hidden entries (BitLocker keys, passwords) are never captured.
if [ -t 0 ] && [ -z "$SYSMEDIC_TTY" ] && command -v script >/dev/null; then
    case "$(tty)" in /dev/tty1|/dev/tty2)
        export SYSMEDIC_TTY=$(tty)
        mountpoint -q /mnt/persist || /usr/local/sbin/mount-persist >/dev/null 2>&1 || true
        if mountpoint -q /mnt/persist; then tdir=/mnt/persist/transcripts; else tdir=/run/sysmedic/transcripts; fi
        mkdir -p "$tdir"
        export SYSMEDIC_TRANSCRIPT="$tdir/$(date +%Y%m%d-%H%M%S)-${SYSMEDIC_TTY#/dev/}.log"
        exec script -q -f -e --log-out "$SYSMEDIC_TRANSCRIPT" -c "bash -l"
        ;;
    esac
fi
console=${SYSMEDIC_TTY:-$(tty)}
[ -r /usr/local/lib/sysmedic/ui.sh ] && . /usr/local/lib/sysmedic/ui.sh
_cmd() { printf '  %s%-28s%s %s%s%s\n' "${_U_ACC:-}" "$1" "${_U_N:-}" "${_U_D:-}" "$2" "${_U_N:-}"; }

# SysMedic auto-launch — console 1 runs the rescue flow, console 2 is the engineer's shell
if [ -t 0 ] && [ "$console" = /dev/tty2 ]; then
    echo ''
    ui_banner "Engineer console" "Alt+F1 returns to the assistant · this console is recorded for review (output, not keystrokes)"
    ui_section "Commands"
    _cmd 'menu' 'the rescue menu (tests, Windows tools, reports, update…)'
    _cmd 'sysmedic-guard status' 'which disks are write-protected'
    _cmd 'sysmedic-unlock /dev/X' 'allow writes to one partition (backs it up first)'
    _cmd 'sysmedic-lock' 'protect everything again'
    _cmd 'sysmedic-note "text"' 'add a note to the job report (sysmedic-report builds it)'
    _cmd 'sysmedic-note --feedback "…"' 'something SysMedic should do better (for the review)'
    _cmd 'sysmedic-help' 'the guides: field guide, BitLocker, hardware tests…'
    bl=$(lsblk -lnpo NAME,FSTYPE 2>/dev/null | awk '$2=="BitLocker"{print $1}')
    ui_section "BitLocker"
    if [ -n "$bl" ]; then
        for d in $bl; do _cmd "sysmedic-win bitlocker $d" "$(lsblk -dno SIZE "$d" | xargs) $(lsblk -dno PARTLABEL "$d" | xargs) · type this line to unlock (read-only)"; done
    else
        ui_info "No BitLocker volumes on this machine" "syntax: sysmedic-win bitlocker /dev/<partition>"
    fi
    ui_info "Recovery key: 48 digits (8 groups of 6), typed into a hidden prompt: never shown, stored or logged" \
            "From aka.ms/myrecoverykey or the owner's IT admin. Repairs: sysmedic-unlock the partition, then add --rw."
    ui_info "Key with someone else? The phone dashboard's BitLocker card (or sysmedic-win bitlocker-web)" \
            "they type it on their own phone or laptop on the same network: secure link, read-only, stops by itself"
    echo ''
    /usr/local/bin/sysmedic-dash
    echo ''
elif [ -t 0 ] && [ "$console" = /dev/tty1 ] && [ -z "$AMBULANCE_LAUNCHED" ]; then
    export AMBULANCE_LAUNCHED=1
    # Every boot is a new job: no AI history from the previous customer carries over
    rm -rf /root/.local/share/opencode/storage /root/.local/share/opencode/snapshot /root/.local/share/opencode/log \
           /root/.local/share/opencode/opencode.db* /root/.local/share/opencode/tool-output 2>/dev/null

    # Quick network attempt — don't block (splash already tried; this ensures it's up)
    command -v netplan &>/dev/null && { netplan apply 2>/dev/null || true; }
    clear
    setvtrgb /etc/sysmedic/vtrgb 2>/dev/null; clear

    /usr/local/sbin/mount-persist || true
    /usr/local/sbin/start-ollama && ui_ok "Offline AI ready" "$(/usr/local/sbin/sysmedic-ai-device status 2>/dev/null | sed 's/^ *//')"
    echo ''

    # Read-only triage first: the engineer (and the AI) start from facts
    # Check if splash transition already ran the scan
    if [ -f /run/sysmedic/latest/summary.txt ] && [ -f /run/sysmedic/latest/scan.json ]; then
        cat /run/sysmedic/latest/summary.txt
    else
        /usr/local/bin/sysmedic-scan
    fi

    # Phone dashboard (view + job notes); the QR code is on console 2
    setsid -f /usr/local/bin/sysmedic-dash --serve >/dev/null 2>&1 </dev/null
    ip4=$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -1)
    ui_section "Next"
    [ -n "$ip4" ] && ui_info "Phone dashboard: http://$ip4:8080" "scan the QR code on Alt+F2: tests, notes, BitLocker unlock"
    ui_info "Disks are write-protected" "to repair, unlock one partition on Alt+F2 (sysmedic-unlock)"

    audit() { . /etc/sysmedic/audit.sh; printf '%s [tty1] %s\n' "$(date -Is)" "$*" >> "$(_sysmedic_audit_file)"; }
    mem_gb=$(( ($(awk '/MemTotal/ {print $2}' /proc/meminfo) + 524288) / 1048576 ))   # rounded GB
    online=$(python3 -c 'import json; print(int(json.load(open("/run/sysmedic/latest/scan.json"))["network"]["online"]))' 2>/dev/null)
    mode=offline
    if [ "$online" = 1 ] && [ "$mem_gb" -ge 4 ] && grep -qw avx /proc/cpuinfo; then
        ui_info "Cloud AI available (OpenCode Zen, free)" "it sees this scan and command output; serial numbers are kept out; files are read only with your approval"
        read -r -t 60 -p "  ${_U_ACC:-}❯${_U_N:-} Does the customer consent to cloud AI? [y/N] " consent || true
        if [ "$consent" = y ] || [ "$consent" = Y ]; then
            mode=cloud; audit "CONSENT cloud AI: yes"
        else
            audit "CONSENT cloud AI: no — using offline assistant"
        fi
    fi

    if [ "$mode" = offline ] && [ "$mem_gb" -lt 6 ]; then
        ui_warn "The offline assistant needs 6 GB RAM; this machine has ${mem_gb} GB" "opening the rescue menu"
        sleep 4
        exec /usr/local/bin/ambulance
    fi
    [ "$mode" = offline ] && { setsid -f /usr/local/bin/sysmedic-ask --warm >/dev/null 2>&1 </dev/null; }

    echo ''
    read -r -t 60 -p "  ${_U_ACC:-}❯${_U_N:-} Enter: start the $mode assistant · m: rescue menu  " choice || true
    [ "$choice" = m ] && exec /usr/local/bin/ambulance
    echo ''

    # The AI runs in a shared session (tmux ai-cloud / ai-offline): the remote AI web terminal attaches to the same
    # one, so the phone and this screen see one conversation
    tmux -f /etc/sysmedic/tmux.conf new-session -A -s "ai-$mode" "/usr/local/bin/sysmedic-ai-session $mode --explain"
    echo ''
    if [ "$mode" = cloud ]; then
        echo 'OpenCode closed. Type "menu" for the rescue menu, or "sysmedic-ask" for the offline assistant.'
    else
        echo 'Assistant closed. Type "menu" for the rescue menu, or "sysmedic-ask" to restart it.'
    fi
    exec bash
fi
