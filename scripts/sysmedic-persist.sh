#!/bin/bash
# SysMedic Persistence — save/restore session data on the boot device
# All data lives under /root/sysmedic/ (215G free on boot drive)
# Called from preflight.sh and menu.sh for cross-boot persistence

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}[PERSIST]${NC} $1"; }
ok()    { echo -e "  ${GREEN}[PERSIST]${NC} $1"; }
warn()  { echo -e "  ${YELLOW}[PERSIST]${NC} $1"; }
fail()  { echo -e "  ${RED}[PERSIST]${NC} $1"; }

PERSIST_DIR="/root/sysmedic"
PERSIST_SESSION="${PERSIST_DIR}/session"
PERSIST_REPORTS="${PERSIST_DIR}/reports"
PERSIST_CAPTURES="${PERSIST_DIR}/captures"
PERSIST_SCRIPTS="${PERSIST_DIR}/scripts"
PERSIST_UPDATES="${PERSIST_DIR}/updates"
CONTEXT_FILE="/tmp/sysmedic-context.json"

# ──────────────────────────────────────────────
# Ensure persistence directory structure exists
# ──────────────────────────────────────────────
ensure_structure() {
    mkdir -p "$PERSIST_SESSION" 2>/dev/null
    mkdir -p "$PERSIST_REPORTS" 2>/dev/null
    mkdir -p "$PERSIST_CAPTURES" 2>/dev/null
    mkdir -p "$PERSIST_SCRIPTS" 2>/dev/null
    mkdir -p "$PERSIST_UPDATES" 2>/dev/null

    # Link /root/reports → persistent reports
    if [ -L /root/reports ]; then
        # Fix broken symlink from old SanDisk era
        local target=$(readlink /root/reports)
        if [ "$target" != "$PERSIST_REPORTS" ]; then
            rm -f /root/reports
            ln -sf "$PERSIST_REPORTS" /root/reports
        fi
    elif [ -d /root/reports ]; then
        # Move existing reports to persistent storage
        cp -r /root/reports/* "$PERSIST_REPORTS"/ 2>/dev/null
        rm -rf /root/reports
        ln -sf "$PERSIST_REPORTS" /root/reports
    else
        ln -sf "$PERSIST_REPORTS" /root/reports
    fi
}

# ──────────────────────────────────────────────
# Save session data
# ──────────────────────────────────────────────
save_session() {
    local label="${1:-manual}"

    ensure_structure

    # Save context file if exists
    if [ -f "$CONTEXT_FILE" ]; then
        cp "$CONTEXT_FILE" "${PERSIST_SESSION}/last-context.json" 2>/dev/null
    fi

    # Save WIKI.md
    if [ -f /opt/sysmedic/WIKI.md ]; then
        cp /opt/sysmedic/WIKI.md "${PERSIST_SESSION}/WIKI.md" 2>/dev/null
    fi

    # Save ROADMAP.md
    if [ -f /opt/sysmedic/ROADMAP.md ]; then
        cp /opt/sysmedic/ROADMAP.md "${PERSIST_SESSION}/ROADMAP.md" 2>/dev/null
    fi

    # Write session log entry
    local now=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    local host_info=""
    if [ -f "$CONTEXT_FILE" ]; then
        host_info=$(python3 -c "
import json
with open('$CONTEXT_FILE') as f:
    d = json.load(f)
sys = d.get('system', {})
cpu = d.get('cpu', {})
mem = d.get('memory', {})
print(f'{sys.get(\"vendor\",\"?\")} {sys.get(\"product\",\"?\")} / {cpu.get(\"model\",\"?\")[:40]} / {mem.get(\"total_gb\")}GB')
" 2>/dev/null)
    fi

    echo "[${now}] ${label} — ${host_info:-unknown hardware}" >> "${PERSIST_SESSION}/sessions.log"
    ok "Session saved (${label})"
}

# ──────────────────────────────────────────────
# Show persistence status
# ──────────────────────────────────────────────
show_status() {
    ensure_structure
    echo ""
    ok "Persistence directory at ${PERSIST_DIR}"
    echo "  Free on boot device: $(df -h / 2>/dev/null | tail -1 | awk '{print $4}')"
    echo "  Persistence used:    $(du -sh "$PERSIST_DIR" 2>/dev/null | awk '{print $1}')"
    echo ""
    echo "  Session log entries: $(wc -l < "${PERSIST_SESSION}/sessions.log" 2>/dev/null || echo 0)"
    echo "  Reports: $(find "$PERSIST_REPORTS" -type f 2>/dev/null | wc -l)"
    echo "  Captures: $(ls -d "$PERSIST_CAPTURES"/*/ 2>/dev/null | wc -l)"
    echo "  Last session: $(tail -1 "${PERSIST_SESSION}/sessions.log" 2>/dev/null | cut -d' ' -f1-3)"
    echo ""
}

# ──────────────────────────────────────────────
# Load previous session context (if any)
# ──────────────────────────────────────────────
load_previous_session() {
    if [ -f "${PERSIST_SESSION}/last-context.json" ]; then
        echo ""
        python3 -c "
import json
with open('${PERSIST_SESSION}/last-context.json') as f:
    d = json.load(f)
sys = d.get('system', {})
cpu = d.get('cpu', {})
mem = d.get('memory', {})
print(f'  Previous session hardware:')
print(f'    {sys.get(\"vendor\",\"?\")} {sys.get(\"product\",\"?\")}')
print(f'    {cpu.get(\"model\",\"?\")[:60]}')
print(f'    {mem.get(\"total_gb\")} GB RAM')
for os_item in d.get('detected_oses', []):
    print(f'    OS: {os_item.get(\"name\")} on {os_item.get(\"device\")}')
" 2>/dev/null
        echo ""
        info "Previous session context loaded (${PERSIST_SESSION}/last-context.json)"
        return 0
    fi
    warn "No previous session found"
    return 1
}

# ──────────────────────────────────────────────
# Main entry point
# ──────────────────────────────────────────────
main() {
    case "${1:-status}" in
        mount|setup)
            ensure_structure
            save_session "boot"
            load_previous_session
            ;;
        save)
            save_session "${2:-manual}"
            ;;
        status)
            show_status
            ;;
        prev|previous)
            ensure_structure
            load_previous_session
            ;;
        *)
            echo "Usage: sysmedic-persist.sh {setup|save|status|prev}"
            echo ""
            echo "  setup    — Ensure structure + save boot session"
            echo "  save     — Save current session state"
            echo "  status   — Show persistence status"
            echo "  prev     — Show previous session info"
            ;;
    esac
}

main "$@"
