#!/usr/bin/env python3
"""Synthetic captures through discoverlib: python3 build/tests/test_discoverlib.py"""
import os
import socket
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "../staging/shared/usr/local/lib/sysmedic"))
import discoverlib as D  # noqa: E402

M = lambda s: bytes(int(x, 16) for x in s.split(":"))
SW, PC, PRN = "00:1b:0d:aa:bb:01", "52:54:00:12:34:56", "3c:2a:f4:11:22:33"


def eth(dst, src, et, body):
    return M(dst) + M(src) + struct.pack(">H", et) + body


def tlv(t, v):
    return struct.pack(">H", (t << 9) | len(v)) + v


def lldp():
    b = tlv(1, b"\x04" + M(SW)) + tlv(2, b"\x05Gi1/0/24") + tlv(3, struct.pack(">H", 120)) + tlv(4, b"Front desk")
    b += tlv(5, b"core-sw1") + tlv(6, b"Cisco IOS 15.2") + tlv(7, struct.pack(">HH", 0x14, 0x14))
    b += tlv(8, bytes([5, 1]) + socket.inet_aton("192.168.10.2") + bytes([2, 0, 0, 0, 0, 0]))
    b += tlv(127, b"\x00\x80\xc2\x01" + struct.pack(">H", 20)) + tlv(127, b"\x00\x80\xc2\x03" + struct.pack(">H", 20) + bytes([5]) + b"staff")
    b += tlv(127, b"\x00\x12\x0f\x02" + bytes([5, 0, 0]))
    return eth("01:80:c2:00:00:0e", SW, 0x88CC, b + b"\x00\x00")


def cdp():
    t = lambda ty, v: struct.pack(">HH", ty, len(v) + 4) + v
    b = bytes([2, 180, 0, 0]) + t(1, b"edge-sw2") + t(3, b"FastEthernet0/7") + t(6, b"WS-C2960") + t(10, struct.pack(">H", 30)) + t(11, b"\x00")
    llc = b"\xaa\xaa\x03\x00\x00\x0c\x20\x00" + b
    return eth("01:00:0c:cc:cc:cc", "00:1b:0d:aa:bb:02", len(llc), llc)


def stp():
    bp = struct.pack(">HBBB", 0, 2, 2, 1) + struct.pack(">H", 0x8000) + M(SW) + struct.pack(">I", 4) + struct.pack(">H", 0x8000) + M(SW) + b"\x80\x01" + bytes(8)
    llc = b"\x42\x42\x03" + bp
    return eth("01:80:c2:00:00:00", SW, len(llc), llc)


def udp(sip, dip, sp, dp, data):
    u = struct.pack(">HHHH", sp, dp, 8 + len(data), 0) + data
    ip = bytes([0x45, 0, 0, 0, 0, 0, 0, 0, 64, 17, 0, 0]) + socket.inet_aton(sip) + socket.inet_aton(dip)
    return ip + u


def dhcp(kind, server, yi, host=b""):
    b = bytes([2 if kind in (2, 5) else 1, 1, 6, 0]) + bytes(4) + bytes(8) + socket.inet_aton(yi) + bytes(8) + M(PC) + bytes(10) + bytes(192) + b"\x63\x82\x53\x63"
    o = bytes([53, 1, kind]) + bytes([54, 4]) + socket.inet_aton(server) + bytes([3, 4]) + socket.inet_aton("192.168.10.1") + bytes([6, 4]) + socket.inet_aton("192.168.10.1")
    o += bytes([1, 4]) + socket.inet_aton("255.255.255.0") + bytes([15, 5]) + b"lan.x"
    if host:
        o += bytes([12, len(host)]) + host
    return b + o + b"\xff"


def dnsname(n):
    return b"".join(bytes([len(p)]) + p.encode() for p in n.split(".")) + b"\x00"


def mdns():
    ptr = dnsname("_ipp._tcp.local") + struct.pack(">HHIH", 12, 1, 120, 0)
    inst = dnsname("Office Printer._ipp._tcp.local")
    ptr = dnsname("_ipp._tcp.local") + struct.pack(">HHIH", 12, 1, 120, len(inst)) + inst
    a = dnsname("printer.local") + struct.pack(">HHIH", 1, 1, 120, 4) + socket.inet_aton("192.168.10.50")
    return struct.pack(">HHHHHH", 0, 0x8400, 0, 2, 0, 0) + ptr + a


def nbns():
    name = "OFFICEPC".ljust(15) + "\x00"
    enc = "".join(chr(65 + (ord(c) >> 4)) + chr(65 + (ord(c) & 15)) for c in name)
    return struct.pack(">HHHHHH", 1, 0x2910, 1, 0, 0, 1) + b"\x20" + enc.encode() + b"\x00" + struct.pack(">HH", 0x20, 1)


