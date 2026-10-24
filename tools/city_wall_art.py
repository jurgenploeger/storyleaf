#!/usr/bin/env python3
"""A city's stone wall and its round towers (`TownFence.place`, maps.json town `walls: "stone"`), drawn in
the game's pixel style (docs/pixel-style.md) instead of the flat blocks `BorderArt` drew in Swift: rough-cut
stones of varied sizes in courses, each lit along its top and left and shaded along its bottom and right,
hue-shifted greys (cool in shadow, warm in the light), crenellations with a lit coping, moss and a dark
plinth at the foot, and a tinted outline, a deep shade of the stone. The game grades both with the map's
palette, as it did the old ones.

    python3 tools/city_wall_art.py                 # → art/sprites/city_wall.png, city_tower.png
    python3 tools/city_wall_art.py --sheet out.png # both at 6×, the wall repeated as the game runs it

`city_wall` is one cell's stretch, face on, 24 × 32 pixels for the wall's 32 points (`BorderArt.wallHeight`),
which `TownFence.pieces` slants along each side of the wall's cells: it tiles from side to side (each
course's stones wrap round), so stretches run on as one wall, and it has no outline at its sides. Its
merlons stand on the cell's quarters, a gap at its middle and its ends, so the halves a corner turns
between (`TownFence.pieces` draws each half of the cell along one side) look alike. `city_tower` is a round
tower 30 × 60 pixels for its 30 × 60 points (`BorderArt.towerSize`), its foot on its bottom rows.
Needs pillow + numpy.
"""

import math
import pathlib
import sys

import numpy as np
from PIL import Image


ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"

# The stone: the town gate's (RD's) cool slate grey, its shadows turned toward blue-violet and its
# lights a touch warm, as RD shades it (#25252b, #3a3e41, #646867, #a3a8a4 are the gate's own); the grass
# at the foot the gate's greens.
STONE = [(0x1f, 0x1f, 0x27), (0x2b, 0x2c, 0x34), (0x3a, 0x3e, 0x41), (0x4b, 0x50, 0x51), (0x5d, 0x62, 0x62),
         (0x72, 0x77, 0x75), (0x8b, 0x90, 0x8b), (0xa3, 0xa8, 0xa4), (0xbd, 0xc0, 0xb7)]
GRASS = [(0x1e, 0x2e, 0x16), (0x26, 0x34, 0x19), (0x35, 0x55, 0x22), (0x49, 0x74, 0x2f), (0x66, 0x93, 0x3f),
         (0x82, 0xaf, 0x50)]
MORTAR = -1.0                              # light below every stone's: a joint


def to_image(light, alpha):
    """An RGBA image from light (0 dark … 1 lit, on the stone's ramp), clear where not `alpha`."""
    index = np.clip(np.round(np.nan_to_num(light, nan=0.0) * (len(STONE) - 1)), 0, len(STONE) - 1).astype(int)
    out = np.zeros(light.shape + (4,), np.uint8)
    out[..., :3] = np.array(STONE, np.uint8)[index]
    out[..., 3] = np.where(alpha, 255, 0)
    return out


def outline(img, wrap_x=False, deep=0):
    """A tinted outline, `deep` on the stone's ramp (not black: docs/pixel-style.md, rule 7), on every
    opaque pixel next to a clear one (round the sides too unless `wrap_x`,
    where the picture runs on into the next copy of itself); a top edge facing the light a shade lighter,
    as the light hits it."""
    a = img[..., 3] > 0
    pad = np.pad(a, 1, mode="constant")
    if wrap_x:
        pad[1:-1, 0], pad[1:-1, -1] = a[:, -1], a[:, 0]
    up, down = ~pad[:-2, 1:-1], ~pad[2:, 1:-1]
    left, right = ~pad[1:-1, :-2], ~pad[1:-1, 2:]
    edge = a & (up | down | left | right)
    out = img.copy()
    top_lit = edge & up & ~left & ~right & ~down
    out[edge & ~top_lit, :3] = np.array(STONE[deep], np.uint8)
    out[top_lit, :3] = np.array(STONE[3], np.uint8)
    return out


