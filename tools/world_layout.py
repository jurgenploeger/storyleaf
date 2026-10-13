#!/usr/bin/env python3
"""Lays the lands out as one continent (content/world.json), so you can walk from one to the next.

Every outdoor map gets an origin in world cells: the world cell its south-west cell sits on, x east
and y north, as the maps' own cells run. Lands a road joins touch along that edge, and the road
meets itself across the border: the exit's `at` on both sides lands on the same world row (or
column). Nothing overlaps; past an edge where a road leads into a cave, the mountains it rises
into keep a strip clear (`CAVE_CLEARANCE`). Lands keep the order of their `world` spot on the
atlas, and sit as close together as the roads allow.

It's an integer program (scipy's HiGHS): the land's origins, and the `at` of every road whose map
doesn't give one, chosen to keep the roads where their maps put them and the continent
compact. A road keeps its `at` where it can; where the layout needs it to meet the next land
elsewhere along the border, that's its `meets` (the road is still laid toward `at`, round the
lakes and hills it was placed for, and only its last stretch bends: `WorldMap.carveRoad`).

    python3 tools/world_layout.py               # solve, write content/world.json and the roads' `at`
    python3 tools/world_layout.py --check       # only report whether world.json still fits maps.json
    python3 tools/world_layout.py --preview out.png   # a picture of the continent (needs pillow)
    python3 tools/world_layout.py --check --preview out.png   # the same, of world.json as it is

The preview draws the coasts as the game lets the sea in over them (`coast`, after
Fairyland/World/Coast.swift) and the bands where one land gives way to the next (`looks`, after
Fairyland/World/Seam.swift): keep them in step.

Needs numpy and scipy.
"""

import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAPS = ROOT / "content/maps.json"
WORLD = ROOT / "content/world.json"

# How far a road's middle stays from either end of the border it crosses, in cells.
ROAD_MARGIN = 10
# How many cells past an edge where a road leads into a cave stay clear of other lands: its
# mountains and their mist (WorldScene.placeCrags) reach that far.
CAVE_CLEARANCE = 30
# What the layout pays for each cell a road meets the border away from its `at`, each cell of
# wilds between lands side by side on the atlas, and each cell their middles are out of line.
MOVE_COST = 1.0
GAP_COST = 0.5
SKEW_COST = 0.05
OPPOSITE = {"north": "south", "south": "north", "east": "west", "west": "east"}


def load_maps():
    data = json.loads(MAPS.read_text())
    maps = {m["id"]: m for m in data["maps"]}
    lands = {i: m for i, m in maps.items() if "cave" not in m["theme"]}
    return data, maps, lands


def links(maps, lands):
    """Each road between two lands once, as (west or south land, east or north land, axis), and
    the edges where a road leads into a cave."""
    pairs = {}
    caves = []
    for land_id, land in lands.items():
        for exit in land["exits"]:
            if exit["to"] not in lands:
                if exit["to"] in maps:
                    caves.append((land_id, exit["edge"]))
                continue
            if exit["edge"] in ("east", "north"):
                axis = "x" if exit["edge"] == "east" else "y"
                pairs[(land_id, exit["to"])] = axis
    return [(a, b, axis) for (a, b), axis in pairs.items()], caves


def exit_of(land, edge):
    return next((e for e in land["exits"] if e["edge"] == edge), None)


def crossing(exit):
    """Where a road crosses its edge, from the edge's middle: `meets`, else `at`."""
    return exit.get("meets", exit.get("at", 0))


def road_offset(land, edge, at):
    """Where a road's middle crosses `edge`, in cells along it from the land's own corner
    (`WorldMap.carveRoad`: the middle of the edge plus `at`)."""
    length = land["height"] if edge in ("east", "west") else land["width"]
    return length // 2 + at


