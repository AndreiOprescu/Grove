#!/usr/bin/env python3
"""Draws the leaf icons of the system tray (app/assets/tray/).

Run it again only when the shape changes:  python3 scripts/make_tray_icons.py
It needs no package: the PNG files are written by hand.
The same shape is in app/android/app/src/main/res/drawable/ic_notification.xml.
"""
import math
import os
import struct
import zlib

# The leaf, on a 24 x 24 grid: two arcs from the base to the tip, and a stem.
BASE, TIP, RADIUS = (5.0, 19.0), (20.0, 4.0), 14.0
STEM = ((5.5, 18.5), (3.0, 21.0), 1.0)
RIB = ((8.5, 15.5), (15.0, 9.0), 0.55)


def _centres():
    mx, my = (BASE[0] + TIP[0]) / 2, (BASE[1] + TIP[1]) / 2
    half = math.dist(BASE, TIP) / 2
    away = math.sqrt(RADIUS**2 - half**2)
    nx, ny = 1 / math.sqrt(2), 1 / math.sqrt(2)
    return (mx + away * nx, my + away * ny), (mx - away * nx, my - away * ny)


CENTRES = _centres()


def _near(p, line):
    (ax, ay), (bx, by), radius = line
    dx, dy = bx - ax, by - ay
    t = max(0.0, min(1.0, ((p[0] - ax) * dx + (p[1] - ay) * dy) / (dx * dx + dy * dy)))
    return math.dist(p, (ax + t * dx, ay + t * dy)) <= radius


def inside(p, rib):
    if _near(p, STEM):
        return True
    if not all(math.dist(p, c) <= RADIUS for c in CENTRES):
        return False
    return not (rib and _near(p, RIB))


def draw(size, colour, rib):
    samples = 4
    rows = []
    for y in range(size):
        row = bytearray([0])  # PNG filter: none
        for x in range(size):
            hits = 0
            for sy in range(samples):
                for sx in range(samples):
                    p = ((x + (sx + 0.5) / samples) * 24 / size, (y + (sy + 0.5) / samples) * 24 / size)
                    hits += inside(p, rib)
            row += bytes([*colour, round(255 * hits / samples**2)])
        rows.append(bytes(row))
    return b"".join(rows)


def chunk(kind, data):
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))


def write(path, size, colour, rib):
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(draw(size, colour, rib), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


if __name__ == "__main__":
    out = os.path.join(os.path.dirname(__file__), "..", "app", "assets", "tray")
    os.makedirs(out, exist_ok=True)
    # macOS: a black shape. The system colours it for a light or a dark menu bar.
    write(os.path.join(out, "leaf_template.png"), 36, (0, 0, 0), rib=False)
    # Windows: a green leaf that shows on a light and on a dark taskbar.
    write(os.path.join(out, "leaf.png"), 64, (76, 160, 104), rib=True)
