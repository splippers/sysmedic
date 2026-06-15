#!/usr/bin/env bash
# SysMedic - Windows Diagnostic Toolkit
# Reads & analyzes Windows logs for Update failures and BSOD analysis

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC}   $1"; }
fail()  { echo -e "  ${RED}[FAIL]${NC}   $1"; }
header(){ echo -e "\n${BOLD}$1${NC}\n"; }

REPORT_DIR="/root/reports/windows"
mkdir -p "$REPORT_DIR"

header "🪟 Windows Diagnostic Collection"
echo "  This will mount your Windows partition and collect:
  • Windows Update logs (CBS, DISM, WindowsUpdate)
  • BSOD/crash dump information
  • System & Application Event Logs (EVTX)
  • Driver status and problem devices
  • Recent error events
  The report will be saved for AI analysis.
"

# Step 1: Find Windows partition
echo -e "${BOLD}Step 1: Locate Windows volume${NC}"
echo ""
echo "Available partitions:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL 2>/dev/null | grep -E 'ntfs|NAME|vfat'
echo ""

read -p "  Enter Windows partition (e.g. /dev/nvme0n1p3): " win_part
mkdir -p /mnt/windows

echo ""
if ! ntfs-3g -o ro "$win_part" /mnt/windows 2>/dev/null; then
    fail "Could not mount $win_part — is it BitLocker'd?"
    echo "  Use menu option 11 (BitLocker Unlock) first, then re-run this."
    exit 1
fi
ok "Mounted $win_part → /mnt/windows (read-only)"
echo ""

# Step 2: Collect basic system info from registry
header "Step 2: System Information"
WIN_DIR="/mnt/windows/Windows"
SYSTEM32="$WIN_DIR/System32"
REG_DIR="$WIN_DIR/System32/config"
REPORT_FILE="$REPORT_DIR/windows_diagnostic_$(date +%Y%m%d_%H%M%S).txt"

{
echo "=============================================="
echo "  Windows Diagnostic Report"
echo "  Generated: $(date)"
echo "  Source: $win_part"
echo "=============================================="
echo ""

# Try to get Windows version from Software hive
if [ -f "$REG_DIR/SOFTWARE" ]; then
    echo "--- Windows Version ---"
    chntpw -e "$REG_DIR/SOFTWARE" 2>/dev/null | grep -i -E 'CurrentVersion|CurrentBuild|EditionID|ProductName' | head -10
    echo ""
fi
} > "$REPORT_FILE"

cat "$REPORT_FILE"
echo ""

# Step 3: Windows Update Logs
header "Step 3: Windows Update Logs"
UPDATE_LOGS=""
{
echo "=============================================="
echo "  WINDOWS UPDATE LOGS"
echo "=============================================="
echo ""
} >> "$REPORT_FILE"

# CBS.log
CBS_LOG="$WIN_DIR/Logs/CBS/CBS.log"
if [ -f "$CBS_LOG" ]; then
    cbs_size=$(stat -c%s "$CBS_LOG" 2>/dev/null)
    cbs_lines=$(wc -l < "$CBS_LOG" 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} CBS.log: ${cbs_size} bytes, ${cbs_lines} lines"
    
    # Extract errors and failures
    echo "--- CBS.log: Errors & Failures (last 200 entries) ---" >> "$REPORT_FILE"
    grep -i -E 'error|fail|corrupt|0x8007|0x8024|0x800f|0x80073' "$CBS_LOG" 2>/dev/null | tail -200 >> "$REPORT_FILE" 2>/dev/null
    echo "" >> "$REPORT_FILE"
    
    # Get the last 50 lines for recent activity
    echo "--- CBS.log: Last 50 lines ---" >> "$REPORT_FILE"
    tail -50 "$CBS_LOG" >> "$REPORT_FILE" 2>/dev/null
    echo "" >> "$REPORT_FILE"
    
    # Summary
    cbs_errors=$(grep -c -i 'error' "$CBS_LOG" 2>/dev/null)
    cbs_fails=$(grep -c -i 'failed' "$CBS_LOG" 2>/dev/null)
    echo "  CBS.log: $cbs_errors errors, $cbs_fails failures found"
    UPDATE_LOGS="yes"
