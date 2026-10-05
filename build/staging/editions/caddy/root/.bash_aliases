# SysMedic shell config
alias diag='/opt/sysmedic/sysmedic-diagnose'
alias netcheck='/opt/sysmedic/sysmedic-netcheck'
alias battery='watch -n 2 "cat /sys/class/power_supply/BAT0/uevent | grep -E \"STATUS|CAPACITY|CURRENT|CHARGE|VOLTAGE\""'
alias disks='lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL'
alias temp='for tz in /sys/class/thermal/thermal_zone*; do echo "$(basename $tz): $(cat $tz/type) = $(( $(cat $tz/temp 2>/dev/null || echo 0) / 1000 ))°C"; done'
alias smart-all='for d in /dev/sd[a-z] /dev/nvme*n1; do [ -b "$d" ] && echo "=== $d ===" && smartctl -H "$d" 2>/dev/null; done'
alias ports='ss -tlnp'
alias processes='ps aux --sort=-%cpu | head -20'
alias mem='free -h'
alias myip='ip -br addr'
alias nsmoke='echo "=== DNS ===" && nslookup google.com 2>&1 | head -5 && echo "=== PING ===" && ping -c2 -W2 8.8.8.8 2>&1 | tail -2 && echo "=== TRACE ===" && traceroute -n -m 5 8.8.8.8 2>&1 && echo "=== PORTS ===" && ss -tlnp | head -10 && echo "=== IFACE ===" && ip -br addr'
alias scan-lan='nmap -sn 192.168.1.0/24'
alias scan-ports='nmap -sT -p- --min-rate=10000'

# (The old auth gateway was removed: it offered 'Skip'/'Bypass', so it protected nothing,
#  and it pre-empted the SysMedic boot flow in ~/.profile.)
