#!/usr/bin/env python3
"""Weapons from Retro Diffusion: a picked 64-pixel RD drawing (art-variants/) made into the game's
two sprites, by the same rules as tools/item_art.py's drawn weapons:

- art/sprites/item_<id>.png, 32 × 32: the icon in bags, shops and the Character tab;
- art/sprites/held_<id>_side.png and _front.png: the weapon in hand walking left or right, and held up
  nearly upright facing you or away (GearArt.posed, item_art.posed), one of its pixels
  to one of the hero's.

Both are shrunk from the RD drawing with its own outline taken off, each pixel the colour that
covers most of it (a thin blade wins over the air beside it), then outlined afresh in the items'
outline colour, so an RD weapon sits among the drawn ones. The game holds a weapon by the solid
pixel nearest the bottom-left corner and points it up and away (GearArt.held), so a drawing must lie
diagonally, grip bottom-left; one that doesn't can be turned (`turn`, degrees anticlockwise) before
it's shrunk. A magic weapon's glow (items.json `glow`) goes round its tip, found here.

    python3 tools/weapon_art.py                       # every weapon in PICKED
    python3 tools/weapon_art.py --out DIR bronze_sword=art-variants/rdw_bronze_sword/x_1.png
                                                       # a candidate, written to DIR instead
Check in hand with `python3 tools/gear_preview.py --weapons out.png <id> [folder]`.
"""

import json
import math
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
import item_art as ia   # noqa: E402

ROOT = ia.ROOT
VARIANTS = ROOT / "art-variants"

ICON_INNER, HELD_INNER = 27, 20   # as big as the drawn weapons (tools/item_art.py), outline aside

