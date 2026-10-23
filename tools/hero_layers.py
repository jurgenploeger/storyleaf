#!/usr/bin/env python3
"""Splits each race's walk sheets into paper-doll layers, like Fairyland Online dressed its heroes:

    art/sprites/body_<race>.png          the body, bald (the hair taken off, the scalp drawn in)
    art/sprites/locks_<race>.png         a beard, which stays whatever the style (copied, so the
                                         body stays whole; empty for the clean-shaven)
    art/sprites/hair_<style>_<race>.png  every hairstyle, fitted to every race's head
    art/sprites/hood_<race>.png          a hood and a helmet sized to the bare head; the game
    art/sprites/helmet_<race>.png        colours them like the armour (see MARKERS below)
    art/sprites/nape_<style>_<race>.png  each hairstyle from a fifth of the way down the head:
                                         worn under armour with a walk sheet of its own, so long
                                         hair, a ponytail or braids show below the helmet or hood

A gender with its own walk sheet (classes.json `sheets`) gets the same set with a _<gender> suffix
(body_elf_male.png, ...). Every hairstyle is taken from the sheet it was drawn on (STYLES: a
ponytail from the female human, a bob from a sheet kept only for its hair) and fitted to every
head, so a girl can wear a boy's hair and the other way round. A gender's own hair is the one it
starts with: appearance.json `styles` with a `sheet`.

The game stacks body + locks + hair (or body + locks + hood/helmet: no hair pokes through). The
body is recoloured like the whole sheet used to be (skin, hair, outfit); the locks and hair layers
hold nothing but hair, so the hair colour reaches every shade of them (appearance.json
`hairLayer`). A style moved onto another head is lined up with its skull and brow, kept off its
face, opened where an elf's ears poke through, and painted in that sheet's own hair colours, so
one head has one hair colour before any dye. Rerun after changing a walk sheet:

    python3 tools/hero_layers.py            # writes the PNGs
    python3 tools/hero_layers.py --preview /tmp/layers.png

Needs pillow + numpy.
"""
import argparse
import colorsys
import json
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import palette_preview as pp  # noqa: E402

F = 48
DIRS = ["up", "right", "down", "left"]
OUTLINE = np.array([0.16, 0.12, 0.18])
# Every hairstyle, each taken from the walk sheet it was drawn on, as (race, sheet). The last three
# sheets are no one's body any more, only where their hair comes from.
STYLES = {
    "spiky": ("human", "player_walk"), "long": ("elf", "elf_walk"), "crop": ("dwarf", "dwarf_walk"),
    "ponytail": ("human", "human_female_walk"), "swept": ("elf", "elf_male_walk"),
    "braids": ("dwarf", "dwarf_female_walk"), "bob": ("human", "human_other_walk"),
    "shoulder": ("elf", "elf_other_walk"), "messy": ("dwarf", "dwarf_other_walk"),
}
# Walk sheets no hero wears but townsfolk do (art/assets.json `derive` with `layers`), as (race,
# sheet): split the same way, their own hair kept as hair_<body> (an old dwarf's bushy mop; his
# beard is his locks).
TOWNSFOLK = {"dwarf_npc": ("dwarf", "dwarf_npc_walk")}
# Headgear is drawn in magenta, which no recolour touches (skin 5-45°, hair 12-58°, outfit 85-170°)
# and no hero sheet uses. The game paints soft magenta (saturation 0.6) in the armour's colour,
# keeping the shade (value: 0.92 light, 0.7 mid, 0.45 dark), and full magenta in its trim colour.
# Storyleaf/Art/GearOverlay.swift and tools/gear_preview.py read these.
MARK_HUE = 300 / 360
# Sheets whose hair rises well above the skull (a bun): the top of the head is the first row with
# this many hair pixels instead of four, so the bald scalp sits on the real head, not the bun.
TUFTS = {"human_female_walk": 8}
# Hair hanging past the head (side locks, braids) is looked for down to this many rows below the brow.
LOCK_DEPTH = 14
# The bald skull's half-width in pixels, smallest and largest.
SKULL = (6.0, 7.0)
# Races with long pointed ears, which poke out through any hairstyle.
EARED = {"elf"}
# Under armour with its own walk sheet (a helmet, a hood) only the hair this far down the head and
# below shows, from the top of the head to the feet: none rises over the helmet.
NAPE = 0.2
# Brightness, for matching shades between two heads of hair.
LUMA = np.array([0.299, 0.587, 0.114])
# The window a hair dye recolours on the hair and locks layers.
HAIR_LAYER = json.load(open(ROOT / "content" / "appearance.json"))["hairLayer"]


def hsv(p):
    return colorsys.rgb_to_hsv(*p[:3])


def opaque(p):
    return p[3] >= 0.5


def is_hair(p):
    """Bright hair: the rule content/appearance.json recolours (hue 12-58, saturated, bright)."""
    if not opaque(p):
        return False
    h, s, v = hsv(p)
    return 12 <= h * 360 <= 58 and s >= 0.55 and v >= 0.55


