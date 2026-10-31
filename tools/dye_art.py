#!/usr/bin/env python3
"""Dyes on gear (TalesOfDorlune/Content/Dyes.swift): each piece's main colour and its trim, mirrored here
to tune and check them without a Mac.

A dye takes a piece's main material, or its trim, to the dye's colour (`DyeDef.rule(onto:)`): its hue,
its saturation (half the material's own shading in saturation kept) and its brightness round the
material's middle, the ramp kept from dark to light but squeezed so the lightest still fits under white.
What a material is, on each kind of armour sheet, its hats, the outfit under drawn-on armour and the
trims, is Dyes.swift's `DyeDef.materials` table, which this tool reads, so the two can't drift apart.

The trim of an armour sheet or its hat is a layer of its own (`<sheet>_trim.png`), cut out of the sheet
here: the pixels in its trim colours (`TRIMS`, each layer's windows), never a hand or a face (the
paper-doll body's hands and face) and, under a dwarf's hat, never the gold hair round his face. The
game lays it over the sheet in the trim's colour when a piece is dyed a trim.

    python3 tools/dye_art.py cut              # writes the trim layers, prints each material's numbers
    python3 tools/dye_art.py check            # every dye on every kind, main and trim: pass or fail
    python3 tools/dye_art.py hafts            # writes each axe's handle layer (<art>_haft.png)
    python3 tools/dye_art.py --sheet out.png  # contact sheet: every dye on every kind, at 4x

Needs pillow, numpy and scipy.
"""
import glob
import json
import pathlib
import re
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPRITES = ROOT / "art" / "sprites"
SWIFT = ROOT / "TalesOfDorlune" / "Content" / "Dyes.swift"
RACES = ["human", "elf", "dwarf"]
KINDS = ["iron_plate", "chain_mail", "dragon_mail", "mage_robe", "ranger_cloak", "snow_cloak"]
HAT_KINDS = KINDS + ["hide_hood"]
# Where a race's eyes are in a frame (art/eyes.json): a dwarf's hair under a hat starts a little above.
EYE = {"human": 20, "elf": 20, "dwarf": 26}

# Each trim layer's colours: (hue from, hue to, saturation from, to, value from, to), a hue window that
# wraps round red when from > to. Measured on the sheets (2026-10-30): a robe's gold sash and hem, a
# plate's red sash (a human's) or gold collar and belt (an elf's), a dragon mail's gold, a ranger's
# gold clasps, a hide hood's fur lining. Under a hat the gold is the more saturated: an elf's face is a
# pale gold. Chain mail's only second colour is its undershirt, the same
# reds and browns as the hands; a snow cloak has none; nor do a ranger's hood (its gold is the face's),
# a dwarf's wizard hat (its gold is his hair) or a dwarf's plate (a few spots on the hands).
TRIMS = {
    "armor_mage_robe_human": [(45, 62, 0.33, 1, 0.4, 1)],
    "armor_mage_robe_elf": [(45, 62, 0.5, 1, 0.5, 1)],
    "armor_mage_robe_dwarf": [(30, 62, 0.8, 1, 0.55, 1)],
    "armor_iron_plate_human": [(340, 22, 0.4, 1, 0.2, 1)],
    "armor_iron_plate_elf": [(38, 62, 0.65, 1, 0.3, 1), (320, 345, 0.4, 1, 0.3, 1)],
    "armor_dragon_mail_human": [(35, 62, 0.45, 1, 0.5, 1)],
    "armor_dragon_mail_elf": [(35, 62, 0.45, 1, 0.5, 1)],
    "armor_dragon_mail_dwarf": [(35, 62, 0.45, 1, 0.5, 1)],
    "armor_ranger_cloak_human": [(40, 62, 0.33, 1, 0.5, 1)],
    "armor_ranger_cloak_elf": [(40, 62, 0.33, 1, 0.5, 1)],
    "armor_ranger_cloak_dwarf": [(40, 62, 0.33, 1, 0.5, 1)],
    "hat_mage_robe_human": [(44, 62, 0.4, 0.8, 0.4, 1)],
    "hat_iron_plate_human": [(38, 62, 0.65, 1, 0.3, 1)],
    "hat_iron_plate_elf": [(38, 62, 0.65, 1, 0.3, 1)],
    "hat_iron_plate_dwarf": [(30, 62, 0.5, 1, 0.4, 1)],
    "hat_dragon_mail_human": [(35, 62, 0.6, 1, 0.5, 1)],
    "hat_dragon_mail_elf": [(35, 62, 0.6, 1, 0.5, 1)],
    "hat_dragon_mail_dwarf": [(35, 62, 0.6, 1, 0.5, 1)],
    "hat_hide_hood_human": [(42, 65, 0.12, 0.5, 0.5, 1)],
    "hat_hide_hood_elf": [(42, 65, 0.12, 0.5, 0.5, 1)],
    "hat_hide_hood_dwarf": [(42, 65, 0.12, 0.5, 0.5, 1)],
}
# A layer with fewer trim pixels than this over its 16 frames isn't worth one.
MIN_TRIM = 40