class Expr:
    """A linear expression: variables (by column) times coefficients, plus a constant."""

    def __init__(self, terms=None, constant=0):
        self.terms = dict(terms or {})
        self.constant = constant

    @staticmethod
    def of(value):
        return value if isinstance(value, Expr) else Expr(constant=value)

    def __add__(self, other):
        other = Expr.of(other)
        terms = dict(self.terms)
        for column, coefficient in other.terms.items():
            terms[column] = terms.get(column, 0) + coefficient
        return Expr(terms, self.constant + other.constant)

    __radd__ = __add__

    def __neg__(self):
        return Expr({c: -k for c, k in self.terms.items()}, -self.constant)

    def __sub__(self, other):
        return self + (-Expr.of(other))

    def __rsub__(self, other):
        return Expr.of(other) - self

    def __mul__(self, factor):
        return Expr({c: k * factor for c, k in self.terms.items()}, self.constant * factor)

    __rmul__ = __mul__


def solve(maps, lands):
    import numpy as np
    from scipy.optimize import Bounds, LinearConstraint, milp

    ids = sorted(lands)
    pairs, caves = links(maps, lands)
    names, bounds, integer = [], [], []
    rows = []      # (Expr, low, high)
    cost = []      # (weight, Expr of one variable)

    def var(name, low=-np.inf, high=np.inf, whole=True):
        names.append(name)
        bounds.append((low, high))
        integer.append(whole)
        return Expr({len(names) - 1: 1})

    def keep(expr, low=-np.inf, high=np.inf):
        rows.append((Expr.of(expr), low, high))

    xs = {i: var(("x", i), -3000, 3000) for i in ids}
    ys = {i: var(("y", i), -3000, 3000) for i in ids}
    # Where each road meets the border, on both sides (`meets`): its `at` unless the layout needs
    # it elsewhere. The road is still laid toward its `at`; only its last stretch bends to where it
    # meets the next land (`WorldMap.carveRoad`), so the land comes out as it was.
    ats = {}
    for land_id in ids:
        for exit in lands[land_id]["exits"]:
            if exit["to"] not in lands:
                continue
            edge = exit["edge"]
            length = lands[land_id]["height" if edge in ("east", "west") else "width"]
            bound = length // 2 - ROAD_MARGIN
            term = var(("meets", land_id, edge), -bound, bound)
            moved = var(("moved", land_id, edge), 0, np.inf, whole=False)
            keep(moved - term, -exit.get("at", 0))
            keep(moved + term, exit.get("at", 0))
            cost.append((MOVE_COST, moved))
            ats[(land_id, edge)] = term

    for a, b, axis in pairs:
        la, lb = lands[a], lands[b]
        if axis == "x":
            # b east of a: they touch, and the road's row is the same on both sides.
            keep(xs[b] - xs[a], la["width"], la["width"])
            road_a = ys[a] + road_offset(la, "east", 0) + ats[(a, "east")]
            road_b = ys[b] + road_offset(lb, "west", 0) + ats[(b, "west")]
            spans = [(ys[a], la["height"]), (ys[b], lb["height"])]
        else:
            keep(ys[b] - ys[a], la["height"], la["height"])
            road_a = xs[a] + road_offset(la, "north", 0) + ats[(a, "north")]
            road_b = xs[b] + road_offset(lb, "south", 0) + ats[(b, "south")]
            spans = [(xs[a], la["width"]), (xs[b], lb["width"])]
        keep(road_a - road_b, 0, 0)
        # Its middle well inside both lands' edges.
        for start, length in spans:
            keep(road_a - start, ROAD_MARGIN)
            keep(start + length - road_a, ROAD_MARGIN + 1)

    # Boxes that mustn't overlap: every land, and the strip past each cave's edge.
    boxes = []      # (owner, x, y, width, height) with x, y expressions
    for land_id in ids:
        land = lands[land_id]
        boxes.append((land_id, xs[land_id], ys[land_id], land["width"], land["height"]))
    for land_id, edge in caves:
        land = lands[land_id]
        w, h = land["width"], land["height"]
        dx, dy, bw, bh = {
            "east": (w, 0, CAVE_CLEARANCE, h),
            "west": (-CAVE_CLEARANCE, 0, CAVE_CLEARANCE, h),
            "north": (0, h, w, CAVE_CLEARANCE),
            "south": (0, -CAVE_CLEARANCE, w, CAVE_CLEARANCE),
        }[edge]
        boxes.append((land_id, xs[land_id] + dx, ys[land_id] + dy, bw, bh))
    big = 8000
    for n, (o1, x1, y1, w1, h1) in enumerate(boxes):
        for o2, x2, y2, w2, h2 in boxes[n + 1:]:
            if o1 == o2:
                continue
            sides = [var(("side", n, k), 0, 1) for k in range(4)]
            # One of: first west of second, east of it, south, north (big-M lets the others off).
            keep(x2 - x1 - w1 + (1 - sides[0]) * big, 0)
            keep(x1 - x2 - w2 + (1 - sides[1]) * big, 0)
            keep(y2 - y1 - h1 + (1 - sides[2]) * big, 0)
            keep(y1 - y2 - h2 + (1 - sides[3]) * big, 0)
            keep(sides[0] + sides[1] + sides[2] + sides[3], 1)

    # The atlas's order: a land further east on the atlas has its middle further east, and so on.
    for a in ids:
        for b in ids:
            ga, gb = lands[a]["world"], lands[b]["world"]
            if ga[0] < gb[0]:
                keep((xs[b] * 2 + lands[b]["width"]) - (xs[a] * 2 + lands[a]["width"]), 0)
            if ga[1] < gb[1]:
                keep((ys[b] * 2 + lands[b]["height"]) - (ys[a] * 2 + lands[a]["height"]), 0)

    # Compact: lands side by side on the atlas sit close, their middles in line.
    by_spot = {tuple(lands[i]["world"]): i for i in ids}
    for (gx, gy), a in by_spot.items():
        for dx, dy in ((1, 0), (0, 1)):
            b = by_spot.get((gx + dx, gy + dy))
            if not b:
                continue
            la, lb = lands[a], lands[b]
            gap = var(("gap", a, b), 0, np.inf, whole=False)
            skew = var(("skew", a, b), 0, np.inf, whole=False)
            if dx:
                keep(gap - (xs[b] - xs[a] - la["width"]), 0)
                middle = (ys[a] * 2 + la["height"]) - (ys[b] * 2 + lb["height"])
            else:
                keep(gap - (ys[b] - ys[a] - la["height"]), 0)
                middle = (xs[a] * 2 + la["width"]) - (xs[b] * 2 + lb["width"])
            keep(skew - middle, 0)
            keep(skew + middle, 0)
            cost.append((GAP_COST, gap))
            cost.append((SKEW_COST, skew))

    # Meadowbrook (the start) at the origin.
    start = "meadowbrook" if "meadowbrook" in lands else ids[0]
    keep(xs[start], 0, 0)
    keep(ys[start], 0, 0)

    count = len(names)
    matrix = np.zeros((len(rows), count))
    lower = np.zeros(len(rows))
    upper = np.zeros(len(rows))
    for r, (expr, low, high) in enumerate(rows):
        for column, coefficient in expr.terms.items():
            matrix[r, column] = coefficient
        lower[r] = low - expr.constant
        upper[r] = high - expr.constant
    objective = np.zeros(count)
    for weight, expr in cost:
        for column, coefficient in expr.terms.items():
            objective[column] += weight * coefficient
    result = milp(objective, constraints=LinearConstraint(matrix, lower, upper),
                  integrality=np.array([1 if whole else 0 for whole in integer]),
                  bounds=Bounds([b[0] for b in bounds], [b[1] for b in bounds]), options={"time_limit": 180})
    if result.x is None:
        sys.exit(f"No layout fits: {result.message}")

    def value(expr):
        return round(expr.constant + sum(k * result.x[c] for c, k in expr.terms.items()))

    origins = {i: [value(xs[i]), value(ys[i])] for i in ids}
    roads = {key: value(expr) for key, expr in ats.items()}
    return origins, roads, result


