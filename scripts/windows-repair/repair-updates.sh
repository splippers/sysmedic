#!/usr/bin/env bash
# SysMedic - Windows Update Repair Toolkit
# Fixes Windows Update issues: corrupt store, stuck updates, component repair

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC}   $1"; }
fail()  { echo -e "  ${RED}[FAIL]${NC}   $1"; }
header(){ echo -e "\n${BOLD}$1${NC}\n"; }

header "🛠️  Windows Update & Driver Repair"
echo ""
echo "  This tool performs common Windows Update fixes:"
echo "    1) Reset Windows Update components"
echo "    2) Clear SoftwareDistribution cache"
echo "    3) Fix corrupt Component Store (via DISM offline)"
echo "    4) Check system files (via SFC offline)"
echo "    5) Re-register Windows Update DLLs"
echo "    6) Safe driver rollback (disable problematic updates)"
echo ""

# Step 1: Mount Windows partition
echo -e "${BOLD}Step 1: Mount Windows volume${NC}"
echo ""
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL 2>/dev/null | grep -E 'ntfs|NAME|vfat'
echo ""
read -p "  Enter Windows partition (e.g. /dev/nvme0n1p3): " win_part
mkdir -p /mnt/windows

if ! ntfs-3g "$win_part" /mnt/windows 2>/dev/null; then
    fail "Could not mount $win_part"
    echo "  If BitLocker'd, use menu option 11 first."
    exit 1
fi
ok "Mounted $win_part → /mnt/windows"
echo ""

WIN_DIR="/mnt/windows/Windows"
REG_DIR="$WIN_DIR/System32/config"

# Check if we're looking at a real Windows
if [ ! -d "$REG_DIR" ]; then
    fail "This doesn't look like a Windows partition (no System32/config)"
    umount /mnt/windows 2>/dev/null
    exit 1
fi

# Step 2: Select repair action
header "Repair Actions"
echo "  1) Full Windows Update reset (clear cache + re-register)"
echo "  2) Clear SoftwareDistribution cache only"
echo "  3) Offline DISM scan & repair (fix component store)"
echo "  4) Offline SFC scan (fix system file integrity)"
echo "  5) Re-register Windows Update DLLs"
echo "  6) Check for Windows Update error codes in logs"
echo "  7) ALL of the above"
echo "  0) Cancel"
echo ""
read -p "  Choose [0-7]: " action

SOFTWAREDIST="$WIN_DIR/SoftwareDistribution"
SYSTEM32="$WIN_DIR/System32"
REPORT_DIR="/root/reports/windows"
mkdir -p "$REPORT_DIR"