# The main material of each kind of sheet (DyeDef.materials), as the tiers' tints find it.
MAINS = {
    "iron_plate": dict(hue=[140, 260], minSaturation=0.05),
    "chain_mail": dict(hue=[150, 260], minSaturation=0.03),
    "dragon_mail": dict(hue=[335, 25], minSaturation=0.55),
    "mage_robe": dict(hue=[190, 260], minSaturation=0.2),
    "ranger_cloak": dict(hue=[70, 170], minSaturation=0.2),
    "snow_cloak": dict(hue=[180, 250], minSaturation=0.1),
    "hide_hood": dict(hue=[180, 260], minSaturation=0.2),
    "outfit": dict(hue=[85, 170], minSaturation=0.3),   # the tunic under drawn-on armour
}
DARK = 0.2   # outlines and the darkest shadows keep their colour (DyeDef.rule(onto:) `minValue`)
# The same on an icon or a held sprite (Recolor.dyeRules `outline`), just over the held sprites' own
# outline, #231834 at 0.204 on all 214 of them: at 0.2 a blue steel's dye took it, and a Crimson axe's
# handle had a red outline (playtesting 2026-10-31: "The handle of the axe has a weird red outline").
ICON_DARK = 0.21


# MARK: the game's colour maths (Recolor.swift)

def hsv(rgb):
    """Recolor.hsv on an (..., 3) array of 0-1 values: hue in degrees."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    d = mx - mn
    safe = np.where(d > 0, d, 1)
    hr = 60 * np.fmod((g - b) / safe, 6)
    hg = 60 * ((b - r) / safe + 2)
    hb = 60 * ((r - g) / safe + 4)
    h = np.where(d > 0, np.where(mx == r, hr, np.where(mx == g, hg, hb)), 0)
    h = np.where(h < 0, h + 360, h)
    s = np.where(mx > 0, d / np.where(mx > 0, mx, 1), 0)
    return h, s, mx


def rgb(h, s, v):
    c = v * s
    x = c * (1 - np.abs(np.fmod(h / 60, 2) - 1))
    m = v - c
    z = np.zeros_like(h)
    sector = [(h < 60), (h < 120), (h < 180), (h < 240), (h < 300)]
    r = np.select(sector, [c, x, z, z, x], c)
    g = np.select(sector, [x, c, c, x, z], z)
    b = np.select(sector, [z, z, x, c, c], x)
    return np.stack([r + m, g + m, b + m], -1)


def matches(rule, h, s, v):
    m = (s >= (rule.get("minSaturation") if rule.get("minSaturation") is not None else 0.15)) & \
        (s <= (rule.get("maxSaturation") if rule.get("maxSaturation") is not None else 1)) & \
        (v >= (rule.get("minValue") or 0)) & (v <= (rule.get("maxValue") if rule.get("maxValue") is not None else 1))
    hue = rule.get("hue")
    if hue:
        m &= ((h >= hue[0]) & (h <= hue[1])) if hue[0] <= hue[1] else ((h >= hue[0]) | (h <= hue[1]))
    return m


def distance(rule, h):
    hue = rule.get("hue")
    if not hue:
        return np.zeros_like(h)
    width = hue[1] - hue[0] if hue[0] <= hue[1] else hue[1] + 360 - hue[0]
    d = np.fmod(h - hue[0] - width / 2, 360)
    return np.where(d > 180, d - 360, np.where(d < -180, d + 360, d))


def apply(rules, image):
    """Recolor.apply: the first rule that matches each opaque pixel recolours it. Returns the image and
    which rule (index, -1 for none) took each pixel."""
    a = image.astype(float) / 255
    out = a.copy()
    h, s, v = hsv(a[..., :3])
    taken = np.full(h.shape, -1)
    free = a[..., 3] > 0
    for index, rule in enumerate(rules):
        m = free & matches(rule, h, s, v)
        free &= ~m
        taken[m] = index
        nh = h.copy()
        if rule.get("to") is not None:
            nh = rule["to"] + (rule.get("spread") or 0) * distance(rule, h)
        nh = np.fmod(nh, 360)
        nh = np.where(nh < 0, nh + 360, nh)
        ns = np.clip(s * (rule.get("saturation") if rule.get("saturation") is not None else 1)
                     + (rule.get("saturationOffset") or 0), 0, 1)
        nv = np.clip(v * (rule.get("value") if rule.get("value") is not None else 1)
                     + (rule.get("valueOffset") or 0), 0, 1)
        out[..., :3] = np.where(m[..., None], rgb(nh, ns, nv), out[..., :3])
    return (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), taken


# MARK: Dyes.swift

def materials():
    """DyeDef.mains and DyeDef.trims, read from Dyes.swift."""
    text = SWIFT.read_text()
    tables = []
    for name in ("mains", "trims"):
        start = text.index(f"static let {name}:")
        body = text[start:text.index("\n    ]", start)]
        table = {}
        for key, entry_text in re.findall(r'"(\w+)": DyeMaterial\(([^)]*)\)', body):
            entry = {}
            for field, value in re.findall(r"(\w+): (\[[^\]]*\]|[\d.]+)", entry_text):
                entry[field] = json.loads(value) if value.startswith("[") else float(value)
            table[key] = entry
        tables.append(table)
    return tables


def dyes():
    items = json.loads((ROOT / "content" / "items.json").read_text())["items"]
    return [(item["id"], item["dye"]) for item in items if item.get("dye")]


def rule_onto(dye, m):
    """DyeDef.rule(onto:): the material `m` taken to the dye's colour."""
    top = lightest(dye)
    # Room to keep the shading: the middle may sit a little under the dye's own (SLACK, a white's more),
    # so the ramp needn't be squeezed flat under white (playtesting 2026-10-31: "make sure that the dyed
    # items don't lose the details like shadows and highlights").
    # A light dye's: a dark one has no white to fit under, its shadows black to stay over.
    slack = (SLACK_WHITE if dye["saturation"] < 0.1 else SLACK) * min(1, max(0, (dye["value"] - 0.5) / 0.2))
    # A dark dye's the other way: its middle may sit a little over its own, so its shadows have room
    # over black (`rise`, DyeDef.rise; a blackish Midnight on a bright blade squeezed it flat).
    rise = SLACK * min(1, max(0, (0.5 - dye["value"]) / 0.2))
    middle = dye["value"] + rise
    # Its darkest (the material's least, `minValue`) no darker than FLOOR, nor its lightest past `top`.
    least = m["minValue"] if m.get("minValue") is not None else 0.2
    # Never more contrast than it had, unless brightening a dark one as before (`value` over its middle).
    gain = max(0.3, min(max(1, dye["value"] / m["value"]),
                        (middle - slack - FLOOR) / max(0.01, m["value"] - least),
                        (top - dye["value"] + slack) / max(0.01, m["light"] - m["value"])))
    return dict(hue=m.get("hue"), minSaturation=m.get("minSaturation", 0), maxSaturation=m.get("maxSaturation"),
                minValue=m.get("minValue"), to=dye["hue"], spread=0.25,
                saturation=0.5 * dye["saturation"] / m["saturation"], saturationOffset=0.5 * dye["saturation"],
                value=gain, valueOffset=min(middle - gain * m["value"], top - gain * m["light"]))


