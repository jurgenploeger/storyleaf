#!/usr/bin/env python3
"""Draws every skill's 32×32 icon in code, in the same style as tools/item_art.py (free).

    python3 tools/skill_art.py                 # all skills → art/sprites/skill_<id>.png
    python3 tools/skill_art.py fire_bolt flash # just these
    python3 tools/skill_art.py --sheet /tmp/skills.png

The icons sit on the coloured tile of the skill's element or kind in menus and the battle bar.
"""

import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from item_art import (  # noqa: E402
    BLUE, GOLD, GREEN, LEATHER, ORANGE, RED, SIZE, SNOW, SPRITES, STEEL, TEAL, VIOLET, WHITE, WOOD,
    Canvas, encode_png, hexc, light_top_left, star_shape,
)

FIRE = [hexc("c0301a"), hexc("ff7a1a"), hexc("ffe060")]
STONE = [hexc("5a4a3a"), hexc("9a8266"), hexc("d0bc98")]
MUD = [hexc("4a3018"), hexc("7a5230"), hexc("b08050")]
JELLY = [hexc("1c6ab0"), hexc("48a8f0"), hexc("c4ecff")]
SHADOW = [hexc("2a1a4a"), hexc("5a3a9a"), hexc("b09aff")]
BONE = [hexc("b8b0a0"), hexc("f0ece0"), WHITE]


def flame(c, cx, cy, r, colors=FIRE):
    dark, mid, light = colors
    c.poly([(cx, cy - r * 1.6), (cx + r * 0.9, cy - r * 0.2), (cx + r, cy + r * 0.5), (cx, cy + r),
            (cx - r, cy + r * 0.5), (cx - r * 0.9, cy - r * 0.2)], dark)
    c.disc(cx, cy + r * 0.2, r * 0.8, mid)
    c.poly([(cx, cy - r * 1.1), (cx + r * 0.5, cy), (cx, cy + r * 0.6), (cx - r * 0.5, cy)], mid)
    c.disc(cx, cy + r * 0.3, r * 0.4, light)


def trail(c, x, y, color, dx=-1, dy=1):
    """A comet tail of shrinking puffs behind a flying spell."""
    for i, r in enumerate((2.6, 1.9, 1.2)):
        c.disc(x + dx * (4 + i * 4), y + dy * (4 + i * 4), r, color)


def swirl(c, cx, cy, color, turns=2.2, r0=1.5, grow=0.16, width=1.1, points=60):
    for i in range(points):
        t = i / points * math.pi * 2 * turns
        r = r0 + i * grow
        c.disc(cx + r * math.cos(t), cy + r * math.sin(t) * 0.8, width, color)


def leaf(c, cx, cy, angle, length=5, colors=GREEN):
    dx, dy = math.cos(angle) * length, math.sin(angle) * length
    nx, ny = -dy * 0.45, dx * 0.45
    c.poly([(cx - dx, cy - dy), (cx + nx, cy + ny), (cx + dx, cy + dy), (cx - nx, cy - ny)], colors[1])
    c.line(cx - dx, cy - dy, cx + dx, cy + dy, colors[0])


def heart(c, cx, cy, r, colors):
    c.disc(cx - r * 0.5, cy - r * 0.2, r * 0.6, colors[1])
    c.disc(cx + r * 0.5, cy - r * 0.2, r * 0.6, colors[1])
    c.poly([(cx - r * 1.08, cy), (cx + r * 1.08, cy), (cx, cy + r * 1.1)], colors[1])
    c.disc(cx - r * 0.6, cy - r * 0.4, r * 0.22, colors[2])


def paw(c, cx, cy, colors):
    # Toes well apart from each other and the pad: closer, the finish rounded them into one lump.
    c.ellipse(cx, cy + 4, 4.4, 3.4, colors[1])
    for (dx, dy) in ((-7, -1.6), (-3, -7.4), (3, -7.4), (7, -1.6)):
        c.disc(cx + dx, cy + dy, 1.8, colors[1])
    c.disc(cx - 1.5, cy + 2, 1.2, colors[2])


def fangs(c, cx, cy, colors, jaw=BONE):
    c.poly([(cx - 9, cy - 3), (cx + 9, cy - 3), (cx + 7, cy + 2), (cx - 7, cy + 2)], colors[1])   # upper jaw
    for dx in (-6, -2, 2, 6):
        c.poly([(dx + cx - 1.8, cy + 1), (dx + cx + 1.8, cy + 1), (dx + cx, cy + 6)], jaw[1])
    c.poly([(cx - 8, cy + 9), (cx + 8, cy + 9), (cx + 6, cy + 13), (cx - 6, cy + 13)], colors[1])   # lower jaw
    for dx in (-4, 0, 4):
        c.poly([(dx + cx - 1.5, cy + 10), (dx + cx + 1.5, cy + 10), (dx + cx, cy + 6)], jaw[1])


