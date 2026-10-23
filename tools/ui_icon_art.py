#!/usr/bin/env python3
"""The UI's own pixel-art icons, drawn in code like the items: writes art/sprites/ui_<icon>.png (32×32).

Each is named after the `GameIcon` it stands in for (Storyleaf/UI/GameIcon.swift): `IconImage` shows the
pixel art at button sizes (the battle buttons, the HUD's buttons, the menu's tabs) and keeps the vector
icon for small inline glyphs. Same look as tools/item_art.py: flat colours with a light and a dark shade
and the game's dark outline. Edit a drawing and rerun:

    python3 tools/ui_icon_art.py               # all of them
    python3 tools/ui_icon_art.py sword paw     # just these
    python3 tools/ui_icon_art.py --sheet out.png   # also a 4× contact sheet
"""

import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from item_art import OUTLINE, TEAL, Canvas, GOLD, SPRITES, STEEL, WOOD, encode_png, hexc, seal_gem  # noqa: E402

SIZE = 32
LEATHER = [hexc("6d3f1f"), hexc("9a5b2c"), hexc("c98a4b")]
RED = [hexc("9e1b2a"), hexc("d8333f"), hexc("ff7a7f")]
BLUE = [hexc("1f4fa0"), hexc("3d7fe0"), hexc("8fc3ff")]
GREEN = [hexc("2e6b2e"), hexc("4caf50"), hexc("9be38f")]
PINK = [hexc("c2507a"), hexc("f48fb1"), hexc("ffd0e2")]
PARCH = [hexc("b8925a"), hexc("e8cf9a"), hexc("fff3d6")]
CREAM = [hexc("cdbb98"), hexc("f6ead0"), hexc("ffffff")]
CYAN = [hexc("1b8fa8"), hexc("4fd1e8"), hexc("c4f6ff")]
WHITE = hexc("ffffff")
INK = hexc("2b2140")


def shade_ball(c, tones, cx, cy, r, only=None):
    """Three-tone shading of the pixels in `tones`' middle colour (or `only`): light up-left, dark down-right."""
    dark, mid, light = tones
    target = only or mid
    for y in range(SIZE):
        for x in range(SIZE):
            if c.px[y][x] == target:
                d = (x - cx) + (y - cy)
                if d > r * 0.5:
                    c.px[y][x] = dark
                elif d < -r * 0.7:
                    c.px[y][x] = light


def star_points(cx, cy, outer, inner, points, turn=-math.pi / 2):
    return [
        (cx + math.cos(turn + i * math.pi / points) * (outer if i % 2 == 0 else inner),
         cy + math.sin(turn + i * math.pi / points) * (outer if i % 2 == 0 else inner))
        for i in range(points * 2)
    ]


# ---------------------------------------------------------------- the icons

def draw_sword(c):
    # Attack: a broad steel blade with a bright edge, a heavy gold guard and a red gem.
    c.poly([(27.5, 3), (29, 4.5), (13.5, 22.5), (9.5, 18.5)], STEEL[1])
    c.poly([(27.5, 3), (29, 4.5), (13.5, 22.5), (11.5, 20.5)], STEEL[0])
    c.line(26.5, 4.5, 11, 19.5, STEEL[2])
    c.line(25, 5, 12.5, 17.5, STEEL[1])
    c.line(6, 15, 16, 25, GOLD[1], width=3.4)
    c.line(6, 14.5, 15, 23.5, GOLD[2])
    c.line(10, 22, 5, 27, WOOD[1], width=3)
    c.line(10, 23, 5.5, 27.5, WOOD[0])
    c.disc(4, 28, 2.2, GOLD[1])
    c.set(3, 27, GOLD[2])
    c.disc(11, 20, 1.5, RED[1])
    c.set(10, 19, RED[2])


def draw_sparkles(c):
    # Skills: a big gold star with a cyan and a pink one, each four-pointed.
    for (cx, cy, outer, inner, tones) in [(13, 15, 11.5, 3.2, GOLD), (24.5, 7.5, 6.5, 2, CYAN), (24.5, 23.5, 5.5, 1.8, PINK)]:
        c.poly(star_points(cx, cy, outer, inner, 4), tones[1])
        shade_ball(c, tones, cx, cy, inner * 1.6)
        c.set(cx, cy, WHITE)
    c.rect(12, 14, 13, 15, WHITE)


