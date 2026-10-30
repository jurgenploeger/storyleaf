#!/usr/bin/env python3
"""The acceptance gate for a new or changed sprite, and a sheet to judge it by eye.

Run from the repo root. Needs Pillow (and numpy, for tools/pixel_style.py).

  sprite_check.py check ID... [--new]
        For each art id: registered in art/assets.json, made by the route its entry says (Retro
        Diffusion's `request`, a `derive`, or a PNG drawn in code), the size its kind takes, hard
        pixels (no partial transparency), a clear background, the house look scored by
        tools/pixel_style.py for its kind, and for characters and creatures the Pixel Heroes marks
        (a dark outline all round, dark lines inside, bright colour). With --new, those marks and
        the style bands fail the check instead of warning (RD's existing sprites are the reference,
        not judged by them). A monster also needs eyes or a reason in art/eyes.json. Exits 1 on a
        failure.
  sprite_check.py review OUT ID... [--with ID,ID]
        Each sprite at 1x and 4x beside four sprites of its kind the game already ships (or the
        ones given), on the map's green and on a dark battle field: the review by eye every sprite
        needs (docs/pixel-style.md, *Review by eye*).
"""
import argparse
import colorsys
import glob
import json
import os
import re
import subprocess
import sys

from PIL import Image, ImageDraw

ROOT = os.getcwd()
SPRITES = os.path.join(ROOT, "art", "sprites")
ASSETS = {a["id"]: a for a in json.load(open(os.path.join(ROOT, "art", "assets.json")))["assets"]}
EYES = json.load(open(os.path.join(ROOT, "art", "eyes.json")))

# The sizes each kind ships at (measured 2026-10-29 over every sprite the game has).
SIZES = {
    "monster": {(40, 40), (64, 64)},
    "walk_sheet": {(192, 192)},
    "tile": {(32, 32)},
    "item": {(64, 64)},
    "icon": {(128, 128)},
    "building": {(96, 96), (160, 160), (192, 192)},
}
# Props come at their family's size: these are the usual ones (77 at 32×32, 33 at 64×64, 11 at 32×48 on
# 2026-10-29); anything else (the ship, 202×328) warns, to be checked against its family by eye.
PROP_SIZES = {(32, 32), (64, 64), (32, 48), (48, 48), (32, 64), (64, 48), (96, 64), (96, 96)}
TOOLS = {p: open(p).read() for p in glob.glob(os.path.join(ROOT, "tools", "*_art.py"))}
# tools/pixel_style.py's band set for each kind.
STYLE_KIND = {"monster": "creature", "prop": "scenery", "building": "building", "item": "item", "tile": "scenery"}
# Kinds whose pixels are all hard: a light-drawn icon (skill and UI icons) is smooth by design.
HARD = {"monster", "walk_sheet", "tile", "building", "prop", "item"}
CHARACTERS = {"monster", "walk_sheet"}


def drawn_by(art_id):
    """The tools/*_art.py that draws this id by name (`"id": draw_...` or `def draw_id`), if one does:
    some assets keep an old `request` but are drawn in code (the ship, the candy cane)."""
    for path, src in TOOLS.items():
        if re.search(r"""["']%s["']\s*:\s*\w*draw""" % re.escape(art_id), src) or re.search(r"def draw_%s\b" % re.escape(art_id), src):
            return os.path.relpath(path, ROOT)
    return None


def png(name):
    path = os.path.join(SPRITES, name + ".png")
    return Image.open(path).convert("RGBA") if os.path.exists(path) else None


def root_png(art_id, depth=0):
    """The picture an id shows, before recolouring: its own PNG, else its paper-doll layers stacked
    (a townsperson), else its base's (a palette swap)."""
    im = png(art_id)
    if im is not None or depth > 4:
        return im
    derive = ASSETS.get(art_id, {}).get("derive") or {}
    if derive.get("layers"):
        layers = [png(l["id"]) for l in derive["layers"]]
        if all(layers):
            out = layers[0]
            for layer in layers[1:]:
                out = Image.alpha_composite(out, layer)
            return out
    base = derive.get("from")
    return root_png(base, depth + 1) if base else None


def luma(p):
    return (0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]) / 255