# ---------------------------------------------------------------- the skills

def draw_bash(c):
    c.line(7, 26, 18, 13, WOOD[1], width=3)
    c.line(8, 26, 19, 14, WOOD[0])
    c.poly([(15, 5), (25, 13), (20, 19), (10, 11)], STEEL[1])          # hammer head
    c.shade(lambda x, y, col: col == STEEL[1] and x + y > 32, STEEL[0])
    c.line(15, 6, 24, 13, STEEL[2])
    for (x, y) in ((26, 20), (28, 16), (24, 24)):
        c.line(x, y, x + 3, y + 1, GOLD[2], width=2)                    # impact


def draw_first_aid(c):
    c.rect(6, 9, 26, 25, WHITE)
    c.rect(6, 22, 26, 25, hexc("d8dce8"))
    c.rect(14, 11, 18, 23, RED[1])
    c.rect(10, 15, 22, 19, RED[1])
    c.rect(14, 11, 15, 23, RED[2])


def draw_power_strike(c):
    c.line(10, 22, 26, 6, STEEL[1], width=4)
    c.line(11, 21, 25, 7, STEEL[2])
    c.line(6, 18, 13, 25, GOLD[1], width=3)
    c.line(8, 23, 4, 27, LEATHER[1], width=3)
    star_shape(c, 26, 6, 4, WHITE, inner=0.35)


def draw_whirlwind(c):
    swirl(c, 16, 16, hexc("e8f4ff"), turns=2.4, grow=0.2, width=1.3)
    for a in range(3):
        t = a * 2 * math.pi / 3
        x, y = 16 + 11 * math.cos(t), 16 + 9 * math.sin(t)
        c.line(x, y, x + 4 * math.cos(t + 1.9), y + 4 * math.sin(t + 1.9), STEEL[2], width=2)


def draw_fire_bolt(c):
    trail(c, 14, 19, FIRE[1])
    flame(c, 19, 14, 7)


def draw_ember(c):
    flame(c, 16, 17, 6)
    for (x, y) in ((8, 10), (24, 9), (25, 24)):
        c.disc(x, y, 1.2, FIRE[2])


def draw_stone_spike(c):
    for (x, h, w) in ((9, 14, 4), (16, 22, 5), (23, 16, 4)):
        c.poly([(x - w, 28), (x, 28 - h), (x + w, 28)], STONE[1])
        c.shade(lambda px, py, col, x=x: col == STONE[1] and px > x, STONE[0])
    c.rect(3, 27, 29, 29, MUD[1])


def draw_rock_throw(c):
    trail(c, 13, 19, STONE[2])
    c.poly([(14, 9), (22, 7), (27, 13), (25, 21), (17, 23), (13, 17)], STONE[1])
    c.shade(lambda x, y, col: col == STONE[1] and x + y > 38, STONE[0])
    c.line(15, 11, 21, 9, STONE[2])


def draw_mud_shot(c):
    trail(c, 14, 20, MUD[1])
    c.disc(20, 16, 7, MUD[1])
    light_top_left(c, MUD, 20, 16, 7)
    for (x, y) in ((27, 11), (28, 20), (24, 25)):
        c.disc(x, y, 1.4, MUD[1])


def draw_leaf_storm(c):
    swirl(c, 16, 16, hexc("c8f0b0", 200), turns=1.6, grow=0.2, width=0.8)
    for i in range(5):
        t = i * 2 * math.pi / 5
        leaf(c, 16 + 9 * math.cos(t), 16 + 8 * math.sin(t), t + 1.2, 4)


def draw_vine_whip(c):
    for i in range(50):
        t = i / 50
        x, y = 6 + t * 20, 26 - t * 18 + math.sin(t * math.pi * 2.2) * 4
        c.disc(x, y, 1.3, GREEN[1])
    for t in (0.25, 0.55, 0.85):
        leaf(c, 6 + t * 20, 26 - t * 18 + math.sin(t * math.pi * 2.2) * 4 - 3, -0.6, 3)