def is_skin(p):
    if not opaque(p):
        return False
    h, s, v = hsv(p)
    return h * 360 <= 40 and 0.15 < s < 0.55 and v > 0.6


def is_outfit(p):
    if not opaque(p):
        return False
    h, s, _ = hsv(p)
    return 85 <= h * 360 <= 170 and s >= 0.3


def hairish(p):
    """A darker strand of hair: same hues, dimmer. Only counts when it touches the bright hair."""
    if not opaque(p) or is_skin(p):
        return False
    h, s, v = hsv(p)
    return 5 <= h * 360 <= 62 and s >= 0.3 and v >= 0.2


def lockish(p):
    """Any shade of hair: gold to deep red, highlight to shadow. Bright reds only when strong (an
    auburn highlight), so pink ears and cheeks stay skin."""
    if not opaque(p) or is_skin(p):
        return False
    h, s, v = hsv(p)
    h *= 360
    if 5 <= h <= 62:
        return s >= 0.3 and v >= 0.12
    if h >= 345 or h < 5:
        return s >= (0.6 if v >= 0.6 else 0.4) and v >= 0.12
    return False


def dark(p):
    return opaque(p) and max(p[:3]) < 0.35


def frame(sheet, row, col):
    return sheet[row * F:(row + 1) * F, col * F:(col + 1) * F]


def crown(f, width=4):
    """Top of the head: the first row with `width` hair pixels (four skips a lone spike's tip; a
    sheet with a bun on top asks for more, see TUFTS)."""
    for y in range(F):
        if sum(is_hair(f[y, x]) for x in range(F)) >= width:
            return y
    return None


def skin_run(f, y):
    """The widest run of skin on row y, as (left, right)."""
    best, run = None, []
    for x in range(F + 1):
        if x < F and is_skin(f[y, x]):
            run.append(x)
        elif run:
            if best is None or len(run) > best[1] - best[0] + 1:
                best = (run[0], run[-1])
            run = []
    return best


def reddish(p):
    """The pink-red edge round an elf's ear (or a cheek): bright, red to orange-red. An elf's hair
    is gold, so on an elf this is never hair."""
    if not opaque(p):
        return False
    h, s, v = hsv(p)
    h *= 360
    return (h <= 25 or h >= 340) and s >= 0.3 and v >= 0.45


def mask(f, test):
    return np.array([[test(f[y, x]) for x in range(F)] for y in range(F)])


def flood(f, seeds, ok, allowed=None, diagonal=False):
    """Every pixel joined to the seeds through pixels that pass `ok` (and `allowed`, if given)."""
    m = np.zeros((F, F), bool)
    stack = [q for q in seeds if allowed is None or allowed[q]]
    for y, x in stack:
        m[y, x] = True
    steps = [(dy, dx) for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx] if diagonal \
        else [(1, 0), (-1, 0), (0, 1), (0, -1)]
    while stack:
        y, x = stack.pop()
        for dy, dx in steps:
            yy, xx = y + dy, x + dx
            if 0 <= yy < F and 0 <= xx < F and not m[yy, xx] and (allowed is None or allowed[yy, xx]) \
                    and ok(f[yy, xx]):
                m[yy, xx] = True
                stack.append((yy, xx))
    return m


def neighbours8(y, x):
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if (dy or dx) and 0 <= y + dy < F and 0 <= x + dx < F:
                yield y + dy, x + dx


class Head:
    """Where one frame's head is: crown, brow (first row of the face), face span, skull ellipse."""

    def __init__(self, f, facing, drop, half, tuft=4):
        self.top = crown(f, tuft)
        self.brow = self.top + drop
        self.facing = facing
        xs = [x for y in range(self.top, self.brow) for x in range(F) if is_hair(f[y, x])]
        cx = (min(xs) + max(xs)) / 2
        runs = [r for r in (skin_run(f, y) for y in range(self.brow, self.brow + 4)) if r]
        self.face = (min(r[0] for r in runs), max(r[1] for r in runs)) if runs else None
        if self.face and facing in ("right", "left"):
            front = self.face[1] if facing == "right" else self.face[0]
            cx = front - (half - 1.5) if facing == "right" else front + (half - 1.5)
        elif self.face and facing == "down":
            cx = (self.face[0] + self.face[1]) / 2
        self.cx = cx
        self.half = half
        self.ry = half * 0.9
        self.cy = self.brow + 1          # the skull's widest row, just below the brow

    def inside(self, x, y, grow=0.0):
        return ((x - self.cx) / (self.half + grow)) ** 2 + ((y - self.cy) / (self.ry + grow)) ** 2 <= 1


