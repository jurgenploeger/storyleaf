#!/usr/bin/env python3
"""Previews worn armour on the hero: the same algorithm as Fairyland/Art/GearOverlay.swift (chain
links, open vests, pauldrons, robe hems, capes, helmets and hoods, gloves, boots and necklaces), on
the same paper-doll layers the game stacks (tools/hero_layers.py), to tune it without a Mac.

    python3 tools/gear_preview.py /tmp/gear.png      # every armour in items.json on every race
    python3 tools/gear_preview.py --capes /tmp/capes.png   # every status cape, over some armours
    python3 tools/gear_preview.py --trinkets /tmp/t.png    # gloves, boots and necklaces on every body
    python3 tools/gear_preview.py --hats /tmp/h.png        # every festive hat on every body

Needs pillow + numpy.
"""
import colorsys
import math
import numpy as np

FRAME = 48
DIRS = ['up', 'right', 'down', 'left']


def hsv(c):
    return colorsys.rgb_to_hsv(*c)


def outfit_mask(base):
    """Outfit pixels on the original sheet: green (hue 85-170), saturated."""
    h, w = base.shape[:2]
    m = np.zeros((h, w), bool)
    for y in range(h):
        for x in range(w):
            r, g, b, a = base[y, x]
            if a < 0.5:
                continue
            hh, s, v = hsv((r, g, b))
            m[y, x] = 85 <= hh * 360 <= 170 and s >= 0.3
    return m


def shade(c, k):
    return np.clip(np.array(c[:3]) * k, 0, 1)


def mix(c, d, t):
    return np.clip(np.array(c[:3]) * (1 - t) + np.array(d[:3]) * t, 0, 1)


def hexc(s):
    v = int(s.lstrip('#'), 16)
    return np.array([(v >> 16) & 255, (v >> 8) & 255, v & 255]) / 255


def fur(x, y):
    """Snowy fur: white with grey flecks."""
    return np.array([0.78, 0.82, 0.88]) if (x * 7 + y * 3) % 5 == 0 else np.array([0.97, 0.98, 1.0])


def is_mark(p):
    """A helmet or hood pixel (hero_layers.py draws them in magenta)."""
    if p[3] < 0.5:
        return False
    hh, s, _ = hsv(tuple(p[:3]))
    return abs(hh * 360 - 300) < 12 and s > 0.3


