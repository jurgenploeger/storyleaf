#!/usr/bin/env python3
"""Storyleaf's pixel-art style, measured: the numbers behind docs/pixel-style.md.

Every sprite the game shipped from Retro Diffusion (monsters, props, buildings, tiles, and the weapon and
armour icons shrunk from RD drawings) is the reference: `calibrate` measures them all and writes each
metric's accepted band (the reference's 10th to 90th percentile, per size class) to
tools/pixel_style.json. `check` scores any sprite against those bands, so art drawn in code can be held to
the look RD gave us, and the bands can be re-run as the reference grows.

    python3 tools/pixel_style.py calibrate                 # measure the reference, write the bands
    python3 tools/pixel_style.py check <png>...            # score sprites (exit 1 if any fails)
    python3 tools/pixel_style.py compare                   # reference vs the code-drawn item icons
    python3 tools/pixel_style.py check --kind icon <png>   # pick the band set (icon, creature, scenery)

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
    and tools/armour_art.py made from picked RD drawings; creatures the monsters; scenery props, buildings
    and tiles."""
    assets = json.loads((ROOT / "art" / "assets.json").read_text())["assets"]
    out = {"icon": [], "creature": [], "scenery": []}
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
    import armour_art
    import weapon_art
    rd_items = set(weapon_art.PICKED) | set(armour_art.plan())
    out["icon"] = [SPRITES / f"item_{i}.png" for i in sorted(rd_items) if (SPRITES / f"item_{i}.png").exists()]
    return out


def code_drawn_icons():
    """The item icons tools/item_art.py draws in code (what the style has to lift)."""
    import armour_art
    import weapon_art
    rd_items = set(weapon_art.PICKED) | set(armour_art.plan())
    items = json.loads((ROOT / "content" / "items.json").read_text())["items"]
    return [SPRITES / f"item_{i['id']}.png" for i in items
            if i["id"] not in rd_items and (SPRITES / f"item_{i['id']}.png").exists()]


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
    m["outline_colours"] = int(len(np.unique(np.round(rgb[edge] * 255).astype(int) @ np.array([65536, 256, 1]))))

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

    # Ramps: colours grouped by hue family (saturated ones), shades per family and their hue shift.
    hsv = np.array([colorsys.rgb_to_hsv(*(np.array([(u >> 16) & 255, (u >> 8) & 255, u & 255]) / 255)) for u in uniq])
    fam = {}
    for (h, s, v), c in zip(hsv, counts):
        if s < 0.15 or v < 0.12:
            continue
        fam.setdefault(int(((h * 360 + 15) % 360) // 30), []).append((h * 360, s, v, c))
    big = [f for f in fam.values() if sum(x[3] for x in f) >= max(6, n * 0.06)]
    m["shades_per_ramp"] = float(np.median([len(f) for f in big])) if big else None
    shifts = []
    for f in big:
        if len(f) < 3:
            continue
        f = sorted(f, key=lambda x: x[2])
        dark, light = f[: max(1, len(f) // 3)], f[-max(1, len(f) // 3):]
        hd = np.average([x[0] for x in dark], weights=[x[3] for x in dark])
        hl = np.average([x[0] for x in light], weights=[x[3] for x in light])
        shifts.append(float(warm_distance(np.array(hd)) - warm_distance(np.array(hl))))
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

    # Size and placement in the canvas (icons: centred, filling most of it).
    ys, xs = np.nonzero(opaque)
    h, w = opaque.shape
    m["fill"] = float(max(xs.max() - xs.min() + 1, ys.max() - ys.min() + 1) / max(h, w))
    m["off_centre"] = float(max(abs((xs.min() + xs.max() + 1) / 2 - w / 2), abs((ys.min() + ys.max() + 1) / 2 - h / 2)))
    return m


# Which way each metric fails, and which the bands enforce. Hard criteria must all pass; soft ones are
# scored, and a sprite passes with SOFT_PASS of them. Metrics left out are reported, never judged.
ENFORCED = {
    "semi_alpha": "max", "colour_density": "min", "outline_dark": "min", "outline_sat": "min",
    "outline_value": "both", "flat": "max", "orphans": "max", "shades_per_ramp": "min", "hue_shift": "min",
    "value_range": "min", "light_top_left": "min", "highlight_share": "both", "cluster_size": "both",
}
# Partial transparency is soft: only a light effect (a magic staff's glow) may use it.
HARD = {"colour_density", "flat", "outline_dark", "fill"}
SOFT_PASS = 0.8
# Icons fill most of their tile (fixed rules, not measured bands).
ICON_RULES = {"fill": ("min", 0.78)}
# The band is the reference's 5th to 95th percentile, never narrower than this (a house rule such as the
# icons' one outline colour has no spread at all).
MIN_WIDTH = {"outline_sat": 0.1, "outline_value": 0.1, "outline_dark": 0.04}


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
            kb[name] = {"p10": round(lo - pad, 4), "median": round(float(np.median(vals)), 4),
                        "p90": round(hi + pad, 4)}
        bands["kinds"][kind] = kb
    BANDS.write_text(json.dumps(bands, indent=2) + "\n")
    print(f"wrote {BANDS.relative_to(ROOT)}: " + ", ".join(f"{k} ({v['count']})" for k, v in bands["kinds"].items()))


def judge(m, kind):
    """[(metric, value, band, ok)] for one sprite's metrics against its kind's bands."""
    bands = json.loads(BANDS.read_text())["kinds"][kind]
    out = []
    for name, way in ENFORCED.items():
        if name not in bands or m.get(name) is None:
            continue
        b = bands[name]
        v = m[name]
        low_ok = v >= b["p10"] if way in ("min", "both") else True
        high_ok = v <= b["p90"] if way in ("max", "both") else True
        band = {"min": f"≥{b['p10']}", "max": f"≤{b['p90']}", "both": f"{b['p10']}–{b['p90']}"}[way]
        out.append((name, v, band, low_ok and high_ok))
    if kind == "icon":
        for name, (way, limit) in ICON_RULES.items():
            v = m[name]
            out.append((name, v, ("≥" if way == "min" else "≤") + str(limit), v >= limit if way == "min" else v <= limit))
    return out


def verdict(j):
    """(passes, soft score): every hard criterion, and SOFT_PASS of the soft ones."""
    hard = all(ok for n, *_, ok in j if n in HARD)
    soft = [ok for n, *_, ok in j if n not in HARD]
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
        ok, s = verdict(j)
        res[str(p)] = (ok, s, [(n, round(v, 3), b) for n, v, b, good in j if not good])
    return res


def compare():
    ref = reference()["icon"]
    code = code_drawn_icons()
    for label, paths in (("RD icons (reference)", ref), ("code-drawn icons", code)):
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
            ok, s = verdict(j)
            print(f"{p}: {'PASS' if ok else 'FAIL'} (soft {s:.0%}, needs {SOFT_PASS:.0%} and every hard one)")
            for n, v, b, good in j:
                print(f"   {'✓' if good else '✗'} {n:16} {v:8.3f}   {b}{'   hard' if n in HARD else ''}")
            bad += not ok
        return 1 if bad else 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
