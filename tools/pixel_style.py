#!/usr/bin/env python3
"""Storyleaf's pixel-art style, measured: the numbers behind docs/pixel-style.md.

Every sprite the game shipped from Retro Diffusion (monsters, props, buildings, tiles, and the weapon and
armour icons shrunk from RD drawings) is the reference: `calibrate` measures them all and writes each
metric's accepted band (the reference's 10th to 90th percentile, per size class) to
tools/pixel_style.json. `check` scores any sprite against those bands, so art drawn in code can be held to
the look RD gave us, and the bands can be re-run as the reference grows.

    python3 tools/pixel_style.py calibrate                 # measure the reference, write the bands
    python3 tools/pixel_style.py check <png>...            # score sprites (exit 1 if any fails)
    python3 tools/pixel_style.py compare                   # RD's icons, ours, and the flat designs
    python3 tools/pixel_style.py check --kind icon <png>   # pick the band set (icon, creature, scenery, building)
    python3 tools/pixel_style.py check --kind item <png>   # the clean item icons' rules (RD's Potion), 2026-10-26

Needs pillow + numpy.
"""

import colorsys
import json
import pathlib
import sys

import numpy as np
from PIL import Image

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"
BANDS = pathlib.Path(__file__).resolve().parent / "pixel_style.json"
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

# Sprites drawn over an RD asset by code (prop_art.py, crystal_art.py): not reference.
CODE_PROPS = {"candy_cane", "ship", "cave_ladder", "cave_rope", "waystone"}


# --- The reference and its classes -----------------------------------------------------------------

def reference():
    """{kind: [png paths]}: every shipped sprite RD drew. Icons are the 32 × 32 item icons tools/weapon_art.py
    and tools/armour_art.py made from picked RD drawings till 2026-10-26 (`legacy_rd_icons`: the game
    ships them at 64 now, kind `rd_item`); creatures the monsters; scenery props, buildings
    and tiles; buildings also on their own (a 96-pixel house holds fewer colours to its size than a bush,
    so RD's own failed a third of the scenery bands)."""
    assets = json.loads((ROOT / "art" / "assets.json").read_text())["assets"]
    out = {"icon": [], "creature": [], "scenery": [], "building": []}
    for a in assets:
        if "request" not in a or "derive" in a or a["id"] in CODE_PROPS or a["id"].startswith("crystal"):
            continue
        path = SPRITES / f"{a['id']}.png"
        if not path.exists():
            continue
        if a["kind"] == "monster":
            out["creature"].append(path)
        elif a["kind"] in ("prop", "building", "tile"):
            out["scenery"].append(path)
            if a["kind"] == "building":
                out["building"].append(path)
    out["icon"] = legacy_rd_icons()
    return out


def legacy_rd_icons():
    """RD's weapon and armour icons as the game had them till 2026-10-26, shrunk to 32 and outlined in the
    house violet (written to a temporary folder): the reference of the `icon` bands, which judge sprites
    in the 32-pixel look (`check --kind icon`, `pixel_kit --demo`)."""
    import tempfile
    import armour_art
    import item_art
    import weapon_art
    folder = pathlib.Path(tempfile.mkdtemp())
    out = []
    for item_id, (path, turn) in sorted(weapon_art.PICKED.items()):
        icon = weapon_art.shrink(weapon_art.load(weapon_art.VARIANTS / path, turn), item_art.SIZE, weapon_art.ICON_INNER)
        (folder / f"item_{item_id}.png").write_bytes(icon.png())
        out.append(folder / f"item_{item_id}.png")
    for item_id, (shape, mat, tint) in sorted(armour_art.plan().items()):
        (folder / f"item_{item_id}.png").write_bytes(armour_art.icon(shape, mat, tint, small=True).png())
        out.append(folder / f"item_{item_id}.png")
    return out


def rd_items():
    """Items whose icon RD drew: the weapons and armour made from picked RD drawings, and any item
    sprite generated outright (assets.json, not drawn by tools/item_art.py: the Potion)."""
    import armour_art
    import item_art
    import weapon_art
    assets = json.loads((ROOT / "art" / "assets.json").read_text())["assets"]
    generated = {a["id"][len("item_"):] for a in assets
                 if a["id"].startswith("item_") and "request" in a and "derive" not in a}
    return set(weapon_art.PICKED) | set(armour_art.plan()) | (generated - set(item_art.DRAWINGS))


def code_drawn_icons():
    """The item icons tools/item_art.py draws in code."""
    rd = rd_items()
    items = json.loads((ROOT / "content" / "items.json").read_text())["items"]
    return [SPRITES / f"item_{i['id']}.png" for i in items
            if i["id"] not in rd and (SPRITES / f"item_{i['id']}.png").exists()]


# --- Metrics ---------------------------------------------------------------------------------------

def load(path):
    return np.asarray(Image.open(path).convert("RGBA")).astype(float) / 255


def luma(rgb):
    return rgb @ np.array([0.299, 0.587, 0.114])


def neighbours(mask):
    """4-neighbour shifts of a boolean array, padded with False."""
    p = np.pad(mask, 1)
    return [p[:-2, 1:-1], p[2:, 1:-1], p[1:-1, :-2], p[1:-1, 2:]]


def warm_distance(hue_deg):
    """Degrees from yellow-orange (50°), where pixel art's highlights lean; shadows lean away, to blue."""
    d = np.abs((hue_deg - 50 + 180) % 360 - 180)
    return d


def _box(a, r):
    """The mean of each pixel's (2r + 1)-square neighbourhood, zero outside."""
    k = 2 * r + 1
    c = np.pad(np.pad(a, r).cumsum(0).cumsum(1), ((1, 0), (1, 0)))
    H, W = a.shape
    return (c[k:k + H, k:k + W] - c[:H, k:k + W] - c[k:k + H, :W] + c[:H, :W]) / (k * k)