def draw_blessing(c):
    for i in range(8):
        t = i * math.pi / 4
        c.line(16 + 6 * math.cos(t), 18 + 6 * math.sin(t), 16 + 13 * math.cos(t), 18 + 13 * math.sin(t), GOLD[2], width=2)
    c.disc(16, 18, 5.5, GOLD[1])
    c.disc(15, 17, 2.2, WHITE)
    c.ring(16, 6, 6, 4.4, GOLD[2], ry_scale=0.4)                         # halo


def draw_flash(c):
    star_shape(c, 16, 16, 13, hexc("fff6b0"), inner=0.3)
    star_shape(c, 16, 16, 7, WHITE, inner=0.4, rotation=-math.pi / 2 + math.pi / 5)
    c.disc(16, 16, 3, WHITE)


def draw_wild_call(c):
    paw(c, 13, 17, LEATHER)
    for r in (5, 8):
        for i in range(10):
            t = -0.9 + i * 0.2
            c.set(20 + r * math.cos(t), 16 + r * math.sin(t), WHITE)


def draw_roar(c):
    c.ellipse(12, 16, 8, 9, ORANGE[1])                                  # a lion's head
    c.disc(12, 16, 5.5, hexc("f4c890"))
    c.ellipse(13, 19, 3, 2.2, RED[0])                                   # open mouth
    c.set(10, 14, hexc("231834")); c.set(14, 14, hexc("231834"))
    for r in (4, 7, 10):
        for i in range(9):
            t = -0.8 + i * 0.2
            c.set(19 + r * math.cos(t), 17 + r * math.sin(t), WHITE)


def draw_mend_beast(c):
    heart(c, 16, 17, 10, [hexc("a01c4a"), hexc("f04a7a"), hexc("ffb0c8")])
    paw(c, 16, 17, [BONE[0], WHITE, BONE[0]])


def draw_nibble(c):
    c.disc(16, 16, 11, hexc("f4e0b0"))                                  # a biscuit with a bite out
    for (x, y) in ((26, 8), (28, 14), (22, 4)):
        c.disc(x, y, 4.5, None)
    for (x, y) in ((11, 13), (16, 20), (19, 12), (12, 20)):
        c.disc(x, y, 1, hexc("b07a3a"))


def draw_shadow_bite(c):
    c.disc(16, 16, 12, hexc("2a1a4a", 160))
    fangs(c, 16, 11, SHADOW)


def draw_jelly_splash(c):
    c.poly([(8, 24), (8, 16), (12, 9), (20, 9), (24, 16), (24, 24)], JELLY[1])
    c.shade(lambda x, y, col: col == JELLY[1] and x > 19, JELLY[0])
    c.disc(12, 13, 2, JELLY[2])
    c.set(13, 18, hexc("231834")); c.set(19, 18, hexc("231834"))
    for (x, y) in ((5, 27), (27, 27), (28, 21), (4, 21)):
        c.disc(x, y, 1.5, JELLY[1])


def draw_bubble(c):
    # Filled with the pale of the water, not rings alone (finished, thin rings read as a chain).
    for (x, y, r) in ((13, 18, 7), (23, 10, 4), (23, 22, 3), (7, 8, 2.5)):
        c.disc(x, y, r, JELLY[2])
        c.ring(x, y, r, r - 1.4, JELLY[1])
        c.disc(x - r * 0.4, y - r * 0.4, max(1, r * 0.22), WHITE)


def draw_frost_breath(c):
    for i in range(6):
        t = i * math.pi / 3
        x, y = 16 + 12 * math.cos(t), 16 + 12 * math.sin(t)
        c.line(16, 16, x, y, SNOW[2], width=2)
        for k in (0.55, 0.8):
            bx, by = 16 + 12 * k * math.cos(t), 16 + 12 * k * math.sin(t)
            for s in (-1, 1):
                c.line(bx, by, bx + 3 * math.cos(t + s * 0.9), by + 3 * math.sin(t + s * 0.9), SNOW[1])
    c.disc(16, 16, 2.5, WHITE)


def draw_pine_needles(c):
    for (x0, y0, x1, y1) in ((6, 24, 22, 8), (10, 27, 26, 11), (4, 18, 18, 5)):
        c.line(x0, y0, x1, y1, GREEN[0], width=2)
        c.line(x0, y0 - 1, x1, y1 - 1, GREEN[2])
        c.poly([(x1, y1 - 2), (x1 + 3, y1 - 3), (x1 + 2, y1)], GREEN[2])


