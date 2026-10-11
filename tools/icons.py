#!/usr/bin/env python3
"""Vendors the game's UI icons from Iconaut (MIT, https://github.com/iconaut-design/icons).

Each icon lands in Fairyland/Resources/Assets.xcassets/Icons/ as a template SVG, twice:
`icon-<name>` is Iconaut's 24px drawing and `icon-<name>-16` its simplified 16px one, so
small icons stay crisp. The Swift side is `GameIcon` in Fairyland/UI/GameIcon.swift; keep
the names here and there in sync. A few are our own drawings instead (`OWN`, from
art/icons/<name>-24.svg and -16.svg), where Iconaut has no shape that works.

    python3 tools/icons.py                 # download the pinned release from GitHub
    python3 tools/icons.py --source DIR    # use a local clone instead
"""

import argparse
import json
import pathlib
import shutil
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Fairyland/Resources/Assets.xcassets/Icons"
LICENSE_OUT = ROOT / "third_party/iconaut/LICENSE"
COMMIT = "178077725739aa39b321527e4c704d460bb2383f"
RAW = f"https://raw.githubusercontent.com/iconaut-design/icons/{COMMIT}"

# game name → (Iconaut category/name, style)
ICONS = {
    "sword": ("gaming/sword", "solid"),
    "globe": ("navigation/globe", "solid"),
    "sparkles": ("ai/sparkles", "solid"),
    "backpack": ("education/backpack", "solid"),
    "shield": ("security/shield", "solid"),
    "wind": ("weather/wind", "solid"),
    "heart": ("essential/heart", "solid"),
    "heart-plus": ("health/heart-plus", "solid"),
    "more": ("essential/circle-ellipsis", "solid"),
    "close": ("essential/close", "solid"),
    "check": ("essential/check", "solid"),
    "check-circle": ("essential/check-circle", "solid"),
    "badge-check": ("awards/badge-check", "solid"),
    "plus": ("essential/plus", "solid"),
    "user": ("people/user", "solid"),
    "users": ("people/users", "solid"),
    "paw": ("nature/paw", "solid"),
    "book": ("education/book-marked", "solid"),
    "talk": ("communication/message-dots", "solid"),
    "sun": ("weather/sun", "solid"),
    "moon": ("weather/moon-star", "solid"),
    "music": ("media/music", "solid"),
    "music-off": ("media/music-off", "solid"),
    "settings": ("essential/settings", "solid"),
    "volume": ("media/volume", "solid"),
    "chevron-up": ("arrows/chevron-up", "solid"),
    "chevron-down": ("arrows/chevron-down", "solid"),
    "arrow-up": ("arrows/arrow-up", "solid"),
    "arrow-down": ("arrows/arrow-down", "solid"),
    "arrow-left": ("arrows/arrow-left", "solid"),
    "arrow-right": ("arrows/arrow-right", "solid"),
    "play": ("media/play", "solid"),
    "dice": ("gaming/dice-five", "solid"),
    "map": ("navigation/map", "solid"),
    "tap": ("gestures/tap", "solid"),
    "palette": ("essential/palette", "solid"),
    "star": ("weather/star", "solid"),
    "star-outline": ("weather/star", "line"),
    "gift": ("commerce/gift", "solid"),
    "coins": ("commerce/coins", "solid"),
    "egg": ("food/egg", "solid"),
    "edit": ("essential/edit", "solid"),
    "lock": ("essential/lock", "solid"),
    "search": ("essential/search", "solid"),
    "sort": ("arrows/arrows-up-down", "solid"),
    # Items
    "potion": ("gaming/health-potion", "solid"),
    "flask": ("education/flask", "solid"),
    "axe": ("home/axe", "solid"),
    "wand": ("ai/wand", "solid"),
    "diamond": ("nature/diamond", "solid"),
    "gem": ("awards/gem", "solid"),
    "seal-stone": ("awards/gem", "solid"),
    "ring": ("essential/circle-dot", "solid"),
    "clover": ("nature/clover", "solid"),
    "shield-check": ("security/shield-check", "solid"),
    "shield-plus": ("security/shield-plus", "solid"),
    "shield-star": ("security/shield-star", "solid"),
    "shield-heart": ("security/shield-heart", "solid"),
    # Skills
    "hammer": ("home/hammer", "solid"),
    "first-aid": ("health/first-aid", "solid"),
    "tornado": ("weather/tornado", "solid"),
    "mountain": ("nature/mountain", "solid"),
    "leaf": ("nature/leaf", "solid"),
    "droplet": ("weather/droplet", "solid"),
    "pine-tree": ("nature/pine-tree", "solid"),
    "tooth": ("health/tooth", "solid"),
    "bounce": ("arrows/chevron-double-up", "solid"),
    # Elements (the rest are droplet, leaf, mountain, sun and moon above, and flame in OWN)
    "magnet": ("education/magnet", "solid"),
    "circle-dashed": ("essential/circle-dashed", "solid"),
}

# Our own drawings in art/icons/, on Iconaut's 24-unit grid.
OWN_DIR = ROOT / "art/icons"
OWN = [
    # Fire: a flame with three tongues. Iconaut's flame is a teardrop with a small side
    # tongue, which at badge size read as water's droplet.
    "flame",
]


def read(source, path):
    if source:
        return (source / path).read_bytes()
    with urllib.request.urlopen(f"{RAW}/{path}") as response:
        return response.read()


def imageset(name, svg):
    folder = OUT / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    # Template rendering ignores colour; a concrete fill keeps every SVG renderer happy.
    (folder / f"{name}.svg").write_bytes(svg.replace(b"currentColor", b"#000000"))
    contents = {
        "images": [{"idiom": "universal", "filename": f"{name}.svg"}],
        "info": {"author": "xcode", "version": 1},
        "properties": {"preserves-vector-representation": True, "template-rendering-intent": "template"},
    }
    (folder / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--source", type=pathlib.Path, help="local clone of iconaut-design/icons")
    args = parser.parse_args()

    categories = {path.split("/")[0] for path, _ in ICONS.values()}
    # Iconaut's folder layout: icons/<category>/<name>/<size>/<style>.svg
    if args.source and not all((args.source / "icons" / c).is_dir() for c in categories):
        parser.error(f"{args.source} doesn't look like an Iconaut clone")

    if OUT.exists():
        shutil.rmtree(OUT)
    OUT.mkdir(parents=True)
    (OUT / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    for name, (path, style) in ICONS.items():
        imageset(f"icon-{name}", read(args.source, f"icons/{path}/24/{style}.svg"))
        imageset(f"icon-{name}-16", read(args.source, f"icons/{path}/16/{style}.svg"))
    for name in OWN:
        imageset(f"icon-{name}", (OWN_DIR / f"{name}-24.svg").read_bytes())
        imageset(f"icon-{name}-16", (OWN_DIR / f"{name}-16.svg").read_bytes())

    LICENSE_OUT.parent.mkdir(parents=True, exist_ok=True)
    LICENSE_OUT.write_bytes(read(args.source, "LICENSE"))
    print(f"Vendored {len(ICONS)} Iconaut icons and {len(OWN)} of our own into {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