def face_region(f, head):
    """The face from the brow down to the chin: on each row, everything between its outermost skin
    (joined to the middle of the face), so the eyes, blush and mouth it holds count as face."""
    region = np.zeros((F, F), bool)
    mid = (head.face[0] + head.face[1]) / 2 if head.face else head.cx
    reach = np.zeros((F, F), bool)
    for y in range(head.brow, min(F, head.brow + 10)):
        for x in range(F):
            reach[y, x] = abs(x - mid) <= head.half + 1
    seeds = [(y, x) for y in range(head.brow, min(F, head.brow + 4)) for x in range(F)
             if reach[y, x] and abs(x - mid) <= 2 and is_skin(f[y, x])]
    skin = flood(f, seeds, is_skin, reach)
    for y in range(F):
        xs = np.nonzero(skin[y])[0]
        if len(xs):
            region[y, xs.min():xs.max() + 1] = True
    return region


def front_of_body(face, head):
    """Below the chin, where hanging hair never is: down the middle of the chest seen from the
    front, in front of the neck seen from the side. Buttons, a collar or a strap there that touch
    the hair stay with the body."""
    out = np.zeros((F, F), bool)
    rows = [y for y in range(F) if face[y].any()]
    if not rows or head.facing == "up":
        return out
    chin = rows[-1]
    xs = np.nonzero(face[chin])[0]
    mid, half = (xs.min() + xs.max()) / 2, (xs.max() - xs.min()) / 2
    for y in range(chin + 1, F):
        for x in range(F):
            if head.facing == "down":
                out[y, x] = abs(x - mid) <= half + 1
            else:
                out[y, x] = (x - mid) * (1 if head.facing == "right" else -1) >= -1
    return out


def ear_mask(f, head, face):
    """An elf's ears: skin that isn't face, from above the brow to just under it, with the pink-red
    edge drawn round it."""
    ears = np.zeros((F, F), bool)
    for y in range(max(0, head.brow - 6), min(F, head.brow + 2)):
        for x in range(F):
            ears[y, x] = is_skin(f[y, x]) and not face[y, x]
    edge = np.zeros((F, F), bool)
    for y, x in zip(*np.nonzero(ears)):
        for q in neighbours8(y, x):
            if not ears[q] and reddish(f[q]):
                edge[q] = True
    return ears | edge


def grow(m, steps=1):
    out = m.copy()
    for _ in range(steps):
        prev = out.copy()
        for y, x in zip(*np.nonzero(prev)):
            for q in neighbours8(y, x):
                out[q] = True
    return out


def join_strands(f, hair, reach, gap=2):
    """Pieces of hair cut off from the rest by a thin dark band (a braid's tie, the outline between
    two locks) join it when they're within `gap` pixels, piece by piece."""
    loose = mask(f, lockish) & reach & ~hair
    pieces = []
    while loose.any():
        piece = flood(f, [tuple(np.argwhere(loose)[0])], lambda p: True, loose, diagonal=True)
        pieces.append(piece)
        loose &= ~piece
    joined = True
    while joined:
        joined = False
        near = grow(hair, gap)
        for i, piece in enumerate(pieces):
            if piece is not None and (piece & near).any():
                hair = hair | piece
                pieces[i] = None
                joined = True
    return hair


