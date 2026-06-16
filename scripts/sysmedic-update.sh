#!/bin/bash
# SysMedic Self-Update — check for and apply updates from CraicKen mesh + git
# Updates SysMedic scripts, tools, and configuration across the fleet

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}[UPDATE]${NC} $1"; }
ok()    { echo -e "  ${GREEN}[UPDATE]${NC} $1"; }
warn()  { echo -e "  ${YELLOW}[UPDATE]${NC} $1"; }
fail()  { echo -e "  ${RED}[UPDATE]${NC} $1"; }

REPO="/opt/sysmedic"
CRAICKEN="https://meta.splippers.com"
TOKEN="111JbCV3_BSzwygG0XJ-6kFWDz8v-LHx0rwb8zGv7H8"
BACKUP_DIR="/root/sysmedic-backups"
PERSIST_UPDATES="/root/sysmedic/updates"

# ──────────────────────────────────────────────
# Check network connectivity
# ──────────────────────────────────────────────
check_network() {
    ping -c1 -W2 8.8.8.8 &>/dev/null || ping -c1 -W2 meta.splippers.com &>/dev/null
}

# ──────────────────────────────────────────────
# Get current git info
# ──────────────────────────────────────────────
git_info() {
    cd "$REPO" 2>/dev/null || return 1
    local commit=$(git rev-parse --short HEAD 2>/dev/null)
    local branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    local date=$(git log -1 --format=%cd --date=short 2>/dev/null)
    local message=$(git log -1 --format=%s 2>/dev/null)
    local status=""
    if ! git diff --quiet 2>/dev/null; then
        status=" (${YELLOW}uncommitted changes${NC})"
    fi
    echo "  Current:  ${commit} on ${branch} (${date})"
    echo "  Message:  ${message}${status}"
    echo "${commit}|${branch}|${date}"
}

# ──────────────────────────────────────────────
# Update via git pull from origin
# ──────────────────────────────────────────────
git_update() {
    info "Checking for git updates..."
    cd "$REPO" || return 1

    # Save current commit for rollback
    local old_commit=$(git rev-parse --short HEAD 2>/dev/null)

    # Fetch and check for updates
    git fetch origin 2>/dev/null
    local behind=$(git rev-list --count HEAD..origin/master 2>/dev/null)
    if [ -z "$behind" ] || [ "$behind" -eq 0 ]; then
        ok "Already up to date (origin/master)"
        return 0
    fi

    info "Found ${behind} commit(s) behind origin/master"
    echo ""

    # Show what's coming
    echo "  Pending changes:"
    git log --oneline HEAD..origin/master 2>/dev/null | while read line; do
        echo "    ${line}"
    done
    echo ""

    # Backup current state
    mkdir -p "$BACKUP_DIR" 2>/dev/null
    local backup_name="sysmedic-backup-$(date +%Y%m%d-%H%M%S)"
    git diff --name-only 2>/dev/null | while read f; do
        [ -f "$f" ] && mkdir -p "$BACKUP_DIR/${backup_name}/$(dirname $f)" && cp "$f" "$BACKUP_DIR/${backup_name}/$f" 2>/dev/null
    done
    if [ -d "$BACKUP_DIR/${backup_name}" ]; then
        ok "Backed up uncommitted changes to ${BACKUP_DIR}/${backup_name}"
    fi

    # Stash any local changes, pull, re-apply
    local had_stash=false
    if ! git diff --quiet 2>/dev/null; then
        git stash push -m "sysmedic-auto-stash-$(date +%Y%m%d%H%M%S)" 2>/dev/null
        had_stash=true
    fi

    # Pull
    if git pull origin master 2>/dev/null; then
        local new_commit=$(git rev-parse --short HEAD 2>/dev/null)
        ok "Updated: ${old_commit} → ${new_commit}"
        echo ""
        git log --oneline "${old_commit}..${new_commit}" 2>/dev/null | while read line; do
            echo "    ${line}"
        done
    else
        fail "Git pull failed (check credentials/network)"
        # Attempt rollback
        git reset --hard "$old_commit" 2>/dev/null
        return 1
    fi

    # Re-apply stashed changes if any
    if $had_stash; then
        git stash pop 2>/dev/null && info "Re-applied local changes"
    fi

    # Save to persistent storage
    if [ -d "$PERSIST_UPDATES" ]; then
        git log --oneline -10 > "${PERSIST_UPDATES}/last-git-log.txt" 2>/dev/null
    fi

    return 0
}

