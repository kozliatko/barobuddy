#!/usr/bin/env python3
"""Generate the BaroBuddy launcher icons.

Four sizes are needed across the target devices:
  40x40 -> fr935, fenix5, fenix5x, d2charlie, fenix7x family
  36x36 -> fenix5s, fenixchronos
  65x65 -> fr965
  40x33 -> vivoactive3, the one target whose icon is not square

Run from the project root:  python3 tools/make_launcher_icon.py
"""

import math
import os

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WHITE = (255, 255, 255)
SS = 8  # supersample factor, downscaled at the end for smooth edges


def draw_icon(width, path, height=None):
    """Draws the dial centred in a width x height canvas.

    The dial is sized off the shorter edge, so a wider-than-tall icon gets
    black margins left and right rather than an oval.
    """
    height = width if height is None else height
    img = Image.new("RGB", (width * SS, height * SS), (0, 0, 0))
    d = ImageDraw.Draw(img)

    size = min(width, height)
    cx = width * SS / 2.0
    cy = height * SS / 2.0
    r = size * SS / 2.0 - 2 * SS

    # barometer dial
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=WHITE, width=int(2.2 * SS))

    # tick marks, gap at the bottom
    for deg in range(-150, 151, 30):
        a = math.radians(deg - 90)
        r1, r2 = r - 1.0 * SS, r - 3.4 * SS
        d.line(
            [
                cx + r1 * math.cos(a), cy + r1 * math.sin(a),
                cx + r2 * math.cos(a), cy + r2 * math.sin(a),
            ],
            fill=WHITE,
            width=int(1.6 * SS),
        )

    # needle pointing up-right (rising pressure)
    a = math.radians(45 - 90)
    d.line(
        [cx, cy, cx + (r - 5 * SS) * math.cos(a), cy + (r - 5 * SS) * math.sin(a)],
        fill=WHITE,
        width=int(2.4 * SS),
    )

    # hub
    hub = 2.2 * SS
    d.ellipse([cx - hub, cy - hub, cx + hub, cy + hub], fill=WHITE)

    img = img.resize((width, height), Image.LANCZOS)
    # MIP displays have a 64 colour palette; keep the icon well inside it
    img = img.quantize(colors=16, method=Image.MEDIANCUT).convert("RGB")
    img.save(path)
    print("wrote %s (%dx%d)" % (path, width, height))


if __name__ == "__main__":
    draw_icon(40, os.path.join(ROOT, "resources", "drawables", "launcher_icon.png"))
    draw_icon(36, os.path.join(ROOT, "resources-round-218x218", "drawables", "launcher_icon.png"))
    draw_icon(65, os.path.join(ROOT, "resources-round-454x454", "drawables", "launcher_icon.png"))
    draw_icon(40, os.path.join(ROOT, "resources-vivoactive3", "drawables", "launcher_icon.png"), 33)
