#!/usr/bin/env python3
"""Crop the watch display out of a Connect IQ simulator screenshot.

The simulator draws the watch as a photograph on a sheet, so the display is
somewhere inside a rendered case and its position differs per device. Rather
than guess, the circle is located from a calibration shot: a build whose
onUpdate() clears the whole screen to magenta and returns. Magenta appears
nowhere in the watch renders, which white does not manage — the fenix 5S is a
white watch on a white sheet.

    monkeyc ... -o cal.prg            # with onUpdate() clearing to 0xFF00FF
    monkeydo cal.prg <device>
    ffmpeg -f x11grab -video_size 1280x1024 -i :99 -frames:v 1 -y cal.png
    monkeydo BaroBuddy.prg <device>   # the real build
    ffmpeg ... -y shot.png
    python3 tools/crop_screenshot.py cal.png shot.png out.png 320

The calibration and the screenshot have to come from the same simulator window
position, so capture them back to back without moving the window.
"""
import sys
from PIL import Image, ImageDraw

cal, shot, dst, out_size = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])

im = Image.open(cal).convert('RGB')
px = im.load()
W, H = im.size

def lit(p):
    return p[0] > 180 and p[1] < 90 and p[2] > 180

x0, y0, x1, y1 = W, H, 0, 0
for y in range(H):
    for x in range(W):
        if not lit(px[x, y]):
            continue
        if x < x0: x0 = x
        if y < y0: y0 = y
        if x > x1: x1 = x
        if y > y1: y1 = y

size = max(x1 - x0, y1 - y0) + 1
mx, my = (x0 + x1) // 2, (y0 + y1) // 2
box = (mx - size // 2, my - size // 2, mx - size // 2 + size, my - size // 2 + size)

crop = Image.open(shot).convert('RGB').crop(box)
# Inset by a couple of pixels: the outermost ring of the calibration circle is
# anti-aliased against the bezel and would show up as a grey arc.
inset = 3
mask = Image.new('L', (size, size), 0)
ImageDraw.Draw(mask).ellipse([inset, inset, size - 1 - inset, size - 1 - inset], fill=255)
out = Image.new('RGB', (size, size), (0, 0, 0))
out.paste(crop, (0, 0), mask)
out.resize((out_size, out_size), Image.LANCZOS).save(dst)
print("%s display %dpx at %s" % (dst, size, box))
