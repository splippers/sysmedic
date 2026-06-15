#!/bin/bash
# SysMedic WiFi Connect with WPS Push-Button Support
# Scans for networks, lets you connect by password or WPS button

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'
BOLD='\033[1m'

info()  { echo -e "  ${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC}   $1"; }
fail()  { echo -e "  ${RED}[FAIL]${NC}   $1"; }
header(){ echo -e "\n${BOLD}$1${NC}\n"; }

# Find available WiFi interfaces
find_wifi_iface() {
    for iface in /sys/class/net/wl*; do
        [ -e "$iface" ] || continue
        name=$(basename "$iface")
        # Skip if it's the internal Intel AX211 (we want the USB dongle)
        iw dev "$name" info 2>/dev/null | grep -q 'type managed' && echo "$name" && return 0
    done
    # Fallback: any wireless interface
    for iface in /sys/class/net/wl*; do
        [ -e "$iface" ] || continue
        echo "$(basename "$iface")" && return 0
    done
    return 1
}

# Ensure interface is up
iface_up() {
    ip link set "$1" up 2>/dev/null
    # Wait for interface to be ready
    for i in $(seq 1 5); do
        iw dev "$1" scan 2>/dev/null | head -1 >/dev/null && return 0
        sleep 1
    done
    return 1
}

# Scan and display networks with numbers
scan_networks() {
    local iface="$1"
    header "Scanning for WiFi networks on $iface..."
    
    # Run scan and extract networks
    iw dev "$iface" scan 2>/dev/null | awk '
    BEGIN { count=0; }
    /^BSS / { 
        mac=$2; 
        count++; 
        ssid=""; 
        signal=""; 
        wpa="" 
    }
    /freq:/ { freq=$2/1000 " GHz" }
    /signal:/ { signal=$2 " dBm" }
    /SSID:/ { 
        $1=""; 
        ssid=substr($0,2); 
        if(length(ssid)==0) ssid="<hidden SSID>"
    }
    /RSN:|WPA:/ { 
        if($1=="RSN:*"||$1=="WPA:*") { 
            if(wpa=="") wpa=$1; 
            else if(wpa!=$1) wpa="WPA/WPA2"
        }
    }
    /--/ {
        if(ssid!="" && ssid!="<hidden SSID>") {
            printf "%d|%s|%s|%s|%s\n", count, ssid, signal, freq, wpa
            ssid=""
        }
    }
    END {
        if(count==0) print "NONE"
    }' 2>/dev/null | sort -t'|' -k1 -n > /tmp/wifi-scan.txt
    
    # Display results
    if [ ! -s /tmp/wifi-scan.txt ] || grep -q 'NONE' /tmp/wifi-scan.txt; then
        fail "No networks found or scan failed"
        return 1
    fi
    
    local i=1
    echo ""
    printf "  %-3s %-30s %-12s %-10s\n" "#" "SSID" "Signal" "Band"
    printf "  %-3s %-30s %-12s %-10s\n" "---" "------------------------------" "-----------" "----------"
    while IFS='|' read -r num ssid signal freq wpa; do
        printf "  ${BOLD}%-3d${NC} %-30s %-12s %-10s\n" "$i" "$ssid" "$signal" "$freq"
        i=$((i+1))
    done < /tmp/wifi-scan.txt
    
    echo ""
    return 0
}