else
    warn "CBS.log not found"
    echo "--- CBS.log: NOT FOUND ---" >> "$REPORT_FILE"
fi

# DISM log
DISM_LOG="$WIN_DIR/Logs/DISM/DISM.log"
if [ -f "$DISM_LOG" ]; then
    dism_size=$(stat -c%s "$DISM_LOG" 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} DISM.log: ${dism_size} bytes"
    
    echo "" >> "$REPORT_FILE"
    echo "--- DISM.log: Errors & Warnings ---" >> "$REPORT_FILE"
    grep -i -E 'error|fail|corrupt|0x8007|0x8024|0x800f' "$DISM_LOG" 2>/dev/null | tail -100 >> "$REPORT_FILE" 2>/dev/null
    echo "" >> "$REPORT_FILE"
    
    dism_errors=$(grep -c -i 'error' "$DISM_LOG" 2>/dev/null)
    echo "  DISM.log: $dism_errors errors found"
    UPDATE_LOGS="yes"
else
    warn "DISM.log not found"
fi

# WindowsUpdate.log (legacy location)
WU_LOG="$WIN_DIR/WindowsUpdate.log"
if [ -f "$WU_LOG" ]; then
    wu_size=$(stat -c%s "$WU_LOG" 2>/dev/null)
    echo -e "  ${GREEN}✓${NC} WindowsUpdate.log: ${wu_size} bytes"
    
    echo "" >> "$REPORT_FILE"
    echo "--- WindowsUpdate.log: Errors & Failures ---" >> "$REPORT_FILE"
    grep -i -E 'error|fail|0x8024|0x8007|0x800f' "$WU_LOG" 2>/dev/null | tail -100 >> "$REPORT_FILE" 2>/dev/null
    
    UPDATE_LOGS="yes"
else
    # Modern Windows uses .dat or .etl files
    for wu_file in "$WIN_DIR/Logs/WindowsUpdate/"*.etl "$WIN_DIR/Logs/WindowsUpdate/"*.dat; do
        [ -f "$wu_file" ] && echo -e "  ${GREEN}✓${NC} $(basename $wu_file) (binary trace log)" && UPDATE_LOGS="yes"
    done
fi

# Setup log (Panther)
PANTHER_LOG="$WIN_DIR/Panther/setupact.log"
if [ -f "$PANTHER_LOG" ]; then
    echo -e "  ${GREEN}✓${NC} setupact.log (Panther)"
    
    echo "" >> "$REPORT_FILE"
    echo "--- setupact.log (Panther): Last 100 lines ---" >> "$REPORT_FILE"
    tail -100 "$PANTHER_LOG" >> "$REPORT_FILE" 2>/dev/null
    echo "" >> "$REPORT_FILE"
    
    # Check for upgrade failures
    grep -i -E 'error|fail|rollback|0x8007|0x8024|0x800f' "$PANTHER_LOG" 2>/dev/null | tail -50 >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    UPDATE_LOGS="yes"
fi

# Windows Update client operational log (.evtx)
WU_EVTX="$SYSTEM32/winevt/Logs/Microsoft-Windows-WindowsUpdateClient%4Operational.evtx"
if [ -f "$WU_EVTX" ]; then
    echo -e "  ${GREEN}✓${NC} Windows Update Client operational log (EVTX)"
    evtx_out="$REPORT_DIR/windows_update_events.txt"
    evtxexport "$WU_EVTX" 2>/dev/null | grep -i -E 'error|fail|0x80|installed successfully|installation failure' | tail -100 > "$evtx_out" 2>/dev/null
    
    if [ -s "$evtx_out" ]; then
        echo "" >> "$REPORT_FILE"
        echo "--- Windows Update Events (from EVTX) ---" >> "$REPORT_FILE"
        cat "$evtx_out" >> "$REPORT_FILE"
    fi
    UPDATE_LOGS="yes"
