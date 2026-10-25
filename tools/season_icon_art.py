#!/usr/bin/env python3
"""The seasonal app icons, Halloween, Christmas and Easter, that the game switches to while each festive
season runs (`SeasonalIcon` in Storyleaf/App, the seasons' dates in content/rewards.json `seasons`). The
same picked drawing as the app icon (tools/app_icon_art.py `SOURCE`), cropped a little looser so a hat
fits on the hero's head (`BOX`, 128 pixels at 8×), with only the scenery changed and something festive
on him:

  Halloween  a purple night, a moon, autumn leaves, bats, a jack-o'-lantern, a witch's hat
  Christmas  a pale winter sky, snow on the trees and the ground, snowflakes, a Santa hat
  Easter     a bright spring sky, fresh leaves and blossom, flowers and painted eggs, bunny ears

Held to docs/pixel-style.md and docs/sprite-acceptance.md:

- **The drawing's own clusters stay.** The scenery is Retro Diffusion's, so it's recoloured, never redrawn:
  each class of colour (sky, leaves, blossom, branches, grass) is a small ramp in the drawing (one to nine
  colours), and each of its colours is swapped for the one of the same rank on the season's ramp, which
  turns its shadows away from yellow and its lights toward it. The light and texture are RD's.
- **Tinted outlines on the scenery:** its dark pixels take a deep shade of what they round, never black.
- **Snow lies where the light does,** on the lit tops of the leaves' clusters, in RD's snow colours
  (scenery_art.SNOW); never a strip along an edge or single pixels as noise.
- **The hats and props are drawn with pixel_kit:** lit from the top left, a few hue-shifted shades with
  texture, a contact shadow, and the dark outline characters and their gear have.
- **A hat sits as a head piece does:** its band on the head's widest row above the eyes (y 72 here, the
  scalp's top at 53 and the eyes at 96), a little wider than the scalp, the hair above it hidden.
- **Nothing in the corners** iOS rounds off (about 29 of the drawing's pixels), so every prop shows.

The hero is left as drawn (`HERO`, his outline in the drawing's pixels). Written as
AppIcon-<Season>.appiconset, one 1024 image each (iOS shows it in every appearance).

    python3 tools/season_icon_art.py                    # writes the three icon sets
    python3 tools/season_icon_art.py --preview out.png  # all three at Home Screen sizes, beside the icon

Needs pillow + numpy.
"""

import argparse
import colorsys
import json
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

import app_icon_art
from pixel_kit import Material, Sprite
from scenery_art import SNOW

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Storyleaf/Resources/Assets.xcassets"

BOX = (44, 40, 172, 168)
SCALE = 8
# The hero and his sword, in the drawing's pixels: nothing inside is recoloured.
HERO = [(55, 44), (64, 43), (72, 60), (79, 78), (85, 98), (89, 110), (93, 108), (96, 100), (94, 90), (87, 84),
        (84, 76), (90, 66), (98, 56), (108, 51), (122, 51), (136, 53), (146, 59), (151, 70), (153, 84), (151, 98),
        (149, 106), (151, 112), (152, 124), (150, 132), (155, 140), (153, 150), (146, 156), (145, 168), (97, 168),
        (97, 157), (93, 155), (87, 153), (84, 144), (78, 141), (77, 131), (66, 131), (63, 124), (71, 118),
        (79, 117), (71, 96), (62, 72), (55, 50)]
# Below this row the green is the meadow, above it the trees' leaves.
GROUND = 147
SKY, LEAVES, BLOSSOM, BRANCHES, GRASS, DARK = 1, 2, 3, 4, 5, 6


def hexrgb(code: str) -> np.ndarray:
    code = code.lstrip("#")
    return np.array([int(code[i:i + 2], 16) for i in (0, 2, 4)], dtype=float) / 255


