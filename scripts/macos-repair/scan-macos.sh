#!/usr/bin/env bash
# SysMedic - macOS Volume Scanner
# Detects HFS+ and APFS volumes on all disks

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC}   $1"; }
fail()  { echo -e "  ${RED}[FAIL]${NC}   $1"; }
header(){ echo -e "\n${BOLD}$1${NC}\n"; }

header "macOS Volume Scanner"
echo ""

# HFS+ detection
header "HFS+ / HFS (macOS Extended) Volumes"
found_hfs=0
for part in $(lsblk -nro NAME,FSTYPE 2>/dev/null | grep -E 'hfs|hfsplus' | awk '{print $1}'); do
    dev="/dev/$part"
    label=$(blkid -s LABEL -o value "$dev" 2>/dev/null)
    size=$(lsblk -nro SIZE "$dev" 2>/dev/null)
    echo -e "  ${GREEN}●${NC} $dev  ${YELLOW}$size${NC}  Label: ${BOLD}${label:-<none>}${NC}"
    found_hfs=1
done
[ "$found_hfs" -eq 0 ] && echo "  No HFS+ volumes found"

# APFS detection
header "APFS (Apple File System) Volumes"
found_apfs=0
for disk in $(lsblk -ndo NAME 2>/dev/null); do
    if fsapfsinfo "/dev/$disk" 2>/dev/null | grep -q "APFS"; then
        echo -e "  ${GREEN}●${NC} /dev/$disk  (detected via fsapfsinfo)"
        found_apfs=1
    fi
done

# Also scan for partitions with 'apfs' label or Apple partition map
for part in $(lsblk -nro NAME,FSTYPE 2>/dev/null | grep -i 'apfs\|apple' | awk '{print $1}'); do
    dev="/dev/$part"
    label=$(blkid -s LABEL -o value "$dev" 2>/dev/null)
    size=$(lsblk -nro SIZE "$dev" 2>/dev/null)
    echo -e "  ${GREEN}●${NC} $dev  ${YELLOW}$size${NC}  Label: ${BOLD}${label:-<none>}${NC}"
    found_apfs=1
done

# Also check for Apple partitions (using gdisk)
for disk in $(lsblk -ndo NAME 2>/dev/null | grep -v loop); do
    if gdisk -l "/dev/$disk" 2>/dev/null | grep -qi "Apple\|Apple HFS\|Apple APFS\|Apple Core Storage"; then
        echo -e "  ${GREEN}●${NC} /dev/$disk  (Apple partition table detected)"
        gdisk -l "/dev/$disk" 2>/dev/null | grep -i "Apple" | while read -r line; do
            echo "    └─ $line"
        done
        found_apfs=1
    fi
done

[ "$found_apfs" -eq 0 ] && echo "  No APFS volumes found"

echo ""
if [ "$found_hfs" -eq 0 ] && [ "$found_apfs" -eq 0 ]; then
    warn "No macOS volumes detected at all"
    echo "  If you have a Mac drive connected, try: gdisk -l /dev/sdX"
fi
