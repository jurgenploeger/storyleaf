#!/usr/bin/env python3
"""The UI's own icons, drawn in code in the skills' style (tools/skill_art.py): solid shapes made of
light, deep at their rim and bright toward their top left, with a glow round them, sparks and flares, a
soft shadow under them so they stand off whatever button they're on. Not pixel art (playtesting
2026-10-24: "can we use the same style from the skill visuals for icons in the UI?"): drawn smooth at
512 pixels and shrunk to 128 (art/sprites/ui_<icon>.png), on no backdrop of their own, as the buttons
they sit on are tiles already.

Each is named after the `GameIcon` it stands in for (Storyleaf/UI/GameIcon.swift): `IconImage` shows it
at button sizes (the battle buttons, the HUD's buttons, the menu's tabs), smoothed, and keeps the vector
icon for small inline glyphs. Edit a drawing and rerun:

    python3 tools/ui_icon_art.py               # all of them
    python3 tools/ui_icon_art.py sword paw     # just these
    python3 tools/ui_icon_art.py --sheet out.png   # also a contact sheet on the game's button colours
"""

import math
import pathlib
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from skill_art import LIGHTS, N, OUT, SPRITES, Icon, heart_shape, paw, rgb, shield  # noqa: E402


class UIIcon(Icon):
    """The skills' `Icon`, its solid shapes without their coloured glow and on a smaller, softer
    shadow: on a light button (the title screen's cream ones) the glow read as a smudge round them.
    The sparks and flares keep theirs."""

    def body(self, mask, light, cx, cy, r, rim=True, shadow=True):
        deep, main, bright, core = light
        if shadow:
            self.over(np.zeros(3), self._soft(mask, 0.012) * 0.32)
        field = self.radial(cx, cy, r, core, deep, power=0.8)
        inner = np.hypot(self.x - cx, self.y - cy) < r * 0.55
        field = np.where(inner[..., None], self.radial(cx, cy, r * 0.55, core, bright, power=1.2), field)
        self.over(field, mask)
        if rim:
            self.add(bright, np.clip(mask - Icon._erode(mask), 0, 1) * 0.5)


def light(*hexes):
    """A light's four colours, deep to core (as skill_art's LIGHTS)."""
    return [rgb(h) for h in hexes]


GOLD = LIGHTS["light"]
STEEL = light("#5a6a86", "#a8b8d0", "#e4ecf8", "#ffffff")
LEATHER = light("#6d3a18", "#a8622e", "#e09a58", "#ffd8a8")
RED = light("#9e1b2a", "#e03a46", "#ff8a90", "#ffe4e6")
BLUE = light("#1a4aa0", "#3d84e8", "#9ccaff", "#eef8ff")
GREEN = light("#1e6a2a", "#3cb850", "#9be38f", "#efffe8")
PINK = light("#b0406a", "#f07aa6", "#ffc4da", "#fff2f7")
PARCH = light("#9a7444", "#e0c48c", "#fff0cc", "#fffdf4")
CREAM = light("#a8987a", "#eee2c8", "#fffaf0", "#ffffff")
TEAL = light("#0e6a7a", "#2cb8c8", "#9cf0f4", "#f0ffff")
CYAN = LIGHTS["water"]
SKIN = light("#b06a44", "#e8a878", "#ffd8b8", "#fff4ea")


def star_points(cx, cy, outer, inner, points=5, turn=-math.pi / 2):
    return [(cx + math.cos(turn + k * math.pi / points) * (outer if k % 2 == 0 else inner),
             cy + math.sin(turn + k * math.pi / points) * (outer if k % 2 == 0 else inner)) for k in range(points * 2)]


def rect(ic, x0, y0, x1, y1, radius=0.03):
    img = Image.new("L", (N, N), 0)
    ImageDraw.Draw(img).rounded_rectangle([x0 * N, y0 * N, x1 * N, y1 * N], radius=int(radius * N), fill=255)
    return np.asarray(img, float) / 255


# ---------------------------------------------------------------- the icons