fi

if [ -z "$UPDATE_LOGS" ]; then
    echo "  ${YELLOW}No Windows Update logs found${NC}"
fi
echo ""

# Step 4: BSOD / Crash Dump Analysis
header "Step 4: BSOD & Crash Dump Analysis"
{
echo "=============================================="
echo "  BSOD / CRASH DUMP ANALYSIS"
echo "=============================================="
echo ""
} >> "$REPORT_FILE"

# Minidumps
MINIDUMP_DIR="$WIN_DIR/Minidump"
if [ -d "$MINIDUMP_DIR" ]; then
    dmp_count=$(ls "$MINIDUMP_DIR"/*.dmp 2>/dev/null | wc -l)
    if [ "$dmp_count" -gt 0 ]; then
        echo -e "  ${RED}${dmp_count} minidump(s) found${NC} — system has crashed!"
        
        echo "--- Minidump Files ---" >> "$REPORT_FILE"
        for dmp in "$MINIDUMP_DIR"/*.dmp; do
            dmp_name=$(basename "$dmp")
            dmp_size=$(stat -c%s "$dmp" 2>/dev/null)
            dmp_date=$(stat -c%y "$dmp" 2>/dev/null | cut -d. -f1)
            echo "  $dmp_name  ($dmp_size bytes)  $dmp_date"
        done >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
        
        # Extract readable strings from minidumps (BugCheck codes, driver names)
        echo "--- BugCheck codes & driver names from minidumps (strings) ---" >> "$REPORT_FILE"
        for dmp in "$MINIDUMP_DIR"/*.dmp; do
            echo "=== $(basename "$dmp") ===" >> "$REPORT_FILE"
            strings "$dmp" 2>/dev/null | grep -i -E \
                'bugcheck|DRIVER_|PAGE_FAULT|IRQL|KMODE|SYSTEM_SERVICE|NTFS|FATAL|PFN_LIST|CORRUPT|CRITICAL|DPC_WATCHDOG|KERNEL_SECURITY|BAD_POOL|MEMORY_MANAGEMENT|UNEXPECTED_KERNEL|CLOCK_WATCHDOG|MACHINE_CHECK|VIDEO_TDR|THREAD_STUCK|SYSTEM_THREAD|HAL_INITIALIZATION|driver|\.sys|ntoskrnl|win32k|dxgkrnl|nvlddmkm|igfx|atikmdag|rtwlan|e1d65x|netwlv' \
                2>/dev/null | head -100 >> "$REPORT_FILE"
        done
        echo "" >> "$REPORT_FILE"
        
        # Show minidump dates for timeline
        echo "--- Crash Timeline ---" >> "$REPORT_FILE"
        ls -la "$MINIDUMP_DIR"/*.dmp 2>/dev/null | awk '{print $6, $7, $8}' >> "$REPORT_FILE"
        echo "" >> "$REPORT_FILE"
    else
        echo -e "  ${GREEN}✓${NC} No minidumps (clean)"
        echo "--- No minidumps found ---" >> "$REPORT_FILE"
    fi
else
    warn "Minidump directory not found"
    echo "--- Minidump directory not found ---" >> "$REPORT_FILE"
fi

# MEMORY.DMP
MEMORY_DMP="$WIN_DIR/MEMORY.DMP"
if [ -f "$MEMORY_DMP" ]; then
    mem_size=$(du -h "$MEMORY_DMP" 2>/dev/null | cut -f1)
    echo -e "  ${RED}MEMORY.DMP found${NC} (${mem_size}) — full kernel crash dump"
    echo "" >> "$REPORT_FILE"
    echo "--- MEMORY.DMP: Full memory dump ---" >> "$REPORT_FILE"
    echo "  Size: $mem_size" >> "$REPORT_FILE"
    echo "  Date: $(stat -c%y "$MEMORY_DMP" 2>/dev/null | cut -d. -f1)" >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
    
    # Extract crash info from MEMORY.DMP
    echo "--- BugCheck info from MEMORY.DMP ---" >> "$REPORT_FILE"
    strings "$MEMORY_DMP" 2>/dev/null | grep -i -E \
        'bugcheck|0x00000[0-9a-fA-F]|DRIVER_IRQL|KMODE_EXCEPTION|SYSTEM_SERVICE|PFN_LIST|BAD_POOL|DPC_WATCHDOG|KERNEL_SECURITY' \
        2>/dev/null | head -50 >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
else
    echo -e "  ${GREEN}✓${NC} No MEMORY.DMP"
fi

# LiveKernelReports
LKR_DIR="$WIN_DIR/LiveKernelReports"
if [ -d "$LKR_DIR" ]; then
    lkr_count=$(find "$LKR_DIR" -name '*.dmp' 2>/dev/null | wc -l)
    if [ "$lkr_count" -gt 0 ]; then
        echo -e "  ${YELLOW}${lkr_count} LiveKernelReport(s) found${NC}"
        echo "" >> "$REPORT_FILE"
        echo "--- LiveKernelReports ---" >> "$REPORT_FILE"
        find "$LKR_DIR" -name '*.dmp' 2>/dev/null -exec ls -la {} \; >> "$REPORT_FILE"
    else
        echo -e "  ${GREEN}✓${NC} No LiveKernelReports"
    fi
fi
echo ""

# Step 5: Event Log Analysis (.evtx)
header "Step 5: Event Log Analysis"
{
echo "=============================================="
echo "  EVENT LOG ANALYSIS (EVTX)"
echo "=============================================="
echo ""
} >> "$REPORT_FILE"

EVTX_DIR="$SYSTEM32/winevt/Logs"
parse_evtx_errors() {
    local evtx_file="$1"
    local label="$2"
    local outfile="$3"
    
    if [ ! -f "$evtx_file" ]; then
        return
    fi
    
    echo -e "  ${GREEN}✓${NC} Parsing $label..."
    
    # Use evtxexport to dump and grep for errors
    {
        echo "--- ${label} : Critical/Error Events ---"
        evtxexport "$evtx_file" 2>/dev/null | grep -i -E \
            'Level="2"|Level="1"|Error|Critical|BugCheck|0x00000[0-9a-fA-F]|failed|unexpected shutdown|previous shutdown' \
            2>/dev/null | head -200
        echo ""
    } >> "$outfile"
}

# System event log — most important for BSODs
parse_evtx_errors "$EVTX_DIR/System.evtx" "System Event Log (BSODs, hardware failures)" "$REPORT_FILE"

# Application event log
parse_evtx_errors "$EVTX_DIR/Application.evtx" "Application Event Log (app crashes)" "$REPORT_FILE"

# Windows Update client
parse_evtx_errors "$EVTX_DIR/Microsoft-Windows-WindowsUpdateClient%4Operational.evtx" "Windows Update Client Operational" "$REPORT_FILE"

# Windows Update client (alternative name)
if [ ! -f "$EVTX_DIR/Microsoft-Windows-WindowsUpdateClient%4Operational.evtx" ]; then
    for wu_evtx in "$EVTX_DIR"/WindowsUpdate*.evtx; do
        [ -f "$wu_evtx" ] && parse_evtx_errors "$wu_evtx" "$(basename $wu_evtx)" "$REPORT_FILE"
    done
fi

# Step 6: Driver health check
header "Step 6: Driver Health"
{
echo "=============================================="
echo "  DRIVER STATUS"
echo "=============================================="
echo ""
} >> "$REPORT_FILE"

# Check driver store
DRV_STORE="$WIN_DIR/System32/DriverStore/FileRepository"
if [ -d "$DRV_STORE" ]; then
    drv_count=$(ls "$DRV_STORE" 2>/dev/null | wc -l)
    echo -e "  ${GREEN}✓${NC} Driver store: $drv_count packages"
    echo "  Driver store: $drv_count packages" >> "$REPORT_FILE"
fi

# Check for known problematic drivers (alphabetical list)
echo "" >> "$REPORT_FILE"
echo "--- Known problematic drivers (checking for presence) ---" >> "$REPORT_FILE"
problem_drivers=(
    "nvlddmkm.sys"    # NVIDIA — top BSOD cause
    "dxgkrnl.sys"     # DirectX graphics kernel
    "igdkmd64.sys"    # Intel graphics
    "atikmdag.sys"    # AMD graphics
    "rtwlan.sys"      # Realtek wireless
    "e1d65x64.sys"    # Intel Ethernet
    "netwlv64.sys"    # Intel Wireless
    "bcmwl63a.sys"    # Broadcom wireless
    "dumpfve.sys"     # BitLocker crash dump
    "tcpip.sys"       # Networking stack
    "ntoskrnl.exe"    # NT Kernel (blamed in many BSODs — usually not the real cause)
)
for drv in "${problem_drivers[@]}"; do
    found=$(find "$WIN_DIR" -name "$drv" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        drv_path="${found#/mnt/windows/}"
        echo "  Present: $drv_path" >> "$REPORT_FILE"
    fi
done

# Check for driver signing issues
if [ -f "$CBS_LOG" ]; then
    echo "" >> "$REPORT_FILE"
    echo "--- Driver signing errors in CBS.log ---" >> "$REPORT_FILE"
    grep -i 'driver.*signing\|signature.*failed\|catalog.*error' "$CBS_LOG" 2>/dev/null | tail -30 >> "$REPORT_FILE"
fi

# Step 7: Check software distribution / update cache
header "Step 7: Windows Update Cache Status"
{
echo "=============================================="
echo "  WINDOWS UPDATE CACHE"
echo "=============================================="
echo ""
} >> "$REPORT_FILE"

SOFTWAREDIST="$WIN_DIR/SoftwareDistribution"
if [ -d "$SOFTWAREDIST" ]; then
    sd_size=$(du -sh "$SOFTWAREDIST" 2>/dev/null | cut -f1)
    echo -e "  ${GREEN}✓${NC} SoftwareDistribution: ${sd_size}"
    echo "  SoftwareDistribution size: $sd_size" >> "$REPORT_FILE"
    
    # Check download folder
    if [ -d "$SOFTWAREDIST/Download" ]; then
        dl_count=$(ls "$SOFTWAREDIST/Download" 2>/dev/null | wc -l)
        dl_size=$(du -sh "$SOFTWAREDIST/Download" 2>/dev/null | cut -f1)
        echo "  Pending downloads: $dl_count items ($dl_size)" >> "$REPORT_FILE"
    fi
    
    # Check for corrupt datastore
    if [ -f "$SOFTWAREDIST/DataStore/DataStore.edb" ]; then
        ds_size=$(stat -c%s "$SOFTWAREDIST/DataStore/DataStore.edb" 2>/dev/null)
        echo "  DataStore.edb: $ds_size bytes" >> "$REPORT_FILE"
    fi
else
    echo "  SoftwareDistribution folder not found" >> "$REPORT_FILE"
fi

# Step 8: Collect SFC info
header "Step 8: System File Checker Info"
{
echo "=============================================="
echo "  SYSTEM FILE CHECKER (SFC)"
echo "=============================================="
echo ""
} >> "$REPORT_FILE"

SFC_LOG="$WIN_DIR/Logs/CBS/cbs_persist_*.log"
for log in "$WIN_DIR/Logs/CBS/cbs_persist_"*.log; do
    [ -f "$log" ] || continue
    echo -e "  ${GREEN}✓${NC} $(basename "$log")"
    echo "--- $(basename "$log"): Corrupt files ---" >> "$REPORT_FILE"
    grep -i 'corrupt\|cannot repair\|0x800f' "$log" 2>/dev/null | tail -50 >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
done

# Step 9: Check for pending reboot
header "Step 9: Pending Operations"
{
echo "=============================================="
echo "  PENDING REBOOT & OPERATIONS"
echo "=============================================="
echo ""
} >> "$REPORT_FILE"

# Check for PendingFileRenameOperations in the registry files
if [ -f "$REG_DIR/SYSTEM" ]; then
    echo "--- Pending rename operations (from registry) ---" >> "$REPORT_FILE"
    # Use chntpw to extract
    chntpw -e "$REG_DIR/SYSTEM" 2>/dev/null | grep -A 20 'PendingFileRenameOperations' | head -30 >> "$REPORT_FILE" 2>/dev/null
    echo "" >> "$REPORT_FILE"
fi

# Check for Update Pending
UPDATE_PENDING="$WIN_DIR/WinSxS/pending.xml"
if [ -f "$UPDATE_PENDING" ]; then
    echo -e "  ${YELLOW}⚠  Pending update operations found (pending.xml)${NC}"
    echo "  Pending.xml exists — updates are staged but need reboot" >> "$REPORT_FILE"
fi

# --- Generate Summary ---
echo ""
header "═══════════════════════════════════"
header "  DIAGNOSTIC SUMMARY"
header "═══════════════════════════════════"

echo "" >> "$REPORT_FILE"
echo "==============================================" >> "$REPORT_FILE"
echo "  DIAGNOSTIC SUMMARY" >> "$REPORT_FILE"
echo "==============================================" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

# Count issues found
{
echo "Findings:"
echo ""

# BSOD check
if [ "$dmp_count" -gt 0 ] 2>/dev/null; then
    echo "🔴 BSOD CRASHES: $dmp_count minidump(s) found — system has experienced crashes"
    echo "  • Check System event log for BugCheck codes"
    echo "  • Minidump dates:"
    ls "$MINIDUMP_DIR"/*.dmp 2>/dev/null | while read dmp; do
        echo "    - $(basename "$dmp"): $(stat -c%y "$dmp" 2>/dev/null | cut -d. -f1)"
    done
    echo ""
fi

# CBS errors
if [ -n "$cbs_errors" ] && [ "$cbs_errors" -gt 0 ] 2>/dev/null; then
    echo "🟡 WINDOWS UPDATE (CBS): $cbs_errors errors, $cbs_fails failures"
    echo ""
fi

# DISM errors
if [ -n "$dism_errors" ] && [ "$dism_errors" -gt 0 ] 2>/dev/null; then
    echo "🟡 DISM: $dism_errors errors in log"
    echo ""
fi

# Pending updates
if [ -f "$UPDATE_PENDING" ]; then
    echo "🟡 PENDING: Updates staged, reboot pending"
    echo "  • A reboot is required to complete update installation"
    echo ""
fi

echo "Report file: $REPORT_FILE"
echo "OpenCode can analyze this report for error codes and solutions."
} | tee -a "$REPORT_FILE"

# Final message
echo ""
info "Full diagnostic report saved to:"
echo "  $REPORT_FILE"
echo ""
echo -e "  ${BOLD}To analyze errors with AI, type in the chat:${NC}"
echo "    Read and analyze: $REPORT_FILE"

# Offer to display the report
read -p "  Display report now? [y/N]: " show_report
if [ "$show_report" = "y" ] || [ "$show_report" = "Y" ]; then
    less "$REPORT_FILE"
fi

# Cleanup
echo ""
info "Unmounting Windows partition..."
umount /mnt/windows 2>/dev/null && ok "Unmounted $win_part"