# item id → (the picked RD drawing under art-variants/, degrees to turn it anticlockwise).
PICKED = {
    "bronze_sword": ("rdw_bronze_sword/20261022-175549_2.png", 0),
    "dragon_god_sword": ("rdw_dragon_god_sword/20261022-175616_1.png", 0),
    "thunder_god_axe": ("rdw_thunder_god_axe/20261022-175843_1.png", 0),
    "oak_staff": ("rdw_oak_staff/20261022-175925_0.png", 0),
    "starfall_staff": ("rdw_starfall_staff/20261022-180009_1.png", 0),
    "novice_bronze_sword": ("rdw_novice_bronze_sword/20261022-183950_0.png", 0),
    "bronze_broadsword": ("rdw_bronze_broadsword/20261022-184017_2.png", 0),
    "bronze_longsword": ("rdw_bronze_longsword/20261022-184051_1.png", 0),
    "copper_sword": ("rdw_copper_sword/20261022-184129_1.png", 0),
    "iron_longsword": ("rdw_iron_longsword/20261022-184227_2.png", 0),
    "silver_inlaid_longsword": ("rdw_silver_inlaid_longsword/20261022-184254_0.png", 0),
    "silver_sword": ("rdw_silver_sword/20261022-184335_0.png", 0),
    "blue_frost_sword": ("rdw_blue_frost_sword/20261022-184402_1.png", 0),
    "tempered_steel_sword": ("rdw_tempered_steel_sword/20261022-184441_0.png", 0),
    "golden_sword": ("rdw_golden_sword/20261022-184614_2.png", 0),
    "silver_steel_sword": ("rdw_silver_steel_sword/20261022-184647_1.png", 0),
    "serpent_sword": ("rdw_serpent_sword/20261022-184707_0.png", 0),
    "alloy_shortsword": ("rdw_alloy_shortsword/20261022-184743_1.png", 0),
    "platinum_longsword": ("rdw_platinum_longsword/20261022-184823_0.png", 0),
    "ironcleaver_sword": ("rdw_ironcleaver_sword/20261022-184853_1.png", 0),
    "tungsten_dragonslayer": ("rdw_tungsten_dragonslayer/20261022-184922_0.png", 0),
    "aurora_blade": ("rdw_aurora_blade/20261022-184956_1.png", 0),
    "phantom_blade": ("rdw_phantom_blade/20261022-185111_1.png", 0),
    "sky_splitter": ("rdw_sky_splitter/20261022-185203_2.png", 0),
    "moonlight_sword": ("rdw_moonlight_sword/20261022-185254_0.png", 0),
    "novice_axe": ("rdw_novice_axe/20261022-185346_0.png", 0),
    "small_hatchet": ("rdw_small_hatchet/20261022-175707_2.png", -45),
    "wood_axe": ("rdw_wood_axe/20261022-185500_2.png", 180),
    "hand_axe": ("rdw_hand_axe/20261022-185551_0.png", 0),
    "copper_plate_axe": ("rdw_copper_plate_axe/20261022-185618_1.png", 0),
    "light_war_axe": ("rdw_light_war_axe/20261022-185654_2.png", 0),
    "windchaser_axe": ("rdw_windchaser_axe/20261022-185728_2.png", 0),
    "iron_bead_axe": ("rdw_iron_bead_axe/20261022-185748_2.png", 0),
    "curved_war_axe": ("rdw_curved_war_axe/20261022-185838_1.png", 0),
    "steel_axe": ("rdw_steel_axe/20261022-185916_0.png", -45),
    "twin_blade_axe": ("rdw_twin_blade_axe/20261022-190006_2.png", 0),
    "long_war_axe": ("rdw_long_war_axe/20261022-190046_1.png", 0),
    "grey_dragon_axe": ("rdw_grey_dragon_axe/20261022-190123_1.png", 0),
    "overlord_axe": ("rdw_overlord_axe/20261022-190219_1.png", 0),
    "alloy_twin_war_axe": ("rdw_alloy_twin_war_axe/20261022-190402_1.png", 0),
    "titanium_dwarf_axe": ("rdw_titanium_dwarf_axe/20261022-190432_1.png", 0),
    "tungsten_skybreaker": ("rdw_tungsten_skybreaker/20261022-190550_0.png", 0),
    "aurora_axe": ("rdw_aurora_axe/20261022-190631_0.png", 0),
    "phantom_axe": ("rdw_phantom_axe/20261022-190708_0.png", 0),
    "luna_axe": ("rdw_luna_axe/20261022-190811_1.png", 0),
    "dragon_god_axe": ("rdw_dragon_god_axe/20261022-190838_1.png", 0),
    "wooden_sword": ("rdw_wooden_sword/20261022-190859_1.png", 0),
    "iron_axe": ("rdw_iron_axe/20261022-190920_2.png", 0),
    "steel_sword": ("rdw_steel_sword/20261022-191227_2.png", 0),
    "battle_axe": ("rdw_battle_axe/20261022-191321_2.png", 0),
    "elder_staff": ("rdw_elder_staff/20261022-191357_1.png", 0),
    "star_wand": ("rdw_star_wand/20261022-191419_0.png", 0),
    "wild_horn": ("rdw_wild_horn/20261022-191545_2.png", 0),
    "bamboo_staff": ("rdw_bamboo_staff/20261022-191645_0.png", 0),
    "rattan_staff": ("rdw_rattan_staff/20261022-191712_1.png", 0),
    "heavy_rattan_staff": ("rdw_heavy_rattan_staff/20261022-191732_0.png", 0),
    "lightwood_staff": ("rdw_lightwood_staff/20261022-192004_1.png", 0),
    "brownwood_staff": ("rdw_brownwood_staff/20261022-192031_0.png", 0),
    "blossom_staff": ("rdw_blossom_staff/20261022-192107_0.png", -45),
    "teak_staff": ("rdw_teak_staff/20261022-192200_0.png", 0),
    "heavywood_staff": ("rdw_heavywood_staff/20261022-192245_1.png", 0),
    "red_cypress_staff": ("rdw_red_cypress_staff/20261022-192405_0.png", 0),
    "blood_cypress_staff": ("rdw_blood_cypress_staff/20261022-192440_2.png", 0),
    "yew_staff": ("rdw_yew_staff/20261022-192507_0.png", 0),
    "purple_star_staff": ("rdw_purple_star_staff/20261022-192559_1.png", 0),
    "armorbreaker_staff": ("rdw_armorbreaker_staff/20261022-192639_0.png", 0),
    "ironcrusher_staff": ("rdw_ironcrusher_staff/20261022-192708_2.png", 0),
    "red_cloud_staff": ("rdw_red_cloud_staff/20261022-192759_0.png", 0),
    "titanium_sceptre": ("rdw_titanium_sceptre/20261022-192837_1.png", 0),
    "emperor_sceptre": ("rdw_emperor_sceptre/20261022-192939_2.png", 0),
    "aurora_staff": ("rdw_aurora_staff/20261022-193021_2.png", 0),
    "sky_ending_staff": ("rdw_sky_ending_staff/20261022-193113_2.png", 0),
    "luna_staff": ("rdw_luna_staff/20261022-193227_0.png", 0),
    "starfall_blade": ("rdw_starfall_blade/20261022-193407_1.png", 0),
    "starfall_axe": ("rdw_starfall_axe/20261022-193436_0.png", 0),
    "goldleaf_blade": ("rdw_goldleaf_blade/20261022-193514_0.png", 0),
    "goldleaf_axe": ("rdw_goldleaf_axe/20261022-193544_1.png", 0),
    "goldleaf_staff": ("rdw_goldleaf_staff/20261022-193634_2.png", 0),
    "crystal_wand": ("rdw_crystal_wand/20261022-194825_2.png", 0),
    "ghost_staff": ("rdw_ghost_staff/20261022-195050_1.png", 0),
    "dragon_god_staff": ("rdw_dragon_god_staff/20261022-195123_1.png", 0),
}


