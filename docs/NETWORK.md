# Network

## Getting connected

- **Ethernet** and **USB tethering** (Android: Settings → Hotspot → USB tethering; iPhone: Personal Hotspot) work automatically via DHCP.
- **Wi-Fi:** offered on the **first screen at boot** (`sysmedic-connect`) when there's no internet yet. Later: `wifi` (menu 13) opens NetworkManager's `nmtui` picker. Choose the network, enter the password, Esc to leave. WPS isn't supported.
- **Passwords stay in RAM.** NetworkManager keeps networks in `/run/NetworkManager/system-connections` (`conf.d/90-sysmedic-networks-in-ram.conf`), so they're forgotten at shutdown on both editions, the writable caddy included. The deploy also removes any Wi-Fi passwords saved on a drive before this.
- `sysmedic-connect --status` prints how SysMedic is connected.
- Check: `nmcli device`, `nmcli dev wifi list`, `ip -br addr`.

### When Wi-Fi doesn't appear

The boot scan reports drivers that couldn't load their firmware, e.g. *"The iwlwifi driver couldn't load its firmware (iwlwifi-QuZ-a0-hr-b0-77)"*, and Wi-Fi adapters with no driver at all. SysMedic keeps Wi-Fi drivers out of the initramfs: newer kernels ask for newer firmware than Ubuntu ships, and inside the initramfs only the requested file names are available, so the driver would give up before the main disk is mounted. Loading them from the full system fixes this for cards like the Intel AX201. **(caddy)** As a fallback, boot the 6.8 kernel from *Advanced options*.

### DNS

Public resolvers (1.1.1.1, 9.9.9.9) are queried alongside the site's DNS, so lookups work even when the site's DNS is broken. The scan reports **"Internet is reachable but DNS is failing"** as a site fault.

### The clock

A machine whose hardware clock is wrong (a flat CMOS battery, a BIOS never set) starts SysMedic with the wrong time too, and then every secure connection fails: the cloud AI, apt ("Release file is not valid yet") and malware signatures all see certificates as "not yet valid" or expired. It looks like a network fault, but it isn't.

- **Automatic:** as soon as SysMedic is online (first screen, or `wifi` later), it reads the real time from plain-HTTP servers and corrects **its own** clock for the session. The customer's hardware clock is left alone. SysMedic doesn't use NTP sync (systemd-timesyncd is masked) because a synced Linux clock gets copied into the hardware clock every 11 minutes, in UTC, which would put a Windows machine (local-time hardware clock) an hour out after the visit.
- **The scan** says which it is: "SysMedic's clock is 10 h 20 min slow, so secure connections fail", DNS failing, HTTPS blocked (sign-in page, proxy, firewall), or no internet. It also reports **"This machine's hardware clock is … slow"**. A clock that's a whole number of hours out is usually Windows keeping local time, which is normal and not reported.
- `sysmedic-clock` shows all three times, and `sysmedic-clock fix` corrects SysMedic's clock by hand.
- `sysmedic-clock fix --rtc` (**engineer only**, Alt+F2) also sets the machine's hardware clock. It asks whether the machine runs Windows (local time, with the time zone) or not (UTC). If the clock is wrong again after the machine has been unplugged, replace the CMOS battery.

## Tools

| Purpose | Tools |
|---|---|
| Reachability, path | ping, arping, fping, tracepath, traceroute, `mtr -rwc 10 HOST` |
| DNS | dig, nslookup, host, whois, `resolvectl status` |
| Interfaces, links | ip, ss, ethtool (`ethtool -t` self-test), iw, iwconfig, nmcli, wavemon (Wi-Fi signal), ndisc6/rdisc6 (IPv6) |
| Throughput | iperf3, iperf, speedtest-cli, curl |
| Capture and traffic | tcpdump, tshark, termshark, ngrep, iftop, nload, bmon, nethogs, iptraf-ng |
| LAN and services | nmap, ncat, arp-scan, nbtscan, avahi-browse, smbclient, nmblookup, mount.cifs, showmount, snmpwalk, lldpcli |
| Transfer | lftp, tnftp, tftp, telnet, socat, netcat, rsync, ssh/scp |
| Building | bridge-utils, vlan, hostapd, dnsmasq-base, ipcalc, sipcalc |
| Serial / BMC | minicom, picocom, ipmitool |

Probe other machines (nmap, arp-scan, nbtscan, hping3) only on networks you're allowed to test.

Services that would announce or serve on a customer network are **masked** and start only when you ask: lldpd (`systemctl unmask --now lldpd`), avahi-daemon, hostapd, rpcbind (needed for NFSv3: `systemctl unmask --now rpcbind`).

No SSH server runs at boot.
