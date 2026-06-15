#!/usr/bin/env bash
# SysMedic - Launch BitLocker Web Unlock Portal
# Starts a LAN-accessible web server for pasting recovery keys

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'; BOLD='\033[1m'
info()  { echo -e "  ${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "  ${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "  ${YELLOW}[WARN]${NC}   $1"; }

SCRIPT="/opt/sysmedic/scripts/bitlocker-web-unlock.py"

clear
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║   🔐 BitLocker Web Unlock Portal                     ║${NC}"
echo -e "${BOLD}╠══════════════════════════════════════════════════════╣${NC}"
echo -e "${BOLD}║                                                     ║${NC}"
echo -e "${BOLD}║  This starts a web server on your LAN so you can    ║${NC}"
echo -e "${BOLD}║  paste the 48-digit recovery key from your phone    ║${NC}"
echo -e "${BOLD}║  or laptop instead of typing it on this keyboard.   ║${NC}"
echo -e "${BOLD}║                                                     ║${NC}"
echo -e "${BOLD}║  After unlock, it runs diagnostics and shows:       ║${NC}"
echo -e "${BOLD}║  • BSOD analysis (BugCheck codes decoded)           ║${NC}"
echo -e "${BOLD}║  • Windows Update errors with explanations          ║${NC}"
echo -e "${BOLD}║  • Corrupt component store details                  ║${NC}"
echo -e "${BOLD}║  • Problematic driver detection                     ║${NC}"
echo -e "${BOLD}║  • System health summary                            ║${NC}"
echo -e "${BOLD}║                                                     ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# Check dependencies
if ! command -v dislocker &>/dev/null; then
    fail "dislocker not installed. Run: apt-get install -y dislocker"
    exit 1
fi

if ! python3 -c "import http.server" 2>/dev/null; then
    fail "Python3 http.server not available"
    exit 1
fi

# Warn about network security
echo -e "  ${YELLOW}⚠  SECURITY NOTE:${NC}"
echo -e "  This server is accessible to ANYONE on the local network."
echo -e "  Anyone who can reach this IP can:"
echo -e "    • See the machine hostname and disk information"
echo -e "    • Attempt to unlock the drive (brute-force is slow though)"
echo -e "  ${YELLOW}Only run on trusted networks.${NC}"
echo ""

read -p "  Continue? [y/N]: " confirm
if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
    info "Cancelled"
    exit 0
fi

echo ""
echo -e "  ${GREEN}Starting web server...${NC}"
echo -e "  Access it from any device on the same network."
echo ""
echo -e "  ${BOLD}Press Ctrl+C to stop the server.${NC}"
echo ""

# Run the Python web server
python3 "$SCRIPT"
