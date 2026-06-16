#!/bin/bash
# SysMedic — AI-Deep Diagnostic Analysis Pipeline (Tier 3)
# Aggregates all available diagnostics into structured JSON + human-readable report
# for AI-driven root cause analysis via OpenCode.
#
# Usage: bash sysmedic-analyze.sh [--quick] [--ai]
#   --quick   Skip long-running tests (SMART long, badblocks)
#   --ai      Launch OpenCode with the analysis when complete
#
# Output:
#   /tmp/sysmedic-analysis.json     — structured JSON for AI consumption
#   /root/sysmedic/reports/analysis-<ts>/summary.txt — human-readable report

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}[ANALYZE]${NC} $1"; }
ok()    { echo -e "  ${GREEN}[ANALYZE]${NC} $1"; }
warn()  { echo -e "  ${YELLOW}[ANALYZE]${NC} $1"; }
fail()  { echo -e "  ${RED}[ANALYZE]${NC} $1"; }

TIMESTAMP=$(date -u +%Y%m%d-%H%M%S)
REPORT_DIR="/root/sysmedic/reports/analysis-${TIMESTAMP}"
CONTEXT_FILE="/tmp/sysmedic-context.json"
ANALYSIS_JSON="/tmp/sysmedic-analysis.json"
SUMMARY_FILE="${REPORT_DIR}/summary.txt"
QUICK_MODE=false
LAUNCH_AI=false
DIAGNOSTIC_COLLECTED=0
DIAGNOSTIC_FAILED=0

mkdir -p "$REPORT_DIR"

# Parse args
for arg in "$@"; do
    case "$arg" in
        --quick) QUICK_MODE=true ;;
        --ai)    LAUNCH_AI=true ;;
    esac
done

# ──────────────────────────────────────────────
# Cleanup
# ──────────────────────────────────────────────
cleanup() {
    info "Cleaning up temporary mounts..."
    umount /mnt/sysmedic-analysis 2>/dev/null
    rm -rf /tmp/sysmedic-analyze-* 2>/dev/null
}
trap cleanup EXIT

# ──────────────────────────────────────────────
# Section tracking
# ──────────────────────────────────────────────
section() {
    echo "" >> "$SUMMARY_FILE"
    echo "══════════════════════════════════════════════════════" >> "$SUMMARY_FILE"
    echo "  $1" >> "$SUMMARY_FILE"
    echo "══════════════════════════════════════════════════════" >> "$SUMMARY_FILE"
}

log_finding() {
    local severity="$1" category="$2" finding="$3"
    echo -e "  [${severity}] [${category}] ${finding}" | tee -a "$SUMMARY_FILE"
    if [ "$severity" = "FAIL" ]; then
        ((DIAGNOSTIC_FAILED++))
    else
        ((DIAGNOSTIC_COLLECTED++))
    fi
}

# ──────────────────────────────────────────────
# Begin
# ──────────────────────────────────────────────

echo ""
echo -e "${BOLD}  ╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}  ║   🔬  SysMedic AI-Deep Analysis                      ║${NC}"
echo -e "${BOLD}  ║   Aggregating diagnostics for root cause analysis    ║${NC}"
echo -e "${BOLD}  ╚══════════════════════════════════════════════════════╝${NC}"
echo ""

[ "$QUICK_MODE" = true ] && info "Quick mode — skipping long-running tests"

# ──────────────────────────────────────────────
# 1) Load preflight context
# ──────────────────────────────────────────────
section "1. SYSTEM CONTEXT"

# Run preflight if context doesn't exist
if [ ! -f "$CONTEXT_FILE" ]; then
    if [ -x "$(dirname "$0")/preflight.sh" ]; then
        warn "No preflight context — running preflight.sh..."
        bash "$(dirname "$0")/preflight.sh" 2>/dev/null
    else
        warn "No context file and preflight.sh not found — using direct hardware detection"
    fi
fi

if [ -f "$CONTEXT_FILE" ]; then
    if python3 -c "import json; json.load(open('$CONTEXT_FILE'))" 2>/dev/null; then
        log_finding "OK" "SYSTEM" "Loaded preflight context from ${CONTEXT_FILE}"
    else
        warn "Corrupt context JSON — removing"
        rm -f "$CONTEXT_FILE"
    fi
fi

# Extract system info (from context if available, otherwise direct)
SYS_VENDOR="Unknown"; SYS_PRODUCT="Unknown"; SYS_SERIAL="Unknown"
CPU_MODEL="Unknown"; MEM_GB="?"; KERNEL="$(uname -a 2>/dev/null)"