def write(data, lands, origins, roads):
    for (land_id, edge), value in roads.items():
        exit = exit_of(lands[land_id], edge)
        exit.pop("meets", None)
        if value != exit.get("at", 0):
            exit["meets"] = value
    MAPS.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    world = {
        "_about": "Where each outdoor land lies on the one continent, in world cells: the world cell its "
                  "south-west cell sits on (x east, y north, as a map's own columns and rows run). Lands a road "
                  "joins touch along that edge and the road meets itself across the border; borders without "
                  "a road are walled off, and where no land lies are the wilds. Laid out by "
                  "tools/world_layout.py; check_content.py checks it still fits maps.json.",
        "lands": {i: origins[i] for i in sorted(origins, key=lambda i: (-origins[i][1], origins[i][0]))},
    }
    # One land a line: "id": [x, y].
    lines = [f'    "{i}": [{x}, {y}]' for i, (x, y) in world["lands"].items()]
    WORLD.write_text("{\n  \"_about\": " + json.dumps(world["_about"], ensure_ascii=False) + ",\n  \"lands\": {\n"
                     + ",\n".join(lines) + "\n  }\n}\n")


# The coast (Fairyland/World/Coast.swift): the lands' outer corners rounded to ROUNDING cells, and
# the sea in over their coasts from SHALLOWEST to DEEPEST cells (TOWN_DEPTH beside a town), in two
# waves of noise over the continent; none within reach of a road over a border.
ROUNDING = 30
SHALLOWEST, DEEPEST, TOWN_DEPTH = 3.0, 30.0, 1.25
PROTECTION, RING = 0.8, 8.5
MASK64 = (1 << 64) - 1


