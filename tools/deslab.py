#!/usr/bin/env python3
"""Cuts the raised slab of ground some generated buildings stand on out of their sprites, so they
stand on the map's own ground like the rest (a square of grass with thick sides under a house
reads as a strange block on the map). Flood fills from the sprite's bottom rows through the
slab's colours only, so the same colours inside the building (a window's glint, green stone)
stay, then drops any lone pixels left over. Rerun it after regenerating one of these sprites.

  python3 tools/deslab.py              all of them
  python3 tools/deslab.py inn          just these
"""
import colorsys
import sys
from collections import deque
from pathlib import Path

from PIL import Image

SPRITES = Path(__file__).resolve().parent.parent / "art" / "sprites"


def grass(hue, s, v, minimum):
    return 50 <= hue <= 170 and s > minimum


def soil(hue, s, v):
    return (hue <= 60 or hue >= 340) and (s > 0.45 or (v < 0.3 and s > 0.25))


# Per sprite: which colours are slab, and from which row down to start filling.
SLABS = {
    # A square of grass with dark green sides.
    "inn": {"slab": lambda h, s, v: grass(h, s, v, 0.2), "from": 70},
    # A grassy island with soil underneath; its stone is a grey green, so only strong greens.
    "magic_tower": {"slab": lambda h, s, v: grass(h, s, v, 0.4) or soil(h, s, v), "from": 70},
}


def deslab(name):
    path = SPRITES / f"{name}.png"
    image = Image.open(path).convert("RGBA")
    width, height = image.size
    pixels = image.load()
    slab = SLABS[name]["slab"]

    def part(x, y):
        r, g, b, a = pixels[x, y]
        if a == 0:
            return False
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        return slab(h * 360, s, v)

    seen = {(x, y) for y in range(SLABS[name]["from"], height) for x in range(width) if part(x, y)}
    queue = deque(seen)
    while queue:
        x, y = queue.popleft()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < width and 0 <= ny < height and (nx, ny) not in seen and part(nx, ny):
                seen.add((nx, ny))
                queue.append((nx, ny))
    for spot in seen:
        pixels[spot] = (0, 0, 0, 0)
    # Lone pixels the slab's edge left behind.
    lone = [(x, y) for y in range(height) for x in range(width) if pixels[x, y][3] > 0
            and not any(0 <= x + dx < width and 0 <= y + dy < height and pixels[x + dx, y + dy][3] > 0
                        for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy)]
    for spot in lone:
        pixels[spot] = (0, 0, 0, 0)
    image.save(path)
    print(f"{name}: cut {len(seen)} pixels of slab and {len(lone)} lone ones")


if __name__ == "__main__":
    for name in sys.argv[1:] or SLABS:
        deslab(name)