# Use a temp file for safe variable passing from Python to Bash
_SYSINFO_FILE="/tmp/sysmedic-sysinfo-$$.sh"
python3 << PYEOF 2>/dev/null
import json
try:
    with open('/tmp/sysmedic-context.json') as f:
        d = json.load(f)
    s = d.get('system', {})
    c = d.get('cpu', {})
    m = d.get('memory', {})
    vendor = s.get('vendor', 'Unknown')
    product = s.get('product', 'Unknown')
    serial = s.get('serial', 'Unknown')
    cpu = c.get('model', 'Unknown')
    mem = m.get('total_gb', '?')
except:
    vendor = 'Unknown'; product = 'Unknown'; serial = 'Unknown'
    cpu = 'Unknown'; mem = '?'

with open('$_SYSINFO_FILE', 'w') as f:
    f.write(f'SYS_VENDOR={vendor!r}\n')
    f.write(f'SYS_PRODUCT={product!r}\n')
    f.write(f'SYS_SERIAL={serial!r}\n')
    f.write(f'CPU_MODEL={cpu!r}\n')
    f.write(f'MEM_GB={mem!r}\n')
PYEOF

if [ -f "$_SYSINFO_FILE" ]; then
    source "$_SYSINFO_FILE"
    rm -f "$_SYSINFO_FILE"
fi

# Fallback if context didn't have data
if [ "$SYS_VENDOR" = "Unknown" ] || [ -z "$SYS_VENDOR" ]; then
    SYS_VENDOR="$(dmidecode -s system-manufacturer 2>/dev/null || echo "Unknown")"
    SYS_PRODUCT="$(dmidecode -s system-product-name 2>/dev/null || echo "Unknown")"
    SYS_SERIAL="$(dmidecode -s system-serial-number 2>/dev/null || echo "Unknown")"
    CPU_MODEL="$(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | sed 's/.*: //' || echo "Unknown")"
    MEM_GB="$(free -g | awk '/^Mem:/{print $2}')"
fi

echo "  System:  ${SYS_VENDOR} ${SYS_PRODUCT} (${SYS_SERIAL})" | tee -a "$SUMMARY_FILE"
echo "  CPU:     ${CPU_MODEL}" | tee -a "$SUMMARY_FILE"
echo "  RAM:     ${MEM_GB} GB" | tee -a "$SUMMARY_FILE"
echo "  Kernel:  ${KERNEL:0:100}" | tee -a "$SUMMARY_FILE"

# ──────────────────────────────────────────────
# 2) Fresh SMART health check on all drives
# ──────────────────────────────────────────────
section "2. DISK HEALTH (SMART)"
for disk in $(lsblk -dno NAME 2>/dev/null | grep -E '^(sd|nvme|mmcblk)'); do
    dev="/dev/${disk}"
    if [ ! -b "$dev" ]; then continue; fi

    # Basic health
    health=$(smartctl -H "$dev" 2>/dev/null | grep -E 'SMART overall-health|PASSED|FAILED' | head -1)
    if echo "$health" | grep -qi "PASSED"; then
        log_finding "PASS" "DISK" "${dev}: SMART health PASSED"
    elif echo "$health" | grep -qi "FAILED"; then
        log_finding "FAIL" "DISK" "${dev}: SMART health FAILED!"
    else
        log_finding "WARN" "DISK" "${dev}: SMART status unavailable"
    fi

    # Temperature (smartctl outputs columns: ID# ATTRIBUTE_NAME FLAG VALUE WORST THRESH TYPE UPDATED WHEN_FAILED RAW_VALUE)
    temp=$(smartctl -A "$dev" 2>/dev/null | grep -i "Temperature_Celsius" | awk '{print $10}')
    # If no raw value, try the VALUE column (column 4)
    [ -z "$temp" ] && temp=$(smartctl -A "$dev" 2>/dev/null | grep -i "Temperature_Celsius" | awk '{print $4}')
    [ -n "$temp" ] && log_finding "INFO" "DISK" "${dev}: ${temp}°C"

    # Critical attributes
    realloc=$(smartctl -A "$dev" 2>/dev/null | grep "Reallocated_Sector_Ct" | awk '{print $NF}')
    pending=$(smartctl -A "$dev" 2>/dev/null | grep "Current_Pending_Sector" | awk '{print $NF}')
    uncorrect=$(smartctl -A "$dev" 2>/dev/null | grep "Offline_Uncorrectable" | awk '{print $NF}')
    crc=$(smartctl -A "$dev" 2>/dev/null | grep "UDMA_CRC_Error" | awk '{print $NF}')

    [ -n "$realloc" ] && [ "$realloc" -gt 0 ] && log_finding "WARN" "DISK" "${dev}: ${realloc} reallocated sectors"
    [ -n "$pending" ] && [ "$pending" -gt 0 ] && log_finding "WARN" "DISK" "${dev}: ${pending} pending sectors"
    [ -n "$uncorrect" ] && [ "$uncorrect" -gt 0 ] && log_finding "FAIL" "DISK" "${dev}: ${uncorrect} uncorrectable sectors!"
    [ -n "$crc" ] && [ "$crc" -gt 0 ] && log_finding "WARN" "DISK" "${dev}: ${crc} UDMA CRC errors"

    # Save full SMART data
    smartctl -a "$dev" 2>/dev/null > "${REPORT_DIR}/smart-${disk}.txt"