def _hash(x, y, seed):
    h = ((x & MASK64) * 0x9E3779B97F4A7C15) & MASK64
    h ^= ((y & MASK64) * 0xC2B2AE3D27D4EB4F) & MASK64
    h ^= seed
    h ^= h >> 29
    h = (h * 0xBF58476D1CE4E5B9) & MASK64
    h ^= h >> 32
    return (h % 1000000) / 1000000.0


def _value(x, y, every, seed):
    import math
    gx, gy = x / every, y / every
    i, j = math.floor(gx), math.floor(gy)
    fx, fy = gx - i, gy - j
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b, c, d = _hash(i, j, seed), _hash(i + 1, j, seed), _hash(i, j + 1, seed), _hash(i + 1, j + 1, seed)
    return (a * (1 - sx) + b * sx) * (1 - sy) + (c * (1 - sx) + d * sx) * sy


def coast(lands, origins, left, bottom, width, height):
    """Where the sea is over the continent's cells from (left, bottom), width x height: True for sea.

    Without what's on each land (roads, water, hills and people hold the sea back in the game), and
    with straight-line distances where the game steps cell by cell: near enough to tune by."""
    import numpy as np
    from scipy import ndimage
    land = np.zeros((height, width), bool)
    town = np.zeros((height, width), bool)
    for land_id, (x, y) in origins.items():
        spec = lands[land_id]
        land[y - bottom:y - bottom + spec["height"], x - left:x - left + spec["width"]] = True
        if spec.get("fence"):
            town[y - bottom:y - bottom + spec["height"], x - left:x - left + spec["width"]] = True
    to_sea = ndimage.distance_transform_edt(land)
    to_core = ndimage.distance_transform_edt(to_sea < ROUNDING)
    shape = np.where(to_sea >= ROUNDING, to_sea, ROUNDING - to_core)
    crossings = np.ones((height, width), bool)
    for land_id, (x, y) in origins.items():
        spec = lands[land_id]
        for exit in spec["exits"]:
            if exit["to"] not in origins:
                continue
            edge, along = exit["edge"], road_offset(spec, exit["edge"], crossing(exit))
            cx, cy = {"east": (x + spec["width"] - 1, y + along), "west": (x, y + along),
                      "north": (x + along, y + spec["height"] - 1), "south": (x + along, y)}[edge]
            crossings[cy - bottom, cx - left] = False
    to_crossing = ndimage.distance_transform_edt(crossings)
    to_town = ndimage.distance_transform_edt(~town) if town.any() else np.full((height, width), 1e9)
    sea = ~land
    for row, col in zip(*np.nonzero(land & (shape < DEEPEST))):
        x, y = col + left + 0.5, row + bottom + 0.5
        wave = (_value(x, y, 64, 0x51) + _value(x, y, 24, 0xA7) * 0.4) / 1.4
        depth = SHALLOWEST + (DEEPEST - SHALLOWEST) * wave
        t = min(1.0, max(0.0, (to_town[row, col] - 1) / 12))
        depth = TOWN_DEPTH + (depth - TOWN_DEPTH) * t * t * (3 - 2 * t)
        depth = min(depth, PROTECTION * to_crossing[row, col] - RING)
        sea[row, col] = shape[row, col] < depth
    return sea