def draw_backpack(c):
    # Bag and Items: a leather pack with a buckled flap, a pocket and a top handle.
    c.ring(16, 8, 4.5, 2.6, LEATHER[0])
    c.poly([(6, 10), (26, 10), (27, 28), (5, 28)], LEATHER[1])
    c.rect(5, 26, 27, 28, LEATHER[0])
    c.poly([(7, 9), (25, 9), (25, 16), (21, 19), (11, 19), (7, 16)], LEATHER[2])
    c.shade(lambda x, y, col: col == LEATHER[2] and y >= 16, LEATHER[1])
    c.rect(10, 21, 22, 26, LEATHER[0])
    c.rect(11, 21, 21, 25, LEATHER[1])
    c.rect(14, 16, 17, 19, GOLD[1])
    c.rect(15, 17, 16, 18, LEATHER[0])
    c.set(14, 16, GOLD[2])
    c.shade(lambda x, y, col: col == LEATHER[1] and x >= 24, LEATHER[0])


def draw_shield(c):
    # Guard: a steel-rimmed heater shield, blue with a gold star.
    c.poly([(5, 4), (27, 4), (27, 15), (16, 30), (5, 15)], STEEL[1])
    c.poly([(8, 7), (24, 7), (24, 15), (16, 26), (8, 15)], BLUE[1])
    c.shade(lambda x, y, col: col == BLUE[1] and x >= 16, BLUE[0])
    c.shade(lambda x, y, col: col == BLUE[1] and x < 12 and y < 13, BLUE[2])
    c.shade(lambda x, y, col: col == STEEL[1] and x >= 17, STEEL[0])
    c.shade(lambda x, y, col: col == STEEL[1] and (x < 8 or y < 6), STEEL[2])
    c.poly(star_points(16, 15, 6, 2.6, 5), GOLD[1])
    shade_ball(c, GOLD, 16, 15, 3)


def draw_wind(c):
    # Run: a winged boot, with speed lines behind it.
    c.rect(13, 6, 20, 20, LEATHER[1])
    c.poly([(13, 19), (25, 19), (28, 23), (28, 26), (13, 26)], LEATHER[1])
    c.rect(13, 25, 28, 27, LEATHER[0])
    c.rect(12, 5, 21, 8, LEATHER[2])
    c.shade(lambda x, y, col: col == LEATHER[1] and x >= 18 and y < 20, LEATHER[0])
    c.rect(20, 21, 24, 22, LEATHER[2])
    c.poly([(13, 9), (4, 4), (5, 8), (2, 10), (6, 12), (3, 14), (9, 15), (13, 15)], WHITE)
    c.shade(lambda x, y, col: col == WHITE and y >= 13, CREAM[0])
    c.line(5, 9, 11, 11, CREAM[0])
    for y, x0 in [(19, 2), (22, 4), (25, 1)]:
        c.line(x0, y, x0 + 7, y, CYAN[1])


def draw_heart(c):
    # A glossy red heart.
    c.disc(10.5, 11.5, 6.2, RED[1])
    c.disc(21.5, 11.5, 6.2, RED[1])
    c.poly([(4.5, 13), (27.5, 13), (16, 27.5)], RED[1])
    shade_ball(c, RED, 16, 15, 9)
    c.rect(8, 8, 9, 9, WHITE)
    c.set(10, 8, RED[2])
    c.set(8, 10, RED[2])


def draw_seal_stone(c):
    # Capture: the Seal Stone you throw, the item's own teal crystal with its white spiral.
    seal_gem(c, TEAL)


def draw_more(c):
    # More: three gold orbs.
    for cx in (7, 16, 25):
        c.disc(cx, 16, 3.8, GOLD[1])
        shade_ball(c, GOLD, cx, 16, 3)
        c.set(cx - 1, 15, WHITE)