def arp(smac, sip):
    return eth("ff:ff:ff:ff:ff:ff", smac, 0x0806, struct.pack(">HHBBH", 1, 0x800, 6, 4, 1) + M(smac) + socket.inet_aton(sip) + bytes(6) + socket.inet_aton("192.168.10.1"))


def pcap(frames):
    f = tempfile.NamedTemporaryFile(suffix=".pcap", delete=False)
    f.write(struct.pack("<IHHiIII", 0xA1B2C3D4, 2, 4, 0, 0, 65535, 1))
    for i, fr in enumerate(frames):
        f.write(struct.pack("<IIII", 1000 + i, 0, len(fr), len(fr)) + fr)
    f.close()
    return f.name


class T(unittest.TestCase):
    def setUp(self):
        fr = [lldp(), cdp(), stp(),
              eth(PC, SW, 0x0800, udp("192.168.10.1", "192.168.10.77", 67, 68, dhcp(2, "192.168.10.1", "192.168.10.77"))),
              eth(PC, "aa:bb:cc:00:00:09", 0x0800, udp("192.168.10.99", "192.168.10.77", 67, 68, dhcp(2, "192.168.10.99", "192.168.10.78"))),
              eth("ff:ff:ff:ff:ff:ff", PC, 0x0800, udp("0.0.0.0", "255.255.255.255", 68, 67, dhcp(1, "0.0.0.0", "0.0.0.0", b"laptop-7"))),
              eth("01:00:5e:00:00:fb", PRN, 0x0800, udp("192.168.10.50", "224.0.0.251", 5353, 5353, mdns())),
              eth("ff:ff:ff:ff:ff:ff", PC, 0x0800, udp("192.168.10.77", "192.168.10.255", 137, 137, nbns())),
              arp(PC, "192.168.10.77"), arp("aa:bb:cc:00:00:07", "192.168.10.77"), arp(PRN, "192.168.10.50")]
        self.net = D.analyse(pcap(fr))

    def test_lldp(self):
        l = next(x for x in self.net.links if x["proto"] == "LLDP")
        self.assertEqual((l["name"], l["port"], l["pvid"], l["mgmt"]), ("core-sw1", "Gi1/0/24", 20, "192.168.10.2"))
        self.assertEqual(l["vlans"], {20: "staff"})
        self.assertIn("bridge", l["caps"])
        self.assertIn("PSE", l["poe"])

    def test_cdp(self):
        l = next(x for x in self.net.links if x["proto"] == "CDP")
        self.assertEqual((l["name"], l["port"], l["platform"], l["pvid"], l["duplex"]), ("edge-sw2", "FastEthernet0/7", "WS-C2960", 30, "half"))

    def test_stp(self):
        self.assertEqual(len(self.net.stp), 1)
        self.assertTrue(list(self.net.stp)[0].endswith(SW))

    def test_dhcp_two_servers_and_hostname(self):
        self.assertEqual(set(self.net.dhcp_servers), {"192.168.10.1", "192.168.10.99"})
        self.assertIn("laptop-7", self.net.hosts[PC]["names"])
        self.assertTrue(any("DHCP server" in t for _, t in D.findings(self.net)))

    def test_mdns_and_netbios(self):
        h = self.net.hosts[PRN]
        self.assertIn("printer", h["names"])
        self.assertIn("_ipp._tcp", h["services"])
        self.assertIn("OFFICEPC", self.net.hosts[PC]["names"])

    def test_duplicate_ip(self):
        self.assertTrue(any("192.168.10.77" in t and "duplicate" in t for _, t in D.findings(self.net)))

    def test_lldp_telemetry_tlv(self):
        import json
        t = json.dumps({"h": "BOX", "d": 93, "m": 20, "t": 88}).encode()
        b = tlv(1, b"\x04" + M(SW)) + tlv(2, b"\x05eth0") + tlv(3, struct.pack(">H", 120)) + tlv(127, b"SM1\x01" + t) + b"\x00\x00"
        n = D.analyse(pcap([eth("01:80:c2:00:00:0e", SW, 0x88CC, b)]))
        self.assertEqual(n.links[0]["telemetry"]["h"], "BOX")
        msgs = " ".join(m for _, m in D.findings(n))
        self.assertIn("disk 93% full", msgs)
        self.assertIn("88 °C", msgs)

    def test_empty_capture(self):
        n = D.analyse(pcap([]))
        self.assertTrue(any("Nothing was heard" in t for _, t in D.findings(n)))

    def test_truncated_frames_do_not_crash(self):
        D.analyse(pcap([lldp()[:20], cdp()[:30], b"\x00" * 5, stp()[:18]]))


if __name__ == "__main__":
    unittest.main()
