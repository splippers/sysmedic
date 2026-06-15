#!/usr/bin/env bash
# SysMedic - Recover Data from Windows Volumes
# Copies user data from NTFS partitions to a target drive

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC}   $1"; }
fail()  { echo -e "  ${RED}[FAIL]${NC}   $1"; }
header(){ echo -e "\n${BOLD}$1${NC}\n"; }

header "Windows Data Recovery"
echo ""

# Step 1: List available NTFS volumes
info "Scanning for Windows partitions..."
windows_parts=()
i=1
for part in $(lsblk -nro NAME,FSTYPE 2>/dev/null | grep -i 'ntfs' | awk '{print "/dev/"$1}'); do
    size=$(lsblk -nro SIZE "$part" 2>/dev/null)
    label=$(blkid -s LABEL -o value "$part" 2>/dev/null)
    echo -e "  ${GREEN}$i)${NC} ${BOLD}$part${NC}  ${YELLOW}$size${NC}  ${label:-<no label>}"
    windows_parts+=("$part")
    i=$((i+1))
done

if [ ${#windows_parts[@]} -eq 0 ]; then
    fail "No NTFS/Windows partitions found"
    exit 1
fi

echo ""
read -p "  Select Windows partition to recover from [1-${#windows_parts[@]}]: " sel
sel=$((sel-1))
win_dev="${windows_parts[$sel]}"

# Step 2: Mount source
header "Mounting $win_dev"
mkdir -p /mnt/windows
if ! ntfs-3g "$win_dev" /mnt/windows 2>/dev/null; then
    fail "Could not mount $win_dev"
    echo "  Try: ntfsfix $win_dev  then retry"
    exit 1
fi
ok "Mounted $win_dev → /mnt/windows"

# Step 3: Choose recovery target
header "Recovery Target"
echo "  1) Mount a USB/external drive"
echo "  2) Use persistence partition (/mnt/persist)"
echo "  3) Use a local directory (/root/recovered_windows)"
echo ""
read -p "  Choose [1-3]: " target_choice

case "$target_choice" in
    1)
        echo ""
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null | grep -v loop
        echo ""
        read -p "  Enter target device (e.g. /dev/sda1): " target_dev
        mkdir -p /mnt/recover
        if mount "$target_dev" /mnt/recover 2>/dev/null; then
            TARGET="/mnt/recover"
            ok "Mounted $target_dev → $TARGET"
        else
            fail "Could not mount $target_dev"
            TARGET="/root/recovered_windows"
            warn "Falling back to $TARGET"
        fi
        ;;
    2)
        if [ -d /mnt/persist ]; then
            TARGET="/mnt/persist/recovered_windows"
            mkdir -p "$TARGET"
            ok "Using $TARGET"
        else
            TARGET="/root/recovered_windows"
            warn "No persistence partition — using $TARGET"
        fi
        ;;
    3)
        TARGET="/root/recovered_windows"
        mkdir -p "$TARGET"
        ok "Using $TARGET"
        ;;
esac

# Step 4: Select data to recover
header "Select Data to Recover"
echo "  1) Quick — User profiles (Desktop, Documents, Downloads)"
echo "  2) Full — Entire Users directory"
echo "  3) Custom — Choose specific folders"
echo ""
read -p "  Choose [1-3]: " scope

mkdir -p "$TARGET"

case "$scope" in
    1)
        for user_dir in /mnt/windows/Users/*/; do
            [ -d "$user_dir" ] || continue
            username=$(basename "$user_dir")
            echo ""
            echo -e "  ${BOLD}$username${NC}"
            
            for folder in "Desktop" "Documents" "Downloads" "Pictures" "Music" "Videos" "Favorites" "OneDrive"; do
                src="$user_dir/$folder"
                if [ -d "$src" ]; then
                    dst="$TARGET/$username/$folder"
                    mkdir -p "$dst"
                    echo -ne "    ${CYAN}$folder...${NC} "
                    size=$(du -sh "$src" 2>/dev/null | cut -f1)
                    rsync -ah --progress "$src/" "$dst/" 2>/dev/null | tail -1
                    ok "Done ($size)"
                fi
            done
        done
        ;;
    2)
        for user_dir in /mnt/windows/Users/*/; do
            [ -d "$user_dir" ] || continue
            username=$(basename "$user_dir")
            echo -e "  ${CYAN}Copying $username...${NC}"
            rsync -ah --progress "$user_dir" "$TARGET/" 2>/dev/null
            ok "Copied $username"
        done
        ;;
    3)
        echo ""
        echo -e "  ${BOLD}Available folders in /mnt/windows/Users/:${NC}"
        ls /mnt/windows/Users/ 2>/dev/null | while read u; do echo "    ├─ $u"; done
        echo ""
        read -p "  Enter username(s) to recover (space-separated): " -a usernames
        for username in "${usernames[@]}"; do
            src="/mnt/windows/Users/$username"
            if [ -d "$src" ]; then
                echo -e "  ${CYAN}Copying $username...${NC}"
                rsync -ah --progress "$src/" "$TARGET/$username/" 2>/dev/null
                ok "Copied $username"
            else
                warn "User '$username' not found"
            fi
        done
        ;;
esac

# Also grab other useful Windows data
echo ""
header "Additional Recovery"
read -p "  Copy Windows event logs? [y/N]: " get_logs
if [ "$get_logs" = "y" ] || [ "$get_logs" = "Y" ]; then
    if [ -d "/mnt/windows/Windows/System32/winevt/Logs" ]; then
        mkdir -p "$TARGET/Windows_Logs"
        cp /mnt/windows/Windows/System32/winevt/Logs/*.evtx "$TARGET/Windows_Logs/" 2>/dev/null
        ok "Event logs copied"
    fi
fi

# Summary
echo ""
header "Recovery Complete"
ok "Data recovered to: $TARGET"
echo -e "  Total size: $(du -sh "$TARGET" 2>/dev/null | cut -f1)"
echo ""
info "To unmount Windows volume: umount /mnt/windows"
echo ""
ls "$TARGET" 2>/dev/null | while read f; do echo "  ├─ $f"; done