done

# ──────────────────────────────────────────────
# 3) Scan for recent stress test reports
# ──────────────────────────────────────────────
section "3. STRESS TEST HISTORY"
STRESS_REPORTS_DIR="/root/sysmedic/reports"
found_stress=false

for report_dir in $(ls -td "${STRESS_REPORTS_DIR}/stress-"* 2>/dev/null | head -5); do
    ts=$(basename "$report_dir" | sed 's/stress-//')
    # Parse timestamp
    date_part=$(echo "$ts" | cut -d- -f1)
    time_part=$(echo "$ts" | cut -d- -f2)
    readable="${date_part:0:4}-${date_part:4:2}-${date_part:6:2} ${time_part:0:2}:${time_part:2:2}:${time_part:4:2}"

    # Check report age (skip if older than 30 days in quick mode)
    if [ "$QUICK_MODE" = true ]; then
        dir_epoch=$(stat -c %Y "$report_dir" 2>/dev/null || echo 0)
        now_epoch=$(date +%s)
        age_days=$(( (now_epoch - dir_epoch) / 86400 ))
        [ "$age_days" -gt 30 ] && continue
    fi

    echo "  Report: ${report_dir} (${readable})" >> "$SUMMARY_FILE"
    found_stress=true

    # Check for summary file
    if [ -f "${report_dir}/summary.txt" ]; then
        echo "  ├─ Summary:" >> "$SUMMARY_FILE"
        sed 's/^/  │  /' "${report_dir}/summary.txt" >> "$SUMMARY_FILE" 2>/dev/null
    fi

    # Check test results
    for logfile in "${report_dir}"/*.log; do
        [ ! -f "$logfile" ] && continue
        fname=$(basename "$logfile")
        case "$fname" in
            cpu-stress*)       echo "  ├─ CPU stress test log present" >> "$SUMMARY_FILE" ;;
            memory-stress*)    echo "  ├─ Memory stress test log present" >> "$SUMMARY_FILE" ;;
            drive-stress*)     echo "  ├─ Drive stress test log present" >> "$SUMMARY_FILE" ;;
            memtester*)        echo "  ├─ memtester log present" >> "$SUMMARY_FILE" ;;
            temperature*)      echo "  ├─ Temperature log present" >> "$SUMMARY_FILE" ;;
            smart-full*)       echo "  ├─ Full SMART data captured" >> "$SUMMARY_FILE" ;;
            badblocks*)        echo "  ├─ Badblocks log present" >> "$SUMMARY_FILE" ;;
            burnin-*)          echo "  ├─ Burn-in data: ${fname}" >> "$SUMMARY_FILE" ;;
        esac
    done

    # Extract key findings from stress test summary
    if [ -f "${report_dir}/summary.txt" ]; then
        grep -E "FAIL|ERROR|panic|throttle|critical" "${report_dir}/summary.txt" 2>/dev/null | while read line; do
            log_finding "WARN" "STRESS" "Previous stress test finding: ${line}"
        done
    fi

    # Copy SMART deltas if available
    for sf in burnin-smart-before.log burnin-smart-after.log; do
        [ -f "${report_dir}/${sf}" ] && cp "${report_dir}/${sf}" "${REPORT_DIR}/"
    done

    echo "" >> "$SUMMARY_FILE"
done

if [ "$found_stress" = false ]; then
    log_finding "INFO" "STRESS" "No recent stress test reports found"
fi

# ──────────────────────────────────────────────
# 4) dmesg error analysis
# ──────────────────────────────────────────────
section "4. KERNEL LOG (dmesg)"
ERROR_PATTERNS="error|fail|panic|oops|hung_task|blocked|watchdog|thermal.throttle|soft_lockup|rcu_sched|kernel BUG|Out of memory|segfault"
dmesg_errors=$(dmesg 2>/dev/null | grep -iE "${ERROR_PATTERNS}" | tail -50)
if [ -n "$dmesg_errors" ]; then
    count=$(echo "$dmesg_errors" | wc -l)
    log_finding "WARN" "DMESG" "${count} kernel issues detected (showing last 15)"
    echo "$dmesg_errors" | tail -15 | while read line; do
        echo "  ╎ ${line}" >> "$SUMMARY_FILE"
    done
    echo "$dmesg_errors" > "${REPORT_DIR}/dmesg-errors.txt"
else
    log_finding "PASS" "DMESG" "No critical kernel errors detected"
fi

# ──────────────────────────────────────────────
# 5) Temperature analysis
# ──────────────────────────────────────────────
section "5. THERMAL ANALYSIS"
if command -v sensors &>/dev/null; then
    sensors_data=$(sensors 2>/dev/null)
    if [ -n "$sensors_data" ]; then
        echo "$sensors_data" > "${REPORT_DIR}/sensors-current.txt"

        # Extract peak temps
        peaks=$(echo "$sensors_data" | grep -v '(' | grep -oP '[\+\-][0-9]+\.[0-9]+°C' | sed 's/[+°C]//g' | sort -rn | head -5)
        if [ -n "$peaks" ]; then
            hottest=$(echo "$peaks" | head -1)
            echo "  Current peak temperature: ${hottest}°C" >> "$SUMMARY_FILE"

            # Check against common thresholds
            if [ "$(echo "$hottest" | cut -d. -f1)" -gt 100 ]; then
                log_finding "WARN" "THERMAL" "Peak temp ${hottest}°C exceeds 100°C — possible throttling"
            elif [ "$(echo "$hottest" | cut -d. -f1)" -gt 90 ]; then
                log_finding "INFO" "THERMAL" "Peak temp ${hottest}°C — warm but within spec"
            else
                log_finding "PASS" "THERMAL" "Temperatures nominal (peak ${hottest}°C)"
            fi
        fi

        # CPU package temp
        pkg_temp=$(echo "$sensors_data" | grep "Package" | awk '{print $4}' 2>/dev/null)
        [ -n "$pkg_temp" ] && echo "  CPU package: ${pkg_temp}" >> "$SUMMARY_FILE"

        # NVMe temp
        nvme_temp=$(echo "$sensors_data" | grep "Composite" | awk '{print $2}' 2>/dev/null)
        [ -n "$nvme_temp" ] && echo "  NVMe: ${nvme_temp}" >> "$SUMMARY_FILE"

        # Check for thermal throttle
        if echo "$sensors_data" | grep -qi "throttle"; then
            log_finding "FAIL" "THERMAL" "Thermal throttling detected by sensors!"
        fi
    else
        log_finding "WARN" "THERMAL" "sensors command available but returned no data"
    fi
else
    log_finding "WARN" "THERMAL" "lm-sensors not installed — falling back to /sys/class/thermal"
    for zone in /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$zone" ] || continue
        temp=$(cat "$zone" 2>/dev/null)
        temp_c=$(( temp / 1000 ))
        echo "  Thermal zone $(basename $(dirname $zone)): ${temp_c}°C" >> "$SUMMARY_FILE"
    done
fi

# ──────────────────────────────────────────────
# 6) Detected OS issues
# ──────────────────────────────────────────────
section "6. DETECTED OS ANALYSIS"
# Extract OS info from context safely via temp file
_OSINFO_FILE="/tmp/sysmedic-osinfo-$$.sh"
if [ -f "$CONTEXT_FILE" ]; then
    python3 << PYEOF 2>/dev/null
import json
with open('/tmp/sysmedic-context.json') as f:
    d = json.load(f)
oses = d.get('detected_oses', [])
with open('$_OSINFO_FILE', 'w') as f:
    f.write(f'OS_COUNT={len(oses)}\n')
    for i, os_item in enumerate(oses):
        name = os_item.get('name', '?')
        dev = os_item.get('device', '?')
        otype = os_item.get('type', '?')
        f.write(f'OS_{i}_NAME={name!r}\n')
        f.write(f'OS_{i}_DEV={dev!r}\n')
        f.write(f'OS_{i}_TYPE={otype!r}\n')
PYEOF
    if [ -f "$_OSINFO_FILE" ]; then
        source "$_OSINFO_FILE"
        rm -f "$_OSINFO_FILE"
    fi
fi

# Probe each detected OS for boot issues
for part in $(lsblk -nr -o NAME,FSTYPE 2>/dev/null | grep -E 'ext4|ntfs|xfs|btrfs' | awk '{print $1}'); do
    dev="/dev/${part}"
    mountpoint="/tmp/sysmedic-analyze-mount-${part}"
    mkdir -p "$mountpoint" 2>/dev/null

    if mount "$dev" "$mountpoint" 2>/dev/null; then
        # Linux checks
        if [ -f "${mountpoint}/etc/os-release" ]; then
            os_name=$(grep PRETTY_NAME "${mountpoint}/etc/os-release" 2>/dev/null | cut -d= -f2 | tr -d '"')
            echo "  ${os_name} on ${dev}" >> "$SUMMARY_FILE"

            # Check last journalctl errors
            if [ -d "${mountpoint}/var/log/journal" ]; then
                log_count=$(find "${mountpoint}/var/log/journal" -name "*.journal" 2>/dev/null | wc -l)
                [ "$log_count" -gt 0 ] && echo "  ├─ Systemd journal entries: ${log_count}" >> "$SUMMARY_FILE"
            fi

            # Check for dpkg failures
            if [ -f "${mountpoint}/var/log/dpkg.log" ]; then
                dpkg_errors=$(grep -c "error\|fail" "${mountpoint}/var/log/dpkg.log" 2>/dev/null || echo 0)
                [ "$dpkg_errors" -gt 0 ] && log_finding "WARN" "OS" "${dev}: ${dpkg_errors} dpkg error(s) found"
            fi

            # Check for kernel panics in logs
            for logf in "${mountpoint}/var/log/kern.log" "${mountpoint}/var/log/syslog"; do
                [ -f "$logf" ] || continue
                panic_count=$(grep -c "panic\|Oops\|kernel BUG" "$logf" 2>/dev/null || echo 0)
                [ "$panic_count" -gt 0 ] && log_finding "FAIL" "OS" "${dev}: ${panic_count} kernel panic(s) in ${logf}"
            done

            # Check disk space
            df_output=$(df -h "$dev" 2>/dev/null | tail -1)
            usage=$(echo "$df_output" | awk '{print $5}' | tr -d '%')
            if [ -n "$usage" ] && [ "$usage" -gt 90 ]; then
                log_finding "WARN" "OS" "${dev}: disk usage at ${usage}%"
            fi

        # Windows checks
        elif [ -d "${mountpoint}/Windows/System32" ]; then
            echo "  Windows on ${dev}" >> "$SUMMARY_FILE"
            # Check for minidumps
            dumps=$(find "${mountpoint}/Windows/minidump" -name "*.dmp" 2>/dev/null | wc -l)
            log_dumps=$(find "${mountpoint}/Windows/system32/LogFiles" -name "*.evtx" 2>/dev/null | wc -l)
            [ "$dumps" -gt 0 ] && log_finding "WARN" "OS" "${dev}: ${dumps} BSOD minidump(s) found"
            [ "$log_dumps" -gt 0 ] && echo "  ├─ Event log files: ${log_dumps}" >> "$SUMMARY_FILE"

            # Check for pending updates (via Windows\Update.log)
            if [ -f "${mountpoint}/Windows/WindowsUpdate.log" ]; then
                update_errors=$(grep -c "failed\|error\|0x8" "${mountpoint}/Windows/WindowsUpdate.log" 2>/dev/null || echo 0)
                [ "$update_errors" -gt 0 ] && log_finding "WARN" "OS" "${dev}: ${update_errors} Windows Update error(s)"
            fi
        fi

        umount "$mountpoint" 2>/dev/null
    fi
    rmdir "$mountpoint" 2>/dev/null
done

# ──────────────────────────────────────────────
# 7) Bootloader integrity check
# ──────────────────────────────────────────────
section "7. BOOTLOADER INTEGRITY"
for disk in nvme0n1 sda sdb sdc; do
    [ -b "/dev/${disk}" ] || continue
    efi_part=""
    # Find EFI partition
    for part in $(lsblk -nlo NAME "/dev/${disk}" 2>/dev/null); do
        full="/dev/${part}"
        if blkid "$full" 2>/dev/null | grep -qi "EFI\|vfat"; then
            efi_part="$full"
            break
        fi
    done

    if [ -n "$efi_part" ]; then
        mp="/tmp/sysmedic-analyze-efi"
        mkdir -p "$mp" 2>/dev/null
        if mount "$efi_part" "$mp" 2>/dev/null; then
            # Check for bootloaders
            has_grub=false; has_windows=false; has_syslinux=false
            [ -f "${mp}/EFI/ubuntu/grubx64.efi" ] && has_grub=true
            [ -d "${mp}/EFI/Microsoft" ] && has_windows=true
            [ -f "${mp}/EFI/syslinux/syslinux.efi" ] && has_syslinux=true

            echo "  EFI partition: ${efi_part}" >> "$SUMMARY_FILE"
            $has_grub && echo "  ├─ GRUB (Ubuntu/Linux bootloader) present" >> "$SUMMARY_FILE"
            $has_windows && echo "  ├─ Windows Boot Manager present" >> "$SUMMARY_FILE"
            $has_syslinux && echo "  ├─ SYSLINUX present" >> "$SUMMARY_FILE"

            # Check for missing files
            if $has_grub && [ ! -f "${mp}/EFI/ubuntu/grub.cfg" ]; then
                log_finding "WARN" "BOOT" "GRUB EFI binary present but grub.cfg missing on ${efi_part}"
            fi
            umount "$mp" 2>/dev/null
        fi
        rmdir "$mp" 2>/dev/null
    fi
done

# ──────────────────────────────────────────────
# 8) Network diagnostics
# ──────────────────────────────────────────────
section "8. NETWORK STATUS"
echo "  Interfaces:" >> "$SUMMARY_FILE"
ip -4 addr show 2>/dev/null | grep -w inet | while read line; do
    echo "  ╎ ${line}" >> "$SUMMARY_FILE"
done

# Connectivity test
if ping -c1 -W2 8.8.8.8 &>/dev/null; then
    log_finding "PASS" "NET" "Internet reachable (8.8.8.8)"
elif ping -c1 -W2 1.1.1.1 &>/dev/null; then
    log_finding "PASS" "NET" "Internet reachable (1.1.1.1)"
else
    log_finding "WARN" "NET" "No internet connectivity detected"
fi

# ──────────────────────────────────────────────
# 9) Check for known hardware patterns (heuristics)
# ──────────────────────────────────────────────
section "9. HARDWARE ANOMALY DETECTION"
anomalies_found=0

# Read CPU core temps looking for large deltas
if command -v sensors &>/dev/null; then
    core_temps=$(sensors 2>/dev/null | grep -i "Core" | grep -oP '[\+\-][0-9]+\.[0-9]+°C' | sed 's/[+°C]//g')
    if [ -n "$core_temps" ]; then
        max_temp=$(echo "$core_temps" | sort -rn | head -1)
        min_temp=$(echo "$core_temps" | sort -n | head -1)
        delta=$(echo "$max_temp - $min_temp" | bc 2>/dev/null)
        if [ "$(echo "$delta > 15" | bc 2>/dev/null)" = "1" ]; then
            log_finding "WARN" "THERMAL" "Core temperature delta ${delta}°C exceeds 15°C — possible TIM/heatsink issue"
            ((anomalies_found++))
        fi
    fi
fi

# Check for high IRQ time
irq_info=$(head -1 /proc/stat 2>/dev/null)
if [ -n "$irq_info" ]; then
    total_jiffies=$(echo "$irq_info" | awk '{for(i=2;i<=NF;i++) s+=$i; print s}')
    irq_jiffies=$(echo "$irq_info" | awk '{print $6+$7}')
    if [ "$total_jiffies" -gt 0 ]; then
        irq_pct=$(echo "scale=2; 100 * $irq_jiffies / $total_jiffies" | bc 2>/dev/null)
        if [ "$(echo "$irq_pct > 10" | bc 2>/dev/null)" = "1" ]; then
            log_finding "WARN" "CPU" "High IRQ time (${irq_pct}%) — possible hardware interrupt storm"
            ((anomalies_found++))
        fi
    fi
fi

# Check memory errors in dmesg
mem_errors=$(dmesg 2>/dev/null | grep -ci "edac\|mce.*error\|uncorrected.*memory\|CE.*memory\|memory.*failure")
if [ "$mem_errors" -gt 0 ]; then
    log_finding "FAIL" "MEMORY" "${mem_errors} memory error(s) in kernel log — check for bad DIMMs!"
    ((anomalies_found++))
fi

if [ "$anomalies_found" -eq 0 ]; then
    log_finding "PASS" "HW-ANOMALY" "No hardware anomalies detected"
fi

# ──────────────────────────────────────────────
# 10) Generate structured JSON for AI
# ──────────────────────────────────────────────
section "10. GENERATING AI ANALYSIS DATA"

# Export needed variables for Python
export SYSMEDIC_REPORT_DIR="$REPORT_DIR"
export SYSMEDIC_QUICK_MODE="$QUICK_MODE"
export SYSMEDIC_ANALYSIS_JSON="$ANALYSIS_JSON"

python3 << 'PYEOF' 2>/dev/null
import json, os, subprocess
from datetime import datetime

report_dir = os.environ.get('SYSMEDIC_REPORT_DIR', '/root/sysmedic/reports/analysis-unknown')
summary_file = os.path.join(report_dir, "summary.txt")
context_file = "/tmp/sysmedic-context.json"
analysis_json = os.environ.get('SYSMEDIC_ANALYSIS_JSON', '/tmp/sysmedic-analysis.json')
quick_mode = os.environ.get('SYSMEDIC_QUICK_MODE', 'false') == 'true'

def read_file(path):
    try:
        with open(path) as f:
            return f.read()
    except:
        return ""

def run(cmd):
    try:
        return subprocess.check_output(cmd, shell=True, stderr=subprocess.DEVNULL, timeout=10).decode(errors='replace').strip()
    except:
        return ""

analysis = {
    "analysis_timestamp": datetime.utcnow().isoformat() + "Z",
    "sysmedic_version": "3.0",
    "analysis_type": "quick" if quick_mode else "full",
}

# Load context
if os.path.isfile(context_file):
    try:
        with open(context_file) as f:
            analysis["preflight_context"] = json.load(f)
    except Exception as e:
        analysis["preflight_context"] = {"error": f"failed to parse context JSON: {e}"}

# Collect summary
analysis["summary"] = read_file(summary_file)

# Collect recent stress test results
stress_results = []
stress_base = "/root/sysmedic/reports"
if os.path.isdir(stress_base):
    for d in sorted(os.listdir(stress_base), reverse=True)[:5]:
        if d.startswith("stress-"):
            dp = os.path.join(stress_base, d)
            stress_results.append({
                "report": d,
                "summary": read_file(os.path.join(dp, "summary.txt")),
                "has_memtester": os.path.isfile(os.path.join(dp, "memtester.log")),
                "has_cpu_stress": any(f.startswith("cpu-stress") for f in os.listdir(dp) if os.path.isfile(os.path.join(dp, f))),
                "has_memory_stress": any(f.startswith("memory-stress") for f in os.listdir(dp) if os.path.isfile(os.path.join(dp, f))),
                "has_drive_stress": any(f.startswith("drive-stress") for f in os.listdir(dp) if os.path.isfile(os.path.join(dp, f))),
                "has_burnin": any(f.startswith("burnin") for f in os.listdir(dp) if os.path.isfile(os.path.join(dp, f))),
            })
analysis["stress_test_history"] = stress_results

# Collect dmesg errors
analysis["dmesg_errors"] = read_file(os.path.join(report_dir, "dmesg-errors.txt"))

# Collect current sensors
analysis["current_sensors"] = read_file(os.path.join(report_dir, "sensors-current.txt"))

# Collect SMART for all disks
smart_data = {}
if os.path.isdir(report_dir):
    for f in os.listdir(report_dir):
        if f.startswith("smart-"):
            disk_name = f.replace("smart-", "").replace(".txt", "")
            smart_data[disk_name] = read_file(os.path.join(report_dir, f))
analysis["smart_reports"] = smart_data

# Memory info
analysis["memory_health"] = {
    "total_gb": run("free -g | awk '/^Mem:/{print $2}'"),
    "available_gb": run("free -g | awk '/^Mem:/{print $7}'"),
    "swap_total": run("free -h | awk '/^Swap:/{print $2}'"),
}

# Uptime
analysis["uptime"] = run("uptime -p")
analysis["load_average"] = run("cat /proc/loadavg")

# Battery health
bat_info = {}
for bat in os.listdir("/sys/class/power_supply/"):
    if bat.startswith("BAT"):
        def read_bat(f):
            try:
                with open(f"/sys/class/power_supply/{bat}/{f}") as fh:
                    return fh.read().strip()
            except:
                return None
        ef = read_bat("energy_full")
        efd = read_bat("energy_full_design")
        wear = 0.0
        if ef and efd and int(efd) > 0:
            wear = round((1 - int(ef) / int(efd)) * 100, 1)
        bat_info = {
            "status": read_bat("status"),
            "capacity_pct": read_bat("capacity"),
            "wear_pct": wear,
            "manufacturer": read_bat("manufacturer"),
        }
        break
analysis["battery"] = bat_info

# Write final JSON
with open(analysis_json, "w") as f:
    json.dump(analysis, f, indent=2, default=str, sort_keys=False)

print("  [OK] AI-ready analysis JSON written to " + analysis_json)
PYEOF

if [ -f "$ANALYSIS_JSON" ] && python3 -c "import json; json.load(open('$ANALYSIS_JSON'))" 2>/dev/null; then
    json_size=$(stat -c%s "$ANALYSIS_JSON" 2>/dev/null)
    json_human=$(numfmt --to=iec $json_size 2>/dev/null || echo "${json_size}B")
    log_finding "PASS" "AI" "Analysis JSON generated (${json_human})"
else
    log_finding "FAIL" "AI" "Failed to generate analysis JSON"
fi

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
section "SUMMARY"
echo "  Findings collected: ${DIAGNOSTIC_COLLECTED}" >> "$SUMMARY_FILE"
echo "  Warnings/Issues:    ${DIAGNOSTIC_FAILED}" >> "$SUMMARY_FILE"
echo "" >> "$SUMMARY_FILE"
echo "  AI Analysis file:   ${ANALYSIS_JSON}" >> "$SUMMARY_FILE"
echo "  Report directory:   ${REPORT_DIR}" >> "$SUMMARY_FILE"

echo ""
echo -e "${BOLD}  ╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}  ║              AI ANALYSIS COMPLETE                     ║${NC}"
echo -e "${BOLD}  ╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}  ║${NC}  Diagnostics collected: ${DIAGNOSTIC_COLLECTED}"
echo -e "${BOLD}  ║${NC}  Warnings/Issues:       ${YELLOW}${DIAGNOSTIC_FAILED}${NC}"
echo -e "${BOLD}  ║${NC}  Analysis JSON:         ${CYAN}${ANALYSIS_JSON}${NC}"
echo -e "${BOLD}  ║${NC}  Report dir:            ${REPORT_DIR}"
echo -e "${BOLD}  ╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# ──────────────────────────────────────────────
# Launch AI if requested
# ──────────────────────────────────────────────
if [ "$LAUNCH_AI" = true ] && command -v opencode &>/dev/null; then
    echo -e "${BOLD}  Launching OpenCode for AI-powered root cause analysis...${NC}"
    echo ""

    # Set up the environment for OpenCode
    export SYSMEDIC_ANALYSIS_FILE="$ANALYSIS_JSON"
    export SYSMEDIC_ANALYSIS_REPORT="$REPORT_DIR"

    # Launch with a pre-seeded prompt
    echo -e "${CYAN}  The AI will receive the full diagnostic analysis.${NC}"
    echo -e "${CYAN}  Providing summary as initial context...${NC}"
    echo ""

    # Print the analysis prompt
    cat << PROMPT

══════════════════════════════════════════════════════
  SysMedic AI Analysis — Context for OpenCode
══════════════════════════════════════════════════════

  System:  ${SYS_VENDOR} ${SYS_PRODUCT} (${SYS_SERIAL})
  CPU:     ${CPU_MODEL}
  RAM:     ${MEM_GB} GB

  The full diagnostic analysis is available at:
    JSON:  ${ANALYSIS_JSON}
    Text:  ${SUMMARY_FILE}

  Starting OpenCode with AI analysis capability...
PROMPT

    echo ""
    sleep 2
    opencode
elif [ "$LAUNCH_AI" = true ]; then
    fail "OpenCode not found — cannot launch AI analysis"
    echo "  Install or mount persistence partition with OpenCode first."
    echo "  Analysis data is still available at:"
    echo "    JSON:  ${ANALYSIS_JSON}"
    echo "    Text:  ${SUMMARY_FILE}"
fi

echo ""
info "Analysis complete. Data saved to:"
echo "  ${REPORT_DIR}/"
echo "  ${ANALYSIS_JSON}"
echo ""