def draw_sword(ic):
    # Attack: a steel blade up to the top right, its edge catching the light, a gold guard and a red gem.
    ic.glow(0.56, 0.44, 0.36, STEEL[1], 0.35)
    blade = [(0.86, 0.1), (0.9, 0.14), (0.42, 0.66), (0.34, 0.58)]
    ic.body(ic.poly(blade, blur=0.002), STEEL, 0.7, 0.26, 0.5)
    ic.add(STEEL[3], ic.line([(0.86, 0.12), (0.4, 0.6)], 0.012, blur=0.002) * 0.9)
    ic.body(ic.line([(0.22, 0.5), (0.5, 0.78)], 0.07, blur=0.002), GOLD, 0.32, 0.6, 0.2)
    ic.body(ic.line([(0.34, 0.66), (0.16, 0.84)], 0.06, blur=0.002), LEATHER, 0.24, 0.74, 0.14)
    ic.body(ic.ellipse(0.13, 0.87, 0.055), RED, 0.12, 0.86, 0.06)
    ic.body(ic.ellipse(0.36, 0.64, 0.045), RED, 0.35, 0.63, 0.05, shadow=False)
    ic.flare(0.84, 0.14, 0.16, GOLD, strength=0.8)


def sparkle_points(cx, cy, r, bulk=0.62, n=120):
    """A four-pointed sparkle with curved sides, full in the middle (the ✨ shape): a superellipse
    |x|^p + |y|^p = r^p, its sides bowing in more the smaller `bulk` (p) is."""
    out = []
    for k in range(n):
        t = 2 * math.pi * k / n
        c, s_ = math.cos(t), math.sin(t)
        out.append((cx + r * math.copysign(abs(c) ** (2 / bulk), c), cy + r * math.copysign(abs(s_) ** (2 / bulk), s_)))
    return out


# The sparkles' gold, a shade deeper at its rim than the skills' light, so it holds its shape on a
# cream button.
AMBER = light("#c26a06", "#f2a30d", "#ffd640", "#fff8d0")


def draw_sparkles(ic):
    # Skills: three sparkles of light, gold, sky and rose, full-bodied with curved sides (playtesting
    # 2026-10-24: thin four-pointed stars had no body and washed out on the buttons).
    ic.flare(0.4, 0.56, 0.4, GOLD, strength=0.9)
    ic.body(ic.poly(sparkle_points(0.4, 0.56, 0.34), blur=0.003), AMBER, 0.36, 0.5, 0.3)
    ic.flare(0.76, 0.22, 0.2, CYAN, strength=0.8)
    ic.body(ic.poly(sparkle_points(0.76, 0.22, 0.17), blur=0.002), BLUE, 0.74, 0.2, 0.15)
    ic.flare(0.78, 0.78, 0.16, LIGHTS["dark"], strength=0.6)
    ic.body(ic.poly(sparkle_points(0.78, 0.78, 0.13), blur=0.002), PINK, 0.76, 0.76, 0.12)


def draw_backpack(ic):
    # The bag: a leather pack, its flap down over it, a pocket and a gold buckle.
    ic.body(ic.arc(0.5, 0.26, 0.12, 180, 360, 0.04), LEATHER, 0.46, 0.18, 0.14)
    ic.body(rect(ic, 0.2, 0.26, 0.8, 0.9, 0.1), LEATHER, 0.3, 0.32, 0.5)
    ic.body(rect(ic, 0.2, 0.26, 0.8, 0.52, 0.1), LEATHER, 0.3, 0.28, 0.36)
    ic.body(rect(ic, 0.32, 0.62, 0.68, 0.84, 0.05), LEATHER, 0.38, 0.64, 0.26)
    ic.body(rect(ic, 0.43, 0.46, 0.57, 0.6, 0.02), GOLD, 0.47, 0.49, 0.12)
    ic.sparkle(0.48, 0.5, 0.05, GOLD, 0.7)


def draw_shield(ic):
    # Defend: a blue shield, its rim lit, a gold star on it.
    ic.glow(0.5, 0.5, 0.42, BLUE[1], 0.35)
    shield(ic, BLUE, 0.5, 0.52, 1.2)
    ic.body(ic.poly(star_points(0.5, 0.48, 0.16, 0.065), blur=0.002), GOLD, 0.48, 0.44, 0.16, shadow=False)
    ic.flare(0.32, 0.24, 0.14, GOLD, strength=0.6)