def rules_onto(dye, m):
    """DyeDef.rules(onto:): `rule_onto`, and under it, where that squeezed the ramp to fit a light dye under
    white, a rule of the material's shadows (its middle and darker) that keeps their contrast: up to
    SHADOW_GAIN (a white's SHADOW_GAIN_WHITE) and no darker than FLOOR. Squeezed whole, a Snow White
    plate's deepest shadow sat at 0.76 and it read as one white blob (playtesting 2026-10-31: "This
    looks too white")."""
    main = rule_onto(dye, m)
    least = m["minValue"] if m.get("minValue") is not None else 0.2
    middle = main["valueOffset"] + main["value"] * m["value"]
    most = dye.get("shadowGain") or (SHADOW_GAIN_WHITE if dye["saturation"] < 0.1 else SHADOW_GAIN)
    gain = max(main["value"], min(most, (middle - FLOOR) / max(0.01, m["value"] - least)))
    if gain <= main["value"] + 1e-6:
        return [main]
    shadows = dict(main, maxValue=m["value"], value=gain, valueOffset=middle - gain * m["value"])
    # A dye's own shadow colour (items.json `shadowHue`, `shadowSaturation`): gold's warmer, toward
    # amber, white's a cool blue grey, so the ramp turns as it darkens, as drawn shading does.
    if dye.get("shadowHue") is not None:
        shadows["to"] = dye["shadowHue"]
    if dye.get("shadowSaturation") is not None:
        shadows["saturation"] = 0.5 * dye["shadowSaturation"] / m["saturation"]
        shadows["saturationOffset"] = 0.5 * dye["shadowSaturation"]
    return [shadows, main]


SHADED = rules_onto   # how an icon's dyed family is recoloured (a preview can swap it)


# How far under a dye's own brightness a piece's middle may sit, to keep its shading (DyeDef.slack).
SLACK = 0.08
SLACK_WHITE = 0.12
# How much contrast a light dye's shadows keep where its lights are squeezed under white (`rules_onto`,
# DyeDef.shadowGain): all they had, a white's more, so its plate still has a deep shadow and an edge.
SHADOW_GAIN = 1.0
SHADOW_GAIN_WHITE = 2.0
# The darkest a dyed piece's material goes (DyeDef.floor): just over black, so its deepest shadow still
# reads as part of it.
FLOOR = 0.06


def lightest(dye):
    """DyeDef.lightest: the brightest a dye's shine goes. White for a light dye; for a dark one, down
    toward halfway from its colour to white, the darker the further (from 0.7 down to 0.3): a Midnight
    plate's shine at 0.8 read as white beside its 0.32 navy (playtesting 2026-10-31)."""
    darkness = min(1, max(0, (0.7 - dye["value"]) / 0.4))
    return 1 - 0.5 * (1 - dye["value"]) * darkness


# How far, in degrees, a barely coloured family's hue may lie from the greys' own and still be one
# material with them (Recolor.dyeRules `greyReach`): a teal steel's blade and its grey shine.
GREY_REACH = 60
# How big, against the bigger family, the one nearer a weapon's tip has to be to be its main colour
# (Recolor.dyeRules `tipShare`).
TIP_SHARE = 1 / 3


