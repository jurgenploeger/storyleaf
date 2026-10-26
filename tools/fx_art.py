#!/usr/bin/env python3
"""Art for the few battle marks that aren't light, drawn in code like tools/item_art.py (free):
writes art/sprites/fx_<name>.png. The elemental spells themselves are drawn in light and colour
(TalesOfDorlune/Battle/ElementEffects.swift); these are poison's bubbles (AilmentEffects.swift) and the
marks by a fighter's HP bar: poison (a purple drop), lowered stats (a crimson arrow down, a curse's)
and raised ones (a blue arrow up, a buff's). The bubble is pixel art; the marks are smooth and glossy,
drawn at 3x and shown at a third of their size.

    python3 tools/fx_art.py                  # every sprite
    python3 tools/fx_art.py --sheet out.png  # also a 4x contact sheet to look at
"""

import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from item_art import SPRITES, encode_png, hexc  # noqa: E402

WATER = [hexc("0e3c74"), hexc("1c6ab0"), hexc("48a8f0"), hexc("a8dcff"), hexc("ffffff")]


class Canvas:
    """A width × height pixel canvas (item_art's Canvas is square)."""

    def __init__(self, width, height):
        self.w, self.h = width, height
        self.px = [[None] * width for _ in range(height)]

    def set(self, x, y, color):
        x, y = int(round(x)), int(round(y))
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = color

    def png(self, scale=1):
        rows = []
        for y in range(self.h * scale):
            row = bytearray([0])
            for x in range(self.w * scale):
                row += bytes(self.px[y // scale][x // scale] or (0, 0, 0, 0))
            rows.append(bytes(row))
        return encode_png(self.w * scale, self.h * scale, b"".join(rows))


def pixels(rows, palette):
    """A canvas from rows of characters, each a key of `palette` ('.' is empty)."""
    c = Canvas(len(rows[0]), len(rows))
    for y, row in enumerate(rows):
        for x, key in enumerate(row):
            if key != ".":
                c.px[y][x] = palette[key]
    return c


# ---------------------------------------------------------------- poison

def bubble():
    c = Canvas(9, 9)
    for i in range(48):
        a = i / 48 * math.tau
        c.set(4 + math.cos(a) * 3.4, 4 + math.sin(a) * 3.4, WATER[3])
    c.set(3, 2, WATER[4])
    c.set(2, 3, WATER[4])
    return c


# ---------------------------------------------------------------- the marks by the HP bar

# Glossy marks, drawn smooth at 3x (33 x 39 px, shown 11 x 13 pt by BattleScene): a dark outline, a
# fill that deepens downward, a white sheen over the top and a glint, and a soft shadow underneath.
MARK_W, MARK_H = 33, 39
POISON = {"line": hexc("2c0e4a"), "stops": [hexc("efd8ff"), hexc("a45ef0"), hexc("5a22a0")]}
CURSE = {"line": hexc("3d0a18"), "stops": [hexc("ffb4c0"), hexc("e8485f"), hexc("8e1631")]}
RAISE = {"line": hexc("0c2f63"), "stops": [hexc("b4e8ff"), hexc("3fa6f2"), hexc("1b5fc0")]}


def sd_polygon(x, y, verts):
    """Signed distance from (x, y) to a polygon: negative inside."""
    d = (x - verts[0][0]) ** 2 + (y - verts[0][1]) ** 2
    s = 1.0
    j = len(verts) - 1
    for i in range(len(verts)):
        ex, ey = verts[j][0] - verts[i][0], verts[j][1] - verts[i][1]
        wx, wy = x - verts[i][0], y - verts[i][1]
        t = max(0.0, min(1.0, (wx * ex + wy * ey) / (ex * ex + ey * ey)))
        d = min(d, (wx - ex * t) ** 2 + (wy - ey * t) ** 2)
        above, below, side = y >= verts[i][1], y < verts[j][1], ex * wy > ey * wx
        if (above and below and side) or (not above and not below and not side):
            s = -s
        j = i
    return s * math.sqrt(d)


def smooth_min(a, b, k):
    h = max(0.0, min(1.0, 0.5 + 0.5 * (b - a) / k))
    return b + (a - b) * h - k * h * (1 - h)


def glossy(shape, colors, glint):
    """A mark from `shape(x, y)` (signed distance in px, negative inside): outlined, shaded from light
    at the top to deep at the bottom, a sheen over its upper part, a glint at `glint`, and a shadow."""
    c = Canvas(MARK_W, MARK_H)
    rows = [y + 0.5 for y in range(MARK_H) if any(shape(x + 0.5, y + 0.5) < 0 for x in range(MARK_W))]
    top, bottom = rows[0], rows[-1]
    line, (light, mid, deep) = colors["line"], colors["stops"]

    def mix(a, b, t):
        return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))

    def over(under, color, alpha):   # (r, g, b, a) straight alpha, `color` laid over it
        out = alpha + under[3] * (1 - alpha)
        if out <= 0:
            return (0, 0, 0, 0)
        return tuple((color[i] * alpha + under[i] * under[3] * (1 - alpha)) / out for i in range(3)) + (out,)

    for y in range(MARK_H):
        for x in range(MARK_W):
            px, py = x + 0.5, y + 0.5
            d = shape(px, py)
            pixel = (0, 0, 0, 0)
            shadow = max(0.0, min(1.0, (0.9 - shape(px, py - 1.6)) / 1.8))
            pixel = over(pixel, (0, 0, 0), 0.32 * shadow)
            pixel = over(pixel, line[:3], max(0.0, min(1.0, 0.5 - d)))
            fill = max(0.0, min(1.0, 0.5 - (d + 2.0)))
            if fill > 0:
                t = max(0.0, min(1.0, (py - top) / (bottom - top)))
                color = mix(light, mid, t / 0.45) if t < 0.45 else mix(mid, deep, (t - 0.45) / 0.55)
                # The sheen: white over the top 45%, strongest at the top, a crisp lower edge.
                u = (py - top) / ((bottom - top) * 0.45)
                if u < 1 and d < -3.2:
                    color = mix(color, (255, 255, 255), 0.42 * (1 - u) ** 0.7 * min(1.0, 1.15 - u))
                g = math.hypot((px - glint[0]) / 2.6, (py - glint[1]) / 1.9)
                color = mix(color, (255, 255, 255), 0.9 * max(0.0, min(1.0, 1.4 - g)))
                pixel = over(pixel, color, fill)
            c.px[y][x] = tuple(int(round(v)) for v in pixel[:3]) + (int(round(pixel[3] * 255)),) if pixel[3] > 0 else None
    return c


