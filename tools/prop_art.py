#!/usr/bin/env python3
"""Props drawn in code where a generated sprite came out wrong: writes art/sprites/<id>.png.

Like tools/item_art.py: flat colours with a light and a dark shade and the game's dark outline, no
image libraries needed. Edit a drawing below and rerun:

    python3 tools/prop_art.py                   # all of them
    python3 tools/prop_art.py candy_cane        # just these
    python3 tools/prop_art.py --sheet out.png   # also a 6× contact sheet on the meadow's green
"""

import math
import pathlib
import sys

from item_art import OUTLINE, encode_png, hexc

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"


class Canvas:
    """A width × height grid of RGBA pixels (None is clear)."""

    def __init__(self, width, height):
        self.width, self.height = width, height
        self.px = [[None] * width for _ in range(height)]

    def get(self, x, y):
        return self.px[y][x] if 0 <= x < self.width and 0 <= y < self.height else None

    def outline(self, color=OUTLINE):
        grow = [(x, y) for y in range(self.height) for x in range(self.width)
                if self.px[y][x] is None and any(self.get(x + dx, y + dy) not in (None, color)
                                                 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
        for x, y in grow:
            self.px[y][x] = color

    def png(self):
        raw = b"".join(b"\x00" + b"".join(bytes(c or (0, 0, 0, 0)) for c in row) for row in self.px)
        return encode_png(self.width, self.height, raw)


def nearest_on_path(path, x, y):
    """The closest point to (x, y) on a path of straight pieces and arcs: (distance, how far along
    the path, the unit vector out from it to the point)."""
    best = None
    start = 0.0
    for piece in path:
        if piece[0] == "line":
            _, (ax, ay), (bx, by) = piece
            length = math.hypot(bx - ax, by - ay)
            t = max(0.0, min(1.0, ((x - ax) * (bx - ax) + (y - ay) * (by - ay)) / (length * length)))
            px, py, along = ax + (bx - ax) * t, ay + (by - ay) * t, start + t * length
        else:
            # An arc round (cx, cy) of radius r from angle a0 to a1 (radians, y up on screen).
            _, (cx, cy), r, a0, a1 = piece
            length = abs(a1 - a0) * r
            angle = math.atan2(-(y - cy), x - cx)
            lo, hi = min(a0, a1), max(a0, a1)
            while angle < lo - math.pi:
                angle += 2 * math.pi
            while angle > hi + math.pi:
                angle -= 2 * math.pi
            angle = max(lo, min(hi, angle))
            px, py = cx + r * math.cos(angle), cy - r * math.sin(angle)
            along = start + abs(angle - a0) * r
        d = math.hypot(x - px, y - py)
        normal = ((x - px) / d, (y - py) / d) if d > 1e-6 else (0.0, 0.0)
        if best is None or d < best[0]:
            best = (d, along, normal)
        start += length
    return best


def draw_candy_cane():
    """A giant candy cane stuck in the ground: a straight shaft with its hook curling over to the
    left, red stripes winding round the white, lit from the top left like the other sprites."""
    c = Canvas(32, 48)
    # The shaft stands in the middle, where the game sets a prop down on its cell.
    shaft_x, top, bottom, bend = 16.5, 13.0, 47.0, 5.0
    path = [
        ("line", (shaft_x, bottom), (shaft_x, top)),
        ("arc", (shaft_x - bend, top), bend, 0.0, math.pi),
        ("line", (shaft_x - 2 * bend, top), (shaft_x - 2 * bend, top + 4.5)),
    ]
    half = 3.0
    reds = [hexc("9b1a2e"), hexc("d8324a"), hexc("f27a86")]
    whites = [hexc("cdbcc4"), hexc("f6eef1"), hexc("ffffff")]
    light = (-0.6, -0.8)
    for y in range(c.height):
        for x in range(c.width):
            d, along, (nx, ny) = nearest_on_path(path, x + 0.5, y + 0.5)
            if d > half:
                continue
            # Which side of the path it's on, so the stripes run round the cane on a slant.
            side = d if (nx * light[0] + ny * light[1]) >= 0 else -d
            stripe = (along + 1.0 * side) % 8.0 < 3.5
            lit = (nx * light[0] + ny * light[1]) * d / half
            tone = 2 if lit > 0.45 else 0 if lit < -0.3 else 1
            c.px[y][x] = (reds if stripe else whites)[tone]
    # Outlined in the candy's own darkest red, as the generated sweets are, not the items' ink.
    c.outline(hexc("5c1424"))
    return c


def draw_ship():
    """The ship moored at a harbor (`LandStage.placeHarbors`): a little sailing ship lying along the
    map's east, as the game's 2:1 view sees it, its bow up the screen to the right, its south side
    and its stern toward you, one mast with a square sail with a gold star on it, a jib to the bow
    and a pennant, lit stern windows, and a gangplank down off its near side to the pier.

    Built in three dimensions in the game's own points (u along the hull to the bow, v across it to
    the north, z up from the water) and projected as `WorldMap.project` does, nearest surface first
    a point at a time. The middle of its waterline is the middle of the picture, where the game sets
    it on the sea (anchor 0.5, 0.5); mirrored, it lies along the north."""
    c = 0.5 ** 0.5
    half_length, beam = 110.0, 40.0
    mast_u, mast_top, yard_z, sail_low = 8.0, 150.0, 138.0, 62.0
    light = (-0.55, 0.55, 1.0)
    norm = math.sqrt(sum(a * a for a in light))
    light = tuple(a / norm for a in light)

    def sheer(u):
        """The deck's height over the water along the hull: low amidships, up to a raised stern."""
        t = u / half_length
        return 24 + 7 * max(0.0, t) ** 2 + (12 if u < -58 else 12 * max(0.0, (-u - 46) / 12) if u < -46 else 0)

    def breadth(u):
        """The deck's half-width along the hull: full amidships, to a point at the bow, a flat stern."""
        t = u / half_length
        if t > 0:
            return beam * math.sqrt(max(0.0, 1 - t ** 2.2))
        return beam * (1 - 0.28 * t ** 2)

    points = {}

    def put(u, v, z, color, layer=0):
        sx = (u - v) * c
        sy = -((u + v) * c * 0.5 + z)
        depth = (u + v) - c * z - layer * 1000
        key = (int(math.floor(sx)), int(math.floor(sy)))
        if key not in points or depth < points[key][0]:
            points[key] = (depth, color)

    def shade(n, tones):
        lit = sum(a * b for a, b in zip(n, light))
        return tones[2] if lit > 0.45 else tones[0] if lit < -0.05 else tones[1]

    wood = [hexc("5c3820"), hexc("8a5a30"), hexc("b37c45")]
    seam = hexc("4a2c18")
    paint = [hexc("1f5c70"), hexc("2f8296"), hexc("4fb0c0")]
    gold = [hexc("b07a20"), hexc("e8b84a"), hexc("ffe08a")]
    sail = [hexc("c9b48c"), hexc("e8dcc0"), hexc("fbf5e6")]
    # The rigging in the outline's own ink, a pixel wide (the outline grows round anything else).
    rope = OUTLINE
    step = 0.45
    # The near side of the hull, from the waterline up past the deck (its bulwark), planked.
    u = -half_length
    while u <= half_length:
        top, wide = sheer(u) + 5, breadth(u)
        low = wide * 0.82
        z = 0.0
        while z <= top:
            t = z / top
            v = -(low + (wide - low) * t)
            n = (0.0, -1.0, 0.25)
            if top - z < 3.2:
                color = shade(n, gold)
            elif top - z < 11:
                color = shade(n, paint)
            elif int(z) % 6 == 0:
                color = seam
            else:
                color = shade(n, wood)
            put(u, v, z, color)
            z += step
        u += step
    # The far side's bulwark, seen from inside over the deck.
    u = -half_length
    while u <= half_length:
        wide = breadth(u)
        z = sheer(u)
        while z <= sheer(u) + 5:
            put(u, wide, z, shade((0.0, -1.0, 0.0), wood) if z < sheer(u) + 4 else gold[1])
            z += step
        u += step
    # The stern, flat across, with its lit windows.
    stern = -half_length
    v = -breadth(stern)
    while v <= breadth(stern):
        top = sheer(stern) + 5
        z = 0.0
        while z <= top:
            window = abs(v) < 26 and 21 < z < 29 and (int(v + 26) % 13) < 8
            if window:
                color = hexc("ffd86a") if z < 26 else hexc("fff2b0")
            elif top - z < 3.2:
                color = gold[2]
            elif top - z < 11:
                color = paint[2]
            elif int(z) % 6 == 0:
                color = seam
            else:
                color = wood[2]
            put(stern - 0.5, v, z, color)
            z += step
        v += step
    # The deck, planked along the hull.
    u = -half_length
    while u <= half_length:
        wide = breadth(u)
        v = -wide
        while v <= wide:
            color = seam if int(v + 100) % 8 == 0 else wood[2] if (int(u + 200) // 30 + int(v + 100) // 8) % 3 else wood[1]
            put(u, v, sheer(u), color)
            v += step
        u += step
    # A hatch amidships and a barrel by the mast.
    for u in frange(-30, -6, step):
        for v in frange(-12, 12, step):
            put(u, v, sheer(u) + 3, seam if abs(v) > 10.5 or u < -28.5 or u > -7.5 else wood[0])
    # The mast and its yard.
    for z in frange(sheer(mast_u), mast_top, step):
        for angle in frange(0, 2 * math.pi, 0.2):
            n = (math.cos(angle), math.sin(angle), 0.0)
            put(mast_u + 2.5 * n[0], 2.5 * n[1], z, shade(n, wood))
    for v in frange(-52, 52, step):
        for angle in frange(0, 2 * math.pi, 0.3):
            n = (math.cos(angle), 0.0, math.sin(angle))
            put(mast_u + 2 * n[0], v, yard_z + 2 * n[2], shade(n, wood))
    # The square sail, billowing toward the bow, a gold star on it.
    for z in frange(sail_low, yard_z - 1, step * 0.8):
        for v in frange(-48, 48, step * 0.8):
            across, up = v / 48, (z - sail_low) / (yard_z - sail_low)
            bulge = 16 * (1 - across ** 2) * math.sin(math.pi * (0.15 + 0.85 * up))
            slope = -32 * across / 48 * math.sin(math.pi * (0.15 + 0.85 * up))
            n = (-1.0, slope / 16, 0.15)
            star = in_star(v, z - (sail_low + yard_z) / 2 - 4, 30)
            if star:
                color = shade(n, [gold[0], gold[1], hexc("f2c64a")])
            elif z - sail_low < 7:
                color = shade(n, paint)
            elif (z - sail_low) % 18 < 1:
                color = sail[0]
            else:
                color = shade(n, sail)
            put(mast_u + 4 + bulge, v, z, color)
    # The jib, from the mast down to the bow.
    bow = (half_length + 16, 0.0, sheer(half_length) + 6)
    head, foot = (mast_u + 4, 0.0, mast_top - 16), (mast_u + 6, 0.0, sail_low - 14)
    for a in frange(0, 1, 0.004):
        for b in frange(0, 1 - a, 0.004):
            u = head[0] + (bow[0] - head[0]) * a + (foot[0] - head[0]) * b
            z = head[2] + (bow[2] - head[2]) * a + (foot[2] - head[2]) * b
            belly = -7 * math.sin(math.pi * min(1.0, a + b)) * (1 - b)
            put(u, belly, z, sail[2] if b < 0.5 else sail[1])
    # A bowsprit out to the jib, the stays and the pennant at the top.
    line(put, (half_length - 10, 0, sheer(half_length) + 2), bow, wood[1], 1.6)
    line(put, (mast_u, 0, mast_top), (-half_length + 4, 0, sheer(-half_length) + 6), rope, 0.2)
    line(put, (mast_u, 0, yard_z), (mast_u - 10, -breadth(mast_u - 10), sheer(mast_u - 10) + 5), rope, 0.2)
    line(put, (mast_u, 0, yard_z), (mast_u - 10, breadth(mast_u - 10), sheer(mast_u - 10) + 5), rope, 0.2)
    for t in frange(0, 1, 0.01):
        length = 26 * t
        wave = 2.5 * math.sin(t * 9)
        for z in frange(-4 * (1 - t), 4 * (1 - t), step):
            put(mast_u - 2 - length, wave, mast_top + 2 + z, hexc("d83a4a") if t < 0.75 else hexc("ffd75a"))
    # A lantern over the stern.
    for z in frange(0, 9, step):
        for v in frange(-3, 3, step):
            put(-half_length + 2, v, sheer(-half_length) + 9 + z, hexc("fff2b0") if 2 < z < 7 and abs(v) < 2 else hexc("3a2a20"))
    # The gangplank, from its near side down onto the pier (`WorldMap.pierHeight` over the water,
    # its far edge `LandStage.shipAcross` cells off), with cleats across it.
    deck_z = sheer(0) + 1
    for s in frange(0, 1, 0.004):
        v = -(breadth(0) - 4) + (-62 - -(breadth(0) - 4)) * s
        z = deck_z + (6 - deck_z) * s
        for u in frange(-7, 7, step):
            cleat = int(s * 60) % 6 == 0
            put(u, v, z + (1 if cleat else 0), wood[0] if cleat or abs(u) > 6 else wood[2], layer=1)
    xs = [k[0] for k in points]
    ys = [k[1] for k in points]
    half_w = max(-min(xs), max(xs)) + 2
    half_h = max(-min(ys), max(ys)) + 2
    canvas = Canvas(2 * half_w, 2 * half_h)
    for (x, y), (_, color) in points.items():
        canvas.px[y + half_h][x + half_w] = color
    canvas.outline()
    # Foam where it sits in the water, under the outline.
    for u in frange(-half_length, half_length + 8, 1.0):
        wide = breadth(min(u, half_length)) * 0.82 + 2
        for v in (-wide, -wide - 1.5):
            x, y = int(math.floor((u - v) * c)) + half_w, int(math.floor(-((u + v) * c * 0.5))) + half_h
            if 0 <= y < canvas.height and 0 <= x < canvas.width and canvas.px[y][x] is None:
                canvas.px[y][x] = hexc("e8f8ff", 200 if v == -wide else 110)
    return canvas


def draw_cave_ladder():
    """A way down to a cave's deeper level (RuneScape's ladders into the dark): a round pit in the
    cave floor, ringed with stones, black at its heart, and a wooden ladder standing up out of it,
    leaning back a little, lit from the top left."""
    c = Canvas(48, 48)
    cx, cy, rx, ry = 24.0, 35.0, 19.0, 9.5
    stones = [hexc("3b3a48"), hexc("5d5c6e"), hexc("8a8a9c")]
    dark = [hexc("07060c"), hexc("15131f"), hexc("262333")]
    for y in range(c.height):
        for x in range(c.width):
            u, v = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            r = math.hypot(u, v)
            if r > 1.0:
                continue
            if r > 0.72:
                # The rim's stones: a ring broken into blocks, lit on the side toward the light.
                angle = math.atan2(v, u)
                block = int((angle + math.pi) / (2 * math.pi) * 14)
                lit = -(u * 0.6 + v * 0.8)
                tone = 2 if lit > 0.35 else 0 if lit < -0.35 else 1
                if (block % 2 == 0 and tone > 0):
                    tone -= 1
                c.px[y][x] = stones[tone]
            else:
                # The pit: darker toward the middle, its far wall (the top) catching a little light.
                tone = 0 if r < 0.45 else 1 if v > -0.35 else 2
                c.px[y][x] = dark[tone]
    woods = [hexc("5a3518"), hexc("8c5a2b"), hexc("c08a4c")]
    # Two rails from down in the pit to above its far rim, leaning back toward the top right.
    rails = [((17.0, 38.0), (19.5, 6.0)), ((29.0, 38.0), (31.5, 6.0))]
    for (ax, ay), (bx, by) in rails:
        for t in frange(0, 1, 0.01):
            x, y = ax + (bx - ax) * t, ay + (by - ay) * t
            for dx in (0, 1, 2):
                px, py = int(x) + dx, int(y)
                if 0 <= px < c.width and 0 <= py < c.height:
                    c.px[py][px] = woods[2 if dx == 0 else 1 if dx == 1 else 0]
    # Rungs every five pixels, between the rails.
    for k in range(6):
        t = 0.12 + k * 0.155
        y = int(38.0 + (6.0 - 38.0) * t)
        left = int(17.0 + 2.5 * t) + 3
        right = int(29.0 + 2.5 * t)
        for x in range(left, right):
            c.px[y][x] = woods[1]
            if y + 1 < c.height and c.px[y + 1][x] in dark + stones:
                c.px[y + 1][x] = woods[0]
    c.outline()
    return c


def frange(start, stop, step):
    """From `start` to `stop` (inclusive) in steps of `step`."""
    count = int(round((stop - start) / step))
    return [start + (stop - start) * i / max(1, count) for i in range(count + 1)]


def line(put, a, b, color, width):
    """A rope or a spar from one point to another (u, v, z), `width` thick."""
    length = math.dist(a, b)
    for t in frange(0, 1, 0.4 / max(1.0, length)):
        p = [a[i] + (b[i] - a[i]) * t for i in range(3)]
        for dz in frange(-width / 2, width / 2, 0.4):
            put(p[0], p[1], p[2] + dz, color)


def in_star(x, y, radius):
    """Whether (x, y) is inside a five-pointed star of that radius, point up."""
    corners = []
    for k in range(10):
        r = radius if k % 2 == 0 else radius * 0.45
        angle = math.pi / 2 + k * math.pi / 5
        corners.append((r * math.cos(angle), r * math.sin(angle)))
    inside = False
    for (ax, ay), (bx, by) in zip(corners, corners[1:] + corners[:1]):
        if (ay > y) != (by > y) and x < ax + (y - ay) * (bx - ax) / (by - ay):
            inside = not inside
    return inside


DRAWINGS = {
    "candy_cane": draw_candy_cane,
    "cave_ladder": draw_cave_ladder,
    "ship": draw_ship,
}


def main(argv):
    sheet_path = None
    if "--sheet" in argv:
        index = argv.index("--sheet")
        sheet_path = argv[index + 1]
        argv = argv[:index] + argv[index + 2:]
    ids = argv or sorted(DRAWINGS)
    drawn = {prop: DRAWINGS[prop]() for prop in ids}
    for prop, art in drawn.items():
        (SPRITES / f"{prop}.png").write_bytes(art.png())
    print(f"wrote {len(ids)} prop sprites to art/sprites/")
    if sheet_path:
        scale, pad = 6, 6
        width = sum(art.width * scale + pad for art in drawn.values()) + pad
        height = max(art.height for art in drawn.values()) * scale + 2 * pad
        pixels = [[(110, 160, 90, 255)] * width for _ in range(height)]
        ox = pad
        for art in drawn.values():
            for y in range(art.height * scale):
                for x in range(art.width * scale):
                    color = art.px[y // scale][x // scale]
                    if color:
                        pixels[pad + y][ox + x] = color
            ox += art.width * scale + pad
        raw = b"".join(b"\x00" + b"".join(bytes(p) for p in row) for row in pixels)
        pathlib.Path(sheet_path).write_bytes(encode_png(width, height, raw))
        print(f"contact sheet: {sheet_path}")


if __name__ == "__main__":
    main(sys.argv[1:])
