#!/bin/bash
# SysMedic CraicKen Telemetry
# Registers on CraicKen, collects diagnostics, pipes data home

CRAICKEN="https://meta.splippers.com"
AGENT_NAME="sysmedic"
CRAIC_KINDS=("craic" "ken")
BEARER=""
PERSIST_DIR="/mnt/persist"
LOG_FILE="${PERSIST_DIR}/logs/craic-connect.log"

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}[CRAIC]${NC} $1"; }
ok()    { echo -e "  ${GREEN}[CRAIC]${NC} $1"; }
warn()  { echo -e "  ${YELLOW}[CRAIC]${NC} $1"; }
fail()  { echo -e "  ${RED}[CRAIC]${NC} $1"; }

log() { echo "[$(date +%H:%M:%S)] $*" >> "$LOG_FILE" 2>/dev/null || true; }

# --- Network readiness ---
wait_for_network() {
    local tries=0
    while [ $tries -lt 30 ]; do
        if ping -c1 -W2 8.8.8.8 &>/dev/null || ping -c1 -W2 192.168.1.75 &>/dev/null; then
            return 0
        fi
        sleep 2
        tries=$((tries+1))
    done
    return 1
}

# --- CraicKen API helpers ---
craic_api() {
    local method="$1" path="$2" data="$3"
    local url="${CRAICKEN}${path}"
    local args=(-s -X "$method" -H "Content-Type: application/json")
    [ -n "$BEARER" ] && args+=(-H "Authorization: Bearer $BEARER")
    [ -n "$data" ] && args+=(-d "$data")
    curl "${args[@]}" "$url" 2>/dev/null
}

