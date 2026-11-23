"""announce — let the SysMedic phone app find this visit on the engineer's own network (mDNS / Bonjour).

Off by default. SysMedic is quiet on a customer's network ("listens only"), so this only ever speaks on the private
hotspot (or an address the engineer names), never on the customer's LAN, and it only answers for one service:

    _sysmedic._tcp.local   PTR -> <visit>._sysmedic._tcp.local
                           SRV -> <host>.local : 8443      TXT -> edition, version, state, scheme
                           A   -> this computer's address on that interface

No access code, token, customer name or machine detail is announced; the app still needs the QR code or the engineer's
access code to open anything. Pure functions here; the loop and the socket are in sysmedic-announce.
"""
import socket
import struct

SERVICE = "_sysmedic._tcp.local"
PORT = 8443
TTL = 120
T_A, T_PTR, T_TXT, T_SRV, T_ANY = 1, 12, 16, 33, 255
CLASS_IN, CACHE_FLUSH = 1, 0x8000


def encode_name(name):
    out = b""
    for label in name.strip(".").split("."):
        raw = label.encode("utf-8")
        if not 0 < len(raw) < 64:
            raise ValueError(f"bad label {label!r}")
        out += bytes([len(raw)]) + raw
    return out + b"\0"


def decode_name(data, off):
    """-> (name, offset after it); follows compression pointers (bounded, so a hostile packet cannot loop)."""
    labels, jumped, end, hops = [], False, off, 0
    while True:
        if off >= len(data):
            raise ValueError("truncated name")
        n = data[off]
        if n == 0:
            off += 1
            break
        if n & 0xC0 == 0xC0:
            if off + 1 >= len(data):
                raise ValueError("truncated pointer")
            ptr = ((n & 0x3F) << 8) | data[off + 1]
            if not jumped:
                end = off + 2
            jumped = True
            hops += 1
            if hops > 10 or ptr >= len(data):
                raise ValueError("bad pointer")
            off = ptr
            continue
        labels.append(data[off + 1:off + 1 + n].decode("utf-8", "replace"))
        off += 1 + n
    return ".".join(labels), (off if not jumped else end)


def questions(packet):
    """The (name, type) questions in an mDNS query; [] for answers, junk and truncated packets."""
    try:
        _id, flags, qd, *_ = struct.unpack("!6H", packet[:12])
        if flags & 0x8000:                      # a response, not a query
            return []
        off, out = 12, []
        for _ in range(min(qd, 16)):
            name, off = decode_name(packet, off)
            qtype, _qclass = struct.unpack("!2H", packet[off:off + 4])
            off += 4
            out.append((name.lower(), qtype))
        return out
    except (ValueError, struct.error):
        return []


def txt(pairs):
    out = b""
    for k, v in pairs:
        item = f"{k}={v}".encode("utf-8")[:255]
        out += bytes([len(item)]) + item
    return out or b"\0"


def record(name, rtype, rdata, flush=True):
    return encode_name(name) + struct.pack("!HHIH", rtype, CLASS_IN | (CACHE_FLUSH if flush else 0), TTL, len(rdata)) + rdata


def service_records(visit, host, address, edition, version, state):
    """The records that describe this visit (name labels are kept to what mDNS allows)."""
    inst = f"{visit}.{SERVICE}"
    ptr = record(SERVICE, T_PTR, encode_name(inst), flush=False)
    srv = record(inst, T_SRV, struct.pack("!3H", 0, 0, PORT) + encode_name(f"{host}.local"))
    tx = record(inst, T_TXT, txt([("txtvers", "1"), ("edition", edition), ("version", version), ("state", state), ("scheme", "https")]))
    a = record(f"{host}.local", T_A, socket.inet_aton(address))
    return [ptr, srv, tx, a]


def response(records):
    return struct.pack("!6H", 0, 0x8400, 0, len(records), 0, 0) + b"".join(records)


def wants(qs):
    """Does a query ask about our service (browse, or the instance, or ANY of it)?"""
    return any(n == SERVICE or n.endswith("." + SERVICE) for n, t in qs if t in (T_PTR, T_SRV, T_TXT, T_ANY))


def visit_name(machine_id):
    """A neutral instance name from the machine id, never from customer data: 'SysMedic-1a2b3c'."""
    return "SysMedic-" + "".join(c for c in machine_id.lower() if c in "0123456789abcdef")[:6]
