"""discoverlib — what a network says about itself, learned by listening (no packets are sent).

Reads a pcap and understands: LLDP and CDP (which switch and port, VLAN, power, speed), spanning tree (root bridge),
DHCP (who hands out addresses), ARP, mDNS / SSDP / NetBIOS announcements, IPv6 router advertisements.
Pure Python, no third-party modules, so it also runs on a pcap taken somewhere else.
"""
import json
import re
import socket
import struct
import time

ETH_P = {0x0800: "ip", 0x0806: "arp", 0x86DD: "ip6", 0x88CC: "lldp", 0x8100: "vlan", 0x88A8: "vlan"}
CAPS = {0: "other", 1: "repeater", 2: "bridge", 3: "WLAN AP", 4: "router", 5: "telephone", 6: "DOCSIS", 7: "station"}
_oui = None


def mac(b):
    return ":".join(f"{x:02x}" for x in b)


def vendor(m):
    """Manufacturer from the IEEE list on the drive (ieee-data), '' if unknown or locally administered."""
    global _oui
    if _oui is None:
        _oui = {}
        for path in ("/usr/share/ieee-data/oui.txt", "/var/lib/ieee-data/oui.txt"):
            try:
                with open(path, errors="replace") as fh:
                    for line in fh:
                        mt = re.match(r"([0-9A-F]{2})-([0-9A-F]{2})-([0-9A-F]{2})\s+\(hex\)\s+(.+)", line)
                        if mt:
                            _oui["".join(mt.groups()[:3]).lower()] = mt.group(4).strip()
                break
            except OSError:
                continue
    h = m.replace(":", "").lower()
    if len(h) < 6 or int(h[1], 16) & 2:
        return ""
    return _oui.get(h[:6], "")


def packets(path):
    """Yield (timestamp, frame bytes) from a classic pcap file (little or big endian, microsecond or nanosecond)."""
    with open(path, "rb") as f:
        head = f.read(24)
        if len(head) < 24:
            return
        magic = head[:4]
        endian = "<" if magic in (b"\xd4\xc3\xb2\xa1", b"\x4d\x3c\xb2\xa1") else ">"
        nano = magic in (b"\x4d\x3c\xb2\xa1", b"\xa1\xb2\x3c\x4d")
        if magic not in (b"\xd4\xc3\xb2\xa1", b"\xa1\xb2\xc3\xd4", b"\x4d\x3c\xb2\xa1", b"\xa1\xb2\x3c\x4d"):
            raise ValueError("not a classic pcap file (capture with: tcpdump -w FILE)")
        link = struct.unpack(endian + "I", head[20:24])[0]
        if link != 1:
            raise ValueError(f"link type {link} is not Ethernet")
        while True:
            h = f.read(16)
            if len(h) < 16:
                return
            sec, frac, caplen, _ = struct.unpack(endian + "IIII", h)
            data = f.read(caplen)
            if len(data) < caplen:
                return
            yield sec + frac / (1e9 if nano else 1e6), data


# ---- link layer: LLDP, CDP, spanning tree