def detail(f, b, m, a, facing, pattern, wear, mid, acc, box):
    """The finer work on stronger armour (items.json `pattern`), drawn over the cut."""
    y0, y1, x0, x1, yb = box
    dark, light = shade(mid, 0.55), mix(mid, (1, 1, 1), 0.45)
    cells = list(zip(*np.nonzero(m)))

    def edge(y, x):
        return any(not (0 <= y + dy < FRAME and 0 <= x + dx < FRAME) or not m[y + dy, x + dx]
                   for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)))

    def put(x, y, c):
        if 0 <= x < FRAME and 0 <= y < FRAME:
            f[y, x, :3] = c
            f[y, x, 3] = 1

    def metal_boots(tint):
        # Brown boots turn to armoured boots, keeping their shading.
        for y in range(max(0, yb - 5), yb + 1):
            for x in range(FRAME):
                if not a[y, x]:
                    continue
                hh, s, v = hsv(tuple(b[y, x, :3]))
                if 0.02 <= hh <= 0.12 and s > 0.35 and v < 0.75:
                    f[y, x, :3] = np.clip(np.array(tint) * (0.55 + v * 0.9), 0, 1)

    if pattern == 'engraved':
        # Overlapping plates (a dark seam every few rows, a rivet at each end) and a bright shine.
        for y, x in cells:
            if edge(y, x):
                continue
            if y > y0 + 3 and (y - y0) % 4 == 3:
                f[y, x, :3] = dark
            elif facing in ('down', 'up') and x == x0 + 2:
                f[y, x, :3] = light
        for y in range(y0 + 7, y1, 4):
            for x in (x0 + 1, x1 - 1):
                if m[y, x]:
                    f[y, x, :3] = light
        metal_boots((0.62, 0.66, 0.74))
    elif pattern == 'scales':
        # Dragon scales: staggered rows of little arches, gold along the collar and hem.
        for y, x in cells:
            if edge(y, x):
                continue
            row = (y - y0) // 2
            sx = (x + 2 * (row % 2)) % 4
            if sx == 0:
                f[y, x, :3] = dark
            elif (y - y0) % 2 == 0 and sx == 2:
                f[y, x, :3] = light
        bottom = {}
        for y, x in cells:
            bottom[x] = max(bottom.get(x, 0), y)
        for x, y in bottom.items():
            f[y, x, :3] = acc
        for y, x in cells:
            if y == y0:
                f[y, x, :3] = acc
        metal_boots((0.55, 0.16, 0.14))
        # Horns on the helmet.
        marks = [(y, x) for y in range(FRAME) for x in range(FRAME) if is_mark(b[y, x])]
        if marks:
            hy = min(y for y, _ in marks)
            row = [x for y, x in marks if y == hy + 2] or [x for _, x in marks]
            hl, hr = min(row), max(row)
            ivory, tip = np.array([0.96, 0.91, 0.78]), np.array([0.72, 0.64, 0.5])
            horn = []
            for side, x in ((-1, hl), (1, hr)):
                pts = [(x + side, hy + 2, ivory), (x + side, hy + 1, ivory), (x + 2 * side, hy, ivory), (x + 2 * side, hy - 1, tip)]
                for px, py, c in pts:
                    put(px, py, c)
                    horn.append((py, px))
            for py, px in horn:
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    yy, xx = py + dy, px + dx
                    if 0 <= yy < FRAME and 0 <= xx < FRAME and f[yy, xx, 3] < 0.5:
                        f[yy, xx, :3] = (0.16, 0.12, 0.18)
                        f[yy, xx, 3] = 1
    elif pattern == 'fur':
        # White fur round the hood's opening: the hood next to the face (and the cape's hem, drawn
        # with the cape). Its dark pixels made a white wedge down the side, like a wing.
        def bare(yy, xx):
            if not (0 <= yy < FRAME and 0 <= xx < FRAME) or b[yy, xx, 3] < 0.5:
                return False
            hh, ss, vv = hsv(tuple(b[yy, xx, :3]))
            return (hh <= 40 / 360 or hh >= 342 / 360) and 0.12 < ss < 0.65 and vv > 0.55
        for y in range(FRAME):
            for x in range(FRAME):
                if is_mark(b[y, x]) and any(bare(y + dy, x + dx) for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                    f[y, x, :3] = fur(x, y)
    elif pattern == 'runes':
        # Glowing runes: a stitched band down the front, and marks along the hem.
        if facing == 'down':
            cx = (x0 + x1) // 2
            for y in range(y0 + 2, yb - 2):
                if a[y, cx] and (y % 2 == 0):
                    put(cx, y, mix(acc, (1, 1, 1), 0.3))
        hem = yb - 4
        for x in range(FRAME):
            if f[hem, x, 3] > 0.5 and (x % 3 == 0) and not np.allclose(f[hem, x, :3], (0.16, 0.12, 0.18), atol=0.05):
                put(x, hem, mix(acc, (1, 1, 1), 0.45))
    elif pattern == 'pockets':
        # Two patch pockets with buttons, and a light collar.
        if facing == 'down':
            for px in (x0 + 1, x1 - 3):
                for y in range(y1 - 4, y1 - 1):
                    for x in range(px, px + 3):
                        if m[y, x]:
                            f[y, x, :3] = light if y == y1 - 4 else (dark if x in (px, px + 2) or y == y1 - 2 else mix(mid, dark, 0.4))
                put(px + 1, y1 - 4, acc)
            cx = (x0 + x1) // 2
            for x in range(cx - 2, cx + 3):
                if m[y0, x]:
                    f[y0, x, :3] = light


def apply(base, recolored, wear=None, accent=None, pattern=None):
    out = recolored.copy()
    mask = outfit_mask(base)
    acc = hexc(accent) if accent else np.array([0.95, 0.78, 0.25])
    for row, facing in enumerate(DIRS):
        for col in range(base.shape[1] // FRAME):
            oy, ox = row * FRAME, col * FRAME
            f = out[oy:oy + FRAME, ox:ox + FRAME]
            m = mask[oy:oy + FRAME, ox:ox + FRAME]
            a = base[oy:oy + FRAME, ox:ox + FRAME, 3] > 0.5
            if not m.any():
                continue
            ys, xs = np.nonzero(m)
            y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
            yb = np.nonzero(a.any(1))[0].max()          # lowest opaque row (feet)
            mid = np.median(f[m][:, :3], axis=0)
            dark, light = shade(mid, 0.55), mix(mid, (1, 1, 1), 0.35)
            outline = np.array([0.16, 0.12, 0.18])

            def put(x, y, c, only_empty=False):
                if 0 <= x < FRAME and 0 <= y < FRAME and (not only_empty or not a[y, x]):
                    f[y, x, :3] = c
                    f[y, x, 3] = 1

            if wear == 'mail':
                for y, x in zip(ys, xs):
                    if (x + y) % 2 == 0:
                        f[y, x, :3] = light
                    elif (x + 2 * y) % 4 == 1:
                        f[y, x, :3] = dark
            elif wear == 'vest':
                if facing == 'down':
                    cx = (x0 + x1) // 2
                    for y, x in zip(ys, xs):
                        if abs(x - cx) <= 1 and y < y1 - 1:
                            f[y, x, :3] = (0.93, 0.88, 0.76) if x != cx else (0.8, 0.74, 0.62)
                    put(cx - 2, y0 + 3, acc)
                    put(cx + 2, y0 + 3, acc)
            elif wear == 'plate':
                # Round pauldrons on the shoulders: a dome with a rim, lit from the top left.
                pads = {'down': [x0 + 1, x1 - 1], 'up': [x0 + 1, x1 - 1], 'right': [x1 - 1], 'left': [x0 + 1]}[facing]
                for px in pads:
                    for dy in range(-1, 3):
                        for dx in range(-2, 3):
                            if dx * dx + (dy - 0.6) ** 2 * 1.6 <= 4.4:
                                c = light if dy <= 0 else mid
                                if dy == 2 or abs(dx) == 2 and dy >= 1:
                                    c = dark
                                put(px + dx, y0 + dy, c)
                    put(px - 1, y0 - 1, (1, 1, 1))
                if facing in ('down', 'up'):
                    cx = (x0 + x1) // 2
                    for y in range(y0 + 3, y1):
                        if m[y, cx]:
                            f[y, cx, :3] = light
                    if facing == 'down':
                        put(cx, y0 + 4, acc)
            elif wear == 'robe':
                # The hem drops past the knees: below the tunic, fill to just above the boots.
                bottom = {}
                for y, x in zip(ys, xs):
                    bottom[x] = max(bottom.get(x, 0), y)
                hem_top = max(bottom.values())
                hem_bottom = yb - 2
                cols = [x for x in bottom if bottom[x] >= hem_top - 2]
                lx, rx = min(cols), max(cols)
                for y in range(hem_top + 1, hem_bottom + 1):
                    flare = (y - hem_top + 1) // 2
                    for x in range(lx - flare, rx + flare + 1):
                        c = mid
                        if x in (lx - flare, rx + flare):
                            c = dark
                        put(x, y, c)
                for x in range(lx - (hem_bottom - hem_top + 1) // 2, rx + (hem_bottom - hem_top + 1) // 2 + 1):
                    put(x, hem_bottom, dark)
                    put(x, hem_bottom - 1, acc)
            elif wear == 'cloak':
                top, bot = y0, yb - 3
                cx = (x0 + x1) // 2
                if facing == 'up':
                    # From behind: the cape covers the back, widening toward the hem.
                    for y in range(top, bot + 1):
                        w = (y - top) // 3
                        for x in range(x0 - w, x1 + w + 1):
                            edge = x in (x0 - w, x1 + w) or y == bot
                            c = outline if edge else (light if x == cx - 2 else mid)
                            if pattern == 'fur' and not edge and y >= bot - 2:
                                c = fur(x, y)
                            put(x, y, c)
                else:
                    # From the front or side: the cape shows just outside the body's outline.
                    for y in range(top + 1, bot + 1):
                        filled = np.nonzero(a[y])[0]
                        if len(filled) == 0:
                            continue
                        left, right = filled.min(), filled.max()
                        flare = (y - top) // 5
                        if facing == 'down':
                            spots = [(left - 1 - flare, True), (right + 1 + flare, True)]
                            spots += [(left - flare, False)] if flare else []
                            spots += [(right + flare, False)] if flare else []
                        elif facing == 'right':
                            spots = [(left - 1 - flare, True)] + [(left - k, False) for k in range(0, flare + 1)]
                        else:
                            spots = [(right + 1 + flare, True)] + [(right + k, False) for k in range(0, flare + 1)]
                        for x, outer in spots:
                            c = outline if outer else mid
                            if pattern == 'fur' and not outer and y >= bot - 2:
                                c = fur(x, y)
                            put(x, y, c, only_empty=True)
                    if facing == 'down':
                        put(cx, top, acc); put(cx - 1, top, acc); put(cx, top + 1, shade(acc, 0.7))
            # A helmet or hood (hero_layers.py) comes in magenta: soft magenta takes the armour's
            # colour, keeping its shade, and full magenta the trim.
            for y in range(FRAME):
                for x in range(FRAME):
                    if not a[y, x]:
                        continue
                    hh, s, v = hsv(tuple(base[oy + y, ox + x, :3]))
                    if abs(hh * 360 - 300) < 12 and s > 0.3:
                        f[y, x, :3] = acc if s > 0.85 else (light if v > 0.82 else (dark if v < 0.55 else mid))
            if pattern:
                detail(f, base[oy:oy + FRAME, ox:ox + FRAME], m, a, facing, pattern, wear, mid, acc, (y0, y1, x0, x1, yb))
    return out


def trinkets(body, out, gloves=None, boots=None, necklace=None, chain=None):
    """Gloves on the hands, boots on the feet and a necklace under the chin (GearOverlay.trinkets),
    each in its colour (#RRGGBB) at the brightness of what was there. Found on the plain body: its
    skin in patches, the biggest the face and those below its chin the arms, whose last three rows
    are the hands; the boots are its brown near the feet."""
    gloves, boots, necklace = (hexc(c) if c else None for c in (gloves, boots, necklace))
    ch = hexc(chain) if chain else np.array([0.95, 0.78, 0.25])
    for row, facing in enumerate(DIRS):
        for col in range(body.shape[1] // FRAME):
            oy, ox = row * FRAME, col * FRAME
            f = out[oy:oy + FRAME, ox:ox + FRAME]
            b = body[oy:oy + FRAME, ox:ox + FRAME]
            a = b[..., 3] > 0.5
            rows = np.nonzero(a.any(1))[0]
            if len(rows) == 0 or rows[-1] - rows[0] <= 8:
                continue
            feet = rows[-1]

            def paint(x, y, c, lift, gain):
                if 0 <= x < FRAME and 0 <= y < FRAME and f[y, x, 3] > 0.5:
                    f[y, x, :3] = np.clip(c * (lift + hsv(tuple(f[y, x, :3]))[2] * gain), 0, 1)

            def put(x, y, c):
                if 0 <= x < FRAME and 0 <= y < FRAME and f[y, x, 3] > 0.5:
                    f[y, x, :3] = c

            if boots is not None:
                for y in range(max(0, feet - 5), feet + 1):
                    for x in range(FRAME):
                        hh, s, v = hsv(tuple(b[y, x, :3]))
                        if a[y, x] and 7 / 360 <= hh <= 43 / 360 and s > 0.35 and v < 0.75:
                            paint(x, y, boots, 0.55, 0.9)
            if gloves is None and necklace is None:
                continue
            skin = np.zeros((FRAME, FRAME), bool)
            for y in range(FRAME):
                for x in range(FRAME):
                    if a[y, x]:
                        hh, s, v = hsv(tuple(b[y, x, :3]))
                        skin[y, x] = (hh <= 40 / 360 or hh >= 342 / 360) and 0.12 < s < 0.65 and v > 0.55
            seen = np.zeros_like(skin)
            patches = []
            for y in range(FRAME):
                for x in range(FRAME):
                    if skin[y, x] and not seen[y, x]:
                        stack, cells = [(y, x)], []
                        seen[y, x] = True
                        while stack:
                            cy, cx = stack.pop()
                            cells.append((cy, cx))
                            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                                ny, nx = cy + dy, cx + dx
                                if 0 <= ny < FRAME and 0 <= nx < FRAME and skin[ny, nx] and not seen[ny, nx]:
                                    seen[ny, nx] = True
                                    stack.append((ny, nx))
                        patches.append(cells)
            if not patches:
                continue
            face = max(patches, key=len)
            chin = max(y for y, _ in face)
            if gloves is not None:
                for cells in patches:
                    if cells is face or min(y for y, _ in cells) < chin - 1:
                        continue
                    low = max(y for y, _ in cells)
                    for y, x in cells:
                        if y >= low - 2:
                            paint(x, y, gloves, 0.5, 0.6)
            under = [x for y, x in face if y == chin]
            if necklace is not None and facing == 'down' and under:
                cx = (min(under) + max(under)) // 2
                for dx, dy in ((-2, 1), (-1, 2), (1, 2), (2, 1)):
                    put(cx + dx, chin + dy, ch)
                put(cx, chin + 2, mix(necklace, (1, 1, 1), 0.4))
                put(cx, chin + 3, necklace)
    return out


def head(body):
    """The head on a plain body frame (`body`, 48 × 48): its skin's biggest patch (the bald scalp is
    skin too), as (top, chin, cells). None if there's none."""
    a = body[..., 3] > 0.5
    skin = np.zeros((FRAME, FRAME), bool)
    for y in range(FRAME):
        for x in range(FRAME):
            if a[y, x]:
                hh, s, v = hsv(tuple(body[y, x, :3]))
                skin[y, x] = (hh <= 40 / 360 or hh >= 342 / 360) and 0.12 < s < 0.65 and v > 0.55
    seen = np.zeros_like(skin)
    best = []
    for y in range(FRAME):
        for x in range(FRAME):
            if skin[y, x] and not seen[y, x]:
                stack, cells = [(y, x)], []
                seen[y, x] = True
                while stack:
                    cy, cx = stack.pop()
                    cells.append((cy, cx))
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < FRAME and 0 <= nx < FRAME and skin[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            stack.append((ny, nx))
                if len(cells) > len(best):
                    best = cells
    if not best:
        return None
    return min(y for y, _ in best), max(y for y, _ in best), best


def half_up(v):
    """Rounded, halves up (as Swift's `rounded()` for the positive numbers here; Python's round() rounds
    halves to even)."""
    return int(math.floor(v + 0.5))


# Where tools/wear_art.py puts each piece in its frame (GearOverlay's constants of the same names).
HAT_BRIM, ANCHOR_X, ANCHOR_Y = 40, 24, 20
SHOULDER_Y, CAPE_DROP, CAPE_SPAN = 24, 20, 14
CAPE_FLOOR = 0.05   # a cape's shadows take its colour down to here
CHIN_Y = 20         # where a scarf's wearer's chin is


def piece_sheet(kind):
    """A worn piece's sheet as tools/wear_art.py cut it out (art/sprites/wear_<kind>.png)."""
    import pathlib
    from PIL import Image
    sprites = pathlib.Path(__file__).resolve().parent.parent / "art" / "sprites"
    return np.asarray(Image.open(sprites / f"wear_{kind}.png").convert("RGBA")).astype(float) / 255


def lengthened(t, by, start):
    """Pixel-art stretch down (GearOverlay's Piece.lengthened): `by` rows repeated (or dropped)
    through the middle of the piece's rows from `start` down, the rows above staying put."""
    rows = [y for y in range(start, FRAME) if (t[y, :, 3] > 0.5).any()]
    if by == 0 or not rows:
        return t
    body = [t[y] for y in range(start, max(rows) + 1)]
    for k in range(abs(by)):
        m = max(0, min(len(body) - 1, len(body) // 2 + (k % 3 - 1)))
        if by > 0:
            body.insert(m, body[m])
        elif len(body) > 1:
            body.pop(m)
    out = t.copy()
    out[start:] = 0
    for i, row in enumerate(body):
        if start + i < FRAME:
            out[start + i] = row
    return out


def figure(frame):
    """A figure's top, feet, shoulders (0.38 of the way down: where the tunic starts on every race's
    sheet) and its outline's left and right there (GearOverlay.figure); None if it's too small."""
    a = frame[..., 3] > 0.5
    rows = np.nonzero(a.any(1))[0]
    if len(rows) == 0 or rows[-1] - rows[0] <= 8:
        return None
    top, feet = rows[0], rows[-1]
    shoulder = top + half_up((feet - top) * 0.38)
    xs = np.nonzero(a[shoulder])[0]
    if len(xs) == 0:
        return None
    return top, feet, shoulder, xs.min(), xs.max()


def lit(t, floor=0.25):
    """A piece's coloured pixels: not its white, its outline or its holes (darker than `floor`; a
    cape's deepest shadow is its colour too, its outline neutral)."""
    out = np.zeros(t.shape[:2], bool)
    for y, x in zip(*np.nonzero(t[..., 3] > 0.5)):
        _, s_, v_ = hsv(tuple(t[y, x, :3]))
        out[y, x] = s_ > 0.2 and v_ > floor
    return out


def widen(t, by, keep_top=0):
    """Pixel-art stretch (GearOverlay.widen): repeat (or drop) `by` columns through the middle of the
    piece's rows from `keep_top` down, spread a little either side, so a pom over it keeps its shape."""
    if by == 0:
        return t
    cols = [x for x in range(FRAME) if (t[keep_top:, x, 3] > 0.5).any()]
    if not cols:
        return t
    l, r = min(cols), max(cols)
    out = t.copy()
    out[keep_top:] = 0
    body = t[keep_top:, l:r + 1]
    for k in range(abs(by)):
        m = max(0, min(body.shape[1] - 1, body.shape[1] // 2 + (k % 3 - 1)))
        if by > 0:
            body = np.concatenate([body[:, :m + 1], body[:, m:]], 1)
        elif body.shape[1] > 1:
            body = np.concatenate([body[:, :m], body[:, m + 1:]], 1)
    x0 = half_up((l + r) / 2 - (body.shape[1] - 1) / 2)
    for i in range(body.shape[1]):
        if 0 <= x0 + i < FRAME:
            out[keep_top:, x0 + i] = body[:, i]
    return out


def pinched(t, by):
    """Narrower by `by` columns, dropped next to its edges in turn, left then right (GearOverlay's
    Piece.pinched): what's between them, a mask's eye holes, stays put."""
    out = t.copy()
    for k in range(by):
        cols = [x for x in range(FRAME) if (out[:, x, 3] > 0.5).any()]
        if len(cols) < 8:
            break
        l, r = min(cols), max(cols)
        if k % 2 == 0:
            out[:, l + 1:l + 3] = out[:, l:l + 2].copy()
            out[:, l] = 0
        else:
            out[:, r - 2:r] = out[:, r - 1:r + 1].copy()
            out[:, r] = 0
    return out


def bbox(t):
    ys, xs = np.nonzero(t[..., 3] > 0.5)
    return (ys.min(), ys.max(), xs.min(), xs.max()) if len(ys) else None


def painted(t, colour, trim=None, floor=0.25):
    """A piece in the hat's colours: its coloured pixels (not its white fur, its outline or its eye
    holes) in `trim` if it has one (a bunny's pink band), else `colour`, as light or dark as they were
    against their middle shade."""
    out = t.copy()
    tone = hexc(trim) if trim else hexc(colour)
    shades = [(y, x, hsv(tuple(t[y, x, :3]))[2]) for y, x in zip(*np.nonzero(lit(t, floor)))]
    if not shades:
        return out
    middle = sorted(v for _, _, v in shades)[len(shades) // 2]
    for y, x, v in shades:
        out[y, x, :3] = np.clip(tone * (v / middle), 0, 1)
        out[y, x, 3] = 1
    return out


def face(f, cells, top, chin):
    """The face on frame `f` as drawn (GearOverlay.face), its head found on the plain body (`cells`,
    `top`, `chin` from `head`): the eyes' whites with a pupil or lash beside or over them and the
    face's skin near (a glint in a beard or on a helmet has none; a cream white, as some armour sheets
    draw, only if there's no pure one), the highest pair; and the rows from them up and down that show
    skin or white. As (eye top, the middle of each eye, the face's top row, its bottom row, whether a
    pixel is face, the columns searched), or None from behind."""
    drawn = f[..., 3] > 0.5
    xs_all = [x for _, x in cells]
    whites, near = [], []
    for most, least in ((0.06, 0.92), (0.25, 0.85)):
        for y in range(max(0, top + 2), min(FRAME, chin + 3)):
            for x in range(max(0, min(xs_all) - 1), min(FRAME, max(xs_all) + 3)):
                if not drawn[y, x]:
                    continue
                _, s_, v_ = hsv(tuple(f[y, x, :3]))
                if s_ >= most or v_ <= least:
                    continue
                dark = lambda yy, xx: 0 <= yy < FRAME and 0 <= xx < FRAME and drawn[yy, xx] and hsv(tuple(f[yy, xx, :3]))[2] < 0.35
                if not (dark(y, x - 1) or dark(y, x + 1) or dark(y - 1, x)):
                    continue
                whites.append((y, x))
                if any(0 <= xx < FRAME and drawn[yy, xx] and is_skin(f[yy, xx])
                       for yy in (y, y + 1) if yy < FRAME for xx in (x - 2, x - 1, x + 1, x + 2)):
                    near.append((y, x))
        if near:
            break
    eyes = near or whites
    if not eyes:
        return None
    eye = min(y for y, _ in eyes)
    xs = sorted({x for y, x in eyes if y <= eye + 1})
    groups = [[xs[0]]]
    for x in xs[1:]:
        (groups[-1].append(x) if x - groups[-1][-1] <= 2 else groups.append([x]))
    mids = [sum(g) / len(g) for g in groups]
    span = range(max(0, min(xs_all) - 2), min(FRAME, max(xs_all) + 3))

    def facial(y, x):
        if not drawn[y, x]:
            return False
        _, s_, v_ = hsv(tuple(f[y, x, :3]))
        return is_skin(f[y, x]) or (s_ < most and v_ > least)

    def shows(y):
        return 0 <= y < FRAME and any(facial(y, x) for x in span)
    low = eye
    while low - eye < 6 and shows(low + 1):
        low += 1
    high = eye
    while eye - high < 8 and shows(high - 1):
        high -= 1
    return eye, mids, high, low, facial, span


def scarf(body, out, colour, base=None):
    """A festive scarf (a necklace that wears `scarf`; GearOverlay.scarf) round the neck, over
    everything: the piece Retro Diffusion drew (art/sprites/wear_scarf.png), what's under its wearer's
    chin, in its colour, put under the chin as drawn (armour with a sheet of its own draws its head
    higher or lower than the plain body; from behind, the chin found from the front), across the middle
    of the body at the shoulders. The chin is found on `base`, the sprite before any recolouring (the
    game's `original`): the skin test knows the sheets' own fair skin, not a darker tone the hero chose."""
    sheet = piece_sheet("scarf")

    def chin_of(row, c):
        """The bottom of the face as drawn in that frame: from behind, the front's; with no face to
        find, the plain body's chin."""
        oy, ox = DIRS.index('down' if DIRS[row] == 'up' else DIRS[row]) * FRAME, c * FRAME
        found = head(body[oy:oy + FRAME, ox:ox + FRAME])
        if found is None:
            return None
        seen = face((out if base is None else base)[oy:oy + FRAME, ox:ox + FRAME], found[2], found[0], found[1])
        return seen[3] if seen else found[1]
    chins = {(row, c): chin_of(row, c) for row in range(len(DIRS)) for c in range(body.shape[1] // FRAME)}
    for row, facing in enumerate(DIRS):
        piece = painted(sheet[row * FRAME:(row + 1) * FRAME], colour)
        if bbox(piece) is None:
            continue
        for c in range(body.shape[1] // FRAME):
            oy, ox = row * FRAME, c * FRAME
            f = out[oy:oy + FRAME, ox:ox + FRAME]
            fig = figure(body[oy:oy + FRAME, ox:ox + FRAME])
            if fig is None or chins[(row, c)] is None:
                continue
            for y, x in zip(*np.nonzero(piece[..., 3] > 0.5)):
                ty, tx = y + chins[(row, c)] - CHIN_Y, x + (fig[3] + fig[4]) // 2 - ANCHOR_X
                if 0 <= ty < FRAME and 0 <= tx < FRAME:
                    f[ty, tx, :3] = piece[y, x, :3]
                    f[ty, tx, 3] = 1
    return out


def hat(body, out, kind, colour, trim=None, base=None):
    """A festive hat on the head (GearOverlay.hat), every frame: a piece Retro Diffusion drew on a
    hero (art/sprites/wear_<kind>.png, cut out by tools/wear_art.py), fitted to the head as drawn, hair
    and all, measured on the plain body (the scalp, the eyes) and on `out` before the hat goes on.
    crown (a party crown), santa and ears (a bunny's, its band in `trim`) go round the head: their band
    on the head's widest row over the eyes, as wide as the scalp and a little more, over all the hair
    above it. A mask (none from behind) goes over the face, its eye holes on the
    eyes, found on the face as drawn (armour with a sheet of its own has a face of its own), no wider
    or taller than the face, a little over a beard, and from the side as far forward as it reaches. The
    face is found on `base`, the sprite before any recolouring (the game's `original`): the skin test
    knows the sheets' own fair skin, not a darker tone the hero chose (it found no face on a deep one,
    and the mask slid off it)."""
    sheet = piece_sheet(kind)
    for row, facing in enumerate(DIRS):
        piece = painted(sheet[row * FRAME:(row + 1) * FRAME], colour, trim)
        if bbox(piece) is None:
            continue
        for c in range(body.shape[1] // FRAME):
            oy, ox = row * FRAME, c * FRAME
            f = out[oy:oy + FRAME, ox:ox + FRAME]
            found = head(body[oy:oy + FRAME, ox:ox + FRAME])
            if found is None:
                continue
            top, chin, cells = found
            span = [x for y, x in cells if y == top + 3] or [x for _, x in cells]
            left, right = min(span), max(span)
            cx = (left + right) // 2
            drawn = f[..., 3] > 0.5     # the head as drawn, hair and all, before the hat goes on

            def stamp(t, dy, dx):
                for y, x in zip(*np.nonzero(t[..., 3] > 0.5)):
                    if 0 <= y + dy < FRAME and 0 <= x + dx < FRAME:
                        f[y + dy, x + dx, :3] = t[y, x, :3]
                        f[y + dy, x + dx, 3] = 1

            if kind == 'mask':
                seen = face(f if base is None else base[oy:oy + FRAME, ox:ox + FRAME], cells, top, chin)
                if seen is None:
                    continue
                oy_, mids, high, low, facial, span = seen
                ox_ = (mids[0] + mids[-1]) / 2 if facing == 'down' else max(mids) if facing == 'right' else min(mids)
                dx = half_up(ox_) - ANCHOR_X
                # The mask stops two rows under the chin (over the top of a dwarf's beard) and starts no
                # more than a row over the face (on the hair).
                t = piece
                if facing == 'down':
                    # No wider than the face (its outermost skin or eye pixels from just over the eyes
                    # to the chin) and its outline: on a narrow face it spilled onto the hair.
                    rows = [[x for x in span if facial(y, x)] for y in range(oy_ - 1, low + 1)]
                    wide = max((max(r) - min(r) + 1 for r in rows if r), default=0)
                    _, _, tl, tr = bbox(t)
                    if wide:
                        t = pinched(t, max(0, min(4, (tr - tl + 1) - (wide + 2))))
                t0, t1, _, _ = bbox(t)
                below = max(0, min(3, t1 - (low - oy_ + ANCHOR_Y + 2)))
                t = lengthened(t, -below, ANCHOR_Y + 2)
                above = max(0, min(3, (high - oy_ + ANCHOR_Y - 1) - t0))
                t = lengthened(t[::-1], -above, FRAME - ANCHOR_Y + 1)[::-1]
                dy = oy_ - ANCHOR_Y
                if facing in ('right', 'left'):
                    # From the side, as far forward as the face reaches on any of its rows (forehead,
                    # nose, chin; not the hair above, whose ginger passes for skin), the outline past
                    # it: no skin peeking out in front of it. Within three pixels of the front eye on
                    # the front eye hole.
                    sign = 1 if facing == 'right' else -1
                    need = 0
                    for y in range(high, low + 1):
                        mask_row = [x for x in range(FRAME) if t[y - dy, x, 3] > 0.5] if 0 <= y - dy < FRAME else []
                        if not mask_row:
                            continue
                        face_row = [x for x in span if facial(y, x)]
                        if face_row:
                            reach = (max(face_row) + 1 - (max(mask_row) + dx)) if sign > 0 else ((min(mask_row) + dx) - (min(face_row) - 1))
                            need = max(need, reach)
                    dx += sign * min(3, need)
                stamp(t, dy, dx)
                continue

            def around(y):
                """The head as drawn on row `y`: the run through its middle, hair and all, never
                narrower than the scalp and its outline."""
                if not 0 <= y < FRAME:
                    return left - 1, right + 1
                near = [x for x in range(max(0, cx - 3), min(FRAME, cx + 4)) if drawn[y, x]]
                if not near:
                    return left - 1, right + 1
                l = r = min(near, key=lambda x: abs(x - cx))
                while l - 1 >= max(0, left - 6) and drawn[y, l - 1]:
                    l -= 1
                while r + 1 < min(FRAME, right + 7) and drawn[y, r + 1]:
                    r += 1
                return min(l, left - 1), max(r, right + 1)

            # The eyes: gaps in the face's skin (none from behind). The band sits on the widest row of
            # the head as drawn, hair and all, at least two rows over them: worn round the head, not
            # perched on top of it. Never lower than three fifths of the way from the scalp's top to
            # the eyes: a cowl or a helmet round the face is wide all the way down.
            skin = {(y, x) for y, x in cells}
            eyes = [y for y, x in cells if y > top + 2 and (y, x + 1) not in skin
                    and ((y, x + 2) in skin or (y, x + 3) in skin)]
            eye = min(eyes) if eyes else top + max(4, (chin - top) // 2)
            deep = min(eye - 2, top + max(2, (eye - top) * 3 // 5))
            crown_top = min((y for y in range(FRAME) if drawn[y, max(0, left):right + 1].any()), default=top)
            widths = {y: around(y)[1] - around(y)[0] for y in range(crown_top, deep + 1)}
            brim = max(widths, key=lambda y: (widths[y], y)) if widths else top + 1
            # As wide as the scalp and its outline and a little more, within three pixels of as drawn;
            # a pom (the rows narrower than half the piece) keeps its shape.
            t0, t1, tl, tr = bbox(piece)
            keep = next(y for y in range(t0, t1 + 1) if (piece[y, :, 3] > 0.5).sum() >= max(1, (tr - tl + 1) // 2))
            band = int((piece[HAT_BRIM, :, 3] > 0.5).sum())
            t = widen(piece, max(-3, min(3, (right - left + 5) - band)), keep)
            t0, t1, tl, tr = bbox(t)
            dy, dx = brim + 1 - HAT_BRIM, (left + right + 1) // 2 - (tl + tr + 1) // 2
            # It sits on the head: the hair above the band it doesn't cover goes (spiky hair stuck up
            # between a crown's points or a bunny's ears).
            for y in range(0, brim - 1):
                for x in range(max(0, left - 1), min(FRAME, right + 2)):
                    ty, tx = y - dy, x - dx
                    if drawn[y, x] and not (0 <= ty < FRAME and 0 <= tx < FRAME and t[ty, tx, 3] > 0.5):
                        f[y, x] = 0
            stamp(t, dy, dx)
    return out


def is_skin(p):
    hh, s, v = hsv(tuple(p[:3]))
    return (hh <= 40 / 360 or hh >= 342 / 360) and 0.12 < s < 0.65 and v > 0.55


CAPE_REACH = 4   # how far past its edge a cape's lining reaches to meet the body (from the side)


def lining(t, dx, dy, shoulder, a, f, put, colour, trim, outline, front):
    """A cape's inside, seen from the front or the side wherever the body doesn't cover it: on each
    row below the shoulders, every gap within the cape's own span (between its panels, between an arm
    swung out and the body), and a gap of up to CAPE_REACH pixels between its edge and the body (from
    the side, where the back leans away from it). Dark in the cape's colour; along its bottom two
    rows, its trim and outline, so the hem runs on unbroken (playtesting 2026-10-21: "the cloaks still
    have a gap depending on what they wear or their arm position"). From the side only what shows
    of it counts: the part hidden behind the body reaches under the legs, and nothing hangs between
    them there. Last, any clear pixel it has closed in (one the bare figure didn't), as between an
    arm and the back above where it shows, is its inside too. GearOverlay.lining."""
    def body(x, y):
        return 0 <= x < FRAME and 0 <= y < FRAME and a[y, x]

    rows = {}
    for y, x in zip(*np.nonzero(t[..., 3] > 0.5)):
        if front or not body(x + dx, y + dy):
            rows.setdefault(y + dy, []).append(x + dx)
    if not rows:
        return
    bottom = max(rows)
    inside = shade(colour, 0.45)

    for y, xs in rows.items():
        if y <= shoulder or not 0 <= y < FRAME:
            continue
        tone = outline if y == bottom else trim if y == bottom - 1 else inside
        lo, hi = min(xs), max(xs)
        fill = [x for x in range(lo, hi + 1)]
        for start, step in ((lo - 1, -1), (hi + 1, 1)):
            gap = []
            x = start
            while len(gap) < CAPE_REACH and 0 <= x < FRAME and not body(x, y):
                gap.append(x)
                x += step
            if body(x, y):
                fill += gap
        for x in fill:
            if 0 <= x < FRAME and not body(x, y) and x not in xs:
                put(x, y, tone, only_empty=True)
    before, after = enclosed(~a), enclosed(f[..., 3] < 0.5)
    for y, x in zip(*np.nonzero(after & ~before)):
        put(x, y, outline if y == bottom else trim if y == bottom - 1 else inside)


def enclosed(clear):
    """The pixels of `clear` that can't be reached from the frame's edge through it (4 ways)."""
    reached = np.zeros_like(clear)
    stack = [(y, x) for y in range(FRAME) for x in (0, FRAME - 1)] + [(y, x) for x in range(FRAME) for y in (0, FRAME - 1)]
    while stack:
        y, x = stack.pop()
        if 0 <= y < FRAME and 0 <= x < FRAME and clear[y, x] and not reached[y, x]:
            reached[y, x] = True
            stack += [(y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)]
    return clear & ~reached


def cape(base, out, colour, trim):
    """A status cape over whatever is worn (GearOverlay.drape): the cape Retro Diffusion drew
    (art/sprites/wear_cape.png, cut out by tools/wear_art.py) in its colour, stretched to the body
    (its shoulders 0.38 of the way from the top of the head to the feet, as wide as it is there, and
    as long down to the feet), its trim along the hem. From behind it hangs over the body, the hair
    falling over its top, a diamond emblem on the back; from the front and the side it shows past the
    body's outline, a clasp at the collar."""
    acc = hexc(trim)
    outline = np.array([0.16, 0.12, 0.18])
    sheet = piece_sheet("cape")
    for row, facing in enumerate(DIRS):
        frame = sheet[row * FRAME:(row + 1) * FRAME]
        coloured = lit(frame, CAPE_FLOOR)
        piece = painted(frame, colour, floor=CAPE_FLOOR)
        # Its trim: the lowest coloured pixel of each column, and the outline under it.
        for x in range(FRAME):
            ys = np.nonzero(coloured[:, x])[0]
            if len(ys):
                piece[ys.max(), x, :3] = acc
                if ys.max() + 1 < FRAME and piece[ys.max() + 1, x, 3] < 0.5:
                    piece[ys.max() + 1, x, :3] = outline
                    piece[ys.max() + 1, x, 3] = 1
        if bbox(piece) is None:
            continue
        for c in range(base.shape[1] // FRAME):
            oy, ox = row * FRAME, c * FRAME
            f = out[oy:oy + FRAME, ox:ox + FRAME]
            b = base[oy:oy + FRAME, ox:ox + FRAME]
            a = b[..., 3] > 0.5
            fig = figure(b)
            if fig is None:
                continue
            top, feet, shoulder, left, right = fig
            cx = (left + right) // 2
            # From the front and the side a little wider than the body, so it shows past its outline.
            flare = {'up': 0, 'down': 4}.get(facing, 2)
            t = widen(lengthened(piece, (feet - shoulder) - CAPE_DROP, SHOULDER_Y), (right - left + 1) - CAPE_SPAN + flare)
            dy, dx = shoulder - SHOULDER_Y, cx - ANCHOR_X

            def put(x, y, cc, only_empty=False):
                if 0 <= x < FRAME and 0 <= y < FRAME and (not only_empty or not a[y, x]):
                    f[y, x, :3] = cc
                    f[y, x, 3] = 1

            def hair(x, y):
                if y >= shoulder + 11 or not (0 <= x < FRAME and 0 <= y < FRAME) or not a[y, x]:
                    return False
                hh, ss, vv = hsv(tuple(b[y, x, :3]))
                return 10 <= hh * 360 <= 65 and ss > 0.4 and vv > 0.6

            for y, x in zip(*np.nonzero(t[..., 3] > 0.5)):
                if facing == 'up':
                    if not hair(x + dx, y + dy):
                        put(x + dx, y + dy, t[y, x, :3])
                else:
                    put(x + dx, y + dy, t[y, x, :3], only_empty=True)
            if facing != 'up':
                lining(t, dx, dy, shoulder, a, f, put, hexc(colour), acc, outline, facing == 'down')
            if facing == 'up':
                emblem = shoulder + 6
                for ey in range(-2, 3):
                    for ex in range(abs(ey) - 2, 3 - abs(ey)):
                        if not hair(cx + ex, emblem + ey):
                            put(cx + ex, emblem + ey, acc if abs(ex) + abs(ey) < 2 else shade(acc, 0.7))
            elif facing == 'down':
                put(cx, shoulder, acc); put(cx - 1, shoulder, acc); put(cx, shoulder + 1, shade(acc, 0.7))
    return out


def main(out):
    import json
    import pathlib
    import sys
    from PIL import Image
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    import palette_preview as pp
    root = pathlib.Path(__file__).resolve().parent.parent
    items = [i for i in json.load(open(root / "content" / "items.json"))["items"] if i["type"] == "armor"]
    races = json.load(open(root / "content" / "classes.json"))["races"]
    zoom = 3
    sheet = Image.new("RGB", (len(races) * 4 * 48 * zoom, len(items) * 48 * zoom), (80, 130, 80))
    for k, race in enumerate(races):
        for r, item in enumerate(items):
            # The layers the game stacks (GameSession.layers): body, locks, then hair or headgear; or the
            # armour's own sheet, which is drawn as it is.
            if race["id"] in item.get("sheets", {}):
                image = Image.open(root / "art" / "sprites" / f"{item['sheets'][race['id']]}.png").convert("RGBA")
                if item.get("tint"):
                    tinted = pp.recolor(np.asarray(image).astype(float) / 255, item["tint"])
                    image = Image.fromarray((np.clip(tinted, 0, 1) * 255).round().astype(np.uint8), "RGBA")
                for c, row in enumerate((2, 1, 0, 3)):
                    frame = image.crop((0, row * 48, 48, row * 48 + 48)).resize((48 * zoom, 48 * zoom), Image.NEAREST)
                    sheet.paste(frame, ((k * 4 + c) * 48 * zoom, r * 48 * zoom), frame)
                continue
            head = {"plate": "helmet", "cloak": "hood"}.get(item.get("wear"))
            top = f"{head}_{race['id']}" if head else f"hair_{race['hair']}_{race['id']}"
            base = Image.open(root / "art" / "sprites" / f"body_{race['id']}.png").convert("RGBA")
            for layer in (f"locks_{race['id']}", top):
                base.alpha_composite(Image.open(root / "art" / "sprites" / f"{layer}.png").convert("RGBA"))
            base = np.asarray(base).astype(float) / 255
            dressed = pp.recolor(base, item["recolor"]) if item.get("recolor") else base.copy()
            dressed = apply(base, dressed, item.get("wear"), item.get("accent"), pattern=item.get("pattern"))
            image = Image.fromarray((np.clip(dressed, 0, 1) * 255).astype(np.uint8), "RGBA")
            for c, row in enumerate((2, 1, 0, 3)):   # down, right, up, left
                frame = image.crop((0, row * 48, 48, row * 48 + 48)).resize((48 * zoom, 48 * zoom), Image.NEAREST)
                sheet.paste(frame, ((k * 4 + c) * 48 * zoom, r * 48 * zoom), frame)
    sheet.save(out)
    print(f"wrote {out}: {', '.join(i['id'] for i in items)} on {', '.join(r['id'] for r in races)}")


def capes(out):
    """Every status cape on every race: plain, and over plate, a cloak's own sheet and a robe."""
    import json
    import pathlib
    import sys
    from PIL import Image
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    import palette_preview as pp
    root = pathlib.Path(__file__).resolve().parent.parent
    items = {i["id"]: i for i in json.load(open(root / "content" / "items.json"))["items"]}
    races = json.load(open(root / "content" / "classes.json"))["races"]
    worn = [None] + [items[i] for i in ("iron_plate", "ranger_cloak", "mage_robe") if i in items]
    capes_ = [i for i in items.values() if i["type"] == "cape"]
    zoom = 2
    sheet = Image.new("RGB", (len(races) * 4 * 48 * zoom, len(capes_) * 48 * zoom), (80, 130, 80))
    for r, item_cape in enumerate(capes_):
        armour = worn[r % len(worn)]
        for k, race in enumerate(races):
            if armour and race["id"] in armour.get("sheets", {}):
                base = np.asarray(Image.open(root / "art" / "sprites" / f"{armour['sheets'][race['id']]}.png").convert("RGBA")).astype(float) / 255
                dressed = base.copy()
            else:
                head = {"plate": "helmet", "cloak": "hood"}.get((armour or {}).get("wear"))
                top = f"{head}_{race['id']}" if head else f"hair_{race['hair']}_{race['id']}"
                image = Image.open(root / "art" / "sprites" / f"body_{race['id']}.png").convert("RGBA")
                for layer in (f"locks_{race['id']}", top):
                    image.alpha_composite(Image.open(root / "art" / "sprites" / f"{layer}.png").convert("RGBA"))
                base = np.asarray(image).astype(float) / 255
                dressed = pp.recolor(base, armour["recolor"]) if armour and armour.get("recolor") else base.copy()
                if armour:
                    dressed = apply(base, dressed, armour.get("wear"), armour.get("accent"), pattern=armour.get("pattern"))
            dressed = cape(base, dressed, item_cape["color"], item_cape["accent"])
            image = Image.fromarray((np.clip(dressed, 0, 1) * 255).astype(np.uint8), "RGBA")
            for c, row in enumerate((2, 1, 0, 3)):   # down, right, up, left
                frame = image.crop((0, row * 48, 48, row * 48 + 48)).resize((48 * zoom, 48 * zoom), Image.NEAREST)
                sheet.paste(frame, ((k * 4 + c) * 48 * zoom, r * 48 * zoom), frame)
    sheet.save(out)
    print(f"wrote {out}: {', '.join(i['id'] for i in capes_)}")


def dressed(race, body, style, armour=None, worn=(), skin=None):
    """A hero as the game draws them (GameSession.layers and registerArt): paper-doll layers, or an
    armour's own sheet over the hair from a fifth of the way down the head (nape_*); then the cut,
    and the gloves, boots, necklace and festive hat in `worn`, found on the plain body the armour is
    drawn on. `skin` is a skin tone's id (appearance.json `skin`): its recolour goes on the body, or on
    the armour's sheet, as the game's does, never on the hair."""
    import pathlib
    import sys
    from PIL import Image
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    import palette_preview as pp
    sprites = pathlib.Path(__file__).resolve().parent.parent / "art" / "sprites"

    def load(name):
        return Image.open(sprites / f"{name}.png").convert("RGBA")
    import json
    tones = json.load(open(sprites.parent.parent / "content" / "appearance.json"))["skin"]
    tone = next((t.get("recolor") or [] for t in tones if t["id"] == skin), [])

    def array(img):
        return np.asarray(img).astype(float) / 255

    def stacked(layers):
        """Layers (arrays) drawn on each other, bottom first."""
        img = Image.fromarray((np.clip(layers[0], 0, 1) * 255).round().astype(np.uint8), "RGBA")
        for layer in layers[1:]:
            img.alpha_composite(Image.fromarray((np.clip(layer, 0, 1) * 255).round().astype(np.uint8), "RGBA"))
        return array(img)
    sheet = (armour or {}).get("sheets", {}).get(race)
    if sheet:
        nape, worn_sheet = array(load(f"nape_{style}_{body}")), array(load(sheet))
        base = stacked([nape, worn_sheet])
        rules = tone + (armour.get("tint") or [])
        out = stacked([nape, pp.recolor(worn_sheet, rules)]) if rules else base.copy()
        skeleton = f"body_{race}"
    else:
        # A festive hat sits on the hair, in place of a helmet or hood.
        hatted = any(item["type"] == "head" for item in worn)
        head = None if hatted else {"plate": "helmet", "cloak": "hood"}.get((armour or {}).get("wear"))
        layers = [array(load(name)) for name in (f"body_{body}", f"locks_{body}", f"{head}_{body}" if head else f"hair_{style}_{body}")]
        base = stacked(layers)
        # The skin tone and the armour's colours on the body only (GameSession.bodyRules), and the
        # armour's on a helmet or hood too.
        rules = tone + ((armour or {}).get("recolor") or [])
        top = pp.recolor(layers[2], armour["recolor"]) if head and armour and armour.get("recolor") else layers[2]
        out = stacked([pp.recolor(layers[0], rules) if rules else layers[0], layers[1], top])
        if armour:
            out = apply(base, out, armour.get("wear"), armour.get("accent"), pattern=armour.get("pattern"))
        skeleton = f"body_{body}"
    pieces = {item["type"]: item for item in worn}
    # A festive scarf is worn as a necklace, drawn round the neck instead of a pendant.
    wrap = pieces.pop("necklace") if pieces.get("necklace", {}).get("wear") == "scarf" else None
    necklace = pieces.get("necklace", {})
    plain = np.asarray(load(skeleton)).astype(float) / 255
    out = trinkets(plain, out, gloves=pieces.get("gloves", {}).get("color"),
                   boots=pieces.get("boots", {}).get("color"), necklace=necklace.get("color"), chain=necklace.get("accent"))
    if "cape" in pieces:
        out = cape(base, out, pieces["cape"]["color"], pieces["cape"]["accent"])
    if wrap:
        out = scarf(plain, out, wrap["color"], base)
    if "head" in pieces:
        out = hat(plain, out, pieces["head"]["hat"], pieces["head"]["color"], pieces["head"].get("accent"), base)
    return out


BODIES = [("human", "human", "spiky"), ("human", "human_female", "ponytail"), ("elf", "elf", "long"),
          ("elf", "elf_male", "swept"), ("dwarf", "dwarf", "crop"), ("dwarf", "dwarf_female", "braids")]
# Every skin tone (appearance.json `skin`), taken in turn across the --wear grid.
SKINS = ["fair", "rosy", "tan", "brown", "deep"]
# One armour of every cut, and every walk sheet of its own: what a wearable must fit over.
OUTFITS = [None, "leather_vest", "copper_hide", "chain_mail", "mage_robe", "ranger_cloak", "snow_cloak",
           "iron_plate", "dragon_mail"]


def wear_sheet(out, worn_ids):
    """The wearables `worn_ids` (a hat, a cape, ...) on every body (each race, each gender) under every
    armour cut and sheet (OUTFITS, a row each), facing down, right, up and left, in every skin tone in
    turn, drawn in the game's order: what docs/sprite-acceptance.md asks to look at before a wearable
    ships."""
    import json
    import pathlib
    from PIL import Image
    root = pathlib.Path(__file__).resolve().parent.parent
    items = {i["id"]: i for i in json.load(open(root / "content" / "items.json"))["items"]}
    zoom = 2
    sheet = Image.new("RGB", (len(BODIES) * 4 * 48 * zoom + (len(BODIES) - 1) * 8, len(OUTFITS) * 48 * zoom), (80, 130, 80))
    for r, outfit in enumerate(OUTFITS):
        for k, (race, body, style) in enumerate(BODIES):
            img = dressed(race, body, style, items.get(outfit), [items[i] for i in worn_ids], skin=SKINS[(r + k) % len(SKINS)])
            image = Image.fromarray((np.clip(img, 0, 1) * 255).round().astype(np.uint8), "RGBA")
            for c, row in enumerate((2, 1, 0, 3)):   # down, right, up, left
                frame = image.crop((0, row * 48, 48, row * 48 + 48)).resize((48 * zoom, 48 * zoom), Image.NEAREST)
                sheet.paste(frame, ((k * 4 + c) * 48 * zoom + k * 8, r * 48 * zoom), frame)
    sheet.save(out)
    print(f"wrote {out}: {', '.join(worn_ids)} over {', '.join(o or 'nothing' for o in OUTFITS)}")


def trinket_sheet(out):
    """Every body (each race, each gender) in a few outfits, with gloves, boots and a necklace."""
    import json
    import pathlib
    from PIL import Image
    root = pathlib.Path(__file__).resolve().parent.parent
    items = {i["id"]: i for i in json.load(open(root / "content" / "items.json"))["items"]}
    bodies = [("human", "human", "spiky"), ("human", "human_female", "ponytail"), ("elf", "elf", "long"),
              ("elf", "elf_male", "swept"), ("dwarf", "dwarf", "crop"), ("dwarf", "dwarf_female", "braids")]
    outfits = [(None, ("leather_gloves", "speed_boots", "amber_amulet")),
               ("leather_vest", ("falcon_gloves", "traveler_boots", "phoenix_amulet")),
               ("mage_robe", ("starforged_gauntlets", "cloudstep_boots", "moonstone_pendant")),
               ("iron_plate", ("dragonhide_gauntlets", "speed_boots", "emerald_glass_amulet")),
               ("dragon_mail", ("goldleaf_gauntlets", "goldleaf_boots", "goldleaf_pendant")),
               ("snow_cloak", ("iron_gauntlets", "leather_boots", "shell_pendant"))]
    zoom = 3
    sheet = Image.new("RGB", (len(bodies) * 4 * 48 * zoom, len(outfits) * 48 * zoom), (80, 130, 80))
    for k, (race, body, style) in enumerate(bodies):
        for r, (armour, worn) in enumerate(outfits):
            img = dressed(race, body, style, items.get(armour), [items[i] for i in worn if i in items])
            image = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA")
            for c, row in enumerate((2, 1, 0, 3)):   # down, right, up, left
                frame = image.crop((0, row * 48, 48, row * 48 + 48)).resize((48 * zoom, 48 * zoom), Image.NEAREST)
                sheet.paste(frame, ((k * 4 + c) * 48 * zoom, r * 48 * zoom), frame)
    sheet.save(out)
    print(f"wrote {out}: {', '.join(b for _, b, _ in bodies)} in {', '.join(str(a) for a, _ in outfits)}")


def hat_sheet(out, hats=None):
    """Every body (each race, each gender) in each festive hat (items.json type head), over a few outfits."""
    import json
    import pathlib
    from PIL import Image
    root = pathlib.Path(__file__).resolve().parent.parent
    items = {i["id"]: i for i in json.load(open(root / "content" / "items.json"))["items"]}
    bodies = [("human", "human", "spiky"), ("human", "human_female", "ponytail"), ("elf", "elf", "long"),
              ("elf", "elf_male", "swept"), ("dwarf", "dwarf", "crop"), ("dwarf", "dwarf_female", "braids")]
    worn = hats or [i for i in items.values() if i["type"] == "head"]
    outfits = [None, "leather_vest", "mage_robe", "iron_plate", "ranger_cloak"]
    zoom = 3
    sheet = Image.new("RGB", (len(bodies) * 4 * 48 * zoom, len(worn) * 48 * zoom), (80, 130, 80))
    for k, (race, body, style) in enumerate(bodies):
        for r, item in enumerate(worn):
            img = dressed(race, body, style, items.get(outfits[(r + k) % len(outfits)]), [item])
            image = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA")
            for c, row in enumerate((2, 1, 0, 3)):   # down, right, up, left
                frame = image.crop((0, row * 48, 48, row * 48 + 48)).resize((48 * zoom, 48 * zoom), Image.NEAREST)
                sheet.paste(frame, ((k * 4 + c) * 48 * zoom, r * 48 * zoom), frame)
    sheet.save(out)
    print(f"wrote {out}: {', '.join(i['id'] for i in worn)}")


if __name__ == "__main__":
    import sys
    if len(sys.argv) > 2 and sys.argv[1] == "--capes":
        capes(sys.argv[2])
    elif len(sys.argv) > 2 and sys.argv[1] == "--trinkets":
        trinket_sheet(sys.argv[2])
    elif len(sys.argv) > 2 and sys.argv[1] == "--hats":
        hat_sheet(sys.argv[2])
    elif len(sys.argv) > 3 and sys.argv[1] == "--wear":
        wear_sheet(sys.argv[2], sys.argv[3].split("+"))
    else:
        main(sys.argv[1] if len(sys.argv) > 1 else "gear-preview.png")