def load(path, turn=0):
    """The RD drawing as a Canvas, cropped to the weapon, its own dark outline taken off."""
    from PIL import Image
    img = Image.open(path).convert("RGBA")
    if turn:
        img = img.rotate(turn, resample=Image.NEAREST, expand=True)
    box = img.getbbox()
    img = img.crop(box)
    w, h = img.size
    side = max(w, h)
    c = ia.Canvas(side)
    for y in range(h):
        for x in range(w):
            r, g, b, a = img.getpixel((x, y))
            if a >= 128:
                c.px[y + (side - h)][x] = (r, g, b, 255)   # squared up, along the bottom and left
    # Its outline, if it drew one (most of its edge dark): the dark pixels next to the air, peeled
    # once. Without one, a dark grip at the edge is the weapon's own.
    edge = [(x, y) for y in range(side) for x in range(side)
            if c.px[y][x] and any(c.get(x + dx, y + dy) is None for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
    dark = [(x, y) for x, y in edge if max(c.px[y][x][:3]) < 80]
    if len(dark) > 0.7 * len(edge):
        for x, y in dark:
            c.px[y][x] = None
    return c


def shrink(src, size, inner):
    """`src` fitted into an `inner`-pixel square of a `size` canvas, along its bottom and across its
    middle, as big as the drawn weapons are (their median: 27 of 32 on the icon, 20 of 24 held, before
    the outline), with room above for a glow: each pixel the colour covering most of it, kept if the
    weapon covers enough of it."""
    out = ia.Canvas(size)
    left, top = (size - inner) // 2, size - 1 - inner
    k = src.size / inner
    for y in range(inner):
        for x in range(inner):
            cover = {}
            for sy in range(int(y * k), min(src.size, int(math.ceil((y + 1) * k)))):
                for sx in range(int(x * k), min(src.size, int(math.ceil((x + 1) * k)))):
                    share = (min(sx + 1, (x + 1) * k) - max(sx, x * k)) * (min(sy + 1, (y + 1) * k) - max(sy, y * k))
                    colour = src.px[sy][sx]
                    cover[colour] = cover.get(colour, 0) + share
            air = cover.pop(None, 0)
            if cover:
                colour, _ = max(cover.items(), key=lambda kv: kv[1])
                if sum(cover.values()) >= air * 0.6:
                    out.px[y + top][x + left] = colour
    out.outline()
    return out


def tip(c):
    """Where a magic weapon's glow goes: its solid pixel nearest the top-right corner, a pixel and a
    half in from it (items.json `glowAt`, in the icon's pixels)."""
    best = min(((x, y) for y in range(c.size) for x in range(c.size) if c.px[y][x] and c.px[y][x] != ia.OUTLINE),
               key=lambda p: (c.size - p[0]) + p[1])
    return [round((best[0] - 1.5) * 2) / 2, round((best[1] + 1.5) * 2) / 2]


def make(item_id, path, turn=0, out=None):
    """Writes item_<id>.png and held_<id>_side/_front.png (to art/sprites/, or `out`); returns the glow
    spot."""
    items = {i["id"]: i for i in json.loads((ROOT / "content" / "items.json").read_text())["items"]}
    src = load(path, turn)
    icon = shrink(src, ia.SIZE, ICON_INNER)
    k = src.size / HELD_INNER        # its pixels to one of the hero's: as long held as a drawn one
    side, front = ia.posed(src, k), ia.posed(src, k, ia.FRONT_TURN)
    spot = None
    if items[item_id].get("glow"):
        spot = tip(icon)
        ia.halo(icon, spot[0], spot[1], 10, ia.hexc(items[item_id]["glow"].lstrip("#")))
    folder = pathlib.Path(out) if out else ia.SPRITES
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f"item_{item_id}.png").write_bytes(icon.png())
    (folder / f"held_{item_id}_side.png").write_bytes(side.png())
    (folder / f"held_{item_id}_front.png").write_bytes(front.png())
    return spot


def main(argv):
    out = None
    if "--out" in argv:
        i = argv.index("--out")
        out, argv = argv[i + 1], argv[:i] + argv[i + 2:]
    picks = {a.split("=")[0]: (a.split("=")[1], 0) for a in argv} if argv else {k: (VARIANTS / v[0], v[1]) for k, v in PICKED.items()}
    for item_id, (path, turn) in picks.items():
        spot = make(item_id, path, turn, out)
        print(f"{item_id}: from {path}" + (f", glowAt {spot}" if spot else ""))


if __name__ == "__main__":
    main(sys.argv[1:])