def rubble(dy, ch, p, wd, base, tone, pit=False):
    """The light on one pixel of a rough-cut stone `wd` × `ch` (joints included: its last row and column
    are the joint), `p` and `dy` into it: rounded as RD's stones are, each a lump lit on its upper left and
    deep on its lower right, its corners worn into the joints."""
    if dy >= ch - 1 or p >= wd - 1:
        return MORTAR
    inner_w, inner_h = wd - 1, ch - 1
    corner = (dy in (0, inner_h - 1)) and (p in (0, inner_w - 1))
    if corner and inner_w > 2 and inner_h > 2 and not (dy == 0 and p == 0):
        return MORTAR if (dy == inner_h - 1 and p == inner_w - 1) else base + tone - 0.3
    fx = (p + 0.5) / inner_w
    fy = (dy + 0.5) / inner_h
    v = base + tone + 0.42 * (0.5 - fy) + 0.2 * (0.5 - fx)
    if dy == 0 and fx < 0.75:
        v += 0.18                          # its top edge catching the light
    if dy == inner_h - 1 or p == inner_w - 1:
        v -= 0.12                          # the edge turned from it
    if pit:
        v -= 0.16
    return v


def courses_along(width, heights, seed, min_w=4, max_w=8):
    """Stones laid in courses `heights` tall, each course's stones of widths `min_w` … `max_w` (joint
    included) adding up to `width` and wrapping round it, the joints apart from the course above.
    Returns for each course a list over x of (stone number, x into it, its width)."""
    rng = np.random.default_rng(seed)
    layout, number = [], 0
    for _ in heights:
        widths = []
        while sum(widths) < width:
            widths.append(int(rng.integers(min_w, max_w + 1)))
        excess = sum(widths) - width
        while excess > 0:
            i = int(np.argmax(widths))
            take = min(excess, widths[i] - min_w)
            widths[i] -= take
            excess -= take
        start = int(rng.integers(0, width))
        row = [None] * width
        x = start
        for wd in widths:
            for k in range(wd):
                row[(x + k) % width] = (number, k, wd)
            x += wd
            number += 1
        layout.append(row)
    return layout


def grass(img, feet, seed, tufts):
    """Tufts of grass at the foot, as the gate's: blades up from the ground, dark at the root, lit at
    the tips. `feet[x]`: the row the ground is at in column x (or None); `tufts`: (x, height) pairs."""
    rng = np.random.default_rng(seed)
    green = np.array(GRASS, np.uint8)
    h, w = img.shape[:2]
    for x, tall in tufts:
        for dx, t in ((0, tall), (-1, max(1, tall - 2)), (1, max(1, tall - 1))):
            col = (x + dx) % w
            if feet[col] is None:
                continue
            for k in range(t):
                y = feet[col] - k
                if 0 <= y < h:
                    shade = 1 + min(4, int((k + 1) / t * 4.0 + rng.random() * 0.6))
                    img[y, col, :3] = green[shade]
                    img[y, col, 3] = 255
    return img


# ------------------------------------------------------------------------------------------ the wall

WALL_W, WALL_H = 24, 32


