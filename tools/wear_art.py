#!/usr/bin/env python3
"""Worn gear from Retro Diffusion sheets (art-variants/), made ready for the game in code.

    python3 tools/wear_art.py                  # writes the PNGs below
    python3 tools/wear_art.py --sheet out.png  # also a contact sheet to look at

Armour that wears a whole walk sheet of its own (items.json `sheets`, like Iron Plate's) is a sheet
Retro Diffusion drew per race, copied from the variant picked below, its main material brought to
one colour on every race (MATERIAL), so it looks the same on all of them and a tier's `tint` lands on
the same colour everywhere.

    art/sprites/armor_mage_robe_<race>.png    the blue hooded robe and pointed hood
    art/sprites/armor_chain_mail_<race>.png   chain mail with its coif over the hair

Festive hats and masks are cut out of a sheet of a hero wearing one, a frame per way they face (rows
up, right, down, left; 48 × 192), and moved so the game can fit them to any head
(GearOverlay.hat, tools/gear_preview.py `hat`):

    art/sprites/wear_<hat>.png   crown, santa, ears: the band round the head on row HAT_BRIM,
                                 centred on column ANCHOR_X
    art/sprites/wear_mask.png    the Halloween mask: its eye holes' top row on ANCHOR_Y, centred on
                                 ANCHOR_X between them (from the side, its front eye hole there);
                                 none from behind
    art/sprites/wear_scarf.png   the Christmas scarf: its wearer's chin (the face's bottom row, as
                                 gear_preview.face finds it; from behind, the front's) on CHIN_Y, the
                                 middle of the figure at the shoulders (0.38 of the way down from the
                                 top of the head to the feet) on ANCHOR_X
    art/sprites/wear_cape.png    a status cape: its wearer's shoulders on SHOULDER_Y, the middle of
                                 the figure there on ANCHOR_X, stretched to CAPE_DROP rows from the
                                 shoulders to the feet and CAPE_SPAN pixels across the shoulders, so
                                 the game stretches it to any body (GearOverlay.drape)

Needs pillow + numpy.
"""
import argparse
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from palette_preview import hsv2rgb, rgb2hsv  # noqa: E402

VARIANTS = ROOT / "art-variants"
SPRITES = ROOT / "art" / "sprites"
RACES = ("human", "elf", "dwarf")

# The variant each sheet is made from (2026-10-19). The robe was rerolled until the kid had no
# beard: a prompt with "wizard" in it drew one every time.
ARMOUR = {
    "armor_mage_robe_human": "pilot_mage_robe_human_v4/20261019-115504_0.png",
    "armor_mage_robe_elf": "pilot_mage_robe_elf_v3/20261019-115524_0.png",
    "armor_mage_robe_dwarf": "pilot_mage_robe_dwarf/20261019-115017_0.png",
    "armor_chain_mail_human": "pilot_chain_mail_human/20261019-113735_0.png",
    "armor_chain_mail_elf": "pilot_chain_mail_elf/20261019-115042_0.png",
    "armor_chain_mail_dwarf": "pilot_chain_mail_dwarf/20261019-115104_0.png",
    # The hide cloaks' hood (2026-10-23; drawn in code as a smooth dome with a spike till then): a
    # hero in a blue fur-lined hood, only its hat kept (HAT_ONLY), blue so recolouring it into the
    # nine hide colours (items.json `tint`) leaves the face in it alone.
    "armor_hide_hood_human": "pilot_hide_hood_human/20261023-065741_0.png",
    "armor_hide_hood_elf": "pilot_hide_hood_elf/20261023-065810_0.png",
    "armor_hide_hood_dwarf": "pilot_hide_hood_dwarf/20261023-065930_0.png",
} | {f"armor_{kind}_{race}": f"legacy/armor_{kind}_{race}.png"   # drawn before these notes were kept
     for kind in ("iron_plate", "dragon_mail", "snow_cloak", "ranger_cloak") for race in RACES}