def draw_web_shot(c):
    for i in range(8):
        t = i * math.pi / 4
        c.line(16, 16, 16 + 13 * math.cos(t), 16 + 13 * math.sin(t), hexc("eeeaf8"))
    for r in (4, 8, 12):
        pts = [(16 + r * math.cos(i * math.pi / 4), 16 + r * math.sin(i * math.pi / 4)) for i in range(9)]
        for (a, b) in zip(pts, pts[1:]):
            c.line(a[0], a[1], b[0], b[1], hexc("eeeaf8"))
    c.disc(16, 16, 2.4, SHADOW[1])


def draw_bounce(c):
    c.ellipse(16, 25, 8, 2, hexc("231834", 90))                          # shadow
    c.disc(16, 13, 7.5, hexc("ff8ab8"))
    light_top_left(c, [hexc("c04a7a"), hexc("ff8ab8"), hexc("ffd0e4")], 16, 13, 7.5)
    for (x, y) in ((6, 12), (26, 12), (8, 6), (24, 6)):
        c.disc(x, y, 1, WHITE)


def draw_golden_spin(c):
    swirl(c, 16, 16, GOLD[2], turns=1.3, r0=8, grow=0.08, width=0.8, points=40)
    c.ellipse(16, 16, 6, 8, GOLD[1])
    c.ellipse(16, 16, 3.5, 5.5, GOLD[0])
    c.line(16, 11, 16, 21, GOLD[2])
    star_shape(c, 25, 7, 3, WHITE, inner=0.35)


def draw_gust(c):
    for (y, x0, x1, curl) in ((10, 5, 22, 1), (17, 3, 26, -1), (24, 7, 20, 1)):
        c.line(x0, y, x1, y, hexc("e8f4ff"), width=2)
        for i in range(12):
            t = i / 12 * math.pi * 1.4
            c.set(x1 + 3 * math.sin(t), y - curl * (3 - 3 * math.cos(t)), hexc("e8f4ff"))


def draw_recovery(c):
    heart(c, 16, 18, 9, GREEN)
    c.rect(14, 11, 18, 23, WHITE)                                       # a white cross on the heart
    c.rect(10, 15, 22, 19, WHITE)
    for x, y in ((5, 7), (27, 9), (26, 26)):
        c.rect(x - 1, y, x + 2, y + 1, GREEN[2])
        c.rect(x, y - 1, x + 1, y + 2, GREEN[2])


def draw_revive(c):
    c.ring(16, 6, 6, 4.4, GOLD[2], ry_scale=0.4)                        # halo
    for side in (-1, 1):                                                 # a pair of white wings
        c.poly([(16, 14), (16 + side * 13, 9), (16 + side * 12, 14), (16 + side * 14, 17),
                (16 + side * 10, 21), (16 + side * 11, 24), (16, 22)], WHITE)
        c.line(16, 16, 16 + side * 11, 12, hexc("c8d4f0"))
        c.line(16, 19, 16 + side * 10, 18, hexc("c8d4f0"))
    c.disc(16, 18, 3.4, GOLD[1])
    c.disc(15, 17, 1.4, GOLD[2])


def draw_bless(c):
    c.poly([(6, 7), (26, 7), (26, 16), (16, 28), (6, 16)], BLUE[1])     # a shield
    c.poly([(6, 7), (16, 7), (16, 28), (6, 16)], BLUE[2])
    c.poly([(9, 10), (23, 10), (23, 16), (16, 24), (9, 16)], BLUE[0])
    star_shape(c, 16, 15.5, 6, GOLD[1])
    c.disc(15, 14, 1.6, GOLD[2])


def draw_protection(c):
    c.poly([(6, 5), (26, 5), (26, 15), (16, 28), (6, 15)], STEEL[1])     # a steel shield
    c.poly([(6, 5), (16, 5), (16, 28), (6, 15)], STEEL[2])
    c.poly([(9, 8), (23, 8), (23, 15), (16, 24), (9, 15)], STEEL[0])
    c.line(9, 8, 23, 8, GOLD[1], width=2)                                # a gold rim along the top
    c.disc(16, 15, 4, GOLD[1])                                           # and a gold boss
    c.disc(15, 14, 1.6, GOLD[2])


def draw_holy_glow(c):
    for i in range(12):                                                  # rays of light round...
        t = i * math.pi / 6
        reach = 14 if i % 2 == 0 else 10
        c.line(16 + 7 * math.cos(t), 16 + 7 * math.sin(t), 16 + reach * math.cos(t), 16 + reach * math.sin(t),
               hexc("ffe0f8") if i % 2 else GOLD[2], width=2)
    c.disc(16, 16, 7, hexc("f070c0"))                                    # ...an orb of rosy magic
    c.disc(16, 16, 5, hexc("ffb0e0"))
    c.disc(14.5, 14.5, 2, WHITE)


