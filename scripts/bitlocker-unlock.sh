#!/usr/bin/env bash
# SysMedic - BitLocker Unlock & Mount
# Decrypts BitLocker-protected volumes using dislocker

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC}   $1"; }
fail()  { echo -e "  ${RED}[FAIL]${NC}   $1"; }
header(){ echo -e "\n${BOLD}$1${NC}\n"; }

header "🔐 BitLocker Unlock Tool"
echo ""

# Step 1: Find encrypted partitions
info "Scanning for BitLocker volumes..."
echo ""
encrypted_parts=()
i=1
for part in $(lsblk -nro NAME 2>/dev/null | grep -v loop); do
    dev="/dev/$part"
    # Check with dislocker if it's a BitLocker volume
    if dislocker -V "$dev" 2>/dev/null | grep -qi "bitlocker"; then
        size=$(lsblk -nro SIZE "$dev" 2>/dev/null)
        model=$(lsblk -nro MODEL "$dev" 2>/dev/null | head -1)
        echo -e "  ${GREEN}$i)${NC} ${BOLD}$dev${NC}  ${YELLOW}$size${NC}  ${model:+(}$model${model:+) }${CYAN}[BitLocker]${NC}"
        encrypted_parts+=("$dev")
        i=$((i+1))
    fi
done

if [ ${#encrypted_parts[@]} -eq 0 ]; then
    warn "No BitLocker volumes detected"
    echo ""
    echo -e "  ${YELLOW}Note:${NC} Some BitLocker volumes may not advertise themselves."
    echo "  You can still try unlocking below if you know the device."
    echo ""
fi

echo ""
echo "  If your device wasn't auto-detected, enter it manually."
read -p "  Select partition [1-${#encrypted_parts[@]}] or enter device path manually: " sel

# Parse selection
if [[ "$sel" =~ ^[0-9]+$ ]] && [ "$sel" -ge 1 ] && [ "$sel" -le "${#encrypted_parts[@]}" ]; then
    idx=$((sel-1))
    BLK_DEV="${encrypted_parts[$idx]}"
else
    BLK_DEV="$sel"
fi

if [ ! -b "$BLK_DEV" ]; then
    fail "Not a valid block device: $BLK_DEV"
    exit 1
fi

echo ""
header "Unlock Method"
echo "  1) 48-digit Recovery Key"
echo "  2) User Password (if one was set)"
echo "  3) BEK file on USB key"
echo "  0) Cancel"
echo ""
read -p "  Choose [0-3]: " method

case "$method" in
    1)
        echo ""
        echo -e "  Enter the 48-digit recovery key."
        echo -e "  ${YELLOW}Format:${NC} XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX-XXXXXX"
        echo -e "  ${YELLOW}Or:${NC}     XXXXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX"
        echo ""
        read -p "  Recovery key: " rec_key
        rec_key=$(echo "$rec_key" | tr -d ' \t-')
        
        echo ""
        info "Unlocking $BLK_DEV..."
        mkdir -p /mnt/bitlocker
        dislocker -V "$BLK_DEV" -p"$rec_key" -r -- /mnt/bitlocker 2>&1
        ;;
    2)
        echo ""
        read -s -p "  User password: " user_pass
        echo ""
        echo ""
        info "Unlocking $BLK_DEV with user password..."
        mkdir -p /mnt/bitlocker
        dislocker -V "$BLK_DEV" -u"$user_pass" -r -- /mnt/bitlocker 2>&1
        ;;
    3)
        echo ""
        read -p "  Path to BEK file: " bek_file
        if [ ! -f "$bek_file" ]; then
            fail "BEK file not found: $bek_file"
            exit 1
        fi
        info "Unlocking $BLK_DEV with BEK file..."
        mkdir -p /mnt/bitlocker
        dislocker -V "$BLK_DEV" -f "$bek_file" -r -- /mnt/bitlocker 2>&1
        ;;
    0) exit 0 ;;
    *) fail "Invalid choice"; exit 1 ;;
esac

# Step 3: Mount the decrypted volume
if [ -f /mnt/bitlocker/dislocker-file ]; then
    ok "BitLocker unlocked successfully!"
    echo ""
    header "Accessing Decrypted Volume"
    
    if command -v ntfs-3g &>/dev/null; then
        mkdir -p /mnt/windows
        mount -o loop,ro /mnt/bitlocker/dislocker-file /mnt/windows 2>/dev/null || \
        mount -o loop /mnt/bitlocker/dislocker-file /mnt/windows 2>/dev/null
        
        if mountpoint -q /mnt/windows; then
            ok "Decrypted volume mounted at /mnt/windows"
            echo ""
            echo -e "  ${BOLD}Contents:${NC}"
            ls /mnt/windows/ 2>/dev/null | head -10
            echo ""
            info "You can now:"
            echo "    • Browse files:  ls -la /mnt/windows/"
            echo "    • Run Windows repair tools"
            echo "    • Recover data to external drive"
            echo ""
            info "When done, unmount with:"
            echo "    umount /mnt/windows && umount /mnt/bitlocker"
        else
            warn "Could not mount with ntfs-3g"
            echo "  The dislocker file is at: /mnt/bitlocker/dislocker-file"
            echo "  Try: mount -o loop /mnt/bitlocker/dislocker-file /mnt/windows"
        fi
    else
        warn "ntfs-3g not installed"
        echo "  The decrypted data is available as a loopback file:"
        echo "    /mnt/bitlocker/dislocker-file"
    fi
else
    fail "Unlock failed"
    echo ""
    echo "  Possible reasons:"
    echo "    • Incorrect recovery key / password"
    echo "    • Drive uses TPM-only protection (cannot be unlocked from Linux)"
    echo "    • Volume state is suspended or corrupted"
    echo ""
    echo "  Tips:"
    echo "    • Double-check the 48-digit recovery key format"
    echo "    • Try with -s flag (skip state check):"
    echo "      dislocker -V $BLK_DEV -p'<key>' -s -- /mnt/bitlocker"
    echo "    • Dump metadata to diagnose:"
    echo "      dislocker -V $BLK_DEV -v"
fi