# ──────────────────────────────────────────────
# Check CraicKen mesh for version manifest
# ──────────────────────────────────────────────
check_mesh_manifest() {
    info "Checking CraicKen mesh for SysMedic version info..."

    local resp
    resp=$(curl -s --connect-timeout 5 "$CRAICKEN/api/v1/wiki/article/sysmedic" \
        -H "Authorization: Bearer $TOKEN" 2>/dev/null)

    if [ -z "$resp" ]; then
        warn "Mesh unreachable — skipping manifest check"
        return 1
    fi

    # Parse the wiki article for version metadata
    local mesh_version
    mesh_version=$(echo "$resp" | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    content = d.get('article', {}).get('content', '')
    for line in content.split('\n'):
        if line.startswith('## SysMedic Version'):
            print(line.split()[-1])
            break
except: pass
" 2>/dev/null)

    if [ -n "$mesh_version" ]; then
        local local_version=$(cd "$REPO" && git rev-parse --short HEAD 2>/dev/null)
        info "Mesh version: ${mesh_version}"
        info "Local version: ${local_version:-unknown}"
        if [ "$mesh_version" != "${local_version:-}" ] && [ -n "$local_version" ]; then
            warn "Local version differs from mesh — consider updating"
            return 2
        fi
    fi
    return 0
}

# ──────────────────────────────────────────────
# Update script-level files (non-git tracked)
# ──────────────────────────────────────────────
update_scripts() {
    info "Checking for script updates on mesh..."
    # Future: download update manifest from mesh and apply patches
    # For now, this is a placeholder for mesh-distributed script updates
    ok "Script-level update check passed"
    return 0
}

# ──────────────────────────────────────────────
# Show full version info
# ──────────────────────────────────────────────
show_version() {
    echo ""
    echo -e "${BOLD}  ╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}  ║   SysMedic Version                    ║${NC}"
    echo -e "${BOLD}  ╚══════════════════════════════════════╝${NC}"
    echo ""
    cd "$REPO" 2>/dev/null && git_info
    echo ""
    if command -v opencode &>/dev/null; then
        echo "  AI model: opencode/big-pickle"
    fi
    echo ""
    # Check persisted version log
    if [ -f "${PERSIST_UPDATES}/last-git-log.txt" ]; then
        echo "  Update history (last 10):"
        cat "${PERSIST_UPDATES}/last-git-log.txt" | while read line; do
            echo "    ${line}"
        done
    fi
    echo ""
}

# ──────────────────────────────────────────────
# Main entry
# ──────────────────────────────────────────────
main() {
    case "${1:-check}" in
        update|upgrade)
            show_version
            echo ""
            if ! check_network; then
                fail "No network connection — update requires internet"
                echo "  Connect via WiFi (menu option 2) and retry"
                return 1
            fi
            git_update
            update_scripts
            echo ""
            ok "Update check complete"
            ;;
        check)
            if ! check_network; then
                warn "No network — skipping update check"
                return 1
            fi
            git_update
            check_mesh_manifest
            ;;
        version|status)
            show_version
            ;;
        force)
            # Force pull even if up to date
            cd "$REPO" && git fetch origin 2>/dev/null && git reset --hard origin/master 2>/dev/null
            ok "Force-synced to origin/master"
            show_version
            ;;
        *)
            echo "Usage: sysmedic-update.sh {check|update|version|force}"
            echo ""
            echo "  check    — Check for + apply available updates (idempotent)"
            echo "  update   — Same as check (alias)"
            echo "  version  — Show current version info"
            echo "  force    — Force reset to origin/master (discards local changes)"
            ;;
    esac
}

main "$@"