def front_frame(art_id, im):
    """A walk sheet's standing pose facing you (row 3, column 0); a picture as it is."""
    if ASSETS.get(art_id, {}).get("kind") == "walk_sheet" and im.size == (192, 192):
        return im.crop((0, 96, 48, 144))
    return im


def pixel_heroes_marks(im):
    """sprite-acceptance.md, *Characters and creatures*: the edge's median light at most 0.25 and
    half its pixels darker than 0.25; a fifth of all pixels darker than 0.2; median saturation 0.45
    or more (unless it's a white, grey or black subject)."""
    px = im.load()
    w, h = im.size
    solid = [(x, y) for y in range(h) for x in range(w) if px[x, y][3] >= 128]
    if not solid:
        return None
    s = set(solid)
    edge = [q for q in solid if any((q[0] + dx, q[1] + dy) not in s for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
    edge_l = sorted(luma(px[q]) for q in edge)
    sats = sorted(colorsys.rgb_to_hsv(*(c / 255 for c in px[q][:3]))[1] for q in solid)
    median = lambda v: v[len(v) // 2]
    return {
        "outline_median": median(edge_l),
        "outline_dark_share": sum(1 for v in edge_l if v < 0.25) / len(edge_l),
        "inside_dark_share": sum(1 for q in solid if luma(px[q]) < 0.2) / len(solid),
        "saturation_median": median(sats),
    }


def check(ids, new):
    failures, warnings = [], []

    def fail(i, msg):
        failures.append(f"{i}: {msg}")

    def warn(i, msg):
        (failures if new else warnings).append(f"{i}: {msg}")

    for i in ids:
        a = ASSETS.get(i)
        if a is None:
            fail(i, "not in art/assets.json: register it (id, kind, and `request`, `derive` or a PNG drawn by a tool)")
            continue
        kind = a["kind"]
        own = png(i)
        derive = a.get("derive") or {}
        if derive and own is not None:
            route = "its own PNG (which wins over its derive)"
        elif derive:
            route = "derive from " + derive["from"] + (" in layers" if derive.get("layers") else "")
        elif drawn_by(i):
            route = "code (" + drawn_by(i) + ")"
        else:
            route = "retro diffusion" if a.get("request") else "code"
        if not derive and own is None and not a.get("request"):
            fail(i, "no `request`, no `derive` and no art/sprites PNG: nothing makes it")
            continue
        if not derive and a.get("request") and own is None:
            fail(i, "has a Retro Diffusion `request` but no PNG yet: dry-run, get the user's OK, generate, pick")
            continue
        im = root_png(i)
        if im is None:
            fail(i, f"its base `{a['derive']['from']}` has no PNG")
            continue
        print(f"{i}: {kind}, made by {route}, {im.size[0]}×{im.size[1]}")
        if kind in SIZES and im.size not in SIZES[kind]:
            fail(i, f"{im.size[0]}×{im.size[1]} isn't a size {kind}s ship at ({', '.join(f'{w}×{h}' for w, h in sorted(SIZES[kind]))})")
        if kind == "prop" and im.size not in PROP_SIZES:
            warnings.append(f"{i}: {im.size[0]}×{im.size[1]} is an unusual size for a prop: check it against its family on the review sheet")
        alphas = list(im.getchannel("A").tobytes())
        partial = sum(1 for v in alphas if 0 < v < 255)
        if kind in HARD and partial and not (kind == "item" and ASSETS[i].get("glow")):
            fail(i, f"{partial} half-transparent pixels: pixel art has hard pixels only (docs/pixel-style.md rule 1)")
        if kind != "tile":
            w, h = im.size
            if any(im.getpixel(c)[3] for c in ((0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1))):
                fail(i, "a corner isn't clear: the background has to be transparent (`remove_bg`)")
        if kind in CHARACTERS:
            m = pixel_heroes_marks(front_frame(i, im))
            if m:
                bad = []
                if m["outline_median"] > 0.25 or m["outline_dark_share"] < 0.5:
                    bad.append(f"outline too pale (median {m['outline_median']:.2f}, {m['outline_dark_share']:.0%} dark; wants ≤0.25 and ≥50%)")
                if m["inside_dark_share"] < 0.2:
                    bad.append(f"too few dark lines inside ({m['inside_dark_share']:.0%}; wants ≥20%)")
                if m["saturation_median"] < 0.45:
                    bad.append(f"colour muted (median saturation {m['saturation_median']:.2f}; wants ≥0.45 unless it's a white, grey or black subject)")
                for b in bad:
                    warn(i, "Pixel Heroes look: " + b)
        if kind == "monster" and not a.get("derive"):
            if i not in EYES.get("pictures", {}) and i not in EYES.get("skipped", {}):
                fail(i, "no eyes in art/eyes.json and no `skipped` reason (the sprite-idle-animation skill)")
        style = STYLE_KIND.get(kind)
        if style and own is not None:
            r = subprocess.run([sys.executable, "tools/pixel_style.py", "check", "--kind", style, os.path.join(SPRITES, i + ".png")],
                               capture_output=True, text=True)
            misses = [l.strip() for l in r.stdout.splitlines() if l.strip().startswith("✗")]
            if r.returncode or misses:
                warn(i, f"tools/pixel_style.py --kind {style}: " + "; ".join(misses[:6]))
    for w in warnings:
        print("  ! " + w)
    if failures:
        print(f"✗ {len(failures)} problem(s):")
        for f in failures:
            print("  • " + f)
        return 1
    print(f"✓ {len(ids)} sprite(s) pass" + (" (warnings above are judged against the RD reference, not failures)" if warnings else ""))
    return 0


def neighbours(art_id, n=4):
    """Four RD sprites of the same kind, the same size if any are (else the nearest in size)."""
    kind = ASSETS[art_id]["kind"]
    size = root_png(art_id).size
    pool = [(a["id"], png(a["id"]).size) for a in ASSETS.values()
            if a["kind"] == kind and a.get("request") and a["id"] != art_id and png(a["id"]) is not None]
    same = [i for i, sz in pool if sz == size]
    if not same:
        same = [i for i, sz in sorted(pool, key=lambda q: abs(q[1][0] * q[1][1] - size[0] * size[1]))][:n]
    step = max(1, len(same) // n)
    return same[::step][:n]


def review(out, ids, given):
    missing = [i for i in ids + (given or []) if i not in ASSETS or root_png(i) is None]
    if missing:
        sys.exit("no such sprite (or no PNG yet): " + ", ".join(missing))
    rows = [[i] + (given or neighbours(i)) for i in ids]
    z = 4
    # Each row is laid out for its own sprites, so a 40-pixel monster isn't lost in a row sized for a ship.
    layout = []
    for row in rows:
        frames = [front_frame(a, root_png(a)) for a in row]
        cw = max(f.width for f in frames)
        ch = max(f.height for f in frames)
        layout.append((row, frames, cw, ch))
    width = max(len(row) * (cw * (z + 1) + 24) for row, _, cw, _ in layout)
    height = sum(2 * (ch * z + 30) for _, _, _, ch in layout)
    sheet = Image.new("RGBA", (width, height), (0, 0, 0, 255))
    d = ImageDraw.Draw(sheet)
    y0 = 0
    for row, frames, cw, ch in layout:
        tile = cw * (z + 1) + 24
        for bg in ((112, 160, 88, 255), (24, 30, 46, 255)):
            d.rectangle([0, y0, width, y0 + ch * z + 30], fill=bg)
            for c, (art, f) in enumerate(zip(row, frames)):
                x0 = c * tile + 6
                d.text((x0, y0 + 2), ("> " if c == 0 else "") + art, fill=(255, 255, 255, 255))
                sheet.alpha_composite(f, (x0, y0 + 16))
                sheet.alpha_composite(f.resize((f.width * z, f.height * z), Image.NEAREST), (x0 + cw + 8, y0 + 16))
            y0 += ch * z + 30
    sheet.save(out)
    print("wrote", out, "(first in each row is the one under review)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("check")
    p.add_argument("ids", nargs="+")
    p.add_argument("--new", action="store_true", help="hold it to the target look: style bands and Pixel Heroes marks fail")
    p = sub.add_parser("review")
    p.add_argument("out")
    p.add_argument("ids", nargs="+")
    p.add_argument("--with", dest="given", help="comma-separated ids to show beside it instead of picked ones")
    a = ap.parse_args()
    if a.cmd == "check":
        sys.exit(check(a.ids, a.new))
    review(a.out, a.ids, a.given.split(",") if a.given else None)


if __name__ == "__main__":
    main()