def city_wall():
    w, h = WALL_W, WALL_H
    yy, xx = np.mgrid[0:h, 0:w]
    light = np.full((h, w), np.nan)
    alpha = np.zeros((h, w), bool)
    rng = np.random.default_rng(3)
    tones = rng.normal(0, 0.05, 512)
    pits = rng.random((h, w)) < 0.05

    # Merlons on the cell's quarters, 7 wide with 5 between (two a cell), a gap at the middle and the ends,
    # so a corner's two halves look alike: rows 0 … 6, each one stone under a capstone lit on top.
    for left in (3, 15):
        for y in range(0, 7):
            for k in range(7):
                x = left + k
                if y < 2:
                    v = 0.82 if y == 0 else 0.66                       # the capstone, seen from above
                    v -= 0.08 * (k / 6)
                    if k == 6:
                        v -= 0.16
                else:
                    v = rubble(y - 2, 6, k, 8 if k < 7 else 7, 0.56, tones[left])   # one stone, its joint under it
                    if k == 6:
                        v = (v if v != MORTAR else 0.3) - 0.12                         # its right side, in shade
                light[y, x] = v
                alpha[y, x] = True
    # The coping along the wall-walk, rows 7 … 8: long slabs lit on top, a shadow line under them.
    alpha[7:9] = True
    for x in range(w):
        joint = (x + 2) % 12 == 0
        light[7, x] = 0.56 if joint else 0.78 - 0.04 * ((x + 2) % 12) / 11
        light[8, x] = 0.22 if joint else 0.5
    # Courses of rubble, rows 9 … 28: 5, 4, 6 and 5 tall, stones 4 to 8 wide wrapping round the stretch.
    heights = [5, 4, 6, 5]
    layout = courses_along(w, heights, seed=11)
    y = 9
    for course, ch in zip(layout, heights):
        for dy in range(ch):
            for x in range(w):
                number, p, wd = course[x]
                base = 0.58 - 0.01 * (y - 9)                            # a little darker toward the foot
                light[y, x] = rubble(dy, ch, p, wd, base, tones[(number * 7) % 512], pits[y, x])
            alpha[y] = True
            y += 1
    # Under the coping, its shadow on the top course.
    light[9] -= 0.12
    # The footing, rows 29 … 31: big flat stones stepping out, their top lit, dark into the ground.
    alpha[29:32] = True
    for x in range(w):
        joint = (x + 5) % 8 == 0
        light[29, x] = MORTAR if joint else 0.62
        light[30, x] = MORTAR if joint else 0.4
        light[31, x] = 0.18
    img = to_image(light, alpha)
    img = outline(img, wrap_x=True)
    # Grass up against its foot, more in some places than others, wrapping round the stretch.
    return grass(img, [h - 1] * w, 5, [(1, 4), (4, 2), (9, 3), (14, 2), (18, 5), (21, 3)])


# ------------------------------------------------------------------------------------------ the tower

TOWER_W, TOWER_H = 30, 60