def ramp(dark: str, light: str, n: int) -> list:
    """`n` shades from `dark` to `light`, the hue turning the short way between them (so a ramp whose
    shadow sits away from yellow and its light toward it keeps doing so), in hard steps."""
    h0, s0, v0 = colorsys.rgb_to_hsv(*hexrgb(dark))
    h1, s1, v1 = colorsys.rgb_to_hsv(*hexrgb(light))
    dh = (h1 - h0 + 0.5) % 1 - 0.5
    out = []
    for i in range(n):
        t = i / max(1, n - 1)
        out.append(np.array(colorsys.hsv_to_rgb((h0 + dh * t) % 1, s0 + (s1 - s0) * t, v0 + (v1 - v0) * t)))
    return out


# Each season: for every class, the dark and light ends of its ramp (shadows turned away from yellow,
# lights toward it), and the sky in three bands down the icon.
SEASONS = {
    "Halloween": {
        "sky": [("#26163f", "#3a2257"), ("#4a2462", "#62307a"), ("#8a3a5e", "#b4544e")],
        LEAVES: ("#4a1430", "#ffb84a"), BLOSSOM: ("#1a0e2e", "#a45cae"),
        BRANCHES: ("#2e1a26", "#4a2c30"), GRASS: ("#24221a", "#b8923a"),
    },
    "Christmas": {
        "sky": [("#86a8d4", "#9cbade"), ("#a8c4e4", "#bcd2ec"), ("#c8dcf0", "#dce9f6")],
        LEAVES: ("#0c2a2e", "#3e8a5c"), BLOSSOM: (SNOW[0], SNOW[4]),
        BRANCHES: ("#2a2232", "#4a3c48"), GRASS: (SNOW[1], SNOW[4]),
    },
    "Easter": {
        "sky": [("#62b4f0", "#78c4f6"), ("#8cd0f8", "#a4dcfa"), ("#bce8fc", "#d6f2ff")],
        LEAVES: ("#1e5a3a", "#d4f07a"), BLOSSOM: ("#7a2a62", "#ffe2ee"),
        BRANCHES: ("#4a2a2a", "#8a5a3e"), GRASS: ("#1e6a3a", "#dcf28a"),
    },
}


def hero_mask() -> np.ndarray:
    """The hero exactly, outline and all. `HERO` only roughs him out: the background is flooded in from
    outside it through everything but dark pixels, as far as a band 5 pixels inside it, so it stops at his
    own outline (and where that has a gap, leaks a few pixels at most); his gold (the sword's lit edge,
    which has no dark line) is never background, and sky never his. Then his outline is the dark pixels
    within 2 of what's left. Cut from the polygon alone, his outline came out half his and half the
    scenery's, recoloured, and looked chewed."""
    w, h = BOX[2] - BOX[0], BOX[3] - BOX[1]
    image = Image.new("L", (w, h))
    ImageDraw.Draw(image).polygon([(x - BOX[0], y - BOX[1]) for x, y in HERO], fill=255)
    rough = np.asarray(image) > 0
    rgb = app_icon_art.crop(BOX)
    dark = rgb.max(axis=2) <= 0.2
    four = ndimage.generate_binary_structure(2, 1)
    outer = ndimage.binary_dilation(rough, four, iterations=5)
    inner = ndimage.binary_erosion(rough, four, iterations=5)
    gold = app_icon_art.is_gold(rgb) & outer
    sky = app_icon_art.sky_mask(rgb)
    seeds = (~outer & ~dark) | sky
    back = ndimage.binary_propagation(seeds, structure=four, mask=(~dark & ~inner & ~gold) | sky)
    light = ~dark & ~back & outer
    near = ndimage.distance_transform_cdt(~light, metric="chessboard") <= 2
    return ndimage.binary_fill_holes(light | (dark & near & outer)) & ~sky


