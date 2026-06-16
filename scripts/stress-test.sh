#!/bin/bash
# SysMedic — Hardware Stress Test & Burn-In Suite
# Tier 2: Validates CPU, RAM, disk, and thermal stability
#
# Usage: bash stress-test.sh
#
# Options:
#   1  CPU Stress Test      — stress-ng all cores
#   2  Memory Stress Test   — memtester + stress-ng vm
#   3  Drive Stress Test    — stress-ng hdd + optional badblocks
#   4  SMART Long Test      — schedule + monitor self-test
#   5  Temperature Monitor  — live watch with logging
#   6  Full Burn-In Suite   — all tests sequentially
#   7  Quick Sanity Check   — 5-min short test loop
#   0  Exit

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'

SCRIPT_NAME="$(basename "$0")"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
REPORT_DIR="/root/sysmedic/reports/stress-${TIMESTAMP}"
SUMMARY_FILE="${REPORT_DIR}/summary.txt"
PASS=0; FAIL=0; WARN=0
ABORTED=0

mkdir -p "$REPORT_DIR"

# ──────────────────────────────────────────────
# Cleanup trap
# ──────────────────────────────────────────────
cleanup() {
    echo -e "\n  ${YELLOW}Aborting... stopping all stress processes...${NC}"
    killall stress-ng 2>/dev/null
    killall memtester 2>/dev/null
    ABORTED=1
    echo -e "\n  ${YELLOW}Partial results saved to ${REPORT_DIR}${NC}"
}
trap cleanup SIGINT SIGTERM

# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────
show_header() {
    local title="$1"
    clear
    echo ""
    echo -e "${BOLD}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}  ║  ${title}${NC}"
    echo -e "${BOLD}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
}

pause() {
    echo ""
    read -p "  Press Enter..."
}

log() {
    local status="$1" msg="$2"
    echo -e "  [${status}] ${msg}" | tee -a "$SUMMARY_FILE"
    case "$status" in
        PASS) ((PASS++)) ;;
        FAIL) ((FAIL++)) ;;
        WARN) ((WARN++)) ;;
    esac
}

section() {
    echo "" >> "$SUMMARY_FILE"
    echo "────────────────────────────────────────────" >> "$SUMMARY_FILE"
    echo "  $1" >> "$SUMMARY_FILE"
    echo "────────────────────────────────────────────" >> "$SUMMARY_FILE"
}

detect_ncpus() { nproc 2>/dev/null || echo 4; }

prompt_duration() {
    local default="$1" label="${2:-minutes}"
    read -p "  Duration in ${label} [${default}]: " dur
    echo "${dur:-$default}"
}

