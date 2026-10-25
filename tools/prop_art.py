#!/usr/bin/env python3
"""Props drawn in code where a generated sprite came out wrong: writes art/sprites/<id>.png.

Like tools/item_art.py: flat colours with a light and a dark shade and the game's dark outline. The
ship, as big as a grand building, is finished as the buildings are instead (tools/pixel_kit.py, with
pillow + numpy) and held to their bands: `pixel_style.py check --kind building art/sprites/ship.png`.
Edit a drawing below and rerun:

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
    a point at a time. Each point keeps which part it's on, its surface's normal and its place on
    that surface; the parts are then lit and finished as the buildings are (tools/building_art.py,
    docs/pixel-style.md: a hue-shifted ramp per material, planks and canvas at the sprite's own
    pixels, every form modelled by the light from the top left and in front, a tinted outline, a
    palette of RD's size), and scored with `pixel_style.py check --kind building`. The middle of its
    waterline is the middle of the picture, where the game sets it on the sea (anchor 0.5, 0.5);
    mirrored, it lies along the north."""
    import numpy as np
    from PIL import Image
    import building_art
    from pixel_kit import SS, Material, Sprite, limit_palette

    c = 0.5 ** 0.5
    half_length, beam = 110.0, 40.0
    mast_u, mast_top, yard_z, sail_low = 8.0, 150.0, 138.0, 62.0

    # The view and the light in the ship's own axes: toward you (down the screen and out of it),
    # the screen's right and up; the light as the buildings' (from the top left and in front).
    toward = np.array([-1.0, -1.0, c])
    toward /= np.linalg.norm(toward)
    right = np.array([1.0, -1.0, 0.0]) / 2 ** 0.5
    up = np.cross(toward, right)
    up = up if up[2] > 0 else -up
    sl = building_art.LIGHT
    light = sl[0] * right - sl[1] * up + sl[2] * toward
    light /= np.linalg.norm(light)

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

    def lit(n, low=0.12, span=0.7):
        """How lit a surface facing `n` is, 0 … 1: its normal turned toward you, light from the top left
        and in front. A face turned away from it still sits `low` (the side you see most of is turned
        from the light, and wants to read as its colour in shade, not black); canvas, lit through, higher."""
        n = np.asarray(n, float)
        n = n / (np.linalg.norm(n) or 1)
        if n @ toward < 0:
            n = -n
        return float(low + span * np.clip((n @ light + 0.6) / 1.6, 0, 1))

    def normal(f, p, q, e=0.3):
        """The normal of a surface f(p, q) -> (u, v, z), from its slopes."""
        a = np.subtract(f(p + e, q), f(p - e, q))
        b = np.subtract(f(p, q + e), f(p, q - e))
        return np.cross(a, b)

    points = {}
    casters = []

    def put(u, v, z, part, light_, a=0.0, d=0.0, layer=0):
        sx = (u - v) * c
        sy = -((u + v) * c * 0.5 + z)
        depth = (u + v) - c * z - layer * 1000
        key = (int(math.floor(sx)), int(math.floor(sy)))
        if key not in points or depth < points[key][0]:
            points[key] = (depth, part, light_, a, d)
        if part in ("sail", "jib", "band", "star", "spar"):
            casters.append((u, v, z))

    along = (1 + 0.25) ** 0.5 * c          # pixels on screen per point along the hull
    step = 0.45

    # The near side of the hull, from the waterline up past the deck (its bulwark): its sides round out
    # from the waterline, turn in a little to the rail (the light catching that turn) and close in to
    # the bow, so the light turns across it.
    def side(u, z):
        top = sheer(u) + 5
        t = min(1.0, max(0.0, z / top))
        return (u, -breadth(u) * (0.6 + 0.4 * math.sin(t * math.pi * 0.65) / math.sin(math.pi * 0.65)), z)

    for u in frange(-half_length, half_length, step):
        top = sheer(u) + 5
        for z in frange(0.0, top, step):
            n = normal(side, u, z)
            if n[1] > 0:
                n = -n
            # The waterline in the hull's own shadow, the strakes under the rail and the wale in theirs.
            wale = 12 + 3 * max(0.0, u / half_length) ** 2          # a smooth line, not stepping up at the stern
            shadow = -0.1 * max(0.0, 1 - z / 9) - (0.22 if 3.2 <= top - z < 4.8 or wale - 2.5 <= z < wale else 0)
            part = "rail" if top - z < 3.2 else "paint" if top - z < 11 else "hull"
            su, sv, sz = side(u, z)
            if wale <= z < wale + 2.4:
                # The wale: a heavy strake standing out along the hull, its top lit, its face rounded.
                part, sv = "wale", sv - 1.0
                n = n + np.array([0.0, 0.0, 1.2 * (z - wale - 1.2)])
            put(su, sv, sz, part, lit(n) + shadow, u * along, -z)
    # The far side's bulwark, seen from inside over the deck, in the near rail's shadow at its foot.
    for u in frange(-half_length, half_length, step):
        wide, base = breadth(u), sheer(u)
        for z in frange(base, base + 5, step):
            part = "rail" if z > base + 4 else "hull"
            put(u, wide, z, part, lit((0, -1, 0)) - 0.25 * (1 - (z - base) / 5), u * along, -z)
    # The stern, its face rounded from the waterline up (lit as it leans back toward the rail), with its
    # lit windows.
    stern = -half_length
    for v in frange(-breadth(stern), breadth(stern), step):
        top = sheer(stern) + 5
        for z in frange(0.0, top, step):
            window = abs(v) < 26 and 21 < z < 29 and (int(v + 26) % 13) < 8
            part = "window" if window else "rail" if top - z < 3.2 else "paint" if top - z < 11 else "hull"
            # Each window set back: its frame's shadow along its top inside, a lit sill under it.
            sill = abs(v) < 26 and 19.6 < z <= 21 and (int(v + 26) % 13) < 8
            shade = (-0.3 if z > 27.4 else 0.25 if z >= 25 else 0) if window else 0.25 if sill else \
                -0.22 if 3.2 <= top - z < 4.8 else -0.18 * max(0.0, 1 - z / 9)
            put(stern - 0.5, v, z, part, (0.5 if window else lit((-1, 0, 1.2 * (z / top - 0.45)), 0.08, 0.6)) + shade, -v * along, -z)
    # The mast and its yard, round.
    for z in frange(sheer(mast_u), mast_top, step):
        for angle in frange(0, 2 * math.pi, 0.2):
            n = (math.cos(angle), math.sin(angle), 0.0)
            put(mast_u + 2.5 * n[0], 2.5 * n[1], z, "spar", lit(n), 0, -z)
    for v in frange(-52, 52, step):
        for angle in frange(0, 2 * math.pi, 0.3):
            n = (math.cos(angle), 0.0, math.sin(angle))
            put(mast_u + 2 * n[0], v, yard_z + 2 * n[2], "spar", lit(n), v, 0)

    # The square sail, billowing toward the bow, a gold star on it, a blue band along its foot; soft
    # creases run down it toward its corners, where the sheets pull it (cloth has folds, not a flat sheen).
    def sail_at(v, z):
        across, rise = v / 48, (z - sail_low) / (yard_z - sail_low)
        crease = 3.0 * math.sin(2 * math.pi * rise * 3.5 + 3 * abs(across)) * (0.3 + 0.7 * abs(across))
        return (mast_u + 4 + (16 + crease) * (1 - across ** 2) * math.sin(math.pi * (0.15 + 0.85 * rise)), v, z)

    for z in frange(sail_low, yard_z - 1, step * 0.8):
        for v in frange(-48, 48, step * 0.8):
            star = in_star(v, z - (sail_low + yard_z) / 2 - 4, 30)
            part = "star" if star else "band" if z - sail_low < 7 else "sail"
            # Its head in the yard's shadow, its edges curling away into shade.
            put(*sail_at(v, z), part, lit(normal(sail_at, v, z), 0.3, 0.65) - 0.2 * max(0.0, 1 - (yard_z - z) / 6) - 0.3 * (v / 48) ** 4,
                -v * along, -z)

    # The jib, on the stay from the masthead down to the bowsprit, its belly out toward you, set well
    # forward on it, clear of the square sail: set into its belly, its edge ran down the middle of the
    # sail's star; set just behind it, it came out from under the sail's edge in the same cream and
    # read as one sail cut by the other (2026-10-25). Sky between the two now.
    bow = (half_length + 16, 0.0, sheer(half_length) + 6)
    along_stay = (mast_u + 62 - mast_u) / (bow[0] - mast_u)
    head = (mast_u + 62, 0.0, mast_top + (bow[2] - mast_top) * along_stay)
    foot = (mast_u + 66, 0.0, sheer(mast_u + 66) + 8)

    def jib_at(a, b):
        return (head[0] + (bow[0] - head[0]) * a + (foot[0] - head[0]) * b,
                -7 * math.sin(math.pi * min(1.0, a + b)) * (1 - b),
                head[2] + (bow[2] - head[2]) * a + (foot[2] - head[2]) * b)

    for a in frange(0, 1, 0.004):
        for b in frange(0, 1 - a, 0.004):
            u, v, z = jib_at(a, b)
            # Lit along its luff (the stay), turning into shade across it to its foot.
            put(u, v, z, "jib", lit(normal(jib_at, a, b, 0.01), 0.38, 0.5) + 0.4 * (0.45 - b / max(1 - a, 0.01)), u * along, -z)
    # The shadow the sails and the mast cast on the deck, toward the bow, away from the light.
    shaded = set()
    for u, v, z in casters:
        drop = (z - sheer(u)) / light[2]
        su, sv = u - light[0] * drop, v - light[1] * drop
        if -half_length < su < half_length and abs(sv) < breadth(su):
            shaded.add((round(su), round(sv)))
    # The deck, planked along the hull, darker in under the bulwarks; cambered, falling away a little to
    # each side from its middle, and turned as it rises to the bow and steps up to the stern's raised
    # deck (that step's face dark, turned from the light).
    for u in frange(-half_length, half_length, step):
        wide, rise = breadth(u), sheer(u + 0.5) - sheer(u - 0.5)
        for v in frange(-wide, wide, step):
            under = max(0.0, 1 - (wide - abs(v)) / 14) ** 1.5 if wide > 4 else 0.0
            shadow = 0.2 if (round(u), round(v)) in shaded else 0.0
            put(u, v, sheer(u), "deck", lit((-rise, 0.35 * v / max(wide, 1), 1), 0.08, 0.6) - 0.35 * under - shadow, u * along, v * along)
    # A hatch amidships: its coaming lit on top, its lid a step down.
    for u in frange(-30, -6, step):
        for v in frange(-12, 12, step):
            rim = abs(v) > 10.5 or u < -28.5 or u > -7.5
            put(u, v, sheer(u) + 3, "hatch", lit((0, 0, 1)) + (0.15 if rim else -0.2), u * along, v * along)
    # On deck: two barrels forward of the mast and a crate aft, on the near side where you see them,
    # each a form of its own, lit round.
    for bu, bv in ((34.0, -13.0), (42.0, -20.0)):
        base = sheer(bu)
        for z in frange(base, base + 10, step):
            k = (z - base) / 10
            r = 4.0 + 0.9 * math.sin(math.pi * k)
            hoop = abs(k - 0.2) < 0.05 or abs(k - 0.8) < 0.05
            for angle in frange(0, 2 * math.pi, 0.12):
                n = (math.cos(angle), math.sin(angle), -0.3 * math.cos(math.pi * k))
                put(bu + r * n[0], bv + r * n[1], z, "iron" if hoop else "barrel", lit(n), angle * 3, -z)
        for rr in frange(0, 4.0, step):
            for angle in frange(0, 2 * math.pi, 0.5 / max(rr, 0.5)):
                put(bu + rr * math.cos(angle), bv + rr * math.sin(angle), base + 10, "barrel",
                    lit((0, 0, 1)) + 0.1 - (0.15 if rr > 3.2 else 0), rr * math.cos(angle), rr * math.sin(angle))
    cu, cv, cs = -40.0, -22.0, 9.0
    base = sheer(cu)
    for p in frange(0, cs, step):
        for q in frange(0, cs, step):
            edge = 0.15 if min(p, q, cs - p, cs - q) < 1 else 0
            put(cu + p, cv + q, base + cs, "crate", lit((0, 0, 1)) + 0.12 - edge, p, q)
            put(cu + p, cv, base + q, "crate", lit((0, -1, 0)) - edge, p, -q)
            put(cu, cv + q, base + p, "crate", lit((-1, 0, 0)) - edge, -q, -p)
    # A bowsprit out to the jib, and the pennant at the top, rippling.
    line(lambda u, v, z, part: put(u, v, z, part, lit((0, -1, 1))), (half_length - 10, 0, sheer(half_length) + 2), bow, "spar", 1.6)
    for t in frange(0, 1, 0.01):
        length = 26 * t
        wave = 2.5 * math.sin(t * 9)
        slope = 2.5 * 9 / 26 * math.cos(t * 9)
        for z in frange(-4 * (1 - t), 4 * (1 - t), step):
            put(mast_u - 2 - length, wave, mast_top + 2 + z, "pennant" if t < 0.75 else "tip", lit((slope, -1, 0)), length, -z)
    # A lantern over the stern.
    for z in frange(0, 9, step):
        for v in frange(-3, 3, step):
            glow = 2 < z < 7 and abs(v) < 2
            put(-half_length + 2, v, sheer(-half_length) + 9 + z, "window" if glow else "iron", 0.75 if glow else lit((-1, -0.3, 0.2)))
    # The gangplank, from its near side down onto the pier (`WorldMap.pierHeight` over the water,
    # its far edge `LandStage.shipAcross` cells off), with cleats across it.
    deck_z = sheer(0) + 1
    for s in frange(0, 1, 0.004):
        v = -(breadth(0) - 4) + (-62 - -(breadth(0) - 4)) * s
        z = deck_z + (6 - deck_z) * s
        for u in frange(-7, 7, step):
            cleat = int(s * 60) % 6 == 0
            edge = abs(u) > 6
            put(u, v, z + (1 if cleat else 0), "plank", lit((0, -0.5, 1)) + (0.2 if cleat else -0.25 if edge else 0), u, v, layer=1)

    xs = [k[0] for k in points]
    ys = [k[1] for k in points]
    half_w = max(-min(xs), max(xs)) + 2
    half_h = max(-min(ys), max(ys)) + 2
    W, H = 2 * half_w, 2 * half_h

    # The parts, back to front (what lies on top casts its shadow down and to the right): base colour,
    # pattern, texture, gloss.
    parts = {
        "hull": ("#8a5a30", "strakes", 0.03, 0.0),
        "paint": ("#2f8296", "strakes", 0.02, 0.0),
        "rail": ("#d9a63a", None, 0.0, 0.5),
        "deck": ("#b37c45", "deck", 0.01, 0.0),
        "hatch": ("#6e4524", "boards", 0.02, 0.0),
        "plank": ("#a5713d", None, 0.03, 0.0),
        "wale": ("#5c3a22", None, 0.02, 0.0),
        "barrel": ("#a0683a", "boards", 0.02, 0.0),
        "crate": ("#c09058", "boards", 0.02, 0.0),
        "iron": ("#4a3a30", None, 0.0, 0.0),
        "window": ("#ffd86a", None, 0.0, 0.0),
        "sail": ("#e6d3a8", "canvas", 0.02, 0.0),
        "band": ("#2f8296", "canvas", 0.02, 0.0),
        "jib": ("#e6d3a8", None, 0.02, 0.0),
        "star": ("#e8b84a", None, 0.02, 0.0),
        "spar": ("#8a5a30", None, 0.02, 0.0),
        "pennant": ("#d83a4a", None, 0.0, 0.0),
        "tip": ("#ffd75a", None, 0.0, 0.0),
    }
    patterns = {
        "strakes": lambda r, a, d: strakes(r, a, d, h=7, length=46, seed=21, lap=0.4, vary=0.4),
        "deck": lambda r, a, d: strakes(r, a, d, h=6, length=38, seed=22, vary=0.45) * 0.85,
        "boards": lambda r, a, d: building_art.planks(r, a, d, h=3, seed=23, vertical=True) * 0.6,
        # Canvas: panels sewn top to bottom, a faint seam between each.
        "canvas": lambda r, a, d: building_art.planks(r, a, d, h=9, seed=24, vertical=True) * 0.3,
    }
    part_of = np.full((H, W), "", object)
    shade = np.zeros((H, W))
    pa, pd = np.zeros((H, W)), np.zeros((H, W))
    for (x, y), (_, part, value, a, d) in points.items():
        part_of[y + half_h, x + half_w] = part
        shade[y + half_h, x + half_w] = value
        pa[y + half_h, x + half_w], pd[y + half_h, x + half_w] = a, d

    s = Sprite(W, H)
    s.light, s.rim = building_art.LIGHT, "lower"
    # Flat ground under the kit's own light: what each part's light is measured from.
    base = 0.05 + 0.55 * float(building_art.LIGHT[2]) ** 2
    ones = np.ones((SS, SS))
    coarse = np.random.default_rng(5).random((H // 5 + 2, W // 5 + 2))
    steps_noise = (np.asarray(Image.fromarray((coarse * 255).astype(np.uint8)).resize(((W // 5 + 2) * 5, (H // 5 + 2) * 5), Image.BILINEAR),
                              float)[:H, :W] / 255 - 0.5) * 0.5
    for part, (colour, pattern, texture, gloss) in parts.items():
        region = part_of == part
        if not region.any():
            continue
        value = np.where(region, shade, 0.0)
        if pattern:
            value = value + np.where(region, patterns[pattern](region, pa, pd), 0.0)
        # Onto the ramp's own steps here, each step's edge broken in soft clusters (less on the canvas,
        # where they read as stains): left between two shades, the kit dithers a slow change of light (a
        # sail's billow) into a field of checkerboard, which the craft (docs/pixel-style.md) warns is noise.
        value = np.round(value * 6 + steps_noise * (0.4 if part in ("sail", "jib") else 1.0)) / 6
        relief = 0.0 if part == "window" else 1.0
        detail = value - (base if relief else 0.55)
        mat = Material(colour, texture=texture * building_art.TEXTURE, shades=7, gloss=gloss, variety=3,
                       shift=building_art.SHIFT, relief=relief)
        s.mask(np.kron(region, ones).astype(bool), mat, height=np.zeros((H * SS, W * SS)), detail=np.kron(detail, ones))
    img = s.render(outline="tinted")
    size = int((np.asarray(img)[..., 3] > 0).sum())
    img = np.array(limit_palette(img, int(size * 0.9 / 100)))

    # The rigging in hemp, a pixel wide, over the finish (the stays from the masthead to the bowsprit
    # and the stern, and from the yard down to each side), and foam where the hull sits in the water: opaque specks, broken.
    rope = (92, 62, 40, 255)

    def ink(u, v, z, colour):
        # Behind whatever's nearer there (a stay passing behind a sail is hidden by it).
        key = (int(math.floor((u - v) * c)), int(math.floor(-((u + v) * c * 0.5 + z))))
        if key in points and points[key][0] < (u + v) - c * z - 1.0:
            return
        x, y = key[0] + half_w, key[1] + half_h
        if 0 <= y < H and 0 <= x < W:
            img[y, x] = colour

    for a, b in (((mast_u, 0, mast_top), bow),                                   # the forestay, holding the jib
                 ((mast_u, 0, mast_top), (-half_length + 4, 0, sheer(-half_length) + 6)),
                 ((mast_u, 0, yard_z), (mast_u - 10, -breadth(mast_u - 10), sheer(mast_u - 10) + 5)),
                 ((mast_u, 0, yard_z), (mast_u - 10, breadth(mast_u - 10), sheer(mast_u - 10) + 5))):
        for t in frange(0, 1, 0.3 / math.dist(a, b)):
            ink(*[a[i] + (b[i] - a[i]) * t for i in range(3)], rope)
    foam = [(232, 248, 255, 255), (178, 222, 236, 255)]
    for u in frange(-half_length, half_length + 8, 1.0):
        wide = breadth(min(u, half_length)) * 0.6 + 2
        for k, v in enumerate((-wide, -wide - 1.5)):
            x, y = int(math.floor((u - v) * c)) + half_w, int(math.floor(-((u + v) * c * 0.5))) + half_h
            if 0 <= y < H and 0 <= x < W and img[y, x, 3] == 0 and math.sin(u * 0.37) + 0.6 * math.sin(u * 1.3) > -0.4 + k:
                img[y, x] = foam[k]
    canvas = Canvas(W, H)
    canvas.px = [[tuple(int(v) for v in img[y, x]) if img[y, x, 3] else None for x in range(W)] for y in range(H)]
    return canvas


def strakes(region, a, d, h, length, seed, lap=0.0, vary=0.14):
    """A hull's strakes or a deck's boards (light and shade, as tools/building_art.py's patterns): long
    boards `h` pixels wide along `a`, a dark seam under each and its top edge lit, an end joint every
    `length` pixels or so, staggered, and a little grain. A wall's planks (`building_art.planks`) are
    short, and on a hull their joints stacked up like bricks. `lap`: each board overlaps the one under
    it (clinker-built), lit along its top and turning into shadow down to its lapped edge. `vary`: how
    far one board's tone differs from the next (old timber, each board weathered its own way)."""
    import numpy as np
    import building_art
    A, D = building_art._grid(region, a, d)
    board = D // h
    rng = np.random.default_rng(seed)
    offset = rng.integers(0, length, size=64)[board % 64]
    tone = (rng.random(64)[board % 64] - 0.5) * vary
    seam = D % h == h - 1
    joint = (A + offset) % length == 0
    grain = (np.sin(A * 0.31 + board * 2.3) > 0.92) * -0.1
    turn = lap * (0.5 - (D % h) / max(h - 1, 1))
    return np.where(seam | joint, -0.34, grain + tone + turn + np.where(D % h == 0, 0.08, 0.0))


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


def draw_cave_rope():
    """The way back up from a cave's deeper level (playtesting 2026-10-20: "instead of a staircase to
    go up in the caves, it should be a rope going up"): a knotted hemp rope hanging from a hole in
    the roof, swaying a little, its end coiled on the floor in a dim pool of light from above. It
    fades out toward the top, up into the dark. Lit from the top left."""
    c = Canvas(32, 72)
    hemp = [hexc("5c3d1e"), hexc("9c6f3c"), hexc("d4ac6c")]
    # The pool of light the hole lets down, under everything.
    cx, cy, rx, ry = 16.0, 64.0, 14.0, 6.0
    for y in range(c.height):
        for x in range(c.width):
            r = math.hypot((x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry)
            if r <= 1.0:
                c.px[y][x] = hexc("bcd8ff", int(70 * (1 - r) ** 0.7))
    light = {(x, y) for y in range(c.height) for x in range(c.width) if c.px[y][x] is not None}

    def put(x, y, color):
        if 0 <= x < c.width and 0 <= y < c.height:
            c.px[y][x] = color

    # The coil on the floor: loops of rope, open in the middle, the lower ones first, each lit
    # along its far (upper) edge.
    for lift, (lx, ly) in ((0.0, (10.5, 4.6)), (2.5, (8.5, 3.6))):
        for t in frange(0, 2 * math.pi, 0.01):
            tone = 2 if math.sin(t) < -0.4 else 0 if math.sin(t) > 0.5 else 1
            put(int(cx + 0.5 + math.cos(t) * lx), int(cy - lift + math.sin(t) * ly), hemp[tone])
    # The hanging rope, three pixels wide, its twist showing as a stripe every four rows.
    top, bottom = 0, int(cy) - 3
    for y in range(top, bottom + 1):
        x = int(round(cx - 1 + 1.3 * math.sin(y / 11.0)))
        twist = (y % 4) < 2
        put(x, y, hemp[2] if twist else hemp[1])
        put(x + 1, y, hemp[1] if twist else hemp[2])
        put(x + 2, y, hemp[0])
        # A knot every twelve rows, a hand-hold to climb by.
        if y > 14 and (bottom - y) % 12 == 4:
            put(x - 1, y, hemp[1])
            put(x + 3, y, hemp[0])
            put(x, y - 1, hemp[2])
            put(x + 1, y - 1, hemp[2])
            put(x + 2, y - 1, hemp[1])
    # Outline the rope and coil, not the pool of light.
    pool = {p: c.px[p[1]][p[0]] for p in light if c.px[p[1]][p[0]] is not None and c.px[p[1]][p[0]][3] < 255}
    for x, y in pool:
        c.px[y][x] = None
    c.outline()
    for (x, y), color in pool.items():
        if c.px[y][x] is None:
            c.px[y][x] = color
    # Up into the dark: the top third fades away.
    fade = 26
    for y in range(fade):
        for x in range(c.width):
            if c.px[y][x] is not None:
                r, g, b, a = c.px[y][x]
                c.px[y][x] = (r, g, b, int(a * (y / fade) ** 1.5))
    return c


def draw_waystone():
    """A waystone (NPC role `waystone`): a standing stone out in the wild, rounded at the top and
    leaning in a little, lit from the top left, its runes a glowing blue (the game fades the whole
    stone while it sleeps), on a ring of flat stones in the grass."""
    c = Canvas(32, 48)
    stone = [hexc("4a4a5c"), hexc("75768a"), hexc("a4a6b8")]
    base = [hexc("55554a"), hexc("86846f"), hexc("b4b09a")]
    glow = [hexc("2e7fd8"), hexc("6cc4ff"), hexc("e4f6ff")]
    # The flat stones round its foot: an ellipse, lit at the top left.
    for y in range(c.height):
        for x in range(c.width):
            u, v = (x + 0.5 - 16) / 14.5, (y + 0.5 - 42) / 4.5
            if u * u + v * v <= 1:
                c.px[y][x] = base[2 if u + v < -0.6 else 0 if u + v > 0.6 else 1]
    # The stone: wider at its foot than its head, the head an arc.
    for y in range(4, 43):
        t = (y - 4) / 38
        half = 6.5 + 2.5 * t
        if y < 10:
            half *= math.sqrt(max(0.0, 1 - ((10 - y) / 6.5) ** 2))
        middle = 16 + 0.8 * (1 - t)
        for x in range(c.width):
            d = (x + 0.5 - middle) / max(half, 0.1)
            if abs(d) <= 1:
                c.px[y][x] = stone[2 if d < -0.45 else 0 if d > 0.5 else 1]
    # Its runes: a circle and the strokes through it, carved deep and glowing.
    runes = [(16, 14), (16, 15), (16, 16), (16, 17), (16, 18), (16, 19), (16, 20), (16, 21), (16, 22),
             (14, 15), (13, 16), (18, 15), (19, 16), (14, 24), (15, 25), (16, 26), (17, 25), (18, 24),
             (13, 29), (14, 30), (15, 31), (16, 32), (17, 31), (18, 30), (19, 29), (16, 33), (16, 34), (16, 35)]
    for (x, y) in runes:
        c.px[y][x] = glow[1]
    for (x, y) in ((16, 14), (16, 26), (16, 32)):
        c.px[y][x] = glow[2]
    for (x, y) in runes:
        if c.get(x + 1, y + 1) in stone:
            c.px[y + 1][x + 1] = glow[0]
    # Moss on its shaded side, low down.
    for (x, y) in ((21, 36), (22, 37), (21, 38), (22, 39), (20, 40), (23, 40)):
        if c.get(x, y) in stone:
            c.px[y][x] = hexc("4f7a3a")
    c.outline()
    return c


def draw_lost_pile():
    """What you lost when you fell, left where you fell (`LostPile`, `GameSession.loseBelongings`): a
    burlap sack slumped on its side, its neck open and its tie loose, coins spilled out of it, a red
    potion and a sword lying by it. Drawn with tools/pixel_kit.py as the lairs' pieces are (lit from
    the top left, hue-shifted ramps, a tinted outline) and scored as scenery."""
    from pixel_kit import Material, Sprite

    burlap = Material("#b08a52", shades=5, texture=0.09, grain=1.0)
    tie = Material("#8a5a2c", shades=4, texture=0.03)
    gold = Material("#f2c444", shades=5, texture=0.02, gloss=0.6)
    rim = Material("#b07a1c", shades=4, texture=0.02)
    glass = Material("#d83a3a", shades=5, texture=0.0, gloss=0.8)
    cork = Material("#9a7046", shades=3, texture=0.04)
    steel = Material("#c4ccd8", shades=5, texture=0.02, gloss=0.6)
    hilt = Material("#7a4a26", shades=4, texture=0.03)
    s = Sprite(40, 32)
    # The little sword behind, lying back to front.
    s.stroke([(9, 13.5), (22, 6)], 2.6, steel)
    s.stroke([(7.5, 11), (10.5, 16)], 1.6, hilt)
    s.stroke([(4.5, 16.5), (8.5, 14.2)], 1.8, hilt)
    # The sack: a fat body, its neck to the right, open.
    s.ellipse(16, 21, 10.5, 7.5, burlap)
    s.poly([(23, 16), (30, 13.5), (32, 18), (25, 24)], burlap, bulge=0.7)
    s.ellipse(31, 16, 2.6, 3.2, tie, profile="flat", rot=-25)
    s.stroke([(24, 17.5), (26, 21.5)], 1.4, tie)
    # Coins spilled from its mouth: back to front, the nearer over the farther.
    for cx, cy in ((34, 20), (29.5, 24.5), (35.5, 25.5), (31.5, 28.5)):
        s.ellipse(cx, cy + 1.1, 3.4, 2.0, rim, profile="flat")
        s.ellipse(cx, cy, 3.4, 2.0, gold)
    # A red potion in front of the sack.
    s.ellipse(11, 27, 3.4, 3.1, glass)
    s.poly([(10, 21.5), (12, 21.5), (12, 24.5), (10, 24.5)], glass, bulge=0.5)
    s.poly([(9.7, 20), (12.3, 20), (12.3, 21.8), (9.7, 21.8)], cork, profile="flat")
    image = s.render(outline="tinted")
    canvas = Canvas(image.width, image.height)
    canvas.px = [[image.getpixel((x, y)) if image.getpixel((x, y))[3] else None for x in range(image.width)]
                 for y in range(image.height)]
    return canvas


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
    "cave_rope": draw_cave_rope,
    "lost_pile": draw_lost_pile,
    "ship": draw_ship,
    "waystone": draw_waystone,
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
                        # Blended over the ground, as the game draws it (a faded pixel isn't white).
                        under, a = pixels[pad + y][ox + x], color[3] / 255
                        pixels[pad + y][ox + x] = tuple(int(color[i] * a + under[i] * (1 - a)) for i in range(3)) + (255,)
            ox += art.width * scale + pad
        raw = b"".join(b"\x00" + b"".join(bytes(p) for p in row) for row in pixels)
        pathlib.Path(sheet_path).write_bytes(encode_png(width, height, raw))
        print(f"contact sheet: {sheet_path}")


if __name__ == "__main__":
    main(sys.argv[1:])
