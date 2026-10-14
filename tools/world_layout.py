#!/usr/bin/env python3
"""Paints the lands as one continent (content/world.json): each land a shape of its own, as
RuneScape's regions are, not a rectangle.

The design (world.json `design`) gives each land its middle on the continent (`at`, in world cells,
x east and y north) and, but for a town, one or more lobes round it: ellipses `[dx, dy, across,
up, turn°]` out from its middle. Every cell goes to the land whose lobes reach it most easily (its
distance over their size), the lands pushing against each other where they meet; where none
reaches, the sea. The lobes are scaled so each land comes out as many cells as its `area` (about
as big as its map was), and the whole continent is bent by smooth noise first
(`WARPS`), so coasts and borders wander: bays, headlands and capes instead of straight lines.
A town is its rectangle exactly, its wall all round.

Then it's tidied: stray cells and slivers go to the land round them, a land in more than one piece
keeps its biggest, pools inland fill in. Where a road crosses from one land into the next, the
border runs straight for a stretch (`CROSSING`), across the way the exit goes, so the road meets
itself and a quest's gate fits; a town's road crosses its wall where its exit says (`at`, from the
middle of that side). Where a road leads into a cave, that side of the land is a straight coast
(`CAVE_ALONG` either side of the road) with open sea past it for the mountains the cave is in.

Rivers (world.json `rivers`) run from a spring to the sea through the turns of their `course`,
meandering a little (`RIVER_WOBBLE`) and widening as they go, some from one land on into the next.
They keep clear of towns, the roads' crossings, the middles and everything set down by hand; a road
or trail crossing one gets a bridge in the game, so it has to cross squarely, where the river's
narrow and away from the sea; and bits of land a river cuts off with no road over go under water if
they're small (`SLIVER`), else it's a problem to fix in the course.

Each land's map is the box round its shape, its middle at the land's middle (maps.json `width`
and `height`, which this writes). world.json gets, per land, the cell its box starts on (`lands`),
where each road crosses its border (`roads`, in its own cells: the last cell on its side, the next
one over the edge the exit names being the other land's), each river's middle (`line`), and its
shape (`regions`): row by row from the south, over its box and `MARGIN` cells round it, runs of
`[code, length]`: 1 its own land, 2 the sea it draws (the sea nearest it), 3 its own land under a
river, 4 a land next door's under a river, 0 neither.

    python3 tools/world_layout.py                     # paint, write content/world.json and the sizes
    python3 tools/world_layout.py --check             # only check world.json against maps.json
    python3 tools/world_layout.py --preview out.png   # and a picture of the continent (pillow)
    python3 tools/world_layout.py --check --preview out.png

Painting needs numpy and scipy; the check needs neither (check_content.py runs it).
"""

import argparse
import json
import math
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAPS = ROOT / "content/maps.json"
WORLD = ROOT / "content/world.json"

# How far round each land's box its shape is written: the sea it draws reaches that far
# (WorldScene.surroundingsMargin).
MARGIN = 18
# The bends in the continent: (every how many cells, how far, seeds for x and y).
WARPS = ((110, 22.0, 0xA11, 0xA12), (40, 10.0, 0xA13, 0xA14), (14, 3.0, 0xA15, 0xA16))
# The coast's own roughness: how far the reach of the lobes wanders at the coast, every how many cells.
COAST_WOBBLE = ((28, 0.13, 0xC01), (9, 0.05, 0xC02))
# Where a road crosses between two lands, the border runs straight this far either side of it,
# and this far back into each land.
CROSSING = 8
CROSSING_DEEP = 9
# Where a road leads into a cave: the coast runs straight this far either side of it, the land
# reaching it this far in, and no land this far past it (its mountains and their mist,
# WorldScene.placeCrags).
CAVE_ALONG = 16
CAVE_DEEP = 10
CAVE_CLEARANCE = 30
# Sea enclosed by land smaller than this fills in (pools inland); bigger is an inland sea.
POOL = 900
# Land in pieces smaller than this goes to the sea or the land round it.
SCRAP = 400
# How far inside its land everything set down by hand must stand, and a road's line from the
# hub (or its last waypoint) to where it crosses.
CONTENT_MARGIN = 3
ROAD_MARGIN = 3
# Rivers (world.json `rivers`): a gentle meander sideways off the course drawn ((every, cells,
# seed), along the river), and a pool round each river's spring this much wider than it.
RIVER_WOBBLE = ((18, 2.2, 0xD01), (7, 0.7, 0xD02))
SPRING = 2.0
# How far a river keeps from where a road crosses a border, from a land's middle and hub, from
# anything set down by hand, from a town and from where a road leads into a cave, in cells.
RIVER_CROSSING = 10
RIVER_MIDDLE = 8
RIVER_CONTENT = 4
RIVER_TOWN = 5
RIVER_CAVE = 30
# Where a road crosses a river (a bridge, `WorldMap.bridge(over:along:)`): at least this square on
# (the cosine of the angle between them, at most), no wider than this, and this far from the sea
# (whose shore slopes down to it), the road's border crossing and its hub.
BRIDGE_SQUARE = 0.6
BRIDGE_WIDEST = 8.0
BRIDGE_SEA = 10
BRIDGE_END = 10
# Bits of land a river cuts off from the rest smaller than this go under its water.
SLIVER = 120
# Codes in a land's shape (`regions`): its own land, the sea it draws, its own land under a river,
# and another land's under a river.
OWN, SEA, RIVER, RIVER_AWAY = 1, 2, 3, 4

STEP = {"east": (1, 0), "west": (-1, 0), "north": (0, 1), "south": (0, -1)}
OPPOSITE = {"north": "south", "south": "north", "east": "west", "west": "east"}


def load_maps():
    data = json.loads(MAPS.read_text())
    maps = {m["id"]: m for m in data["maps"]}
    lands = {i: m for i, m in maps.items() if "cave" not in m["theme"]}
    return data, maps, lands


def is_town(land):
    return land.get("fence") is True


# MARK: Noise (the same hash as Fairyland/World/Coast.swift's)

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
    gx, gy = x / every, y / every
    i, j = math.floor(gx), math.floor(gy)
    fx, fy = gx - i, gy - j
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b, c, d = _hash(i, j, seed), _hash(i + 1, j, seed), _hash(i, j + 1, seed), _hash(i + 1, j + 1, seed)
    return (a * (1 - sx) + b * sx) * (1 - sy) + (c * (1 - sx) + d * sx) * sy


def _hash_np(x, y, seed):
    import numpy as np
    with np.errstate(over="ignore"):
        h = x.astype(np.int64).astype(np.uint64) * np.uint64(0x9E3779B97F4A7C15)
        h ^= y.astype(np.int64).astype(np.uint64) * np.uint64(0xC2B2AE3D27D4EB4F)
        h ^= np.uint64(seed)
        h ^= h >> np.uint64(29)
        h *= np.uint64(0xBF58476D1CE4E5B9)
        h ^= h >> np.uint64(32)
    return (h % np.uint64(1000000)).astype(np.float64) / 1000000.0


def _value_np(x, y, every, seed):
    """`_value` over arrays."""
    import numpy as np
    gx, gy = x / every, y / every
    i, j = np.floor(gx), np.floor(gy)
    fx, fy = gx - i, gy - j
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = _hash_np(i, j, seed), _hash_np(i + 1, j, seed)
    c, d = _hash_np(i, j + 1, seed), _hash_np(i + 1, j + 1, seed)
    return (a * (1 - sx) + b * sx) * (1 - sy) + (c * (1 - sx) + d * sx) * sy