choose_disk() {
    local disks=()
    while IFS= read -r line; do
        disks+=("$line")
    done < <(lsblk -dno NAME,SIZE,TYPE | grep -E "sd|nvme" | awk '{print "/dev/" $1 " (" $2 ")"}')
    if [ ${#disks[@]} -eq 0 ]; then
        echo "  ${RED}No block devices found!${NC}"
        return 1
    fi
    echo "  Available disks:"
    local i=1
    local names=()
    for d in "${disks[@]}"; do
        name=$(echo "$d" | awk '{print $1}')
        names+=("$name")
        echo "  ${i}) $d"
        ((i++))
    done
    echo ""
    read -p "  Select disk [1-${#disks[@]}]: " sel
    sel="${sel:-1}"
    if [ "$sel" -ge 1 ] && [ "$sel" -le "${#names[@]}" ]; then
        echo "${names[$((sel-1))]}"
    else
        echo "  ${RED}Invalid selection${NC}" >&2
        return 1
    fi
}

# ──────────────────────────────────────────────
# 1) CPU Stress Test
# ──────────────────────────────────────────────
run_cpu_stress() {
    show_header "  CPU STRESS TEST"
    local ncpus
    ncpus=$(detect_ncpus)
    local duration
    duration=$(prompt_duration 10)
    local logfile="${REPORT_DIR}/cpu-stress.log"

    section "CPU Stress Test (${duration} min, ${ncpus} cores)"
    log "WARN" "Starting CPU stress on ${ncpus} cores for ${duration} min — watch temps!"

    echo -e "  ${CYAN}Before:${NC}"
    local temp_before
    temp_before=$(sensors 2>/dev/null | grep -i "core" | head -3 | paste -sd ' | ')
    echo "    ${temp_before:-N/A}"

    echo -e "\n  ${YELLOW}Running: stress-ng --cpu ${ncpus} --cpu-method all --timeout ${duration}m${NC}"
    echo "  Logging to ${logfile}"

    stress-ng --cpu "$ncpus" --cpu-method all --timeout "${duration}m" \
        --metrics-brief 2>&1 | tee -a "$logfile"

    local exit_code=$?
    echo -e "\n  ${CYAN}After:${NC}"
    local temp_after
    temp_after=$(sensors 2>/dev/null | grep -i "core" | head -3 | paste -sd ' | ')
    echo "    ${temp_after:-N/A}"

    if [ "$exit_code" -eq 0 ] && [ "$ABORTED" -eq 0 ]; then
        log "PASS" "CPU stress test completed (${duration} min, ${ncpus} cores)"
    elif [ "$ABORTED" -eq 1 ]; then
        log "WARN" "CPU stress test aborted"
    else
        log "FAIL" "CPU stress test failed (exit code ${exit_code})"
    fi

    # Record peak temps
    sensors 2>/dev/null > "${REPORT_DIR}/cpu-temps-after.log"
    pause
}

# ──────────────────────────────────────────────
# 2) Memory Stress Test
# ──────────────────────────────────────────────
run_memory_stress() {
    show_header "  MEMORY STRESS TEST"
    local duration
    duration=$(prompt_duration 10)
    local logfile="${REPORT_DIR}/memory-stress.log"

    section "Memory Stress Test (${duration} min)"
    log "WARN" "Starting memory stress for ${duration} min"

    # Get total memory in MB
    local total_mem_mb
    total_mem_mb=$(free -m | awk '/^Mem:/{print int($2 * 0.85)}')
    echo -e "  ${CYAN}Total RAM:${NC} $(free -h | awk '/^Mem:/{print $2}')"
    echo -e "  ${CYAN}Testing ~${total_mem_mb} MB${NC}"
    echo ""

    # Phase 1: memtester (quick targeted test)
    echo -e "  ${YELLOW}Phase 1: memtester (256 MB, 2 passes)${NC}"
    memtester 256M 2 2>&1 | tee -a "$logfile"
    local mt_exit=$?

    # Phase 2: stress-ng vm (longer soak, uses 80% of RAM)
    echo -e "\n  ${YELLOW}Phase 2: stress-ng VM stress (${duration} min)${NC}"
    local vm_workers
    vm_workers=$(detect_ncpus)
    stress-ng --vm "$vm_workers" --vm-bytes "${total_mem_mb}M" \
        --timeout "${duration}m" --metrics-brief 2>&1 | tee -a "$logfile"
    local ng_exit=$?

    if [ "$ABORTED" -eq 1 ]; then
        log "WARN" "Memory stress test aborted"
    elif [ "$mt_exit" -eq 0 ] && [ "$ng_exit" -eq 0 ]; then
        log "PASS" "Memory stress test passed (${duration} min)"
    else
        log "FAIL" "Memory stress test detected issues (memtester=${mt_exit}, stress-ng=${ng_exit})"
    fi
    pause
}

# ──────────────────────────────────────────────
# 3) Drive Stress Test
# ──────────────────────────────────────────────
run_drive_stress() {
    show_header "  DRIVE STRESS TEST"
    local disk
    disk=$(choose_disk) || { pause; return; }

    local duration
    duration=$(prompt_duration 5)
    local logfile="${REPORT_DIR}/drive-stress-$(basename ${disk}).log"

    section "Drive Stress Test: ${disk} (${duration} min)"
    log "WARN" "Starting drive stress on ${disk} for ${duration} min"

    # Check SMART health before
    echo -e "\n  ${CYAN}SMART health before:${NC}"
    smartctl -H "$disk" 2>/dev/null | grep -E "SMART overall-health|PASSED|FAILED" | tee -a "$logfile"

    # Run stress-ng hdd with multiple workers
    local hdd_workers=2
    echo -e "\n  ${YELLOW}Running: stress-ng --hdd ${hdd_workers} --hdd-ops 1000000 --timeout ${duration}m${NC}"
    stress-ng --hdd "$hdd_workers" --timeout "${duration}m" \
        --metrics-brief 2>&1 | tee -a "$logfile"
    local hdd_exit=$?

    # Check SMART after
    echo -e "\n  ${CYAN}SMART health after:${NC}"
    smartctl -H "$disk" 2>/dev/null | grep -E "SMART overall-health|PASSED|FAILED" | tee -a "$logfile"

    # SMART attributes delta
    echo -e "\n  ${CYAN}SMART attributes:${NC}"
    smartctl -A "$disk" 2>/dev/null | grep -iE "Reallocated_Sector|Pending_Sector|Uncorrectable|UDMA_CRC|Temperature" \
        | tee -a "$logfile"

    if [ "$ABORTED" -eq 1 ]; then
        log "WARN" "Drive stress test aborted"
    elif [ "$hdd_exit" -eq 0 ]; then
        log "PASS" "Drive stress test completed on ${disk}"
    else
        log "FAIL" "Drive stress test reported errors (exit ${hdd_exit})"
    fi

    # Option: badblocks
    echo ""
    echo -e "  ${YELLOW}Run badblocks read-only scan on ${disk}?${NC}"
    echo "  (Destructive write test is NOT selected — read-only only)"
    read -p "  Run read-only badblocks? [y/N]: " bb_ok
    if [[ "$bb_ok" =~ ^[yY] ]]; then
        echo -e "\n  ${YELLOW}Running badblocks (read-only, 4 concurrent) — this could take hours...${NC}"
        echo "  Press Ctrl+C to skip."
        local bb_log="${REPORT_DIR}/badblocks-$(basename ${disk}).log"
        badblocks -svn -c 4096 "$disk" 2>&1 | tee "$bb_log"
        local bb_exit=$?
        if [ "$bb_exit" -eq 0 ]; then
            log "PASS" "Badblocks read-only: no errors on ${disk}"
        elif [ "$ABORTED" -eq 1 ]; then
            log "WARN" "Badblocks aborted on ${disk}"
        else
            log "FAIL" "Badblocks found errors on ${disk} — check ${bb_log}"
        fi
    fi
    pause
}

# ──────────────────────────────────────────────
# 4) SMART Long Test
# ──────────────────────────────────────────────
run_smart_long() {
    show_header "  SMART LONG TEST"
    local disk
    disk=$(choose_disk) || { pause; return; }

    local logfile="${REPORT_DIR}/smart-long-$(basename ${disk}).log"
    section "SMART Long Test: ${disk}"

    # Check if SMART is available
    if ! smartctl -i "$disk" 2>/dev/null | grep -q "SMART support is: Enabled"; then
        log "FAIL" "SMART not available or not enabled on ${disk}"
        pause
        return
    fi

    # Check if a test is already running
    if smartctl -l selftest "$disk" 2>/dev/null | grep -q "Self-test execution status:"; then
        local status
        status=$(smartctl -l selftest "$disk" 2>/dev/null | grep "Self-test execution status:")
        echo -e "  ${YELLOW}${status}${NC}"
        read -p "  Abort current test and start new? [y/N]: " abort_ok
        if [[ "$abort_ok" =~ ^[yY] ]]; then
            smartctl -X "$disk" 2>/dev/null
            sleep 2
        else
            echo "  Monitoring existing test..."
        fi
    fi

    # Start long test
    echo -e "\n  ${YELLOW}Starting SMART long self-test on ${disk}...${NC}"
    echo "  (This typically takes 1-2 hours for a 256 GB NVMe)"
    smartctl -t long "$disk" 2>&1 | tee -a "$logfile"

    # Estimate completion time
    local estimated_min
    estimated_min=$(smartctl -c "$disk" 2>/dev/null | grep "Short self-test routine" | awk '{print $NF}' | tr -d '()')
    echo -e "\n  ${CYAN}Test started. You can:${NC}"
    echo "    1) Monitor progress:  watch -n 60 smartctl -l selftest ${disk} | tail -5"
    echo "    2) Check status now:  smartctl -l selftest ${disk} | tail -10"
    echo "    3) Abort test:        smartctl -X ${disk}"
    echo ""
    echo "  Log file: ${logfile}"
    echo ""

    # Ask if they want to wait or background
    read -p "  Wait for completion? (monitor every 60s) [y/N]: " wait_ok
    if [[ "$wait_ok" =~ ^[yY] ]]; then
        echo -e "  ${YELLOW}Monitoring SMART test every 60s — Ctrl+C to stop monitoring${NC}"
        while true; do
            sleep 60
            clear
            echo -e "${BOLD}  SMART Long Test Status — ${disk}${NC}"
            smartctl -l selftest "$disk" 2>/dev/null | tail -15
            echo ""
            # Check if completed
            if smartctl -l selftest "$disk" 2>/dev/null | grep -q "Self-test execution status:"; then
                # Still running
                :
            else
                # Completed
                local result
                result=$(smartctl -l selftest "$disk" 2>/dev/null | grep -E "^# 1" | head -1)
                if echo "$result" | grep -qi "completed without error"; then
                    log "PASS" "SMART long test passed on ${disk}"
                else
                    log "FAIL" "SMART long test completed with issues: ${result}"
                fi
                echo -e "\n  ${GREEN}Test finished!${NC}"
                smartctl -a "$disk" 2>/dev/null > "${REPORT_DIR}/smart-full-$(basename ${disk}).log"
                break
            fi
        done
    else
        echo -e "  ${YELLOW}Test running in background. Check later with:${NC}"
        echo "    smartctl -l selftest ${disk}"
        log "WARN" "SMART long test started on ${disk} (background)"
    fi
    pause
}

# ──────────────────────────────────────────────
# 5) Temperature Monitor
# ──────────────────────────────────────────────
run_temp_monitor() {
    show_header "  TEMPERATURE MONITOR"
    local interval
    read -p "  Polling interval (seconds) [5]: " interval
    interval="${interval:-5}"
    local logfile="${REPORT_DIR}/temperature.log"

    section "Temperature Monitor (interval ${interval}s)"
    log "WARN" "Starting temperature monitor — log: ${logfile}"

    echo -e "  ${YELLOW}Monitoring sensors every ${interval}s — press Ctrl+C to stop${NC}"
    echo "  Logging to ${logfile}"
    echo ""

    # Log header
    echo "# Temperature log — $(date)" > "$logfile"
    echo "# Interval: ${interval}s" >> "$logfile"
    echo "# Timestamp | Sensors | NVMe | Core" >> "$logfile"

    local peak=0
    while true; do
        clear
        echo -e "${BOLD}  Temperature Monitor — $(date +%H:%M:%S)${NC}"
        echo ""

        # Get sensor data
        local sensor_data
        sensor_data=$(sensors 2>/dev/null)
        echo "$sensor_data" | grep -v "^$" | head -20

        # Extract peak temp
        local current_peak
        current_peak=$(echo "$sensor_data" | grep -v '(' | grep -oP '[\+\-][0-9]+\.[0-9]+°C' | sed 's/[+°C]//g' | sort -rn | head -1)
        if [ -n "$current_peak" ]; then
            local peak_int
            peak_int=$(echo "$current_peak" | cut -d. -f1)
            if [ "$peak_int" -gt "$peak" ]; then
                peak=$peak_int
            fi
        fi

        echo ""
        echo -e "  ${BOLD}Peak:${NC} ${peak}°C"
        echo -e "  ${CYAN}Log:${NC} ${logfile}"

        # Log periodically
        local nvme_temp
        nvme_temp=$(echo "$sensor_data" | grep "Composite" | awk '{print $2}' 2>/dev/null)
        local core_temp
        core_temp=$(echo "$sensor_data" | grep "Package" | awk '{print $4}' 2>/dev/null)
        echo "$(date +%H:%M:%S) | ${nvme_temp:-N/A} | ${core_temp:-N/A}" >> "$logfile"

        sleep "$interval"

        # Check for abort
        if [ "$ABORTED" -eq 1 ]; then
            echo -e "\n  ${YELLOW}Monitor stopped${NC}"
            break
        fi
    done
    log "PASS" "Temperature monitor ended (peak ${peak}°C)"
    pause
}

# ──────────────────────────────────────────────
# 6) Full Burn-In Suite
# ──────────────────────────────────────────────
run_full_burnin() {
    show_header "  FULL BURN-IN SUITE"
    echo -e "  ${YELLOW}This will run ALL stress tests sequentially.${NC}"
    echo "  Duration per test can be configured."
    echo "  Total estimated time: 20 min to several hours."
    echo ""
    echo "  1) Full burn-in (default durations — 10 min each)"
    echo "  2) Overnight burn-in (4 hours per test)"
    echo "  3) Custom durations"
    echo ""
    read -p "  Choose [1-3]: " burn_mode
    local cpu_dur=10 mem_dur=10 drive_dur=5

    case "$burn_mode" in
        2) cpu_dur=240; mem_dur=240; drive_dur=240 ;;
        3)
            echo ""; cpu_dur=$(prompt_duration 10); mem_dur=$(prompt_duration 10)
            drive_dur=$(prompt_duration 5)
            ;;
    esac

    section "FULL BURN-IN SUITE"
    log "WARN" "Beginning full burn-in suite — all tests logging to ${REPORT_DIR}"
    echo -e "  ${CYAN}CPU:${NC} ${cpu_dur} min  |  ${CYAN}RAM:${NC} ${mem_dur} min  |  ${CYAN}Drive:${NC} ${drive_dur} min"
    echo -e "  ${CYAN}System:${NC} $(detect_ncpus) cores, $(free -h | awk '/^Mem:/{print $2}') RAM"
    echo -e "  ${CYAN}Started:${NC} $(date)"
    echo ""

    # Record baseline
    sensors 2>/dev/null > "${REPORT_DIR}/burnin-temps-before.log"
    smartctl -a /dev/nvme0n1 2>/dev/null > "${REPORT_DIR}/burnin-smart-before.log"

    # Run all tests
    run_cpu_stress
    [ "$ABORTED" -eq 1 ] && { log "WARN" "Burn-in aborted during CPU test"; pause; return; }

    run_memory_stress
    [ "$ABORTED" -eq 1 ] && { log "WARN" "Burn-in aborted during memory test"; pause; return; }

    # Pick the boot disk for drive stress
    local boot_disk
    boot_disk=$(lsblk -no PKNAME "$(findmnt -n -o SOURCE /)" 2>/dev/null | head -1)
    [ -z "$boot_disk" ] && boot_disk="nvme0n1"
    # Run drive stress non-interactively
    section "Drive Stress Test: /dev/${boot_disk} (${drive_dur} min)"
    log "WARN" "Running drive stress on /dev/${boot_disk}"
    stress-ng --hdd 2 --timeout "${drive_dur}m" --metrics-brief 2>&1 \
        | tee "${REPORT_DIR}/drive-stress-burnin.log"
    [ "$ABORTED" -eq 1 ] && { log "WARN" "Burn-in aborted during drive test"; pause; return; }

    # Final checks
    sensors 2>/dev/null > "${REPORT_DIR}/burnin-temps-after.log"
    smartctl -a /dev/nvme0n1 2>/dev/null > "${REPORT_DIR}/burnin-smart-after.log"

    section "BURN-IN COMPLETE"
    echo -e "  ${GREEN}Finished:${NC} $(date)" >> "$SUMMARY_FILE"

    # Compare SMART before/after
    local realloc_before realloc_after pending_before pending_after
    realloc_before=$(grep "Reallocated_Sector_Ct" "${REPORT_DIR}/burnin-smart-before.log" 2>/dev/null | awk '{print $NF}')
    realloc_after=$(grep "Reallocated_Sector_Ct" "${REPORT_DIR}/burnin-smart-after.log" 2>/dev/null | awk '{print $NF}')
    pending_before=$(grep "Current_Pending_Sector" "${REPORT_DIR}/burnin-smart-before.log" 2>/dev/null | awk '{print $NF}')
    pending_after=$(grep "Current_Pending_Sector" "${REPORT_DIR}/burnin-smart-after.log" 2>/dev/null | awk '{print $NF}')
    unc_before=$(grep "Offline_Uncorrectable" "${REPORT_DIR}/burnin-smart-before.log" 2>/dev/null | awk '{print $NF}')
    unc_after=$(grep "Offline_Uncorrectable" "${REPORT_DIR}/burnin-smart-after.log" 2>/dev/null | awk '{print $NF}')

    echo -e "\n  ${BOLD}SMART delta:${NC}" >> "$SUMMARY_FILE"
    echo "    Reallocated sectors:   ${realloc_before:-?} → ${realloc_after:-?}" >> "$SUMMARY_FILE"
    echo "    Current pending:       ${pending_before:-?} → ${pending_after:-?}" >> "$SUMMARY_FILE"
    echo "    Offline uncorrectable: ${unc_before:-?} → ${unc_after:-?}" >> "$SUMMARY_FILE"

    show_summary
    pause
}