def classes(rgb: np.ndarray) -> np.ndarray:
    """Each pixel's class: 0 keep, SKY, LEAVES, BLOSSOM, BRANCHES, GRASS or DARK (outline and deep shade)."""
    hsv = np.array([[colorsys.rgb_to_hsv(*p) for p in row] for row in rgb])
    hue, sat, val = hsv[..., 0] * 360, hsv[..., 1], hsv[..., 2]
    rows = np.arange(rgb.shape[0])[:, None] + BOX[1]
    out = np.zeros(rgb.shape[:2], int)
    out[app_icon_art.sky_mask(rgb)] = SKY
    green = (hue > 60) & (hue < 170) & (sat > 0.18) & (val > 0.18)
    out[green & (rows < GROUND)] = LEAVES
    out[green & (rows >= GROUND)] = GRASS
    out[((hue > 270) | (hue < 8)) & (sat > 0.15) & (val > 0.2) & ~green] = BLOSSOM
    out[(hue >= 8) & (hue < 45) & (sat > 0.15) & (val > 0.15) & (val < 0.62)] = BRANCHES
    out[val <= 0.18] = DARK
    out[(hue >= 45) & (hue <= 60) & (rows >= GROUND)] = GRASS
    out[hero_mask()] = 0
    return out


def luma(c) -> float:
    return float(np.dot(c, [0.299, 0.587, 0.114]))


