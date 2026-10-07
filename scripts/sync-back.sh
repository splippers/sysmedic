#!/usr/bin/env bash
# SysMedic - Session Sync-Back
# Collects repair session artifacts and saves them to the persistence partition.
# Run this on the booted USB after completing repairs.
#
# Usage: sync-back.sh [session-name]
#   If no session name is given, one is generated from date + target hostname.

set -uo pipefail

VERSION="0.1.0"
PERSIST_MOUNT="/mnt/persist"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

info()  { echo -e "  ${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC}   $1"; }
fail()  { echo -e "  ${RED}[FAIL]${NC}   $1"; }

##############################################################################

check_persist() {
    if [ ! -d "$PERSIST_MOUNT" ] || ! mountpoint -q "$PERSIST_MOUNT" 2>/dev/null; then
        # Try to mount
        /usr/local/sbin/mount-persist 2>/dev/null || true
    fi

    if ! mountpoint -q "$PERSIST_MOUNT" 2>/dev/null; then
        fail "Persistence partition not available"
        echo ""
        echo "  Make sure the USB was written with --write (creates SYSMEDIC_PERSIST partition)"
        echo "  Or mount it manually:"
        echo "    mount /dev/sdX2 /mnt/persist   # (use the correct device)"
        return 1
    fi
    return 0
}

collect_logs() {
    local session_dir="$1"
    local log_dir="${session_dir}/logs"

    mkdir -p "$log_dir"
    info "Collecting logs..."

    # System logs from the live session
    for log in /var/log/syslog /var/log/kern.log /var/log/boot.log /var/log/dmesg; do
        if [ -f "$log" ]; then
            cp "$log" "$log_dir/" 2>/dev/null && ok "  $(basename $log) saved"
        fi
    done

    # dmesg output
    dmesg > "$log_dir/dmesg.txt" 2>/dev/null && ok "  dmesg saved"

    # Repair script logs (if any were created in /tmp)
    for log in /tmp/sysmedic-*.log; do
        [ -f "$log" ] && cp "$log" "$log_dir/" && ok "  $(basename $log) saved"
    done

    # Journalctl for the current boot (if systemd)
    if command -v journalctl &>/dev/null; then
        journalctl --this-boot --no-pager -p err 2>/dev/null > "$log_dir/journal-errors.txt" && ok "  journal errors saved"
    fi
}

collect_custom_scripts() {
    local session_dir="$1"
    local custom_dir="${session_dir}/custom-scripts"

    mkdir -p "$custom_dir"

    # Any custom scripts the user created in /opt/sysmedic/custom/
    local source_custom="/opt/sysmedic/custom"
    if [ -d "$source_custom" ] && [ "$(ls -A "$source_custom" 2>/dev/null)" ]; then
        cp -a "$source_custom/"* "$custom_dir/" 2>/dev/null
        local count
        count=$(ls -A "$custom_dir" 2>/dev/null | wc -l)
        ok "  $count custom script(s) saved"
    else
        info "  No custom scripts found"
    fi
}

collect_target_info() {
    local session_dir="$1"

    info "Collecting target machine info..."

    # Detect if any target partitions are mounted
    # Look for mounted non-live partitions
    local target_info="${session_dir}/target-info.txt"
    {
        echo "=== SysMedic Session Report ==="
        echo "Date:       $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "Host:       $(hostname 2>/dev/null || echo 'unknown')"
        echo "Kernel:     $(uname -a 2>/dev/null || echo 'unknown')"
        echo ""
        echo "=== Target Machine ==="
        echo ""
        echo "=== Block Devices ==="
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL 2>/dev/null | grep -v loop
        echo ""
        echo "=== Mounted Filesystems ==="
        mount | grep -v "tmpfs\|devtmpfs\|squashfs\|overlay"
        echo ""
        echo "=== Repairs Performed ==="
        # Collect from repair logs
        for logfile in "$session_dir"/logs/*.log /tmp/sysmedic-*.log; do
            [ -f "$logfile" ] && echo "--- $(basename $logfile) ---" && cat "$logfile" 2>/dev/null
        done
    } > "$target_info"
    ok "  Target info saved"
}

collect_repair_results() {
    local session_dir="$1"
    local results_dir="${session_dir}/results"

    mkdir -p "$results_dir"

    # Collect fstab backups
    for bk in /tmp/fstab-* /tmp/fstab.bak*; do
        [ -f "$bk" ] && cp "$bk" "$results_dir/" && info "  fstab backup saved"
    done

    # Collect partition table backups
    for bk in /tmp/sfdisk-*.log /tmp/part-*.bak; do
        [ -f "$bk" ] && cp "$bk" "$results_dir/" && info "  Part table backup saved"
    done

    # Collect GRUB configs from target if mounted
    for target in /mnt/target-*/boot/grub/grub.cfg; do
        [ -f "$target" ] && cp "$target" "$results_dir/grub.cfg-$(basename $(dirname $(dirname $(dirname $target))))"
    done
}

##############################################################################

main() {
    echo ""
    echo -e "${CYAN}${BOLD}══════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  SysMedic Session Sync-Back${NC}"
    echo -e "${CYAN}${BOLD}══════════════════════════════════════${NC}"
    echo ""

    # Check persistence
    check_persist || exit 1

    # Determine session name
    local session_name="${1:-}" session_dir
    # Save into this visit's session (the one sysmedic-scan started), not a separate folder
    if [ -z "$session_name" ] && [ -d "$(readlink -f /run/sysmedic/latest 2>/dev/null)" ]; then
        session_dir=$(readlink -f /run/sysmedic/latest)
        session_name=$(basename "$session_dir")
    fi
    if [ -z "$session_name" ]; then
        local host
        host=$(hostname -s 2>/dev/null || echo "unknown")
        session_name="session-$(date +%Y%m%d-%H%M%S)-${host}"
    fi
    session_dir="${session_dir:-${PERSIST_MOUNT}/sessions/${session_name}}"
    mkdir -p "$session_dir"

    info "Session: $session_name"
    info "Output:  $session_dir"
    echo ""

    # Collect all artifacts
    collect_logs "$session_dir"
    collect_custom_scripts "$session_dir"
    collect_target_info "$session_dir"
    collect_repair_results "$session_dir"

    # Create summary
    echo ""
    local total_size
    total_size=$(du -sh "$session_dir" 2>/dev/null | awk '{print $1}')
    local file_count
    file_count=$(find "$session_dir" -type f 2>/dev/null | wc -l)

    ok "Session saved to persistence:"
    echo "    Path:   $session_dir"
    echo "    Files:  $file_count"
    echo "    Size:   $total_size"
    echo ""
    echo -e "${BOLD}To import this session into the repo on your build machine:${NC}"
    echo ""
    echo "  1. Mount the USB's persistence partition:"
    echo "     mount LABEL=SYSMEDIC_PERSIST /mnt"
    echo ""
    echo "  2. Run the import tool:"
    echo "     ./tools/import-session.sh /mnt/sessions/${session_name}"
    echo ""
    echo -e "${YELLOW}Session logs and custom scripts are now on the persistence partition.${NC}"
    echo -e "${YELLOW}They will survive USB unmount and can be fed back into the repo.${NC}"
    echo ""
}

main "$@"