def draw_user(c):
    # Character: a knight's helm with a red plume.
    c.poly([(16, 2), (23, 1), (26, 4), (21, 7), (17, 8)], RED[1])
    c.line(18, 3, 24, 2, RED[2])
    c.disc(16, 15, 10, STEEL[1])
    c.rect(6, 15, 26, 25, STEEL[1])
    c.poly([(6, 24), (26, 24), (23, 29), (9, 29)], STEEL[1])
    shade_ball(c, STEEL, 16, 15, 10)
    c.rect(9, 15, 23, 17, INK)
    c.rect(15, 18, 16, 26, STEEL[0])
    c.line(10, 9, 14, 7, STEEL[2])
    c.rect(11, 20, 13, 21, STEEL[0])
    c.rect(18, 20, 20, 21, STEEL[0])


def draw_paw(c):
    # Companions: a paw with pink pads.
    # Toes a little smaller and apart from the pad: closer, the finish ran them together.
    for (cx, cy) in [(5.5, 12.5), (12, 6), (20, 6), (26.5, 12.5)]:
        c.ellipse(cx, cy, 3, 3.6, PINK[1])
        shade_ball(c, PINK, cx, cy, 2.6)
    c.poly([(10, 23), (12.5, 17.5), (19.5, 17.5), (22, 23), (19.5, 28), (12.5, 28)], PINK[1])
    c.ellipse(16, 23, 7, 5, PINK[1])
    shade_ball(c, PINK, 16, 22, 5.5)
    c.rect(12, 17, 13, 18, WHITE)


def draw_book(c):
    # Quests and books: a green storybook with gold corners, a gold leaf and a red ribbon.
    c.rect(24, 6, 26, 27, CREAM[1])
    c.rect(25, 7, 25, 26, CREAM[0])
    c.rect(6, 4, 24, 28, GREEN[1])
    c.rect(6, 4, 8, 28, GREEN[0])
    c.rect(9, 5, 23, 6, GREEN[2])
    for (x, y) in [(22, 4), (22, 27), (9, 4), (9, 27)]:
        c.rect(x, y, x + 2, y + 1, GOLD[1])
    c.poly([(16, 9), (21, 14), (16, 22), (11, 14)], GOLD[1])
    c.line(16, 11, 16, 20, GOLD[0])
    c.shade(lambda x, y, col: col == GOLD[1] and x < 15 and y < 14, GOLD[2])
    c.rect(18, 28, 20, 31, RED[1])
    c.set(19, 31, None)


def draw_talk(c):
    # Chat: a cream speech bubble with three blue dots.
    c.ellipse(16, 13, 13, 9.5, CREAM[1])
    c.poly([(8, 18), (6, 28), (16, 21)], CREAM[1])
    c.shade(lambda x, y, col: col == CREAM[1] and (y > 18 or x > 25), CREAM[0])
    c.shade(lambda x, y, col: col == CREAM[1] and y < 7, CREAM[2])
    for cx in (10, 16, 22):
        c.disc(cx, 13, 1.9, BLUE[1])
        c.set(cx - 1, 12, BLUE[2])


def draw_settings(c):
    # Settings: a steel cog round a blue gem.
    for i in range(8):
        angle = i * math.pi / 4
        cx, cy = 16 + math.cos(angle) * 11, 16 + math.sin(angle) * 11
        nx, ny = math.cos(angle + math.pi / 2) * 2.6, math.sin(angle + math.pi / 2) * 2.6
        dx, dy = math.cos(angle) * 3, math.sin(angle) * 3
        c.poly([(cx - nx - dx, cy - ny - dy), (cx + nx - dx, cy + ny - dy), (cx + nx + dx, cy + ny + dy), (cx - nx + dx, cy - ny + dy)], STEEL[1])
    c.disc(16, 16, 10, STEEL[1])
    shade_ball(c, STEEL, 16, 16, 10)
    c.disc(16, 16, 5.5, STEEL[0])
    c.disc(16, 16, 4, BLUE[1])
    shade_ball(c, BLUE, 16, 16, 3)
    c.set(15, 15, WHITE)