def recolour(rgb: np.ndarray, kind: np.ndarray, season: dict) -> tuple:
    """RD's colours swapped class by class, rank for rank, onto the season's ramps; the sky in its bands;
    the dark pixels a deep shade of the class they round. Returns the image and each class's new ramp."""
    out = rgb.copy()
    key = (rgb * 255 + 0.5).astype(int)
    ramps = {}
    for code in (LEAVES, BLOSSOM, BRANCHES, GRASS):
        where = kind == code
        colours = sorted({tuple(c) for c in key[where]}, key=lambda c: luma(np.array(c)))
        if not colours:
            continue
        ramps[code] = ramp(*season[code], max(2, len(colours)))
        swap = {c: ramps[code][round(i * (len(ramps[code]) - 1) / max(1, len(colours) - 1))] for i, c in enumerate(colours)}
        for y, x in np.argwhere(where):
            out[y, x] = swap[tuple(key[y, x])]
    # The sky: a band per third of the icon, its lighter shade where RD's sky was lighter.
    sky = kind == SKY
    lights = sorted({tuple(c) for c in key[sky]}, key=lambda c: luma(np.array(c)))
    for y, x in np.argwhere(sky):
        band = season["sky"][min(2, y * 3 // rgb.shape[0])]
        out[y, x] = hexrgb(band[1] if tuple(key[y, x]) == lights[-1] and len(lights) > 1 else band[0])
    # The dark pixels: the deepest shade of the class most round them, darker still.
    h, w = kind.shape
    for y, x in np.argwhere(kind == DARK):
        near = kind[max(0, y - 2):y + 3, max(0, x - 2):x + 3].ravel()
        near = near[(near != DARK) & (near != 0) & (near != SKY)]
        code = np.bincount(near).argmax() if len(near) else LEAVES
        deep = ramps.get(code, ramps.get(LEAVES))[0]
        out[y, x] = deep * 0.72
    return out, ramps


def place(out: np.ndarray, sprite: Image.Image, x: int, y: int, behind: np.ndarray = None) -> None:
    """A rendered sprite with its top left at the drawing's (x, y); where `behind` is True it doesn't cover."""
    art = np.asarray(sprite.convert("RGBA"), dtype=float) / 255
    for dy in range(art.shape[0]):
        for dx in range(art.shape[1]):
            if art[dy, dx, 3] < 0.5:
                continue
            ox, oy = x + dx - BOX[0], y + dy - BOX[1]
            if 0 <= ox < out.shape[1] and 0 <= oy < out.shape[0] and (behind is None or not behind[oy, ox]):
                out[oy, ox] = art[dy, dx, :3]


def hat(out: np.ndarray, sprite: Image.Image, x: int, y: int) -> None:
    """A hat put on: first the hair above its brim or band is cleared (sprite-acceptance.md, *Head pieces*:
    no hair poking up round it), each hair pixel taking the colour of the nearest scenery in its row, then
    the hat itself."""
    alpha = np.asarray(sprite.convert("RGBA"))[..., 3] >= 128
    cover = np.zeros(out.shape[:2], bool)
    for dy, dx in np.argwhere(alpha):
        oy, ox = y + dy - BOX[1], x + dx - BOX[0]
        if 0 <= ox < out.shape[1] and 0 <= oy < out.shape[0]:
            cover[oy, ox] = True
    hero = hero_mask()
    for col in np.flatnonzero(cover.any(axis=0)):
        bottom = np.flatnonzero(cover[:, col]).max()
        for row in range(bottom):
            if hero[row, col] and not cover[row, col]:
                for reach in range(1, out.shape[1]):
                    for side in (col - reach, col + reach):
                        if 0 <= side < out.shape[1] and not hero[row, side] and not cover[row, side]:
                            out[row, col] = out[row, side]
                            break
                    else:
                        continue
                    break
    place(out, sprite, x, y)


def shadow(out, kind, x0, x1, y, depth=0.62) -> None:
    """A contact shadow on the ground under something set on it: a flat oval, the ground's shades darker."""
    for x in range(x0, x1 + 1):
        for dy in (0, 1):
            ox, oy = x - BOX[0], y + dy - BOX[1]
            inset = (x - x0 < 2 or x1 - x < 2) and dy == 1
            if 0 <= ox < out.shape[1] and 0 <= oy < out.shape[0] and kind[oy, ox] in (GRASS, DARK) and not inset:
                out[oy, ox] = out[oy, ox] * depth


def pixels(out, kind, points, colours, allowed) -> None:
    """Small marks (a flower, a snowflake, a bat) at the drawing's points, only on `allowed` classes."""
    for (x, y), colour in zip(points, colours):
        ox, oy = x - BOX[0], y - BOX[1]
        if 0 <= ox < out.shape[1] and 0 <= oy < out.shape[0] and kind[oy, ox] in allowed:
            out[oy, ox] = colour


# --- the hats --------------------------------------------------------------------------------------------
# Each is drawn so its band's middle lands on the head's widest row above the eyes, (120, 72).

def witch_hat() -> tuple:
    """A witch's hat: a wide brim, a cone with hollow sides that bends over near the top, its tip hanging
    off to the right, and a gold band. The cone is one shape: up its sides, then along a tapering curve."""
    import math
    s = Sprite(92, 50)
    purple = Material("#5a3a8c", shades=5, texture=0.05)
    s.ellipse(42, 42, 40, 6.5, purple, rot=-3)

    def bend(t):
        # A cubic curve from the cone's waist up and over to its tip.
        p = [(42, 26), (40, 16), (52, 10), (68, 20)]
        x = (1 - t) ** 3 * p[0][0] + 3 * (1 - t) ** 2 * t * p[1][0] + 3 * (1 - t) * t * t * p[2][0] + t ** 3 * p[3][0]
        y = (1 - t) ** 3 * p[0][1] + 3 * (1 - t) ** 2 * t * p[1][1] + 3 * (1 - t) * t * t * p[2][1] + t ** 3 * p[3][1]
        return x, y

    steps = [i / 16 for i in range(17)]
    left, right = [], []
    for t in steps:
        x, y = bend(t)
        x2, y2 = bend(min(1, t + 0.02))
        x1, y1 = bend(max(0, t - 0.02))
        dx, dy = x2 - x1, y2 - y1
        n = math.hypot(dx, dy) or 1
        half = 9.0 * (1 - t) ** 1.2 + 1.0
        left.append((x + dy / n * half, y - dx / n * half))
        right.append((x - dy / n * half, y + dx / n * half))
    cone = [(19, 42), (25, 35), (30, 30), (33, 27)] + left + right[::-1] + [(51, 27), (55, 31), (60, 36), (66, 42)]
    s.poly(cone, purple)
    s.poly([(20, 38), (65, 38), (63, 34), (22, 34)], Material("#e8a838", shades=4, texture=0.03, gloss=0.4), profile="cylinder")
    return s.render(), (78, 30)


def santa_hat() -> tuple:
    s = Sprite(86, 50)
    fur = Material("#f2f0f6", shades=4, texture=0.12, grain=1.0)
    s.poly([(12, 36), (16, 22), (26, 12), (40, 6), (54, 8), (66, 16), (74, 26), (80, 38), (78, 44), (72, 34),
            (66, 26), (66, 36)], Material("#cc2e3e", shades=5, texture=0.05))
    s.ellipse(40, 38, 36, 7, fur)
    s.ellipse(78, 43, 6.5, 6.5, fur)
    return s.render(), (79, 33)


def bunny_ears() -> tuple:
    """Bunny ears on a pink band worn over the hair, a little back from the brow, the ears standing up and
    leaning a little apart."""
    s = Sprite(70, 50)
    white = Material("#f4f0f8", shades=4, texture=0.04)
    pink = Material("#ff9cc0", shades=4, texture=0.03)
    s.ellipse(22, 22, 6.5, 16, white, rot=-20)
    s.ellipse(48, 22, 6.5, 16, white, rot=20)
    s.ellipse(22, 23, 2.8, 11, pink, rot=-20, profile="flat")
    s.ellipse(48, 23, 2.8, 11, pink, rot=20, profile="flat")
    s.stroke([(4, 48), (12, 40), (24, 36), (46, 36), (58, 40), (66, 48)], 5, pink)
    return s.render(), (85, 26)


# --- the props -------------------------------------------------------------------------------------------

def pumpkin() -> Image.Image:
    s = Sprite(20, 17)
    orange = Material("#e8781e", shades=5, texture=0.05)
    s.ellipse(5.5, 11, 5, 5.5, orange)
    s.ellipse(14.5, 11, 5, 5.5, orange)
    s.ellipse(10, 10.5, 6, 6, orange)
    s.stroke([(10, 5), (11, 1.5)], 2.6, Material("#5c7a2a", shades=3, texture=0.02))
    img = s.render()
    glow, deep = (255, 228, 120, 255), (255, 168, 52, 255)
    for x, y, c in [(6, 9, glow), (7, 9, glow), (7, 10, deep), (12, 9, glow), (13, 9, glow), (12, 10, deep),
                    (6, 13, deep), (7, 13, glow), (8, 13, glow), (9, 14, glow), (10, 13, glow), (11, 14, glow),
                    (12, 13, glow), (13, 13, deep)]:
        img.putpixel((x, y), c)
    return img


def egg(base: str, stripe: str) -> Image.Image:
    s = Sprite(11, 13)
    s.ellipse(5.5, 6.8, 4.3, 5.8, Material(base, shades=4, texture=0.03, gloss=0.3))
    s.ellipse(5.5, 7.4, 4.0, 1.3, Material(stripe, shades=3, texture=0.0), profile="flat")
    return s.render()


def moon() -> Image.Image:
    s = Sprite(17, 17)
    s.ellipse(8.5, 8.5, 7.5, 7.5, Material("#f6e2a2", shades=4, texture=0.1, grain=2.0))
    s.ellipse(6, 7, 1.8, 1.6, Material("#d4b46e", shades=2, texture=0.0), profile="flat")
    s.ellipse(10.5, 11, 1.6, 1.4, Material("#d4b46e", shades=2, texture=0.0), profile="flat")
    return s.render(outline="tinted")


BAT = ["k.......k",
       "kkk.k.kkk",
       ".kkkkkkk.",
       "..kk.kk.."]


def bat(out, kind, x, y, colour) -> None:
    for dy, row in enumerate(BAT):
        for dx, ch in enumerate(row):
            if ch == "k":
                pixels(out, kind, [(x + dx, y + dy)], [colour], (SKY, BLOSSOM, LEAVES))


def plus(x, y):
    return [(x, y), (x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]


# --- the seasons -----------------------------------------------------------------------------------------

def halloween(out, kind, ramps):
    place(out, moon(), 82, 40, behind=kind == 0)
    deep = hexrgb("#1a0c26")
    for x, y in ((52, 112), (66, 121), (156, 97)):
        bat(out, kind, x, y, deep)
    shadow(out, kind, 70, 90, 166)
    place(out, pumpkin(), 70, 150)
    small = pumpkin().resize((14, 12), Image.NEAREST)
    shadow(out, kind, 148, 161, 166)
    place(out, small, 148, 155)
    sprite, at = witch_hat()
    hat(out, sprite, *at)


def christmas(out, kind, ramps):
    snow = [hexrgb(c) for c in SNOW]
    # Snow on the lit tops of the leaves' clusters: their lightest colour turns to snow, the next to its shadow.
    leaves = ramps[LEAVES]
    for y, x in np.argwhere(kind == LEAVES):
        c = out[y, x]
        if np.allclose(c, leaves[-1]):
            out[y, x] = snow[4]
        elif len(leaves) > 2 and np.allclose(c, leaves[-2]):
            out[y, x] = snow[2]
    flakes = [(90, 46), (62, 108), (54, 124), (160, 96), (74, 126), (160, 126)]
    for x, y in flakes:
        pixels(out, kind, plus(x, y), [snow[4]] * 5, (SKY, BLOSSOM, LEAVES, BRANCHES))
    sprite, at = santa_hat()
    hat(out, sprite, *at)


def easter(out, kind, ramps):
    # Flowers in the meadow: a cross of petals round a gold centre, clear of the eggs.
    petals = [hexrgb("#ffffff"), hexrgb("#ffd6ea"), hexrgb("#e6d4ff")]
    for i, (x, y) in enumerate([(52, 150), (95, 160), (158, 150), (66, 162)]):
        pixels(out, kind, plus(x, y), [hexrgb("#ffc83a")] + [petals[i % 3]] * 4, (GRASS, DARK))
    for (base, stripe), x, y in ((("#ff9cc4", "#7cc8ff"), 69, 153), (("#9ce08a", "#ffd25a"), 79, 156),
                                 (("#b8a4ff", "#ff9c9c"), 149, 154)):
        shadow(out, kind, x + 1, x + 9, y + 12)
        place(out, egg(base, stripe), x, y)
    sprite, at = bunny_ears()
    place(out, sprite, *at)


DRAW = {"Halloween": halloween, "Christmas": christmas, "Easter": easter}


def icon(season: str) -> Image.Image:
    rgb = app_icon_art.crop(BOX)
    kind = classes(rgb)
    out, ramps = recolour(rgb, kind, SEASONS[season])
    DRAW[season](out, kind, ramps)
    big = np.repeat(np.repeat(out, SCALE, axis=0), SCALE, axis=1)
    return Image.fromarray((np.clip(big, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def write(season: str, image: Image.Image) -> Path:
    folder = ASSETS / f"AppIcon-{season}.appiconset"
    folder.mkdir(exist_ok=True)
    name = f"AppIcon-{season}.png"
    image.save(folder / name, optimize=True)
    (folder / "Contents.json").write_text(json.dumps({
        "images": [{"filename": name, "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    }, indent=2) + "\n")
    return folder / name


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--preview", type=Path, help="write all three at Home Screen sizes here, beside the app icon")
    args = parser.parse_args()
    made = {}
    for season in SEASONS:
        made[season] = icon(season)
        print(f"wrote {write(season, made[season]).relative_to(ROOT)}")
    if args.preview:
        sizes = [300, 120, 60]
        rows = [Image.open(app_icon_art.LIGHT).convert("RGB")] + list(made.values())
        sheet = Image.new("RGB", (sum(sizes) + 10 * (len(sizes) + 1), len(rows) * 320), (242, 242, 247))
        for index, image in enumerate(rows):
            x = 10
            for side in sizes:
                sheet.paste(app_icon_art.rounded(image, side), (x, 10 + index * 320))
                x += side + 10
        sheet.save(args.preview)
        print(f"preview in {args.preview}: the app icon, then {', '.join(made)}")


if __name__ == "__main__":
    main()
