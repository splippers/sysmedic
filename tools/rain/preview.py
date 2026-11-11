#!/usr/bin/env python3
"""preview.py OUT.png [--calm] [--seed N] — one rain frame as a PNG (for review without a screen)."""
import sys
from PIL import Image, ImageDraw, ImageFont
import os
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../build/staging/shared/usr/local/lib/sysmedic"))
import rain  # noqa: E402

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
COLS, ROWS, CW, CH = 100, 34, 12, 22


def main():
    out = sys.argv[1]
    seed = int(sys.argv[sys.argv.index("--seed") + 1]) if "--seed" in sys.argv else 7
    r = rain.Rain(COLS, ROWS, seed=seed, calm="--calm" in sys.argv)
    for _ in range(40):
        r.step()
    box = rain.make_box(COLS, ROWS, ["Scanning this PC…", "Customer disks are write-protected."])
    img = Image.new("RGB", (COLS * CW, ROWS * CH), (3, 8, 5))
    d = ImageDraw.Draw(img)
    f = ImageFont.truetype(FONT, 18)
    r.t = 6                                              # where the logo highlight is, for the picture
    for y, row in enumerate(r.frame(box)):
        for x, (ch, lv) in enumerate(row):
            if ch != " ":
                d.text((x * CW, y * CH), ch, font=f, fill={6: (235, 255, 240), 7: rain.RGB[4], 8: rain.RGB[5]}.get(lv) or rain.RGB[lv])
    img.save(out)


main()
