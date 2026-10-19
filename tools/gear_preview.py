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
        # White fur round the hood's opening (and the cape's hem, drawn with the cape).
        for y in range(FRAME):
            for x in range(FRAME):
                if is_mark(b[y, x]) and hsv(tuple(b[y, x, :3]))[2] < 0.5:
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


def hat(body, out, kind, colour, trim=None):
    """A festive hat on the head (GearOverlay.hat), every frame, fitted to the head as drawn, hair and
    all: measured on the plain body (the scalp, the eyes) and on `out` before the hat goes on.
    `kind`: crown, a paper party crown round the head's widest rows over the eyes, three points up
    (RuneScape's party hats); santa, a red cap with a white fur brim there and a pom, over all the hair
    above, its tip flopped back; ears, a bunny's, out of the hair and as tall over it whatever the hair,
    pink inside (`trim`) from the front; mask, the face in the mask's colour (`colour`, shaded as the
    skin was) with hollow eyes and a toothy grin, from the front and the side."""
    col = hexc(colour)
    acc = hexc(trim) if trim else np.array([1.0, 1.0, 1.0])
    white, grey = np.array([0.98, 0.98, 1.0]), np.array([0.80, 0.82, 0.88])
    hollow = np.array([0.08, 0.05, 0.08])
    for row, facing in enumerate(DIRS):
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
            back = {'right': -1, 'left': 1, 'down': 1, 'up': -1}[facing]
            drawn = f[..., 3] > 0.5     # the head as drawn, hair and all, before the hat goes on

            def around(y):
                """The head as drawn on row `y`: the run through its middle, hair and all, never
                narrower than the scalp and its outline. A hat measured on the scalp alone came out
                smaller than any hair round it."""
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

            # The eyes: gaps in the face's skin (none from behind). The hat's brim sits on the widest
            # row of the head as drawn, hair and all, at least two rows over them: worn round the
            # head, not perched on top of it.
            # Never lower than three fifths of the way from the scalp's top to the eyes: a cowl or a
            # helmet round the face is wide all the way down.
            skin = {(y, x) for y, x in cells}
            eyes = [y for y, x in cells if y > top + 2 and (y, x + 1) not in skin
                    and ((y, x + 2) in skin or (y, x + 3) in skin)]
            eye = min(eyes) if eyes else top + max(4, (chin - top) // 2)
            deep = min(eye - 2, top + max(2, (eye - top) * 3 // 5))
            crown_top = min((y for y in range(FRAME) if drawn[y, max(0, left):right + 1].any()), default=top)
            widths = {y: around(y)[1] - around(y)[0] for y in range(crown_top, deep + 1)}
            brim = max(widths, key=lambda y: (widths[y], y)) if widths else top + 1

            def crest(x0, x1):
                """The highest row drawn over columns x0 to x1 (the top of the hair there)."""
                rows = [y for y in range(FRAME) if drawn[y, max(0, x0):min(FRAME, x1 + 1)].any()]
                return min(rows) if rows else top

            def put(x, y, cc):
                if 0 <= x < FRAME and 0 <= y < FRAME:
                    f[y, x, :3] = cc
                    f[y, x, 3] = 1

            def stamp(parts):
                """Each part (cells, colour for a cell, its outline) filled, in order, outlined where
                the hat meets the outside."""
                whole = set().union(*(cells for cells, _, _ in parts))
                for cells, fill, line in parts:
                    for x, y in cells:
                        edge = any((x + dx, y + dy) not in whole for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
                        put(x, y, line if edge else fill(x, y))

            if kind == 'crown':
                # A band round the head at the scalp's top, as wide as the head is there, hair and
                # all; three points up from its top row.
                shape = {(x, y) for y in (brim - 2, brim - 1, brim) for x in range(around(y)[0], around(y)[1] + 1)}
                l, r = around(brim - 2)
                peaks = [l + 2, (l + r) // 2, r - 2]
                for x in range(l, r + 1):
                    rise = max(0, 4 - 2 * min(abs(x - p) for p in peaks))
                    for y in range(brim - 2 - rise, brim - 2):
                        shape.add((x, y))
                light = mix(col, (1, 1, 1), 0.4)
                stamp([(shape, lambda x, y: shade(col, 0.75) if y == brim else light if y == brim - 2 else col, shade(col, 0.42))])
            elif kind == 'santa':
                # A white fur brim round the head, hair and all; the cap over everything above it,
                # narrowing and flopping over to the back.
                band = {(x, y) for y in (brim - 2, brim - 1, brim) for x in range(around(y)[0] - 1, around(y)[1] + 2)}
                l, r = around(brim - 2)
                half = (r - l) / 2
                # Up from the brim to past the top of the hair, narrowing; everything drawn up there
                # is under the cap.
                rise = max(8, brim - 2 - crown_top + 3)
                cap = {(x, y) for y in range(crown_top, brim - 2) for x in range(FRAME)
                       if drawn[y, x] and around(y)[0] <= x <= around(y)[1]}
                for k in range(1, rise + 1):
                    w = half * (1 - (k - 1) / (rise + 0.5))
                    mid = (l + r) / 2 + back * ((k - 1) ** 2) / (10 * rise / 8)
                    for x in range(half_up(mid - w), half_up(mid + w) + 1):
                        cap.add((x, brim - 2 - k))
                tip = (half_up((l + r) / 2 + back * (((rise - 1) ** 2) / (10 * rise / 8) + 0.4)), brim - 2 - rise)
                pom = {(tip[0] + dx, tip[1] + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if abs(dx) + abs(dy) < 2}
                dark = shade(col, 0.72)
                stamp([(cap, lambda x, y: dark if (x - (l + r) / 2) * back > half * 0.4 else col, shade(col, 0.42)),
                       (band, lambda x, y: grey if y == brim else white, grey * 0.62),
                       (pom, lambda x, y: white, grey * 0.62)])
            elif kind == 'ears':
                # Two tall ears from the head, leaning out a little; pink inside, seen from the front.
                spots = {'down': (cx - 4, cx + 2), 'up': (cx - 4, cx + 2), 'right': (cx - 3, cx), 'left': (cx - 1, cx + 2)}[facing]
                parts = []
                for n, x0 in enumerate(spots):
                    lean = -1 if n == 0 else 1
                    shape, inner = set(), set()
                    # Out of the hair there (or the scalp), as tall over it whatever the hair is like.
                    hair = crest(x0, x0 + 3)
                    base = min(top + 1, hair + 2)
                    length = base - min(top - 9, hair - 7)
                    for k in range(0, length + 1):
                        y = base - k
                        dx = lean * (k // 5)
                        width = 2 if k >= length - 1 else 3
                        for x in range(x0 + dx, x0 + dx + width + 1):
                            shape.add((x, y))
                        if facing == 'down' and 2 <= k <= length - 2:
                            inner.add((x0 + dx + 1 + n, y))
                    parts.append((shape, lambda x, y, inner=inner: acc if (x, y) in inner else col, shade(col, 0.55)))
                stamp(parts)
            elif kind == 'mask':
                if facing == 'up':
                    continue
                face = {(x, y) for y, x in cells if y < chin}
                for x, y in face:
                    hh, s, v = hsv(tuple(f[y, x, :3]))
                    if (hh <= 40 / 360 or hh >= 342 / 360) and 0.12 < s < 0.65 and v > 0.55:
                        f[y, x, :3] = np.clip(col * (0.3 + v * 0.8), 0, 1)
                # The eyes (what wasn't skin on the face) as hollows, a row deeper; a grin at the chin.
                eyes = [(x, y) for y in range(top, chin) for x in range(FRAME)
                        if (x, y) not in face and any((x + dx, y) in face for dx in (-1, 1)) and any((x, y + dy) in face for dy in (-1, 1))]
                for x, y in eyes:
                    put(x, y, hollow)
                    if (x, y - 1) in face:
                        put(x, y - 1, hollow)
                mouth = chin - 1
                row_ = sorted(x for x, y in face if y == mouth)
                if row_:
                    if facing == 'down':
                        teeth = range(cx - 2, cx + 3)
                    elif facing == 'right':
                        teeth = range(row_[-1] - 3, row_[-1])
                    else:
                        teeth = range(row_[0] + 1, row_[0] + 4)
                    for x in teeth:
                        if (x, mouth) in face:
                            put(x, mouth, hollow if abs(x - cx) % 2 else mix(col, (1, 1, 1), 0.7))
    return out


def cape(base, out, colour, trim):
    """A status cape over whatever is worn (GearOverlay.drape): from behind, hung from the shoulders
    (0.38 of the way from the top of the head to the feet) nearly to the feet, widening, its trim
    along the hem and a diamond emblem, the hair falling over its top; from the front and the side,
    past the body's outline, a clasp at the collar."""
    col, acc = hexc(colour), hexc(trim)
    dark, light = shade(col, 0.62), mix(col, (1, 1, 1), 0.3)
    outline = np.array([0.16, 0.12, 0.18])
    for row, facing in enumerate(DIRS):
        for c in range(base.shape[1] // FRAME):
            oy, ox = row * FRAME, c * FRAME
            f = out[oy:oy + FRAME, ox:ox + FRAME]
            b = base[oy:oy + FRAME, ox:ox + FRAME]
            a = b[..., 3] > 0.5
            rows = np.nonzero(a.any(1))[0]
            if len(rows) == 0 or rows[-1] - rows[0] <= 8:
                continue
            top, feet = rows[0], rows[-1]
            shoulder = top + int(round((feet - top) * 0.38))
            hem = feet - 3
            xs = np.nonzero(a[shoulder])[0]
            if hem <= shoulder + 2 or len(xs) == 0:
                continue
            left, right = xs.min(), xs.max()
            cx = (left + right) // 2

            def put(x, y, cc, only_empty=False):
                if 0 <= x < FRAME and 0 <= y < FRAME and (not only_empty or not a[y, x]):
                    f[y, x, :3] = cc
                    f[y, x, 3] = 1

            def hair(x, y):
                if y >= shoulder + 11 or not (0 <= x < FRAME and 0 <= y < FRAME) or not a[y, x]:
                    return False
                hh, ss, vv = hsv(tuple(b[y, x, :3]))
                return 10 <= hh * 360 <= 65 and ss > 0.4 and vv > 0.6

            if facing == 'up':
                for y in range(shoulder, hem + 1):
                    widen = (y - shoulder) // 4
                    lo, hi = left + 1 - widen, right - 1 + widen
                    for x in range(lo, hi + 1):
                        if lo < hi and not hair(x, y):
                            put(x, y, outline if x in (lo, hi) or y == hem else acc if y == hem - 1
                                else light if x == lo + 1 else dark if x == hi - 1 else col)
                emblem = shoulder + 6
                for dy in range(-2, 3):
                    for dx in range(abs(dy) - 2, 3 - abs(dy)):
                        if not hair(cx + dx, emblem + dy):
                            put(cx + dx, emblem + dy, acc if abs(dx) + abs(dy) < 2 else shade(acc, 0.7))
                continue
            for y in range(shoulder + 1, hem + 1):
                xs = np.nonzero(a[y])[0]
                if len(xs) == 0:
                    continue
                l, r = xs.min(), xs.max()
                flare = 1 + (y - shoulder) // 4
                if facing == 'down':
                    spots = [(l - flare, True), (r + flare, True)] + [s for k in range(1, flare) for s in ((l - k, False), (r + k, False))]
                elif facing == 'right':
                    spots = [(l - flare - 1, True)] + [(l - k, False) for k in range(1, flare + 1)]
                else:
                    spots = [(r + flare + 1, True)] + [(r + k, False) for k in range(1, flare + 1)]
                for x, outer in spots:
                    put(x, y, outline if outer else acc if y == hem else col, only_empty=True)
            if facing == 'down':
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


def dressed(race, body, style, armour=None, worn=()):
    """A hero as the game draws them (GameSession.layers and registerArt): paper-doll layers, or an
    armour's own sheet over the hair from a fifth of the way down the head (nape_*); then the cut,
    and the gloves, boots, necklace and festive hat in `worn`, found on the plain body the armour is
    drawn on."""
    import pathlib
    import sys
    from PIL import Image
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    import palette_preview as pp
    sprites = pathlib.Path(__file__).resolve().parent.parent / "art" / "sprites"

    def load(name):
        return Image.open(sprites / f"{name}.png").convert("RGBA")
    sheet = (armour or {}).get("sheets", {}).get(race)
    if sheet:
        image = load(f"nape_{style}_{body}")
        image.alpha_composite(load(sheet))
        base = np.asarray(image).astype(float) / 255
        out = pp.recolor(base, armour["tint"]) if armour.get("tint") else base.copy()
        skeleton = f"body_{race}"
    else:
        # A festive hat sits on the hair, in place of a helmet or hood.
        hatted = any(item["type"] == "head" for item in worn)
        head = None if hatted else {"plate": "helmet", "cloak": "hood"}.get((armour or {}).get("wear"))
        image = load(f"body_{body}")
        for layer in (f"locks_{body}", f"{head}_{body}" if head else f"hair_{style}_{body}"):
            image.alpha_composite(load(layer))
        base = np.asarray(image).astype(float) / 255
        out = pp.recolor(base, armour["recolor"]) if armour and armour.get("recolor") else base.copy()
        if armour:
            out = apply(base, out, armour.get("wear"), armour.get("accent"), pattern=armour.get("pattern"))
        skeleton = f"body_{body}"
    pieces = {item["type"]: item for item in worn}
    necklace = pieces.get("necklace", {})
    plain = np.asarray(load(skeleton)).astype(float) / 255
    out = trinkets(plain, out, gloves=pieces.get("gloves", {}).get("color"),
                   boots=pieces.get("boots", {}).get("color"), necklace=necklace.get("color"), chain=necklace.get("accent"))
    if "head" in pieces:
        out = hat(plain, out, pieces["head"]["hat"], pieces["head"]["color"], pieces["head"].get("accent"))
    return out


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
    else:
        main(sys.argv[1] if len(sys.argv) > 1 else "gear-preview.png")