# Where two lands meet, one gives way to the other across a band: SEAM_BLEND cells either side of a
# middle line that wanders up to SEAM_REACH cells either side of the straight border, in waves of
# noise along it (every SEAM_WAVES cells), coming back to the border over the last SEAM_TAPER cells
# at either end of the stretch they share. Across the band the other land's ground comes in
# patches (`patch`), more and more of them. Not beside a town, whose walls stand on the border.
SEAM_REACH, SEAM_TAPER, SEAM_BLEND = 10.0, 16.0, 20.0
SEAM_WAVES = ((52, 0x5EA, 1.0), (18, 0x5EB, 0.5), (7, 0x5EC, 0.18))


def seam_fade(along, low, high):
    """How far the band reaches at `along`: none at the ends of the stretch two lands share
    (low...high, world cells), all of it SEAM_TAPER in (`Seam.fade`)."""
    t = min(1.0, max(0.0, min(along - low, high - along) / SEAM_TAPER))
    return t * t * (3 - 2 * t)


def seam_offset(along, line, low, high, sign):
    """How far into the land `sign` is +1 for (the first of the two by id) the middle line lies at
    `along` (in world cells along the border, which lies at `line` across it; the two share
    low...high): `Seam.offset` in Fairyland/World/Seam.swift (keep the two in step)."""
    fade = seam_fade(along, low, high)
    if fade <= 0:
        return 0.0
    wave = sum(_value(along, line, every, seed) * weight for every, seed, weight in SEAM_WAVES)
    wave /= sum(weight for _, _, weight in SEAM_WAVES)
    return sign * (wave * 2 - 1) * SEAM_REACH * fade


def seam_share(side, width):
    """How much of the ground is the other land's `side` cells this side of the middle line, the
    band `width` either side of it (`Seam.share`)."""
    t = min(1.0, max(0.0, (width - side) / (2 * width)))
    return t * t * (3 - 2 * t)


def seam_patch(x, y):
    """Patchy noise over the continent's cells, 0.02...0.98 (`Seam.patch`)."""
    raw = (_value(x, y, 3.4, 0x9A1) + _value(x, y, 1.5, 0x9A2) * 0.5) / 1.5
    return min(0.98, max(0.02, 0.5 + (raw - 0.5) * 1.8))


def borders(lands, origins):
    """Every pair of lands sharing a stretch of border, neither a town: (first, second, the edge of
    the first it runs along, where the border lies across, the world cells along it they share)."""
    found = []
    ids = sorted(origins)
    for i, a in enumerate(ids):
        for b in ids[i + 1:]:
            if lands[a].get("fence") or lands[b].get("fence"):
                continue
            (ax, ay), (bx, by) = origins[a], origins[b]
            aw, ah, bw, bh = lands[a]["width"], lands[a]["height"], lands[b]["width"], lands[b]["height"]
            rows = (max(ay, by), min(ay + ah, by + bh))
            columns = (max(ax, bx), min(ax + aw, bx + bw))
            if ax + aw == bx and rows[0] < rows[1]:
                found.append((a, b, "east", bx, rows))
            elif bx + bw == ax and rows[0] < rows[1]:
                found.append((a, b, "west", ax, rows))
            elif ay + ah == by and columns[0] < columns[1]:
                found.append((a, b, "north", by, columns))
            elif by + bh == ay and columns[0] < columns[1]:
                found.append((a, b, "south", ay, columns))
    return found


