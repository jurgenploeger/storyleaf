#!/usr/bin/env python3
"""The seasonal app icons, Halloween, Christmas and Easter, that the game switches to while each festive
season runs (`SeasonalIcon` in Storyleaf/App, the seasons' dates in content/rewards.json `festive`). The
same picked drawing as the app icon (tools/app_icon_art.py `SOURCE`), cropped a little looser so a hat
fits on the hero's head (`BOX`, 128 pixels at 8×), with only the scenery changed and something festive
on him:

  Halloween  a purple night under a big moon, autumn leaves, bats, jack-o'-lanterns, a witch's hat
  Christmas  a pale winter sky, snow on the trees and the ground, fairy lights, falling snow, a Santa hat
  Easter     a fresh spring meadow, blossom, flowers and painted eggs, bunny ears

The hero is left as drawn (`HERO`, his outline in the drawing's pixels). Every background pixel is sorted
by its colour (sky, leaves, blossom, branches, grass, outline) and its shade laid on the season's ramp for
that class in hard steps, as pixel art shades; what's added is drawn in the same pixels with a dark
outline. Written as AppIcon-<Season>.appiconset, one 1024 image each (iOS shows it in every appearance).

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

import app_icon_art

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "Storyleaf/Resources/Assets.xcassets"

BOX = (44, 40, 172, 168)
SCALE = 8
# The hero and his sword, in the drawing's pixels: nothing inside is regraded.
HERO = [(55, 44), (64, 43), (72, 60), (79, 78), (85, 98), (89, 110), (93, 108), (96, 100), (94, 90), (87, 84),
        (84, 76), (90, 66), (98, 56), (108, 51), (122, 51), (136, 53), (146, 59), (151, 70), (153, 84), (151, 98),
        (149, 106), (151, 112), (152, 124), (150, 132), (155, 140), (153, 150), (146, 156), (145, 168), (97, 168),
        (97, 157), (93, 155), (87, 153), (84, 144), (78, 141), (77, 131), (66, 131), (63, 124), (71, 118),
        (79, 117), (71, 96), (62, 72), (55, 50)]
# Below this row the green is the meadow, above it the trees' leaves.
GROUND = 147
INK = (24, 14, 18)


def rgb(*c):
    return np.array(c, dtype=float) / 255


SEASONS = {
    "Halloween": {
        "sky": [rgb(46, 26, 78), rgb(74, 36, 96), rgb(120, 52, 96), rgb(196, 92, 60)],
        "leaves": [rgb(70, 24, 20), rgb(136, 48, 22), rgb(200, 94, 30), rgb(240, 152, 46)],
        "blossom": [rgb(36, 18, 50), rgb(66, 30, 82), rgb(102, 48, 112), rgb(142, 78, 142)],
        "branches": [rgb(28, 18, 22), rgb(52, 32, 32), rgb(80, 52, 44)],
        "grass": [rgb(40, 40, 22), rgb(70, 66, 28), rgb(108, 94, 36), rgb(150, 122, 46)],
        "outline": rgb(20, 12, 24),
    },
    "Christmas": {
        "sky": [rgb(146, 184, 226), rgb(172, 204, 236), rgb(198, 222, 244), rgb(220, 236, 250)],
        "leaves": [rgb(14, 44, 38), rgb(24, 74, 56), rgb(44, 108, 72), rgb(80, 146, 92)],
        "blossom": [rgb(140, 160, 196), rgb(184, 202, 228), rgb(222, 232, 247), rgb(248, 251, 255)],
        "branches": [rgb(30, 22, 28), rgb(56, 40, 44), rgb(86, 66, 66)],
        "grass": [rgb(146, 166, 204), rgb(186, 204, 232), rgb(220, 231, 247), rgb(248, 251, 255)],
        "outline": rgb(22, 20, 36),
    },
    "Easter": {
        "sky": [rgb(112, 192, 248), rgb(146, 212, 252), rgb(184, 228, 254), rgb(218, 242, 255)],
        "leaves": [rgb(36, 94, 46), rgb(72, 148, 58), rgb(126, 194, 78), rgb(186, 226, 118)],
        "blossom": [rgb(150, 70, 120), rgb(212, 110, 160), rgb(244, 160, 198), rgb(255, 214, 232)],
        "branches": [rgb(46, 28, 26), rgb(82, 52, 40), rgb(122, 82, 58)],
        "grass": [rgb(48, 116, 46), rgb(88, 166, 58), rgb(146, 206, 86), rgb(198, 234, 136)],
        "outline": rgb(24, 20, 24),
    },
}


def hero_mask() -> np.ndarray:
    w, h = BOX[2] - BOX[0], BOX[3] - BOX[1]
    image = Image.new("L", (w, h))
    ImageDraw.Draw(image).polygon([(x - BOX[0], y - BOX[1]) for x, y in HERO], fill=255)
    return np.asarray(image) > 0


def classes(rgb_: np.ndarray) -> np.ndarray:
    """Each pixel's class: 0 keep, 1 sky, 2 leaves, 3 blossom, 4 branches, 5 grass, 6 outline."""
    hsv = np.array([[colorsys.rgb_to_hsv(*p) for p in row] for row in rgb_])
    hue, sat, val = hsv[..., 0] * 360, hsv[..., 1], hsv[..., 2]
    rows = np.arange(rgb_.shape[0])[:, None] + BOX[1]
    out = np.zeros(rgb_.shape[:2], int)
    out[app_icon_art.sky_mask(rgb_)] = 1
    green = (hue > 60) & (hue < 170) & (sat > 0.18) & (val > 0.18)
    out[green & (rows < GROUND)] = 2
    out[green & (rows >= GROUND)] = 5
    out[((hue > 270) | (hue < 8)) & (sat > 0.15) & (val > 0.2) & ~green] = 3
    brown = (hue >= 8) & (hue < 45) & (sat > 0.15) & (val > 0.15) & (val < 0.62)
    out[brown] = 4
    out[val <= 0.18] = 6
    # Yellow flowers in the grass stay grass.
    out[(hue >= 45) & (hue <= 60) & (rows >= GROUND)] = 5
    return out