def draw_map(c):
    # Maps: folded parchment with a dotted red road to an X.
    c.poly([(3, 8), (11, 5), (20, 8), (29, 5), (29, 25), (20, 28), (11, 25), (3, 28)], PARCH[1])
    c.shade(lambda x, y, col: col == PARCH[1] and 11 <= x < 20, PARCH[0])
    c.shade(lambda x, y, col: col == PARCH[1] and x < 11 and y < 12, PARCH[2])
    c.ellipse(8, 20, 3, 2.5, GREEN[1])
    c.ellipse(24, 11, 2.5, 2, GREEN[1])
    for (x, y) in [(8, 15), (11, 13), (14, 15), (17, 17), (20, 15), (22, 13)]:
        c.set(x, y, RED[1])
    c.line(23, 18, 27, 22, RED[1], width=2)
    c.line(27, 18, 23, 22, RED[1], width=2)


def draw_gift(c):
    # Gifts: a red box tied with a gold ribbon and bow.
    c.rect(6, 15, 26, 29, RED[1])
    c.rect(4, 11, 28, 16, RED[2])
    c.rect(4, 15, 28, 16, RED[0])
    c.shade(lambda x, y, col: col == RED[1] and x >= 21, RED[0])
    c.rect(14, 11, 18, 29, GOLD[1])
    c.rect(14, 11, 15, 29, GOLD[2])
    c.ellipse(11, 8, 4.2, 3, GOLD[1])
    c.ellipse(21, 8, 4.2, 3, GOLD[1])
    c.ellipse(11, 8, 1.8, 1.2, GOLD[0])
    c.ellipse(21, 8, 1.8, 1.2, GOLD[0])
    c.rect(15, 7, 17, 10, GOLD[2])


def draw_coins(c):
    # Gold: three coins, one on top of two, each with a rim, a glint and a mark.
    for (cx, cy) in [(16, 11), (9.5, 21), (22.5, 21)]:
        c.disc(cx, cy, 8, OUTLINE)
        c.disc(cx, cy, 7, GOLD[0])
        c.disc(cx - 0.5, cy - 0.5, 5.8, GOLD[1])
        c.line(cx - 4, cy - 1, cx - 1, cy - 4, GOLD[2])
        c.rect(cx - 0.5, cy - 2.5, cx + 0.5, cy + 2.5, GOLD[0])


def draw_star(c):
    # Stars: a five-pointed gold star with a glint.
    c.poly(star_points(16, 16.5, 14, 6, 5), GOLD[1])
    shade_ball(c, GOLD, 16, 16, 7)
    c.rect(13, 11, 14, 12, WHITE)


def draw_egg(c):
    # Eggs: a cream egg with green spots.
    c.ellipse(16, 17.5, 9, 12, CREAM[1])
    shade_ball(c, CREAM, 16, 17, 8)
    for (x, y, r) in [(12, 13, 2), (19, 20, 2.5), (13, 23, 1.6), (20, 11, 1.4)]:
        c.disc(x, y, r, GREEN[1])
    c.rect(12, 8, 13, 9, WHITE)


def draw_arrow_down(c):
    # Bringing a game back (Import a backup): a green arrow down into a blue tray.
    c.rect(4, 19, 27, 28, BLUE[1])
    c.rect(6, 19, 25, 21, BLUE[0])
    c.rect(4, 22, 27, 22, BLUE[2])
    c.shade(lambda x, y, col: col == BLUE[1] and x >= 23, BLUE[0])
    c.rect(13, 3, 18, 12, GREEN[1])
    c.poly([(6.5, 11), (24.5, 11), (15.5, 20.5)], GREEN[1])
    c.shade(lambda x, y, col: col == GREEN[1] and (x <= 13 if y <= 11 else x < 15 - (y - 12) * 0.2), GREEN[2])
    c.shade(lambda x, y, col: col == GREEN[1] and x >= 18, GREEN[0])