def draw_wind(ic):
    # Run: a winged boot, streaks of wind behind it.
    for k, y in enumerate((0.5, 0.64, 0.78)):
        ic.trail([(0.04 + 0.04 * k, y), (0.2, y), (0.34, y)], 0.05, CYAN, 0.9)
    boot = [(0.46, 0.18), (0.66, 0.18), (0.66, 0.6), (0.92, 0.68), (0.94, 0.86), (0.4, 0.86), (0.42, 0.6)]
    ic.body(ic.poly(boot, blur=0.002), LEATHER, 0.5, 0.3, 0.45)
    ic.body(rect(ic, 0.43, 0.16, 0.69, 0.26, 0.03), LEATHER, 0.5, 0.18, 0.2)
    wing = [(0.44, 0.34), (0.2, 0.12), (0.26, 0.24), (0.14, 0.24), (0.24, 0.34), (0.16, 0.38), (0.4, 0.46)]
    ic.body(ic.poly(wing, blur=0.002), CREAM, 0.3, 0.26, 0.26)


def draw_heart(ic):
    # Health: a red heart, glossy, with a spark of light on it.
    ic.glow(0.5, 0.52, 0.42, RED[1], 0.4)
    ic.body(heart_shape(ic, 0.5, 0.54, 0.38), RED, 0.4, 0.4, 0.4)
    ic.over(RED[3], ic.ellipse(0.34, 0.38, 0.06, 0.04, blur=0.008) * 0.85)
    ic.sparkle(0.78, 0.22, 0.05, GOLD, 0.8)


def draw_seal_stone(ic):
    # Capture: a teal seal stone, a swirl of light inside it.
    hexagon = [(0.5 + math.cos(a) * 0.34, 0.52 + math.sin(a) * 0.38) for a in np.linspace(-math.pi / 2, 1.5 * math.pi, 7)[:-1]]
    ic.glow(0.5, 0.52, 0.42, TEAL[1], 0.45)
    ic.body(ic.poly(hexagon, blur=0.002), TEAL, 0.42, 0.38, 0.4)
    for k, r in enumerate((0.16, 0.1, 0.05)):
        ic.add(TEAL[3], ic.arc(0.5, 0.54, r, 200 + k * 60, 470 + k * 60, 0.025, blur=0.003) * 0.8)
    ic.sparkle(0.78, 0.2, 0.05, CYAN, 0.8)


def draw_more(ic):
    # More: three gold beads of light in a row.
    for x in (0.2, 0.5, 0.8):
        ic.body(ic.ellipse(x, 0.52, 0.11), GOLD, x - 0.03, 0.49, 0.12)


def person(ic, cx, cy, s, shirt):
    """A head and shoulders: a round face and a shirt."""
    ic.body(ic.ellipse(cx, cy + 0.3 * s, 0.26 * s, 0.2 * s) * (ic.y < cy + 0.42 * s), shirt, cx - 0.06 * s, cy + 0.16 * s, 0.3 * s)
    ic.body(ic.ellipse(cx, cy - 0.06 * s, 0.15 * s), SKIN, cx - 0.04 * s, cy - 0.1 * s, 0.16 * s)


def draw_user(ic):
    # Character: one hero, head and shoulders.
    ic.glow(0.5, 0.5, 0.4, BLUE[1], 0.3)
    person(ic, 0.5, 0.44, 1.25, BLUE)


def draw_users(ic):
    # Friends: two heroes side by side, one a little behind.
    person(ic, 0.34, 0.4, 0.95, GREEN)
    person(ic, 0.64, 0.5, 1.05, BLUE)


def draw_paw(ic):
    # Companions: a pink paw.
    ic.glow(0.5, 0.52, 0.42, PINK[1], 0.4)
    paw(ic, PINK, 0.5, 0.5, 1.5)


def draw_book(ic):
    # The Monster Book: a green book, a gold gem on its cover, a bookmark below.
    ic.body(ic.poly([(0.66, 0.86), (0.74, 0.86), (0.74, 0.98), (0.7, 0.94), (0.66, 0.98)]), RED, 0.69, 0.88, 0.06)
    ic.body(rect(ic, 0.24, 0.1, 0.82, 0.88, 0.04), CREAM, 0.4, 0.2, 0.5)
    ic.body(rect(ic, 0.18, 0.08, 0.76, 0.86, 0.05), GREEN, 0.28, 0.16, 0.46)
    ic.over(GREEN[0], rect(ic, 0.18, 0.08, 0.26, 0.86, 0.03) * 0.6)
    ic.body(ic.poly([(0.47, 0.26), (0.6, 0.47), (0.47, 0.68), (0.34, 0.47)], blur=0.002), GOLD, 0.44, 0.38, 0.22, shadow=False)
    ic.flare(0.46, 0.4, 0.14, GOLD, strength=0.6)