def parse_lldp(p):
    d = {"proto": "LLDP", "caps": [], "vlans": {}}
    i = 0
    while i + 2 <= len(p):
        t, ln = p[i] >> 1, ((p[i] & 1) << 8) | p[i + 1]
        v = p[i + 2:i + 2 + ln]
        i += 2 + ln
        if t == 0:
            break
        if t in (1, 2) and v:
            sub, val = v[0], v[1:]
            txt = (mac(val) if sub in ((4,) if t == 1 else (3,)) and len(val) == 6
                   else socket.inet_ntoa(val[1:5]) if sub == 5 and len(val) >= 5 and val[0] == 1
                   else val.decode("utf-8", "replace"))
            d["chassis" if t == 1 else "port"] = txt
        elif t == 3 and len(v) == 2:
            d["ttl"] = struct.unpack(">H", v)[0]
        elif t == 4:
            d["port_desc"] = v.decode("utf-8", "replace")
        elif t == 5:
            d["name"] = v.decode("utf-8", "replace")
        elif t == 6:
            d["descr"] = v.decode("utf-8", "replace").replace("\n", " ")[:160]
        elif t == 7 and len(v) >= 4:
            en = struct.unpack(">H", v[2:4])[0]
            d["caps"] = [n for b, n in CAPS.items() if en & (1 << b)]
        elif t == 8 and len(v) >= 6 and v[1] == 1 and v[0] >= 5:
            d["mgmt"] = socket.inet_ntoa(v[2:6])
        elif t == 127 and len(v) >= 4:
            oui, sub, val = v[:3], v[3], v[4:]
            if oui == b"\x00\x80\xc2" and sub == 1 and len(val) >= 2:
                d["pvid"] = struct.unpack(">H", val[:2])[0]
            elif oui == b"\x00\x80\xc2" and sub == 3 and len(val) >= 3:
                vid, nl = struct.unpack(">H", val[:2])[0], val[2]
                d["vlans"][vid] = val[3:3 + nl].decode("utf-8", "replace")
            elif oui == b"SM1" and sub == 1:
                try:
                    d["telemetry"] = json.loads(val.decode("utf-8", "replace"))
                except ValueError:
                    pass
            elif oui == b"\x00\x12\x0f" and sub == 1 and len(val) >= 5:
                d["autoneg"] = bool(val[0] & 1)
            elif oui == b"\x00\x12\x0f" and sub == 2 and len(val) >= 3:
                d["poe"] = ("PSE (switch supplies power)" if val[0] & 1 else "PD (device takes power)") + \
                           (", enabled" if val[0] & 4 else ", disabled" if val[0] & 2 else "")
    return d


def parse_cdp(p):
    d = {"proto": "CDP"}
    i = 4
    while i + 4 <= len(p):
        t, ln = struct.unpack(">HH", p[i:i + 4])
        if ln < 4:
            break
        v = p[i + 4:i + ln]
        i += ln
        if t == 1:
            d["name"] = v.decode("utf-8", "replace")
        elif t == 3:
            d["port"] = v.decode("utf-8", "replace")
        elif t == 5:
            d["descr"] = v.decode("utf-8", "replace").replace("\n", " ")[:160]
        elif t == 6:
            d["platform"] = v.decode("utf-8", "replace")
        elif t == 4 and len(v) == 4:
            c = struct.unpack(">I", v)[0]
            d["caps"] = [n for bit, n in ((1, "router"), (2, "transparent bridge"), (4, "source-route bridge"), (8, "switch"),
                                          (16, "host"), (32, "IGMP"), (64, "repeater")) if c & bit]
        elif t == 10 and len(v) == 2:
            d["pvid"] = struct.unpack(">H", v)[0]
        elif t == 11 and len(v) == 1:
            d["duplex"] = "full" if v[0] else "half"
        elif t == 2 and len(v) >= 4:
            n = struct.unpack(">I", v[:4])[0]
            j, ips = 4, []
            for _ in range(min(n, 4)):
                if j + 3 > len(v):
                    break
                ptl = v[j + 1]
                j += 2 + ptl
                al = struct.unpack(">H", v[j:j + 2])[0]
                addr = v[j + 2:j + 2 + al]
                j += 2 + al
                if al == 4:
                    ips.append(socket.inet_ntoa(addr))
            if ips:
                d["mgmt"] = ips[0]
    return d


def parse_stp(p):
    if len(p) < 35 or p[2] > 3 or p[3] not in (0, 0x80, 2):
        return None
    flags = p[4]
    return {"root": f"{struct.unpack('>H', p[5:7])[0]}/{mac(p[7:13])}", "cost": struct.unpack(">I", p[13:17])[0],
            "bridge": f"{struct.unpack('>H', p[17:19])[0]}/{mac(p[19:25])}", "topology_change": bool(flags & 1)}


# ---- DNS-style names (mDNS, NetBIOS)