def measure(path):
    """Every metric for one sprite, as {name: value}. None where a metric doesn't apply (too few pixels)."""
    img = load(path)
    a = img[..., 3]
    opaque = a > 0.5
    rgb = img[..., :3]
    m = {}
    n = int(opaque.sum())
    if n < 12:
        return None
    m["semi_alpha"] = float(((a > 0.02) & (a < 0.98)).sum() / max(1, (a > 0.02).sum()))

    cols = rgb[opaque]
    keys = np.round(cols * 255).astype(int) @ np.array([65536, 256, 1])
    uniq, counts = np.unique(keys, return_counts=True)
    m["colours"] = int(len(uniq))
    # Colours per 100 opaque pixels: small sprites need fewer.
    m["colour_density"] = float(len(uniq) / n * 100)

    edge = opaque & ~np.logical_and.reduce(neighbours(opaque))
    interior = opaque & ~edge
    m["edge_share"] = float(edge.sum() / n)
    el = luma(rgb[edge])
    il = luma(rgb[interior]) if interior.any() else luma(cols)
    # The outline: darker than what it rounds (luma well under the interior's median).
    m["outline_dark"] = float((el < np.median(il) * 0.55).mean())
    # Tinted, not black: the outline's own saturation and lightness.
    eh = np.array([colorsys.rgb_to_hsv(*c) for c in rgb[edge]])
    dark_edge = eh[el < np.median(il) * 0.55]
    m["outline_sat"] = float(np.median(dark_edge[:, 1])) if len(dark_edge) else 0.0
    m["outline_value"] = float(np.median(dark_edge[:, 2])) if len(dark_edge) else 1.0
    # The clean item icons (2026-10-26, *Item icons* in docs/pixel-style.md): the outline in the hue of what
    # it rounds (`outline_hue`: degrees between each outline pixel and the inside pixel next to it, median,
    # where both have colour; RD's Potion 6°, the house violet round a gold coin 138°), and one pixel thick
    # (`outline_double`: the share of outline pixels with a pixel nearly as dark right inside them, the dark
    # ring that made our icons' borders read two or three pixels thick: the Potion 0.29, ours 0.66).
    # (By value, the HSV brightness, not luma: a saturated red's mid tone has a low luma, and was counted
    # as a dark ring where it was the shaded side of the form, 2026-10-26.)
    L = rgb.max(axis=2)
    med = float(np.median(L[interior])) if interior.any() else 0.5
    hues, double = [], []
    H_, W_ = opaque.shape
    for y, x in zip(*np.nonzero(edge)):
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            yy, xx = y + dy, x + dx
            if 0 <= yy < H_ and 0 <= xx < W_ and interior[yy, xx]:
                h1, s1, _ = colorsys.rgb_to_hsv(*rgb[y, x])
                h2, s2, _ = colorsys.rgb_to_hsv(*rgb[yy, xx])
                if s1 > 0.2 and s2 > 0.25:
                    hues.append(abs((h1 - h2) * 360 + 180) % 360 - 180)
                # Against the inside near it (within 4 pixels), not the whole sprite's: a drum's brown side in
                # shadow beside its pale head isn't a ring.
                near = interior[max(0, yy - 4):yy + 5, max(0, xx - 4):xx + 5]
                local = float(np.median(L[max(0, yy - 4):yy + 5, max(0, xx - 4):xx + 5][near])) if near.any() else med
                double.append(L[yy, xx] < max(0.45 * local, L[y, x] * 1.6))
                break
    m["outline_hue"] = float(np.median(np.abs(hues))) if hues else None
    m["outline_double"] = float(np.mean(double)) if double else None
    # The edge's weight (2026-10-26, "are the outlines a bit too thin now?"): the outline's own value
    # (`line_value`, median; the Potion 0.08) and, just inside it on the lit side (top left), the value
    # over the lit inside's (90th percentile): `rim_lit`. The Potion keeps a mid-tone rim there (0.70), so
    # its one-pixel line reads firm; straight from the line to the lightest shade (0.93 to 1) it reads as
    # a hairline.
    V = rgb.max(axis=2)
    m["line_value"] = float(np.median(V[edge]))
    inner1 = interior & ~np.logical_and.reduce(neighbours(interior))
    inner2 = interior & ~inner1
    ys_, xs_ = np.nonzero(opaque)
    gy_, gx_ = np.mgrid[0:opaque.shape[0], 0:opaque.shape[1]]
    lit_side = (gx_ - xs_.mean()) + (gy_ - ys_.mean()) < 0
    if (inner1 & lit_side).sum() >= 8 and inner2.sum() >= 30:
        m["rim_lit"] = float(np.median(V[inner1 & lit_side]) / max(np.percentile(V[inner2], 90), 1e-6))
    else:
        m["rim_lit"] = None
    # Kinks (2026-10-26, "some pixels don't line up or are a bit out of place, making the shape of a smaller
    # coin [...] not the right shape"): along each side of the silhouette, a run of one or two pixels the
    # outline steps in to and straight back out of (or out and back in), as a curve never does; per step
    # of the outline. Two shapes meeting make one too (two coins side by side), so it allows a few: RD's
    # Potion 0, the small coins drawn off the pixel grid 0.04 to 0.14.
    kink = steps = 0
    for view in (opaque, opaque[::-1], opaque.T, opaque.T[::-1]):
        prof = [int(np.argmax(col)) if col.any() else None for col in view.T]
        runs, vals = [], []
        for v in prof:
            if vals and v == vals[-1]:
                runs[-1] += 1
            else:
                runs.append(1)
                vals.append(v)
        for k in range(1, len(runs) - 1):
            a_, b_, c_ = vals[k - 1], vals[k], vals[k + 1]
            if None in (a_, b_, c_):
                continue
            steps += 1
            if (b_ - a_) * (c_ - b_) < 0 and runs[k] <= 2 and abs(b_ - a_) <= 2 and abs(c_ - b_) <= 2:
                kink += 1
    m["kinks"] = float(kink / steps) if steps else 0.0
    m["canvas"] = int(max(opaque.shape))
    # Drawn at its size, not doubled from a smaller one (`native`): the share of pixels that a 2× shrink and
    # blow-up would change among those where the colour changes, at the best of the four alignments. A 32-pixel icon blown up to 64 scores 0,
    # and keeps its blocky steps and thick outline; RD's Potion 0.5, the clean icons 0.37 to 0.48.
    q = np.where(opaque, np.round(rgb * 255).astype(int) @ np.array([65536, 256, 1]), -1)
    best = 1.0
    for oy in (0, 1):
        for ox in (0, 1):
            part = q[oy:, ox:]
            hh, ww = part.shape[0] // 2 * 2, part.shape[1] // 2 * 2
            part = part[:hh, :ww]
            back = np.repeat(np.repeat(part[::2, ::2], 2, 0), 2, 1)
            # Only where the colour changes (a boundary): inside a flat facet any size survives the trip.
            pp = np.pad(part, 1, constant_values=-1)
            boundary = (part >= 0) & ((pp[:-2, 1:-1] != part) | (pp[2:, 1:-1] != part)
                                      | (pp[1:-1, :-2] != part) | (pp[1:-1, 2:] != part))
            best = min(best, float((back != part)[boundary].mean()) if boundary.any() else 0.0)
    m["native"] = best
    m["outline_colours"] = int(len(np.unique(np.round(rgb[edge] * 255).astype(int) @ np.array([65536, 256, 1]))))
    # The outline against what it rounds: each edge pixel's value (HSV) over the mean value of the inside
    # within 2 pixels of it, median. RD's outlines are a deep shade of the colour inside (a green tree's
    # dark green, about 0.6 to 0.85 of it); a near-black line round everything sits far lower.
    val = rgb.max(axis=2)
    pad = 2
    iv = np.pad(np.where(interior, val, 0.0), pad)
    ic = np.pad(interior.astype(float), pad)
    tot = np.zeros(opaque.shape)
    cnt = np.zeros(opaque.shape)
    for dy in range(-pad, pad + 1):
        for dx in range(-pad, pad + 1):
            tot += iv[pad + dy:pad + dy + opaque.shape[0], pad + dx:pad + dx + opaque.shape[1]]
            cnt += ic[pad + dy:pad + dy + opaque.shape[0], pad + dx:pad + dx + opaque.shape[1]]
    near = edge & (cnt > 0)
    inside_v = tot[near] / cnt[near]
    rel = val[near] / np.maximum(inside_v, 0.04)
    m["outline_rel"] = float(np.median(np.minimum(rel, 1.5))) if near.any() else None
    # Light in broad areas: how much of the inside's spread of light survives a 5 × 5 blur. RD lights a
    # house as a few big areas (a lit front, a side in shadow, a dark band under the eaves) with detail
    # on top; light that lives only in a grain on every pixel blurs away to nothing.
    lum = luma(rgb)
    w = opaque.astype(float)
    full = _box(w, 2)
    blurred = _box(lum * w, 2) / np.maximum(full, 1e-6)
    deep = opaque & (full > 0.99)
    m["light_masses"] = float(blurred[deep].std() / max(lum[deep].std(), 1e-6)) if deep.sum() >= 30 else None
    # Light modelling the forms (2026-10-24, the user: ours looked "too flat [...] more three-dimensional,
    # like the retro diffusion sprites"): the slope of the light once a 9 × 9 blur has taken the detail out,
    # median over the inside. RD shades every big form as a form (a tower round, a doorway deep, a band
    # with a shadow under it, a roof darker toward its eave): its median 0.019; ours lit each face in one
    # tone and scored 0.014.
    full4 = _box(w, 4)
    soft = _box(lum * w, 4) / np.maximum(full4, 1e-6)
    gy, gx = np.gradient(soft)
    core = opaque & (full4 > 0.99)
    m["form_relief"] = float(np.median(np.hypot(gx, gy)[core])) if core.sum() >= 30 else None

    # Flatness: interior pixels with all 8 neighbours their own colour.
    k = np.full(opaque.shape, -1)
    k[opaque] = keys
    p = np.pad(k, 1, constant_values=-2)
    same = np.ones(opaque.shape, bool)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dy or dx:
                same &= p[1 + dy:p.shape[0] - 1 + dy, 1 + dx:p.shape[1] - 1 + dx] == k
    m["flat"] = float((same & interior).sum() / max(1, interior.sum()))
    # Orphans: interior pixels unlike all 4 neighbours (noise, or a highlight speck).
    diff = np.ones(opaque.shape, bool)
    for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
        diff &= p[1 + dy:p.shape[0] - 1 + dy, 1 + dx:p.shape[1] - 1 + dx] != k
    m["orphans"] = float((diff & interior).sum() / max(1, interior.sum()))
    # Clusters: the mean size of 4-connected same-colour patches inside. Noise is all ones and twos;
    # form-following texture makes patches of a few pixels; flat fills make big ones.
    seen = np.zeros(opaque.shape, bool)
    sizes = []
    H, W = opaque.shape
    for sy, sx in zip(*np.nonzero(interior)):
        if seen[sy, sx]:
            continue
        stack, size, colour = [(sy, sx)], 0, k[sy, sx]
        seen[sy, sx] = True
        while stack:
            y, x = stack.pop()
            size += 1
            for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                yy, xx = y + dy, x + dx
                if 0 <= yy < H and 0 <= xx < W and not seen[yy, xx] and interior[yy, xx] and k[yy, xx] == colour:
                    seen[yy, xx] = True
                    stack.append((yy, xx))
        sizes.append(size)
    m["cluster_size"] = float(np.mean(sizes)) if sizes else None

    # Ramps: a sprite's colours chained into ramps by hue (a gap of more than 25° round the wheel starts a
    # new one, so a ramp that hue-shifts from blue shadows to yellow lights stays one), greys a ramp of
    # their own. Shades are a ramp's distinct brightness levels (steps of 0.05); hue shift compares its
    # darker third with its lighter third.
    hsv = np.array([colorsys.rgb_to_hsv(*(np.array([(u >> 16) & 255, (u >> 8) & 255, u & 255]) / 255)) for u in uniq])
    ramps = {"grey": []}
    sat = [(h * 360, s_, v, c) for (h, s_, v), c in zip(hsv, counts) if s_ >= 0.15 and v >= 0.12]
    for (h, s_, v), c in zip(hsv, counts):
        if (s_ < 0.15 or v < 0.12) and v >= 0.12:
            ramps["grey"].append((h * 360, s_, v, c))
    if sat:
        sat.sort()
        hues = [x[0] for x in sat]
        gaps = [(hues[(k + 1) % len(hues)] - hues[k]) % 360 for k in range(len(hues))]
        start = (int(np.argmax(gaps)) + 1) % len(hues)       # cut the wheel at its widest gap
        order = sat[start:] + sat[:start]
        current = [order[0]]
        for prev, nxt in zip(order, order[1:]):
            if (nxt[0] - prev[0]) % 360 > 25:
                ramps[len(ramps)] = current
                current = []
            current.append(nxt)
        ramps[len(ramps)] = current
    big = [f for f in ramps.values() if f and sum(x[3] for x in f) >= max(6, n * 0.06)]
    m["shades_per_ramp"] = float(np.median([len({round(x[2] / 0.05) for x in f}) for f in big])) if big else None
    shifts = []
    for key, f in ramps.items():
        if key == "grey" or f not in big or len(f) < 3:
            continue
        f = sorted(f, key=lambda x: x[2])
        dark, light = f[: max(1, len(f) // 3)], f[-max(1, len(f) // 3):]
        hd = np.degrees(np.angle(np.average(np.exp(1j * np.radians([x[0] for x in dark])), weights=[x[3] for x in dark])))
        hl = np.degrees(np.angle(np.average(np.exp(1j * np.radians([x[0] for x in light])), weights=[x[3] for x in light])))
        shifts.append(float(warm_distance(np.array(hd % 360)) - warm_distance(np.array(hl % 360))))
    m["hue_shift"] = float(np.median(shifts)) if shifts else None
    # Value range across the sprite's colours: deep shadows to bright highlights.
    lum = luma(cols)
    m["value_range"] = float(np.percentile(lum, 95) - np.percentile(lum, 5))
    m["saturation"] = float(np.median([colorsys.rgb_to_hsv(*c)[1] for c in cols]))

    # Light from the top left: interior luma against position (correlation with -x - y).
    if interior.sum() > 20:
        ys, xs = np.nonzero(interior)
        t = -(xs - xs.mean()) - (ys - ys.mean())
        l = luma(rgb[interior])
        m["light_top_left"] = float(np.corrcoef(t, l)[0, 1]) if l.std() > 1e-6 and t.std() > 1e-6 else 0.0
    else:
        m["light_top_left"] = None
    # Highlights: a few bright specks (top 4% of luma) that stand out from their surroundings.
    m["highlight_share"] = float((il > np.median(il) + 0.25).mean()) if len(il) else 0.0

    # Pillow shading (the classic beginner's mistake, Pixel Fixer, TU Delft 2025): light that follows the
    # outline in from every side instead of coming from one direction. How much more the inside's
    # brightness tracks the distance in from the edge than it tracks nearness to the light.
    if interior.sum() > 20:
        ins = np.zeros(opaque.shape)
        cur = opaque.copy()
        k = 0
        while cur.any() and k < 40:
            k += 1
            ins[cur] = k
            q = np.pad(cur, 1)
            cur = cur & q[:-2, 1:-1] & q[2:, 1:-1] & q[1:-1, :-2] & q[1:-1, 2:]
        l = luma(rgb[interior])
        d = ins[interior]
        pillow = float(np.corrcoef(d, l)[0, 1]) if l.std() > 1e-6 and d.std() > 1e-6 else 0.0
        m["pillow"] = pillow - (m["light_top_left"] or 0.0)
    else:
        m["pillow"] = None
    # Jaggies: along one slope of an outline, the steps should grow or shrink steadily (1, 1, 2, 2, 3),
    # never jump about (1, 3, 1, 3). Each column's top edge and each row's left edge is read as runs of
    # equal height; a run is a jaggy when the outline steps the same way on both sides of it (one slope,
    # not the turn at the top of a curve) and it is 2 or more longer, or shorter, than both neighbours.
    # The share of such runs among those inside a slope.
    jag = total = 0
    for mask in (opaque, opaque.T):
        tops = [int(np.argmax(col)) for col in mask.T if col.any()]
        runs, steps, cur_run = [], [], 1
        for a_, b_ in zip(tops, tops[1:]):
            if a_ == b_:
                cur_run += 1
            else:
                runs.append(cur_run)
                steps.append(np.sign(b_ - a_))
                cur_run = 1
        runs.append(cur_run)
        for k in range(1, len(runs) - 1):
            if steps[k - 1] != steps[k]:
                continue                      # the outline turns here: not inside one slope
            total += 1
            d0, d1 = runs[k] - runs[k - 1], runs[k] - runs[k + 1]
            if abs(d0) >= 2 and abs(d1) >= 2 and d0 * d1 > 0:
                jag += 1
    m["jaggies"] = float(jag / total) if total else 0.0
    # Dithering on a small sprite reads as noise: the share of the inside in 2 × 2 checkerboards of two
    # colours.
    kk = k_ = None
    kq = np.where(opaque, np.round(rgb * 255).astype(int) @ np.array([65536, 256, 1]), -1)
    a00, a01, a10, a11 = kq[:-1, :-1], kq[:-1, 1:], kq[1:, :-1], kq[1:, 1:]
    checker = (a00 == a11) & (a01 == a10) & (a00 != a01) & (a00 >= 0) & (a01 >= 0)
    m["checker"] = float(checker.sum() / max(1, interior.sum()))

    # Size and placement in the canvas (icons: centred, filling most of it).
    ys, xs = np.nonzero(opaque)
    h, w = opaque.shape
    m["fill"] = float(max(xs.max() - xs.min() + 1, ys.max() - ys.min() + 1) / max(h, w))
    m["off_centre"] = float(max(abs((xs.min() + xs.max() + 1) / 2 - w / 2), abs((ys.min() + ys.max() + 1) / 2 - h / 2)))

    # How ruled it looks (2026-10-24, the user: buildings drawn in code came out "a bit too squared"). RD
    # draws a house by hand: its outline bends, its roof sags and bulges, its stones and shingles are big
    # rounded lumps. Ours were boxes with every face's pattern on a grid. `straight_edges`: the share of
    # the silhouette's top, bottom and side edges in straight runs of 6 pixels or more (RD's median 0.17,
    # ours 0.41). `grid_lines`: the share of the inside on long straight seams, a pixel darker than both its
    # neighbours across it for 7 or more in a row (mortar, planks and tile rows ruled across a face).
    top_bottom = opaque & (~np.pad(opaque, 1)[:-2, 1:-1] | ~np.pad(opaque, 1)[2:, 1:-1])
    sides = opaque & (~np.pad(opaque, 1)[1:-1, :-2] | ~np.pad(opaque, 1)[1:-1, 2:])
    rows, cols_ = _runs(top_bottom), _runs(sides.T)
    m["straight_edges"] = float(sum(r for r in rows + cols_ if r >= 6) / max(1, sum(rows) + sum(cols_)))
    lum = luma(rgb)
    inside = opaque & ~(top_bottom | sides)
    seam_h = inside & (lum < np.roll(lum, 1, 0) - 0.06) & (lum < np.roll(lum, -1, 0) - 0.06)
    seam_v = inside & (lum < np.roll(lum, 1, 1) - 0.06) & (lum < np.roll(lum, -1, 1) - 0.06)
    seams = sum(r for r in _runs(seam_h) + _runs(seam_v.T) if r >= 7)
    m["grid_lines"] = float(seams / max(1, inside.sum()))
    return m


def _runs(mask):
    """The lengths of the runs of True along each row of `mask`."""
    out = []
    for row in mask:
        padded = np.concatenate(([False], row, [False])).astype(np.int8)
        d = np.diff(padded)
        out += list(np.nonzero(d == -1)[0] - np.nonzero(d == 1)[0])
    return out


# Which way each metric fails, and which the bands enforce. Hard criteria must all pass; soft ones are
# scored, and a sprite passes with SOFT_PASS of them. Metrics left out are reported, never judged.
ENFORCED = {
    "semi_alpha": "max", "colour_density": "min", "outline_dark": "min", "outline_sat": "min",
    "outline_value": "both", "flat": "max", "orphans": "max", "shades_per_ramp": "min", "hue_shift": "min",
    "value_range": "min", "light_top_left": "min", "highlight_share": "both", "cluster_size": "both",
    "jaggies": "max", "outline_rel": "min", "light_masses": "min", "straight_edges": "max", "grid_lines": "max",
    "form_relief": "min",
}
# Where a kind is judged the other way too: a building's palette is capped as well as floored (RD's hold
# 18 to 35 colours; drawn shape by shape, ours held over a hundred, every face its own seven shades).
BOTH_BY_KIND = {"building": {"colour_density"}}
# Judged on some kinds only: light in broad areas is a building's (a bush or a tile is all small detail).
ONLY_FOR = {"light_masses": {"building"}, "straight_edges": {"building"}, "grid_lines": {"building"},
            "form_relief": {"building"}}
# Reported, not judged (2026-10-23): `pillow` and `checker` measure two classic mistakes, but neither
# separates RD's art from the flat designs or ours, so they describe, they don't judge.
# Partial transparency is soft: only a light effect (a magic staff's glow) may use it.
HARD = {"colour_density", "flat", "outline_dark", "fill"}
# Buildings: a broken, tinted outline is how RD draws them (a lit roof edge has none), so it's soft there.
# The outline's light against what it rounds (`outline_rel`) is hard wherever RD tints it: a near-black
# line round a green tree is the commonest tell of a sprite drawn in code (playtesting 2026-10-23).
# (Soft on creatures: RD drew every one, and a dark one's outline sits close to its body's light.)
# A building's outline in long ruled runs is hard too: it's what made ours read as boxes beside RD's
# (2026-10-24); and so is light that doesn't model its forms (`form_relief`): it's what made ours read
# flat beside RD's (2026-10-24).
HARD_BY_KIND = {"building": {"colour_density", "flat", "outline_rel", "straight_edges", "form_relief"},
                "scenery": HARD | {"outline_rel"}}
SOFT_PASS = 0.8
# Icons fill most of their tile (fixed rules, not measured bands).
ICON_RULES = {"fill": ("min", 0.78)}
# The band is the reference's 5th to 95th percentile, never narrower than this (a house rule such as the
# icons' one outline colour has no spread at all).
MIN_WIDTH = {"outline_sat": 0.1, "outline_value": 0.1, "outline_dark": 0.04}
# House rules: floors under the measured bands, where the reference's spread alone allowed almost anything
# (2026-10-23). Each is met by about 85% or more of RD's own sprites of its kind; tighten as they allow.
# But a building's `form_relief` is set higher, at what seven in ten of RD's buildings reach (its median
# 0.018): at its 15th percentile (0.014) the flat ones we drew passed (2026-10-24).
FLOORS = {
    "icon": {"shades_per_ramp": 3, "hue_shift": 0.0, "light_top_left": 0.0},
    "creature": {"shades_per_ramp": 5, "hue_shift": 4.0, "light_top_left": 0.0},
    "scenery": {"shades_per_ramp": 4, "hue_shift": 2.0, "light_top_left": -0.05},
    "building": {"light_masses": 0.55, "form_relief": 0.016},
}
# And ceilings over them, where the band's 95th percentile alone would cut RD's own: a building's palette
# cap sits over all but the smallest of RD's (its fence).
CEILINGS = {"building": {"colour_density": 1.4}}
# And caps under them, where the 95th percentile lets in what RD only does now and then: RD's few boxy
# buildings (its adobes, its blacksmith, its puppet theatre) set the band's top, but most of its houses
# bend. Set at RD's own 90th percentile (2026-10-24).
CAPS = {"building": {"straight_edges": 0.40, "grid_lines": 0.033}}


# The clean item icons (2026-10-26): house rules, not a calibrated band, as their reference is one sprite,
# RD's Potion (playtesting: "Look at the potion items we created with retro diffusion, those look nice"),
# with what the redrawn coins, seal stones and clover taught. Each: (way, limit, hard). docs/pixel-style.md,
# *Item icons*, says why each is set where it is.
ITEM_RULES = {
    "canvas": ("min", 64, True),             # drawn at 64 pixels: finer pixels, so a one-pixel outline is thin
    "native": ("min", 0.3, True),            # and drawn there, not blown up (those score 0, flat designs at most 0.24)
    "fill": ("min", 0.78, True),
    "semi_alpha": ("max", 0.0, True),
    "outline_hue": ("max", 30.0, True),      # the outline a deep shade of what it rounds, not the house violet
    "outline_double": ("max", 0.4, True),    # one pixel: no dark ring inside it (the Potion 0.18)
    "outline_rel": ("max", 0.32, False),     # deep, though: it reads as the edge (the Potion 0.13)
    "line_value": ("max", 0.15, False),      # the line itself near-black in its hue (the Potion 0.08)
    "rim_lit": ("max", 0.85, True),          # a mid-tone rim inside it on the lit side, not a hairline (the Potion 0.70)
    # Smooth ramps, no grain (the Potion 1.95; the grained finish 2.3 to 10). Soft: a thin thing (a whip) has
    # few pixels for its colours and runs high without any grain; `orphans` and `cluster_size` see grain.
    "colour_density": ("max", 2.6, False),
    "checker": ("max", 0.05, False),         # no dither fields
    "orphans": ("max", 0.2, False),          # no salt and pepper (the Potion 0.17)
    "cluster_size": ("min", 3.0, False),     # light in bands, not specks (the Potion 3.6; grained 1.6 to 3.2)
    "value_range": ("min", 0.45, False),     # deep shadows to pale lights (the Potion 0.53)
    "shades_per_ramp": ("min", 4, False),    # a form shaded in steps, not a flat design's three tones
    "light_top_left": ("min", 0.1, False),
    "hue_shift": ("min", 3.0, False),
    "jaggies": ("max", 0.08, False),
    "kinks": ("max", 0.04, False),           # outlines that wobble a pixel in and out (the Potion 0)
}
HARD_BY_KIND["item"] = {name for name, (_way, _limit, hard) in ITEM_RULES.items() if hard}

# RD's own item icons (kind `rd_item`: the weapons and armour from tools/weapon_art.py and armour_art.py,
# the Potion): held to the clean look's size and outline, not its texture, which is RD's painting and
# stays as drawn (the user, 2026-10-26, option 1; CLAUDE.md: never redraw RD's art). A magic weapon's glow
# is light round it, so partly clear pixels are allowed here.
# Only what the code sets: the size and the outline. How full the tile is (an axe RD drew small), the band
# inside the outline (a cloak's lit edge) and a dark ring there (a dark red axe's shading) are its painting.
RD_ITEM_RULES = {name: ITEM_RULES[name] for name in ("canvas", "native", "outline_hue", "outline_rel", "line_value")}
RD_ITEM_RULES["outline_rel"] = ("max", 0.32, True)
RD_ITEM_RULES["line_value"] = ("max", 0.15, True)
HARD_BY_KIND["rd_item"] = {name for name, (_way, _limit, hard) in RD_ITEM_RULES.items() if hard}


def calibrate():
    ref = reference()
    bands = {"_about": "Accepted bands per metric and kind (p10/p90 here hold the reference's 5th and 95th percentile) "
                       "(tools/pixel_style.py calibrate). Edit by recalibrating, not by hand.", "kinds": {}}
    for kind, paths in ref.items():
        rows = [r for r in (measure(p) for p in paths) if r]
        kb = {"count": len(rows)}
        for name in ENFORCED:
            vals = np.array([r[name] for r in rows if r.get(name) is not None], float)
            if len(vals) < 5:
                continue
            lo, hi = float(np.percentile(vals, 5)), float(np.percentile(vals, 95))
            pad = max(0.0, MIN_WIDTH.get(name, 0.0) - (hi - lo)) / 2
            low = max(lo - pad, FLOORS.get(kind, {}).get(name, -np.inf))
            high = max(hi + pad, CEILINGS.get(kind, {}).get(name, -np.inf))
            high = min(high, CAPS.get(kind, {}).get(name, np.inf))
            kb[name] = {"p10": round(low, 4), "median": round(float(np.median(vals)), 4),
                        "p90": round(high, 4)}
        bands["kinds"][kind] = kb
    BANDS.write_text(json.dumps(bands, indent=2) + "\n")
    print(f"wrote {BANDS.relative_to(ROOT)}: " + ", ".join(f"{k} ({v['count']})" for k, v in bands["kinds"].items()))


def judge(m, kind):
    """[(metric, value, band, ok)] for one sprite's metrics against its kind's bands."""
    if kind in ("item", "rd_item"):
        out = []
        for name, (way, limit, _hard) in (ITEM_RULES if kind == "item" else RD_ITEM_RULES).items():
            v = m.get(name)
            if v is None:
                continue
            out.append((name, v, ("≥" if way == "min" else "≤") + str(limit), v >= limit if way == "min" else v <= limit))
        return out
    bands = json.loads(BANDS.read_text())["kinds"][kind]
    out = []
    for name, way in ENFORCED.items():
        if name not in bands or m.get(name) is None or kind not in ONLY_FOR.get(name, {kind}):
            continue
        b = bands[name]
        v = m[name]
        if name in BOTH_BY_KIND.get(kind, ()):
            way = "both"
        low_ok = v >= b["p10"] if way in ("min", "both") else True
        high_ok = v <= b["p90"] if way in ("max", "both") else True
        band = {"min": f"≥{b['p10']}", "max": f"≤{b['p90']}", "both": f"{b['p10']}–{b['p90']}"}[way]
        out.append((name, v, band, low_ok and high_ok))
    if kind == "icon":
        for name, (way, limit) in ICON_RULES.items():
            v = m[name]
            out.append((name, v, ("≥" if way == "min" else "≤") + str(limit), v >= limit if way == "min" else v <= limit))
    return out


def verdict(j, kind=None):
    """(passes, soft score): every hard criterion, and SOFT_PASS of the soft ones."""
    hard_set = HARD_BY_KIND.get(kind, HARD)
    hard = all(ok for n, *_, ok in j if n in hard_set)
    soft = [ok for n, *_, ok in j if n not in hard_set]
    s = sum(soft) / len(soft) if soft else 1.0
    return hard and s >= SOFT_PASS, s


def score(paths, kind):
    """Per path: (passes, soft score, failures)."""
    res = {}
    for p in paths:
        m = measure(p)
        if not m:
            continue
        j = judge(m, kind)
        ok, s = verdict(j, kind)
        res[str(p)] = (ok, s, [(n, round(v, 3), b) for n, v, b, good in j if not good])
    return res


def flat_designs():
    """tools/item_art.py's designs as drawn, before pixel_kit finishes them: the flat look the criteria
    must keep failing (written to a temporary folder)."""
    import tempfile
    import item_art
    folder = pathlib.Path(tempfile.mkdtemp())
    out = []
    shipped = {p.stem[len("item_"):] for p in code_drawn_icons()}
    for item_id in sorted(item_art.DRAWINGS):
        if item_id in shipped:
            path = folder / f"item_{item_id}.png"
            path.write_bytes(item_art.render(item_id).png())
            out.append(path)
    return out


def pieces(path_or_img, least):
    """How many separate pieces a sprite is in: opaque parts joined at their sides or corners, of `least`
    pixels or more (a sparkle drawn off the body is a piece too, and counts the same in both)."""
    img = path_or_img if isinstance(path_or_img, Image.Image) else Image.open(path_or_img)
    mask = np.asarray(img.convert("RGBA"))[..., 3] > 127
    seen = np.zeros(mask.shape, bool)
    h, w = mask.shape
    count = 0
    for sy, sx in zip(*np.nonzero(mask)):
        if seen[sy, sx]:
            continue
        stack, size = [(sy, sx)], 0
        seen[sy, sx] = True
        while stack:
            y, x = stack.pop()
            size += 1
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < h and 0 <= xx < w and mask[yy, xx] and not seen[yy, xx]:
                        seen[yy, xx] = True
                        stack.append((yy, xx))
        count += size >= least
    return count


def _bits(mask):
    from pixel_kit import _pieces_map
    return _pieces_map(mask)


def detached():
    """The code-drawn icons that came apart: more pieces at 64 than their 32-pixel design has (a necklace's
    cord no longer joined to its bail, 2026-10-26). [(item, pieces in the design, pieces in the icon)]."""
    import io
    import item_art
    out = []
    for p in code_drawn_icons():
        item_id = p.stem[len("item_"):]
        if item_id not in item_art.DRAWINGS:
            continue
        # The design without its outline: the outline joined a broken string's strands into one piece.
        drawn = np.asarray(Image.open(io.BytesIO(item_art.render(item_id).png())).convert("RGBA")).copy()
        drawn[np.all(drawn[..., :3] == np.array(item_art.OUTLINE[:3]), axis=-1), 3] = 0
        design = pieces(Image.fromarray(drawn), 3)
        # (Sparkles, drawn apart as light, are pale pieces with no outline: not pieces of the thing.)
        lit = np.asarray(Image.open(p).convert("RGBA")).copy()
        bits, sizes = _bits(lit[..., 3] > 127)
        for k in range(len(sizes)):
            piece = bits == k
            if lit[piece][:, :3].max(axis=-1).min() >= 200:
                lit[piece, 3] = 0
        icon = pieces(Image.fromarray(lit), 8)
        if icon > design:
            out.append((item_id, design, icon))
    return out


def lumpy_arcs():
    """The code-drawn icons whose round shapes (drawn `exact`: rings, pearls, eggs) don't come out as clean
    arcs as seen: their outline's stair steps shrinking steadily into the corners (`pixel_kit._arc_runs`),
    round the rim and round a hole. The lower half is checked, its sides row by row and its bottom column by
    column (the top half carries gems and bails); a part leading off the shape (a claw, a stand, an arm, three
    pixels or more) is let through, and a shape shut inside another (a lens in its rim) is left out. Each
    round item is finished again to learn where its shapes were cut (`pixel_kit._arc_mask`), then its icon
    on disk is checked (a ring's lump in its lower right, 2026-10-26). [(item, wrong edge pixels)]."""
    import json
    import item_art
    import pixel_kit
    swaps = {}
    for asset in json.loads((ROOT / "art" / "assets.json").read_text())["assets"]:
        base = (asset.get("derive") or {}).get("from", "")
        if base.startswith("item_") and not asset["derive"].get("layers"):
            swaps.setdefault(base[len("item_"):], []).append(asset["id"])
    out = []
    for item_id in sorted(item_art.DRAWINGS):
        if not any(sh[0] != "poly" for sh in item_art.render(item_id).exact):
            continue
        cuts, real = [], pixel_kit._arc_mask
        def spy(shape, ox, oy, w, h, edge=None):
            cuts.append((edge, ox, oy, w, h, shape))
            return real(shape, ox, oy, w, h, edge)
        pixel_kit._arc_mask = spy
        try:
            item_art.finished(item_id)
        finally:
            pixel_kit._arc_mask = real
        for name in [f"item_{item_id}"] + swaps.get(item_id, []):
            path = SPRITES / f"{name}.png"
            if not path.exists():
                continue
            solid = np.asarray(Image.open(path).convert("RGBA"))[..., 3] > 127
            wrong = sum(_arc_misses(solid, cut) for cut in cuts)
            if wrong:
                out.append((name[len("item_"):], wrong))
    return out


def _arc_misses(solid, cut):
    """How many edge pixels of one cut shape's lower half are off its clean arc in `solid` (the icon's
    opaque pixels): as seen, a rim is its cut and the outline round it, a hole its cut less the outline.
    What lies past the arc in a piece of six pixels or more is a part of its own (a claw, a stand), not a
    lump."""
    import pixel_kit
    edge, ox, oy, w, h, shape = cut
    if edge not in ("outer", "inner") or w < 4 or h < 4:
        return 0
    grow = 1 if edge == "outer" else -1
    seen = pixel_kit._arc_lo(shape, ox, oy, w + 2 * grow, h + 2 * grow)
    if edge == "outer" and not (pixel_kit._cross(pixel_kit._cross(seen, False), True) == seen).all():
        return 0                                  # too thin to cut for its outline: kept plain
    H, W = solid.shape
    seen = seen[:H, :W]
    ys, xs = np.nonzero(seen)
    if not len(ys):
        return 0
    # Past the arc: on a rim, what's opaque outside it; in a hole, what's opaque inside it.
    past = solid & ~seen if edge == "outer" else solid & seen
    bits, sizes = _bits(past)
    big = np.isin(bits, [k for k, n in enumerate(sizes) if n >= 6])
    mid = int(np.ceil((ys.min() + ys.max() + 1) / 2))
    # The edge's pixels and the one past each: the lower half's rows at both ends, its columns at the bottom.
    ends = []
    for y in range(mid, ys.max() + 1):
        row = np.nonzero(seen[y])[0]
        if len(row):
            ends += [((y, row.min()), (y, row.min() - 1)), ((y, row.max()), (y, row.max() + 1))]
    for x in range(xs.min(), xs.max() + 1):
        col = np.nonzero(seen[:, x])[0]
        if len(col):
            ends.append(((col.max(), x), (col.max() + 1, x)))
    misses = checked = enclosed = 0
    for (y, x), (y2, x2) in ends:
        if not (0 <= y2 < H and 0 <= x2 < W):
            continue
        checked += 1
        if edge == "outer":
            # Its edge pixel opaque, the one past it clear (or a part of its own leading off).
            if not solid[y, x]:
                misses += 1
            elif solid[y2, x2]:
                if big[y2, x2]:
                    enclosed += 1
                else:
                    misses += 1
        else:
            # The hole's edge pixel clear (unless something lies in it), the one past it the rim.
            if solid[y, x] and not big[y, x]:
                misses += 1
            elif not solid[y2, x2]:
                misses += 1
    if edge == "outer" and enclosed > checked / 2:
        return 0                                  # shut inside another shape (a lens in its rim)
    return misses


def clean_icons():
    """Every item icon drawn in code: all in the clean look since 2026-10-26 (tools/item_art.py through
    `restyle(clean=True)`, tools/clean_icon_art.py, tools/coin_art.py)."""
    import coin_art
    return code_drawn_icons() + [SPRITES / f"{n}.png" for n in coin_art.drawings()]


def grained_icons(every=6):
    """The finish the clean look replaced, for the rules to keep failing: every `every`-th code-drawn item
    finished the old way (32 pixels, grained, the house outline), and the same blown up to 64 (written to a
    temporary folder)."""
    import io
    import tempfile
    import item_art
    from pixel_kit import restyle
    folder = pathlib.Path(tempfile.mkdtemp())
    out = []
    for item_id in sorted(p.stem[len("item_"):] for p in code_drawn_icons())[::every]:
        if item_id not in item_art.DRAWINGS:
            continue
        drawn = Image.open(io.BytesIO(item_art.render(item_id).png()))
        img = restyle(drawn, preset=item_art.preset_for(item_id), base=item_art.set_colour(item_id), trim=item_art.FUR,
                      **item_art.RESTYLE.get(item_id, {})).render()
        img.save(folder / f"item_{item_id}.png")
        img.resize((64, 64), Image.NEAREST).save(folder / f"up_{item_id}.png")
        out += [folder / f"item_{item_id}.png", folder / f"up_{item_id}.png"]
    return out


def compare_items():
    """The clean look's rules (kind `item`) must pass the Potion and the icons drawn to them, and fail the
    grained finish they replace, at its own size and blown up to 64. And no icon may come apart from its
    design (`detached`)."""
    loose = detached()
    print(f"icons come apart from their design (should be none): {len(loose)}"
          + (": " + ", ".join(f"{i} {d}→{n}" for i, d, n in loose[:12]) if loose else ""))
    lumps = lumpy_arcs()
    print(f"round shapes off their clean arcs (should be none): {len(lumps)}"
          + (": " + ", ".join(f"{i} {n} px" for i, n in lumps[:12]) if lumps else ""))
    ids = {i["id"] for i in json.loads((ROOT / "content" / "items.json").read_text())["items"]}
    rd = [SPRITES / f"item_{i}.png" for i in sorted(rd_items() & ids) if (SPRITES / f"item_{i}.png").exists()]
    for label, paths, kind in (("RD's Potion (the reference, should pass)", [SPRITES / "item_potion.png"], "item"),
                               ("clean item icons (should pass)", clean_icons(), "item"),
                               ("RD's own icons, size and outline (kind rd_item, should pass)", rd, "rd_item"),
                               ("grained finish, 32 and blown up to 64 (should fail)", grained_icons(), "item")):
        res = score(paths, kind)
        fails = {}
        for _, (_, _, f) in res.items():
            for n, *_ in f:
                fails[n] = fails.get(n, 0) + 1
        passed = sum(v[0] for v in res.values())
        print(f"{label}: {len(res)} sprites, {passed} pass ({passed / len(res):.0%})")
        if fails:
            print("   most failed: " + ", ".join(f"{n} {c / len(res):.0%}" for n, c in sorted(fails.items(), key=lambda kv: -kv[1])[:8]))


def compare():
    compare_items()
    # The `icon` bands, calibrated on RD's weapon and armour icons at 32 (as they were till 2026-10-26),
    # still pass those, and must still fail the flat designs.
    ref = reference()["icon"]
    for label, paths in (("RD icons at 32, the icon bands' reference (should pass)", ref),
                         ("flat designs, unfinished (should fail)", flat_designs())):
        res = score(paths, "icon")
        fails = {}
        for _, (_, _, f) in res.items():
            for n, *_ in f:
                fails[n] = fails.get(n, 0) + 1
        passed = sum(v[0] for v in res.values())
        print(f"{label}: {len(res)} sprites, {passed} pass ({passed / len(res):.0%}), "
              f"mean soft score {np.mean([v[1] for v in res.values()]):.2f}")
        print("   most failed: " + ", ".join(f"{n} {c / len(res):.0%}" for n, c in sorted(fails.items(), key=lambda kv: -kv[1])[:8]))


def main(argv):
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return 0
    if argv[0] == "calibrate":
        calibrate()
        return 0
    if argv[0] == "compare":
        compare()
        return 0
    if argv[0] == "check":
        args = argv[1:]
        kind = "icon"
        if "--kind" in args:
            i = args.index("--kind")
            kind = args[i + 1]
            del args[i:i + 2]
        bad = 0
        for p in args:
            m = measure(p)
            if not m:
                print(f"{p}: too few pixels")
                bad += 1
                continue
            j = judge(m, kind)
            ok, s = verdict(j, kind)
            print(f"{p}: {'PASS' if ok else 'FAIL'} (soft {s:.0%}, needs {SOFT_PASS:.0%} and every hard one)")
            for n, v, b, good in j:
                print(f"   {'✓' if good else '✗'} {n:16} {v:8.3f}   {b}{'   hard' if n in HARD_BY_KIND.get(kind, HARD) else ''}")
            bad += not ok
        return 1 if bad else 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