class Race:
    def __init__(self, race_id, sheet_id, template=None, sidehair=False):
        """`template`: the body that patches what long hair hid (a back, shoulders). `sidehair`: hair
        hanging past the head (side locks, braids) belongs to the style, so another style leaves
        the shoulders clean."""
        self.id = race_id
        self.sheet_id = sheet_id
        self.sheet = pp.raw(sheet_id)
        self.tuft = TUFTS.get(sheet_id, 4)
        self.template = template
        self.sidehair = sidehair
        down = frame(self.sheet, DIRS.index("down"), 0)
        top = crown(down, self.tuft)
        # The brow: the first row of face, i.e. skin carrying on into the row below (a stray
        # skin-coloured highlight in the hair doesn't count).
        self.drop = next(y - top for y in range(top, F - 1)
                         if (r := skin_run(down, y)) and r[1] - r[0] >= 2
                         and (n := skin_run(down, y + 1)) and n[1] - n[0] >= 1)
        face = skin_run(down, top + self.drop + 1) or skin_run(down, top + self.drop)
        # The skull's half-width, from the face: eyes and a fringe can split the face's skin into a
        # narrow run, which made some skulls far smaller than the hair drawn round them (and stretched
        # an elf's ears into wings). Every sheet's hair is 15-19 pixels across, so keep it in SKULL.
        self.half = min(SKULL[1], max(SKULL[0], (face[1] - face[0]) / 2 + 3.5))
        self.skin = np.median([down[y, x, :3] for y in range(top + self.drop, top + self.drop + 4)
                               for x in range(F) if is_skin(down[y, x])], axis=0)
        self.beard = self._bearded(down, top)
        self.heads = {}
        self.faces = {}
        self.ears = {}
        self.body = self.sheet.copy()
        self.hair = np.zeros_like(self.sheet)
        self.locks = np.zeros_like(self.sheet)
        found = {}
        for row, facing in enumerate(DIRS):
            for col in range(self.sheet.shape[1] // F):
                found[row, col] = self._find(row, col, facing)
        self._steady(found)
        for (row, col), (take, beard) in found.items():
            self._cut(row, col, take, beard)

    def _bearded(self, down, top):
        brow = top + self.drop
        hair = flood(down, [(y, x) for y in range(top, brow) for x in range(F) if is_hair(down[y, x])], hairish)
        r = skin_run(down, brow + 1)
        cx = (r[0] + r[1]) / 2 if r else F / 2
        chin = brow + 5
        return sum(hair[y, x] for y in range(chin, chin + 6) for x in range(F) if abs(x - cx) < 4) >= 12

    def is_beard(self, head, x, y):
        if not self.beard or head.facing == "up" or not head.brow + 3 <= y <= head.brow + 12:
            return False
        if head.facing == "down":
            return abs(x - head.cx) < head.half - 1
        side = 1 if head.facing == "right" else -1
        return (x - head.cx) * side > -2

    def _find(self, row, col, facing):
        """Which pixels of a frame are hair (with its outline), and where a beard would be."""
        f = frame(self.sheet, row, col)
        head = Head(f, facing, self.drop, self.half, self.tuft)
        self.heads[row, col] = head
        face = face_region(f, head)
        ears = ear_mask(f, head, face) if self.id in EARED else np.zeros((F, F), bool)
        self.faces[row, col] = face
        self.ears[row, col] = ears
        beard = np.array([[self.is_beard(head, x, y) for x in range(F)] for y in range(F)])
        # What the hair never takes: the face from the eyes down (eyes, blush, a mouth), a beard,
        # the front of the body under the chin (a collar, buttons), an elf's ears and the pink-red
        # edge round them.
        below_eyes = np.zeros((F, F), bool)
        below_eyes[head.brow + 2:] = True
        allowed = ~((face & below_eyes) | beard | ears | front_of_body(face, head))
        if self.id in EARED:
            allowed &= ~mask(f, reddish)
        # Seed from the very top of the hair, so a bun above the skull (TUFTS) comes off too.
        seeds = [(y, x) for y in range(crown(f), head.brow) for x in range(F) if is_hair(f[y, x])]
        hair = flood(f, seeds, hairish, allowed)
        if self.sidehair:
            # Hair hanging past the head (side locks, braids, the ends of a bob): any shade of hair
            # still joined to it, down to the shoulders, across a thin dark band (a braid's tie).
            reach = allowed.copy()
            reach[head.brow + LOCK_DEPTH + 1:] = False
            hair |= flood(f, list(zip(*np.nonzero(hair))), lockish, reach, diagonal=True)
            hair = join_strands(f, hair, reach)
        # Pale highlights that look like skin, inside the hair (over the brow, or anywhere on the
        # back of the head): hair too, or they'd keep their colour through a dye. Over the brow
        # nothing is skin but an elf's ears, so there any touching the hair count.
        if self.id not in EARED:
            above = allowed.copy()
            above[head.brow:] = False
            hair |= flood(f, list(zip(*np.nonzero(hair))), lambda p: is_skin(p) or hairish(p), above)
        limit = F if facing == "up" else head.brow
        for _ in range(2):
            for y in range(limit):
                for x in range(F):
                    if not hair[y, x] and allowed[y, x] and opaque(f[y, x]) and not dark(f[y, x]) and sum(
                            hair[q] for q in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1))
                            if 0 <= q[0] < F and 0 <= q[1] < F) >= 3:
                        hair[y, x] = True
        # The hair's own outline goes with it: dark pixels touching nothing but hair, or outline
        # that's already going (an outline two pixels thick).
        lines = np.zeros((F, F), bool)
        for _ in range(3):
            for y in range(min(F, head.brow + LOCK_DEPTH + 1)):
                for x in range(F):
                    if dark(f[y, x]) and not hair[y, x] and not lines[y, x] and allowed[y, x] \
                            and not is_outfit(f[y, x]):
                        near = [q for q in neighbours8(y, x) if opaque(f[q])]
                        if all(hair[q] for q in near if not dark(f[q])) and any(hair[q] or lines[q] for q in near):
                            lines[y, x] = True
        if self.sidehair:
            # Hanging hair shares its outline with the shoulders: it goes when it's mostly the hair's.
            for y in range(head.brow + 2, min(F, head.brow + LOCK_DEPTH + 1)):
                for x in range(F):
                    if dark(f[y, x]) and not hair[y, x] and not lines[y, x] and allowed[y, x] \
                            and not is_outfit(f[y, x]):
                        near = [q for q in neighbours8(y, x) if opaque(f[q]) and not dark(f[q])]
                        mine = sum(hair[q] for q in near)
                        if mine >= 2 and mine * 2 >= len(near):
                            lines[y, x] = True
        return hair | lines, beard

    def _steady(self, found):
        """Hair below the eyes that no other step of the same walk has nearby (a buckle that touches
        the hair in one frame only) stays with the body: as hair it would flicker in the hair colour."""
        steps = self.sheet.shape[1] // F
        for (row, col), (take, beard) in list(found.items()):
            head = self.heads[row, col]
            seen = np.zeros((F, F), bool)
            for c in range(steps):
                if c == col:
                    continue
                other, dy = found[row, c][0], self.heads[row, c].top - head.top
                for y in range(F):
                    if 0 <= y + dy < F:
                        seen[y] |= other[y + dy]
            lone = take & ~grow(seen) if steps > 1 else np.zeros((F, F), bool)
            lone[:head.brow + 2] = False
            # Whole clumps only: a lock's tip swaying a pixel stays hair.
            f = frame(self.sheet, row, col)
            while lone.any():
                clump = flood(f, [tuple(np.argwhere(lone)[0])], lambda p: True, lone, diagonal=True)
                lone &= ~clump
                if clump.sum() >= 3:
                    take = take & ~clump
            found[row, col] = (take, beard)

    def _cut(self, row, col, take, beard):
        """Moves the hair to the hair layer and draws the bald head and what the hair hid."""
        f = frame(self.sheet, row, col)
        body = frame(self.body, row, col)
        head = self.heads[row, col]
        frame(self.hair, row, col)[take] = f[take]
        body[take] = 0
        if self.tuft != 4:
            # A bun's hair tie and highlights don't count as hair: clear whatever is left above the skull.
            body[:max(0, int(head.cy - head.ry) - 1)] = 0
        self._scalp(body, head, mask(f, opaque))
        self._patch(body, head, take, row, col)
        self._tidy(body, take)
        if self.beard:
            # A beard: hair-coloured pixels in the face's lower half and all that hangs from them (not
            # a hand that wanders past). It stays on the body (copied) and takes the hair colour from
            # the locks layer.
            mid = (head.face[0] + head.face[1]) / 2 if head.face else head.cx
            core = [(y, x) for y in range(head.brow + 3, head.brow + 7) for x in range(F)
                    if beard[y, x] and abs(x - mid) <= 3 and lockish(f[y, x])]
            locks = flood(f, core, lockish, beard, diagonal=True)
            frame(self.locks, row, col)[locks] = f[locks]

    def _scalp(self, body, head, drawn):
        """Draws the bare skull round the face, shaded, with an outline, and joins the ears to it,
        inside the sprite as drawn (`drawn`): the skull is rounder than a face seen from the side or
        a cheek seen from the front, and painted past them it stuck out like a heavy brow ridge or a
        lump of an ear (playtesting 2026-10-19)."""
        light, shade = mix(self.skin, (1, 1, 1), 0.25), self.skin * 0.82
        painted = np.zeros((F, F), bool)

        def paint(x, y):
            lit = (x - head.cx) / head.half - (head.cy - y) / head.ry * 0.7
            body[y, x, :3] = light if lit < -0.6 else (shade if lit > 0.45 else self.skin)
            body[y, x, 3] = 1
            painted[y, x] = True

        for y in range(F):
            for x in range(F):
                if drawn[y, x] and head.inside(x, y) and not (y >= head.brow and opaque(body[y, x])):
                    paint(x, y)               # above the face, or round it where hair used to be
        # Ears (skin left beside the skull): bridge each one back to the head.
        for y in range(head.brow - 4, head.brow + 3):
            for x in range(F):
                if is_skin(body[y, x]) and not head.inside(x, y, 0.5):
                    step = 1 if x < head.cx else -1
                    xx = x + step
                    while 0 <= xx < F and not painted[y, xx] and not head.inside(xx, y) and abs(xx - x) < 6:
                        if drawn[y, xx] and (not opaque(body[y, xx]) or dark(body[y, xx])):
                            paint(xx, y)
                        xx += step
        # Specks left floating where the hair was (an ear tip's outline): gone.
        for y in range(F):
            for x in range(F):
                if opaque(body[y, x]) and not painted[y, x] and y < head.brow and not any(
                        opaque(body[q]) for q in neighbours8(y, x)):
                    body[y, x, 3] = 0
        outline(body, painted, drawn)

    def _patch(self, body, head, taken, row, col):
        """Fills what the hair used to hide below the head (a long-haired back, the shoulders) with
        the same part of the template's body; anything outside it becomes see-through."""
        if self.template is None:
            return
        holes = taken & np.array([[not opaque(body[y, x]) for x in range(F)] for y in range(F)])
        holes[:head.cy + 1] = False
        if not holes.any():
            return
        t = frame(self.template.body, row, col)
        dx = int(round(centre_x(body) - centre_x(t)))
        dy = feet(body) - feet(t)
        if not hasattr(self, "_outfit_to"):
            # The template's outfit and skin, shade for shade in this sheet's own colours.
            self._outfit_to = shade_map(colours(self.template.body, is_outfit), colours(self.sheet, is_outfit))
            self._skin_to = shade_map(colours(self.template.body, is_skin), colours(self.sheet, is_skin))
        for y, x in zip(*np.nonzero(holes)):
            ty, tx = y - dy, x - dx
            if not (0 <= ty < F and 0 <= tx < F) or not opaque(t[ty, tx]):
                continue
            p = t[ty, tx]
            body[y, x, :3] = self._outfit_to(p[:3]) if is_outfit(p) else self._skin_to(p[:3]) if is_skin(p) else p[:3]
            body[y, x, 3] = 1

    def _tidy(self, body, taken):
        """Bits the hair leaves floating (a braid's outline, a lock's shadow): small pieces near
        where the hair was that no longer touch the body."""
        solid = mask(body, opaque)
        near = grow(taken, 2)
        seen = np.zeros((F, F), bool)
        for y, x in zip(*np.nonzero(solid & near)):
            if seen[y, x]:
                continue
            piece = flood(body, [(y, x)], lambda p: True, solid, diagonal=True)
            seen |= piece
            if piece.sum() <= 12 and not (piece & ~near).any():
                body[piece] = 0