def dns_name(msg, i):
    labels, jumped, end = [], False, 0
    for _ in range(64):
        if i >= len(msg):
            break
        n = msg[i]
        if n == 0:
            i += 1
            break
        if n & 0xC0 == 0xC0:
            if i + 1 >= len(msg):
                break
            ptr = ((n & 0x3F) << 8) | msg[i + 1]
            if not jumped:
                end = i + 2
            jumped, i = True, ptr
            continue
        labels.append(msg[i + 1:i + 1 + n].decode("utf-8", "replace"))
        i += 1 + n
    return ".".join(labels), (end if jumped else i)


def parse_mdns(m):
    out = []
    if len(m) < 12:
        return out
    qd, an, ns, ar = struct.unpack(">HHHH", m[4:12])
    i = 12
    for _ in range(qd):
        _, i = dns_name(m, i)
        i += 4
    for _ in range(an + ns + ar):
        if i >= len(m):
            break
        name, i = dns_name(m, i)
        if i + 10 > len(m):
            break
        rtype, _, _, rdl = struct.unpack(">HHIH", m[i:i + 10])
        i += 10
        rd = m[i:i + rdl]
        rdi = i
        i += rdl
        if rtype == 12:
            out.append(("ptr", name, dns_name(m, rdi)[0]))
        elif rtype == 33 and len(rd) >= 7:
            out.append(("srv", name, dns_name(m, rdi + 6)[0], struct.unpack(">H", rd[4:6])[0]))
        elif rtype == 1 and len(rd) == 4:
            out.append(("a", name, socket.inet_ntoa(rd)))
        elif rtype == 16:
            out.append(("txt", name, rd.decode("utf-8", "replace")[:80]))
    return out


def netbios_name(m):
    if len(m) < 12 or len(m) < 12 + 34:
        return ""
    enc = m[13:45]
    try:
        raw = bytes(((enc[j] - 65) << 4 | (enc[j + 1] - 65)) & 255 for j in range(0, 32, 2))
    except IndexError:
        return ""
    return raw[:15].decode("ascii", "replace").strip() + f"<{raw[15]:02x}>"


# ---- DHCP

def parse_dhcp(u):
    if len(u) < 240 or u[236:240] != b"\x63\x82\x53\x63":
        return None
    d = {"op": u[0], "yiaddr": socket.inet_ntoa(u[16:20]), "chaddr": mac(u[28:34]), "opts": {}}
    i = 240
    while i < len(u):
        o = u[i]
        if o == 255:
            break
        if o == 0:
            i += 1
            continue
        if i + 1 >= len(u):
            break
        ln = u[i + 1]
        v = u[i + 2:i + 2 + ln]
        i += 2 + ln
        d["opts"][o] = v
    o = d["opts"]
    d["type"] = {1: "discover", 2: "offer", 3: "request", 4: "decline", 5: "ack", 6: "nak", 8: "inform"}.get(o.get(53, b"\0")[0], "?")
    ip4 = lambda b: [socket.inet_ntoa(b[k:k + 4]) for k in range(0, len(b) - 3, 4)]
    d["server"] = ip4(o[54])[0] if 54 in o else ""
    d["router"] = ip4(o[3]) if 3 in o else []
    d["dns"] = ip4(o[6]) if 6 in o else []
    d["mask"] = ip4(o[1])[0] if 1 in o else ""
    d["domain"] = o[15].decode("utf-8", "replace") if 15 in o else ""
    d["hostname"] = o[12].decode("utf-8", "replace") if 12 in o else ""
    d["lease"] = struct.unpack(">I", o[51])[0] if 51 in o and len(o[51]) == 4 else 0
    return d


# ---- the whole capture

class Net:
    def __init__(self):
        self.links, self.stp, self.dhcp_servers, self.hosts = [], {}, {}, {}
        self.ra, self.ssdp, self.frames, self.t0, self.t1 = {}, [], 0, None, None
        self.vlan_tags = set()

    def host(self, m):
        return self.hosts.setdefault(m, {"mac": m, "ips": set(), "names": set(), "services": set(), "seen": set(), "vendor": vendor(m)})

    def add_link(self, src, d):
        for l in self.links:
            if l["proto"] == d["proto"] and l.get("src") == src:
                l.update(d)
                return
        self.links.append(dict(d, src=src))


