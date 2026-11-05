#!/usr/bin/env python3
"""Portable original-style spinning ASCII 42 (stdlib only).

Geometry, glyphs, lighting, perspective and 14 FPS rotation are adapted from
/usr/local/bin/mc-donut-v2 on mc-ai-server, read 2026-11-03.
All Eggys/CENTRUM monitoring, hotkeys, Linux APIs and HUD are intentionally removed.

Example: python3 forty_two.py --color red
         python3 forty_two.py --frames 1 --plain
"""
from __future__ import annotations
import argparse
import math
import os
import shutil
import signal
import sys
import time

LUMINANCE = ".,-~:;=!*#$@"
DIGIT_4 = (
    "100100",
    "100100",
    "100100",
    "100100",
    "111111",
    "000100",
    "000100",
    "000100",
    "000100",
)
DIGIT_2 = (
    "111110",
    "000010",
    "000010",
    "000010",
    "111110",
    "100000",
    "100000",
    "100000",
    "111110",
)


def build_42_points():
    """Original extruded voxel cloud; only exposed side walls are sampled."""
    cells = set()
    gap = 2
    for offset, glyph in ((0, DIGIT_4), (len(DIGIT_4[0]) + gap, DIGIT_2)):
        h = len(glyph)
        for row, line in enumerate(glyph):
            for col, bit in enumerate(line):
                if bit == "1":
                    cells.add((offset + col, h - 1 - row))

    min_x = min(x for x, _ in cells)
    max_x = max(x for x, _ in cells) + 1
    min_y = min(y for _, y in cells)
    max_y = max(y for _, y in cells) + 1
    cx = (min_x + max_x) / 2.0
    cy = (min_y + max_y) / 2.0

    cell = 0.46
    half_depth = 0.56
    surface_steps = (0.08, 0.31, 0.54, 0.77, 0.96)
    edge_steps = (0.08, 0.31, 0.54, 0.77, 0.96)
    depth_steps = (-0.56, -0.30, 0.0, 0.30, 0.56)
    pts = []

    def add(px, py, pz, nx, ny, nz):
        pts.append((px * cell, py * cell, pz, nx, ny, nz))

    for x, y in cells:
        x0 = x - cx
        y0 = y - cy
        for u in surface_steps:
            for v in surface_steps:
                px = x0 + u
                py = y0 + v
                add(px, py, -half_depth, 0.0, 0.0, -1.0)
                add(px, py, +half_depth, 0.0, 0.0, +1.0)

        if (x - 1, y) not in cells:
            for v in edge_steps:
                for z in depth_steps:
                    add(x0, y0 + v, z, -1.0, 0.0, 0.0)
        if (x + 1, y) not in cells:
            for v in edge_steps:
                for z in depth_steps:
                    add(x0 + 1.0, y0 + v, z, +1.0, 0.0, 0.0)
        if (x, y - 1) not in cells:
            for u in edge_steps:
                for z in depth_steps:
                    add(x0 + u, y0, z, 0.0, -1.0, 0.0)
        if (x, y + 1) not in cells:
            for u in edge_steps:
                for z in depth_steps:
                    add(x0 + u, y0 + 1.0, z, 0.0, +1.0, 0.0)

    return tuple(pts)


FORTY_TWO_POINTS = build_42_points()