def draw_talk(ic):
    # Chat: a speech bubble, three dots in it.
    bubble = ic.ellipse(0.5, 0.44, 0.4, 0.3) + ic.poly([(0.26, 0.62), (0.18, 0.88), (0.44, 0.7)], blur=0.002)
    ic.body(np.clip(bubble, 0, 1), CREAM, 0.36, 0.28, 0.42)
    for x in (0.32, 0.5, 0.68):
        ic.body(ic.ellipse(x, 0.45, 0.055), BLUE, x - 0.015, 0.435, 0.06, shadow=False)


def draw_settings(ic):
    # Settings: a steel gear, a blue gem at its hub.
    teeth = []
    for k in range(16):
        a = k * math.pi / 8
        r = 0.42 if k % 2 == 0 else 0.33
        for da in (-0.13, 0.13):
            teeth.append((0.5 + math.cos(a + da) * r, 0.5 + math.sin(a + da) * r))
    gear = np.clip(ic.poly(teeth, blur=0.002) - ic.ellipse(0.5, 0.5, 0.12), 0, 1)
    ic.body(gear, STEEL, 0.38, 0.36, 0.44)
    ic.body(ic.ellipse(0.5, 0.5, 0.1), BLUE, 0.47, 0.47, 0.11, shadow=False)


def draw_map(ic):
    # The world map: a folded parchment, a green land on it and a red X.
    folds = [[(0.1, 0.2), (0.38, 0.12), (0.38, 0.82), (0.1, 0.9)], [(0.38, 0.12), (0.64, 0.2), (0.64, 0.9), (0.38, 0.82)],
             [(0.64, 0.2), (0.9, 0.12), (0.9, 0.82), (0.64, 0.9)]]
    for k, fold in enumerate(folds):
        ic.body(ic.poly(fold, blur=0.002), PARCH, 0.22 + k * 0.26, 0.26, 0.4)
    ic.body(ic.ellipse(0.28, 0.42, 0.1, 0.08) + ic.ellipse(0.48, 0.58, 0.08, 0.06), GREEN, 0.3, 0.42, 0.16, shadow=False)
    for a, b in (((0.68, 0.56), (0.82, 0.7)), ((0.82, 0.56), (0.68, 0.7))):
        ic.body(ic.line([a, b], 0.04), RED, 0.74, 0.6, 0.1, shadow=False)


def draw_gift(ic):
    # Rewards: a red gift box, a gold ribbon and bow, a sparkle.
    ic.body(rect(ic, 0.18, 0.44, 0.82, 0.9, 0.04), RED, 0.3, 0.48, 0.42)
    ic.body(rect(ic, 0.12, 0.32, 0.88, 0.48, 0.04), RED, 0.28, 0.34, 0.4)
    ic.body(rect(ic, 0.44, 0.32, 0.56, 0.9, 0.02), GOLD, 0.48, 0.38, 0.3, shadow=False)
    for side in (-1, 1):
        ic.body(ic.ellipse(0.5 + side * 0.12, 0.24, 0.1, 0.07), GOLD, 0.5 + side * 0.1, 0.22, 0.1)
    ic.flare(0.78, 0.18, 0.14, GOLD, strength=0.8)


def coin(ic, cx, cy, r):
    ic.body(ic.ellipse(cx, cy, r), GOLD, cx - r * 0.3, cy - r * 0.3, r)
    ic.over(GOLD[0], ic.ring(cx, cy, r * 0.7, r * 0.12, blur=0.003) * 0.6)


def draw_coins(ic):
    # Gold: a stack of three coins.
    coin(ic, 0.34, 0.64, 0.2)
    coin(ic, 0.66, 0.66, 0.2)
    coin(ic, 0.5, 0.38, 0.2)
    ic.sparkle(0.82, 0.22, 0.05, GOLD, 0.9)


def draw_star(ic):
    # Favourites and titles: a gold star.
    ic.glow(0.5, 0.52, 0.44, GOLD[1], 0.45)
    ic.body(ic.poly(star_points(0.5, 0.54, 0.42, 0.18), blur=0.002), GOLD, 0.42, 0.42, 0.42)
    ic.flare(0.36, 0.34, 0.14, GOLD, strength=0.6)


