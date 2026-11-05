#!/usr/bin/env python3
"""Rebuild the lightweight transparent GIF preview from the Python renderer.
Needs Pillow only for export; core rendering is stdlib only.
"""
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
from forty_two import render_42

HERE = Path(__file__).resolve().parent
OUT = HERE / 'assets'
OUT.mkdir(exist_ok=True)
W, H = 72, 28
font = ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf', 14)
# Monospaced font effective advance is about 8.43px at 14pt.
char_w = math.ceil(font.getlength('M'))
char_h = 16
size = (W * char_w + 12, H * char_h + 12)
frames = []
count = 96
for i in range(count):
    t = i / count
    # Full X and Y cycles for a seamless, self-contained preview.
    a = math.tau * t / 0.72
    b = math.tau * t / 1.20
    lines = render_42(W, H, a, b, 0, now=t)
    mono = Image.new('L', size, 0)
    drawer = ImageDraw.Draw(mono)
    for row, line in enumerate(lines):
        if line.strip():
            drawer.text((6, row * char_h + 1), line, fill=255, font=font, stroke_width=0)
    # Two-color indexed image with transparent background; black pixels = transparent.
    mono = mono.point(lambda v: 255 if v > 120 else 0)
    pal = Image.new('P', size, 0)
    palette = [0, 0, 0, 255, 78, 78] + [0] * (768 - 6)
    pal.putpalette(palette)
    pal.paste(1, (0, 0, size[0], size[1]), mono)
    frames.append(pal)

frames[0].save(OUT / '42-spinning-transparent.gif', save_all=True,
    append_images=frames[1:], duration=83, loop=0, transparency=0,
    disposal=2, optimize=True)

background = Image.new('RGBA', size, (7, 7, 7, 255))
mask = frames[0].convert('L').point(lambda v: 255 if v > 0 else 0)
red = Image.new('RGBA', size, (255, 78, 78, 255))
background.paste(red, (0, 0), mask)
background.convert('RGB').save(OUT / '42-preview.png', optimize=True)
print('GIF size:', (OUT / '42-spinning-transparent.gif').stat().st_size)
print('GIF frames:', len(frames), 'Canvas:', size)