# Each armour's main material brought to one colour on every race (Retro Diffusion draws each race's
# sheet a shade apart: the dwarf's robe much brighter, its plate greener and darker): the pixels in
# `hue` (degrees, saturation from `min` to `max`) turned to the target hue, their saturation and value
# bent (a power, so black and white stay put and the shading keeps its shape) until their middles are
# the target's (None: as drawn). Only these pixels change: skin, hair, leather and trim keep each
# sheet's own. Steel is greyish (`max`), so a tunic in navy doesn't count as mail; the snow cloak
# keeps each sheet's whiteness, as the dwarf's is mostly white fur. `even`: saturation and value scaled
# evenly instead: the elf's hood is blue at 0.95, and bent down to 0.6 its paler blues went near white
# (a white patch on the crown that no hide's `tint` could reach, being under its minSaturation).
MATERIAL = {
    "mage_robe": dict(hue=(170, 260), min=0.2, to=(222, 0.80, 0.50)),
    "chain_mail": dict(hue=(100, 280), min=0.0, max=0.4, to=(210, 0.20, 0.40)),
    "iron_plate": dict(hue=(140, 260), min=0.03, to=(205, 0.28, 0.45)),
    "dragon_mail": dict(hue=(330, 20), min=0.3, to=(2, 0.85, 0.85)),
    "snow_cloak": dict(hue=(150, 260), min=0.03, to=(202, None, None)),
    "ranger_cloak": dict(hue=(60, 170), min=0.15, to=(110, 0.56, 0.33)),
    "hide_hood": dict(hue=(180, 260), min=0.2, to=(215, 0.60, 0.55), even=True),
}

F = 48
HAT_BRIM, ANCHOR_X, ANCHOR_Y = 40, 24, 20
# The worn piece in each reference, by its colours: (variant, which pixels are the piece).
WEAR = {
    "crown": ("ref_party_crown/20261019-115136_0.png", lambda h, s, v: s > 0.45 and (h < 20 or h > 330) and v > 0.3),
    "santa": ("ref_santa_hat/20261019-113809_0.png",
              lambda h, s, v: (s > 0.45 and (h < 20 or h > 330) and v > 0.3) or (s < 0.22 and v > 0.62)),
    "ears": ("ref_bunny_ears/20261019-115203_0.png",
             lambda h, s, v: (s < 0.25 and v > 0.6) or (s > 0.2 and v > 0.5 and (h > 290 or h < 15))),
    "mask": ("ref_halloween_mask/20261019-113847_0.png", lambda h, s, v: 60 <= h <= 110 and s > 0.2 and v > 0.45),
    "scarf": ("ref_christmas_scarf/20261019-115247_0.png",
              lambda h, s, v: (s > 0.45 and (h < 20 or h > 330) and v > 0.3) or (s < 0.2 and v > 0.75)),
    "cape": ("ref_cape/20261019-115231_0.png", lambda h, s, v: s > 0.5 and (h < 12 or h > 330) and v < 0.97),
}
# Every hero's eyes are six pixels apart from the front, the reference mask's holes five.
MASK_WIDEN = 1
SHOULDER_Y, CAPE_DROP, CAPE_SPAN = 24, 20, 14
CHIN_Y = 20   # where the wearer's chin goes for a scarf