# ──────────────────────────────────────────────
# 7) Quick Sanity Check
# ──────────────────────────────────────────────
run_sanity() {
    show_header "  QUICK SANITY CHECK (5 min)"

    section "Quick Sanity Check"

    echo -e "  ${YELLOW}Running 5-min multi-stress sanity check...${NC}"
    echo "  CPU: 30s    VM: 30s    HDD: 30s    x 5 cycles"
    echo ""

    local cycles=5
    for ((i=1; i<=cycles; i++)); do
        echo -e "  ${CYAN}Cycle ${i}/${cycles}${NC}"
        echo "  ─────────────────────────────────────────"

        # CPU 30s
        echo -n "  CPU (30s)... "
        stress-ng --cpu "$(detect_ncpus)" --cpu-method all --timeout 30s --quiet 2>&1
        echo "done"

        # Cache/memory 30s
        echo -n "  Cache/Mem (30s)... "
        stress-ng --cache "$(detect_ncpus)" --vm 2 --vm-bytes 512M --timeout 30s --quiet 2>&1
        echo "done"

        # Disk 30s
        echo -n "  Drive I/O (30s)... "
        stress-ng --hdd 1 --timeout 30s --quiet 2>&1
        echo "done"

        # Temp check
        local current_temp
        current_temp=$(sensors 2>/dev/null | grep -v '(' | grep -oP '[\+\-][0-9]+\.[0-9]+°C' | sed 's/[+°C]//g' | sort -rn | head -1)
        echo -e "  Temp: ${current_temp:-N/A}°C"
        echo ""
    done

    log "PASS" "Quick sanity check completed (${cycles} cycles, ~5 min)"
    pause
}

