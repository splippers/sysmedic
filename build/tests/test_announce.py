"""mDNS announcement: well-formed answers, only for our service, nothing private in it, junk cannot crash it."""
import os
import socket
import struct
import sys
import unittest

REPO = os.path.abspath(os.path.join(os.path.dirname(__file__), "../.."))
SHARED = os.path.join(REPO, "build/staging/shared")
sys.path.insert(0, os.path.join(SHARED, "usr/local/lib/sysmedic"))
import announce  # noqa: E402


def query(name, qtype=announce.T_PTR, flags=0):
    return struct.pack("!6H", 0, flags, 1, 0, 0, 0) + announce.encode_name(name) + struct.pack("!2H", qtype, 1)


def parse_response(pkt):
    _id, flags, qd, an, *_ = struct.unpack("!6H", pkt[:12])
    off, out = 12, []
    for _ in range(an):
        name, off = announce.decode_name(pkt, off)
        rtype, _cls, _ttl, ln = struct.unpack("!HHIH", pkt[off:off + 10])
        off += 10
        out.append((name, rtype, pkt[off:off + ln], off))
        off += ln
    return flags, out


class Announce(unittest.TestCase):
    def setUp(self):
        self.recs = announce.service_records("SysMedic-1a2b3c", "sysmedic-1a2b3c", "10.42.0.1", "caddy", "2026.10.02", "ready")
        self.pkt = announce.response(self.recs)

    def test_response_is_well_formed(self):
        flags, recs = parse_response(self.pkt)
        self.assertEqual(flags, 0x8400)
        self.assertEqual([r[1] for r in recs], [announce.T_PTR, announce.T_SRV, announce.T_TXT, announce.T_A])
        ptr = announce.decode_name(self.pkt, recs[0][3])[0]
        self.assertEqual(ptr, "SysMedic-1a2b3c._sysmedic._tcp.local")
        port = struct.unpack("!3H", recs[1][2][:6])[2]
        self.assertEqual(port, 8443)
        self.assertEqual(recs[3][2], socket.inet_aton("10.42.0.1"))

    def test_txt_says_only_edition_version_state(self):
        _, recs = parse_response(self.pkt)
        data, items, i = recs[2][2], [], 0
        while i < len(data):
            items.append(data[i + 1:i + 1 + data[i]].decode())
            i += 1 + data[i]
        self.assertEqual(sorted(k.split("=")[0] for k in items), ["edition", "scheme", "state", "txtvers", "version"])

    def test_nothing_private_in_the_packet(self):
        host = socket.gethostname().encode()
        for secret in (b"token", b"?t=", b"password", b"passwd", b"code=", host):
            if secret:
                self.assertNotIn(secret, self.pkt.lower() if secret != host else self.pkt)

    def test_it_answers_our_service_only(self):
        self.assertTrue(announce.wants(announce.questions(query("_sysmedic._tcp.local"))))
        self.assertTrue(announce.wants(announce.questions(query("SysMedic-1a2b3c._sysmedic._tcp.local", announce.T_SRV))))
        self.assertFalse(announce.wants(announce.questions(query("_http._tcp.local"))))
        self.assertFalse(announce.wants(announce.questions(query("_sysmedic._tcp.local", flags=0x8400))))   # a response, not a query
        self.assertFalse(announce.wants(announce.questions(query("_sysmedic._tcp.local", announce.T_A))))

    def test_junk_and_hostile_packets_are_ignored(self):
        loop = b"\xc0\x0c"                                                   # a pointer to itself
        for junk in (b"", b"\x00" * 5, os.urandom(300), struct.pack("!6H", 0, 0, 1, 0, 0, 0) + loop + b"\0\x0c\0\x01",
                     struct.pack("!6H", 0, 0, 999, 0, 0, 0) + b"\x3fabc"):
            self.assertEqual(announce.questions(junk), [])

    def test_instance_name_is_neutral(self):
        self.assertEqual(announce.visit_name("1A2B3C4D-xyz"), "SysMedic-1a2b3c")
        self.assertNotIn("jon", announce.visit_name("jon-davis-laptop").lower())

    def test_default_address_is_the_hotspot_not_the_customer_lan(self):
        src = open(os.path.join(SHARED, "usr/local/bin/sysmedic-announce")).read()
        self.assertIn('HOTSPOT_ADDR = "10.42.0.1"', src)
        self.assertIn("IP_MULTICAST_TTL, 1", src)


if __name__ == "__main__":
    unittest.main(warnings="ignore")