def mix(c, d, t):
    return np.clip(np.array(c[:3]) * (1 - t) + np.array(d[:3]) * t, 0, 1)


def outline(img, painted, inside=None):
    """A dark line round what was painted: on the pixels just outside it, or, given `inside` (the
    sprite as drawn), on its own edge where it meets the outside, so it never grows past the drawing."""
    if inside is not None:
        edge = [(y, x) for y in range(F) for x in range(F) if painted[y, x] and any(
            not (0 <= q[0] < F and 0 <= q[1] < F) or not inside[q]
            for q in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)))]
        for y, x in edge:
            img[y, x, :3] = OUTLINE
    for y in range(F):
        for x in range(F):
            if painted[y, x] or opaque(img[y, x]) or (inside is not None and not inside[y, x]):
                continue
            if any(painted[q] for q in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1))
                   if 0 <= q[0] < F and 0 <= q[1] < F):
                img[y, x, :3] = OUTLINE
                img[y, x, 3] = 1


def centre_x(f):
    xs = [x for y in range(F) for x in range(F) if is_outfit(f[y, x])]
    return sum(xs) / len(xs) if xs else F / 2


def feet(f):
    return max(y for y in range(F) if any(opaque(f[y, x]) for x in range(F)))


def style_source(race):
    """A race's own hair, ready to move onto other heads: where an elf's ears poked through it, the
    gaps are filled with the hair round them."""
    out = race.hair.copy()
    if race.id not in EARED:
        return out
    for (row, col) in race.heads:
        o = frame(out, row, col)
        gaps = grow(race.ears[row, col])
        for _ in range(3):
            fill = []
            for y, x in zip(*np.nonzero(gaps & (o[:, :, 3] < 0.5))):
                near = [o[q] for q in neighbours8(y, x) if o[q][3] >= 0.5]
                if len(near) >= 3:
                    fill.append((y, x, sorted(near, key=lambda p: p[:3] @ LUMA)[len(near) // 2]))
            for y, x, p in fill:
                o[y, x] = p
    return out


def colours(img, test):
    """Every pixel of `img` that passes `test`, as RGB rows."""
    return np.array([p[:3] for p in img.reshape(-1, 4) if test(p)])


def shade_map(src, dst):
    """Takes a colour from `src` (RGB rows) to `dst`'s colour at the same rank of brightness."""
    ranks = np.sort(src @ LUMA)
    shades = dst[np.argsort(dst @ LUMA, kind="stable")]

    def to(c):
        q = np.searchsorted(ranks, c @ LUMA) / max(1, len(ranks) - 1)
        return shades[min(len(shades) - 1, int(round(q * (len(shades) - 1))))]
    return to


def crown_colours(race):
    """The colours of the hair on top of the head (crown to brow, every frame): what every style has,
    unlike a long style's shadowy back."""
    rows = []
    for (row, col), head in race.heads.items():
        hair = frame(race.hair, row, col)
        rows += [hair[y, x, :3] for y in range(head.top, head.brow) for x in range(F) if opaque(hair[y, x])]
    return np.array(rows)


def dyeable(p):
    """In appearance.json's `hairLayer` window, so every hair colour reaches it."""
    h, s, v = hsv(p)
    low, high = HAIR_LAYER["hue"]
    hue = low <= h * 360 <= high if low <= high else (h * 360 >= low or h * 360 <= high)
    return hue and s >= HAIR_LAYER["minSaturation"] and v >= HAIR_LAYER["minValue"]


def recolour_to(layer, source, target):
    """Paints a moved hairstyle in the target sheet's own hair colours: each pixel takes the target's
    colour at the rank of brightness it has on the source, crown matched to crown, so the shading
    stays and one head has one hair colour. A shade no hair dye reaches (the skin showing through the
    target's crown, which the palest tips took, so they stayed pink when dyed) gives way to the
    nearest in brightness that one does; the near-black outline stays, as it's dark whatever the dye."""
    crown = crown_colours(target)
    to = shade_map(crown_colours(source), crown)
    reachable = np.array([c for c in crown if dyeable(c)])
    out = layer.copy()
    for y, x in zip(*np.nonzero(layer[:, :, 3] > 0.5)):
        c = to(layer[y, x, :3])
        if not dyeable(c) and hsv(c)[2] >= HAIR_LAYER["minValue"]:
            c = reachable[np.argmin(np.abs(reachable @ LUMA - c @ LUMA))]
        out[y, x, :3] = c
    return out


def fit_hair(layer, source, target):
    """A style (`layer`, the source race's hair from style_source) moved frame by frame onto the
    target's head: lined up by the skull's middle and the brow, kept off the face from the eyes
    down, open where an elf's ears poke through, in the target's own hair colours."""
    out = np.zeros_like(target.sheet)
    for (row, col), head in target.heads.items():
        src = source.heads[row, col]
        dx = int(round(head.cx - src.cx))
        dy = head.brow - src.brow
        clear = target.faces[row, col].copy()
        clear[:head.brow + 2] = False
        clear |= target.ears[row, col]
        s = frame(layer, row, col)
        o = frame(out, row, col)
        for y, x in zip(*np.nonzero(s[:, :, 3] > 0.5)):
            ty, tx = y + dy, x + dx
            if 0 <= ty < F and 0 <= tx < F and not clear[ty, tx]:
                o[ty, tx] = s[y, x]
    return recolour_to(out, source, target)


def marker(v, s=0.6):
    return np.array(colorsys.hsv_to_rgb(MARK_HUE, s, v))



def headgear(race, kind):
    """A hood or helmet hugging the bare head, face left open, in marker colours."""
    out = np.zeros_like(race.sheet)
    hood = kind == "hood"
    grow = 1.6 if hood else 1.0
    for (row, col), head in race.heads.items():
        o = frame(out, row, col)
        body = frame(race.body, row, col)
        chin = head.brow + (5 if hood else 3)
        top = head.cy - head.ry - grow
        side = {"right": 1, "left": -1}.get(head.facing, 0)
        painted = np.zeros((F, F), bool)
        for y in range(F):
            for x in range(F):
                if y > chin:
                    continue
                inside = head.inside(x, y, grow) if y <= head.cy else abs(x - head.cx) <= head.half + grow - 0.5
                if not inside or y < top:
                    continue
                if y >= head.brow and head.facing != "up":
                    face = head.face or (int(head.cx) - 2, int(head.cx) + 2)
                    if side == 0 and face[0] <= x <= face[1]:
                        continue              # the face stays open
                    if side and (x - (face[0] if side > 0 else face[1])) * side >= 0:
                        continue
                lit = (x - head.cx) / (head.half + grow) - (head.cy - y) / (head.ry + grow) * 0.8
                v = 0.92 if lit < -0.55 else (0.45 if lit > 0.55 else 0.7)
                o[y, x, :3] = marker(v)
                o[y, x, 3] = 1
                painted[y, x] = True
        # A darker fold where it meets the face; a point at the back of a hood.
        for y in range(F):
            for x in range(F):
                if painted[y, x] and y >= head.brow - 1 and head.facing != "up" and any(
                        not painted[q] and opaque(body[q]) for q in ((y, x - 1), (y, x + 1), (y + 1, x))
                        if 0 <= q[1] < F and q[0] < F):
                    o[y, x, :3] = marker(0.4) if hood else marker(0.9, 1.0)
        if hood:
            tip_x = int(np.floor(head.cx - 2.5 * side + 0.5))
            tip_y = int(np.ceil(top)) - 1
            if 0 <= tip_y < F and 0 <= tip_x < F:
                o[tip_y, tip_x, :3] = marker(0.7)
                o[tip_y, tip_x, 3] = 1
                painted[tip_y, tip_x] = True
        else:
            # Trim: a band along the brow and a crest over the top.
            ridge = int(np.floor(head.cx - side + 0.5))
            for y in range(F):
                if painted[y, ridge] and y < head.brow - 1:
                    o[y, ridge, :3] = marker(0.9, 1.0)
            if head.facing != "up":
                for x in range(F):
                    if painted[head.brow - 1, x]:
                        o[head.brow - 1, x, :3] = marker(0.9, 1.0)
        outline(o, painted)
    return out


def build():
    races_json = json.load(open(ROOT / "content" / "classes.json"))["races"]
    races = {}
    # The human body patches what long hair hid on the other races' backs; a gender's sheet is
    # patched from its own race's.
    human = next(r for r in races_json if r["id"] == "human")
    races["human"] = Race("human", human.get("art") or "player_walk")
    for r in races_json:
        if r["id"] not in races:
            races[r["id"]] = Race(r["id"], r.get("art") or "player_walk", template=races["human"], sidehair=True)
    for r in races_json:
        for gender, sheet in (r.get("sheets") or {}).items():
            races[f"{r['id']}_{gender}"] = Race(r["id"], sheet, template=races[r["id"]], sidehair=True)
    # Where each style comes from: a body above, or a sheet kept only for its hair.
    by_sheet = {race.sheet_id: race for race in races.values()}
    for race_id, sheet in STYLES.values():
        if sheet not in by_sheet:
            by_sheet[sheet] = Race(race_id, sheet, template=races[race_id], sidehair=True)
    sources = {style: (by_sheet[sheet], style_source(by_sheet[sheet])) for style, (_, sheet) in STYLES.items()}
    layers = {}
    for rid, race in races.items():
        layers[f"body_{rid}"] = race.body
        layers[f"locks_{rid}"] = race.locks
        layers[f"hood_{rid}"] = headgear(race, "hood")
        layers[f"helmet_{rid}"] = headgear(race, "helmet")
        for style, (source, hair) in sources.items():
            layers[f"hair_{style}_{rid}"] = hair_edge(race.hair if source is race else fit_hair(hair, source, race),
                                                      race.body)
            layers[f"nape_{style}_{rid}"] = nape(layers[f"hair_{style}_{rid}"], race.body)
    for body, (race_id, sheet) in TOWNSFOLK.items():
        folk = Race(race_id, sheet, template=races[race_id], sidehair=True)
        layers[f"body_{body}"] = folk.body
        layers[f"locks_{body}"] = folk.locks
        layers[f"hair_{body}"] = hair_edge(folk.hair, folk.body)
    return races, layers


def hair_edge(hair, body):
    """The hair's outer edge (where neither it nor the body is drawn beyond it) in a deep shade of its own
    colour, as RD outlines everything else: RD drew the ginger's top edge bright, as lit, and dyed purple
    or blue on a dark battle field it read as no outline at all (playtesting 2026-10-23). Kept inside
    the dye's window (`hairLayer`), so a dye turns it a deep shade of the new colour."""
    out = hair.copy()
    solid = (hair[..., 3] > 0.5) | (body[..., 3] > 0.5)
    H, W = solid.shape
    for y, x in zip(*np.nonzero(hair[..., 3] > 0.5)):
        if not any(not (0 <= y + dy < H and 0 <= x + dx < W) or not solid[y + dy, x + dx]
                   or (y + dy) // F != y // F or (x + dx) // F != x // F
                   for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1))):
            continue
        h, s_, v = hsv(hair[y, x])
        if v < 0.4:
            continue                        # dark already
        out[y, x, :3] = colorsys.hsv_to_rgb(h, min(1.0, s_ * 1.15 + 0.06), max(0.2, v * 0.48))
    return out


def nape(hair, body):
    """The hair from NAPE of the way down the head (the body's top row to its feet) and below."""
    out = hair.copy()
    for row in range(body.shape[0] // F):
        for col in range(body.shape[1] // F):
            rows = np.nonzero((body[row * F:(row + 1) * F, col * F:(col + 1) * F, 3] > 0.5).any(1))[0]
            if len(rows) == 0:
                continue
            cut = rows[0] + int(round((rows[-1] - rows[0]) * NAPE))
            out[row * F:row * F + cut, col * F:(col + 1) * F] = 0
    return out


def to_image(a):
    return Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "RGBA")


def stack(*layers):
    out = to_image(layers[0])
    for layer in layers[1:]:
        out.alpha_composite(to_image(layer))
    return np.asarray(out).astype(float) / 255


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--preview", help="write a contact sheet here instead of the PNGs")
    args = parser.parse_args()
    races, layers = build()
    if not args.preview:
        for name, layer in layers.items():
            to_image(layer).save(ROOT / "art" / "sprites" / f"{name}.png")
        print(f"wrote {len(layers)} layers to art/sprites/: {', '.join(sorted(layers))}")
        return
    zoom = 3
    combos = ["body"] + [f"hair_{s}" for s in STYLES] + ["hood", "helmet"]
    sheet = Image.new("RGB", (len(combos) * 4 * F * zoom, len(races) * F * zoom), (80, 130, 80))
    for r, (rid, race) in enumerate(races.items()):
        for k, name in enumerate(combos):
            under = (layers[f"body_{rid}"], layers[f"locks_{rid}"])
            img = stack(*under) if name == "body" else stack(*under, layers[f"{name}_{rid}"])
            im = to_image(img)
            for c, row in enumerate((2, 1, 0, 3)):
                fr = im.crop((0, row * F, F, row * F + F)).resize((F * zoom, F * zoom), Image.NEAREST)
                sheet.paste(fr, ((k * 4 + c) * F * zoom, r * F * zoom), fr)
    sheet.save(args.preview)
    print(f"wrote {args.preview}: columns {', '.join(combos)}; rows {', '.join(races)}")


if __name__ == "__main__":
    main()