def arrow(up):
    """An arrow's signed distance: a wide head and a shaft, corners rounded, pointing up or down."""
    core = [(16.5, 3.4), (29.6, 16.6), (22.4, 16.6), (22.4, 33.4), (10.6, 33.4), (10.6, 16.6), (3.4, 16.6)]
    if not up:
        core = [(x, 36.8 - y) for x, y in reversed(core)]
    return lambda x, y: sd_polygon(x, y, core) - 1.6


def status_poison():
    """Poison's mark by a fighter's HP bar: a glossy purple drop."""
    def drop(x, y):
        round_part = math.hypot(x - 16.5, y - 24.5) - 10.5
        point = sd_polygon(x, y, [(16.5, 2.2), (25.8, 19.5), (7.2, 19.5)])
        return smooth_min(round_part, point, 3.0)
    return glossy(drop, POISON, glint=(11.8, 20.0))


def status_curse():
    """A curse's mark: a glossy crimson arrow pointing down, for lowered stats."""
    return glossy(arrow(up=False), CURSE, glint=(13.0, 7.5))


def status_raise():
    """A buff's mark: a glossy blue arrow pointing up, for raised stats."""
    return glossy(arrow(up=True), RAISE, glint=(11.5, 11.5))


# ---------------------------------------------------------------- all of it

def sprites():
    return {
        "fx_bubble": bubble(),
        "fx_status_poison": status_poison(),
        "fx_status_curse": status_curse(),
        "fx_status_raise": status_raise(),
    }


def contact_sheet(art, path, zoom=4):
    from PIL import Image
    names = sorted(art)
    cell = 48 * zoom + 8
    cols = 8
    sheet = Image.new("RGB", (cols * cell, ((len(names) + cols - 1) // cols) * (cell + 14)), (88, 140, 88))
    import io
    for i, name in enumerate(names):
        img = Image.open(io.BytesIO(art[name].png(zoom)))
        x = (i % cols) * cell + (cell - img.width) // 2
        y = (i // cols) * (cell + 14) + 12 + (cell - img.height) // 2
        sheet.paste(img, (x, y), img)
        from PIL import ImageDraw
        ImageDraw.Draw(sheet).text(((i % cols) * cell + 4, (i // cols) * (cell + 14)), name[3:], fill=(255, 255, 255))
    sheet.save(path)


def main():
    art = sprites()
    for name, canvas in art.items():
        (SPRITES / f"{name}.png").write_bytes(canvas.png())
    print(f"wrote {len(art)} sprites to art/sprites/fx_*.png")
    if "--sheet" in sys.argv:
        path = sys.argv[sys.argv.index("--sheet") + 1]
        contact_sheet(art, path)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
