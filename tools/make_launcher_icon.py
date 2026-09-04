#!/usr/bin/env python3
"""Generate the BaroBuddy launcher icons.

Two sizes are needed across the target devices:
  40x40 -> fr935, fenix5, fenix5x, d2charlie
  36x36 -> fenix5s, fenixchronos

Run from the project root:  python3 tools/make_launcher_icon.py
"""

import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WHITE = (255, 255, 255)
SS = 8  # supersample factor, downscaled at the end for smooth edges


def draw_icon(size, path):
    img = Image.new("RGB", (size * SS, size * SS), (0, 0, 0))
    d = ImageDraw.Draw(img)

    c = size * SS / 2.0
    r = c - 2 * SS

    # barometer dial
    d.ellipse([c - r, c - r, c + r, c + r], outline=WHITE, width=int(2.2 * SS))

    # tick marks, gap at the bottom
    for deg in range(-150, 151, 30):
        a = math.radians(deg - 90)
        r1, r2 = r - 1.0 * SS, r - 3.4 * SS
        d.line(
            [
                c + r1 * math.cos(a), c + r1 * math.sin(a),
                c + r2 * math.cos(a), c + r2 * math.sin(a),
            ],
            fill=WHITE,
            width=int(1.6 * SS),
        )

    # needle pointing up-right (rising pressure)
    a = math.radians(45 - 90)
    d.line(
        [c, c, c + (r - 5 * SS) * math.cos(a), c + (r - 5 * SS) * math.sin(a)],
        fill=WHITE,
        width=int(2.4 * SS),
    )

    # hub
    hub = 2.2 * SS
    d.ellipse([c - hub, c - hub, c + hub, c + hub], fill=WHITE)

    img = img.resize((size, size), Image.LANCZOS)
    # MIP displays have a 64 colour palette; keep the icon well inside it
    img = img.quantize(colors=16, method=Image.MEDIANCUT).convert("RGB")
    img.save(path)
    print("wrote %s (%dx%d)" % (path, size, size))


if __name__ == "__main__":
    draw_icon(40, os.path.join(ROOT, "resources", "drawables", "launcher_icon.png"))
    draw_icon(36, os.path.join(ROOT, "resources-round-218x218", "drawables", "launcher_icon.png"))