# MARK: Painting

class Canvas:
    """The continent's cells from (left, bottom), width × height: which land each is (an index into
    `ids`, -1 the sea)."""

    def __init__(self, ids, left, bottom, width, height):
        import numpy as np
        self.ids = ids
        self.left, self.bottom, self.width, self.height = left, bottom, width, height
        self.owner = np.full((height, width), -1, np.int32)

    def index(self, x, y):
        return y - self.bottom, x - self.left

    def get(self, x, y):
        r, c = self.index(x, y)
        if 0 <= r < self.height and 0 <= c < self.width:
            return int(self.owner[r, c])
        return -1

    def set(self, x, y, value):
        r, c = self.index(x, y)
        if 0 <= r < self.height and 0 <= c < self.width:
            self.owner[r, c] = value


def town_box(land, at):
    """A town's rectangle: (left, bottom, width, height) in world cells, its middle cell at `at` as
    a map's middle is (`WorldMap.center`: width / 2, height / 2)."""
    w, h = land["width"], land["height"]
    return at[0] - w // 2, at[1] - h // 2, w, h


def lobes(design, lands):
    """Every land's lobes on the continent: (x, y, across, up, turn in radians), its own and one
    toward each land a road joins it to, so the two always meet (most of the way along the line
    between their middles; to a town, just outside its gate)."""
    found = {i: [] for i in design}
    for land_id, spec in design.items():
        if is_town(lands[land_id]):
            continue
        cx, cy = spec["at"]
        for lobe in spec["lobes"]:
            found[land_id].append((cx + lobe[0], cy + lobe[1], lobe[2], lobe[3], math.radians(lobe[4]) if len(lobe) > 4 else 0.0))
    for land_id, exit in road_pairs(lands):
        other = exit["to"]
        a, b = design[land_id]["at"], design[other]["at"]
        for here, there, town in ((land_id, other, other), (other, land_id, land_id)):
            if is_town(lands[here]):
                continue
            hx, hy = design[here]["at"]
            if is_town(lands[town]):
                # Just outside the town's gate, on the side toward this land.
                edge = exit["edge"] if town == other else OPPOSITE[exit["edge"]]
                x, y, w, h = town_box(lands[town], design[town]["at"])
                texit = next(e for e in lands[town]["exits"] if e["to"] == here)
                at = texit.get("at", 0)
                back = OPPOSITE[edge]
                gx, gy = {"east": (x + w + 12, y + h // 2 + at), "west": (x - 13, y + h // 2 + at),
                          "north": (x + w // 2 + at, y + h + 12), "south": (x + w // 2 + at, y - 13)}[back]
                found[here].append((gx, gy, 16, 16, 0.0))
            else:
                tx, ty = design[there]["at"]
                length = math.hypot(tx - hx, ty - hy)
                found[here].append((hx + (tx - hx) * 0.4, hy + (ty - hy) * 0.4, length * 0.32, length * 0.32, 0.0))
    return found


def reach(shapes, ids, xs, ys, scales):
    """How easily each land's lobes reach every cell: its distance over their size (below 1
    inside them), for the cells at world (xs, ys), already bent. A town reaches nowhere (its
    rectangle is laid over the rest)."""
    import numpy as np
    big = np.full((len(ids),) + xs.shape, np.inf)
    for k, land_id in enumerate(ids):
        s = scales[land_id]
        for x, y, ax, ay, turn in shapes[land_id]:
            px, py = xs - x, ys - y
            u = px * math.cos(turn) + py * math.sin(turn)
            v = -px * math.sin(turn) + py * math.cos(turn)
            n = np.sqrt((u / (ax * s)) ** 2 + (v / (ay * s)) ** 2)
            big[k] = np.minimum(big[k], n)
    return big


def paint(design, lands):
    """The continent, painted, before it's tidied."""
    import numpy as np
    ids = sorted(design)
    left = bottom = 10 ** 9
    right = top = -10 ** 9
    for land_id in ids:
        cx, cy = design[land_id]["at"]
        extent = max(lands[land_id]["width"], lands[land_id]["height"]) * 1.4 + 60
        left, right = min(left, int(cx - extent)), max(right, int(cx + extent))
        bottom, top = min(bottom, int(cy - extent)), max(top, int(cy + extent))
    canvas = Canvas(ids, left, bottom, right - left, top - bottom)
    ys, xs = np.mgrid[bottom:top, left:right].astype(np.float64)
    xs += 0.5
    ys += 0.5
    bent_x, bent_y = xs.copy(), ys.copy()
    for every, far, seed_x, seed_y in WARPS:
        bent_x += (_value_np(xs, ys, every, seed_x) * 2 - 1) * far
        bent_y += (_value_np(xs, ys, every, seed_y) * 2 - 1) * far
    wobble = np.zeros_like(xs)
    for every, far, seed in COAST_WOBBLE:
        wobble += (_value_np(xs, ys, every, seed) * 2 - 1) * far
    targets = {i: design[i].get("area", 0) for i in ids}
    scales = {i: 1.0 for i in ids}
    shapes = lobes(design, lands)
    for _ in range(10):
        near = reach(shapes, ids, bent_x, bent_y, scales)
        best = near.argmin(axis=0)
        least = near.min(axis=0)
        owner = np.where(least < 1 + wobble, best, -1).astype(np.int32)
        # The towns, their rectangles exactly.
        for k, land_id in enumerate(ids):
            if is_town(lands[land_id]):
                x, y, w, h = town_box(lands[land_id], design[land_id]["at"])
                r, c = canvas.index(x, y)
                owner[r:r + h, c:c + w] = k
        areas = np.bincount(owner[owner >= 0].ravel(), minlength=len(ids))
        for k, land_id in enumerate(ids):
            if is_town(lands[land_id]) or areas[k] == 0:
                continue
            scales[land_id] *= (targets[land_id] / areas[k]) ** 0.5
    canvas.owner = owner
    return canvas


def tidy(canvas, keep, towns):
    """Stray cells go to the land round them; a land in pieces keeps its biggest (the rest to the sea,
    or to the land round it); pools inland fill in. `keep`: cells (a bool array) left as they are.
    `towns`: the towns' indices, which never take a cell (their rectangles are kept)."""
    import numpy as np
    from scipy import ndimage
    owner = canvas.owner
    count = len(canvas.ids)

    def most(values):
        """The commonest of these lands, but a town (or the sea, -1, if there's none)."""
        values = values[~np.isin(values, list(towns))] if towns else values
        return int(np.bincount(values + 1).argmax()) - 1 if values.size else -1

    # Smoothed: each cell the most common land of the 5×5 round it (the sea counts as one).
    for _ in range(2):
        votes = np.zeros((count + 1,) + owner.shape, np.int16)
        for k in range(-1, count):
            if k in towns:
                continue
            votes[k + 1] = ndimage.uniform_filter((owner == k).astype(np.float32), size=5, mode="nearest") * 25 + 0.5
        smooth = votes.argmax(axis=0).astype(np.int32) - 1
        owner = np.where(keep, owner, smooth)
    four = np.array([[0, 1, 0], [1, 1, 1], [0, 1, 0]])
    for _ in range(4):
        changed = False
        for k in range(count):
            labels, found = ndimage.label(owner == k, structure=four)
            if found <= 1:
                continue
            sizes = ndimage.sum(np.ones_like(labels), labels, range(1, found + 1))
            biggest = int(np.argmax(sizes)) + 1
            for piece in range(1, found + 1):
                cells = (labels == piece) & ~keep
                if piece == biggest or not cells.any():
                    continue
                around = ndimage.binary_dilation(cells, structure=four) & ~cells
                others = owner[around]
                owner[cells] = most(others[others != k])
                changed = True
        # Pools inland, and scraps of land out at sea.
        labels, found = ndimage.label(owner == -1, structure=four)
        edge = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]])))
        sizes = ndimage.sum(np.ones_like(labels), labels, range(1, found + 1))
        for piece in range(1, found + 1):
            if piece in edge or sizes[piece - 1] >= POOL:
                continue
            cells = labels == piece
            around = ndimage.binary_dilation(cells, structure=four) & ~cells
            others = owner[around]
            fill = most(others[others >= 0])
            if fill >= 0:
                owner[cells & ~keep] = fill
                changed = True
        for k in range(count):
            labels, found = ndimage.label(owner == k, structure=four)
            sizes = ndimage.sum(np.ones_like(labels), labels, range(1, found + 1))
            for piece in range(1, found + 1):
                cells = (labels == piece) & ~keep
                if sizes[piece - 1] < SCRAP and cells.any():
                    owner[cells] = -1
                    changed = True
        if not changed:
            break
    canvas.owner = owner


