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

# SysMedic auto-launch — console 1 runs the rescue flow, console 2 is the engineer's shell
if [ -t 0 ] && [ "$console" = /dev/tty2 ]; then
    echo ''
    echo '  === SysMedic engineer console ==='
    echo '  sysmedic-guard status      which disks are write-protected'
    echo '  sysmedic-unlock /dev/X     allow writes to one partition (backs it up first)'
    echo '  sysmedic-lock              protect everything again'
    echo '  sysmedic-note "text"       add a note to the job report · sysmedic-report builds it'
    echo '  sysmedic-note --feedback "…"  note something SysMedic should do better (goes to claude-review.md)'
    echo '  sysmedic-help              the SysMedic guides (field guide, BitLocker, hardware tests, ...)'
    echo '  This session is being recorded for later review (output only, not keystrokes).'
    echo '  Alt+F1 returns to the assistant.'
    echo ''
    bl=$(lsblk -lnpo NAME,FSTYPE 2>/dev/null | awk '$2=="BitLocker"{print $1}')
    echo '  --- BitLocker ---'
    if [ -n "$bl" ]; then
        echo '  Encrypted volumes on this machine (type the line for the one you need):'
        for d in $bl; do echo "    sysmedic-win bitlocker $d      ($(lsblk -dno SIZE "$d" | xargs), $(lsblk -dno PARTLABEL "$d" | xargs))"; done
    else
        echo '  No BitLocker volumes detected. Syntax: sysmedic-win bitlocker /dev/<partition>'
    fi
    echo '  Recovery key: 48 digits in 8 groups of 6, e.g. 123456-234567-345678-456789-567890-678901-789012-890123'
    echo '  (dashes and spaces optional). It goes into a hidden prompt: never shown, stored, logged or recorded.'
    echo '  The owner finds it at aka.ms/myrecoverykey (Microsoft account) or from their IT admin. Opens read-only;'
    echo '  for repairs: sysmedic-unlock the partition first, then add --rw.'
    echo '  Key with someone else (customer, IT admin)? sysmedic-win bitlocker-web lets them type it on their'
    echo '  phone or laptop on the same network (secure link + QR code; read-only; stops by itself).'
    /usr/local/bin/sysmedic-dash
    echo ''
elif [ -t 0 ] && [ "$console" = /dev/tty1 ] && [ -z "$AMBULANCE_LAUNCHED" ]; then
    export AMBULANCE_LAUNCHED=1
    # Every boot is a new job: no AI history from the previous customer carries over
    rm -rf /root/.local/share/opencode/storage /root/.local/share/opencode/snapshot /root/.local/share/opencode/log \
           /root/.local/share/opencode/opencode.db* /root/.local/share/opencode/tool-output 2>/dev/null

    # Quick network attempt — don't block
    command -v netplan &>/dev/null && { netplan apply 2>/dev/null || true; }
    # First screen: get online (wired is automatic; offers Wi-Fi), so the scan and cloud AI see the internet
    /usr/local/bin/sysmedic-connect
    clear
    echo ''
    echo "  === SysMedic Recovery System · $(cat /etc/sysmedic/edition 2>/dev/null || echo dev) edition · v$(cat /etc/sysmedic/version 2>/dev/null || echo dev) ==="
    echo "  Network: $(/usr/local/bin/sysmedic-connect --status)"
    echo ''

    /usr/local/sbin/mount-persist || true
    /usr/local/sbin/start-ollama && echo '  Offline AI (Ollama) ready'

    # Read-only triage first: the engineer (and the AI) start from facts
    /usr/local/bin/sysmedic-scan
    echo ''

    # Phone dashboard (view + job notes); the QR code is on console 2
    setsid -f /usr/local/bin/sysmedic-dash --serve >/dev/null 2>&1 </dev/null
    ip4=$(ip -4 -o addr show scope global | awk '{print $4}' | cut -d/ -f1 | head -1)
    [ -n "$ip4" ] && echo "  Phone dashboard: http://$ip4:8080  (scan the QR code on Alt+F2)"

    audit() { . /etc/sysmedic/audit.sh; printf '%s [tty1] %s\n' "$(date -Is)" "$*" >> "$(_sysmedic_audit_file)"; }
    mem_gb=$(( ($(awk '/MemTotal/ {print $2}' /proc/meminfo) + 524288) / 1048576 ))   # rounded GB
    online=$(python3 -c 'import json; print(int(json.load(open("/run/sysmedic/latest/scan.json"))["network"]["online"]))' 2>/dev/null)
    mode=offline
    if [ "$online" = 1 ] && [ "$mem_gb" -ge 4 ] && grep -qw avx /proc/cpuinfo; then
        echo '  Cloud AI available (OpenCode Zen, free). It will see this scan and command output'
        echo '  from this machine; serial numbers are kept out. Files are only read with your approval.'
        read -r -t 60 -p '  Does the customer consent to cloud AI? [y/N] ' consent || true
        if [ "$consent" = y ] || [ "$consent" = Y ]; then
            mode=cloud; audit "CONSENT cloud AI: yes"
        else
            audit "CONSENT cloud AI: no — using offline assistant"
        fi
    fi

    if [ "$mode" = offline ] && [ "$mem_gb" -lt 6 ]; then
        echo "  The offline assistant needs 6 GB RAM — this machine has ${mem_gb} GB. Opening the rescue menu."
        sleep 4
        exec /usr/local/bin/ambulance
    fi
    [ "$mode" = offline ] && { setsid -f /usr/local/bin/sysmedic-ask --warm >/dev/null 2>&1 </dev/null; }

    echo ''
    echo '  Disks are write-protected. To repair, unlock a partition on console 2 (Alt+F2).'
    read -r -t 60 -p "  Press Enter to start the $mode assistant, or type m for the rescue menu: " choice || true
    [ "$choice" = m ] && exec /usr/local/bin/ambulance
    echo ''

    if [ "$mode" = cloud ]; then
        t0=$(date +%s)
        SYSMEDIC_AI=opencode BASH_ENV=/etc/sysmedic/audit.sh opencode --model opencode/big-pickle \
            --prompt 'Read /run/sysmedic/latest/summary.txt (the triage scan of this machine). Explain the findings in plain English, most urgent first, and propose a repair plan. Do not change anything yet.'
        rc=$?
        if [ "$rc" != 0 ] && [ $(( $(date +%s) - t0 )) -lt 30 ]; then
            echo ''
            echo "  OpenCode stopped straight away (exit $rc). Repair it: sysmedic-ai-repair (menu 17), then type: opencode"
        fi
        # Keep the cloud AI conversation with this visit (for the transcript bundle)
        sd=$(readlink -f /run/sysmedic/latest 2>/dev/null)
        [ -d "$sd" ] && [ -d /root/.local/share/opencode/storage ] && mkdir -p "$sd/ai" && \
            cp -a /root/.local/share/opencode/storage "$sd/ai/opencode-$(date +%H%M%S)" 2>/dev/null
        echo ''
        echo 'OpenCode closed. Type "menu" for the rescue menu, or "sysmedic-ask" for the offline assistant.'
    else
        /usr/local/bin/sysmedic-ask --explain
        echo ''
        echo 'Assistant closed. Type "menu" for the rescue menu, or "sysmedic-ask" to restart it.'
    fi
    exec bash
fi