def render_42(width: int, height: int, a: float = 0.0, b: float = 0.0, load: float = 0.0, now: float | None = None) -> list[str]:
    """Pure renderer: 3D rotation, camera-space normals, perspective, z-buffer."""
    width, height = max(1, int(width)), max(1, int(height))
    zbuffer = [0.0 for _ in range(width * height)]
    output = [" " for _ in range(width * height)]

    normalized = max(0.0, min(1.0, load / 100.0))
    cos_a = math.cos(a * 0.72)
    sin_a = math.sin(a * 0.72)
    cos_b = math.cos(b * 1.20)
    sin_b = math.sin(b * 1.20)
    pulse = 1.0 + math.sin((time.monotonic() if now is None else now) * 3.0) * normalized * 0.025
    scale_x = min(width * 0.58, height * 2.55) * pulse
    scale_y = scale_x * 0.48
    camera = 8.3
    lx, ly, lz = -0.35, 0.55, -0.76

    for x, y, z, nx, ny, nz in FORTY_TWO_POINTS:
        y1 = y * cos_a - z * sin_a
        z1 = y * sin_a + z * cos_a
        ny1 = ny * cos_a - nz * sin_a
        nz1 = ny * sin_a + nz * cos_a
        x2 = x * cos_b + z1 * sin_b
        z2 = -x * sin_b + z1 * cos_b
        nx2 = nx * cos_b + nz1 * sin_b
        nz2 = -nx * sin_b + nz1 * cos_b

        depth = camera + z2
        if depth <= 0.3:
            continue
        inv_z = 1.0 / depth
        xp = int(width / 2 + scale_x * inv_z * x2)
        yp = int(height / 2 - scale_y * inv_z * y1)
        if not (0 <= xp < width and 0 <= yp < height):
            continue
        idx = xp + width * yp
        if inv_z <= zbuffer[idx]:
            continue
        zbuffer[idx] = inv_z

        dot = nx2 * lx + ny1 * ly + nz2 * lz
        brightness = 0.22 + 0.78 * max(0.0, dot)
        lum_index = int(brightness * (len(LUMINANCE) - 1))
        lum_index = max(0, min(len(LUMINANCE) - 1, lum_index))
        output[idx] = LUMINANCE[lum_index]

    return ["".join(output[y * width:(y + 1) * width]) for y in range(height)]


ANSI_COLORS = {"red": "\x1b[91m", "cyan": "\x1b[96m", "green": "\x1b[92m", "yellow": "\x1b[93m", "none": ""}


def main():
    parser = argparse.ArgumentParser(description="Portable rotating 3D ASCII 42")
    parser.add_argument("--color", choices=ANSI_COLORS, default="red")
    parser.add_argument("--fps", type=float, default=14)
    parser.add_argument("--load", type=float, default=0, help="0-100, affects speed/pulse like the server")
    parser.add_argument("--frames", type=int, default=0, help="0 = until Ctrl+C")
    parser.add_argument("--width", type=int, default=0, help="fixed columns (default: terminal size)")
    parser.add_argument("--height", type=int, default=0, help="fixed rows (default: terminal size)")
    parser.add_argument("--plain", action="store_true", help="no ANSI or cursor control")
    args = parser.parse_args()
    if args.fps <= 0:
        parser.error("--fps must be > 0")
    if not sys.stdout.isatty() and args.frames == 0:
        parser.error("non-interactive output needs --frames N to avoid infinite redirected output")

    a, b = 0.0, 0.0
    load = max(0, min(args.load, 100))
    use_ansi = not args.plain and sys.stdout.isatty()
    if use_ansi:
        sys.stdout.write("\x1b[?25l\x1b[2J")
    try:
        frame = 0
        while args.frames == 0 or frame < args.frames:
            start = time.monotonic()
            size = shutil.get_terminal_size((90, 32))
            w = args.width or max(30, size.columns - 1)
            h = args.height or max(12, size.lines - 1)
            lines = render_42(w, h, a, b, load)
            picture = "\n".join(lines)
            if use_ansi:
                sys.stdout.write("\x1b[H" + ANSI_COLORS[args.color] + picture + "\x1b[0m\x1b[J")
            else:
                sys.stdout.write(picture + "\n")
                if args.frames != 1:
                    sys.stdout.write("\n--- FRAME ---\n")
            sys.stdout.flush()
            n = load / 100.0
            a += 0.022 + n * 0.045
            b += 0.011 + n * 0.025
            frame += 1
            time.sleep(max(0.0, (1 / args.fps) - (time.monotonic() - start)))
    except KeyboardInterrupt:
        pass
    finally:
        if use_ansi:
            sys.stdout.write("\x1b[0m\x1b[?25h\n")
            sys.stdout.flush()


if __name__ == "__main__":
    main()