def draw_guardianship(c):
    c.ring(16, 24, 14, 11.5, SNOW[1])                                    # a dome of light...
    c.ring(16, 24, 11.5, 10.5, SNOW[2])
    for y in range(25, 32):                                              # (its top half)
        for x in range(32):
            c.px[y][x] = None
    c.rect(2, 24, 30, 26, SNOW[0])                                       # ...over the ground
    c.poly([(11, 11), (21, 11), (21, 17), (16, 23), (11, 17)], BLUE[1])  # and a shield inside
    c.poly([(11, 11), (16, 11), (16, 23), (11, 17)], BLUE[2])
    star_shape(c, 16, 16, 3.4, GOLD[1])


def draw_animal_training(c):
    paw(c, 12, 18, LEATHER)
    c.poly([(24, 3), (30, 10), (26.5, 10), (26.5, 19), (21.5, 19), (21.5, 10), (18, 10)], GOLD[0])   # an arrow up
    c.poly([(24, 3), (24, 19), (21.5, 19), (21.5, 10), (18, 10)], GOLD[1])
    for y in (22, 25, 28):                                               # speed lines
        c.line(20, y, 28, y, WHITE)


def draw_boost(c):
    # Its halves in the orange and its shade: a pale half was the commonest colour, and the finish
    # ramped the whole arrow from it, beige.
    c.poly([(16, 2), (28, 14), (21.5, 14), (21.5, 28), (10.5, 28), (10.5, 14), (4, 14)], ORANGE[0])  # a big arrow up
    c.poly([(16, 2), (16, 28), (10.5, 28), (10.5, 14), (4, 14)], ORANGE[1])
    c.line(16, 6, 16, 26, hexc("fff0c0"))
    for (x, y) in ((5, 22), (27, 21), (26, 26)):
        star_shape(c, x, y, 2.6, WHITE, inner=0.35)                     # sparks


def draw_berserk(c):
    flame(c, 16, 18, 10, colors=[RED[0], RED[1], ORANGE[2]])             # a blaze of rage...
    c.line(10, 17, 14, 19, hexc("231834"), width=2)                      # ...with angry eyes
    c.line(22, 17, 18, 19, hexc("231834"), width=2)
    c.disc(13, 21, 1.2, WHITE)
    c.disc(19, 21, 1.2, WHITE)

def draw_bridge_of_light(c):
    for r, color in ((14, GOLD[1]), (11.5, WHITE), (9, hexc("9ccaff"))):  # a rainbow arch of light
        c.ring(16, 26, r, r - 2.2, color)
    for y in range(26, 32):                                              # only the top half of the rings
        for x in range(32):
            c.px[y][x] = None
    c.rect(4, 25, 9, 27, GOLD[0])
    c.rect(23, 25, 28, 27, GOLD[0])
    c.disc(16, 10, 2.2, WHITE)


POISON = [hexc("2e6a1e"), hexc("6ab83a"), hexc("b8f070")]
GUMS = [hexc("3a1a2a"), hexc("7a2a4a"), hexc("b05a7a")]
INK = hexc("1e2a14")


def draw_curse(c):
    swirl(c, 16, 17, SHADOW[1], turns=1.8, r0=2, grow=0.18, width=1.4)   # dark magic behind
    c.line(4, 4, 7, 7, LEATHER[1], width=2)                              # a sword, snapped in two
    c.line(4, 10, 10, 4, GOLD[1], width=2)
    c.line(9, 9, 14, 14, STEEL[1], width=3)
    c.line(9, 8, 14, 13, STEEL[2])
    c.line(18, 17, 24, 23, STEEL[1], width=3)
    c.line(18, 16, 24, 22, STEEL[2])
    c.poly([(23, 25), (27, 27), (25, 23)], STEEL[1])
    for (x, y) in ((15, 20), (21, 11), (8, 21)):
        c.disc(x, y, 1.3, SHADOW[2])                                     # wisps