# Connect with password
connect_password() {
    local iface="$1" ssid="$2" pass="$3"
    
    header "Connecting to '$ssid'..."
    
    # Generate wpa_supplicant config
    cat > /tmp/wpa-sysmedic.conf << EOF
ctrl_interface=/var/run/wpa_supplicant
ap_scan=1
network={
    ssid="$ssid"
    psk="$pass"
    key_mgmt=WPA-PSK
}
EOF
    
    # Kill any existing wpa_supplicant on this interface
    kill $(cat /var/run/wpa_supplicant/$iface 2>/dev/null) 2>/dev/null || true
    sleep 1
    
    # Start wpa_supplicant
    wpa_supplicant -B -i "$iface" -c /tmp/wpa-sysmedic.conf 2>/dev/null
    
    # Get DHCP
    dhclient "$iface" 2>/dev/null || dhcpcd "$iface" 2>/dev/null || \
        dhcpclient -1 "$iface" 2>/dev/null || \
        info "Trying systemd-networkd for DHCP..."
    
    # Wait and check
    sleep 5
    local ip=$(ip -4 addr show "$iface" 2>/dev/null | grep inet | awk '{print $2}')
    if [ -n "$ip" ]; then
        ok "Connected! IP: $ip"
        return 0
    else
        fail "Connected but no IP address (DHCP may need more time)"
        return 1
    fi
}

# Connect via WPS Push Button
connect_wps() {
    local iface="$1" ssid="$2"
    
    header "WPS Push-Button Connection"
    echo ""
    echo -e "  ${YELLOW}   ╔══════════════════════════════════════╗${NC}"
    echo -e "  ${YELLOW}   ║    PRESS THE WPS BUTTON ON YOUR      ║${NC}"
    echo -e "  ${YELLOW}   ║    ROUTER/ACCESS POINT NOW!           ║${NC}"
    echo -e "  ${YELLOW}   ║                                      ║${NC}"
    echo -e "  ${YELLOW}   ║    (You have 60 seconds)             ║${NC}"
    echo -e "  ${YELLOW}   ╚══════════════════════════════════════╝${NC}"
    echo ""
    
    # Kill any existing wpa_supplicant on this interface
    kill $(cat /var/run/wpa_supplicant/$iface 2>/dev/null) 2>/dev/null || true
    sleep 1
    
    # Start wpa_supplicant with WPS support
    wpa_supplicant -B -i "$iface" -C /var/run/wpa_supplicant 2>/dev/null
    sleep 2
    
    # Wait for wpa_supplicant control interface
    for i in $(seq 1 10); do
        [ -S "/var/run/wpa_supplicant/$iface" ] && break
        sleep 1
    done
    
    echo -e "  ${CYAN}Waiting for WPS...${NC}"
    
    # Initiate WPS PBC (Push Button Configuration)
    wpa_cli -i "$iface" wps_pbc 2>/dev/null
    
    # Monitor for connection
    local count=0
    while [ $count -lt 60 ]; do
        status=$(wpa_cli -i "$iface" status 2>/dev/null | grep 'wpa_state=' | cut -d= -f2)
        case "$status" in
            "COMPLETED")
                echo ""
                ok "WPS negotiation successful!"
                # Get DHCP
                dhclient "$iface" 2>/dev/null || dhcpcd "$iface" 2>/dev/null || true
                sleep 3
                local ip=$(ip -4 addr show "$iface" 2>/dev/null | grep inet | awk '{print $2}')
                if [ -n "$ip" ]; then
                    ok "Connected! IP: $ip"
                else
                    warn "Connected but getting IP..."
                fi
                # Save config for next boot
                wpa_cli -i "$iface" save_config 2>/dev/null
                return 0
                ;;
            "4WAY_HANDSHAKE"|"GROUP_HANDSHAKE")
                echo -ne "  \r${GREEN}Handshaking...${NC}   "
                ;;
            "SCANNING")
                echo -ne "  \r${CYAN}Scanning...${NC}     "
                ;;
            *)
                echo -ne "  \r${YELLOW}Waiting for WPS press...${NC} ($count s)"
                ;;
        esac
        sleep 1
        count=$((count+1))
    done
    
    echo ""
    fail "WPS timed out after 60 seconds"
    echo "  Make sure you pressed the WPS button on your router"
    wpa_cli -i "$iface" terminate 2>/dev/null
    return 1
}