def looks(lands, origins, left, bottom, width, height):
    """Which land's ground shows at each cell from (left, bottom): its index in sorted(origins), or
    -1 in no land. Each land's own, but across the band between two lands, the other's in patches
    (`Seam.showsOther`)."""
    import numpy as np
    ids = sorted(origins)
    look = np.full((height, width), -1, int)
    for index, land_id in enumerate(ids):
        x, y = origins[land_id]
        look[y - bottom:y - bottom + lands[land_id]["height"], x - left:x - left + lands[land_id]["width"]] = index
    depth = int(SEAM_REACH + SEAM_BLEND) + 1
    for a, b, edge, line, (low, high) in borders(lands, origins):
        for along in range(low, high):
            offset = seam_offset(along + 0.5, line, low, high, 1)
            spread = SEAM_BLEND * max(0.1, seam_fade(along + 0.5, low, high))
            for cell in range(line - depth, line + depth):
                # How far the cell's middle is into the first land, from the border.
                inward = (line - cell - 0.5) if edge in ("east", "north") else (cell + 0.5 - line)
                share = seam_share(inward - offset, spread)  # the second land's share
                cx, cy = (cell + 0.5, along + 0.5) if edge in ("east", "west") else (along + 0.5, cell + 0.5)
                shown = ids.index(b) if share > seam_patch(cx, cy) else ids.index(a)
                col, row = int(cx - 0.5) - left, int(cy - 0.5) - bottom
                if 0 <= row < height and 0 <= col < width and look[row, col] in (ids.index(a), ids.index(b)):
                    look[row, col] = shown
    return look


def preview(lands, origins, path):
    import numpy as np
    from PIL import Image, ImageDraw
    xs = [origins[i][0] for i in origins] + [origins[i][0] + lands[i]["width"] for i in origins]
    ys = [origins[i][1] for i in origins] + [origins[i][1] + lands[i]["height"] for i in origins]
    left, right, bottom, top = min(xs) - 40, max(xs) + 40, min(ys) - 40, max(ys) + 40
    scale = 2
    colours = {"tile_grass": (120, 190, 90), "tile_sand": (230, 210, 150), "tile_dark_grass": (70, 120, 70),
               "tile_forest_floor": (90, 130, 60), "tile_snow": (235, 240, 250), "tile_swamp": (100, 120, 80),
               "tile_desert": (220, 190, 120), "tile_scree": (150, 150, 160)}
    sea = coast(lands, origins, left, bottom, right - left, top - bottom)
    cells = np.zeros((top - bottom, right - left, 3), np.uint8)
    cells[:] = (59, 127, 192)
    look = looks(lands, origins, left, bottom, right - left, top - bottom)
    for index, land_id in enumerate(sorted(origins)):
        cells[(look == index) & ~sea] = colours.get(lands[land_id]["theme"]["ground"], (200, 200, 200))
    # North up: the picture's rows run top down.
    image = Image.fromarray(cells[::-1]).resize(((right - left) * scale, (top - bottom) * scale), Image.NEAREST)
    draw = ImageDraw.Draw(image)

    def box(x, y, w, h):
        return [(x - left) * scale, (top - y - h) * scale, (x + w - left) * scale - 1, (top - y - 1) * scale]

    for land_id, (x, y) in origins.items():
        land = lands[land_id]
        draw.text(((x - left + 3) * scale, (top - y - land["height"] + 3) * scale), land_id, fill=(0, 0, 0))
        for exit in land["exits"]:
            edge, at = exit["edge"], crossing(exit)
            if edge in ("east", "west"):
                ry = y + road_offset(land, edge, at)
                rx = x + land["width"] - 4 if edge == "east" else x
                draw.rectangle(box(rx, ry - 1, 4, 3), fill=(200, 60, 40) if exit["to"] in lands else (40, 40, 40))
            else:
                rx = x + road_offset(land, edge, at)
                ry = y + land["height"] - 4 if edge == "north" else y
                draw.rectangle(box(rx - 1, ry, 3, 4), fill=(200, 60, 40) if exit["to"] in lands else (40, 40, 40))
    image.save(path)


