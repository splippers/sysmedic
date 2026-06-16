#!/bin/bash
# SysMedic CraicKen Sync — Push session knowledge to the mesh
# Called at end of session to share learnings across all SysMedic instances

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}[CRAICKEN]${NC} $1"; }
ok()    { echo -e "  ${GREEN}[CRAICKEN]${NC} $1"; }
warn()  { echo -e "  ${YELLOW}[CRAICKEN]${NC} $1"; }

CRAICKEN="https://meta.splippers.com"
TOKEN="111JbCV3_BSzwygG0XJ-6kFWDz8v-LHx0rwb8zGv7H8"
REPO="/opt/sysmedic"
CONTEXT_FILE="/tmp/sysmedic-context.json"
WIKI_FILE="$REPO/WIKI.md"

# ──────────────────────────────────────────────
# Ensure network is available
# ──────────────────────────────────────────────

check_network() {
    if ping -c1 -W2 8.8.8.8 &>/dev/null || ping -c1 -W2 meta.splippers.com &>/dev/null; then
        return 0
    fi
    return 1
}

# ──────────────────────────────────────────────
# Push current session to CraicKen context API
# ──────────────────────────────────────────────

push_session_context() {
    info "Ingesting session context to CraicKen..."

    # Build session summary from context file
    local summary=""
    if [ -f "$CONTEXT_FILE" ]; then
        summary=$(python3 -c "
import json
with open('$CONTEXT_FILE') as f:
    d = json.load(f)
sys = d.get('system', {})
cpu = d.get('cpu', {})
mem = d.get('memory', {})
disks = d.get('disks', [])
disk_summary = '; '.join([f'{x[\"device\"]} {x[\"size\"]} {x[\"type\"]} ({x[\"smart\"]})' for x in disks[:3]])
oses = d.get('detected_oses', [])
os_summary = '; '.join([f'{x[\"name\"]} on {x[\"device\"]}' for x in oses])
sb = d.get('secure_boot', {})
print(f'SysMedic session on {sys.get(\"vendor\",\"?\")} {sys.get(\"product\",\"?\")}')
print(f'  CPU: {cpu.get(\"model\",\"?\")[:60]}')
print(f'  RAM: {mem.get(\"total_gb\")} GB')
print(f'  Disks: {disk_summary}')
print(f'  OSes: {os_summary}')
print(f'  Secure Boot: {sb.get(\"mokutil\")}')
" 2>/dev/null)
    fi

    if [ -z "$summary" ]; then
        summary="SysMedic session completed on unknown hardware (no context file)"
    fi

    # Read WIKI.md for latest session log
    local wiki_entry=""
    if [ -f "$WIKI_FILE" ]; then
        wiki_entry=$(grep -A 50 "^## Session 2026" "$WIKI_FILE" 2>/dev/null | head -60)
    fi

    local full_text="=== SysMedic Session Log ($(date -u +%Y-%m-%dT%H:%M:%SZ)) ===

$summary

$wiki_entry"

    # Ingest as ken (structured knowledge)
    local resp=$(curl -s -X POST "$CRAICKEN/api/v1/context/ingest" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "$(python3 -c "
import json
text = '''$full_text'''
print(json.dumps({
    'text': text,
    'source': 'sysmedic',
    'kind': 'ken',
    'tags': 'sysmedic,rescue,session'
}))
")" 2>/dev/null)

    if echo "$resp" | grep -q '"id"'; then
        ok "Session context ingested (ID: $(echo "$resp" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2))"
    else
        warn "Ingest failed: $(echo "$resp" | head -c 200)"
    fi
}

# ──────────────────────────────────────────────
# Update CraicKen wiki article with latest WIKI.md
# ──────────────────────────────────────────────

push_wiki_article() {
    info "Updating CraicKen wiki article..."

    if [ ! -f "$WIKI_FILE" ]; then
        warn "No WIKI.md found — skipping wiki update"
        return
    fi

    local content=$(cat "$WIKI_FILE")
    # Escape for JSON
    local escaped=$(python3 -c "
import json
with open('$WIKI_FILE') as f:
    content = f.read()
# Prepend metadata header
header = '<!-- authored by opencode/big-pickle via SysMedic at $(date -u +%Y-%m-%dT%H:%M:%SZ) -->\n'
print(json.dumps(header + content))
")

    local resp=$(curl -s -X POST "$CRAICKEN/api/v1/wiki/article" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"sysmedic\",\"content\":$escaped}" 2>/dev/null)

    if echo "$resp" | grep -q '"written":true'; then
        ok "CraicKen wiki article updated"
    else
        warn "Wiki update failed: $(echo "$resp" | head -c 200)"
    fi
}

# ──────────────────────────────────────────────
# Git push (if remote available)
# ──────────────────────────────────────────────

git_push() {
    info "Pushing WIKI.md to git origin..."
    cd "$REPO" || return
    if git diff --quiet 2>/dev/null; then
        ok "No local changes to push"
        return
    fi
    git add WIKI.md 2>/dev/null
    git commit -m "CraicWiki update: $(date -u +%Y-%m-%d)" 2>/dev/null
    if git push origin master 2>/dev/null; then
        ok "Changes pushed to git origin"
    else
        warn "Git push failed (check credentials)"
    fi
}

# ──────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────

main() {
    echo ""
    echo -e "${BOLD}  ╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}  ║   📡  CraicKen Sync                  ║${NC}"
    echo -e "${BOLD}  ║   Pushing session knowledge to mesh  ║${NC}"
    echo -e "${BOLD}  ╚══════════════════════════════════════╝${NC}"
    echo ""

    if ! check_network; then
        warn "No network — skipping CraicKen sync (knowledge cached locally)"
        info "Run 'craic-connect.sh' later when network is available"
        return 1
    fi

    push_session_context
    push_wiki_article
    git_push

    echo ""
    ok "CraicKen sync complete — fleet is now wiser"
}

main "$@"
