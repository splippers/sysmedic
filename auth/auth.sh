#!/bin/bash
# SysMedic Auth Gateway
# ── Network → OAuth → opencode ──

AUTH_DIR="/opt/sysmedic/auth"
CLIENT_FILE="$AUTH_DIR/google_client.json"
TOKEN_CACHE="$AUTH_DIR/auth.token"
BYPASS_KEY="$AUTH_DIR/bypass.key"
LOCK_FILE="/tmp/sysmedic-auth.lock"

# Source shared Splipperverse OAuth helper
source /opt/splipperverse/auth/oauth-helper.sh 2>/dev/null || {
  echo "  [WARN] Splipperverse OAuth helper not found — using standalone auth"
}

# ---- Colors ----
red()    { echo -e "\e[31m$1\e[0m"; }
green()  { echo -e "\e[32m$1\e[0m"; }
yellow() { echo -e "\e[33m$1\e[0m"; }
bold()   { echo -e "\e[1m$1\e[0m"; }

# ---- Banner ----
banner() {
  clear
  echo ""
  echo "  ╔══════════════════════════════════════════════╗"
  echo "  ║          SysMedic  ·  v1.0              ║"
  echo "  ║     AI-Powered System Recovery Toolkit       ║"
  echo "  ╠══════════════════════════════════════════════╣"
  echo "  ║       Authorized access only                 ║"
  echo "  ║     @splippers.com accounts                  ║"
  echo "  ╚══════════════════════════════════════════════╝"
  echo ""
}

# ---- Bypass check ----
check_bypass() {
  # Keycombo bypass: hold Left Shift + Right Shift during boot
  # Or create /opt/sysmedic/auth/bypass.key with a passphrase
  if [ -f "$BYPASS_KEY" ]; then
    echo -n "  Bypass code: "
    read -s BYPASS_INPUT
    echo
    STORED=$(cat "$BYPASS_KEY")
    if [ "$BYPASS_INPUT" = "$STORED" ]; then
      green "  ✓ Bypass accepted"
      return 0
    else
      red "  ✗ Invalid bypass code"
      return 1
    fi
  fi

  # Check if both Shift keys were held (boot-time flag)
  if [ -f /tmp/sysmedic-bypass.flag ]; then
    green "  ✓ Physical bypass detected"
    return 0
  fi

  return 1
}

# ---- Network setup ----
setup_network() {
  while true; do
    # Check if we have connectivity
    if ping -c1 -W2 8.8.8.8 &>/dev/null; then
      green "  ✓ Internet: connected"
      return 0
    fi

    echo "  ⚠  No internet connection"
    echo ""
    echo "  Options:"
    echo "    1) Scan & connect WiFi (nmtui)"
    echo "    2) Scan & connect WiFi (nmcli)"
    echo "    3) Configure static network"
    echo "    4) Retry connection check"
    echo "    5) Power off"
    echo "    s) Skip network (continue to auth)"
    echo ""
    echo -n "  Choose [1-5, s]: "
    read -n1 CHOICE
    echo

    case "$CHOICE" in
      1)
        nmtui 2>/dev/null
        ;;
      2)
        echo "  Scanning..."
        nmcli dev wifi list | head -30
        echo -n "  SSID: "
        read SSID
        echo -n "  Password (leave blank for open): "
        read -s PASS
        echo
        if [ -z "$PASS" ]; then
          nmcli dev wifi connect "$SSID" 2>&1
        else
          nmcli dev wifi connect "$SSID" password "$PASS" 2>&1
        fi
        ;;
      3)
        echo -n "  Interface (e.g. wlp0s20f3): "
        read IFACE
        echo -n "  IP/CIDR (e.g. 192.168.1.100/24): "
        read IPADDR
        echo -n "  Gateway: "
        read GW
        echo -n "  DNS: "
        read DNS
        ip addr add "$IPADDR" dev "$IFACE" 2>/dev/null
        ip link set "$IFACE" up
        ip route add default via "$GW" dev "$IFACE" 2>/dev/null
        echo "nameserver $DNS" > /etc/resolv.conf
        ;;
      4)
        continue
        ;;
       5)
        poweroff
        exit 0
        ;;
      [sS])
        yellow "  Skipping network setup"
        return 0
        ;;
      *)
        echo "  Invalid option"
        sleep 1
        ;;
    esac
  done
}

# ---- Google OAuth (uses shared Splipperverse helper) ----
do_oauth() {
  if oauth_is_mock 2>/dev/null; then
    yellow "  ⚡ No real Google client configured — using mock OAuth"
    oauth_mock "SysMedic · System Recovery Toolkit"
    AUTH_OK=$?
    echo "{\"status\":\"authorized\",\"email\":\"$OAUTH_EMAIL\",\"name\":\"$OAUTH_NAME\"}" > "$TOKEN_CACHE"
    return $AUTH_OK
  fi

  oauth_authenticate "SysMedic · System Recovery Toolkit"
  if [ $? -eq 0 ]; then
    echo "{\"status\":\"authorized\",\"email\":\"$OAUTH_EMAIL\",\"name\":\"$OAUTH_NAME\",\"access_token\":\"$OAUTH_TOKEN\"}" > "$TOKEN_CACHE"
    green "  ✓ Authorized: $OAUTH_EMAIL"
    return 0
  fi
  return 1
}

# ---- Main ----
main() {
  # Single-instance lock
  exec 9>"$LOCK_FILE"
  flock -n 9 || exit 0

  # Already authed in this session?
  if [ -f "$TOKEN_CACHE" ]; then
    # Simple expiry check (re-auth if older than 6 hours)
    AGE=$(($(date +%s) - $(stat -c %Y "$TOKEN_CACHE" 2>/dev/null || echo 0)))
    if [ "$AGE" -lt 21600 ]; then
      EMAIL=$(python3 -c "import json; print(json.load(open('$TOKEN_CACHE')).get('email','unknown'))" 2>/dev/null)
      banner
      green "  ✓ Session valid: $EMAIL"
      echo ""
      return 0
    fi
  fi

  banner

  # Check for bypass
  if check_bypass; then
    echo ""
    yellow "  ── Bypass mode ──"
    echo ""
    return 0
  fi

  echo ""
  echo "  [N] Network setup    [S] Skip auth    [B] Bypass shell    [P] Power off"
  echo -n "  > "
  read -n1 MAIN_CHOICE
  echo
  echo ""

  case "$MAIN_CHOICE" in
    [bB])
      yellow "  ── Bypass → shell ──"
      echo ""
      return 0
      ;;
    [sS])
      yellow "  ── Skip auth → launching opencode ──"
      echo ""
      echo "{\"status\":\"bypassed\",\"email\":\"local@SysMedic\"}" > "$TOKEN_CACHE"
      return 0
      ;;
    [pP])
      poweroff
      exit 0
      ;;
    *)
      # Network first
      echo "  Step 1: Connect to network"
      echo "  ───────────────────────────"
      setup_network
      echo ""

      # Then OAuth
      echo "  Step 2: Google Authentication"
      echo "  ─────────────────────────────"
      echo "  Allowed domain: @splippers.com"
      echo ""
      do_oauth
      echo ""

      if [ $? -ne 0 ]; then
        red "  ── Authentication required to proceed ──"
        echo "  Press Enter to retry, [S] to skip, [B] for shell"
        read -n1 RETRY
        echo
        case "$RETRY" in
          [sS]) echo "{\"status\":\"bypassed\"}" > "$TOKEN_CACHE"; return 0 ;;
          [bB]) return 0 ;;
          *) main ;;
        esac
      fi
      ;;
  esac
}

main "$@"
