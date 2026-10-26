#!/usr/bin/env python3
"""Paints the lands as one continent (content/world.json): each land a shape of its own, as
RuneScape's regions are, not a rectangle.

The design (world.json `design`) gives each land its middle on the continent (`at`, in world cells,
x east and y north) and one or more lobes round it: ellipses `[dx, dy, across, up, turn°]` out
from its middle. The continent is one landmass: the lands' lobes, blurred together and cut again a
little raggedly (`BODY_BLUR`), so there's no sea inland and no notch where two lands meet, one coast
running on past the borders. Every cell of it goes to the land whose lobes reach it most easily (its
distance over their size), the lands pushing against each other where they meet. The lobes are
scaled so each land comes out as many cells as its `area` (about as big as its map was), and the
whole continent is bent by smooth noise first (`WARPS`), so coasts and borders wander. A town's
walled square (maps.json `town.size`) is its own exactly, with its own countryside right round it
(`TOWN_OWN`) and land of some kind beyond (`TOWN_RING`), never the sea; its roads leave through
the gates in its wall (`gate`) and cross the fields to its border as any land's do.

Then it's tidied: stray cells and slivers go to the land round them, a land in more than one piece
keeps its biggest, pools inland fill in. Where a road crosses from one land into the next, the
border runs straight for a stretch (`CROSSING`), across the way the exit goes, so the road meets
itself and a quest's gate fits. A road into a cave ends inland, at a rocky hill with the cave's mouth
in its face (`cave_gates`): out from the hub toward the side the exit names, its face turned toward
you, so you walk north or east into it, clear of the coast, the rivers, the other roads and
everything set down by hand. A road to a land over the sea (maps.json `ship`) ends at a harbor
(`harbors`): on the coast the exit's side faces, with open sea straight out from it for the pier
and the ship moored at its end (`WorldMap.harbor`), nearest the land it sails to.

Rivers (world.json `rivers`) run from a spring to the sea through the turns of their `course`,
meandering a little (`RIVER_WOBBLE`) and widening as they go, some from one land on into the next;
one with a `lake` ends in a lake of its own that wide instead, where it has no way to the sea.
They keep clear of towns, the roads' crossings, the middles and everything set down by hand; a road
or trail crossing one gets a bridge in the game, so it has to cross squarely, where the river's
narrow and away from the sea, and the river runs straight along a row or a column there (the game
lays its bridges along the other); and bits of land a river cuts off with no road over go under water if
they're small (`SLIVER`), else it's a problem to fix in the course.

Each land's map is the box round its shape, its middle at the land's middle (maps.json `width`
and `height`, which this writes). world.json gets, per land, the cell its box starts on (`lands`),
where each road crosses its border (`roads`, in its own cells: the last cell on its side, the next
one over the edge the exit names being the other land's; for a road into a cave, the cell in front of
its mouth, and `into`, the way you walk into it; for a harbor, the last cell of the coast, and
`pier`, the way its pier runs out to sea), each river's middle (`line`), and its
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
# The whole continent's outline: the lands' shapes blurred together this much (cells) and cut at
# `BODY_CUT`, a little raggedly ((every, share, seed)), so it's one landmass with one coast that runs
# on past the borders, not a coast of each land's own.
BODY_BLUR = 24.0
BODY_CUT = 0.3
BODY_WOBBLE = ((60, 0.10, 0xB01), (22, 0.06, 0xB02), (8, 0.025, 0xB03))
# How far round its walls a town's own countryside reaches at least (no other land's nearer), and
# land of some kind (never the sea); and how far out from its gate a town's road runs straight
# before it turns for the border.
TOWN_OWN = 8
TOWN_RING = 16
TOWN_GATE = 5
# How far round each land's middle the painting looks, in cells.
EXTENT = 170
CROSSING = 8
CROSSING_DEEP = 9
# Where a road leads into a cave (`cave_gates`, playtesting 2026-10-16: not at the edge of the map,
# where its mountains stood out in the sea, but inland, a gate to the cave): how far out from the hub
# toward the exit's side its mouth may be (cells along that way), how long a way there is best, how
# far in front of the mouth the road runs straight at it, and the hill's room round it (from the
# mouth's foot: how far in its middle is, and its reach along the face and into it), its main
# summit's top (the same; `WorldMap.raiseGate` raises them, the main summit's foot out over the
# hill's room since 0.7.13, narrower across where a road sways close, `WorldMap.gateAcross`), and
# how far each keeps from the coast or a land next door, the rivers, the other roads (the game sways
# them up to 6 cells) and everything set down by hand.
GATE_OUT = (16, 70)
GATE_IDEAL = 34
GATE_APPROACH = 7
GATE_ROOM = (7, 12, 11)
GATE_SUMMIT = (6, 7, 8)
GATE_COAST = (4, 8)
GATE_RIVER = (3, 6)
GATE_ROAD = (3, 8)
GATE_PEOPLE = (3, 5)
# A harbor (`harbors`): how far straight out from its dock the sea must be open, and how far to
# either side of the road (the pier's three lanes and the ship moored up the screen from it,
# `Region.Road.pierLength`, `WorldMap.harbor`), and how far straight back the land must be its own,
# for the road's last stretch (`ROAD_MARGIN` round it).
HARBOR_SEA = 14
HARBOR_ACROSS = (-3, 6)
HARBOR_BACK = 9
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
# anything set down by hand and from a town, in cells; and how far a road into a cave keeps from one
# all the way (no bridge on it: the game sways it up to 6 cells off its line).
RIVER_CROSSING = 10
RIVER_MIDDLE = 8
RIVER_CONTENT = 4
RIVER_TOWN = 5
RIVER_GATE_ROAD = 8
# Where a road crosses a river (a bridge, `WorldMap.bridge(over:along:)`): at least this square on
# (the cosine of the angle between them, at most), no wider than this, and this far from the sea
# (whose shore slopes down to it), the road's border crossing and its hub.
# The river runs square to its bridge (`SQUARE_REACH`), and the game sways its roads and bends them to
# meet the bridge (`WorldMap.meetRoad`), so the road need only come in at a good slant across it.
BRIDGE_SQUARE = 0.8
# The game lays a bridge along a column or a row, whichever crosses the river more squarely, so the
# river has to run along the other there, at most this many degrees off it (over 4 cells either way,
# as the game measures it): where it ran aslant, its bridge crossed it askew (playtesting 2026-10-25,
# Frog Swamp's road to Sunny Meadow, 33 degrees off).
BRIDGE_AXIS = 12
# So it does: where a road crosses a river, the river runs straight along a row or a column (the one
# nearer its own way there) this many cells either way, easing back into its course over as many again;
# room for the game's road to sway (`WorldMap.carve`, up to 6 cells) and still cross where it's straight.
SQUARE_REACH = 8
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


# MARK: Noise (the same hash as TalesOfDorlune/World/Coast.swift's)

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


def gate(land, box, exit):
    """Where a town's road leaves through its wall (`exit`'s side, its middle and `at` along it):
    the wall's cell, in world cells."""
    x, y, w, h = box
    at = exit.get("at", 0)
    return {"east": (x + w - 1, y + h // 2 + at), "west": (x, y + h // 2 + at),
            "north": (x + w // 2 + at, y + h - 1), "south": (x + w // 2 + at, y)}[exit["edge"]]


def town_box(land, at):
    """A town's walled square (maps.json `town.size`): (left, bottom, width, height) in world cells,
    its middle cell at `at` as the town's middle is (`WorldMap.walls`: width / 2, height / 2 in)."""
    w, h = land["town"]["size"]
    return at[0] - w // 2, at[1] - h // 2, w, h


def lobes(design, lands):
    """Every land's lobes on the continent: (x, y, across, up, turn in radians), its own and one
    toward each land a road joins it to, so the two always meet (most of the way along the line
    between their middles). A town's are its countryside round its walls."""
    found = {i: [] for i in design}
    for land_id, spec in design.items():
        cx, cy = spec["at"]
        for lobe in spec["lobes"]:
            found[land_id].append((cx + lobe[0], cy + lobe[1], lobe[2], lobe[3], math.radians(lobe[4]) if len(lobe) > 4 else 0.0))
    for land_id, exit in road_pairs(lands):
        other = exit["to"]
        for here, there in ((land_id, other), (other, land_id)):
            hx, hy = design[here]["at"]
            tx, ty = design[there]["at"]
            length = math.hypot(tx - hx, ty - hy)
            found[here].append((hx + (tx - hx) * 0.4, hy + (ty - hy) * 0.4, length * 0.32, length * 0.32, 0.0))
    return found


def reach(shapes, ids, xs, ys, scales):
    """How easily each land's lobes reach every cell: its distance over their size (below 1
    inside them), for the cells at world (xs, ys), already bent."""
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
    """The continent, painted, before it's tidied: one landmass (`BODY_BLUR`), each cell of it the
    land that reaches it most easily, a town's walled square its own, with its countryside round."""
    import numpy as np
    from scipy import ndimage
    ids = sorted(design)
    left = bottom = 10 ** 9
    right = top = -10 ** 9
    for land_id in ids:
        cx, cy = design[land_id]["at"]
        left, right = min(left, cx - EXTENT), max(right, cx + EXTENT)
        bottom, top = min(bottom, cy - EXTENT), max(top, cy + EXTENT)
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
    ragged = np.zeros_like(xs)
    for every, far, seed in BODY_WOBBLE:
        ragged += (_value_np(xs, ys, every, seed) * 2 - 1) * far
    # The towns' walled squares, and the countryside every town has round them.
    cores = np.zeros(xs.shape, bool)
    for land_id in ids:
        if is_town(lands[land_id]):
            x, y, w, h = town_box(lands[land_id], design[land_id]["at"])
            r, c = canvas.index(x, y)
            cores[r:r + h, c:c + w] = True
    countryside = ndimage.distance_transform_edt(~cores) <= TOWN_RING
    # Each town's square and its own countryside right round it.
    owned = {}
    for land_id in ids:
        if is_town(lands[land_id]):
            x, y, w, h = town_box(lands[land_id], design[land_id]["at"])
            r, c = canvas.index(x, y)
            square = np.zeros(xs.shape, bool)
            square[r:r + h, c:c + w] = True
            owned[land_id] = ndimage.distance_transform_cdt(~square, metric="chessboard") <= TOWN_OWN
    targets = {i: design[i].get("area", 0) for i in ids}
    scales = {i: 1.0 for i in ids}
    shapes = lobes(design, lands)
    for _ in range(10):
        near = reach(shapes, ids, bent_x, bent_y, scales)
        best = near.argmin(axis=0)
        least = near.min(axis=0)
        # One landmass: the lands' shapes blurred together and cut again a little raggedly, so the
        # gaps and notches where two lands meet fill in and the coast runs on past every border,
        # no sea inland.
        inside = (least < 1 + wobble).astype(np.float64)
        body = ndimage.gaussian_filter(inside, BODY_BLUR) > BODY_CUT + ragged
        body = ndimage.binary_fill_holes(body | countryside)
        owner = np.where(body, best, -1).astype(np.int32)
        for k, land_id in enumerate(ids):
            if is_town(lands[land_id]):
                owner[owned[land_id]] = k
        areas = np.bincount(owner[owner >= 0].ravel(), minlength=len(ids))
        for k, land_id in enumerate(ids):
            if areas[k]:
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
            if exit["to"] in lands and (land_id < exit["to"]) and not exit.get("ship"):
                pairs.append((land_id, exit))
    return pairs


def ship_exits(lands):
    """Every road that ends at a harbor, a ship sailing on to another land (maps.json `ship`), from
    each side: (land, its exit)."""
    return [(land_id, exit) for land_id in sorted(lands) for exit in lands[land_id]["exits"] if exit.get("ship")]


def cave_exits(maps, lands):
    return [(land_id, exit) for land_id in sorted(lands) for exit in lands[land_id]["exits"]
            if exit["to"] not in lands and exit["to"] in maps]


def harbor_side(edge):
    """The side of a harbor's pier its ship is moored on, across it (as `straighten`'s `side`, +1 or
    -1): the one up the screen, north or east, so the ship lies behind the pier and you on it."""
    dx, dy = STEP[edge]
    side = (-dy, dx)
    return 1 if side[0] + side[1] > 0 else -1


def harbors(canvas, design, lands, keep, world_rivers):
    """Where each road to a land over the sea ends (maps.json `ship`): at a harbor on the coast its
    exit's side faces, the last cell of the land, the sea open straight out from it for the pier and
    the ship (`HARBOR_SEA`, `HARBOR_ACROSS`), the land straight behind it its own (`HARBOR_BACK`),
    clear of the rivers and the towns' kept ground, nearest the land it sails to. As
    {land: {to: (x, y)}} in world cells, and problems."""
    import numpy as np
    from scipy import ndimage
    ids = canvas.ids
    index = {land_id: k for k, land_id in enumerate(ids)}
    found = {land_id: {} for land_id in ids}
    problems = []
    springs = [(x, y, w) for n, river in enumerate(world_rivers) for x, y, w, _ in river_line(river, n)]
    for land_id, exit in ship_exits(lands):
        other = exit["to"]
        if other not in index:
            problems.append(f"{land_id}'s ship sails to {other}, which isn't a land")
            continue
        k = index[land_id]
        dx, dy = STEP[exit["edge"]]
        sx, sy = -dy * harbor_side(exit["edge"]), dx * harbor_side(exit["edge"])
        mine = canvas.owner == k
        depth = ndimage.distance_transform_edt(np.pad(mine, 1))[1:-1, 1:-1]
        r, c = np.nonzero(mine)
        tx, ty = design[other]["at"]
        hx, hy = design[land_id]["at"]
        hub = lands[land_id].get("hub") or [0, 0]
        hx, hy = hx + hub[0], hy + hub[1]
        best = None
        for row, col in zip(r, c):
            x, y = int(col) + canvas.left, int(row) + canvas.bottom
            if canvas.get(x + dx, y + dy) != -1:
                continue
            # The sea out in front, for the pier and the ship beside it.
            if any(canvas.get(x + dx * a + sx * b, y + dy * a + sy * b) != -1
                   for a in range(1, HARBOR_SEA + 1) for b in range(HARBOR_ACROSS[0], HARBOR_ACROSS[1] + 1)):
                continue
            # The land behind, the road's last stretch on it with room round it.
            back = [(x - dx * a + sx * b, y - dy * a + sy * b) for a in range(0, HARBOR_BACK + 1)
                    for b in range(-ROAD_MARGIN, ROAD_MARGIN + 1) if a >= 2 or abs(b) <= 1]
            if any(canvas.get(px, py) != k or keep[canvas.index(px, py)] for px, py in back):
                continue
            if any(math.hypot(px - x, py - y) < RIVER_CROSSING + w / 2 + 2 for px, py, w in springs):
                continue
            score = math.hypot(tx - x, ty - y) + 0.3 * math.hypot(hx - x, hy - y)
            if best is None or score < best[0]:
                best = (score, (x, y))
        if best is None:
            problems.append(f"{land_id} has nowhere on its {exit['edge']} coast for a harbor (its ship to {other})")
            continue
        found[land_id][other] = best[1]
    return found, problems


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
    """Where every road between two lands crosses its border, as {land: {to: (x, y)}} in world cells
    (the last cell on the land's side), each road's border laid straight there. (Roads into caves
    end inland, `cave_gates`.)"""
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
    return found, sorted(set(problems))


def boxes(canvas, design, lands):
    """Each land's map: (left, bottom, width, height), the box round its shape (a town's, its
    rectangle). Its middle (`WorldMap.center`, what everything set down by hand is placed from) is
    the box's: width / 2, height / 2 in."""
    import numpy as np
    found = {}
    for k, land_id in enumerate(canvas.ids):
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


def river_line(river, number, straights=()):
    """A river's middle from its spring to the sea, a point every quarter cell: (x, y, how wide it
    is there, how far along it is in cells). Through its `course` (world cells) on a smooth curve,
    meandering a little off it (`RIVER_WOBBLE`, not at its ends), widening from the first of its
    `width` to the second. `straights`: where it runs straight along a row or column instead, round
    a road's crossing (`squared`): how far along, the spot it runs through, and whether eastward."""
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
        x, y = x + side[0] * drift, y + side[1] * drift
        for at, sx, sy, eastward in straights:
            off = abs(s - at)
            if off >= 2 * SQUARE_REACH:
                continue
            t = min(1.0, (2 * SQUARE_REACH - off) / SQUARE_REACH)
            pull = t * t * (3 - 2 * t)
            if eastward:
                y += (sy - y) * pull
            else:
                x += (sx - x) * pull
        line.append((x, y, width, s))
    return line


def squared(line, roads):
    """Where the roads (`roads`, each its points every half cell) cross a river (`line`, from
    `river_line`), the river's `straights` there: how far along it, the spot, and whether it runs
    more east than north there (over 4 cells either way)."""
    import numpy as np
    points = np.array([(x, y) for x, y, _, _ in line])
    radius = np.array([width / 2 + SPRING * max(0.0, 1 - s / 6) for _, _, width, s in line])
    found = []
    for samples in roads:
        gaps = np.sqrt(((points[None, :, :] - np.array(samples)[:, None, :]) ** 2).sum(axis=2))
        nearest = gaps.argmin(axis=1)
        wet = list(gaps[np.arange(len(samples)), nearest] <= radius[nearest]) + [False]
        start = None
        for n, w in enumerate(wet):
            if w and start is None:
                start = n
            elif not w and start is not None:
                k = int(nearest[(start + n - 1) // 2])
                (ax, ay), (bx, by) = points[max(0, k - 16)], points[min(len(points) - 1, k + 16)]
                found.append((line[k][3], float(points[k][0]), float(points[k][1]), abs(bx - ax) >= abs(by - ay)))
                start = None
    return found


def road_lines(land_id, land, middle, crossings, routes, intos=None):
    """A land's roads (to each crossing, from its hub through `routes`' turns) and trails, as
    (what, [(x, y), ...]) in world cells: the lines rivers are bridged on. `intos`: for a road into a
    cave, the way into its mouth (its crossing is the cell in front of it)."""
    mx, my = middle
    hub = land.get("hub") or [0, 0]
    found = []
    for to, (cx, cy) in sorted(crossings.items()):
        exit = next((e for e in land["exits"] if e["to"] == to), None)
        if exit is None:
            continue
        dx, dy = INTO[intos[to]] if to in (intos or {}) else STEP[exit["edge"]]
        last = GATE_APPROACH if to in (intos or {}) else 5
        stops = [(mx + hub[0], my + hub[1])] + [(mx + a, my + b) for a, b in routes.get(to) or []]
        found.append((f"{land_id}'s road to {to}", stops + [(cx - dx * last, cy - dy * last), (cx, cy)]))
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
    # Never through a town's walls; out in its countryside like any land's.
    towns = np.zeros_like(canvas.owner, bool)
    for land_id in ids:
        if is_town(lands[land_id]):
            x, y, w, h = town_box(lands[land_id], design[land_id]["at"])
            r, c = canvas.index(x, y)
            towns[r:r + h, c:c + w] = True
    crossed = [along(stops) for land_id in ids
               for _, stops in road_lines(land_id, lands[land_id], design[land_id]["at"], found[land_id], routes[land_id])]
    for number, river in enumerate(world_rivers):
        name = river.get("name", f"river {number}")
        line = river_line(river, number)
        line = river_line(river, number, squared(line, crossed))
        x0, y0 = line[0][:2]
        x1, y1 = line[-1][:2]
        if canvas.get(int(math.floor(x0)), int(math.floor(y0))) < 0:
            problems.append(f"{name}'s spring isn't on land")
        pool = river.get("lake", 0)
        if not pool and canvas.get(int(math.floor(x1)), int(math.floor(y1))) >= 0:
            problems.append(f"{name} doesn't run out into the sea (or into a lake of its own)")
        total = line[-1][3]
        for x, y, width, s in line:
            radius = width / 2 + SPRING * max(0.0, 1 - s / 6)
            if pool:
                # Widening into the lake it ends in.
                radius = max(radius, pool * min(1.0, max(0.0, 1 - (total - s) / pool)))
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
            clear(cx, cy, RIVER_CROSSING, f"{land_id}'s road to {to}'s crossing")
        clear(mx, my, RIVER_MIDDLE, f"{land_id}'s middle")
        for (dx, dy), what in content_spots(land):
            clear(mx + dx, my + dy, RIVER_CONTENT + CONTENT_MARGIN if what != "hub" else RIVER_MIDDLE, f"{land_id}'s {what}")
    # Roads (and trails) over them: square across, narrow, inland, clear of their ends.
    sea_distance = ndimage.distance_transform_edt(ground)
    bridges = np.zeros_like(under)
    middles = [(p[0], p[1], p[2]) for river in lines for p in river["points"]]
    # Each point's river's first and last point in `middles`.
    ends, first = [], 0
    for river in lines:
        ends += [(first, first + len(river["points"]) - 1)] * len(river["points"])
        first += len(river["points"])
    tree = np.array([(x, y) for x, y, _ in middles])

    def wet(x, y):
        r, c = canvas.index(x, y)
        return 0 <= r < canvas.height and 0 <= c < canvas.width and bool(under[r, c])

    for land_id in ids:
        land = lands[land_id]
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
                low, high = ends[nearest]
                (sx, sy), (ex, ey) = middles[max(low, nearest - 16)][:2], middles[min(high, nearest + 16)][:2]
                slant = math.degrees(math.atan2(ey - sy, ex - sx)) % 90
                slant = min(slant, 90 - slant)
                if slant > BRIDGE_AXIS:
                    problems.append(f"{spot} where it runs {slant:.0f} degrees off the grid")
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
            if "x" in thing and thing.get("summit") is None and not thing.get("at"):
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
        x0, y0, w, h = grids[land_id]
        r0, c0 = canvas.index(x0, y0)
        mine = canvas.owner[r0:r0 + h, c0:c0 + w] == k
        town = town_box(land, design[land_id]["at"]) if is_town(land) else None
        if town:
            # Out of a town through the gate in its wall, never back over it.
            tx, ty, tw, th = town
            mine[ty - y0:ty - y0 + th, tx - x0:tx - x0 + tw] = False
        depth = ndimage.distance_transform_edt(np.pad(mine, 1))[1:-1, 1:-1]
        mx, my = design[land_id]["at"][0] - x0, design[land_id]["at"][1] - y0
        hub = land.get("hub") or [0, 0]
        for to, (cx, cy) in found[land_id].items():
            exit = next(e for e in land["exits"] if e["to"] == to)
            dx, dy = STEP[exit["edge"]]
            goal = (cx - x0 - dx * 5, cy - y0 - dy * 5)
            lead = []
            if town:
                gx, gy = gate(land, town, exit)
                start = (gx + dx * TOWN_GATE - x0, gy + dy * TOWN_GATE - y0)
                lead = [start]
            else:
                start = (mx + hub[0], my + hub[1])
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
            via = turns(path, depth)
            # The last stretch to the border is the game's (`WorldMap.carveRoad`).
            via = [v for v in via if max(abs(v[0] - goal[0]), abs(v[1] - goal[1])) > 6]
            found_ways[land_id][to] = [[px - mx, py - my] for px, py in lead + via]
    return found_ways, problems


def cheapest(mine, depth, start):
    """The cheapest ways from `start` over a land's cells (`mine`, in its box), 8 ways, a step
    costing more the nearer the coast or the border it is (`depth`): each cell's cost and the cell
    it's reached from."""
    import heapq
    h, w = mine.shape
    best = {start: 0.0}
    back = {}
    queue = [(0.0, start)]
    while queue:
        cost, cell = heapq.heappop(queue)
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
    return best, back


def turns(path, depth):
    """A way cut down to its turns: from each waypoint, straight on as far as the way stays as deep
    in the land (up to 6 cells) as the path itself did. The turns, without its ends."""
    def clear(a, b, least):
        n = max(abs(b[0] - a[0]), abs(b[1] - a[1]), 1)
        for t in range(n + 1):
            px = round(a[0] + (b[0] - a[0]) * t / n)
            py = round(a[1] + (b[1] - a[1]) * t / n)
            if depth[py, px] < least:
                return False
        return True

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
    return via


INTO = {"north": (0, 1), "east": (1, 0)}


def gate_into(maps, land_id, exit):
    """The way you walk into a cave's mouth on the road `exit` out of `land_id`: the other way from
    the cave's own road back out of it (maps.json), so inside you come in on the side you walked in
    from (playtesting 2026-10-16). North or east, so its face is turned toward you (down the screen
    is south and west): a cave's ways back out leave by its south or west side. None if they don't."""
    back = [e for e in maps.get(exit["to"], {}).get("exits", []) if e["to"] == land_id]
    into = OPPOSITE[back[0]["edge"]] if back else None
    return into if into in INTO else None


def gate_cells(foot, into, shape):
    """The cells a cave's hill (`shape`: how far past the mouth's foot its middle is, its reach along
    the face and into it) covers, its ellipse grown by a cell: `foot` is the middle of the mouth's
    foot line, in world cells (floats)."""
    ix, iy = INTO[into]
    ax, ay = iy, ix
    centre = (foot[0] + ix * shape[0], foot[1] + iy * shape[0])
    reach = int(max(shape[1], shape[2])) + 2
    cells = []
    for y in range(int(centre[1]) - reach, int(centre[1]) + reach + 1):
        for x in range(int(centre[0]) - reach, int(centre[0]) + reach + 1):
            dx, dy = x + 0.5 - centre[0], y + 0.5 - centre[1]
            u, v = (dx * ax + dy * ay) / shape[1], (dx * ix + dy * iy) / shape[2]
            if (1 - math.hypot(u, v)) * min(shape[1], shape[2]) > -1:
                cells.append((x, y))
    return cells


def gate_foot(at, into):
    """The middle of a cave's mouth's foot, in cells: the far side of `at`, the cell in front of it."""
    ix, iy = INTO[into]
    return (at[0] + 0.5 + ix * 0.5, at[1] + 0.5 + iy * 0.5)


def cave_gates(canvas, design, lands, maps, grids, found, routes, under):
    """Where each road into a cave ends (playtesting 2026-10-16): inland, at a rocky hill with the
    mouth in its face, its face turned toward you, so you walk north or east into it (`gate_into`).
    Out from the hub toward the side the exit names (`GATE_OUT` along that way, no further across it
    than along), the hill's room clear of the coast and the lands next door, the rivers, the other
    roads and everything set down by hand (`GATE_ROOM`, its main summit's further, `GATE_SUMMIT`),
    and the way there from the hub (the cheapest, as `ways` finds) clear of the rivers and the hill,
    running into the mouth straight for `GATE_APPROACH` cells. Of the places that fit, the one with
    the way nearest `GATE_IDEAL` long that turns least into the mouth. Adds each to `found` (the cell
    in front of the mouth) and `routes` (the way's turns); returns {land: {cave: into}} and problems."""
    import numpy as np
    from scipy import ndimage
    intos, problems = {}, []
    index = {land_id: k for k, land_id in enumerate(canvas.ids)}
    wet_distance = ndimage.distance_transform_edt(~under)
    for land_id, exit in cave_exits(maps, lands):
        land = lands[land_id]
        k = index[land_id]
        x0, y0, w, h = grids[land_id]
        r0, c0 = canvas.index(x0, y0)
        mine = canvas.owner[r0:r0 + h, c0:c0 + w] == k
        depth = ndimage.distance_transform_edt(np.pad(mine, 1))[1:-1, 1:-1]
        wet = wet_distance[r0:r0 + h, c0:c0 + w]
        mx, my = design[land_id]["at"][0] - x0, design[land_id]["at"][1] - y0
        hub_offset = land.get("hub") or [0, 0]
        hub = (mx + hub_offset[0], my + hub_offset[1])
        # The other roads, and everything set down by hand.
        roads = np.ones((h, w), bool)
        lines = road_lines(land_id, land, (mx, my), {to: (x - x0, y - y0) for to, (x, y) in found[land_id].items()},
                           routes.get(land_id, {}))
        for _, stops in lines:
            for x, y in along(stops):
                i, j = int(math.floor(x)), int(math.floor(y))
                if 0 <= i < w and 0 <= j < h:
                    roads[j, i] = False
        road_distance = ndimage.distance_transform_edt(roads)
        alone = np.ones((h, w), bool)
        for (dx, dy), _ in content_spots(land):
            if 0 <= mx + dx < w and 0 <= my + dy < h:
                alone[my + dy, mx + dx] = False
        people_distance = ndimage.distance_transform_edt(alone)
        best, back = cheapest(mine, depth, hub)
        into = gate_into(maps, land_id, exit)
        if into is None:
            problems.append(f"{exit['to']}'s road back to {land_id} should leave by its south or west side")
            continue
        ix, iy = INTO[into]
        ox, oy = STEP[exit["edge"]]

        def fits(cells, least):
            coast, river, road, person = least
            xs = np.array([c[0] for c in cells])
            ys = np.array([c[1] for c in cells])
            if xs.min() < 0 or ys.min() < 0 or xs.max() >= w or ys.max() >= h:
                return False
            return bool(mine[ys, xs].all() and (depth[ys, xs] >= coast).all() and (wet[ys, xs] >= river).all()
                        and (road_distance[ys, xs] >= road).all() and (people_distance[ys, xs] >= person).all())

        picked = None
        for y in range(h):
            for x in range(w):
                vx, vy = x - hub[0], y - hub[1]
                forward, across = vx * ox + vy * oy, abs(vx * oy - vy * ox)
                if not (GATE_OUT[0] <= forward <= GATE_OUT[1]) or across > forward:
                    continue
                approach = (round(x - ix * GATE_APPROACH), round(y - iy * GATE_APPROACH))
                if approach not in back:
                    continue
                foot = gate_foot((x, y), into)
                room = gate_cells(foot, into, GATE_ROOM)
                summit = gate_cells(foot, into, GATE_SUMMIT)
                least = lambda n: (GATE_COAST[n], GATE_RIVER[n], GATE_ROAD[n], GATE_PEOPLE[n])
                if not fits(room, least(0)) or not fits(summit, least(1)):
                    continue
                # The way there: clear of the rivers all along and of the hill, and the straight
                # stretch into the mouth on the land.
                path = [approach]
                while path[-1] != hub:
                    path.append(back[path[-1]])
                path.reverse()
                inside = set(room)
                if any(wet[py, px] < RIVER_GATE_ROAD for px, py in path) or any(p in inside for p in path[:-3]):
                    continue
                straight = [(round(x - ix * t), round(y - iy * t)) for t in range(GATE_APPROACH + 1)]
                if not all(0 <= px < w and 0 <= py < h and mine[py, px] and wet[py, px] >= RIVER_GATE_ROAD for px, py in straight):
                    continue
                # How it turns into the mouth: the way's last few cells against `into`.
                tail = path[max(0, len(path) - 7)]
                dx, dy = approach[0] - tail[0], approach[1] - tail[1]
                length = math.hypot(dx, dy) or 1
                turn = math.degrees(math.acos(max(-1.0, min(1.0, (dx * ix + dy * iy) / length))))
                cost = abs(len(path) - GATE_IDEAL) / 12 + turn / 60 + across / max(forward, 1)
                if picked is None or cost < picked[0]:
                    picked = (cost, (x, y), path)
        if picked is None:
            problems.append(f"{land_id}'s road into the cave {exit['to']} has nowhere inland for its mouth")
            continue
        _, (x, y), path = picked
        via = [v for v in turns(path + [(x, y)], depth) if math.hypot(v[0] - x, v[1] - y) > GATE_APPROACH + 2]
        found[land_id][exit["to"]] = (x0 + x, y0 + y)
        routes.setdefault(land_id, {})[exit["to"]] = [[px - mx, py - my] for px, py in via]
        intos.setdefault(land_id, {})[exit["to"]] = into
    return intos, problems


def write(data, lands, design, grids, roads, routes, intos, shapes, lines):
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
            if intos.get(i, {}).get(to):
                road["into"] = intos[i][to]
            exit = next((e for e in lands[i]["exits"] if e["to"] == to), {})
            if exit.get("ship"):
                road["pier"] = exit["edge"]
            entries.append(f'      {json.dumps(to)}: {json.dumps(road, separators=(", ", ": "))}')
        blocks.append(f'    "{i}": {{\n' + ",\n".join(entries) + "\n    }")
    out.append(",\n".join(blocks))
    out += ["  },", '  "rivers": [']
    blocks = []
    for river, line in zip(old.get("rivers", []), lines):
        spec = {key: river[key] for key in ("name", "width", "lake", "course") if key in river}
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
    # The towns' walled squares and the countryside right round them stay as they are; the rest of
    # their countryside is tidied as any land is.
    keep = np.zeros_like(canvas.owner, bool)
    for land_id in canvas.ids:
        if is_town(lands[land_id]):
            x, y, w, h = town_box(lands[land_id], design[land_id]["at"])
            r, c = canvas.index(x - TOWN_OWN, y - TOWN_OWN)
            keep[r:r + h + 2 * TOWN_OWN, c:c + w + 2 * TOWN_OWN] = True
    tidy(canvas, keep, set())
    found, problems = crossings(canvas, design, lands, maps, keep)
    tidy(canvas, keep, set())
    docks, ships = harbors(canvas, design, lands, keep, world_rivers)
    for land_id, ends in docks.items():
        found[land_id].update(ends)
    grids = boxes(canvas, design, lands)
    routes, more = ways(canvas, design, lands, grids, found)
    river, lines, wet = rivers(canvas, world_rivers, design, lands, grids, found, routes)
    intos, caves = cave_gates(canvas, design, lands, maps, grids, found, routes, river)
    # Roads in each land's own cells.
    roads = {i: {to: (x - grids[i][0], y - grids[i][1]) for to, (x, y) in found[i].items()} for i in found}
    return canvas, grids, roads, routes, intos, regions(canvas, grids, river), lines, problems + ships + more + wet + caves


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
    sea_cells = set().union(*sea.values()) if sea else set()
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
        mc, mr = world["middles"][land_id]
        middle = (x0 + mc, y0 + mr)
        if is_town(land):
            # Its walled square all its own, round its middle, with its land round it.
            tx, ty, tw, th = town_box(land, middle)
            if any((x, y) not in cells for x in range(tx, tx + tw) for y in range(ty, ty + th)):
                problems.append(f"world.json: town {land_id}'s walled square isn't all its own")
            ring = [(x, y) for x in range(tx - 2, tx + tw + 2) for y in range(ty - 2, ty + th + 2)
                    if not (tx <= x < tx + tw and ty <= y < ty + th)]
            if any((x, y) in sea_cells for x, y in ring):
                problems.append(f"world.json: town {land_id}'s wall stands by the sea, with no land round it")
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
            last = 5
            if exit.get("ship"):
                # To a harbor: on the coast its side faces, its pier's way written, the sea open
                # straight out from it for the pier and the ship (`harbors`), a ship sailing back.
                if exit["to"] not in lands:
                    problems.append(f"world.json: {land_id}'s ship sails to {exit['to']}, which isn't a land")
                    continue
                if road.get("pier") != exit["edge"]:
                    problems.append(f"world.json: {land_id}'s harbor for {exit['to']} should have its pier run "
                                    f"{exit['edge']} (run tools/world_layout.py)")
                if not any(e["to"] == land_id and e.get("ship") for e in lands[exit["to"]]["exits"]):
                    problems.append(f"world.json: {exit['to']} has no ship back to {land_id}")
                sx, sy = -dy * harbor_side(exit["edge"]), dx * harbor_side(exit["edge"])
                if any((here[0] + dx * a + sx * b, here[1] + dy * a + sy * b) in owner
                       for a in range(1, HARBOR_SEA + 1) for b in range(HARBOR_ACROSS[0], HARBOR_ACROSS[1] + 1)):
                    problems.append(f"world.json: {land_id}'s harbor for {exit['to']} doesn't look out on open sea")
            elif exit["to"] in lands:
                back = world["roads"].get(exit["to"], {}).get(land_id)
                ox, oy = origins[exit["to"]]
                if not back or (ox + back["at"][0], oy + back["at"][1]) != over:
                    problems.append(f"world.json: the road from {land_id} {exit['edge']} doesn't meet {exit['to']}'s")
                if owner.get(over) != exit["to"]:
                    problems.append(f"world.json: past {land_id}'s road {exit['edge']} isn't {exit['to']}")
            else:
                # Into a cave: its mouth inland in a hill on the land, turned toward you, clear of
                # the coast and the rivers (`cave_gates`).
                into = road.get("into")
                if into is None or into != gate_into(maps, land_id, exit):
                    problems.append(f"world.json: {land_id}'s road into the cave {exit['to']} should go {gate_into(maps, land_id, exit)} "
                                    f"into its mouth, the other way from {exit['to']}'s road back (run tools/world_layout.py)")
                    continue
                dx, dy = INTO[into]
                last = GATE_APPROACH
                foot = gate_foot(here, into)
                mine = own.get(land_id, set())
                water = wet.get(land_id, set())
                for shape, n in ((GATE_ROOM, 0), (GATE_SUMMIT, 1)):
                    coast, river = GATE_COAST[n], GATE_RIVER[n]
                    # The cells nearer than that, as the search measures (`cave_gates`).
                    near_coast = [(i, j) for i in range(-coast, coast + 1) for j in range(-coast, coast + 1) if i * i + j * j < coast * coast]
                    near_river = [(i, j) for i in range(-river, river + 1) for j in range(-river, river + 1) if i * i + j * j < river * river]
                    for x, y in gate_cells(foot, into, shape):
                        if not all((x + i, y + j) in mine for i, j in near_coast):
                            problems.append(f"world.json: the hill {land_id}'s road into {exit['to']} ends at reaches "
                                            f"within {coast} cells of its land's edge")
                            break
                        if any((x + i, y + j) in water for i, j in near_river):
                            problems.append(f"world.json: a river runs within {river} cells of the hill {land_id}'s road "
                                            f"into {exit['to']} ends at")
                            break
            hub = land.get("hub") or [0, 0]
            stops = [hub] + road.get("via", [])
            points = [(middle[0] + x, middle[1] + y) for x, y in stops] + [(here[0] - dx * last, here[1] - dy * last)]
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
        lines = road_lines(land_id, land, (x0 + mc, y0 + mr), crossings, {to: r.get("via") for to, r in roads.items()},
                           {to: r["into"] for to, r in roads.items() if "into" in r})
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
        if is_town(land):
            tx, ty, tw, th = town_box(land, (x0 + world["middles"][land_id][0], y0 + world["middles"][land_id][1]))
            if any(tx - RIVER_TOWN <= x < tx + tw + RIVER_TOWN and ty - RIVER_TOWN <= y < ty + th + RIVER_TOWN for x, y in water):
                problems.append(f"world.json: a river runs within {RIVER_TOWN} cells of the town {land_id}'s walls")
        mc, mr = world["middles"][land_id]
        middle = (x0 + mc, y0 + mr)

        def near(spot, reach):
            return any((spot[0] + i, spot[1] + j) in water for i in range(-reach, reach + 1) for j in range(-reach, reach + 1))

        for to, road in world["roads"].get(land_id, {}).items():
            reach = RIVER_CROSSING if to in lands else RIVER_GATE_ROAD
            if near((x0 + road["at"][0], y0 + road["at"][1]), reach):
                problems.append(f"world.json: a river runs within {reach} cells of where {land_id}'s road to {to} "
                                + ("crosses" if to in lands else "goes into the cave"))
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
        intos = {to: r["into"] for to, r in world["roads"].get(land_id, {}).items() if "into" in r}
        lines = road_lines(land_id, land, middle, crossings, routes, intos)
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
        land = lands[land_id]
        colour = COLOURS.get(land["theme"].get("border") if is_town(land) else land["theme"]["ground"], (200, 200, 200))
        walls = None
        if is_town(land):
            x0, y0 = origins[land_id]
            walls = town_box(land, (x0 + world["middles"][land_id][0], y0 + world["middles"][land_id][1]))
        for x, y in cells:
            owner[(x, y)] = land_id
            inside = walls and walls[0] <= x < walls[0] + walls[2] and walls[1] <= y < walls[1] + walls[3]
            pixels[x - left, top - 1 - y] = (196, 160, 120) if inside else colour
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
        intos = {to: r["into"] for to, r in roads.items() if "into" in r}
        for _, stops in road_lines(land_id, land, (mx, my), crossings, {to: r.get("via") for to, r in roads.items()}, intos):
            draw.line([((x - left) * scale, (top - y) * scale) for x, y in stops], fill=(140, 100, 60), width=2)
        # A cave's hill: its main summit, and the room round it for the rest.
        for to, into in intos.items():
            foot = gate_foot(crossings[to], into)
            for cells, colour in ((gate_cells(foot, into, GATE_ROOM), (150, 140, 130)), (gate_cells(foot, into, GATE_SUMMIT), (110, 100, 95))):
                for x, y in cells:
                    draw.rectangle([(x - left) * scale, (top - 1 - y) * scale, (x - left) * scale + scale - 1, (top - 1 - y) * scale + scale - 1], fill=colour)
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
        canvas, grids, roads, routes, intos, shapes, lines, problems = solve(data, maps, lands, world["design"], world.get("rivers", []))
        for problem in problems:
            print("  " + problem)
        write(data, lands, world["design"], grids, roads, routes, intos, shapes, lines)
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