def draw_poison(c):
    c.poly([(16, 3), (23, 13), (25, 19), (22, 26), (16, 28), (10, 26), (7, 19), (9, 13)], POISON[1])   # a drop of venom
    c.shade(lambda x, y, col: col == POISON[1] and x > 18 and y > 15, POISON[0])
    c.disc(12, 15, 1.8, POISON[2])
    c.disc(13, 19, 1.5, INK)                                             # a sickly face
    c.disc(19, 19, 1.5, INK)
    c.line(13, 24, 19, 24, INK)
    for (x, y) in ((26, 6), (28, 11), (5, 7)):
        c.ring(x, y, 2.2, 1.1, POISON[2])                                # bubbles


def draw_venom_bite(c):
    c.disc(16, 16, 12, hexc("1e3a14", 160))
    fangs(c, 16, 8, GUMS)
    for (x, y) in ((10, 25), (16, 28), (22, 25)):
        c.poly([(x - 1.4, y - 3), (x + 1.4, y - 3), (x, y + 1.5)], POISON[1])   # venom dripping
        c.set(x - 0.5, y - 2, POISON[2])


def draw_poison_mist(c):
    for (x, y, r) in ((10, 19, 6), (17, 14, 7.5), (23, 19, 6), (16, 22, 6)):
        c.disc(x, y, r, POISON[1])                                       # a cloud
    c.shade(lambda x, y, col: col == POISON[1] and y > 21, POISON[0])
    for (x, y, r) in ((11, 17, 2.6), (17, 11, 3)):
        c.disc(x, y, r, POISON[2])
    for (x, y) in ((5, 8), (26, 7), (21, 3)):
        c.ring(x, y, 2.2, 1.1, VIOLET[2])                                # bubbles


def draw_evil_eye(c):
    c.poly([(3, 16), (9, 10), (16, 8), (23, 10), (29, 16), (23, 22), (16, 24), (9, 22)], hexc("efe8ff"))   # the eye
    c.disc(16, 16, 6, SHADOW[1])                                         # a violet iris
    c.disc(16, 16, 3.2, SHADOW[0])
    c.rect(15.5, 12, 16.5, 20, hexc("ff5a7a"))                           # a red slit
    c.disc(13.5, 13.5, 1.2, WHITE)
    for (x0, y0, x1, y1) in ((16, 5, 16, 2), (8, 7, 6, 4), (24, 7, 26, 4), (8, 25, 6, 28), (24, 25, 26, 28)):
        c.line(x0, y0, x1, y1, SHADOW[2])                                # a dark glare


SKILLS = {name[5:]: fn for name, fn in dict(globals()).items() if name.startswith("draw_")}


def render(skill_id):
    canvas = Canvas()
    SKILLS[skill_id](canvas)
    canvas.outline()
    return canvas


def main(argv):
    sheet_path = None
    if "--sheet" in argv:
        index = argv.index("--sheet")
        sheet_path = argv[index + 1]
        argv = argv[:index] + argv[index + 2:]
    ids = argv or sorted(SKILLS)
    # Each design is finished in the game's pixel style (docs/pixel-style.md) by tools/pixel_kit.py, as
    # the item icons are: lit, ramped, textured and outlined afresh, its glows kept as drawn.
    import io
    from PIL import Image
    from pixel_kit import restyle
    for skill_id in ids:
        drawn = Image.open(io.BytesIO(render(skill_id).png()))
        restyle(drawn, round_corners=0.3).render().save(SPRITES / f"skill_{skill_id}.png")
    print(f"wrote {len(ids)} skill icons to art/sprites/")
    if sheet_path:
        columns, scale, pad = 7, 4, 6
        rows = math.ceil(len(ids) / columns)
        cell = SIZE * scale + pad
        width, height = columns * cell + pad, rows * cell + pad
        tiles = [(120, 90, 200), (220, 110, 80), (80, 170, 110), (70, 130, 220)]
        pixels = [[(40, 36, 60, 255)] * width for _ in range(height)]
        for n, skill_id in enumerate(ids):
            art = render(skill_id)
            ox, oy = pad + (n % columns) * cell, pad + (n // columns) * cell
            tint = tiles[n % len(tiles)] + (255,)
            for y in range(SIZE * scale):
                for x in range(SIZE * scale):
                    col = art.px[y // scale][x // scale]
                    pixels[oy + y][ox + x] = col if col and col[3] == 255 else tint
        raw = b"".join(b"\x00" + b"".join(bytes(p) for p in row) for row in pixels)
        pathlib.Path(sheet_path).write_bytes(encode_png(width, height, raw))
        print(f"contact sheet: {sheet_path} (order: {', '.join(ids)})")


if __name__ == "__main__":
    main(sys.argv[1:])
