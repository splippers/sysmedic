#!/usr/bin/env bash
# SysMedic - Repair macOS Volumes (HFS+ & APFS)
# Runs fsck on HFS+ or apfsck on APFS volumes

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC}   $1"; }
fail()  { echo -e "  ${RED}[FAIL]${NC}   $1"; }
header(){ echo -e "\n${BOLD}$1${NC}\n"; }

header "macOS Volume Repair"
echo ""

# --- HFS+ Repair ---
header "HFS+ Check & Repair"
found=0
for dev in $(lsblk -nro NAME,FSTYPE 2>/dev/null | grep -E 'hfs|hfsplus' | awk '{print "/dev/"$1}'); do
    label=$(blkid -s LABEL -o value "$dev" 2>/dev/null)
    label="${label:-untitled}"
    echo -e "  ${BOLD}$dev${NC} ($label)"
    echo ""
    
    # Check
    echo -e "  ${CYAN}Running fsck.hfsplus (check only)...${NC}"
    fsck.hfsplus -q "$dev" 2>&1
    rc=$?
    
    if [ $rc -eq 0 ]; then
        ok "Volume is clean"
    elif [ $rc -eq 1 ]; then
        warn "Volume has errors — attempting repair..."
        echo ""
        read -p "  Repair HFS+ volume $dev? [y/N]: " confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            echo ""
            # Unmount if mounted
            umount "$dev" 2>/dev/null
            echo -e "  ${YELLOW}Repairing (may take a while)...${NC}"
            fsck.hfsplus -fy "$dev" 2>&1
            if [ $? -eq 0 ]; then
                ok "Repair successful!"
            else
                fail "Repair failed — data recovery recommended"
                echo "  Try: fsck.hfsplus -fyr $dev  (slower but more thorough)"
            fi
        else
            info "Skipped repair"
        fi
    else
        fail "Could not check volume (exit code $rc)"
    fi
    found=1
    echo ""
done
[ "$found" -eq 0 ] && echo "  No HFS+ volumes detected"

# --- APFS Repair ---
header "APFS Check & Repair"
found=0
for dev in $(lsblk -nro NAME,FSTYPE 2>/dev/null | grep -i 'apfs' | awk '{print "/dev/"$1}'); do
    label=$(blkid -s LABEL -o value "$dev" 2>/dev/null)
    label="${label:-apfs_volume}"
    echo -e "  ${BOLD}$dev${NC} ($label)"
    echo ""
    
    echo -e "  ${CYAN}Running apfsck...${NC}"
    apfsck "$dev" 2>&1
    rc=$?
    
    if [ $rc -eq 0 ]; then
        ok "APFS volume is clean"
    else
        warn "APFS check reported issues (exit code $rc)"
        echo "  Note: apfsck is experimental — errors may be false positives"
        echo "  For serious APFS repair, use macOS Recovery (Cmd+R at boot)"
    fi
    found=1
    echo ""
done

# Also check via fsapfsinfo
if [ "$found" -eq 0 ]; then
    for dev in $(lsblk -nro NAME 2>/dev/null | grep -v loop | awk '{print "/dev/"$1}'); do
        if fsapfsinfo "$dev" 2>/dev/null | grep -q "APFS"; then
            echo -e "  ${BOLD}$dev${NC} (detected via fsapfsinfo)"
            echo ""
            fsapfsinfo "$dev" 2>&1 | head -10
            echo ""
            warn "APFS container detected — individual volumes may be inside"
            echo "  Use apfsck on the raw partition to check the container"
            found=1
        fi
    done
fi
[ "$found" -eq 0 ] && echo "  No APFS volumes detected"

echo ""
if [ "$found" -eq 0 ]; then
    warn "No macOS volumes found to repair"
fi