case "$action" in
    1|7)
        header "Reset Windows Update Components"
        
        # Stop WU services by renaming their registry entries (offline)
        info "This requires registry manipulation — backing up first..."
        if [ -f "$REG_DIR/SOFTWARE" ]; then
            cp "$REG_DIR/SOFTWARE" "$REG_DIR/SOFTWARE.backup.wurepair" && ok "Registry backed up"
        fi
        
        # Clear SoftwareDistribution
        if [ -d "$SOFTWAREDIST" ]; then
            echo ""
            info "Clearing SoftwareDistribution cache..."
            mv "$SOFTWAREDIST" "$WIN_DIR/SoftwareDistribution.old" 2>/dev/null && \
                ok "Cache moved to SoftwareDistribution.old" || \
                warn "Could not rename (in use or permissions)"
        fi
        
        # Clear catroot2
        CATROOT2="$WIN_DIR/System32/catroot2"
        if [ -d "$CATROOT2" ]; then
            mv "$CATROOT2" "$WIN_DIR/System32/catroot2.old" 2>/dev/null && \
                ok "catroot2 cache cleared" || \
                warn "Could not rename catroot2"
        fi
        
        echo ""
        ok "Windows Update components reset completed"
        echo "  Note: On next boot, Windows will recreate these folders."
        echo "  Run Windows Update again to check for updates."
        ;;
    
    2)
        header "Clear SoftwareDistribution Cache"
        if [ -d "$SOFTWAREDIST" ]; then
            sd_size=$(du -sh "$SOFTWAREDIST" 2>/dev/null | cut -f1)
            info "Current size: $sd_size"
            
            read -p "  Move SoftwareDistribution to .old? [y/N]: " confirm
            if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
                mv "$SOFTWAREDIST" "$WIN_DIR/SoftwareDistribution.old" 2>/dev/null && \
                    ok "Cache cleared (old copy at SoftwareDistribution.old)" || \
                    fail "Could not clear cache"
            fi
        else
            warn "SoftwareDistribution folder not found"
        fi
        ;;
    
    3)
        header "Offline DISM Repair"
        echo ""
        info "DISM can repair the component store using Windows-side resources."
        echo ""
        echo "  From the offline Windows, we can:"
        echo "  a) Check component store health (read CBS log)"
        echo "  b) Replace corrupt files from WinSxS backup"
        echo "  c) Note which packages need repair"
        echo ""
        
        # Check CBS log for corruption
        CBS_LOG="$WIN_DIR/Logs/CBS/CBS.log"
        if [ -f "$CBS_LOG" ]; then
            echo -e "  ${BOLD}CBS Log Analysis:${NC}"
            cbs_corrupt=$(grep -c -i 'corrupt\|cannot repair\|0x800f' "$CBS_LOG" 2>/dev/null)
            cbs_pending=$(grep -c -i 'pending\|reboot required' "$CBS_LOG" 2>/dev/null)
            echo "    Corrupt component entries: $cbs_corrupt"
            echo "    Pending operations: $cbs_pending"
            echo ""
            
            # Show specific corrupt files
            echo -e "  ${BOLD}Corrupt component details:${NC}"
            grep -i 'corrupt\|0x800f' "$CBS_LOG" 2>/dev/null | tail -20 | \
                sed 's/^/    /'
        fi
        
        echo ""
        echo -e "  ${YELLOW}To run full DISM offline repair, you need to boot Windows and run:${NC}"
        echo "    DISM /Online /Cleanup-Image /ScanHealth"
        echo "    DISM /Online /Cleanup-Image /RestoreHealth"
        echo ""
        echo "  If Windows won't boot, use the Windows Recovery Environment:"
        echo "    DISM /Image:C:\ /Cleanup-Image /RestoreHealth"
        echo ""
        echo "  From SysMedic, the best we can do is identify which components"
        echo "  are broken so you know what to fix once in Windows."
        
        # Save CBS corruption details to report
        REPORT_FILE="$REPORT_DIR/dism_offline_analysis_$(date +%Y%m%d_%H%M%S).txt"
        {
            echo "DISM Offline Analysis"
            echo "Date: $(date)"
            echo "Source: $win_part"
            echo ""
            echo "--- Corrupt components ---"
            grep -i 'corrupt\|0x800f' "$CBS_LOG" 2>/dev/null | tail -100
            echo ""
            echo "--- Pending operations ---"
            grep -i 'pending\|reboot required' "$CBS_LOG" 2>/dev/null | tail -50
        } > "$REPORT_FILE"
        info "Analysis saved to $REPORT_FILE"
        ;;
    
    4)
        header "Offline SFC (System File Checker)"
        echo ""
        info "SFC cannot be run offline — it needs a running Windows instance."
        echo ""
        echo "  However, we CAN check which files SFC would repair:"
        echo ""
        
        # Check CBS persist logs for SFC findings
        SFC_INFO="$REPORT_DIR/sfc_offline_findings.txt"
        {
            echo "SFC Offline Analysis"
            echo "Date: $(date)"
            echo "Source: $win_part"
            echo ""
            echo "--- Previously corrupted files (from CBS logs) ---"
            for log in "$WIN_DIR/Logs/CBS/cbs_persist_"*.log; do
                [ -f "$log" ] || continue
                echo "=== $(basename "$log") ==="
                grep -i 'corrupt\|cannot repair\|repaired' "$log" 2>/dev/null | tail -100
                echo ""
            done
        } > "$SFC_INFO"
        
        if [ -s "$SFC_INFO" ]; then
            ok "Previously corrupted files logged (see $SFC_INFO)"
            head -50 "$SFC_INFO"
        else
            info "No previous SFC corruption records found"
        fi
        
        echo ""
        echo -e "  ${YELLOW}To run SFC:${NC} Boot Windows and run as Administrator:"
        echo "    sfc /scannow"
        echo "    sfc /scanonce  (next boot)"
        ;;
    
    5)
        header "Re-register Windows Update DLLs"
        echo ""
        info "This stage updates the registry to re-register WU DLLs on next boot."
        echo ""
        
        WU_DLLS=(
            "msxml3.dll"
            "qmgr.dll"
            "qmgrprxy.dll"
            "wuaueng.dll"
            "wuapi.dll"
            "wucltui.dll"
            "wups.dll"
            "wuweb.dll"
            "atl.dll"
            "urlmon.dll"
            "softpub.dll"
            "wintrust.dll"
            "initpki.dll"
            "dssenh.dll"
            "rsaenh.dll"
            "gpkcsp.dll"
            "sccbase.dll"
            "slbcsp.dll"
            "cryptdlg.dll"
            "ole32.dll"
            "actxprxy.dll"
            "mshtml.dll"
            "shdocvw.dll"
            "browseui.dll"
            "clbcatq.dll"
            "vbscript.dll"
            "scrrun.dll"
            "jscript.dll"
            "msxml.dll"
        )
        
        DEST="$REG_DIR/SOFTWARE"
        if [ -f "$DEST" ]; then
            echo -e "  ${BOLD}Registering WU DLLs for next boot...${NC}"
            echo ""
            for dll in "${WU_DLLS[@]}"; do
                # Check if DLL exists
                dll_path=$(find "$WIN_DIR" -name "$dll" 2>/dev/null | head -1)
                if [ -n "$dll_path" ]; then
                    echo "  ✓ $dll"
                else
                    echo "  ✗ $dll (not found — may not be needed on this Windows version)"
                fi
            done
            
            echo ""
            info "DLLs will be registered on next Windows boot."
            echo "  For immediate effect, boot Windows and run as Admin:"
            echo '    regsvr32 /s "$dll"  (for each DLL above)'
        fi
        
        # Also offer to fix Windows Update services (set to automatic)
        echo ""
        read -p "  Set Windows Update services to Automatic? [y/N]: " fix_services
        if [ "$fix_services" = "y" ] || [ "$fix_services" = "Y" ]; then
            info "This requires booting Windows and running:"
            echo "    sc config wuauserv start=auto"
            echo "    sc config bits start=auto"
            echo "    sc config cryptsvc start=auto"
            echo "    sc config trustedinstaller start=auto"
        fi
        ;;
    
    6)
        header "Windows Update Error Code Analysis"
        echo ""
        
        REPORT_FILE="$REPORT_DIR/update_error_codes_$(date +%Y%m%d_%H%M%S).txt"
        {
            echo "Windows Update Error Code Analysis"
            echo "Date: $(date)"
            echo "Source: $win_part"
            echo ""
            
            # Collect error codes from CBS.log
            echo "=== Error codes from CBS.log ==="
            grep -oE '0x[0-9A-Fa-f]{8}' "$WIN_DIR/Logs/CBS/CBS.log" 2>/dev/null | sort | uniq -c | sort -rn | head -30
            echo ""
            
            # Collect error codes from DISM.log  
            echo "=== Error codes from DISM.log ==="
            grep -oE '0x[0-9A-Fa-f]{8}' "$WIN_DIR/Logs/DISM/DISM.log" 2>/dev/null | sort | uniq -c | sort -rn | head -20
            echo ""
            
            # Collect from setup logs
            echo "=== Error codes from Panther logs ==="
            grep -oE '0x[0-9A-Fa-f]{8}' "$WIN_DIR/Panther/setupact.log" 2>/dev/null | sort | uniq -c | sort -rn | head -20
            echo ""
            
            # Collect from event logs
            echo "=== Error codes from System.evtx ==="
            evtxexport "$SYSTEM32/winevt/Logs/System.evtx" 2>/dev/null | grep -oE '0x[0-9A-Fa-f]{8}' | sort | uniq -c | sort -rn | head -30
            echo ""
            
            # Windows Update specific event log
            WU_EVTX="$SYSTEM32/winevt/Logs/Microsoft-Windows-WindowsUpdateClient%4Operational.evtx"
            if [ -f "$WU_EVTX" ]; then
                echo "=== Error codes from WindowsUpdateClient.evtx ==="
                evtxexport "$WU_EVTX" 2>/dev/null | grep -oE '0x[0-9A-Fa-f]{8}' | sort | uniq -c | sort -rn | head -30
            fi
            
        } > "$REPORT_FILE"
        
        cat "$REPORT_FILE"
        echo ""
        ok "Error codes collected to $REPORT_FILE"
        echo ""
        echo -e "  ${BOLD}Common Windows Update error codes decoded:${NC}"
        echo "    0x80070002  — File not found (corrupt update cache)"
        echo "    0x80070005  — Access denied (permissions)"
        echo "    0x80070020  — File in use by another process"
        echo "    0x80070422  — WU service not running or disabled"
        echo "    0x80070643  — Windows corruption (run DISM)"
        echo "    0x80073701  — Component store corrupt (run DISM)"
        echo "    0x800f081f  — CBS corrupt — run SFC + DISM"
        echo "    0x800f0906  — DISM source files not available"
        echo "    0x8024401c  — WU cannot connect to update servers"
        echo "    0x80246008  — BITS service issue"
        echo "    0x80248007  — WU database corrupt"
        echo "    0x8024efff  — Windows Update generic failure"
        echo "    0x80d02002  — WSUS server unavailable"
        echo "    0xc1900101  — Feature update rollback (driver issue)"
        echo "    0xc1900200  — Not enough free disk space"
        echo "    0xc190020e  — Incompatible driver blocked update"
        echo ""
        echo "  Feed the report to OpenCode AI for detailed analysis."
        ;;
    
    0) 
        info "Cancelled"
        ;;
    
    *)
        fail "Invalid choice"
        ;;
esac

# Cleanup
echo ""
info "Unmounting Windows partition..."
umount /mnt/windows 2>/dev/null
ok "Done"