def city_tower():
    w, h = TOWER_W, TOWER_H
    cx, r = 15.0, 12.0                    # the shaft's middle and half-width
    light = np.full((h, w), np.nan)
    alpha = np.zeros((h, w), bool)
    rng = np.random.default_rng(21)
    tones = rng.normal(0, 0.05, 512)
    pits = rng.random((h, w)) < 0.05

    def across(x, radius):
        u = (x + 0.5 - cx) / radius
        return u, math.sqrt(max(0.0, 1 - u * u))

    def round_light(u, b):
        """A cylinder lit from the upper left: brightest left of the middle, deep down its right side."""
        return 0.56 + 0.26 * (-0.7 * u + 0.5 * b) - 0.1

    # The shaft, rows 18 … its foot (an arc: it's round, seen from a little above), in courses that sag
    # the same way, stones laid round it by angle so they narrow toward its sides.
    heights = [5, 4, 5, 5, 4, 5, 5, 4]
    stones_round = 9                      # stones across the visible half, in each course
    for x in range(w):
        u, b = across(x, r)
        if abs(u) > 1:
            continue
        angle = math.asin(u) / math.pi + 0.5                           # 0 … 1 round the front
        foot = int(round(53 + 2.5 * b))
        sag = int(round(2.0 * b))
        for y in range(16, foot + 1):
            yc = y - 16 - sag
            if yc < 0:
                light[y, x] = round_light(u, b) - 0.34                 # under the corbels, in shadow
                alpha[y, x] = True
                continue
            course, dy, top = 0, yc, 0
            while course < len(heights) - 1 and dy >= heights[course]:
                dy -= heights[course]
                course += 1
            ch = heights[course]
            pos = angle * stones_round + (0.5 if course % 2 else 0.0)
            n = int(pos)
            # Each stone's width in pixels where it's widest (the middle), shrinking toward the sides.
            frac = pos - n
            wd = max(3, int(round(r * 2 / stones_round * (0.4 + 1.5 * b))))
            p = min(wd - 1, int(frac * wd))
            v = rubble(dy, ch, p, wd, round_light(u, b), tones[(course * 31 + n) % 512], pits[y, x])
            if abs(u) > 0.9 and v != MORTAR:
                v -= 0.08                                              # turning away at its edges
            light[y, x] = v
            alpha[y, x] = True
    # The plinth: a course stepping out a pixel each side, its top lit, dark into the ground.
    feet = [None] * w
    for x in range(w):
        u, b = across(x, r + 1)
        if abs(u) > 1:
            continue
        bottom = int(round(54 + 2.5 * b))
        feet[x] = bottom
        for y in range(bottom - 2, bottom + 1):
            joint = int((math.asin(u) / math.pi + 0.5) * 6) != int((math.asin(max(-1, u - 0.08)) / math.pi + 0.5) * 6)
            v = round_light(u, b) + (0.14 if y == bottom - 2 else (-0.1 if y == bottom - 1 else -0.3))
            light[y, x] = MORTAR if joint and y < bottom else v
            alpha[y, x] = True

    # The parapet, corbelled out wider than the shaft. Seen from a little above: the back of its rim
    # across the top (back merlons standing on it), the walk inside dark, and the front band of stone
    # below the front rim, its merlons standing up from it.
    pr, top, depth = r + 2, 9.5, 4.2      # the rim's half-width, its middle row, how deep the ellipse looks
    merlon_h = 5
    slots = 5                             # merlons and gaps by turns round the front, a merlon at each end
    for x in range(w):
        u, b = across(x, pr)
        if abs(u) > 1:
            continue
        front, back = top + depth * b, top - depth * b
        slot = int((math.asin(u) / math.pi + 0.5) * slots)
        slot = min(slot, slots - 1)
        frac = (math.asin(u) / math.pi + 0.5) * slots - slot
        merlon = slot % 2 == 0
        lit = round_light(u, b) + 0.06
        # The band below the front rim: two courses of stones, rows front … front + 7.
        for y in range(int(math.ceil(front)), int(round(front + 7.5)) + 1):
            dy = y - math.ceil(front)
            if dy == 0:
                v = lit + 0.2                                           # the rim's lit edge
            elif dy >= 7:
                v = MORTAR                                              # its foot, over the corbels
            else:
                ch, d = (3, dy - 1) if dy < 4 else (4, dy - 4)
                pos = (math.asin(u) / math.pi + 0.5) * 8 + (0.5 if dy >= 4 else 0)
                wd = max(3, int(round(3 + 2 * b)))
                v = rubble(d, ch, min(wd - 1, int((pos % 1) * wd)), wd, lit, tones[(int(pos) + 50 * (dy >= 4)) % 512])
            light[y, x] = v
            alpha[y, x] = True
        # The corbels under it: brackets two rows deep, dark between them.
        y0 = int(round(front + 8.5))
        bracket = int((math.asin(u) / math.pi + 0.5) * 11) % 2 == 0
        for k in range(2):
            if y0 + k < h and abs(u) < 0.97:
                light[y0 + k, x] = (lit - 0.02 - 0.12 * k) if bracket else MORTAR
                alpha[y0 + k, x] = True
        # The walk inside, between the back rim and the front: dark, a little lighter toward the back.
        for y in range(int(math.floor(back)) + 1, int(math.ceil(front))):
            rel = (y - back) / max(1.0, front - back)
            if y - back < 1.5:
                v = 0.36 - 0.14 * u                                     # the back rim's inner face, lit from the left
            else:
                v = 0.16 - 0.06 * rel
            light[y, x] = v
            alpha[y, x] = True
        # The back rim's top and, behind the front gaps, the back merlons up on it.
        y = int(math.floor(back))
        light[y, x] = 0.7 - 0.2 * u
        alpha[y, x] = True
        if not merlon and abs(u) < 0.85:
            for k in range(1, merlon_h):
                light[y - k, x] = (0.74 if k == merlon_h - 1 else 0.56) - 0.24 * u - (0.12 if frac > 0.75 else 0)
                alpha[y - k, x] = True
        # The front merlons, up from the front rim: a cap lit on top, its face, its right side in shade.
        if merlon:
            for k in range(1, merlon_h + 1):
                yy_ = int(math.ceil(front)) - k
                v = lit + (0.26 if k == merlon_h else 0.08)
                if frac < 0.2:
                    v += 0.06
                elif frac > 0.75:
                    v -= 0.2
                light[yy_, x] = v
                alpha[yy_, x] = True
            # Over its cap, where the walk or the back rim lies behind it, a dark line so it stands out.
            above = int(math.ceil(front)) - merlon_h - 1
            if alpha[above, x]:
                light[above, x] = MORTAR

    # Arrow slits a little left of the middle where the light falls: a deep slot, a lit sill under it
    # and its lintel's shadow over it.
    slits = ((14, 25, 8), (14, 39, 6))
    for sx, sy, sh in slits:
        light[sy - 1, sx - 1:sx + 3] = 0.28
        light[sy + sh, sx - 1:sx + 3] = 0.8
        light[sy:sy + sh, sx - 1] = 0.66
        light[sy:sy + sh, sx + 2] = 0.3
    img = to_image(light, alpha)
    for sx, sy, sh in slits:
        img[sy:sy + sh, sx:sx + 2, :3] = (14, 13, 20)
    img = outline(img, deep=1)               # a shade up: the tower's stone is darker than the wall's
    return grass(img, feet, 8, [(4, 4), (6, 2), (12, 2), (19, 3), (22, 5), (25, 3)])