def verify(maps, lands, world):
    """Problems with world.json against maps.json, as messages (the checker shares this)."""
    problems = []
    origins = world.get("lands", {})
    for land_id in lands:
        if land_id not in origins:
            problems.append(f"world.json: {land_id} has no place on the continent")
    for land_id in origins:
        if land_id not in lands:
            problems.append(f"world.json: {land_id} isn't an outdoor map")
    if problems:
        return problems
    pairs, caves = links(maps, lands)

    def rect(land_id):
        x, y = origins[land_id]
        return x, y, x + lands[land_id]["width"], y + lands[land_id]["height"]

    for a, b, axis in pairs:
        ax0, ay0, ax1, ay1 = rect(a)
        bx0, by0, bx1, by1 = rect(b)
        ea, eb = ("east", "west") if axis == "x" else ("north", "south")
        road_a = road_offset(lands[a], ea, crossing(exit_of(lands[a], ea)))
        road_b = road_offset(lands[b], eb, crossing(exit_of(lands[b], eb)))
        if axis == "x":
            if bx0 != ax1:
                problems.append(f"world.json: {b} doesn't touch {a}'s east edge, where a road joins them")
            ya, yb = ay0 + road_a, by0 + road_b
            if ya != yb:
                problems.append(f"world.json: the road from {a} east meets {b} {abs(ya - yb)} cells off")
            if not (max(ay0, by0) + ROAD_MARGIN <= ya < min(ay1, by1) - ROAD_MARGIN):
                problems.append(f"world.json: the road from {a} east into {b} is too near the end of their border")
        else:
            if by0 != ay1:
                problems.append(f"world.json: {b} doesn't touch {a}'s north edge, where a road joins them")
            xa, xb = ax0 + road_a, bx0 + road_b
            if xa != xb:
                problems.append(f"world.json: the road from {a} north meets {b} {abs(xa - xb)} cells off")
            if not (max(ax0, bx0) + ROAD_MARGIN <= xa < min(ax1, bx1) - ROAD_MARGIN):
                problems.append(f"world.json: the road from {a} north into {b} is too near the end of their border")
    boxes = [(i, *rect(i)) for i in lands]
    for land_id, edge in caves:
        x0, y0, x1, y1 = rect(land_id)
        boxes.append((land_id, *{
            "east": (x1, y0, x1 + CAVE_CLEARANCE, y1), "west": (x0 - CAVE_CLEARANCE, y0, x0, y1),
            "north": (x0, y1, x1, y1 + CAVE_CLEARANCE), "south": (x0, y0 - CAVE_CLEARANCE, x1, y0),
        }[edge]))
    for n, (o1, ax0, ay0, ax1, ay1) in enumerate(boxes):
        for o2, bx0, by0, bx1, by1 in boxes[n + 1:]:
            if o1 != o2 and ax0 < bx1 and bx0 < ax1 and ay0 < by1 and by0 < ay1:
                problems.append(f"world.json: {o1} and {o2} overlap (or one stands in the mountains past a cave's edge)")
    return problems


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="only check world.json against maps.json")
    parser.add_argument("--preview", metavar="PNG", help="draw the continent")
    args = parser.parse_args()
    data, maps, lands = load_maps()
    if args.check:
        world = json.loads(WORLD.read_text())
        problems = verify(maps, lands, world)
        print("\n".join(problems) or "world.json fits maps.json")
        if args.preview:
            preview(lands, {k: tuple(v) for k, v in world["lands"].items() if k in lands}, args.preview)
            print(f"preview: {args.preview}")
        sys.exit(1 if problems else 0)
    origins, roads, result = solve(maps, lands)
    print(f"{result.message} (cost {result.fun:.1f})")
    moved = [(k, v) for k, v in roads.items() if v != (exit_of(lands[k[0]], k[1]) or {}).get("at", 0)]
    for (land_id, edge), value in sorted(moved):
        at = exit_of(lands[land_id], edge).get("at", 0)
        print(f"  {land_id} {edge}: meets {value} (at {at}, {value - at:+d})")
    write(data, lands, origins, roads)
    problems = verify(maps, lands, json.loads(WORLD.read_text()))
    print("\n".join(problems) or "world.json written; it fits maps.json")
    if args.preview:
        preview(lands, origins, args.preview)
        print(f"preview: {args.preview}")


if __name__ == "__main__":
    main()