def icon_rules(picture, main, trim, weapon, target=None):
    """Recolor.dyeRules: a picture's main colour and trim, found on it (and measured on `target`, a held
    sprite shrunk from it), taken to the two dyes. Returns the rules, and which are the main colour's and
    which the trim's (None for none)."""
    def colours(pic):
        a = pic.astype(float) / 255
        h, s, v = hsv(a[..., :3])
        ys, xs = np.nonzero((a[..., 3] >= 128 / 255) & (v >= ICON_DARK))
        return h[ys, xs], s[ys, xs], v[ys, xs], xs, ys

    h, s, v, xs, ys = colours(picture)
    windows = []
    left = s >= 0.25
    for _ in range(2):
        if not left.any():
            break
        hist = np.zeros(36)
        for b in np.minimum(35, (h[left] / 10).astype(int)):
            hist[b] += 1
        smooth = np.array([sum(hist[(b + d) % 36] for d in range(-2, 3)) for b in range(36)])
        peak = int(np.argmax(smooth))
        middle = peak * 10 + 5
        windows.append(dict(hue=[float(np.fmod(middle - 40 + 360, 360)), float(np.fmod(middle + 40, 360))],
                            minSaturation=0.25, minValue=ICON_DARK))
        left = left & (np.abs(np.fmod(h - middle + 540, 360) - 180) > 40)
    windows.append(dict(hue=None, minSaturation=0.02, maxSaturation=0.25, minValue=ICON_DARK))

    def families(h, s, v):
        free = np.ones(h.shape, bool)
        found = []
        for w in windows:
            m = free & matches(w, h, s, v)
            free &= ~m
            found.append(m)
        return found

    own = families(h, s, v)
    # A metal's tinted greys and its faintly blue shading are one material (Recolor.dyeRules).
    grey = len(windows) - 1
    group = list(range(len(windows)))
    tinted = own[grey] & (s >= 0.05)
    if tinted.any():
        y, x = float(np.sin(h[tinted] * np.pi / 180).sum()), float(np.cos(h[tinted] * np.pi / 180).sum())
        grey_hue = float(np.fmod(np.arctan2(y, x) * 180 / np.pi + 360, 360))
        for i in range(grey):
            if own[i].any():
                middle = float(np.sort(s[own[i]])[int(own[i].sum()) // 2])
                lo, hi = windows[i]["hue"]
                centre = np.fmod(lo + (np.fmod(hi - lo + 360, 360)) / 2, 360)
                if middle < 0.45 and abs(np.fmod(grey_hue - centre + 540, 360) - 180) <= GREY_REACH:
                    group[i] = grey

    def members(found, of):
        out = np.zeros(found[0].shape, bool)
        for i in range(len(windows)):
            if group[i] == of:
                out |= found[i]
        return out

    least = max(12, 0.04 * len(h))
    ranked = sorted([i for i in range(len(windows)) if group[i] == i and members(own, i).sum() >= least],
                    key=lambda i: (-int(members(own, i).sum()), i))
    if not ranked:
        return [], None, None
    main_at = ranked[0]
    trim_at = ranked[1] if len(ranked) > 1 else None

    def tip(i):
        m = members(own, i)
        return float(np.mean(xs[m] - ys[m]))

    # The family nearer the tip is the blade or the staff's head, so its main colour, if it's a good
    # part of the picture: a small gem or band near the tip is an accent, its trim.
    if weapon and trim_at is not None and tip(trim_at) > tip(main_at) \
            and members(own, trim_at).sum() >= TIP_SHARE * members(own, main_at).sum():
        main_at, trim_at = trim_at, main_at
    if target is not None:
        th, ts, tv, _, _ = colours(target)
        measured = families(th, ts, tv)
    else:
        th, ts, tv, measured = h, s, v, own
    rules = []
    at = []   # each window's rules (a dyed one's shadows get one of their own, `rules_onto`)
    for i, w in enumerate(windows):
        of = group[i]
        dye = main if of == main_at else trim if of == trim_at else None
        if dye is None:
            at.append([len(rules)])
            rules.append(dict(w))
            continue
        found = members(measured, of)
        ss, vv = (np.sort(ts[found]), np.sort(tv[found])) if found.any() else (np.sort(s[members(own, of)]), np.sort(v[members(own, of)]))
        # Its lightest is its very lightest: a picture's few highlights would clip to white.
        m = dict(w, saturation=max(0.02, float(ss[len(ss) // 2])), value=float(vv[len(vv) // 2]), light=float(vv[-1]))
        made = SHADED(dye, m)
        at.append(list(range(len(rules), len(rules) + len(made))))
        rules.extend(made)
    # Which rules are the main colour's and the trim's (a family can have two windows).
    def rules_of(of, dye):
        return [r for i in range(len(windows)) if group[i] == of for r in at[i]] if dye is not None and of is not None else None
    return rules, rules_of(main_at, main), rules_of(trim_at, trim)


# MARK: cutting the trim layers

def load(name):
    return np.asarray(Image.open(SPRITES / f"{name}.png").convert("RGBA"))


def union(pattern):
    found = None
    for path in sorted(glob.glob(str(SPRITES / pattern))):
        alpha = np.asarray(Image.open(path).convert("RGBA"))[..., 3] > 0
        found = alpha if found is None else (found | alpha)
    return found


def skin_like(a):
    """GearOverlay's skin test."""
    h, s, v = hsv(a[..., :3].astype(float) / 255)
    return (a[..., 3] > 127) & ((h <= 40) | (h >= 342)) & (s > 0.12) & (s < 0.65) & (v > 0.55)


def hands(race):
    """The paper-doll bodies' hands: their skin but the face, frame by frame, a pixel round."""
    out = None
    for path in sorted(glob.glob(str(SPRITES / f"body_{race}*.png"))):
        if path.endswith("_npc.png"):
            continue
        a = np.asarray(Image.open(path).convert("RGBA"))
        skin = skin_like(a)
        mask = np.zeros_like(skin)
        for fy in range(0, a.shape[0], 48):
            for fx in range(0, a.shape[1], 48):
                frame = skin[fy:fy + 48, fx:fx + 48]
                labels, n = ndimage.label(frame)
                if n == 0:
                    continue
                sizes = ndimage.sum(frame, labels, range(1, n + 1))
                face = 1 + int(np.argmax(sizes))
                mask[fy:fy + 48, fx:fx + 48] = (labels > 0) & (labels != face)
        mask = ndimage.binary_dilation(mask, iterations=1)
        out = mask if out is None else (out | mask)
    return out


def keep_off(name, race):
    """Where a trim never goes: on a sheet the head, a dwarf's beard and the hands; under a dwarf's hat his
    face and hair."""
    if name.startswith("armor_"):
        # A dwarf's sheet has his beard drawn on it in gold; an elf's collar lies where a beard would.
        beard = union(f"locks_{race}*.png") if race == "dwarf" else False
        return union(f"head_{race}*.png") | beard | hands(race)
    shape = load(name).shape[:2]
    if race != "dwarf":
        return np.zeros(shape, bool)
    zone = union(f"locks_{race}*.png") | union(f"hair_*_{race}*.png") | union(f"head_{race}*.png")
    rows = np.zeros(shape, bool)
    for fy in range(0, shape[0], 48):
        rows[fy + EYE[race] - 3:fy + 48, :] = True
    return zone & rows


def trim_mask(name):
    a = load(name)
    h, s, v = hsv(a[..., :3].astype(float) / 255)
    mask = np.zeros(h.shape, bool)
    for w in TRIMS[name]:
        mask |= matches(dict(hue=[w[0], w[1]], minSaturation=w[2], maxSaturation=w[3], minValue=w[4], maxValue=w[5]), h, s, v)
    return mask & (a[..., 3] > 127) & ~keep_off(name, name.rsplit("_", 1)[1])


def measure(pixels):
    """A material's numbers: the median saturation and value, and the value of its lightest 5%."""
    h, s, v = hsv(pixels[:, :3].astype(float) / 255)
    keep = v >= DARK
    s, v = np.sort(s[keep]), np.sort(v[keep])
    return dict(saturation=round(max(0.02, float(s[len(s) // 2])), 2), value=round(float(v[len(v) // 2]), 2),
                light=round(float(v[min(len(v) - 1, int(0.95 * len(v)))]), 2))


def main_pixels(kind, names=None):
    rule = dict(MAINS[kind], minValue=DARK)
    if names is None:
        names = ([f"body_{r}" for r in RACES] if kind == "outfit" else
                 [f"armor_{kind}_{r}" for r in RACES if kind in KINDS] + [f"hat_{kind}_{r}" for r in RACES])
    found = []
    for name in names:
        a = load(name)
        h, s, v = hsv(a[..., :3].astype(float) / 255)
        found.append(a[(a[..., 3] > 127) & matches(rule, h, s, v)])
    return np.concatenate(found)


def main_line(key, kind, names=None):
    rule = MAINS[kind]
    m = measure(main_pixels(kind, names))
    return (f'"{key}": DyeMaterial(hue: [{rule["hue"][0]}, {rule["hue"][1]}], minSaturation: {rule["minSaturation"]}, '
            f'minValue: {DARK}, saturation: {m["saturation"]}, value: {m["value"]}, light: {m["light"]}),')


def cut():
    mains = [main_line(kind, kind) for kind in MAINS]
    for kind in HAT_KINDS:
        for race in RACES:
            for art in ([f"armor_{kind}_{race}"] if kind in KINDS else []) + [f"hat_{kind}_{race}"]:
                mains.append(main_line(art, kind, [art]))
    trims = []
    for path in glob.glob(str(SPRITES / "*_trim.png")):
        pathlib.Path(path).unlink()
    for name in TRIMS:
        mask = trim_mask(name)
        if mask.sum() < MIN_TRIM:
            print(f"{name}: only {mask.sum()} trim pixels, no layer")
            continue
        a = load(name).copy()
        a[~mask] = 0
        Image.fromarray(a).save(SPRITES / f"{name}_trim.png")
        m = measure(a[mask])
        trims.append(f'"{name}": DyeMaterial(saturation: {m["saturation"]}, value: {m["value"]}, light: {m["light"]}),')
        print(f"art/sprites/{name}_trim.png  {mask.sum()} pixels")
    print("\nDyeDef.mains:\n" + "\n".join(mains) + "\n\nDyeDef.trims:\n" + "\n".join(trims))
    print("\nDyeDef.oneColour:\n" + ", ".join(f'"{w}"' for w in one_colour()))


def one_colour():
    """The weapons whose icon has no second colour to take a trim (a wooden sword, a steel one whose hilt
    is as dark as its outline): DyeDef.oneColour."""
    items = json.loads((ROOT / "content" / "items.json").read_text())["items"]
    dye = dyes()[0][1]
    return sorted(item["id"] for item in items if item["type"] == "weapon" and item.get("art")
                  and (SPRITES / f"{item['art']}.png").exists() and icon_rules(load(item["art"]), None, dye, True)[2] is None)


# MARK: checking

def circular_median(hues):
    """The median hue, measured round the mean so a red split across 0 doesn't fall in the middle."""
    angle = np.degrees(np.arctan2(np.sin(np.radians(hues)).mean(), np.cos(np.radians(hues)).mean()))
    offset = np.fmod(hues - angle + 540, 360) - 180
    return float(np.fmod(angle + np.median(offset) + 360, 360))


# How much of a piece's light-to-dark spread a dye has to keep (`verdict`), where it has one to keep
# (0.05 at least): a quarter let a white or a gold squeeze a piece's shading nearly flat under white
# (477 cases failed 0.3 before the dyes kept their shading, playtesting 2026-10-31).
RAMP_KEPT = 0.28


def verdict(dye, before, after, held=False):
    """Whether the recoloured pixels read as the dye: hue, saturation, brightness, and a ramp kept."""
    solid = before[:, 3] >= 128 if before.shape[1] > 3 else np.ones(len(before), bool)   # a glow's faint halo isn't the material
    before, after = before[solid], after[solid]
    if len(after) == 0:
        return None
    h0, s0, v0 = hsv(before[:, :3].astype(float) / 255)
    h, s, v = hsv(after[:, :3].astype(float) / 255)
    lit = v0 >= DARK
    h, s, v, v0 = h[lit], s[lit], v[lit], v0[lit]
    if len(v) == 0:
        return None
    white = dye["saturation"] < 0.1
    mh, ms, mv = circular_median(h[s > 0.05]) if (s > 0.05).any() else 0, float(np.median(s)), float(np.median(v))
    hue_ok = white or abs(np.fmod(mh - dye["hue"] + 540, 360) - 180) <= 15
    sat_ok = ms <= 0.15 if white else ms >= 0.6 * dye["saturation"]
    # White can't sit at its own 0.96 and keep a ramp on a dark, wide one: very pale is what it must read.
    # A held sprite is a few dozen pixels, most of them its edges' shading, so its middle sits in its
    # shadows, which keep their depth (`rules_onto`): it reads as the dye a little lower.
    val_ok = mv >= (0.68 if held else 0.75) if white else abs(mv - dye["value"]) <= (0.2 if held else 0.15)
    spread0 = np.percentile(v0, 90) - np.percentile(v0, 10)
    spread = np.percentile(v, 90) - np.percentile(v, 10)
    # A few pixels (a held sprite's clasp) can't hold a ramp; more keep at least RAMP_KEPT of theirs, so
    # its shadows and highlights still show (playtesting 2026-10-31).
    ramp_ok = len(v) < 12 or spread0 < 0.05 or (len(np.unique(np.round(v, 3))) >= min(3, len(np.unique(np.round(v0, 3))))
                                                 and spread >= RAMP_KEPT * spread0 - 1e-6)
    return dict(ok=bool(hue_ok and sat_ok and val_ok and ramp_ok), hue=mh, sat=ms, val=mv, spread=(spread, spread0),
                fails="".join(c for c, ok in (("h", hue_ok), ("s", sat_ok), ("v", val_ok), ("r", ramp_ok)) if not ok))


def sheet_cases(tables, dye):
    """(label, original pixels, recoloured pixels) for each kind of sheet and hat, main and trim."""
    mains, trims = tables
    for kind in HAT_KINDS:
        names = ([f"armor_{kind}_{r}" for r in RACES] if kind in KINDS else []) + [f"hat_{kind}_{r}" for r in RACES]
        for name in names:
            a = load(name)
            out, taken = apply(rules_onto(dye, mains.get(name, mains[kind])), a)
            yield f"main {name}", a[taken >= 0], out[taken >= 0]
    for name in TRIMS:
        if name not in trims:
            continue
        a = load(name + "_trim")
        out, taken = apply(rules_onto(dye, trims[name]), a)
        yield f"trim {name}", a[taken >= 0], out[taken >= 0]
    for race in RACES:
        a = load(f"body_{race}")
        out, taken = apply(rules_onto(dye, mains["outfit"]), a)
        yield f"main body_{race}", a[taken >= 0], out[taken >= 0]


def painted_cases(dye):
    """Gloves and boots (GearOverlay.trinkets: the colour scaled by what's under it), a hide cloak and
    drawn-on armour's trim (the cape's `shade`, branch claude/cloak-colour)."""
    c = np.array([int(dye["color"][i:i + 2], 16) for i in (1, 3, 5)]) / 255
    for label, ks in (("gloves", np.linspace(0.5 + 0.6 * 0.55, 0.5 + 0.6 * 1.0, 8)),
                      ("boots", np.linspace(0.55 + 0.9 * 0.3, 0.55 + 0.9 * 0.75, 8))):
        px = np.clip(np.outer(ks, c), 0, 1)
        yield label, np.tile((c * 255).astype(np.uint8), (8, 1)), (px * 255 + 0.5).astype(np.uint8)
    ks = np.linspace(0.6, 1.3, 8)
    yield "hide cloak", np.tile((c * 255).astype(np.uint8), (8, 1)), np.array([shade(c, k) for k in ks])


def shade(colour, k):
    """GearOverlay.shade (claude/cloak-colour): hue kept, value * k^0.45, saturation * (1 - 0.12 * max(0, k - 1)),
    hue + 6 * (k - 1) degrees when saturated."""
    h, s, v = hsv(np.array(colour)[None, :])
    h, s, v = h[0], s[0], v[0]
    if s > 0.1:
        h = np.fmod(h + 6 * (k - 1) + 360, 360)
    out = rgb(np.array([h]), np.array([s * (1 - 0.12 * max(0, k - 1))]), np.array([min(1, v * k ** 0.45)]))[0]
    return (np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8)


def item_cases(dye, kinds=("armor", "head", "gloves", "boots", "weapon")):
    items = json.loads((ROOT / "content" / "items.json").read_text())["items"]
    for item in items:
        if item["type"] not in kinds or (item["type"] == "head" and item.get("hat")) or not item.get("art"):
            continue
        path = SPRITES / f"{item['art']}.png"
        if not path.exists():
            continue
        icon = load(item["art"])
        weapon = item["type"] == "weapon"
        for role in ("main", "trim"):
            pictures = [("icon", icon, None)]
            if weapon and (SPRITES / f"held_{item['id']}_side.png").exists():
                held = load(f"held_{item['id']}_side")
                pictures.append(("held", held, held))
            for what, pic, target in pictures:
                rules, main_at, trim_at = icon_rules(icon, dye if role == "main" else None, dye if role == "trim" else None,
                                                     weapon, target)
                at = main_at if role == "main" else trim_at
                if at is None:
                    continue
                out, taken = apply(rules, pic)
                mine = np.isin(taken, at)
                yield f"{role} {what} {item['id']}", pic[mine], out[mine]


def check(verbose=False):
    tables = materials()
    missing = [n for n in TRIMS if (SPRITES / f"{n}_trim.png").exists() != (n in tables[1])]
    if missing:
        print("Dyes.swift's materials and the trim layers disagree:", missing)
    listed = set(re.findall(r'"(\w+)"', SWIFT.read_text().split("static let oneColour: Set<String> = [")[1].split("]")[0]))
    if listed != set(one_colour()):
        missing.append("oneColour")
        print("Dyes.swift's oneColour isn't the weapons with no trim: rerun cut and paste it in:", sorted(listed ^ set(one_colour())))
    rows, failures = [], []
    for dye_id, dye in dyes():
        groups = {}
        for label, before, after in list(sheet_cases(tables, dye)) + list(painted_cases(dye)) + list(item_cases(dye)):
            v = verdict(dye, before, after, held=" held " in f" {label} ")
            if v is None:
                continue
            words = label.split()
            if words[0] not in ("main", "trim"):
                group = label
            elif words[1] in ("icon", "held"):
                group = f"{words[0]} {words[1]}s"
            else:
                group = words[0] + " " + re.sub(r"^(armor|hat)_(.*)_(human|elf|dwarf)$", lambda m: m[2] + (" hat" if m[1] == "hat" else ""), words[-1])
            groups.setdefault(group, []).append((label, v))
            if not v["ok"]:
                failures.append((dye_id, label, v))
        rows.append((dye_id, {g: (sum(v["ok"] for _, v in vs), len(vs)) for g, vs in groups.items()}))
    columns = list(dict.fromkeys(g for _, gs in rows for g in gs))
    print("dye".ljust(15) + "".join(c.replace("main ", "").replace("trim ", "t:")[:14].ljust(15) for c in columns))
    for dye_id, gs in rows:
        print(dye_id.ljust(15) + "".join((f"{gs[c][0]}/{gs[c][1]}" + (" ok" if gs[c][0] == gs[c][1] else " FAIL")).ljust(15)
                                         if c in gs else "-".ljust(15) for c in columns))
    print(f"\n{len(failures)} failing case(s)")
    failures += [("tables", m, None) for m in missing]
    for dye_id, label, v in [f for f in failures if f[2] is not None][: (None if verbose else 40)]:
        print(f"  {dye_id:15s} {label:45s} {v['fails']}: hue {v['hue']:.0f} sat {v['sat']:.2f} val {v['val']:.2f} "
              f"spread {v['spread'][0]:.2f}/{v['spread'][1]:.2f}")
    return not failures


# MARK: an axe's handle

# How much wider than its haft (across the weapon's long axis) a step has to be to be its head.
HAFT_WIDE = 1.7


def axes():
    """The axes: every weapon whose id ends in _axe, with its icon and held sprites' art."""
    items = json.loads((ROOT / "content" / "items.json").read_text())["items"]
    return [(i["id"], [i["art"], f"held_{i['id']}_side", f"held_{i['id']}_front"])
            for i in items if i["type"] == "weapon" and i["id"].endswith("_axe") and i.get("art")]


def haft_mask(a):
    """An axe picture's handle (playtesting 2026-10-31: "Make sure that the handles of all axes items won't
    be changed with the dye"): everything from the grip up to where it widens into the head. The
    picture's long axis runs from the grip (the solid pixel nearest the bottom-left corner, as
    GearArt.held holds it) to the tip; across it, the haft is about as wide as halfway up it, the head
    HAFT_WIDE times that. The head runs down from its widest step in the upper half while it's wide (a
    gap of two narrow steps allowed); the haft is what's below it, the pommel too."""
    H, W = a.shape[:2]
    ys, xs = np.nonzero(a[..., 3] >= 128)
    pts = np.stack([xs, ys], 1).astype(float)
    grip = pts[np.argmin(xs ** 2 + (H - 1 - ys) ** 2)]
    centred = pts - pts.mean(0)
    _, vectors = np.linalg.eigh(centred.T @ centred)
    along = vectors[:, -1]
    if ((pts - grip) @ along).mean() < 0:
        along = -along
    p = (pts - grip) @ along
    q = (pts - grip) @ np.array([-along[1], along[0]])
    steps = int(np.ceil(p.max())) + 1
    at = np.clip(np.round(p).astype(int), 0, steps - 1)
    width = np.zeros(steps)
    for b in range(steps):
        m = at == b
        if m.any():
            width[b] = q[m].max() - q[m].min() + 1
    middle = width[int(0.15 * steps):int(0.5 * steps)]
    haft = np.median(middle[middle > 0]) if (middle > 0).any() else 1
    top = int(np.argmax(np.where(np.arange(steps) >= steps // 2, width, -1)))
    start, gap = top, 0
    for b in range(top, -1, -1):
        if width[b] > HAFT_WIDE * haft + 0.5:
            start, gap = b, 0
        else:
            gap += 1
            if gap > 2:
                break
    mask = np.zeros((H, W), bool)
    below = at < start - 1
    mask[ys[below], xs[below]] = True
    # Where the haft runs on up into the head (a Battle Axe's, under its blade), it's still the haft: the
    # pixels along its line, joined to it, in colours of its own that the head doesn't have off its line
    # (an outline or a shade the two share would carry it on up through the head).
    if below.any():
        line = np.median(q[below])
        near = ~below & (np.abs(q - line) <= haft / 2 + 0.5)
        head = {tuple(c) for c in a[ys[~below & ~near], xs[~below & ~near], :3]}
        colours = {tuple(c) for c in a[mask][:, :3]} - head
        band = np.zeros((H, W), bool)
        band[ys[near], xs[near]] = [tuple(a[y, x, :3]) in colours for y, x in zip(ys[near], xs[near])]
        while True:
            grown = band & ~mask & (np.pad(mask, 1)[:-2, 1:-1] | np.pad(mask, 1)[2:, 1:-1]
                                    | np.pad(mask, 1)[1:-1, :-2] | np.pad(mask, 1)[1:-1, 2:])
            if not grown.any():
                break
            mask |= grown
    return mask


def hafts():
    """Writes each axe picture's handle as a layer of its own (art/sprites/<art>_haft.png), which the game
    lays over the picture dyed (ArtLibrary.dyedAsset), recoloured by its trim dye alone: a dye takes the
    head, never the handle (RD drew some handles' shading in the head's steel)."""
    for _, arts in axes():
        for art in arts:
            a = load(art)
            layer = np.zeros_like(a)
            mask = haft_mask(a)
            layer[mask] = a[mask]
            Image.fromarray(layer).save(SPRITES / f"{art}_haft.png")
            print(f"{art}_haft.png: {int(mask.sum())} of {int((a[..., 3] >= 128).sum())} pixels")


# MARK: the contact sheet

def contact(out_path):
    mains, trims = materials()
    all_dyes = dyes()
    z = 4
    rows = []
    # Each kind of sheet on each race, its first frame facing you, plain then each dye (main), then each dye as
    # the trim on a main of the next dye along.
    for kind in KINDS:
        for race in RACES:
            sheet = f"armor_{kind}_{race}"
            rows.append((sheet, [(None, None)] + [(d, None) for d in all_dyes] +
                         ([(all_dyes[(i + 4) % len(all_dyes)], d) for i, d in enumerate(all_dyes)] if sheet in trims else [])))
    for kind in HAT_KINDS:
        for race in RACES:
            hat = f"hat_{kind}_{race}"
            rows.append((hat, [(None, None)] + [(d, None) for d in all_dyes] +
                         ([(all_dyes[(i + 4) % len(all_dyes)], d) for i, d in enumerate(all_dyes)] if hat in trims else [])))
    width = 1 + 2 * len(all_dyes)
    cell = 48 * z + 4
    icons = ["item_iron_plate", "item_mage_robe", "item_dragon_mail", "item_leather_gloves"]
    items = json.loads((ROOT / "content" / "items.json").read_text())["items"]
    weapons = [i for i in items if i["type"] == "weapon" and i.get("art") and (SPRITES / f"held_{i['id']}_side.png").exists()]
    weapons = [weapons[k] for k in np.linspace(0, len(weapons) - 1, 6).astype(int)]
    canvas = Image.new("RGBA", (width * cell, (len(rows) + 2 + len(weapons) * 2 + len(icons)) * cell), (58, 62, 70, 255))
    for r, (name, cells) in enumerate(rows):
        a = load(name)
        frame = a[96:144, 0:48]
        for c, (main, trim) in enumerate(cells):
            img = frame
            if main is not None:
                kind = re.sub(r"^(armor|hat)_|_(human|elf|dwarf)$", "", name)
                img, _ = apply(rules_onto(main[1], mains.get(name, mains[kind])), frame)
                if trim is not None and name in trims:
                    layer = load(name + "_trim")[96:144, 0:48]
                    t, _ = apply(rules_onto(trim[1], trims[name]), layer)
                    base = Image.fromarray(img)
                    base.alpha_composite(Image.fromarray(t))
                    img = np.asarray(base)
            shown = Image.fromarray(np.ascontiguousarray(img))
            if name.startswith("armor_"):   # the hero's own head over it, as the game draws it (bald)
                shown.alpha_composite(Image.fromarray(np.ascontiguousarray(load(f"head_{name.rsplit('_', 1)[1]}")[96:144, 0:48])))
            canvas.alpha_composite(shown.resize((48 * z, 48 * z), Image.NEAREST), (c * cell, r * cell))
    r = len(rows) + 1
    for item in icons + [w["art"] for w in weapons]:
        if not (SPRITES / f"{item}.png").exists():
            continue
        icon = load(item)
        weapon = any(w["art"] == item for w in weapons)
        held = next((load(f"held_{w['id']}_side") for w in weapons if w["art"] == item), None)
        for line, picture in ((0, icon), (1, held)):
            if picture is None:
                continue
            for c in range(width):
                if c == 0:
                    img = picture
                elif c <= len(all_dyes):
                    rules, _, _ = icon_rules(icon, all_dyes[c - 1][1], None, weapon, picture if line else None)
                    img, _ = apply(rules, picture)
                else:
                    i = c - 1 - len(all_dyes)
                    rules, _, _ = icon_rules(icon, all_dyes[(i + 4) % len(all_dyes)][1], all_dyes[i][1], weapon,
                                             picture if line else None)
                    img, _ = apply(rules, picture)
                pil = Image.fromarray(img)
                scale = (48 * z) / max(pil.size)
                pil = pil.resize((max(1, int(pil.width * scale)), max(1, int(pil.height * scale))), Image.NEAREST)
                canvas.alpha_composite(pil, (c * cell, r * cell))
            r += 1
    canvas.save(out_path)
    print(f"{out_path}: {canvas.size[0]}x{canvas.size[1]}, columns: plain, each dye as the main colour "
          f"({', '.join(d for d, _ in all_dyes)}), then each as the trim over the dye four along")


if __name__ == "__main__":
    if sys.argv[1:2] == ["cut"]:
        cut()
    elif sys.argv[1:2] == ["hafts"]:
        hafts()
    elif sys.argv[1:2] == ["check"]:
        sys.exit(0 if check("-v" in sys.argv) else 1)
    elif sys.argv[1:2] == ["--sheet"] and len(sys.argv) > 2:
        contact(sys.argv[2])
    else:
        print(__doc__)