# Save WiFi config for auto-connect on next boot
save_auto_connect() {
    local iface="$1" ssid="$2"
    header "Save this network for auto-connect?"
    echo ""
    echo -e "  ${YELLOW}Save '$ssid' so SysMedic auto-connects on next boot?${NC}"
    echo -e "  ${CYAM}1) Yes${NC}"
    echo -e "  ${CYAN}2) No, just this session${NC}"
    echo ""
    read -p "  Choose [1/2]: " save_choice
    if [ "$save_choice" = "1" ]; then
        # Copy wpa_supplicant config to persistence if available
        if [ -d /mnt/persist ]; then
            mkdir -p /mnt/persist/etc
            cp /tmp/wpa-sysmedic.conf /mnt/persist/etc/wpa_supplicant.conf 2>/dev/null
            ok "Saved to /mnt/persist/etc/wpa_supplicant.conf"
        else
            mkdir -p /etc/wpa_supplicant
            cp /tmp/wpa-sysmedic.conf /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null
            ok "Saved to /etc/wpa_supplicant/wpa_supplicant.conf"
        fi
        # Also create a networkd/netplan drop-in for auto-connect
        mkdir -p /mnt/persist/etc/systemd/network/ 2>/dev/null || true
        ok "Network will auto-connect on next boot"
    else
        info "OK, session-only."
    fi
}

# Main menu
main_menu() {
    # Find interface
    local iface=$(find_wifi_iface)
    if [ -z "$iface" ]; then
        fail "No wireless interface found!"
        echo "  Try plugging in your USB WiFi dongle"
        exit 1
    fi
    
    info "Found wireless interface: $iface"
    iface_up "$iface"
    
    # Scan
    scan_networks "$iface" || return 1
    
    # Get list for selection
    local count=$(wc -l < /tmp/wifi-scan.txt)
    if [ "$count" -eq 0 ]; then
        fail "No networks found"
        return 1
    fi
    
    local choice
    read -p "  Select network number (or 'w' for WPS button, 'r' to rescan, 'q' to quit): " choice
    echo ""
    
    case "$choice" in
        q|Q) exit 0 ;;
        r|R) main_menu; return ;;
        w|W)
            # WPS mode - scan for WPS-capable networks or just use any
            header "WPS Push-Button Mode"
            echo ""
            echo "  All WPS-capable networks will accept your button press."
            echo "  The router will negotiate the connection automatically."
            echo ""
            connect_wps "$iface" "" 
            return
            ;;
        *)
            # Validate number
            if ! echo "$choice" | grep -q '^[0-9]\+$'; then
                fail "Invalid choice"
                return 1
            fi
            if [ "$choice" -lt 1 ] || [ "$choice" -gt "$count" ]; then
                fail "Invalid number (1-$count)"
                return 1
            fi
            
            # Get SSID
            local ssid=$(sed -n "${choice}p" /tmp/wifi-scan.txt | cut -d'|' -f2)
            
            echo ""
            echo -e "  Selected: ${BOLD}$ssid${NC}"
            echo ""
            echo -e "  1) Connect with ${GREEN}WPS button${NC} (push button on router)"
            echo -e "  2) Connect with ${YELLOW}password${NC} (enter WiFi password)"
            echo -e "  3) Skip this network"
            echo ""
            read -p "  Choose [1/2/3]: " method
            
            case "$method" in
                1) connect_wps "$iface" "$ssid" ;;
                2)
                    read -p "  Enter WiFi password: " pass
                    connect_password "$iface" "$ssid" "$pass"
                    if [ $? -eq 0 ]; then
                        save_auto_connect "$iface" "$ssid"
                    fi
                    ;;
                *) info "Skipped" ;;
            esac
            ;;
    esac
}

# Run
echo ""
echo -e "${BOLD}  ╔══════════════════════════════════════╗${NC}"
echo -e "${BOLD}  ║   SysMedic WiFi Connect         ║${NC}"
echo -e "${BOLD}  ║   WPS Push-Button or Password         ║${NC}"
echo -e "${BOLD}  ╚══════════════════════════════════════╝${NC}"
main_menu
echo ""
echo -e "  ${CYAN}Current connection status:${NC}"
ip -4 addr show scope global 2>/dev/null | grep inet | awk '{print "  " $NF ": " $2}' || echo "  No IP address"