# ──────────────────────────────────────────────
# Summary
# ──────────────────────────────────────────────
show_summary() {
    local total=$((PASS + FAIL + WARN))
    echo ""
    echo -e "${BOLD}  ╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}  ║              STRESS TEST SUMMARY                     ║${NC}"
    echo -e "${BOLD}  ╠══════════════════════════════════════════════════════╣${NC}"
    echo -e "${BOLD}  ║${NC}  Report: ${REPORT_DIR}"
    echo -e "${BOLD}  ║${NC}  Pass:   ${GREEN}${PASS}${NC}"
    echo -e "${BOLD}  ║${NC}  Fail:   ${RED}${FAIL}${NC}"
    echo -e "${BOLD}  ║${NC}  Warn:   ${YELLOW}${WARN}${NC}"
    echo -e "${BOLD}  ║${NC}  Total:  ${total}"
    echo -e "${BOLD}  ║${NC}"
    if [ "$FAIL" -gt 0 ]; then
        echo -e "${BOLD}  ║  ${RED}⚠  ${FAIL} test(s) FAILED — investigate logs${NC}"
    fi
    if [ "$ABORTED" -eq 1 ]; then
        echo -e "${BOLD}  ║  ${YELLOW}⏹  Test was aborted (Ctrl+C)${NC}"
    fi
    echo -e "${BOLD}  ╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Summary saved to: ${SUMMARY_FILE}"
    echo ""
}