# ------------------------------------------------------------------------------------------ main

DRAWINGS = {"city_wall": city_wall, "city_tower": city_tower}


def main(argv):
    sheet = None
    if "--sheet" in argv:
        i = argv.index("--sheet")
        sheet = pathlib.Path(argv[i + 1])
        argv = argv[:i] + argv[i + 2:]
    out = {}
    for name in argv or list(DRAWINGS):
        arr = DRAWINGS[name]()
        img = Image.fromarray(arr, "RGBA")
        img.save(SPRITES / f"{name}.png")
        out[name] = img
    print(f"wrote {', '.join(out)} to art/sprites/")
    if sheet:
        wall = Image.open(SPRITES / "city_wall.png")
        tower = Image.open(SPRITES / "city_tower.png")
        scale = 6
        run = Image.new("RGBA", (WALL_W * 5, TOWER_H), (0, 0, 0, 0))
        for k in range(5):
            run.alpha_composite(wall, (k * WALL_W, TOWER_H - WALL_H - 2))
        run.alpha_composite(tower, (WALL_W * 2 + (WALL_W - TOWER_W) // 2, 0))
        board = Image.new("RGBA", ((run.width + TOWER_W + 12) * scale, (TOWER_H + 8) * scale), (106, 150, 86, 255))
        board.alpha_composite(run.resize((run.width * scale, run.height * scale), Image.NEAREST), (2 * scale, 4 * scale))
        board.alpha_composite(tower.resize((TOWER_W * scale, TOWER_H * scale), Image.NEAREST),
                              ((run.width + 8) * scale, 4 * scale))
        board.save(sheet)
        print(f"sheet in {sheet}")


if __name__ == "__main__":
    main(sys.argv[1:])