def ramp(luma: np.ndarray, colours: list, low: float, high: float) -> np.ndarray:
    """Each shade, in hard steps, on `colours` from dark to light."""
    steps = np.clip(((luma - low) / max(high - low, 1e-6) * len(colours)).astype(int), 0, len(colours) - 1)
    return np.array(colours)[steps]


def regrade(rgb_: np.ndarray, season: dict) -> np.ndarray:
    out = rgb_.copy()
    luma = rgb_ @ np.array([0.299, 0.587, 0.114])
    kind = classes(rgb_)
    kind[hero_mask()] = 0
    rows = np.arange(rgb_.shape[0])
    for code, name in ((2, "leaves"), (3, "blossom"), (4, "branches"), (5, "grass")):
        where = kind == code
        if where.any():
            lo, hi = np.percentile(luma[where], [3, 97])
            out[where] = ramp(luma[where], season[name], lo, hi)[:]
    # The sky in bands down the icon, a step lighter where the day sky was lighter.
    sky = kind == 1
    band = np.minimum((rows * len(season["sky"])) // len(rows), len(season["sky"]) - 1)
    sky_colour = np.array(season["sky"])[band][:, None, :].repeat(rgb_.shape[1], axis=1)
    out[sky] = sky_colour[sky]
    out[kind == 6] = season["outline"]
    return out, kind


OVER = 4


def part(draw_fn) -> np.ndarray:
    """A shape in the drawing's pixels: `draw_fn` draws it on an ImageDraw in the drawing's coordinates
    (a smooth shape, drawn OVER times as big), and each pixel is in when it's mostly covered."""
    w, h = BOX[2] - BOX[0], BOX[3] - BOX[1]
    image = Image.new("L", (w * OVER, h * OVER))

    class Scaled:
        def __init__(self, draw):
            self.draw = draw

        def polygon(self, points, **kw):
            self.draw.polygon([((x - BOX[0]) * OVER, (y - BOX[1]) * OVER) for x, y in points], fill=255)

        def ellipse(self, box, **kw):
            x0, y0, x1, y1 = box
            self.draw.ellipse([(x0 - BOX[0]) * OVER, (y0 - BOX[1]) * OVER, (x1 - BOX[0]) * OVER, (y1 - BOX[1]) * OVER], fill=255)

    draw_fn(Scaled(ImageDraw.Draw(image)))
    small = image.resize((w, h), Image.BOX)
    return np.asarray(small) >= 128


def shift(mask: np.ndarray, dx: int, dy: int) -> np.ndarray:
    out = np.zeros_like(mask)
    h, w = mask.shape
    out[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = mask[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    return out


def paint(out, parts, ink) -> None:
    """Shaded parts, each (mask, base, light, dark): lit on its top-left edge, shaded on its bottom-right, in
    hard steps, then one dark outline round them all. Later parts go over earlier ones."""
    union = np.zeros(out.shape[:2], bool)
    for mask, base, light, dark in parts:
        out[mask] = base
        out[mask & ~shift(mask, 1, 1)] = light
        out[mask & ~shift(mask, -2, -2)] = dark
        union |= mask
    ring = (shift(union, 1, 0) | shift(union, -1, 0) | shift(union, 0, 1) | shift(union, 0, -1)) & ~union
    out[ring] = ink


def sprite(out, rows: list[str], palette: dict, x0: int, y0: int, only=None) -> None:
    """A sprite in characters, '.' clear, at the drawing's (x0, y0). `only` limits it to where that's True."""
    for dy, row in enumerate(rows):
        for dx, ch in enumerate(row):
            if ch == ".":
                continue
            x, y = x0 + dx - BOX[0], y0 + dy - BOX[1]
            if 0 <= x < out.shape[1] and 0 <= y < out.shape[0] and (only is None or only[y, x]):
                out[y, x] = palette[ch]


PUMPKIN = ["....kgk.....",
           "....kgk.....",
           ".kkkkkkkkkk.",
           "kkoOoOOoOokk",
           "kOoOyyOyyOok",
           "kOoOykOyOOok",
           "kOoOOOOOoOok",
           "kOoyyyyyyOok",
           "kOooykykyook",
           "kkoOoOOoOokk",
           ".kkkkkkkkkk."]
BAT = ["k.......k",
       "kk.k.k.kk",
       ".kkkkkkk.",
       "..kk.kk.."]
EGG = ["..kkk..",
       ".kAAAk.",
       "kAAAAAk",
       "kBBBBBk",
       "kAAAAAk",
       "kCCCCCk",
       "kAAAAAk",
       ".kAAAk.",
       "..kkk.."]


def scatter(out, kind, code, colours, count, seed):
    rng = np.random.default_rng(seed)
    where = np.argwhere(kind == code)
    for y, x in where[rng.choice(len(where), size=min(count, len(where)), replace=False)]:
        out[y, x] = colours[rng.integers(len(colours))]


def halloween(out, kind):
    ink = SEASONS["Halloween"]["outline"]
    sky = kind == 1
    # A big moon low in the sky to the left, behind the leaves.
    moon = part(lambda d: d.ellipse((47, 109, 66, 128)))
    craters = part(lambda d: (d.ellipse((52, 114, 56, 118)), d.ellipse((58, 120, 62, 124))))
    out[moon & sky] = rgb(255, 236, 168)
    out[craters & moon & sky] = rgb(236, 206, 132)
    out[moon & ~shift(moon, -2, 0) & sky] = rgb(236, 206, 132)
    for x, y in ((70, 106), (86, 46), (52, 104), (152, 98)):
        sprite(out, BAT, {"k": ink}, x, y, only=sky | (kind == 3))
    pumpkin = {"k": ink, "o": rgb(214, 104, 24), "O": rgb(244, 146, 40), "y": rgb(255, 226, 96), "g": rgb(70, 110, 40)}
    sprite(out, PUMPKIN, pumpkin, 60, 151)
    sprite(out, PUMPKIN, pumpkin, 150, 154)
    scatter(out, kind, 5, [rgb(214, 96, 30), rgb(240, 160, 48), rgb(170, 52, 30)], 40, 31)
    # A witch's hat on the hair: a wide brim, a tall cone bent back at the tip, a gold band.
    cone = part(lambda d: d.polygon([(100, 67), (108, 53), (113, 41), (114, 33), (122, 39), (131, 51), (140, 67)]))
    band = cone & part(lambda d: d.polygon([(96, 61), (146, 61), (146, 67), (96, 67)]))
    brim = part(lambda d: d.ellipse((80, 63, 160, 76)))
    purple, light, dark = rgb(70, 44, 104), rgb(110, 76, 150), rgb(42, 24, 66)
    paint(out, [(cone, purple, light, dark), (band, rgb(244, 176, 52), rgb(255, 224, 120), rgb(196, 120, 30)),
                (brim, purple, light, dark)], ink)


def christmas(out, kind):
    snow = rgb(248, 251, 255)
    shade = rgb(206, 220, 242)
    h, w = kind.shape
    # Snow on the tops of the leaves and branches: where the pixel above is sky or the outline.
    for y in range(1, h):
        for x in range(w):
            if kind[y, x] in (2, 4) and kind[y - 1, x] in (1, 6):
                out[y, x] = snow
                if y + 1 < h and kind[y + 1, x] == kind[y, x]:
                    out[y + 1, x] = shade
    scatter(out, kind, 2, [rgb(255, 84, 84), rgb(255, 214, 90), rgb(110, 180, 255), rgb(140, 240, 140)], 26, 12)
    for code in (1, 3, 4):
        scatter(out, kind, code, [snow], 14, 40 + code)
    # A Santa hat over the hair: the red cap flopping to the right, a white fur band, a pompom.
    cap = part(lambda d: d.polygon([(90, 69), (96, 57), (108, 49), (122, 47), (136, 50), (148, 57), (156, 67),
                                    (160, 77), (154, 75), (146, 65), (148, 71)]))
    fur = part(lambda d: d.ellipse((84, 63, 152, 77)))
    pom = part(lambda d: d.ellipse((150, 71, 164, 85)))
    red, light, dark = rgb(214, 40, 50), rgb(246, 96, 92), rgb(150, 20, 36)
    white, wlight, wdark = rgb(244, 246, 252), rgb(255, 255, 255), rgb(196, 206, 228)
    paint(out, [(cap, red, light, dark), (fur, white, wlight, wdark), (pom, white, wlight, wdark)], INK)


def easter(out, kind):
    # Fluffy clouds in the sky gaps.
    sky = kind == 1
    clouds = part(lambda d: [d.ellipse(b) for b in ((86, 44, 102, 54), (94, 40, 110, 52), (44, 108, 62, 118), (52, 104, 70, 116), (150, 96, 166, 106))])
    out[clouds & sky] = rgb(255, 255, 255)
    out[clouds & sky & ~shift(clouds, 0, -2)] = rgb(214, 232, 250)
    # Blossom among the leaves, and flowers all over the meadow.
    scatter(out, kind, 2, [rgb(255, 196, 222), rgb(255, 238, 246), rgb(244, 150, 196)], 70, 9)
    scatter(out, kind, 5, [rgb(255, 255, 255), rgb(255, 228, 90), rgb(255, 170, 210), rgb(200, 170, 255)], 60, 7)
    eggs = [
        ({"k": INK, "A": rgb(255, 196, 220), "B": rgb(120, 200, 255), "C": rgb(255, 230, 110)}, 60, 152),
        ({"k": INK, "A": rgb(186, 240, 170), "B": rgb(255, 150, 190), "C": rgb(190, 160, 255)}, 68, 157),
        ({"k": INK, "A": rgb(255, 232, 150), "B": rgb(150, 130, 255), "C": rgb(255, 150, 150)}, 149, 155),
        ({"k": INK, "A": rgb(170, 220, 255), "B": rgb(255, 200, 100), "C": rgb(180, 236, 160)}, 157, 152),
    ]
    for palette, x, y in eggs:
        sprite(out, EGG, palette, x, y)
    # Bunny ears on a pink band over the hair, tilted apart, rising out of the top of the icon.
    def ear(cx, tilt):
        import math
        points = []
        for i in range(24):
            a = 2 * math.pi * i / 24
            x, y = 5.5 * math.cos(a), 17 * math.sin(a)
            r = math.radians(tilt)
            points.append((cx + x * math.cos(r) - y * math.sin(r), 42 + x * math.sin(r) + y * math.cos(r)))
        return points

    def inner(cx, tilt):
        import math
        points = []
        for i in range(24):
            a = 2 * math.pi * i / 24
            x, y = 2.5 * math.cos(a), 12 * math.sin(a)
            r = math.radians(tilt)
            points.append((cx + x * math.cos(r) - y * math.sin(r), 44 + x * math.sin(r) + y * math.cos(r)))
        return points

    left, right = part(lambda d: d.polygon(ear(108, -14))), part(lambda d: d.polygon(ear(134, 14)))
    left_in, right_in = part(lambda d: d.polygon(inner(108, -14))), part(lambda d: d.polygon(inner(134, 14)))
    band = part(lambda d: d.polygon([(94, 66), (102, 58), (114, 54), (128, 54), (140, 58), (148, 66), (146, 69), (138, 62), (128, 58), (114, 58), (104, 62), (97, 69)]))
    white, wlight, wdark = rgb(248, 246, 252), rgb(255, 255, 255), rgb(206, 200, 222)
    pink, plight, pdark = rgb(255, 160, 196), rgb(255, 206, 226), rgb(222, 106, 150)
    paint(out, [(left, white, wlight, wdark), (right, white, wlight, wdark), (band, pink, plight, pdark)], INK)
    out[left_in] = pink
    out[right_in] = pink


DRAW = {"Halloween": halloween, "Christmas": christmas, "Easter": easter}


def icon(season: str) -> Image.Image:
    rgb_ = app_icon_art.crop(BOX)
    out, kind = regrade(rgb_, SEASONS[season])
    DRAW[season](out, kind)
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