def draw_users(c):
    # Friends: two adventurers side by side, shoulders up, the one in front outlined over the other.
    skin = [hexc("c98e5f"), hexc("f2c79a"), hexc("ffe3c4")]
    # Behind, on the left: green tunic, brown hair.
    c.ellipse(11, 25, 7.5, 7, GREEN[1])
    c.disc(11, 10, 4.8, skin[1])
    c.poly([(5.8, 9.5), (7.2, 5.2), (11, 4.2), (14.8, 5.2), (16.2, 9.5), (13.8, 7.6), (8.2, 7.6)], LEATHER[1])
    c.shade(lambda x, y, col: col == GREEN[1] and x >= 14, GREEN[0])
    # In front, on the right: blue tunic, gold hair, an outline where it covers the other.
    c.ellipse(21, 27, 9.5, 7.5, OUTLINE)
    c.disc(21, 13, 6.3, OUTLINE)
    c.ellipse(21, 27, 8.5, 6.5, BLUE[1])
    c.disc(21, 13, 5.3, skin[1])
    c.poly([(15.2, 12.5), (16.6, 7.8), (21, 6.4), (25.4, 7.8), (26.8, 12.5), (24, 10.6), (18, 10.6)], GOLD[1])
    c.shade(lambda x, y, col: col == BLUE[1] and x >= 25, BLUE[0])
    c.shade(lambda x, y, col: col == BLUE[1] and y <= 22 and x <= 19, BLUE[2])
    c.shade(lambda x, y, col: col == skin[1] and x >= 24 and y >= 13, skin[0])
    for (x, y) in [(9, 10), (13, 10), (19, 13), (23, 13)]:
        c.set(x, y, INK)
    # Cut off flat at the shoulders' foot, inside the frame so the outline goes round it.
    for y in range(29, 32):
        for x in range(32):
            c.px[y][x] = None

# GameIcon names use hyphens (arrow-down) where Python names can't: draw_arrow_down draws "arrow-down".
DRAWINGS = {name[len("draw_"):].replace("_", "-"): fn for name, fn in list(globals().items()) if name.startswith("draw_") and callable(fn)}


def render(name):
    canvas = Canvas(SIZE)
    DRAWINGS[name](canvas)
    canvas.outline()
    return canvas


# Icons whose meaning is in small separate parts the finish runs together at button size (the three
# dots ran into a bar, the two faces into a smudge, the backpack's flap and pocket into a lump): they
# keep their crisp flat drawing.
KEEP_FLAT = {"more", "users", "backpack"}


def main(argv):
    sheet_path = None
    if "--sheet" in argv:
        index = argv.index("--sheet")
        sheet_path = argv[index + 1]
        argv = argv[:index] + argv[index + 2:]
    names = argv or sorted(DRAWINGS)
    # Finished in the game's pixel style by tools/pixel_kit.py, as the item and skill icons are.
    import io
    from PIL import Image
    from pixel_kit import restyle
    for name in names:
        drawn = Image.open(io.BytesIO(render(name).png()))
        if name in KEEP_FLAT:
            drawn.save(SPRITES / f"ui_{name}.png")
            continue
        restyle(drawn, round_corners=0.3, texture=0.025).render().save(SPRITES / f"ui_{name}.png")
    print(f"wrote {len(names)} UI icons to art/sprites/")
    if sheet_path:
        # Each icon on the HUD's blue button and the battle's red one, at 4×.
        backs = [(64, 140, 230, 255), (220, 70, 70, 255), (240, 232, 214, 255)]
        scale, pad = 4, 6
        cell = SIZE * scale + pad
        width, height = len(names) * cell + pad, len(backs) * cell + pad
        pixels = [[(30, 34, 52, 255)] * width for _ in range(height)]
        for row, back in enumerate(backs):
            for n, name in enumerate(names):
                art = render(name)
                ox, oy = pad + n * cell, pad + row * cell
                for y in range(SIZE * scale):
                    for x in range(SIZE * scale):
                        c = art.px[y // scale][x // scale]
                        pixels[oy + y][ox + x] = c if c and c[3] == 255 else back
        raw = b"".join(b"\x00" + b"".join(bytes(p) for p in row) for row in pixels)
        pathlib.Path(sheet_path).write_bytes(encode_png(width, height, raw))
        print(f"contact sheet: {sheet_path} (order: {', '.join(names)})")


if __name__ == "__main__":
    main(sys.argv[1:])
