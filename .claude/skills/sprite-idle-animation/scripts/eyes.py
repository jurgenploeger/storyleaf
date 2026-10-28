#!/usr/bin/env python3
"""Eyes that blink, and breaths in whole pixels: find, preview and check them without a Mac.

A mirror of TalesOfDorlune/Art/IdlePoses.swift (EyeBlink) and the eye parts of ArtLibrary.swift
(stacked shut, cleanFaces, idlePoses). Change both in the same commit, or the checks here stop
meaning anything. Needs Pillow. Run from the repo root.

  eyes.py dump ID X0 Y0 W H [--dir right|down|left]
        Every pixel of a region as a letter, one letter per colour, with each colour's luma: read
        coordinates off this, not off a zoomed picture (off-by-one every time).
  eyes.py zoom OUT ID[@dir][:x0:y0:w:h] ...
        Open, shut and breathing out side by side at 10x, a grid every pixel, labels every 5.
        For a layered townsperson or a hero stack pass layers joined by '+' as the ID
        (e.g. body_human+locks_human+hair_crop_human@down).
  eyes.py sheet OUT [--pictures | --people]
        A contact sheet of every sprite in art/eyes.json, open and shut.
  eyes.py fills [--write]
        Fill pixels that shut eyes in the face's own colour: for people a skin colour shared round
        both eyes, beside each eye; for a monster's pair, one colour for both where their fills
        differ. Prints what it would change; --write puts it in art/eyes.json. Look at the zoom
        after: it's a suggestion, the eye is the judge.
  eyes.py check
        The acceptance checks (see SKILL.md): every entry sound, every monster either has eyes or
        is in `skipped`, pairs that shut alike, and every townsperson and hero combination
        (body x hairstyle x hood, helmet or armour) blinking with both eyes or not at all.
        Exits 1 on a failure.
"""
import argparse
import colorsys
import glob
import json
import os
import sys
from collections import Counter, defaultdict

from PIL import Image, ImageDraw

ROOT = os.getcwd()
SPRITES = os.path.join(ROOT, "art", "sprites")
DIRS = ["up", "right", "down", "left"]  # every walk sheet's rows, top to bottom
FRAME = 48
EYES = json.load(open(os.path.join(ROOT, "art", "eyes.json")))
SHEETS, PICTURES = EYES["sheets"], EYES["pictures"]
SKIPPED = EYES.get("skipped", {})
ASSETS = {a["id"]: a for a in json.load(open(os.path.join(ROOT, "art", "assets.json")))["assets"]}

_png = {}


def png(name):
    if name not in _png:
        path = os.path.join(SPRITES, name + ".png")
        _png[name] = Image.open(path).convert("RGBA") if os.path.exists(path) else None
    return _png[name]


def luma(p):
    return 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]


def opaque(p):
    return p is not None and p[3] >= 128


# ---- the game's rules, as IdlePoses.swift and ArtLibrary.swift have them ---------------------

def layer_key(layer):
    """EyeBlink.key(forLayer:): a body's own eyes, its head's its body's; nothing else has any."""
    if layer.startswith("body_"):
        return layer
    if layer.startswith("head_"):
        return "body_" + layer[5:]
    return None


def place(eyes, direction):
    """Frame coordinates to sheet coordinates: each direction's first frame, column 0."""
    oy = DIRS.index(direction) * FRAME
    return [(x, y + oy, w, h, fx, fy + oy) for x, y, w, h, fx, fy in eyes]


def sheet_eyes(key):
    return [e for d, es in SHEETS[key].items() for e in place(es, d)]


