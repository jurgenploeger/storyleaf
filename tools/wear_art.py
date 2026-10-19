#!/usr/bin/env python3
"""Worn gear from Retro Diffusion sheets (art-variants/), made ready for the game in code.

    python3 tools/wear_art.py                  # writes the PNGs below
    python3 tools/wear_art.py --sheet out.png  # also a contact sheet to look at

Armour that wears a whole walk sheet of its own (items.json `sheets`, like Iron Plate's) is a sheet
Retro Diffusion drew per race, copied from the variant picked below: the robe's blue brought to one
royal blue on every race (Retro Diffusion drew the human's a little teal), so a tier's `tint` lands
on the same colour everywhere.

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
    art/sprites/wear_scarf.png   the Christmas scarf: its wearer's shoulders (0.38 of the way down
                                 from the top of the head to the feet) on SHOULDER_Y, the middle of
                                 the figure there on ANCHOR_X
    art/sprites/wear_cape.png    a status cape, the same, stretched to CAPE_DROP rows from the
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
from palette_preview import recolor, rgb2hsv  # noqa: E402  (the game's RecolorRule, in Python)

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
}
# The robes' blue, whatever shade Retro Diffusion drew, turned so its middle lands on one hue, every
# shade turned alike so the hue-shifted shading stays.
ROBE_BLUES = [170, 260]
ROBE_BLUE = 222

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


def load(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(float) / 255


def save(img, name):
    Image.fromarray((np.clip(img, 0, 1) * 255).round().astype(np.uint8), "RGBA").save(SPRITES / f"{name}.png")


def blue(img):
    """The middle hue of the robe's blue pixels."""
    h, s, _ = rgb2hsv(img[..., :3])
    robe = (img[..., 3] > 0) & (s >= 0.2) & (h >= ROBE_BLUES[0]) & (h <= ROBE_BLUES[1])
    return float(np.median(h[robe]))


def armour():
    made = {}
    for name, source in ARMOUR.items():
        img = load(VARIANTS / source)
        if name.startswith("armor_mage_robe"):
            img = recolor(img, [{"hue": ROBE_BLUES, "minSaturation": 0.2, "shift": ROBE_BLUE - blue(img)}])
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
        for row, facing in enumerate(("up", "right", "down", "left")):
            t = piece(sheet[row * F:(row + 1) * F, :F], kind)
            if t is None or (kind == "mask" and facing == "up"):
                frames.append(np.zeros((F, F, 4)))
                continue
            t0, t1, tl, tr = bbox(t)
            if kind in ("cape", "scarf"):
                _, feet, shoulder, left, right = figure(sheet[row * F:(row + 1) * F, :F])
                t = moved(t, SHOULDER_Y - shoulder, ANCHOR_X - (left + right) // 2)
                if kind == "cape":
                    t = widen(lengthened(t, CAPE_DROP - (feet - shoulder), SHOULDER_Y), CAPE_SPAN - (right - left + 1))
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
    made = armour() | wear()
    if args.sheet:
        contact(made, args.sheet)


if __name__ == "__main__":
    main()
