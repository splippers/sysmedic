#!/usr/bin/env bash
# SysMedic - Mount macOS Volumes (HFS+ & APFS)
# Detects and mounts macOS volumes to /mnt/mac

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC}   $1"; }
fail()  { echo -e "  ${RED}[FAIL]${NC}   $1"; }
header(){ echo -e "\n${BOLD}$1${NC}\n"; }

MOUNT_BASE="/mnt/mac"
mkdir -p "$MOUNT_BASE"

header "macOS Volume Mounter"
echo ""

# --- HFS+ ---
header "HFS+ Volumes"
found=0
for dev in $(lsblk -nro NAME,FSTYPE 2>/dev/null | grep -E 'hfs|hfsplus' | awk '{print "/dev/"$1}'); do
    label=$(blkid -s LABEL -o value "$dev" 2>/dev/null)
    label="${label:-untitled}"
    mountpoint="${MOUNT_BASE}/hfs_${label}"
    mkdir -p "$mountpoint"
    
    info "Mounting $dev ($label)..."
    if mount -t hfsplus -o force,rw "$dev" "$mountpoint" 2>/dev/null; then
        ok "Mounted $dev → $mountpoint"
        ls "$mountpoint" 2>/dev/null | head -5 | while read f; do echo "      ├─ $f"; done
        found=1
    else
        fail "Could not mount $dev (try fsck first)"
    fi
done
[ "$found" -eq 0 ] && echo "  No HFS+ volumes detected"

# --- APFS ---
header "APFS Volumes"
found=0
for dev in $(lsblk -nro NAME 2>/dev/null | grep -v loop | awk '{print "/dev/"$1}'); do
    # Quick probe with fsapfsinfo
    if fsapfsinfo "$dev" 2>/dev/null | grep -q "APFS"; then
        label=$(fsapfsinfo "$dev" 2>/dev/null | grep "volume name" | head -1 | cut -d: -f2 | xargs)
        label="${label:-apfs_volume}"
        mountpoint="${MOUNT_BASE}/apfs_${label}"
        mkdir -p "$mountpoint"
        
        info "Mounting $dev ($label) via fsapfsmount..."
        if fsapfsmount "$dev" "$mountpoint" 2>/dev/null; then
            ok "Mounted $dev → $mountpoint (read-only)"
            ls "$mountpoint" 2>/dev/null | head -5 | while read f; do echo "      ├─ $f"; done
            found=1
        else
            # Try with specific partition
            for part in $(lsblk -nro NAME "$dev" 2>/dev/null | tail -n +2 | awk '{print "/dev/"$1}'); do
                if fsapfsmount "$part" "$mountpoint" 2>/dev/null; then
                    ok "Mounted $part → $mountpoint (read-only)"
                    found=1
                    break
                fi
            done
            [ "$found" -eq 0 ] && fail "Could not mount $dev"
        fi
    fi
done
[ "$found" -eq 0 ] && echo "  No APFS volumes detected"

# --- Summary ---
echo ""
header "Mount Summary"
echo -e "  ${BOLD}Mount point:${NC} $MOUNT_BASE"
echo ""
if mount | grep -q "$MOUNT_BASE"; then
    mount | grep "$MOUNT_BASE" | while read -r line; do
        echo -e "  ${GREEN}●${NC} $line"
    done
    echo ""
    ok "Volumes ready at $MOUNT_BASE"
    echo "  Browse: cd $MOUNT_BASE"
else
    warn "No macOS volumes were mounted"
    echo "  Try running scan first: /opt/sysmedic/scripts/macos-repair/scan-macos.sh"
fi