def load(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(float) / 255


def save(img, name):
    Image.fromarray((np.clip(img, 0, 1) * 255).round().astype(np.uint8), "RGBA").save(SPRITES / f"{name}.png")


def material(img, hue, min, to, max=1.0, even=False):
    """`img` with its main material (MATERIAL) brought to the colour `to` (hue, saturation, value).
    Repeated till it settles: turning the hue moves a few pixels in or out of the material's range."""
    lo, hi = hue
    out = img.copy()
    for _ in range(6):
        h, s, v = rgb2hsv(out[..., :3])
        m = (out[..., 3] > 0) & (s >= min) & (s <= max) & (v > 0.12) & (((h >= lo) & (h <= hi)) if lo <= hi else ((h >= lo) | (h <= hi)))
        if not m.any():
            break
        mean = np.degrees(np.angle(np.exp(1j * np.radians(h[m])).mean()))
        middle = mean + np.median((h[m] - mean + 180) % 360 - 180)   # the median, round the circle
        turn = (to[0] - middle + 180) % 360 - 180
        def bend(x, target):
            if target is None:
                return x
            if even:
                return np.clip(x * target / np.clip(np.median(x), 1e-4, 1), 0, 1)
            return np.clip(x, 1e-4, 1) ** (np.log(target) / np.log(np.clip(np.median(x), 1e-4, 0.9999)))
        if abs(turn) < 1 and all(t is None or abs(np.median(x) - t) < 0.01 for x, t in ((s[m], to[1]), (v[m], to[2]))):
            break
        out[..., :3][m] = hsv2rgb((h[m] + turn) % 360, bend(s[m], to[1]), bend(v[m], to[2]))
    return out


# Armour whose walk sheet leaves the head bare, the hero's own head, beard and hair drawn over it
# (`head_<body>`, GameSession.layers; items.json `bareHead`): the hat slot is what goes on the head
# (playtesting 2026-10-21: "the chain mail shouldn't have a hat. We have a specific hat slot", and
# "any armor that shows a hat should have that as a hat item"). What's cut off is that hat:
# `hat_<kind>_<race>`, the sheet's head down to the neck (helmet, hood or coif, and the face in it),
# worn by the matching hat item (items.json `headgear`).
BARE_HEADED = {"chain_mail", "iron_plate", "dragon_mail", "mage_robe", "ranger_cloak", "snow_cloak", "hide_hood"}
# Sheets drawn only for their hat: the body under it is the hero's own, so it isn't kept.
HAT_ONLY = {"hide_hood"}
# Heroes' bodies (tools/hero_layers.py), each race's: its own and its other gender's.
BODIES = {race: [race] + [f"{race}_{g}" for g in ("male", "female") if (SPRITES / f"body_{race}_{g}.png").exists()]
          for race in RACES}


def neck(frame):
    """The row a figure's head ends on: its narrowest row from 6 to 19 below its top (the lowest
    of them if two are as narrow), between the head and the shoulders."""
    a = frame[..., 3] > 0.5
    top = np.nonzero(a.any(1))[0].min()
    widths = {y: int(a[y].sum()) for y in range(top + 6, min(top + 20, F))}
    return min(widths, key=lambda y: (widths[y], -y))


def tunic(frame):
    """A bare body's own tunic (green on every race's sheet, appearance.json recolours it), which a
    head layer leaves out: in a side view an arm or a shoulder reaches up past the neck."""
    h, s, v = rgb2hsv(frame[..., :3])
    return (frame[..., 3] > 0.5) & (h >= 70) & (h <= 170) & (s > 0.25)


def heads():
    """`head_<body>`: each body's bald head down to its neck, for armour that leaves it bare."""
    for bodies in BODIES.values():
        for body in bodies:
            sheet = load(SPRITES / f"body_{body}.png")
            out = np.zeros_like(sheet)
            for row in range(sheet.shape[0] // F):
                for col in range(sheet.shape[1] // F):
                    f = sheet[row * F:(row + 1) * F, col * F:(col + 1) * F]
                    if not (f[..., 3] > 0.5).any():
                        continue
                    keep = np.zeros((F, F), bool)
                    keep[:neck(f) + 1] = True
                    keep &= ~tunic(f)
                    out[row * F:(row + 1) * F, col * F:(col + 1) * F][keep] = f[keep]
            save(out, f"head_{body}")
            print(f"art/sprites/head_{body}.png  from body_{body}.png")


def bared(img, race):
    """An armour sheet with its head cut off, and what's cut off (its hat): everything above the
    highest neck of the race's bodies, so whichever body wears it, its head (`head_<body>`, down to
    its own neck) meets it."""
    out = img.copy()
    hat = np.zeros_like(img)
    bodies = [load(SPRITES / f"body_{body}.png") for body in BODIES[race]]
    for row in range(img.shape[0] // F):
        for col in range(img.shape[1] // F):
            frames = [b[row * F:(row + 1) * F, col * F:(col + 1) * F] for b in bodies]
            cut = min(neck(f) for f in frames if (f[..., 3] > 0.5).any())
            hat[row * F:row * F + cut + 1, col * F:(col + 1) * F] = img[row * F:row * F + cut + 1, col * F:(col + 1) * F]
            out[row * F:row * F + cut + 1, col * F:(col + 1) * F] = 0
    return out, hat


def armour():
    made = {}
    for name, source in ARMOUR.items():
        img = load(VARIANTS / source)
        kind = name[len("armor_"):name.rindex("_")]
        img = material(img, **MATERIAL[kind])
        if kind in BARE_HEADED:
            img, hat = bared(img, name[name.rindex("_") + 1:])
            save(hat, "hat_" + name[len("armor_"):])
            print(f"art/sprites/hat_{name[len('armor_'):]}.png  its hat")
        if kind in HAT_ONLY:
            continue
        save(img, name)
        made[name] = img
        print(f"art/sprites/{name}.png  from art-variants/{source}")
    return made


def piece(frame, kind):
    """The worn piece in one frame of a reference: the biggest patch (8-connected) of its colours in
    the figure's top fifteen rows, so an eye's white or a shoe's shine stays out, with what's drawn
    round it. A Santa hat is everything from the top of the head down to its fur brim and the outline
    under it, as it covers its wearer's whole head top; a mask is, row by row, all that's drawn
    between its outermost pixels and their outline (eye holes and grin); a crown or ears are the patch
    and the dark pixels round it (their outline, and their shading where it's dark)."""
    a = frame[..., 3] > 0.5
    if not a.any():
        return None
    h, s, v = rgb2hsv(frame[..., :3])
    test = WEAR[kind][1]
    core = np.array([[a[y, x] and test(h[y, x], s[y, x], v[y, x]) for x in range(F)] for y in range(F)])
    top = np.nonzero(a.any(1))[0].min()
    if kind == "scarf":     # round the neck
        core[:top + 9] = False
        core[top + 26:] = False
    elif kind != "cape":    # on the head
        core[top + 15:] = False
    seen, best, patches = np.zeros_like(core), [], []
    for y0, x0 in zip(*np.nonzero(core)):
        if seen[y0, x0]:
            continue
        stack, patch = [(y0, x0)], []
        seen[y0, x0] = True
        while stack:
            y, x = stack.pop()
            patch.append((y, x))
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    q = (y + dy, x + dx)
                    if 0 <= q[0] < F and 0 <= q[1] < F and core[q] and not seen[q]:
                        seen[q] = True
                        stack.append(q)
        patches.append(patch)
        if len(patch) > len(best):
            best = patch
    if kind == "cape":  # from the front it shows either side of its wearer: every big patch
        best = [q for patch in patches if len(patch) >= max(6, len(best) / 6) for q in patch]
    if len(best) < 8:
        return None
    ys, xs = np.array([y for y, _ in best]), np.array([x for _, x in best])
    keep = np.zeros_like(core)
    if kind == "santa":
        fur = [y for y, x in best if s[y, x] < 0.22]
        bottom = max(fur) if fur else ys.max()
        if bottom + 1 < F and any(a[bottom + 1, x] and v[bottom + 1, x] < 0.3 for x in range(xs.min(), xs.max() + 1)):
            bottom += 1
        keep[:bottom + 1, max(0, xs.min() - 1):xs.max() + 2] = a[:bottom + 1, max(0, xs.min() - 1):xs.max() + 2]
    elif kind == "mask":
        rows = {}
        for y, x in best:
            rows.setdefault(y, []).append(x)
        for y in range(max(0, ys.min() - 1), min(F, ys.max() + 2)):
            run = rows[min(ys.max(), max(ys.min(), y))]
            keep[y, max(0, min(run) - 1):min(F, max(run) + 2)] = a[y, max(0, min(run) - 1):min(F, max(run) + 2)]
    elif kind == "cape":
        return closed(frame, best)
    else:
        for y, x in best:
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    q = (y + dy, x + dx)
                    if 0 <= q[0] < F and 0 <= q[1] < F and a[q] and (v[q] < 0.35 or (dy, dx) == (0, 0)):
                        keep[q] = True
    out = np.zeros_like(frame)
    out[keep] = frame[keep]
    return out


OUTLINE = (0.10, 0.09, 0.11)   # neutral, so painting a cape in its colour leaves it be


def grown(m):
    """`m` and every pixel next to it (8 ways)."""
    out = m.copy()
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            out |= np.roll(np.roll(m, dy, 0), dx, 1)
    return out


def closed(frame, cells):
    """A cape as its own pixels only (not the wearer's clothes beside it), its gaps closed (where the
    reference's arm crossed it: grown a pixel and shrunk back, and any hole it encloses filled, each
    new pixel the colour of the nearest of its own) and outlined afresh."""
    own = np.zeros((F, F), bool)
    for y, x in cells:
        own[y, x] = True
    shut = ~grown(~grown(own))
    outside = np.zeros((F, F), bool)   # the clear pixels reachable from the frame's edge
    stack = [(y, x) for y in range(F) for x in (0, F - 1)] + [(y, x) for x in range(F) for y in (0, F - 1)]
    while stack:
        y, x = stack.pop()
        if 0 <= y < F and 0 <= x < F and not outside[y, x] and not shut[y, x]:
            outside[y, x] = True
            stack += [(y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)]
    shut = ~outside
    out = np.zeros_like(frame)
    out[own] = frame[own]
    near = list(zip(*np.nonzero(own)))
    for y, x in zip(*np.nonzero(shut & ~own)):
        ny, nx = min(near, key=lambda q: (q[0] - y) ** 2 + (q[1] - x) ** 2)
        out[y, x] = frame[ny, nx]
    edge = ~shut & (np.roll(shut, 1, 0) | np.roll(shut, -1, 0) | np.roll(shut, 1, 1) | np.roll(shut, -1, 1))
    out[edge, :3] = OUTLINE
    out[edge, 3] = 1
    return out


def bbox(t):
    ys, xs = np.nonzero(t[..., 3] > 0.5)
    return ys.min(), ys.max(), xs.min(), xs.max()


def widen(t, by, keep_top=0):
    """Pixel-art stretch: repeat (or drop) `by` columns through the middle of the piece's rows from
    `keep_top` down (so a pom over it keeps its shape), spread a little either side. The game does
    the same (GearOverlay.widen), to fit a hat to the head."""
    if by == 0:
        return t
    cols = [x for x in range(F) if (t[keep_top:, x, 3] > 0.5).any()]
    if not cols:
        return t
    l, r = min(cols), max(cols)
    out = t.copy()
    out[keep_top:] = 0
    body = t[keep_top:, l:r + 1]
    for k in range(abs(by)):
        m = body.shape[1] // 2 + (k % 3 - 1)
        body = np.concatenate([body[:, :m + 1], body[:, m:]], 1) if by > 0 else np.concatenate([body[:, :m], body[:, m + 1:]], 1)
    x0 = int(np.floor((l + r) / 2 - (body.shape[1] - 1) / 2 + 0.5))
    for i in range(body.shape[1]):
        if 0 <= x0 + i < F:
            out[keep_top:, x0 + i] = body[:, i]
    return out


def mirrored_fuller_side(t):
    """A cape from the front, the same either side of its wearer: the side of ANCHOR_X with more of
    it, mirrored onto the other. Its reference held an arm across one side, so that panel stopped
    short of the shoulder, its hem a row off the other's (playtesting 2026-10-21: "off-pixel,
    showing a gap"). The middle is behind the body."""
    xs = np.arange(F)
    left = (t[:, xs < ANCHOR_X, 3] > 0.5).sum()
    right = (t[:, xs > ANCHOR_X, 3] > 0.5).sum()
    out = t.copy()
    for x in range(F):
        source = 2 * ANCHOR_X - x
        if (x < ANCHOR_X) == (right >= left) and 0 <= source < F:
            out[:, x] = t[:, source]
    return out


def holes(t):
    """The mask's eye holes: dark pixels with the mask on both sides and above, as (their top row,
    [the middle column of each])."""
    _, _, v = rgb2hsv(t[..., :3])
    on = (t[..., 3] > 0.5) & (v >= 0.3)
    found = [(y, x) for y in range(F) for x in range(F)
             if t[y, x, 3] > 0.5 and v[y, x] < 0.3
             and any(on[y, x - k] for k in range(1, 4) if x - k >= 0)
             and any(on[y, x + k] for k in range(1, 4) if x + k < F)
             and any(on[y - k, x] for k in range(1, 4) if y - k >= 0)]
    if not found:
        return None
    top = min(y for y, _ in found)
    xs = sorted({x for y, x in found if y <= top + 1})
    groups = [[xs[0]]]
    for x in xs[1:]:
        (groups[-1].append(x) if x - groups[-1][-1] <= 2 else groups.append([x]))
    return top, [sum(g) / len(g) for g in groups]


def lengthened(t, by, start):
    """Pixel-art stretch down: `by` rows repeated (or dropped) through the middle of the piece's rows
    from `start` down, the rows above staying where they are (GearOverlay's Piece.lengthened)."""
    rows = [y for y in range(start, F) if (t[y, :, 3] > 0.5).any()]
    if by == 0 or not rows:
        return t
    body = [t[y] for y in range(start, max(rows) + 1)]
    for k in range(abs(by)):
        m = max(0, min(len(body) - 1, len(body) // 2 + (k % 3 - 1)))
        if by > 0:
            body.insert(m, body[m])
        elif len(body) > 1:
            body.pop(m)
    out = t.copy()
    out[start:] = 0
    for i, row in enumerate(body):
        if start + i < F:
            out[start + i] = row
    return out


def figure(frame):
    """A figure's top, feet, shoulders (0.38 of the way down) and the middle of it there, as the game
    measures a hero for a cape (GearOverlay.figure)."""
    a = frame[..., 3] > 0.5
    rows = np.nonzero(a.any(1))[0]
    top, feet = rows.min(), rows.max()
    shoulder = top + int(np.floor((feet - top) * 0.38 + 0.5))
    xs = np.nonzero(a[shoulder])[0]
    return top, feet, shoulder, xs.min(), xs.max()


def wearer_chins(sheet):
    """The bottom row of the face of the hero wearing a reference, each way they face (as the game
    finds it, gear_preview.face); from behind, the front's."""
    import gear_preview as gp
    chins = {}
    for row in range(4):
        frame = sheet[row * F:(row + 1) * F, :F].copy()
        worn = piece(frame, "scarf")
        if worn is not None:
            frame[worn[..., 3] > 0.5] = 0   # its white stripes would pass for the face
        found = gp.head(frame)
        seen = gp.face(frame, found[2], found[0], found[1]) if found else None
        if seen:
            chins[row] = seen[3]
    chins[0] = chins[2]
    return chins


def moved(t, dy, dx):
    out = np.zeros_like(t)
    ys, xs = np.nonzero(t[..., 3] > 0.5)
    for y, x in zip(ys, xs):
        if 0 <= y + dy < F and 0 <= x + dx < F:
            out[y + dy, x + dx] = t[y, x]
    return out


def wear():
    made = {}
    for kind, (source, _) in WEAR.items():
        sheet = load(VARIANTS / source)
        frames = []
        if kind == "scarf":
            chins = wearer_chins(sheet)
        for row, facing in enumerate(("up", "right", "down", "left")):
            t = piece(sheet[row * F:(row + 1) * F, :F], kind)
            if t is None or (kind == "mask" and facing == "up"):
                frames.append(np.zeros((F, F, 4)))
                continue
            t0, t1, tl, tr = bbox(t)
            if kind == "scarf":
                # Retro Diffusion drew it as a muffler up over the mouth: only what's under the chin
                # (the wrap round the neck and the ends) is kept, so it never covers a face.
                t[:chins[row] + 1] = 0
                _, _, _, left, right = figure(sheet[row * F:(row + 1) * F, :F])
                t = moved(t, CHIN_Y - chins[row], ANCHOR_X - (left + right) // 2)
            elif kind == "cape":
                _, feet, shoulder, left, right = figure(sheet[row * F:(row + 1) * F, :F])
                t = moved(t, SHOULDER_Y - shoulder, ANCHOR_X - (left + right) // 2)
                t = widen(lengthened(t, CAPE_DROP - (feet - shoulder), SHOULDER_Y), CAPE_SPAN - (right - left + 1))
                if facing == "down":
                    t = mirrored_fuller_side(t)
            elif kind == "mask":
                if facing == "down":
                    t = widen(t, MASK_WIDEN)
                top, xs = holes(t)
                x = (xs[0] + xs[-1]) / 2 if facing == "down" else max(xs) if facing == "right" else min(xs)
                t = moved(t, ANCHOR_Y - top, ANCHOR_X - int(np.floor(x + 0.5)))
            else:
                # The band round the head: the widest of the piece's lowest five rows.
                widths = {y: int((t[y, :, 3] > 0.5).sum()) for y in range(t1 - 4, t1 + 1)}
                brim = max(widths, key=lambda y: (widths[y], y))
                t = moved(t, HAT_BRIM - brim, ANCHOR_X - (tl + tr + 1) // 2)
            frames.append(t)
        img = np.concatenate(frames, 0)
        save(img, f"wear_{kind}")
        made[f"wear_{kind}"] = img
        print(f"art/sprites/wear_{kind}.png  from art-variants/{source}")
    return made


def contact(made, out):
    zoom = 3
    sheet = Image.new("RGBA", (4 * 48 * zoom, len(made) * 48 * zoom), (92, 128, 92, 255))
    for i, img in enumerate(made.values()):
        im = Image.fromarray((np.clip(img, 0, 1) * 255).round().astype(np.uint8), "RGBA")
        if img.shape[1] == F:   # a piece: one frame a row
            im = Image.fromarray(np.concatenate([np.asarray(im)] + [np.zeros_like(np.asarray(im))] * 3, 1), "RGBA")
        for j, row in enumerate((2, 1, 0, 3)):
            frame = im.crop((0, row * 48, 48, row * 48 + 48)).resize((48 * zoom, 48 * zoom), Image.NEAREST)
            sheet.alpha_composite(frame, (j * 48 * zoom, i * 48 * zoom))
    sheet.save(out)
    print(out)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--sheet", help="also write a contact sheet here")
    args = parser.parse_args()
    heads()
    made = armour() | wear()
    if args.sheet:
        contact(made, args.sheet)


if __name__ == "__main__":
    main()