def shut(img, eyes, lash):
    """EyeBlink.shut: all the eyes or none; each filled with its fill pixel's colour; a picture's
    lash two-thirds down in the eye's darkest colour (round it, if the eye has none darker than
    the lid)."""
    src = img.load()
    w_, h_ = img.size

    def at(x, y):
        return src[x, y] if 0 <= x < w_ and 0 <= y < h_ else None

    if not eyes or not all(opaque(at(fx, fy)) for *_, fx, fy in eyes):
        return img
    out = img.copy()
    px = out.load()
    for x, y, w, h, fx, fy in eyes:
        fill = at(fx, fy)

        def darkest(m):
            found = [at(i, j) for j in range(y - m, y + h + m) for i in range(x - m, x + w + m) if opaque(at(i, j))]
            return min(found, key=luma) if found else None

        inside = darkest(0)
        lash_colour = inside if inside and luma(inside) < luma(fill) - 30 else darkest(1)
        for j in range(y, y + h):
            for i in range(x, x + w):
                if opaque(at(i, j)):
                    px[i, j] = fill
        if lash and lash_colour:
            row = y + min(h - 1, h * 2 // 3)
            span = range(x - 1, x + 2) if w == 1 else range(x, x + w)
            for i in span:
                if opaque(at(i, row)):
                    px[i, row] = lash_colour
    return out


def shuts_evenly(open_, shut_, eyes):
    """EyeBlink.shutsEvenly: some pixel of every eye changed as the sprite is finally drawn."""
    o, s = open_.load(), shut_.load()
    return bool(eyes) and all(
        any(o[i, j] != s[i, j] for j in range(y, y + h) for i in range(x, x + w)) for x, y, w, h, _, _ in eyes)


def is_face(layer):
    return layer.startswith(("hat_", "armor_"))


def clean_faces(layers, key):
    """ArtLibrary.cleanFaces: no blink with a helmet's or armour's face over the head; in armour,
    only where the head hides the armour's face two pixels round the eyes."""
    tops = [i for i, l in enumerate(layers) if layer_key(l)]
    if not tops or any(is_face(l) for l in layers[tops[-1] + 1:]):
        return set()
    head = png(layers[tops[-1]]).load()
    under = [png(l).load() for l in layers[:tops[-1]] if is_face(l)]
    clean = set()
    for d, es in SHEETS[key].items():
        ok = True
        for x, y, w, h, _, _ in place(es, d):
            for j in range(y - 2, y + h + 2):
                for i in range(x - 2, x + w + 2):
                    if any(lo[i, j][3] >= 128 for lo in under) and head[i, j][3] < 128:
                        ok = False
        if ok:
            clean.add(d)
    return clean


def exhaled(frame):
    """EyeBlink.exhaled: everything above the waist (55% down what's drawn) a pixel lower."""
    px = frame.load()
    w, h = frame.size
    rows = [y for y in range(h) if any(px[x, y][3] >= 128 for x in range(w))]
    if not rows or rows[-1] - rows[0] <= 4:
        return frame
    top, bottom = rows[0], rows[-1]
    waist = top + (bottom - top) * 55 // 100
    out = frame.copy()
    q = out.load()
    for y in range(waist, top, -1):
        for x in range(w):
            q[x, y] = px[x, y - 1]
    for x in range(w):
        q[x, top] = (0, 0, 0, 0)
    return out


def stack(layers, shut_eyes):
    """ArtLibrary.stacked: each body or head layer shut with its own eyes, then all drawn bottom
    first (no recolour, no GearOverlay: those change colours, not where eyes are)."""
    out = None
    for l in layers:
        im = png(l)
        if im is None:
            return None
        k = layer_key(l)
        if shut_eyes and k in SHEETS:
            im = shut(im, sheet_eyes(k), lash=False)
        out = im.copy() if out is None else Image.alpha_composite(out, im)
    return out


def top_key(layers):
    """ArtLibrary.eyeKey for a stack: the face on top's."""
    return next((layer_key(l) for l in reversed(layers) if layer_key(l) in SHEETS), None)


def judge(layers):
    """Per direction: 'blink', 'off' (clean_faces says no) or 'none'/'uneven' (shutsEvenly says no),
    and the shut composite, as idlePoses decides."""
    key = top_key(layers)
    if key is None:
        return None, None, None
    o, s = stack(layers, False), stack(layers, True)
    if o is None:
        return None, None, None
    clean = clean_faces(layers, key)
    verdict = {}
    for d, es in SHEETS[key].items():
        placed = place(es, d)
        changed = [any(o.getpixel((i, j)) != s.getpixel((i, j)) for j in range(y, y + h) for i in range(x, x + w))
                   for x, y, w, h, _, _ in placed]
        if d not in clean:
            verdict[d] = "off"
        elif all(changed):
            verdict[d] = "blink"
        else:
            verdict[d] = "none" if not any(changed) else "uneven"
    return verdict, o, s


# ---- what there is to check --------------------------------------------------------------------

def eyeish(p):
    """An eye white or a green iris left open (the bodies' eyes are white and green)."""
    if not opaque(p):
        return False
    h, s, v = colorsys.rgb_to_hsv(p[0] / 255, p[1] / 255, p[2] / 255)
    return (s < 0.2 and v > 0.85) or (90 <= h * 360 <= 170 and s > 0.3 and v < 0.75)


def hero_stacks():
    """Every townsperson's layers, and every hero: each body that has eyes, in every hairstyle,
    plain, hooded, under each helmet and in each armour sheet, as GameSession.layers stacks them."""
    stacks = []
    for a in ASSETS.values():
        layers = (a.get("derive") or {}).get("layers")
        if layers:
            stacks.append((a["id"], [l["id"] for l in layers]))
    for body_key in sorted(k for k in SHEETS if k.startswith("body_")):
        body = body_key[5:]
        race = body.split("_")[0]
        if not png("head_" + body):
            continue  # townsfolk only (dwarf_npc): no hero wears it
        styles = sorted({os.path.basename(p)[5:-4][: -len(body) - 1] for p in glob.glob(f"{SPRITES}/hair_*_{body}.png")})
        styles = [s for s in styles if png(f"hair_{s}_{body}")]
        kinds = sorted({os.path.basename(p)[4:-4].rsplit("_", 1)[0] for p in glob.glob(f"{SPRITES}/hat_*_{race}.png")})
        armours = sorted({os.path.basename(p)[6:-4].rsplit("_", 1)[0] for p in glob.glob(f"{SPRITES}/armor_*_{race}.png")})
        for s in styles:
            top = [f"locks_{body}", f"hair_{s}_{body}"]
            stacks.append((f"{body}/{s}/plain", ["body_" + body] + top))
            stacks.append((f"{body}/{s}/hood", ["body_" + body, f"locks_{body}", f"hood_{body}"]))
            for k in kinds:
                stacks.append((f"{body}/{s}/helmet {k}",
                               [f"nape_{s}_{body}", "body_" + body, f"napeback_{s}_{body}", f"hat_{k}_{race}", f"locks_{body}"]))
            for a in armours:
                stacks.append((f"{body}/{s}/armour {a}", [f"armor_{a}_{race}", "head_" + body] + top))
    # A layer a hero doesn't have (no locks for a beardless body) is left out, as the game's are.
    return [(n, [l for l in ls if png(l) is not None]) for n, ls in stacks]


def check():
    problems, notes = [], []
    # 1. Every monster drawn as its own picture has eyes, or a reason it hasn't.
    for a in ASSETS.values():
        if a["kind"] == "monster" and not a.get("derive") and png(a["id"]) is not None:
            if a["id"] not in PICTURES and a["id"] not in SKIPPED:
                problems.append(f"{a['id']}: no eyes in art/eyes.json and not in `skipped` (find them, or say why it has none)")
    for name in list(PICTURES) + list(SHEETS):
        if name in SKIPPED:
            problems.append(f"{name}: both in `skipped` and given eyes")
    # 2. Pictures: both eyes of a pair shut alike.
    for name, eyes in PICTURES.items():
        im = png(name)
        if im is None:
            problems.append(f"{name}: no art/sprites/{name}.png")
            continue
        if len(eyes) == 2:
            widths = {e[2] for e in eyes}
            if len(widths) > 1 and min(widths) == 1:
                problems.append(f"{name}: one eye 1 px wide, the other wider: their lashes differ (3 px against {max(widths)})")
            s = shut(im, eyes, lash=True)
            o, p = im.load(), s.load()
            lashes = []
            for x, y, w, h, fx, fy in eyes:
                row = y + min(h - 1, h * 2 // 3)
                lashes.append(p[x, row])
            if len(set(lashes)) > 1 and abs(luma(lashes[0]) - luma(lashes[1])) > 40:
                problems.append(f"{name}: the two lashes are different colours {lashes[0][:3]} / {lashes[1][:3]}")
        if shut(im, eyes, lash=True) is im:
            problems.append(f"{name}: an eye's fill pixel is clear, so none shut")
    # 3. Fills in the face's own colour (people: skin; a monster's pair: one colour).
    wrong = fills(write=False, quiet=True)
    if wrong:
        problems.append(f"{wrong} fill pixel(s) not in the face's own colour: `eyes.py fills` lists them, `--write` fixes them")
    # 4. Every townsperson and hero combination: both eyes or neither, nothing left open.
    tally = Counter()
    for name, layers in hero_stacks():
        verdict, o, s = judge(layers)
        if verdict is None:
            continue
        key = top_key(layers)
        for d, v in verdict.items():
            group = name.split("/")[-1].split(" ")[0] if "/" in name else "townsfolk"
            tally[(group, v)] += 1
            if v != "blink":
                continue
            for x, y, w, h, _, _ in place(SHEETS[key][d], d):
                left = [(i, j - DIRS.index(d) * FRAME) for j in range(y, y + h) for i in range(x, x + w)
                        if s.getpixel((i, j)) == o.getpixel((i, j)) and eyeish(o.getpixel((i, j)))]
                if left:
                    problems.append(f"{name} {d}: eye at {x},{y - DIRS.index(d) * FRAME} still shows open pixels {left[:4]}")
    for (group, v), n in sorted(tally.items()):
        notes.append(f"{group:10} {v:7} {n}")
    print("Blinking views by kind of stack (blink = both eyes shut; off/none/uneven = it doesn't blink that way):")
    for line in notes:
        print("   ", line)
    if problems:
        print(f"✗ {len(problems)} problem(s):")
        for p in problems:
            print("  •", p)
        return 1
    print(f"✓ Eyes OK: {len(PICTURES)} pictures, {len(SHEETS)} sheets, {len(SKIPPED)} skipped")
    return 0


def skin(p):
    """ArtLibrary.skinBounds' test: a face's skin, not hair, outline or eye."""
    if not opaque(p):
        return False
    h, s_, v = colorsys.rgb_to_hsv(p[0] / 255, p[1] / 255, p[2] / 255)
    h *= 360
    return (h <= 40 or h >= 342) and 0.12 < s_ < 0.65 and v > 0.55


def rings(img, eyes, reach=2):
    """Each eye's ring: the opaque pixels within `reach` of its box and outside every eye's box,
    those in the eye's own rows first (beside it), then the rest by distance."""
    px = img.load()
    w_, h_ = img.size
    inside = {(i, j) for x, y, w, h, _, _ in eyes for j in range(y, y + h) for i in range(x, x + w)}
    out = []
    for x, y, w, h, _, _ in eyes:
        cx, cy = x + (w - 1) / 2, y + (h - 1) / 2
        ring = [(i, j) for j in range(y - reach, y + h + reach) for i in range(x - reach, x + w + reach)
                if (i, j) not in inside and 0 <= i < w_ and 0 <= j < h_ and opaque(px[i, j])]
        ring.sort(key=lambda q: (not (y <= q[1] < y + h), (q[0] - cx) ** 2 + (q[1] - cy) ** 2))
        out.append(ring)
    return out


def suggest_fill(img, eyes, people):
    """Better fill pixels for one view's eyes, or the current ones where they're fine.
    People: a skin colour, the commonest round all the view's eyes, beside each eye where it can be
    (a cheek's shade, a lock of hair or the outline shut an eye in the wrong colour).
    Pictures: left alone unless a pair's fills differ in colour; then both take whichever of the two
    is found round both eyes most, so the pair shuts alike."""
    px = img.load()
    current = [(e[4], e[5]) for e in eyes]
    rs = rings(img, eyes)
    if people:
        counts = Counter(px[q] for r in rs for q in r if skin(px[q]))
        shared = [c for c, _ in counts.most_common() if all(any(px[q] == c for q in r) for r in rs)]
        if not shared:
            return current
        colour = shared[0]
        return [cur if px[cur] == colour else next(q for q in r if px[q] == colour) for cur, r in zip(current, rs)]
    if len(eyes) != 2 or px[current[0]] == px[current[1]]:
        return current
    counts = Counter(px[q] for r in rs for q in r)
    options = [c for c in (px[current[0]], px[current[1]]) if all(any(px[q] == c for q in r) for r in rs)]
    if not options:
        return current
    colour = max(options, key=lambda c: counts[c])
    return [cur if px[cur] == colour else next(q for q in r if px[q] == colour) for cur, r in zip(current, rs)]


def fills(write, quiet=False):
    changed = 0
    say = (lambda *a: None) if quiet else print
    data = json.load(open(os.path.join(ROOT, "art", "eyes.json")))
    for name, dirs in data["sheets"].items():
        im = png(name)
        for d, es in dirs.items():
            if not es:
                continue
            oy = DIRS.index(d) * FRAME
            new = suggest_fill(im, place(es, d), people=True)
            for e, (fx, fy) in zip(es, new):
                if (fx, fy - oy) != (e[4], e[5]):
                    say(f"{name} {d} {e[:4]}: fill {e[4]},{e[5]} {im.getpixel((e[4], e[5] + oy))[:3]} → {fx},{fy - oy} {im.getpixel((fx, fy))[:3]}")
                    e[4], e[5] = fx, fy - oy
                    changed += 1
    for name, es in data["pictures"].items():
        im = png(name)
        new = suggest_fill(im, es, people=False)
        for e, (fx, fy) in zip(es, new):
            if (fx, fy) != (e[4], e[5]):
                say(f"{name} {e[:4]}: fill {e[4]},{e[5]} {im.getpixel((e[4], e[5]))[:3]} → {fx},{fy} {im.getpixel((fx, fy))[:3]}")
                e[4], e[5] = fx, fy
                changed += 1
    if write and changed:
        text = open(os.path.join(ROOT, "art", "eyes.json")).read()
        about = json.loads(text)["_about"]
        lines = ["{", " \"_about\": " + json.dumps(about) + ",", " \"sheets\": {"]
        items = list(data["sheets"].items())
        lines += [f"  {json.dumps(k)}: {json.dumps(v)}" + ("," if i < len(items) - 1 else "") for i, (k, v) in enumerate(items)]
        lines += [" },", " \"pictures\": {"]
        items = list(data["pictures"].items())
        lines += [f"  {json.dumps(k)}: " + json.dumps(v, separators=(",", ":")).replace("],[", "], [") + ("," if i < len(items) - 1 else "")
                  for i, (k, v) in enumerate(items)]
        lines += [" },", " \"skipped\": {"]
        items = list(data.get("skipped", {}).items())
        lines += [f"  {json.dumps(k)}: {json.dumps(v)}" + ("," if i < len(items) - 1 else "") for i, (k, v) in enumerate(items)]
        lines += [" }", "}"]
        open(os.path.join(ROOT, "art", "eyes.json"), "w").write("\n".join(lines) + "\n")
        say(f"wrote {changed} fill(s) to art/eyes.json")
    elif changed:
        say(f"{changed} fill(s) would change; --write to apply")
    else:
        say("every fill is the face's own colour")
    return changed


# ---- looking at them ----------------------------------------------------------------------------

def parse_target(arg):
    """ID or a+b+c layers, optional @dir, optional :x0:y0:w:h crop."""
    crop = None
    if ":" in arg:
        arg, *nums = arg.split(":")
        crop = tuple(int(n) for n in nums)
    direction = None
    if "@" in arg:
        arg, direction = arg.split("@")
    return arg.split("+"), direction, crop


def views(layers, direction):
    """(open, shut, breathing out) frames for a picture, a sheet or a stack."""
    if len(layers) == 1 and layers[0] in PICTURES:
        im = png(layers[0])
        return im, shut(im, PICTURES[layers[0]], True), im
    if len(layers) == 1 and layers[0] in SHEETS:
        im = png(layers[0])
        o, s = im, shut(im, sheet_eyes(layers[0]), False)
    elif len(layers) == 1 and layers[0] in ASSETS and (ASSETS[layers[0]].get("derive") or {}).get("layers"):
        layers = [l["id"] for l in ASSETS[layers[0]]["derive"]["layers"]]
        verdict, o, s = judge(layers)
        print(layers, verdict)
    elif len(layers) == 1:
        im = png(layers[0])
        return im, im, im
    else:
        verdict, o, s = judge(layers)
        print(layers, verdict)
    d = direction or "down"
    oy = DIRS.index(d) * FRAME
    fo, fs = o.crop((0, oy, FRAME, oy + FRAME)), s.crop((0, oy, FRAME, oy + FRAME))
    return fo, fs, exhaled(fo)


def zoom(out, targets, z=10):
    tiles = []
    for t in targets:
        layers, d, crop = parse_target(t)
        frames = views(layers, d)
        x0, y0 = (crop[0], crop[1]) if crop else (0, 0)
        if crop:
            frames = [f.crop((crop[0], crop[1], crop[0] + crop[2], crop[1] + crop[3])) for f in frames]
        tiles.append((t, frames, x0, y0))
    tw = max(f[0].width for _, f, _, _ in tiles) * z
    th = max(f[0].height for _, f, _, _ in tiles) * z
    img = Image.new("RGBA", (3 * tw + 120, len(tiles) * (th + 40)), (120, 170, 120, 255))
    d = ImageDraw.Draw(img)
    for r, (name, frames, x0, y0) in enumerate(tiles):
        oy = r * (th + 40) + 30
        d.text((4, oy - 26), f"{name}   open | shut | breathing out", fill=(0, 0, 0, 255))
        for c, f in enumerate(frames):
            ox = 30 + c * (tw + 30)
            img.alpha_composite(f.resize((f.width * z, f.height * z), Image.NEAREST), (ox, oy))
            for i in range(f.width + 1):
                d.line([(ox + i * z, oy), (ox + i * z, oy + f.height * z)], fill=(0, 0, 0, 150 if (x0 + i) % 5 == 0 else 40))
                if c == 0 and i < f.width and (x0 + i) % 5 == 0:
                    d.text((ox + i * z + 1, oy - 12), str(x0 + i), fill=(0, 0, 0, 255))
            for j in range(f.height + 1):
                d.line([(ox, oy + j * z), (ox + f.width * z, oy + j * z)], fill=(0, 0, 0, 150 if (y0 + j) % 5 == 0 else 40))
                if c == 0 and j < f.height and (y0 + j) % 5 == 0:
                    d.text((4, oy + j * z), str(y0 + j), fill=(0, 0, 0, 255))
    img.save(out)
    print("wrote", out)


def contact(out, which):
    names = (list(PICTURES) if which != "people" else []) + (list(SHEETS) if which != "pictures" else [])
    z, cols = 4, 6
    cw = 64 * z
    img = Image.new("RGBA", (cols * (2 * cw + 10), ((len(names) + cols - 1) // cols) * (cw + 14)), (110, 160, 110, 255))
    d = ImageDraw.Draw(img)
    for k, name in enumerate(names):
        o, s, _ = views([name], "down")
        x, y = (k % cols) * (2 * cw + 10), (k // cols) * (cw + 14)
        d.text((x, y), name, fill=(0, 0, 0, 255))
        for m, f in enumerate((o, s)):
            img.alpha_composite(f.resize((f.width * z, f.height * z), Image.NEAREST), (x + m * cw, y + 14))
    img.save(out)
    print("wrote", out)


def dump(name, x0, y0, w, h, direction):
    im = png(name)
    oy = DIRS.index(direction) * FRAME if direction else 0
    letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    pal = {}
    print(f"{name} {direction or ''}  x from {x0}")
    print("    " + "".join(str(x % 10) for x in range(x0, x0 + w)))
    for y in range(y0, y0 + h):
        row = ""
        for x in range(x0, x0 + w):
            p = im.getpixel((x, oy + y))
            if p[3] < 128:
                row += "."
                continue
            pal.setdefault(p[:3], letters[len(pal) % len(letters)])
            row += pal[p[:3]]
        print(f"{y:3} {row}")
    print("  ".join(f"{v}=#{k[0]:02x}{k[1]:02x}{k[2]:02x} luma {int(luma(k))}" for k, v in pal.items()))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("dump")
    p.add_argument("id")
    p.add_argument("box", nargs=4, type=int)
    p.add_argument("--dir", choices=DIRS)
    p = sub.add_parser("zoom")
    p.add_argument("out")
    p.add_argument("targets", nargs="+")
    p = sub.add_parser("sheet")
    p.add_argument("out")
    g = p.add_mutually_exclusive_group()
    g.add_argument("--pictures", action="store_const", const="pictures", dest="which")
    g.add_argument("--people", action="store_const", const="people", dest="which")
    p = sub.add_parser("fills")
    p.add_argument("--write", action="store_true")
    sub.add_parser("check")
    a = ap.parse_args()
    if a.cmd == "dump":
        dump(a.id, *a.box, a.dir)
    elif a.cmd == "zoom":
        zoom(a.out, a.targets)
    elif a.cmd == "sheet":
        contact(a.out, a.which)
    elif a.cmd == "fills":
        fills(a.write)
    else:
        sys.exit(check())


if __name__ == "__main__":
    main()