def draw_egg(ic):
    # Eggs to hatch: a cream egg with green spots.
    egg = [(0.5 + 0.28 * math.sin(t), 0.56 - (0.38 if math.cos(t) > 0 else 0.3) * math.cos(t)) for t in np.linspace(0, 2 * math.pi, 48)]
    ic.glow(0.5, 0.56, 0.42, GREEN[1], 0.25)
    ic.body(ic.poly(egg, blur=0.002), CREAM, 0.42, 0.4, 0.4)
    for (x, y, r) in ((0.42, 0.42, 0.05), (0.6, 0.56, 0.06), (0.44, 0.7, 0.045), (0.62, 0.3, 0.035)):
        ic.body(ic.ellipse(x, y, r), GREEN, x - 0.01, y - 0.01, r, shadow=False)


def draw_arrow_down(ic):
    # Save to the phone: a green arrow down into a blue tray.
    ic.body(rect(ic, 0.12, 0.66, 0.88, 0.9, 0.05), BLUE, 0.28, 0.7, 0.42)
    arrow = [(0.4, 0.08), (0.6, 0.08), (0.6, 0.4), (0.76, 0.4), (0.5, 0.7), (0.24, 0.4), (0.4, 0.4)]
    ic.body(ic.poly(arrow, blur=0.002), GREEN, 0.46, 0.2, 0.5)


# GameIcon names use hyphens (arrow-down) where Python names can't: draw_arrow_down draws "arrow-down".
DRAWINGS = {name[len("draw_"):].replace("_", "-"): fn for name, fn in list(globals().items()) if name.startswith("draw_") and callable(fn)}


# How far a glow or a shadow may reach past what's solid in an icon, in parts of its width: a thin soft
# rim. (Left to spread, the skills' glows and shadows filled the icon's square, and on the title
# screen's cream buttons it showed as a smudge cut off square: playtesting 2026-10-24.)
HALO = 0.035


def render(name):
    """The icon at 128 pixels, on nothing: its glows and shadow a thin soft rim round its shapes, so
    it sits on any button, light or dark, with nothing cut off at its edges."""
    ic = UIIcon(None)
    DRAWINGS[name](ic)
    # What's solid (the shapes, the sparks' cores), and a soft band round it the glows may fill.
    solid = Image.fromarray((ic.a > 0.6).astype(np.uint8) * 255)
    reach = int(HALO * N)
    room = solid.filter(ImageFilter.MaxFilter(2 * (reach // 2) + 1)).filter(ImageFilter.GaussianBlur(reach / 2))
    a = np.minimum(ic.a, np.asarray(room, float) / 255)
    # And faded out over the last few pixels to the edge, where a shape runs close to it.
    edge = np.maximum(np.abs(ic.x - 0.5), np.abs(ic.y - 0.5))
    a = a * np.clip((0.5 - edge) / 0.025, 0, 1)
    rgba = np.dstack([np.clip(ic.rgb, 0, 1) * a[..., None], a])            # premultiplied
    img = Image.fromarray((rgba * 255).round().astype(np.uint8), "RGBa")
    return img.resize((OUT, OUT), Image.LANCZOS).convert("RGBA")


def main(argv):
    sheet_path = None
    if "--sheet" in argv:
        index = argv.index("--sheet")
        sheet_path = argv[index + 1]
        argv = argv[:index] + argv[index + 2:]
    names = argv or sorted(DRAWINGS)
    out = {}
    for name in names:
        out[name] = render(name)
        out[name].save(SPRITES / f"ui_{name}.png")
    print(f"wrote {len(names)} UI icons to art/sprites/")
    if sheet_path:
        # Each icon on the HUD's blue button, the battle's red one and a cream panel, at 96 and 36 pixels.
        backs = [(64, 140, 230, 255), (220, 70, 70, 255), (240, 232, 214, 255)]
        cell, small, pad = 96, 36, 8
        width = len(names) * (cell + pad) + pad
        sheet = Image.new("RGBA", (width, len(backs) * (cell + small + 2 * pad) + pad), (30, 34, 52, 255))
        for row, back in enumerate(backs):
            for n, name in enumerate(names):
                x, y = pad + n * (cell + pad), pad + row * (cell + small + 2 * pad)
                tile = Image.new("RGBA", (cell, cell), back)
                tile.alpha_composite(out[name].resize((cell - 12, cell - 12), Image.LANCZOS), (6, 6))
                sheet.alpha_composite(tile, (x, y))
                little = Image.new("RGBA", (small, small), back)
                little.alpha_composite(out[name].resize((small - 4, small - 4), Image.LANCZOS), (2, 2))
                sheet.alpha_composite(little, (x, y + cell + pad))
        sheet.save(sheet_path)
        print(f"contact sheet: {sheet_path}")


if __name__ == "__main__":
    main(sys.argv[1:])