def _frame(net, ts, fr):
    net.frames += 1
    net.t0 = net.t0 or ts
    net.t1 = ts
    if len(fr) < 14:
        return
    dst, src, et = mac(fr[0:6]), mac(fr[6:12]), struct.unpack(">H", fr[12:14])[0]
    body = fr[14:]
    while et in (0x8100, 0x88A8) and len(body) >= 4:
        net.vlan_tags.add(struct.unpack(">H", body[:2])[0] & 0x0FFF)
        et = struct.unpack(">H", body[2:4])[0]
        body = body[4:]
    if et == 0x88CC:
        net.add_link(src, parse_lldp(body))
        return
    if et <= 1500 and len(body) >= 3:                                  # 802.3 + LLC
        if body[0] == 0x42 and dst == "01:80:c2:00:00:00":
            s = parse_stp(body[3:])
            if s:
                net.stp[s["bridge"]] = dict(s, src=src)
        elif body[0] == 0xAA and body[3:6] == b"\x00\x00\x0c" and body[6:8] == b"\x20\x00":
            net.add_link(src, parse_cdp(body[8:]))
        return
    if et == 0x0806 and len(body) >= 28:
        smac, sip = mac(body[8:14]), socket.inet_ntoa(body[14:18])
        if sip != "0.0.0.0":
            h = net.host(smac)
            h["ips"].add(sip)
            h["seen"].add("ARP")
    elif et == 0x0800 and len(body) >= 20:
        ihl = (body[0] & 15) * 4
        proto, sip = body[9], socket.inet_ntoa(body[12:16])
        pl = body[ihl:]
        if proto == 17 and len(pl) >= 8:
            sp, dp = struct.unpack(">HH", pl[:4])
            data = pl[8:]
            if sp in (67, 68) or dp in (67, 68):
                d = parse_dhcp(data)
                if d:
                    h = net.host(src)
                    h["seen"].add("DHCP")
                    if sp == 67 and sip != "0.0.0.0":
                        h["ips"].add(sip)
                    if d["hostname"]:
                        h["names"].add(d["hostname"])
                    if d["type"] in ("offer", "ack") and d["server"]:
                        s = net.dhcp_servers.setdefault(d["server"], {"mac": src, "router": d["router"], "dns": d["dns"],
                                                                     "mask": d["mask"], "domain": d["domain"], "lease": d["lease"]})
                        s["mac"] = src
            elif sp == 5353 or dp == 5353:
                h = net.host(src)
                h["ips"].add(sip)
                h["seen"].add("mDNS")
                for r in parse_mdns(data):
                    if r[0] == "ptr" and r[1].startswith("_") and "._" in r[1]:
                        h["services"].add(r[1].replace(".local", ""))
                    elif r[0] == "srv":
                        h["names"].add(r[2].replace(".local", ""))
                        h["services"].add(re.sub(r"^.*?\._", "_", r[1]).replace(".local", ""))
                    elif r[0] == "a":
                        h["names"].add(r[1].replace(".local", ""))
            elif dp == 1900 or sp == 1900:
                h = net.host(src)
                h["ips"].add(sip)
                h["seen"].add("SSDP")
                t = data.decode("utf-8", "replace")
                mt = re.search(r"(?im)^(?:SERVER|USN|NT|ST):\s*(.+)$", t)
                sv = re.search(r"(?im)^SERVER:\s*(.+)$", t)
                if sv:
                    h["services"].add("upnp: " + sv.group(1).strip()[:60])
                elif mt:
                    h["services"].add("upnp: " + mt.group(1).strip()[:60])
            elif dp == 137 or sp == 137:
                nm = netbios_name(data)
                if nm:
                    h = net.host(src)
                    h["ips"].add(sip)
                    h["seen"].add("NetBIOS")
                    h["names"].add(nm.split("<")[0])
            elif dp == 5355 or sp == 5355:
                h = net.host(src)
                h["ips"].add(sip)
                h["seen"].add("LLMNR")
    elif et == 0x86DD and len(body) >= 41 and body[6] == 58 and body[40] == 134:
        net.ra[src] = {"ip": socket.inet_ntop(socket.AF_INET6, body[8:24]), "lifetime": struct.unpack(">H", body[46:48])[0]}
        net.host(src)["seen"].add("IPv6 RA")