def road_pairs(lands):
    """Every road between two lands once, as (land, its exit), from the side that names the edge
    first by id."""
    pairs = []
    for land_id in sorted(lands):
        for exit in lands[land_id]["exits"]:
            if exit["to"] in lands and (land_id < exit["to"]):
                pairs.append((land_id, exit))
    return pairs


def cave_exits(maps, lands):
    return [(land_id, exit) for land_id in sorted(lands) for exit in lands[land_id]["exits"]
            if exit["to"] not in lands and exit["to"] in maps]


def straighten(canvas, keep, a, b, cell, edge, along, deep, only=None):
    """Lays a straight border between `a` (index, the side `cell` is on) and `b` (index, or -1 for the
    sea), across `edge` (the way from `a` into `b`): `along` either side of `cell` and `deep` back
    into each. `only`: which side to lay (`"a"`, `"b"`), else both. Cells of a third land, and kept
    cells, stay as they are."""
    dx, dy = STEP[edge]
    side = (-dy, dx)
    x0, y0 = cell
    for s in range(-along, along + 1):
        for d in range(-deep + 1, deep + 1):
            x, y = x0 + side[0] * s + dx * d, y0 + side[1] * s + dy * d
            here = canvas.get(x, y)
            r, c = canvas.index(x, y)
            if not (0 <= r < canvas.height and 0 <= c < canvas.width) or keep[r, c]:
                continue
            if here not in (a, b, -1):
                continue
            mine = d <= 0
            if only == "a" and not mine or only == "b" and mine:
                continue
            canvas.set(x, y, a if mine else b)


