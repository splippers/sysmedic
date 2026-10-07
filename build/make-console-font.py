#!/usr/bin/env python3
"""make-console-font.py — SysMedic's console font: Terminus 11x22 (Vietnamese set) plus the symbols SysMedic draws.

No stock console font has ✔ ✖ ✓ or a full set of sparkline blocks, and Terminus maps ▲ to an arrow and ● to a
tiny dot. This takes Vietnamese-Terminus22x11 (512 glyphs, box drawing and blocks included), frees glyphs used only
by rare Vietnamese letters and old DOS symbols, and draws the missing ones at the same size.

  ./make-console-font.py SOURCE.psf.gz OUTPUT.psf.gz [--preview]
  e.g. ./make-console-font.py root/usr/share/consolefonts/Vietnamese-Terminus22x11.psf.gz \
           staging/shared/usr/share/consolefonts/Vietnamese-SysMedic22x11.psf.gz
  (named CODESET-FONTFACE+size: /etc/default/console-setup has FONTFACE="SysMedic")
"""
import gzip
import math
import struct
import sys

W, H = 11, 22


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy or 1)))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def draw(test):
    """A glyph from test(x, y) -> bool, sampled at pixel centres."""
    return [[bool(test(x + 0.5, y + 0.5)) for x in range(W)] for y in range(H)]


def polyline(points, width):
    segs = list(zip(points, points[1:]))
    return draw(lambda x, y: any(seg_dist(x, y, *a, *b) <= width / 2 for a, b in segs))


def triangle(a, b, c):
    def inside(x, y):
        def s(p, q):
            return (x - q[0]) * (p[1] - q[1]) - (p[0] - q[0]) * (y - q[1])
        d1, d2, d3 = s(a, b), s(b, c), s(c, a)
        return not ((d1 < 0 or d2 < 0 or d3 < 0) and (d1 > 0 or d2 > 0 or d3 > 0))
    return draw(inside)


def union(*gs):
    return [[any(g[y][x] for g in gs) for x in range(W)] for y in range(H)]


def block(eighths):
    rows = round(H * eighths / 8)
    return [[y >= H - rows for x in range(W)] for y in range(H)]


# Cap height in Terminus 22: rows 3..16; the middle of a capital is about row 10.
GLYPHS = {
    "✔": polyline([(1.6, 10.5), (4.2, 14.2), (9.6, 5.2)], 2.3),
    "✓": polyline([(1.8, 10.8), (4.2, 14.0), (9.4, 5.6)], 1.2),
    "✖": union(polyline([(2.0, 6.0), (9.0, 15.0)], 2.3), polyline([(9.0, 6.0), (2.0, 15.0)], 2.3)),
    "□": draw(lambda x, y: 2 <= x <= 9 and 6 <= y <= 15 and not (3 <= x <= 8 and 7 <= y <= 14)),
    "►": triangle((2.5, 5.5), (2.5, 15.5), (9.5, 10.5)),
    "❯": polyline([(3.0, 6.0), (7.6, 10.5), (3.0, 15.0)], 2.0),
    "●": draw(lambda x, y: math.hypot(x - 5.5, y - 10.5) <= 3.9),
    "▲": triangle((5.5, 5.0), (0.8, 14.8), (10.2, 14.8)),
    "▼": triangle((0.8, 6.2), (10.2, 6.2), (5.5, 16.0)),
    "⚠": union(polyline([(5.5, 3.5), (0.9, 16.5), (10.1, 16.5), (5.5, 3.5)], 1.1),
               draw(lambda x, y: 5 <= x <= 6 and (7 <= y <= 12 or 14 <= y <= 15))),
    "▁": block(1), "▂": block(2), "▃": block(3), "▅": block(5), "▆": block(6), "▇": block(7),
}
SPARE_DOS = "☺☻♂♀♪♫"   # CP437 pictures nobody needs on a rescue console


def load(path):
    d = gzip.open(path).read()
    if d[:4] != b"\x72\xb5\x4a\x86":
        sys.exit("expected a PSF2 font")
    magic, ver, hsz, flags, n, bpg, h, w = struct.unpack_from("<8I", d, 0)
    assert (w, h) == (W, H), (w, h)
    glyphs = [bytearray(d[hsz + i * bpg: hsz + (i + 1) * bpg]) for i in range(n)]
    tab = d[hsz + n * bpg:]
    maps = [e.decode("utf-8") for e in tab.split(b"\xff")[:n]]   # sequences (\xfe) not used by this font
    return glyphs, maps, (magic, ver, hsz, flags, n, bpg, h, w)


def pack(rows):
    rowb = (W + 7) // 8
    out = bytearray()
    for r in rows:
        v = 0
        for x, on in enumerate(r):
            if on:
                v |= 1 << (rowb * 8 - 1 - x)
        out += v.to_bytes(rowb, "big")
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    glyphs, maps, hdr = load(src)
    # glyphs that only carry rare Vietnamese precomposed letters, then the DOS pictures
    spare = [i for i, m in enumerate(maps) if m and all(0x1EA0 <= ord(c) <= 0x1EF9 for c in m)]
    spare += [i for i, m in enumerate(maps) if m and set(m) <= set(SPARE_DOS)]
    if len(spare) < len(GLYPHS):
        sys.exit(f"only {len(spare)} spare glyphs for {len(GLYPHS)} new ones")
    for i, m in enumerate(maps):                       # take the new characters away from wherever they were
        maps[i] = "".join(c for c in m if c not in GLYPHS)
    for slot, (ch, rows) in zip(spare, GLYPHS.items()):
        glyphs[slot] = pack(rows)
        maps[slot] = ch
    magic, ver, hsz, flags, n, bpg, h, w = hdr
    out = struct.pack("<8I", magic, ver, 32, flags, n, bpg, h, w) + b"".join(glyphs)
    out += b"".join(m.encode("utf-8") + b"\xff" for m in maps)
    with open(dst, "wb") as raw, gzip.GzipFile(fileobj=raw, mode="wb", mtime=0) as f:   # reproducible bytes
        f.write(out)
    if "--preview" in sys.argv:
        for ch, rows in GLYPHS.items():
            print(f"--- {ch}")
            print("\n".join("".join("#" if v else "." for v in r) for r in rows[2:19]))
    print(f"{dst}: {len(GLYPHS)} glyphs added ({''.join(GLYPHS)})")


if __name__ == "__main__":
    main()