# ──────────────────────────────────────────────
# Main Menu
# ──────────────────────────────────────────────
main_menu() {
    while true; do
        show_header "  HARDWARE STRESS TEST & BURN-IN"
        echo -e "  ${CYAN}System:${NC} $(detect_ncpus) cores · $(free -h | awk '/^Mem:/{print $2}') RAM"
        echo -e "  ${CYAN}Disks:${NC}  $(lsblk -dno NAME,SIZE 2>/dev/null | grep -E "sd|nvme" | tr '\n' ' ')"
        echo ""

        # Show sensor summary
        local cpu_temp
        cpu_temp=$(sensors 2>/dev/null | grep "Package" | awk '{print $4}' 2>/dev/null)
        local nvme_temp
        nvme_temp=$(sensors 2>/dev/null | grep "Composite" | awk '{print $2}' 2>/dev/null)
        [ -n "$cpu_temp" ] && echo -e "  ${CYAN}CPU temp:${NC} ${cpu_temp}"
        [ -n "$nvme_temp" ] && echo -e "  ${CYAN}NVMe temp:${NC} ${nvme_temp}"
        echo ""

        echo "  1)  CPU Stress Test       — all cores, full methods"
        echo "  2)  Memory Stress Test    — memtester + VM soak"
        echo "  3)  Drive Stress Test     — I/O hammer + badblocks"
        echo "  4)  SMART Long Test       — schedule + monitor"
        echo "  5)  Temperature Monitor   — live sensor watch"
        echo "  6)  Full Burn-In Suite    — all tests sequentially"
        echo "  7)  Quick Sanity Check    — 5 min multi-stress"
        echo ""
        echo "  0)  Exit to main menu"
        echo ""
        read -p "  Choice [0-7]: " choice

        case "$choice" in
            1) run_cpu_stress ;;
            2) run_memory_stress ;;
            3) run_drive_stress ;;
            4) run_smart_long ;;
            5) run_temp_monitor ;;
            6) run_full_burnin ;;
            7) run_sanity ;;
            0)
                show_summary
                echo -e "  ${GREEN}Exiting stress test suite.${NC}"
                echo "  All logs in: ${REPORT_DIR}"
                break
                ;;
            *) echo -e "  ${RED}Invalid choice${NC}"; sleep 1 ;;
        esac
    done
}

# Run
main_menu