def analyse(path):
    net = Net()
    for ts, fr in packets(path):
        try:
            _frame(net, ts, fr)
        except (IndexError, ValueError, struct.error, OSError, UnicodeError):
            net.bad = getattr(net, "bad", 0) + 1          # a damaged or odd frame never stops the rest
    return net


def summary(net):
    """A plain dict of everything learned (JSON-friendly)."""
    hosts = []
    for m, h in sorted(net.hosts.items(), key=lambda kv: sorted(kv[1]["ips"])[:1] or ["~"]):
        hosts.append({"mac": m, "vendor": h["vendor"], "ips": sorted(h["ips"]), "names": sorted(h["names"]),
                      "services": sorted(h["services"]), "seen": sorted(h["seen"])})
    return {"seconds": round((net.t1 or 0) - (net.t0 or 0), 1), "frames": net.frames, "links": net.links, "stp": list(net.stp.values()),
            "dhcp_servers": net.dhcp_servers, "router_advertisements": net.ra, "vlan_tags": sorted(net.vlan_tags), "hosts": hosts}


def findings(net):
    """Things worth a look, in plain English."""
    out = []
    if len(net.dhcp_servers) > 1:
        out.append(("warn", "More than one DHCP server answered: " + ", ".join(sorted(net.dhcp_servers)) +
                    ". Two servers hand out conflicting addresses; one is often a stray router or a connected hotspot."))
    ips = {}
    for m, h in net.hosts.items():
        for ip in h["ips"]:
            ips.setdefault(ip, set()).add(m)
    for ip, ms in ips.items():
        if len(ms) > 1:
            out.append(("warn", f"{ip} is claimed by {len(ms)} devices ({', '.join(sorted(ms))}): a duplicate address."))
    if any(s["topology_change"] for s in net.stp.values()):
        out.append(("warn", "Spanning tree reports a topology change: a cable or switch port has just changed state."))
    if len({s["root"] for s in net.stp.values()}) > 1:
        out.append(("warn", "Two different spanning-tree roots are being announced: switches may not be connected as intended."))
    for ra in net.ra.values():
        pass
    if len(net.ra) > 1:
        out.append(("info", f"{len(net.ra)} devices announce themselves as IPv6 routers."))
    for l in net.links:
        if l.get("duplex") == "half":
            out.append(("warn", f"The switch ({l.get('name', l['src'])}) reports HALF duplex on this port: slow and error-prone. Check the cable and speed settings."))
        if l.get("autoneg") is False:
            out.append(("info", "The switch port has auto-negotiation switched off."))
    for l in net.links:
        t = l.get("telemetry") or {}
        who = t.get("h") or l.get("name") or l["src"]
        if t.get("d", 0) >= 90:
            out.append(("warn", f"{who} reports its disk {t['d']}% full."))
        if t.get("m", 0) >= 90:
            out.append(("warn", f"{who} reports memory {t['m']}% used."))
        if t.get("t", 0) >= 85:
            out.append(("warn", f"{who} reports {t['t']} °C: check cooling."))
    if not net.links and net.frames:
        out.append(("info", "No switch announced itself (LLDP/CDP). Many unmanaged and home switches don't."))
    if not net.frames:
        out.append(("warn", "Nothing was heard. Check the cable and the link light, or that this is the right interface."))
    return out


def fmt_dur(s):
    return f"{int(s)}s"