register_agent() {
    info "Registering on CraicKen as '${AGENT_NAME}'..."
    local resp=$(craic_api POST /api/v1/net/register '{
        "name": "sysmedic",
        "nickname": "SysMedic Rescue",
        "hostname": "sysmedic",
        "capabilities": ["os-repair","linux","windows","macos","data-recovery","vpn"],
        "ttl": 600
    }')
    if echo "$resp" | grep -q '"id"'; then
        local id=$(echo "$resp" | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
        ok "Registered! Agent ID: $id"
        log "Registered on CraicKen, ID: $id"
    else
        warn "Registration response: $(echo $resp | head -c 200)"
        log "Registration: $resp"
    fi
}

heartbeat() {
    craic_api POST "/api/v1/net/heartbeat?name=${AGENT_NAME}" >/dev/null 2>&1
}

# --- Diagnostics collectors ---
collect_system_id() {
    echo "--- SYSTEM ID ---"
    echo "hostname: $(hostname 2>/dev/null)"
    echo "kernel: $(uname -a 2>/dev/null)"
    echo "uptime: $(uptime 2>/dev/null)"
    echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    dmidecode -s system-manufacturer 2>/dev/null && dmidecode -s system-product-name 2>/dev/null || lshw -short 2>/dev/null | head -5
}

collect_block_devices() {
    echo "--- BLOCK DEVICES ---"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINT,MODEL 2>/dev/null | grep -v loop
    echo ""
    echo "--- PARTITIONS ---"
    fdisk -l 2>/dev/null | grep -E '^/dev/|Disk /dev/' | grep -v loop
    echo ""
    echo "--- FILESYSTEMS ---"
    blkid 2>/dev/null
}

collect_hardware() {
    echo "--- HARDWARE ---"
    echo "CPU: $(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | xargs)"
    echo "RAM: $(free -h 2>/dev/null | grep Mem | awk '{print $2}')"
    echo "Disks:"
    lshw -class disk -short 2>/dev/null || lsblk -d -o NAME,SIZE,MODEL 2>/dev/null
    echo ""
    echo "--- NETWORK ---"
    ip -4 addr show 2>/dev/null | grep inet | grep -v 127.0.0.1
    echo "WG status:"
    wg show 2>/dev/null || echo "WireGuard not connected"
}

collect_dmesg() {
    echo "--- DMESG ERRORS ---"
    dmesg 2>/dev/null | grep -iE 'error|fail|panic|oops|hung|blocked' | tail -30
}

collect_os_scan() {
    echo "--- OS SCAN ---"
    for part in $(lsblk -nr -o NAME,FSTYPE 2>/dev/null | grep -E 'ext4|ntfs|hfsplus|apfs' | awk '{print $1}'); do
        local mp=$(mktemp -d)
        if mount "/dev/$part" "$mp" 2>/dev/null; then
            if [ -f "$mp/etc/os-release" ]; then
                echo "LINUX: $(grep PRETTY_NAME "$mp/etc/os-release" 2>/dev/null | cut -d= -f2 | tr -d '\"') on /dev/$part"
                echo "  kernel: $(cat "$mp/proc/version" 2>/dev/null || cat "$mp/etc/os-release" 2>/dev/null | head -3)"
                [ -f "$mp/var/log/syslog" ] && echo "  syslog: $(tail -5 "$mp/var/log/syslog" 2>/dev/null)"
            elif [ -d "$mp/Windows/System32" ]; then
                echo "WINDOWS: detected on /dev/$part"
                local winver=$(cat "$mp/Windows/System32/license.rtf" 2>/dev/null | head -1 || echo "unknown")
                echo "  version: $winver"
                # Check for boot issues
                [ -f "$mp/Windows/System32/LogFiles/SrtTrail.txt" ] && echo "  BOOT ISSUE: SrtTrail.txt found"
            elif [ -d "$mp/System/Library/CoreServices" ]; then
                echo "MACOS: detected on /dev/$part"
                local macver=$(cat "$mp/System/Library/CoreServices/SystemVersion.plist" 2>/dev/null | grep -A1 'ProductVersion' | tail -1 | sed 's/.*<string>//;s/<\/string>//')
                echo "  version: $macver"
            fi
            umount "$mp" 2>/dev/null
            rmdir "$mp" 2>/dev/null
        fi
    done
}

collect_smart() {
    echo "--- SMART STATUS ---"
    for disk in $(lsblk -d -o NAME 2>/dev/null | grep -E '^sd|^nvme|^hd'); do
        if command -v smartctl &>/dev/null; then
            smartctl -H "/dev/$disk" 2>/dev/null | grep -E 'SMART|PASSED|FAILED' && echo "  /dev/$disk" || true
        fi
    done
}

collect_all_diagnostics() {
    local tmpfile=$(mktemp)
    {
        collect_system_id
        echo ""
        collect_block_devices
        echo ""
        collect_hardware
        echo ""
        collect_os_scan
        echo ""
        collect_dmesg
        echo ""
        collect_smart
    } > "$tmpfile" 2>/dev/null
    echo "$tmpfile"
}

# --- Ingest to CraicKen ---
ingest_craic() {
    local kind="$1" text="$2" tags="$3"
    local data=$(cat << JSON
{
    "text": $(echo "$text" | jq -Rs . 2>/dev/null || echo "\"$text\""),
    "source": "sysmedic",
    "kind": "$kind",
    "tags": "$tags"
}
JSON
)
    craic_api POST /api/v1/context/ingest "$data" >/dev/null 2>&1
}

send_diagnostics() {
    local diag_file=$(collect_all_diagnostics)
    local content=$(cat "$diag_file" 2>/dev/null)
    
    info "Piping diagnostics to CraicKen..."
    
    # Ingest as ken (knowledge) — full system scan
    ingest_craic "ken" "=== SysMedic Rescue System Scan ===\n${content}" "rescue,system-scan,diagnostics"
    
    # Extract and send individual findings as craic (gossip)
    local os_count=$(echo "$content" | grep -c 'LINUX:\|WINDOWS:\|MACOS:')
    ingest_craic "craic" "Rescue scan complete: found ${os_count} operating system(s) on this machine.\n\n$(echo "$content" | grep -E 'LINUX:|WINDOWS:|MACOS:' | head -10)" "rescue,craic,os-detection"
    
    # Check for errors
    local err_count=$(echo "$content" | grep -ci 'error\|fail\|panic' 2>/dev/null)
    if [ "$err_count" -gt 0 ]; then
        local errors=$(echo "$content" | grep -iE 'error|fail|panic' | head -15)
        ingest_craic "craic" "Diagnostics found ${err_count} potential issues:\n${errors}" "rescue,craic,errors,warning"
    fi
    
    ok "Diagnostics sent to CraicKen as 'ken' + 'craic' entries"
    log "Diagnostics sent to CraicKen"
    rm -f "$diag_file"
}

# --- WireGuard auto-connect ---
connect_wireguard() {
    info "Connecting WireGuard to home network..."
    if command -v wg-quick &>/dev/null && [ -f /etc/wireguard/wg0.conf ]; then
        # Check if already up
        if wg show wg0 &>/dev/null; then
            ok "WireGuard already connected"
            wg show wg0 | grep -E 'interface|public|peer|endpoint'
            return 0
        fi
        wg-quick up wg0 2>&1 | while read line; do log "WG: $line"; done
        sleep 3
        if wg show wg0 &>/dev/null; then
            ok "WireGuard connected! VPN IP: $(ip -4 addr show wg0 2>/dev/null | grep inet | awk '{print $2}')"
            log "WireGuard connected successfully"
            # Route home LAN through VPN
            ip route add 192.168.1.0/24 dev wg0 2>/dev/null || true
            return 0
        else
            warn "WireGuard failed to connect — VPN may not be reachable"
            log "WireGuard connection failed"
            return 1
        fi
    else
        warn "WireGuard not available (wg-quick or config missing)"
        return 1
    fi
}

# --- Main ---
main() {
    mkdir -p "$(dirname "$LOG_FILE")" 2>/dev/null
    
    echo ""
    echo -e "${BOLD}  ╔══════════════════════════════════════╗${NC}"
    echo -e "${BOLD}  ║   🌐  CraicKen Telemetry Connect     ║${NC}"
    echo -e "${BOLD}  ║   Piping diagnostics to the mesh     ║${NC}"
    echo -e "${BOLD}  ╚══════════════════════════════════════╝${NC}"
    echo ""
    
    # Step 1: Wait for network
    info "Waiting for network..."
    if wait_for_network; then
        ok "Network is up"
    else
        warn "No network detected — skipping CraicKen connect"
        log "No network, skipping CraicKen"
        return 1
    fi
    
    # Step 2: Connect WireGuard
    connect_wireguard
    
    # Step 3: Register on CraicKen
    register_agent
    
    # Step 4: Send diagnostics
    send_diagnostics
    
    # Step 5: Background heartbeat loop
    info "Starting heartbeat loop (every 5 minutes)..."
    (
        while true; do
            sleep 300
            heartbeat
        done
    ) &
    HEARTBEAT_PID=$!
    log "Heartbeat PID: $HEARTBEAT_PID"
    
    echo ""
    echo -e "${GREEN}  ✅ CraicKen telemetry active${NC}"
    echo -e "     Agent: ${BOLD}${AGENT_NAME}${NC}"
    echo -e "     Home:  ${BOLD}${CRAICKEN}${NC}"
    echo -e "     VPN:   ${BOLD}10.13.13.8 → splippers.hopto.org${NC}
    echo ""
    echo -e "     ElAIne will see your data on CraicKen!"
    echo ""
}

main