def crossings(canvas, design, lands, maps, keep):
    """Where every road crosses its border, as {land: {to: (x, y)}} in world cells (the last cell on
    the land's side), each road's border laid straight there; and each cave's straight coast."""
    import numpy as np
    ids = canvas.ids
    index = {land_id: k for k, land_id in enumerate(ids)}
    found = {land_id: {} for land_id in ids}
    problems = []
    for land_id, exit in road_pairs(lands):
        other = exit["to"]
        edge = exit["edge"]
        a, b = index[land_id], index[other]
        dx, dy = STEP[edge]
        town_a, town_b = is_town(lands[land_id]), is_town(lands[other])
        if town_a or town_b:
            # Through a town's wall where its exit says: the middle of that side, plus `at`.
            town, back = (land_id, edge) if town_a else (other, OPPOSITE[edge])
            x, y, w, h = town_box(lands[town], design[town]["at"])
            texit = next(e for e in lands[town]["exits"] if e["to"] in (land_id, other) and e["to"] != town)
            at = texit.get("at", 0)
            gate = {"east": (x + w - 1, y + h // 2 + at), "west": (x, y + h // 2 + at),
                    "north": (x + w // 2 + at, y + h - 1), "south": (x + w // 2 + at, y)}[back]
            tx, ty = STEP[back]
            outside = (gate[0] + tx, gate[1] + ty)
            if town_a and town_b:
                pass
            else:
                straighten(canvas, keep, index[town], index[other if town_a else land_id], gate, back,
                           CROSSING, CROSSING_DEEP, only="b")
            cell = gate if town_a else outside
        else:
            # The middle of the stretch of border facing the way the exit goes, nearest where the
            # exit wants it (`at` from the land's middle), else between the two middles.
            r, c = np.nonzero(canvas.owner == a)
            xs, ys = c + canvas.left, r + canvas.bottom
            nx, ny = xs + dx, ys + dy
            ok = np.array([canvas.get(x, y) == b for x, y in zip(nx, ny)]) if len(xs) else np.array([], bool)
            if not ok.any():
                problems.append(f"{land_id} doesn't touch {other} on its {edge} side, where a road joins them")
                continue
            xs, ys = xs[ok], ys[ok]
            (ax, ay), (bx, by) = design[land_id]["at"], design[other]["at"]
            if edge in ("east", "west"):
                want = ay + exit["at"] if "at" in exit else (ay + by) / 2
                spread = ys
            else:
                want = ax + exit["at"] if "at" in exit else (ax + bx) / 2
                spread = xs
            # Prefer the middle of a long stretch: how much border there is near each cell.
            score = []
            for x, y, s in zip(xs, ys, spread):
                near = np.abs(spread - s) <= CROSSING
                score.append(abs(s - want) - 3 * near.sum())
            pick = int(np.argmin(score))
            cell = (int(xs[pick]), int(ys[pick]))
            straighten(canvas, keep, a, b, cell, edge, CROSSING, CROSSING_DEEP)
        found[land_id][other] = cell
        found[other][land_id] = (cell[0] + dx, cell[1] + dy)
        # Kept from here on.
        x0, y0 = cell
        side = (-dy, dx)
        for s in range(-CROSSING, CROSSING + 1):
            for d in range(-CROSSING_DEEP + 1, CROSSING_DEEP + 1):
                r, c = canvas.index(x0 + side[0] * s + dx * d, y0 + side[1] * s + dy * d)
                if 0 <= r < canvas.height and 0 <= c < canvas.width and canvas.owner[r, c] in (a, b):
                    keep[r, c] = True
    for land_id, exit in cave_exits(maps, lands):
        edge = exit["edge"]
        a = index[land_id]
        dx, dy = STEP[edge]
        cx, cy = design[land_id]["at"]
        at = exit.get("at", 0)
        r, c = np.nonzero(canvas.owner == a)
        xs, ys = c + canvas.left, r + canvas.bottom
        # The line: where the coast lies along the stretch, on the whole (half of it in front, half
        # behind, as each row's or column's furthest cell goes).
        if edge in ("east", "west"):
            band = np.abs(ys - (cy + at)) <= CAVE_ALONG
            ends = [xs[band & (ys == y)].max() if edge == "east" else xs[band & (ys == y)].min()
                    for y in np.unique(ys[band])]
            line = int(np.median(ends))
            cell = (line, cy + at)
        else:
            band = np.abs(xs - (cx + at)) <= CAVE_ALONG
            ends = [ys[band & (xs == x)].max() if edge == "north" else ys[band & (xs == x)].min()
                    for x in np.unique(xs[band])]
            line = int(np.median(ends))
            cell = (cx + at, line)
        # The land right up to the line along the stretch, nothing of it past the line anywhere,
        # and nothing at all past it for the mountains.
        straighten(canvas, keep, a, -1, cell, edge, CAVE_ALONG, CAVE_DEEP, only="a")
        for x, y in zip(xs, ys):
            past = (x - cell[0]) * dx + (y - cell[1]) * dy
            if past > 0:
                canvas.set(int(x), int(y), -1)
        side = (-dy, dx)
        for s in range(-CAVE_ALONG - 10, CAVE_ALONG + 11):
            for d in range(1, CAVE_CLEARANCE + 1):
                x, y = cell[0] + side[0] * s + dx * d, cell[1] + side[1] * s + dy * d
                if canvas.get(x, y) >= 0:
                    problems.append(f"{ids[canvas.get(x, y)]} stands in the mountains past {land_id}'s {edge} side, "
                                    "where a road leads into a cave")
                    break
        found[land_id][exit["to"]] = cell
    return found, sorted(set(problems))


def boxes(canvas, design, lands):
    """Each land's map: (left, bottom, width, height), the box round its shape (a town's, its
    rectangle). Its middle (`WorldMap.center`, what everything set down by hand is placed from) is
    the box's: width / 2, height / 2 in."""
    import numpy as np
    found = {}
    for k, land_id in enumerate(canvas.ids):
        land = lands[land_id]
        if is_town(land):
            found[land_id] = town_box(land, design[land_id]["at"])
            continue
        r, c = np.nonzero(canvas.owner == k)
        xs, ys = c + canvas.left, r + canvas.bottom
        found[land_id] = (int(xs.min()), int(ys.min()), int(xs.max() - xs.min() + 1), int(ys.max() - ys.min() + 1))
    return found


def seas(canvas):
    """Which land draws each cell of the sea: the nearest (an index; -1 on land)."""
    import numpy as np
    from scipy import ndimage
    sea = canvas.owner < 0
    _, (rows, cols) = ndimage.distance_transform_edt(sea, return_indices=True)
    nearest = canvas.owner[rows, cols]
    return np.where(sea, nearest, -1)


def encode(row):
    """A row of codes as runs: [code, length, code, length, ...]."""
    runs = []
    for value in row:
        value = int(value)
        if runs and runs[-2] == value:
            runs[-1] += 1
        else:
            runs += [value, 1]
    return runs


def decode(runs):
    row = []
    for n in range(0, len(runs), 2):
        row += [runs[n]] * runs[n + 1]
    return row


def regions(canvas, grids, river):
    """Each land's shape over its box and MARGIN round it, as rows of runs (`encode`). `river`: the
    cells under the rivers (a bool array over the canvas)."""
    import numpy as np
    drawn = seas(canvas)
    found = {}
    for k, land_id in enumerate(canvas.ids):
        x, y, w, h = grids[land_id]
        rows = []
        for row in range(y - MARGIN, y + h + MARGIN):
            r = row - canvas.bottom
            codes = np.zeros(w + 2 * MARGIN, np.int32)
            c0 = x - MARGIN - canvas.left
            for i in range(w + 2 * MARGIN):
                c = c0 + i
                if 0 <= r < canvas.height and 0 <= c < canvas.width:
                    if canvas.owner[r, c] == k:
                        codes[i] = RIVER if river[r, c] else OWN
                    elif drawn[r, c] == k:
                        codes[i] = SEA
                    elif river[r, c]:
                        codes[i] = RIVER_AWAY
            rows.append(encode(codes))
        found[land_id] = rows
    return found


# MARK: Rivers

def _catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return tuple(0.5 * (2 * b + (-a + c) * t + (2 * a - 5 * b + 4 * c - d) * t2 + (-a + 3 * b - 3 * c + d) * t3)
                 for a, b, c, d in zip(p0, p1, p2, p3))


def river_line(river, number):
    """A river's middle from its spring to the sea, a point every quarter cell: (x, y, how wide it
    is there, how far along it is in cells). Through its `course` (world cells) on a smooth curve,
    meandering a little off it (`RIVER_WOBBLE`, not at its ends), widening from the first of its
    `width` to the second."""
    course = [tuple(map(float, p)) for p in river["course"]]
    points = []
    for n in range(len(course) - 1):
        p0, p1, p2, p3 = course[max(0, n - 1)], course[n], course[n + 1], course[min(len(course) - 1, n + 2)]
        steps = max(4, int(math.dist(p1, p2) * 4))
        for s in range(steps):
            points.append(_catmull(p0, p1, p2, p3, s / steps))
    points.append(course[-1])
    gone = [0.0]
    for a, b in zip(points, points[1:]):
        gone.append(gone[-1] + math.dist(a, b))
    total = max(gone[-1], 1e-9)
    narrow, wide = river.get("width", [3, 3])
    line = []
    for n, (x, y) in enumerate(points):
        a, b = points[max(0, n - 1)], points[min(len(points) - 1, n + 1)]
        tx, ty = b[0] - a[0], b[1] - a[1]
        length = math.hypot(tx, ty) or 1
        side = (-ty / length, tx / length)
        s = gone[n]
        ease = min(1.0, s / 12, (total - s) / 12)
        drift = sum((_value(s, number * 41.3, every, seed) * 2 - 1) * far for every, far, seed in RIVER_WOBBLE) * ease
        width = narrow + (wide - narrow) * s / total
        line.append((x + side[0] * drift, y + side[1] * drift, width, s))
    return line


def road_lines(land_id, land, middle, crossings, routes):
    """A land's roads (to each crossing, from its hub through `routes`' turns) and trails, as
    (what, [(x, y), ...]) in world cells: the lines rivers are bridged on."""
    mx, my = middle
    hub = land.get("hub") or [0, 0]
    found = []
    for to, (cx, cy) in sorted(crossings.items()):
        exit = next((e for e in land["exits"] if e["to"] == to), None)
        if exit is None:
            continue
        dx, dy = STEP[exit["edge"]]
        stops = [(mx + hub[0], my + hub[1])] + [(mx + a, my + b) for a, b in routes.get(to) or []]
        found.append((f"{land_id}'s road to {to}", stops + [(cx - dx * 5, cy - dy * 5), (cx, cy)]))
    for trail in land.get("trails") or []:
        stops = [trail.get("from") or hub] + (trail.get("via") or []) + [trail["to"]]
        found.append((f"{land_id}'s trail", [(mx + a, my + b) for a, b in stops]))
    return found


def along(stops):
    """Points every half cell along a line through `stops`."""
    samples = []
    for a, b in zip(stops, stops[1:]):
        n = max(2, int(math.dist(a, b) * 2))
        samples += [(a[0] + (b[0] - a[0]) * t / n, a[1] + (b[1] - a[1]) * t / n) for t in range(n)]
    return samples + [tuple(stops[-1])]


def bridged(lines, wet):
    """The cells a bridge covers where the lines cross water (`wet(x, y)`): each wet point's cell
    and the cells round it."""
    cells = set()
    for _, stops in lines:
        for x, y in along(stops):
            cx, cy = int(math.floor(x)), int(math.floor(y))
            if wet(cx, cy):
                cells.update((cx + i, cy + j) for i in (-1, 0, 1) for j in (-1, 0, 1))
    return cells


def rivers(canvas, world_rivers, design, lands, grids, found, routes):
    """The cells under the rivers (a bool array over the canvas, only land: not a town's), each
    river's middle as [x, y] a cell apart (for `world.json`), and problems: a river too near
    something it should keep clear of, a road crossing it badly (askew, where it's wide, near the
    sea or the road's ends) or running along it, land it cuts off with no road over."""
    import numpy as np
    from scipy import ndimage
    ids = canvas.ids
    index = {land_id: k for k, land_id in enumerate(ids)}
    under = np.zeros_like(canvas.owner, bool)
    lines, problems = [], []
    towns = np.isin(canvas.owner, [index[i] for i in ids if is_town(lands[i])])
    for number, river in enumerate(world_rivers):
        name = river.get("name", f"river {number}")
        line = river_line(river, number)
        x0, y0 = line[0][:2]
        x1, y1 = line[-1][:2]
        if canvas.get(int(math.floor(x0)), int(math.floor(y0))) < 0:
            problems.append(f"{name}'s spring isn't on land")
        if canvas.get(int(math.floor(x1)), int(math.floor(y1))) >= 0:
            problems.append(f"{name} doesn't run out into the sea")
        for x, y, width, s in line:
            radius = width / 2 + SPRING * max(0.0, 1 - s / 6)
            reach = int(radius) + 2
            cx, cy = int(math.floor(x)), int(math.floor(y))
            for j in range(cy - reach, cy + reach + 1):
                for i in range(cx - reach, cx + reach + 1):
                    if math.hypot(i + 0.5 - x, j + 0.5 - y) <= radius:
                        r, c = canvas.index(i, j)
                        if 0 <= r < canvas.height and 0 <= c < canvas.width:
                            under[r, c] = True
        lines.append({"name": name, "points": line})
    ground = canvas.owner >= 0
    if (under & towns).any():
        problems.append("a river runs into a town")
    under &= ground & ~towns
    near_town = ndimage.distance_transform_edt(~towns) <= RIVER_TOWN
    if (under & near_town).any():
        problems.append(f"a river runs within {RIVER_TOWN} cells of a town")
    # Clear of the roads' crossings, the middles and hubs, everything set down by hand and the caves.
    distance = ndimage.distance_transform_edt(~under)

    def clear(x, y, least, what):
        r, c = canvas.index(x, y)
        if 0 <= r < canvas.height and 0 <= c < canvas.width and distance[r, c] <= least:
            problems.append(f"a river runs within {least} cells of {what}")

    for land_id in ids:
        land = lands[land_id]
        mx, my = design[land_id]["at"]
        for to, (cx, cy) in found[land_id].items():
            clear(cx, cy, RIVER_CAVE if to not in lands else RIVER_CROSSING, f"{land_id}'s road to {to}'s crossing")
        if is_town(land):
            continue
        clear(mx, my, RIVER_MIDDLE, f"{land_id}'s middle")
        for (dx, dy), what in content_spots(land):
            clear(mx + dx, my + dy, RIVER_CONTENT + CONTENT_MARGIN if what != "hub" else RIVER_MIDDLE, f"{land_id}'s {what}")
    # Roads (and trails) over them: square across, narrow, inland, clear of their ends.
    sea_distance = ndimage.distance_transform_edt(ground)
    bridges = np.zeros_like(under)
    middles = [(p[0], p[1], p[2]) for river in lines for p in river["points"]]
    tree = np.array([(x, y) for x, y, _ in middles])

    def wet(x, y):
        r, c = canvas.index(x, y)
        return 0 <= r < canvas.height and 0 <= c < canvas.width and bool(under[r, c])

    for land_id in ids:
        land = lands[land_id]
        if is_town(land):
            continue
        roads_here = road_lines(land_id, land, design[land_id]["at"], found[land_id], routes[land_id])
        for x, y in bridged(roads_here, wet):
            r, c = canvas.index(x, y)
            bridges[r, c] = True
        for what, stops in roads_here:
            samples = along(stops)
            flags = [wet(int(math.floor(x)), int(math.floor(y))) for x, y in samples]
            # Each run of samples in the water is a crossing.
            runs, start = [], None
            for n, w in enumerate(flags + [False]):
                if w and start is None:
                    start = n
                elif not w and start is not None:
                    runs.append((start, n - 1))
                    start = None
            for first, last in runs:
                x, y = samples[(first + last) // 2]
                nearest = int(np.argmin(((tree - (x, y)) ** 2).sum(axis=1)))
                width = middles[nearest][2]
                ax, ay = middles[max(0, nearest - 8)][:2]
                bx, by = middles[min(len(middles) - 1, nearest + 8)][:2]
                px, py = samples[max(0, first - 4)]
                qx, qy = samples[min(len(samples) - 1, last + 4)]
                river_dir, road_dir = (bx - ax, by - ay), (qx - px, qy - py)
                cosine = abs(river_dir[0] * road_dir[0] + river_dir[1] * road_dir[1]) / (
                    (math.hypot(*river_dir) * math.hypot(*road_dir)) or 1)
                spot = f"{what} crosses a river at {[round(x), round(y)]}"
                if cosine > BRIDGE_SQUARE:
                    problems.append(f"{spot} askew")
                if width > BRIDGE_WIDEST:
                    problems.append(f"{spot} where it's {width:.1f} wide")
                r, c = canvas.index(int(x), int(y))
                if sea_distance[r, c] < BRIDGE_SEA:
                    problems.append(f"{spot} within {BRIDGE_SEA} cells of the sea")
                if math.dist((x, y), stops[0]) < BRIDGE_END or math.dist((x, y), stops[-1]) < BRIDGE_END:
                    problems.append(f"{spot} too near its ends")
            # Along it: nowhere but at its crossings within 2 cells of the water.
            for n, (x, y) in enumerate(samples):
                if any(first - 8 <= n <= last + 8 for first, last in runs):
                    continue
                r, c = canvas.index(int(math.floor(x)), int(math.floor(y)))
                if distance[r, c] <= 2.5:
                    problems.append(f"{what} runs along a river at {[round(x), round(y)]}")
                    break
    # Land it cuts off: small bits go under the water, the rest needs a road over.
    eight = np.ones((3, 3), bool)
    for land_id in ids:
        k = index[land_id]
        mine = canvas.owner == k
        if not (under & mine).any():
            continue
        dry = mine & (~under | bridges)
        labels, count = ndimage.label(dry, structure=eight)
        mx, my = design[land_id]["at"]
        hub = lands[land_id].get("hub") or [0, 0]
        r, c = canvas.index(mx + hub[0], my + hub[1])
        home = labels[r, c]
        sizes = ndimage.sum(np.ones_like(labels), labels, range(1, count + 1))
        for piece in range(1, count + 1):
            if piece == home:
                continue
            if sizes[piece - 1] < SLIVER:
                under |= labels == piece
            else:
                problems.append(f"a river cuts off {int(sizes[piece - 1])} cells of {land_id} with no road over")
    out = []
    for river in lines:
        points = river["points"]
        kept, last = [], None
        for x, y, _, s in points:
            if last is None or s - last >= 1 or (x, y) == points[-1][:2]:
                kept.append([round(x, 1), round(y, 1)])
                last = s
        out.append(kept)
    return under, out, sorted(set(problems))


def content_spots(land):
    """Everything set down by hand on a land, as [x, y] out from its middle, with what it is."""
    spots = []
    for kind in ("buildings", "decor", "npcs"):
        for thing in land.get(kind) or []:
            if "x" in thing and thing.get("summit") is None:
                spots.append(((thing["x"], thing.get("y", 0)), f"{kind[:-1]} {thing.get('id', thing.get('art', ''))}"))
    for local in land.get("locals") or []:
        if not local.get("at") and local.get("summit") is None:
            spots.append(((local.get("x", 0), local.get("y", 0)), f"local {local.get('name')}"))
    for trail in land.get("trails") or []:
        for point in [trail.get("from"), trail.get("to")] + (trail.get("via") or []):
            if point:
                spots.append((tuple(point), "trail"))
    if land.get("hub"):
        spots.append((tuple(land["hub"]), "hub"))
    return spots


def ways(canvas, design, lands, grids, found):
    """Each road's way from its hub (maps.json `hub`, else the middle) to where it crosses, through
    the middle of its land, as waypoints out from the land's middle (maps.json's `via`): the
    cheapest way where a step costs more the nearer the coast or the border it is, cut down to the
    turns. A town's roads run straight from its square."""
    import heapq
    import numpy as np
    from scipy import ndimage
    found_ways, problems = {}, []
    for k, land_id in enumerate(canvas.ids):
        land = lands[land_id]
        found_ways[land_id] = {}
        if is_town(land):
            continue
        x0, y0, w, h = grids[land_id]
        r0, c0 = canvas.index(x0, y0)
        mine = canvas.owner[r0:r0 + h, c0:c0 + w] == k
        depth = ndimage.distance_transform_edt(np.pad(mine, 1))[1:-1, 1:-1]
        mx, my = design[land_id]["at"][0] - x0, design[land_id]["at"][1] - y0
        hub = land.get("hub") or [0, 0]
        start = (mx + hub[0], my + hub[1])
        for to, (cx, cy) in found[land_id].items():
            exit = next(e for e in land["exits"] if e["to"] == to)
            dx, dy = STEP[exit["edge"]]
            goal = (cx - x0 - dx * 5, cy - y0 - dy * 5)
            if not (0 <= goal[0] < w and 0 <= goal[1] < h and mine[goal[1], goal[0]] and mine[start[1], start[0]]):
                problems.append(f"{land_id}'s road to {to} has nowhere to start or end on its land")
                continue
            # Dijkstra over the land's cells, 8 ways.
            best = {start: 0.0}
            back = {}
            queue = [(0.0, start)]
            while queue:
                cost, cell = heapq.heappop(queue)
                if cell == goal:
                    break
                if cost > best[cell]:
                    continue
                for ox in (-1, 0, 1):
                    for oy in (-1, 0, 1):
                        if not ox and not oy:
                            continue
                        nx, ny = cell[0] + ox, cell[1] + oy
                        if not (0 <= nx < w and 0 <= ny < h) or not mine[ny, nx]:
                            continue
                        step = (1.4142 if ox and oy else 1.0) * (1 + 8 / max(1.0, depth[ny, nx]))
                        if cost + step < best.get((nx, ny), float("inf")):
                            best[(nx, ny)] = cost + step
                            back[(nx, ny)] = cell
                            heapq.heappush(queue, (cost + step, (nx, ny)))
            if goal not in back and goal != start:
                problems.append(f"{land_id}'s road to {to} can't reach its border")
                continue
            path = [goal]
            while path[-1] != start:
                path.append(back[path[-1]])
            path.reverse()

            def clear(a, b, least):
                n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
                for t in range(n + 1):
                    px = round(a[0] + (b[0] - a[0]) * t / n)
                    py = round(a[1] + (b[1] - a[1]) * t / n)
                    if depth[py, px] < least:
                        return False
                return True

            # Cut down to the turns: from each waypoint, straight on as far as the way stays as deep
            # in the land (up to 6 cells) as the path itself did.
            via, i = [], 0
            while i < len(path) - 1:
                j = len(path) - 1
                while j > i + 1:
                    least = min(6.0, min(depth[py, px] for px, py in path[i:j + 1]))
                    if clear(path[i], path[j], least) and j - i <= 60:
                        break
                    j -= 1
                if j < len(path) - 1:
                    via.append(path[j])
                i = j
            # The last stretch to the border is the game's (`WorldMap.carveRoad`).
            via = [v for v in via if max(abs(v[0] - goal[0]), abs(v[1] - goal[1])) > 6]
            found_ways[land_id][to] = [[px - mx, py - my] for px, py in via]
    return found_ways, problems


def write(data, lands, design, grids, roads, routes, shapes, lines):
    for land_id, (x, y, w, h) in grids.items():
        lands[land_id]["width"], lands[land_id]["height"] = w, h
    MAPS.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    old = json.loads(WORLD.read_text())
    about = old.get("_about", "")
    order = sorted(grids, key=lambda i: (-grids[i][1], grids[i][0]))
    out = ["{", f'  "_about": {json.dumps(about, ensure_ascii=False)},', f'  "margin": {MARGIN},', '  "design": {']
    out.append(",\n".join(f'    {json.dumps(i)}: {json.dumps(design[i])}' for i in sorted(design)))
    out += ["  },", '  "lands": {']
    out.append(",\n".join(f'    "{i}": [{grids[i][0]}, {grids[i][1]}]' for i in order))
    out += ["  },", '  "middles": {']
    out.append(",\n".join(f'    "{i}": [{design[i]["at"][0] - grids[i][0]}, {design[i]["at"][1] - grids[i][1]}]' for i in order))
    out += ["  },", '  "roads": {']
    blocks = []
    for i in order:
        entries = []
        for to, cell in sorted(roads[i].items()):
            road = {"at": list(cell)}
            if routes.get(i, {}).get(to):
                road["via"] = routes[i][to]
            entries.append(f'      {json.dumps(to)}: {json.dumps(road, separators=(", ", ": "))}')
        blocks.append(f'    "{i}": {{\n' + ",\n".join(entries) + "\n    }")
    out.append(",\n".join(blocks))
    out += ["  },", '  "rivers": [']
    blocks = []
    for river, line in zip(old.get("rivers", []), lines):
        spec = {key: river[key] for key in ("name", "width", "course")}
        text = json.dumps(spec, separators=(", ", ": "))[:-1]
        blocks.append(f"    {text},\n      \"line\": {json.dumps(line, separators=(',', ':'))}}}")
    out.append(",\n".join(blocks))
    out += ["  ],", '  "regions": {']
    blocks = []
    for i in order:
        rows = ",\n".join("      " + json.dumps(row, separators=(",", ":")) for row in shapes[i])
        blocks.append(f'    "{i}": [\n{rows}\n    ]')
    out.append(",\n".join(blocks))
    out += ["  }", "}"]
    WORLD.write_text("\n".join(out) + "\n")


def solve(data, maps, lands, design, world_rivers):
    import numpy as np
    canvas = paint(design, lands)
    keep = np.zeros_like(canvas.owner, bool)
    towns = set()
    for k, land_id in enumerate(canvas.ids):
        if is_town(lands[land_id]):
            keep |= canvas.owner == k
            towns.add(k)
    tidy(canvas, keep, towns)
    found, problems = crossings(canvas, design, lands, maps, keep)
    tidy(canvas, keep, towns)
    grids = boxes(canvas, design, lands)
    routes, more = ways(canvas, design, lands, grids, found)
    river, lines, wet = rivers(canvas, world_rivers, design, lands, grids, found, routes)
    # Roads in each land's own cells.
    roads = {i: {to: (x - grids[i][0], y - grids[i][1]) for to, (x, y) in found[i].items()} for i in found}
    return canvas, grids, roads, routes, regions(canvas, grids, river), lines, problems + more + wet


# MARK: Checking (no numpy: check_content.py runs it)

def unpack(world, lands):
    """Each land's shape from world.json: its own world cells, the sea it draws, its own cells under
    a river and other lands' under a river round it, as sets."""
    margin = world.get("margin", MARGIN)
    own, sea, wet, away = {}, {}, {}, {}
    for land_id, rows in world.get("regions", {}).items():
        if land_id not in lands or land_id not in world.get("lands", {}):
            continue
        x0, y0 = world["lands"][land_id]
        sets = {OWN: set(), SEA: set(), RIVER: set(), RIVER_AWAY: set()}
        for n, runs in enumerate(rows):
            col = 0
            for k in range(0, len(runs), 2):
                code, length = runs[k], runs[k + 1]
                if code in sets:
                    for i in range(col, col + length):
                        sets[code].add((x0 - margin + i, y0 - margin + n))
                col += length
        own[land_id] = sets[OWN] | sets[RIVER]
        sea[land_id], wet[land_id], away[land_id] = sets[SEA], sets[RIVER], sets[RIVER_AWAY]
    return own, sea, wet, away


def verify(maps, lands, world):
    """Problems with world.json against maps.json, as messages (the checker shares this)."""
    problems = []
    origins = world.get("lands", {})
    if world.get("margin") != MARGIN:
        return [f"world.json: margin should be {MARGIN}"]
    margin = MARGIN
    for land_id in lands:
        for key in ("design", "lands", "middles", "roads", "regions"):
            if land_id not in world.get(key, {}):
                problems.append(f"world.json: {land_id} has nothing in {key}")
    for land_id in origins:
        if land_id not in lands:
            problems.append(f"world.json: {land_id} isn't an outdoor map")
    if problems:
        return problems
    own, sea, wet, away = unpack(world, lands)
    owner = {}
    for land_id, cells in sorted(own.items()):
        land = lands[land_id]
        x0, y0 = origins[land_id]
        w, h = land["width"], land["height"]
        rows = world["regions"][land_id]
        if len(rows) != h + 2 * margin or any(sum(r[1::2]) != w + 2 * margin for r in rows):
            problems.append(f"world.json: {land_id}'s shape isn't the size of its map and the margin round it")
            continue
        if any((x, y) for x, y in cells if not (x0 <= x < x0 + w and y0 <= y < y0 + h)):
            problems.append(f"world.json: {land_id}'s land reaches past its map")
        for cell in cells:
            if cell in owner:
                problems.append(f"world.json: {land_id} and {owner[cell]} both claim the cell {list(cell)}")
                break
            owner[cell] = land_id
        if is_town(land):
            if len(cells) != w * h:
                problems.append(f"world.json: town {land_id} isn't its whole rectangle")
            if world["middles"][land_id] != [w // 2, h // 2]:
                problems.append(f"world.json: town {land_id}'s middle isn't its square's")
        mc, mr = world["middles"][land_id]
        middle = (x0 + mc, y0 + mr)
        if middle not in cells:
            problems.append(f"world.json: {land_id}'s middle isn't on its land")
        for (dx, dy), what in content_spots(land):
            spot = (middle[0] + dx, middle[1] + dy)
            near = all((spot[0] + i, spot[1] + j) in cells
                       for i in range(-CONTENT_MARGIN, CONTENT_MARGIN + 1) for j in range(-CONTENT_MARGIN, CONTENT_MARGIN + 1))
            if not near:
                problems.append(f"world.json: {land_id}'s {what} at {[dx, dy]} is off its land (or within "
                                f"{CONTENT_MARGIN} cells of its edge)")
    for land_id, water in sea.items():
        for cell in water:
            if cell in owner:
                problems.append(f"world.json: {land_id} draws sea over {owner[cell]}'s land at {list(cell)}")
                break
    # Roads: each crosses where the other land's road does, both on their own land, the way the
    # exits say; and the road's way from its hub stays on the land.
    for land_id, land in sorted(lands.items()):
        x0, y0 = origins[land_id]
        mc, mr = world["middles"][land_id]
        middle = (x0 + mc, y0 + mr)
        roads = world["roads"].get(land_id, {})
        for exit in land["exits"]:
            if exit["to"] not in maps:
                continue
            road = roads.get(exit["to"])
            if not road:
                problems.append(f"world.json: {land_id} has no crossing for its road to {exit['to']}")
                continue
            here = (x0 + road["at"][0], y0 + road["at"][1])
            if here not in own.get(land_id, ()):
                problems.append(f"world.json: {land_id}'s road to {exit['to']} crosses off its land")
            dx, dy = STEP[exit["edge"]]
            over = (here[0] + dx, here[1] + dy)
            if exit["to"] in lands:
                back = world["roads"].get(exit["to"], {}).get(land_id)
                ox, oy = origins[exit["to"]]
                if not back or (ox + back["at"][0], oy + back["at"][1]) != over:
                    problems.append(f"world.json: the road from {land_id} {exit['edge']} doesn't meet {exit['to']}'s")
                if owner.get(over) != exit["to"]:
                    problems.append(f"world.json: past {land_id}'s road {exit['edge']} isn't {exit['to']}")
            elif over in owner:
                problems.append(f"world.json: past {land_id}'s road into the cave {exit['to']} is land")
            if is_town(land):
                continue
            hub = land.get("hub") or [0, 0]
            stops = [hub] + road.get("via", [])
            points = [(middle[0] + x, middle[1] + y) for x, y in stops] + [(here[0] - dx * 5, here[1] - dy * 5)]
            for start, end in zip(points, points[1:]):
                steps = max(abs(end[0] - start[0]), abs(end[1] - start[1]), 1)
                off = False
                for n in range(steps + 1):
                    px = round(start[0] + (end[0] - start[0]) * n / steps)
                    py = round(start[1] + (end[1] - start[1]) * n / steps)
                    if not all((px + i, py + j) in own.get(land_id, ())
                               for i in range(-ROAD_MARGIN, ROAD_MARGIN + 1) for j in range(-ROAD_MARGIN, ROAD_MARGIN + 1)):
                        off = True
                        break
                if off:
                    problems.append(f"world.json: {land_id}'s road to {exit['to']} runs within {ROAD_MARGIN} cells of "
                                    "its land's edge on the way")
                    break
    problems += verify_rivers(lands, world, own, wet, away)
    return problems


def bridged_lands(lands, world):
    """The lands where a road or trail crosses a river (and so has a bridge)."""
    if not world.get("regions"):
        return set()
    own, _, wet, _ = unpack(world, lands)
    water = set().union(*wet.values()) if wet else set()
    found = set()
    for land_id, land in lands.items():
        if land_id not in world.get("lands", {}) or not wet.get(land_id):
            continue
        x0, y0 = world["lands"][land_id]
        mc, mr = world["middles"][land_id]
        roads = world["roads"].get(land_id, {})
        crossings = {to: (x0 + r["at"][0], y0 + r["at"][1]) for to, r in roads.items()}
        lines = road_lines(land_id, land, (x0 + mc, y0 + mr), crossings, {to: r.get("via") for to, r in roads.items()})
        if bridged(lines, lambda x, y: (x, y) in water) & own[land_id]:
            found.add(land_id)
    return found


def verify_rivers(lands, world, own, wet, away):
    """Problems with the rivers: each with its middle drawn, the same cells under them from either
    side of a border, none in a town, clear of the roads' crossings, the middles and everything set
    down by hand, and nothing of a land cut off from its hub with no road over."""
    problems = []
    origins = world["lands"]
    for number, river in enumerate(world.get("rivers", [])):
        if len(river.get("line") or []) < 2:
            problems.append(f"world.json: river {river.get('name', number)} has no line drawn (run tools/world_layout.py)")
    water = set().union(*wet.values()) if wet else set()
    owner = {cell: land_id for land_id, cells in own.items() for cell in cells}
    for land_id, land in sorted(lands.items()):
        x0, y0 = origins[land_id]
        w, h = land["width"], land["height"]
        seen = {cell for cell in water if x0 - MARGIN <= cell[0] < x0 + w + MARGIN
                and y0 - MARGIN <= cell[1] < y0 + h + MARGIN and owner.get(cell) not in (None, land_id)}
        if seen != away[land_id]:
            problems.append(f"world.json: {land_id}'s shape doesn't show the rivers round it as the lands they run through do")
        if is_town(land) and wet[land_id]:
            problems.append(f"world.json: a river runs through the town {land_id}")
        mc, mr = world["middles"][land_id]
        middle = (x0 + mc, y0 + mr)

        def near(spot, reach):
            return any((spot[0] + i, spot[1] + j) in water for i in range(-reach, reach + 1) for j in range(-reach, reach + 1))

        for to, road in world["roads"].get(land_id, {}).items():
            reach = RIVER_CROSSING if to in lands else RIVER_CAVE
            if near((x0 + road["at"][0], y0 + road["at"][1]), reach):
                problems.append(f"world.json: a river runs within {reach} cells of where {land_id}'s road to {to} crosses")
        if is_town(land):
            continue
        if near(middle, RIVER_MIDDLE):
            problems.append(f"world.json: a river runs within {RIVER_MIDDLE} cells of {land_id}'s middle")
        for (dx, dy), what in content_spots(land):
            reach = RIVER_MIDDLE if what == "hub" else RIVER_CONTENT + CONTENT_MARGIN
            if near((middle[0] + dx, middle[1] + dy), reach):
                problems.append(f"world.json: a river runs within {reach} cells of {land_id}'s {what} at {[dx, dy]}")
        if not wet[land_id]:
            continue
        crossings = {to: (x0 + r["at"][0], y0 + r["at"][1]) for to, r in world["roads"].get(land_id, {}).items()}
        routes = {to: r.get("via") for to, r in world["roads"].get(land_id, {}).items()}
        lines = road_lines(land_id, land, middle, crossings, routes)
        dry = (own[land_id] - wet[land_id]) | (bridged(lines, lambda x, y: (x, y) in water) & own[land_id])
        hub = land.get("hub") or [0, 0]
        start = (middle[0] + hub[0], middle[1] + hub[1])
        reached, queue = {start}, [start]
        while queue:
            x, y = queue.pop()
            for i in (-1, 0, 1):
                for j in (-1, 0, 1):
                    cell = (x + i, y + j)
                    if cell in dry and cell not in reached:
                        reached.add(cell)
                        queue.append(cell)
        if len(dry - reached):
            problems.append(f"world.json: a river cuts off {len(dry - reached)} cells of {land_id} from its hub")
    return problems




# MARK: Preview

COLOURS = {"tile_grass": (120, 190, 90), "tile_sand": (230, 210, 150), "tile_dark_grass": (70, 120, 70),
           "tile_forest_floor": (90, 130, 60), "tile_snow": (235, 240, 250), "tile_swamp": (100, 120, 80),
           "tile_desert": (220, 190, 120), "tile_scree": (150, 150, 160)}


def preview(lands, world, path, names=None):
    from PIL import Image, ImageDraw
    own, _, wet, _ = unpack(world, lands)
    origins = world["lands"]
    xs = [x for cells in own.values() for x, _ in cells]
    ys = [y for cells in own.values() for _, y in cells]
    left, right, bottom, top = min(xs) - 30, max(xs) + 30, min(ys) - 30, max(ys) + 30
    width, height = right - left, top - bottom
    image = Image.new("RGB", (width, height), (59, 127, 192))
    pixels = image.load()
    owner = {}
    for land_id, cells in own.items():
        colour = COLOURS.get(lands[land_id]["theme"]["ground"], (200, 200, 200))
        if is_town(lands[land_id]):
            colour = (196, 160, 120)
        for x, y in cells:
            owner[(x, y)] = land_id
            pixels[x - left, top - 1 - y] = colour
    # Borders between lands, dark; the rivers.
    for (x, y), land_id in owner.items():
        for dx, dy in ((1, 0), (0, 1)):
            other = owner.get((x + dx, y + dy))
            if other and other != land_id:
                pixels[x - left, top - 1 - y] = (40, 40, 40)
    for cells in wet.values():
        for x, y in cells:
            pixels[x - left, top - 1 - y] = (70, 150, 215)
    scale = 2
    image = image.resize((width * scale, height * scale), Image.NEAREST)
    draw = ImageDraw.Draw(image)
    for land_id, cells in own.items():
        land = lands[land_id]
        x0, y0 = origins[land_id]
        mx, my = x0 + world["middles"][land_id][0], y0 + world["middles"][land_id][1]
        # Its roads, as the game lays them out roughly.
        roads = world["roads"].get(land_id, {})
        crossings = {to: (x0 + r["at"][0], y0 + r["at"][1]) for to, r in roads.items()}
        for _, stops in road_lines(land_id, land, (mx, my), crossings, {to: r.get("via") for to, r in roads.items()}):
            draw.line([((x - left) * scale, (top - y) * scale) for x, y in stops], fill=(140, 100, 60), width=2)
        label = (names or {}).get(land_id, land_id)
        draw.text(((mx - left) * scale - 3 * len(label), (top - my) * scale - 6), label, fill=(0, 0, 0))
        for to, road in world["roads"].get(land_id, {}).items():
            cx, cy = road["at"]
            px, py = (x0 + cx - left) * scale, (top - 1 - (y0 + cy)) * scale
            colour = (200, 40, 30) if to in lands else (30, 30, 30)
            draw.rectangle([px - 3, py - 3, px + 3, py + 3], fill=colour)
    image.save(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="only check world.json against maps.json")
    parser.add_argument("--preview", metavar="PNG", help="draw the continent")
    args = parser.parse_args()
    data, maps, lands = load_maps()
    world = json.loads(WORLD.read_text())
    if not args.check:
        canvas, grids, roads, routes, shapes, lines, problems = solve(data, maps, lands, world["design"], world.get("rivers", []))
        for problem in problems:
            print("  " + problem)
        write(data, lands, world["design"], grids, roads, routes, shapes, lines)
        data, maps, lands = load_maps()
        world = json.loads(WORLD.read_text())
    problems = verify(maps, lands, world)
    print("\n".join(problems) or "world.json fits maps.json")
    if args.preview:
        preview(lands, world, args.preview, {i: m["name"] for i, m in lands.items()})
        print(f"preview: {args.preview}")
    sys.exit(1 if problems else 0)


if __name__ == "__main__":
    main()
