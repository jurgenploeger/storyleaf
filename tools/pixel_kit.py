#!/usr/bin/env python3
"""Pixel art in Retro Diffusion's look, drawn in code: the rules docs/pixel-style.md measures, as a renderer.

A sprite is a list of shapes (ellipses, polygons, thick strokes) in the sprite's own pixels, back to front,
each of a material: a base colour and how its surface takes light. The kit renders them at SS× size, lit
from the top left (each shape bulges as its profile says: a dome, a cylinder along a stroke, flat, or cut
facets like a gem), adds the material's surface texture and a contact shadow under whatever lies on top,
then brings it down to the sprite's size, each pixel on its material's ramp: a few shades whose shadows
turn away from yellow and highlights toward it, as RD's do. Then the house outline round the silhouette, a
darker line where one material meets the one over it, and a speck of highlight on anything glossy.

    from pixel_kit import Material, Sprite
    gem = Material("#E8508C", texture=0.04, gloss=0.9)
    s = Sprite(32)
    s.ellipse(16, 17, 10, 12, gem, profile="facet")
    s.render().save("out.png")

`tools/pixel_style.py check` scores the result against the reference; `python3 tools/pixel_kit.py
--demo out.png` redraws a few code-drawn icons and shows them beside the old ones and RD's, with scores.
Needs pillow + numpy.
"""

import colorsys
import hashlib
import math
import pathlib
import sys

import numpy as np
from PIL import Image
from PIL.ImageFilter import GaussianBlur as ImageFilterGaussian

SS = 4                                   # supersampling: shapes are rendered this many times larger
GLINT = (241, 245, 243)                  # RD's armour glint: one near-white for every metal
OUTLINE = (35, 24, 52)                   # the item icons' house outline (tools/item_art.py OUTLINE)
# The light, tuned to RD's armour icons (2026-10-23): mostly from the front, so a form is lit in its middle
# and darkens toward every edge, with a mild pull to the top left (RD's icons measure 0.12 on
# pixel_style's light_top_left; a light from the top left alone gave ours 0.52).
LIGHT = np.array([-0.17, -0.22, 1.0])
LIGHT = LIGHT / np.linalg.norm(LIGHT)
# The item icons' light since 2026-10-26 (the Potion's, `CLEAN`): from the top left, so a form is lit on its
# upper left and turns into shadow toward its lower right (the Potion measures 0.51 on light_top_left).
ITEM_LIGHT = np.array([-0.5, -0.6, 0.62])
ITEM_LIGHT = ITEM_LIGHT / np.linalg.norm(ITEM_LIGHT)

SHADOW_HUE, LIGHT_HUE = 245.0, 50.0      # shadows lean to blue-violet, highlights to warm yellow


def _rgb(hexcode):
    h = hexcode.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def _toward(h, target, amount):
    """Hue `h` turned up to `amount` degrees toward `target`, the short way, never past it."""
    d = (target - h + 180) % 360 - 180
    return (h + max(-abs(d), min(abs(d), amount)) * (1 if d >= 0 else -1)) % 360


def ramp(base, n=6, shift_dark=12.0, shift_light=7.0, wide=False):
    """`n` shades of `base`, dark to light. The base sits a little above the middle; shadows go deeper,
    more saturated and toward blue; highlights paler and toward yellow. Greys (metal, stone) get a cool
    tint in shadow and a warm one in light, so they aren't dead grey. `wide`: the clean finish's longer
    ramp, as the Potion's (its darkest red a third of its base, its lightest a pale pink): deeper shadows,
    and lights climbing most of the way to white."""
    deep, reach, fade = (1.08, 0.85, 0.5) if wide else (0.95, 0.6, 0.3)
    r, g, b = _rgb(base) if isinstance(base, str) else base
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    h *= 360
    pale = max(0.0, v - 0.7) / 0.3 * (1 - s)  # 0 … 1: how near white the colour is
    v = min(v, 0.88)                         # a base drawn in white still leaves the light somewhere to go
    grey = s < 0.1
    out = []
    # Where the base sits on the ramp: a little above the middle, lower for a pale colour (silver, snow),
    # which would otherwise have nothing left above it but white.
    pivot = 0.52 - 0.17 * max(0.0, (v - 0.8) / 0.2) * (1 - min(1.0, s * 3))
    for i in range(n):
        t = i / (n - 1)                      # 0 darkest … 1 lightest
        k = (t - pivot) * 0.62 / pivot if t < pivot else (t - pivot) * 0.38 / (1 - pivot)
        # Compressed ends, as RD's armour: the darkest shade about two fifths of the base, the lightest
        # well short of white (the glossy speck aside).
        vv = min(1.0, v * (1 + deep * k)) if k < 0 else min(1.0, v + (1 - v) * reach * k / 0.38 + 0.06 * k)
        # Pale materials (pearl, snow, silver) stay soft in shadow, never near-black.
        vv = max(0.08 + 0.4 * pale, vv)
        if grey:
            hh = SHADOW_HUE if k < 0 else LIGHT_HUE
            ss = 0.16 * abs(k) / 0.62 if k < 0 else 0.07 * k / 0.38
        else:
            # Shadows turn away from yellow and lights toward it, round the wheel the short way from this
            # colour (a blue's shadows go to violet, its lights toward cyan; a red's shadows to crimson).
            away = 1 if (h - LIGHT_HUE) % 360 < 180 else -1
            hh = (h + away * shift_dark * -k / 0.62) % 360 if k < 0 else _toward(h, LIGHT_HUE, shift_light * k / 0.38)
            ss = min(1.0, s * (1 + 0.25 * -k / 0.62)) if k < 0 else s * (1 - fade * (k / 0.38) ** 1.4)
        out.append(tuple(round(c * 255) for c in colorsys.hsv_to_rgb(hh / 360, ss, vv)))
    return out


class Material:
    """A surface: its base colour, how many shades, how bumpy (texture: noise on the light, at `grain`
    pixels), how glossy (a specular highlight), and how much it takes light at all (`relief`: 1 rounded
    by the light, 0 flat colour)."""

    def __init__(self, base, shades=6, texture=0.06, grain=1.5, gloss=0.0, relief=1.0, variety=4.0, shift=1.0,
                 wide=False):
        self.base, self.shades, self.texture, self.grain = base, shades, texture, grain
        self.gloss, self.relief = gloss, relief
        # How deep the clean finish's outline is (render outline="deep"), as a share of the darkest shade's value.
        self.outline = 0.5
        # `shift` scales how far the ramp's shadows and lights turn round the wheel (RD's buildings turn
        # theirs about twice as far as an icon's).
        self.colours = ramp(base, shades, 12.0 * shift, 7.0 * shift, wide)
        # A sister ramp a few degrees round the wheel: the texture picks between the two, so a surface
        # carries the near-duplicate colours RD's do instead of one clean ramp (0 turns it off).
        r, g, b = _rgb(base)
        h, sat, v = colorsys.rgb_to_hsv(r, g, b)
        twin = colorsys.hsv_to_rgb(((h * 360 + variety) % 360) / 360, max(0, sat - 0.06), min(1, v * 0.97))
        self.twin = ramp(twin, shades, 12.0 * shift, 7.0 * shift) if variety else self.colours
        self.key = hashlib.md5(f"{base}{shades}{texture}{grain}{shift}".encode()).hexdigest()


def deep_shade(mat):
    """The clean finish's outline colour for a material (2026-10-26, RD's Potion): a deep shade of it, about
    0.5 of the value of its darkest shade (`Material.outline`), its hue kept, a touch richer: a red's
    near-black crimson, a gold's dark umber, never the house violet."""
    r, g, b = (np.array(mat.colours[0]) / 255.0).tolist()
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    return tuple(int(c * 255) for c in colorsys.hsv_to_rgb(h, min(1.0, s * 1.1 + 0.1), max(0.05, v * mat.outline)))


class Sprite:
    def __init__(self, size=32, height=None):
        self.w, self.h = size, height or size
        self.shapes = []         # (mask hi-res bool, material, profile, extra)
        # Shapes stacked on each other cast contact shadows and get a seam where they meet; regions that
        # only touch (a restyled drawing's) don't. Rim light runs round each shape, or the silhouette.
        self.contact, self.seams, self.rim = True, True, "shape"
        # The light, if not the icons' (LIGHT): scenery stands in the world, lit more from the side.
        self.light = LIGHT
        self.overlay = None      # RGBA pixels put on top after the outline (sparkles, glows)
        # A light 2 × 2 dither where a pixel sits between two shades (off for the clean finish).
        self.dither = True
        # Which object the next shapes belong to (`part`): with seams="parts", only where one object lies
        # over another is there a line between them, in the deep outline's colour; a coin's rim and face don't
        # get one.
        self._part = 0

    def part(self):
        """Starts a new object: shapes from here on lie over the ones before as a thing of their own."""
        self._part += 1
        return self

    def _add(self, entry):
        entry[3]["part"] = self._part
        self.shapes.append(entry)

    @classmethod
    def clean(cls, size=64):
        """A sprite in the item icons' look since 2026-10-26 (docs/pixel-style.md, *Item icons*): RD's Potion.
        At 64 pixels, lit from the top left, no grain or dither, a core shadow only where a form turns from
        the light, and (render with outline="deep") a one-pixel outline in a deep shade of what it rounds.
        Give its materials `texture=0, variety=0`."""
        s = cls(size)
        s.light, s.rim, s.dither, s.seams = ITEM_LIGHT, "core", False, "parts"
        return s

    # --- shapes, in the sprite's own pixels -----------------------------------------------------------

    def _grid(self):
        ys, xs = np.mgrid[0:self.h * SS, 0:self.w * SS]
        return (xs + 0.5) / SS, (ys + 0.5) / SS

    def ellipse(self, cx, cy, rx, ry, mat, profile="dome", rot=0.0, bulge=1.0):
        x, y = self._grid()
        c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        u, v = (x - cx) * c + (y - cy) * s, -(x - cx) * s + (y - cy) * c
        self._add((u * u / rx / rx + v * v / ry / ry <= 1, mat, profile, {"centre": (cx, cy), "bulge": bulge}))
        return self

    def poly(self, points, mat, profile="dome", bulge=1.0, tone=None):
        x, y = self._grid()
        inside = np.zeros(x.shape, bool)
        pts = list(points)
        for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
            crosses = ((y0 > y) != (y1 > y)) & (x < (x1 - x0) * (y - y0) / (y1 - y0 + 1e-12) + x0)
            inside ^= crosses
        cx, cy = np.mean([p[0] for p in pts]), np.mean([p[1] for p in pts])
        self._add((inside, mat, profile, {"centre": (cx, cy), "bulge": bulge, "tone": tone}))
        return self

    def mask(self, mask, mat, height=None, detail=None):
        """A shape given as a hi-res mask, with its own height field and per-pixel light (a restyle's)."""
        ys, xs = np.nonzero(mask)
        centre = (xs.mean() / SS, ys.mean() / SS) if len(xs) else (0, 0)
        self._add((mask, mat, "dome", {"centre": centre, "bulge": 1.0, "height": height, "detail": detail}))
        return self

    def stroke(self, points, width, mat, profile="cylinder", bulge=1.0):
        """A thick line through `points`, round at the joins and ends: handles, blades' spines, straps."""
        x, y = self._grid()
        best = np.full(x.shape, np.inf)
        for (x0, y0), (x1, y1) in zip(points, points[1:]):
            dx, dy = x1 - x0, y1 - y0
            t = np.clip(((x - x0) * dx + (y - y0) * dy) / (dx * dx + dy * dy + 1e-12), 0, 1)
            best = np.minimum(best, np.hypot(x - (x0 + t * dx), y - (y0 + t * dy)))
        mask = best <= width / 2
        cx, cy = np.mean([p[0] for p in points]), np.mean([p[1] for p in points])
        self._add((mask, mat, profile, {"centre": (cx, cy), "bulge": bulge, "axis_dist": best / (width / 2)}))
        return self

    # --- rendering ------------------------------------------------------------------------------------

    @staticmethod
    def _distance(mask):
        """Distance (hi-res pixels) from each pixel to the mask's edge, by repeated erosion."""
        d = np.zeros(mask.shape, float)
        cur = mask.copy()
        step = 0
        while cur.any() and step < 400:
            step += 1
            d[cur] = step
            p = np.pad(cur, 1)
            cur = cur & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
        return d

    def _shade(self, mask, mat, profile, extra):
        """Light on one shape, 0 dark … 1 lit, at hi-res."""
        x, y = self._grid()
        if extra.get("height") is not None:
            hgt = extra["height"]
        elif profile == "cylinder" and "axis_dist" in extra:
            hgt = np.sqrt(np.clip(1 - extra["axis_dist"] ** 2, 0, 1)) * extra["bulge"]
        elif profile == "flat":
            hgt = np.zeros(mask.shape)
        else:
            # A round profile (a circle's arc from edge to middle), so the light turns across the whole
            # shape instead of only at its rim.
            d = self._distance(mask)
            t = d / max(1.0, d.max())
            hgt = np.sqrt(np.clip(1 - (1 - t) ** 2, 0, 1)) * extra["bulge"] * (d.max() / SS) * 0.7
        gy, gx = np.gradient(hgt * SS / SS)
        if profile == "facet":
            # Cut stone: each facet one plane, its normal tilted out toward its side of the centre.
            cx, cy = extra["centre"]
            ang = np.arctan2(y - cy, x - cx)
            facet = np.round(ang / (math.pi / 4)) * (math.pi / 4)
            r = np.hypot(x - cx, y - cy)
            d = self._distance(mask) / SS
            table = d > np.percentile(d[mask], 70) if mask.any() else d > 0
            tilt = np.where(table, 0.0, 0.85)
            # Height falls away from the centre, so the gradient points inward (as a dome's does).
            gx, gy = -np.cos(facet) * tilt * (r > 0), -np.sin(facet) * tilt * (r > 0)
        n = np.stack([-gx, -gy, np.ones(mask.shape)], -1)
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        diffuse = np.clip(n @ self.light, 0, 1)
        # A surface facing the light lands on the base colour (the ramp's middle), the edges turning away
        # step down into shadow; only the gloss climbs above it.
        lit = 0.05 + 0.55 * diffuse ** 2
        if self.rim == "core":
            # The clean finish's top-left light: a face looking straight out is a little over the middle of
            # its ramp, the side toward the light climbs to its top, the side away falls to its foot.
            lit = 0.1 + 0.85 * diffuse
        if profile == "flat":
            cx, cy = extra["centre"]
            span = max(2.0, np.sqrt(mask.sum()) / SS)
            lit = 0.55 + 0.25 * (-(x - cx) - (y - cy)) / span
        lit = (1 - mat.relief) * 0.55 + mat.relief * lit
        toned = extra.get("tone") is not None
        if toned:
            # A plane given its own light (a gem's facet, a cut face): 0 dark … 1 lit.
            lit = np.full(mask.shape, float(extra["tone"]))
            if self.rim == "core" and mask.any():
                # The clean finish: a plane still brightens a little toward the light across it, as the
                # Potion's glass does, so it shades in two or three bands instead of one flat tone.
                cx, cy = extra["centre"]
                span = max(2.0, np.sqrt(mask.sum()) / SS)
                lit = lit + 0.12 * (-(x - cx) - (y - cy)) / span
        if mat.gloss and not toned:
            half = (self.light + np.array([0, 0, 1.0])) / np.linalg.norm(self.light + np.array([0, 0, 1.0]))
            lit = lit + mat.gloss * 0.8 * np.clip(n @ half, 0, 1) ** 60
        if extra.get("detail") is not None:
            lit = lit + extra["detail"]
        if mat.texture:
            rng = np.random.default_rng(int(mat.key[:8], 16))
            gw, gh = int(self.w / mat.grain) + 2, int(self.h / mat.grain) + 2
            coarse = rng.random((gh, gw))
            up = np.asarray(Image.fromarray((coarse * 255).astype(np.uint8)).resize(
                (int(gw * mat.grain * SS), int(gh * mat.grain * SS)), Image.BILINEAR), float) / 255
            lit = lit + mat.texture * 2 * (up[:mask.shape[0], :mask.shape[1]] - 0.5)
        return lit

    def render(self, outline="house"):
        """The sprite as a PIL RGBA image. `outline`: "house" (the icons' one dark outline), "tinted" (each
        edge pixel a deep shade of what it rounds, as RD's creatures and scenery do) or None."""
        H, W = self.h * SS, self.w * SS
        layer = np.full((H, W), -1)
        light = np.zeros((H, W))
        for i, (mask, mat, profile, extra) in enumerate(self.shapes):
            shade = self._shade(mask, mat, profile, extra)
            layer[mask] = i
            light[mask] = shade[mask]
        # Contact shadow: what lies on top darkens what's under it, a pixel down and to the right.
        for i, (mask, mat, *_rest) in enumerate(self.shapes if self.contact else []):
            above = np.zeros((H, W), bool)
            for j in range(i + 1, len(self.shapes)):
                above |= self.shapes[j][0]
            cast = np.zeros((H, W), bool)
            cast[SS:, SS:] = above[:-SS, :-SS]
            hit = (layer == i) & cast & ~above
            light[hit] *= 0.72
        # Down to size: each pixel the shape covering most of it (if anything covers half), lit as its average.
        idx = np.full((self.h, self.w), -1)
        val = np.zeros((self.h, self.w))
        for ty in range(self.h):
            for tx in range(self.w):
                block = layer[ty * SS:(ty + 1) * SS, tx * SS:(tx + 1) * SS]
                vals, counts = np.unique(block, return_counts=True)
                best = vals[np.argmax(counts)]
                if best < 0:
                    filled = block >= 0
                    if filled.sum() < SS * SS * 0.5:
                        continue
                    vals2, counts2 = np.unique(block[filled], return_counts=True)
                    best = vals2[np.argmax(counts2)]
                idx[ty, tx] = best
                val[ty, tx] = light[ty * SS:(ty + 1) * SS, tx * SS:(tx + 1) * SS][block == best].mean()
        # Clean edges (the guides' "jaggies"): shrinking leaves one-pixel notches in straight edges and
        # one-pixel spurs on them. A gap with three or four of its neighbours filled is filled from them;
        # a pixel with one neighbour or none, sticking out of an edge, goes.
        for _ in range(2):
            filled = idx >= 0
            p4 = np.pad(idx, 1, constant_values=-1)
            nbrs = np.stack([p4[:-2, 1:-1], p4[2:, 1:-1], p4[1:-1, :-2], p4[1:-1, 2:]])
            count = (nbrs >= 0).sum(0)
            # Only a notch open to the outside: a hole inside (a charm's loop, a ring's middle) stays.
            outside = np.zeros(filled.shape, bool)
            stack = [(y, x) for y in range(self.h) for x in (0, self.w - 1) if not filled[y, x]] + \
                    [(y, x) for x in range(self.w) for y in (0, self.h - 1) if not filled[y, x]]
            for y, x in stack:
                outside[y, x] = True
            while stack:
                y, x = stack.pop()
                for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < self.h and 0 <= xx < self.w and not filled[yy, xx] and not outside[yy, xx]:
                        outside[yy, xx] = True
                        stack.append((yy, xx))
            for y, x in np.argwhere(~filled & (count == 3) & outside):
                vals = [v for v in nbrs[:, y, x] if v >= 0]
                best = max(set(vals), key=vals.count)
                idx[y, x] = best
                same = (idx == best) & (val > 0)
                val[y, x] = val[same].mean() if same.any() else 0.5
            # (Corners count: a diagonal line, a chain, touches only at its corners and isn't a spur.)
            f = np.pad(idx >= 0, 1)
            count8 = sum(f[1 + dy:f.shape[0] - 1 + dy, 1 + dx:f.shape[1] - 1 + dx].astype(int)
                         for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx)
            spur = (idx >= 0) & (count <= 1) & (count8 <= 1)
            idx[spur] = -1
        # Onto the ramps, through the material's grain at the sprite's own pixels (texture added at SS×
        # averages away) and a light 2 × 2 ordered dither, so a step between shades breaks up as RD's do
        # instead of running as a clean band.
        level = np.zeros((self.h, self.w), int)
        bayer = np.array([[0.0, 0.5], [0.75, 0.25]]) - 0.375
        yy, xx = np.mgrid[0:self.h, 0:self.w]
        dither = bayer[yy % 2, xx % 2]
        for i, (_, mat, *_r) in enumerate(self.shapes):
            sel = idx == i
            rng = np.random.default_rng(int(mat.key[8:16], 16) + i)
            # Clustered grain: noise on a 2-pixel lattice, spread to its neighbours, so it forms little
            # patches that follow the light instead of salt-and-pepper speckle.
            coarse = rng.random((self.h // 2 + 2, self.w // 2 + 2))
            blobs = np.asarray(Image.fromarray((coarse * 255).astype(np.uint8)).resize(
                ((self.w // 2 + 2) * 2, (self.h // 2 + 2) * 2), Image.BILINEAR), float)[:self.h, :self.w] / 255
            grain = (blobs - 0.5) * 2 * mat.texture * 2.2
            steps = mat.shades - 1
            v = val * steps + grain * steps
            # Dither only where a pixel sits near the middle between two shades.
            frac = v - np.floor(v)
            near_step = np.abs(frac - 0.5) < 0.18
            if self.shapes[i][2] == "flat" or self.shapes[i][3].get("tone") is not None or mat.relief == 0:
                near_step = np.zeros_like(near_step)
            if not self.dither:
                near_step = np.zeros_like(near_step)
            v = v + np.where(near_step, dither * 0.5, 0)
            level[sel] = np.clip(np.round(v[sel]), 0, steps)
        # Rim light and core shadow: along each shape's own edge, a step lighter where it faces the light
        # (up, left) and a step darker where it turns away (down, right), as RD rounds every form.
        for i, (_, mat, profile, _e) in enumerate(self.shapes):
            if profile == "flat" or mat.relief < 0.5 or _e.get("tone") is not None:
                continue
            sel = idx == i
            p = np.pad(sel if self.rim == "shape" else idx >= 0, 1)
            up, down, left, right = p[:-2, 1:-1], p[2:, 1:-1], p[1:-1, :-2], p[1:-1, 2:]
            # RD darkens a form's inner edge all the way round (the light turns away there), a step deeper
            # where it faces away from the light; no lit rim.
            edge = sel & (~up | ~left | ~down | ~right)
            if self.rim == "core":
                # The clean finish: no ring darkened all the way round (with the outline it read as a
                # border two or three pixels thick, playtesting 2026-10-26); a step darker only on the edges
                # turned from the light, below and right.
                edge = sel & (~down | ~right)
            if self.rim == "lower":
                # Foliage: only the edges turned from the light darken; a cluster's top stays lit.
                edge = sel & (~down | ~right)
            away = sel & (~down | ~right)
            level[edge] = np.maximum(level[edge] - 1, 0)
            level[away] = np.maximum(level[away] - (1 if self.rim == "silhouette" else 0), 0)
        # A darker line where a shape meets one lying over it (on the lower one's side).
        parted = np.zeros((self.h, self.w), bool)
        for y in range(self.h if self.seams else 0):
            for x in range(self.w):
                i = idx[y, x]
                if i < 0:
                    continue
                for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    yy, xx = y + dy, x + dx
                    if not (0 <= yy < self.h and 0 <= xx < self.w and idx[yy, xx] > i):
                        continue
                    if self.seams == "parts":
                        if self.shapes[idx[yy, xx]][3]["part"] != self.shapes[i][3]["part"]:
                            parted[y, x] = True
                            break
                    elif self.shapes[idx[yy, xx]][1] is not self.shapes[i][1]:
                        level[y, x] = max(0, min(level[y, x], self.shapes[i][1].shades - 1) - 2)
                        break
        out = np.zeros((self.h, self.w, 4), np.uint8)
        pick = np.random.default_rng(7).random((self.h // 2 + 2, self.w // 2 + 2))
        pick = np.kron(pick, np.ones((2, 2)))[:self.h, :self.w] > 0.5      # 2 × 2 patches of the twin ramp
        for y in range(self.h):
            for x in range(self.w):
                i = idx[y, x]
                if i >= 0:
                    mat = self.shapes[i][1]
                    out[y, x, :3] = (mat.twin if pick[y, x] else mat.colours)[level[y, x]]
                    out[y, x, 3] = 255
        # Lines inside the silhouette are softer than round it: the darkest shade of what lies beneath, not
        # the outline's deep one (in the outline's colour, a heap of coins read as cracked rock, 2026-10-26).
        for y, x in np.argwhere(parted):
            out[y, x, :3] = self.shapes[idx[y, x]][1].colours[0]
        # Highlight specks: each glossy shape's brightest pixel gets its lightest shade. Polished metal and
        # cut stone (gloss 0.8 and over) get RD's glint instead: a small cross of near-white where the
        # light hits hardest, ringed by the lightest shade, and a speck or two more on other bulges
        # (each plate of a helm or a pauldron catches its own).
        for i, (_, mat, *_r) in enumerate(self.shapes):
            sel = np.argwhere(idx == i)
            if not mat.gloss or not len(sel):
                continue
            lit_here = val[idx == i]
            y, x = sel[np.argmax(lit_here)]
            if mat.gloss >= 0.8 and len(sel) >= 30:
                # The main glint where the form faces the light: the brightest point of its upper left
                # (a plate's own lit edges lower down would pull it onto a helm's cheek).
                (y0, x0), (y1, x1) = sel.min(0), sel.max(0)
                upper_left = (sel[:, 0] <= y0 + (y1 - y0) * 0.45) & (sel[:, 1] <= x0 + (x1 - x0) * 0.6)
                if upper_left.any():
                    y, x = sel[upper_left][np.argmax(lit_here[upper_left])]
            if mat.gloss < 0.8 or len(sel) < 30:
                out[y, x, :3] = mat.colours[-1]
                continue
            def paint(yy, xx, colour):
                if 0 <= yy < self.h and 0 <= xx < self.w and idx[yy, xx] == i:
                    out[yy, xx, :3] = colour
            for dy, dx in ((-1, -1), (-1, 1), (1, -1), (1, 1)):
                paint(y + dy, x + dx, mat.colours[-1])
            for dy, dx in ((0, 0), (-1, 0), (1, 0), (0, -1), (0, 1)):
                paint(y + dy, x + dx, GLINT)
            taken = [(y, x)]
            for k in np.argsort(-lit_here):
                if len(taken) == 3 or lit_here[k] < lit_here.max() * 0.8:
                    break
                yy, xx = sel[k]
                if all(abs(yy - ty) + abs(xx - tx) >= 7 for ty, tx in taken):
                    paint(yy, xx, GLINT)
                    paint(yy, xx + 1, mat.colours[-1])
                    taken.append((yy, xx))
        if outline:
            solid = out[..., 3] > 0
            p = np.pad(solid, 1)
            ring = ~solid & (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:])
            # The house outline, deepened on a dark sprite (a navy lash) so it still reads as the edge:
            # at most half the light of what it rounds.
            house = np.array(OUTLINE, float)
            if solid.any():
                inner = np.median(out[solid][:, :3] @ np.array([0.299, 0.587, 0.114]))
                house *= min(1.0, 0.5 * inner / (house @ np.array([0.299, 0.587, 0.114])))
            for y, x in np.argwhere(ring):
                if outline == "deep":
                    # The Potion's outline (2026-10-26): one pixel, a deep shade of the material it rounds
                    # (a red's near-black crimson, a gold's dark umber), never the house violet: about 0.4
                    # of the value of that material's darkest shade, its hue kept, a touch richer.
                    inside = [(y + dy, x + dx) for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1))
                              if 0 <= y + dy < self.h and 0 <= x + dx < self.w and solid[y + dy, x + dx]]
                    mats = [self.shapes[idx[p]][1] for p in inside if idx[p] >= 0]
                    mat = max(set(mats), key=mats.count) if mats else None
                    if mat is None:
                        out[y, x] = (*house.astype(int), 255)
                        continue
                    out[y, x] = (*deep_shade(mat), 255)
                    continue
                if outline == "house":
                    out[y, x] = (*house.astype(int), 255)
                else:
                    # A deep shade of the very pixel it rounds, its hue kept and its colour a touch
                    # richer, at about two thirds of its light (a little more on the side facing the
                    # light, less turned from it), as RD outlines its scenery and creatures: a green
                    # tree in dark green. At 0.6 of each shape's darkest shade it came out near-black
                    # (playtesting 2026-10-23; `outline_rel` in tools/pixel_style.py).
                    inside = [(dy, dx) for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1))
                              if 0 <= y + dy < self.h and 0 <= x + dx < self.w and solid[y + dy, x + dx]]
                    # Taken from the shape's own ramp at the shade of its pixels within two of it (the body,
                    # not just the darkened rim it touches; its lightest shades as one), so a material's
                    # outline holds a handful of colours, not one per pixel.
                    dy, dx = inside[0]
                    i = idx[y + dy, x + dx]
                    mat = self.shapes[i][1]
                    lit = dy > 0 or dx > 0          # the inside lies below or right: this is a top or left edge
                    near = (slice(max(0, y - 2), y + 3), slice(max(0, x - 2), x + 3))
                    body = level[near][idx[near] == i]
                    step = min(int(np.median(body)), mat.shades * 2 // 3 if lit else mat.shades // 2)
                    r, g, b_ = (np.array(mat.colours[step]) / 255.0).tolist()
                    h_, s_, v_ = colorsys.rgb_to_hsv(r, g, b_)
                    v_ = v_ * (0.9 if lit else 0.74)
                    s_ = min(1.0, s_ * 1.2 + 0.1)
                    out[y, x] = (*[int(c * 255) for c in colorsys.hsv_to_rgb(h_, s_, v_)], 255)
        if self.overlay is not None:
            on = self.overlay[..., 3] > 0
            out[on] = self.overlay[on]
        return Image.fromarray(out, "RGBA")


# --- Material presets: surfaces that bring their own detail ------------------------------------------------
#
# RD draws material detail no shape describes: the bands of plate armour, the rings of mail, rows of
# scales, folds in cloth, a seam stitched in leather, grain in wood. A preset is that detail as a pattern
# of light and shade at the sprite's own pixels (so it lands crisp, not averaged away), laid over a
# region's lighting, and the finish that goes with it (gloss, texture). Patterns follow the region:
# its top, left and long axis.

def limit_palette(img, n):
    """`img` (PIL RGBA) with at most `n` colours: the two closest (by a rough perceptual distance) merge
    into the commoner of them, over and over, so the colours that stay are ones the sprite already had
    and a rare accent (a lit window, a flower) survives while near-twins from different shapes go. RD's
    buildings hold about 18 to 35 colours; drawn shape by shape, ours held over a hundred."""
    a = np.array(img.convert("RGBA"))
    on = a[..., 3] > 0
    keys, inverse, counts = np.unique(a[on][:, :3], axis=0, return_inverse=True, return_counts=True)
    cols = keys.astype(float)
    alive = list(range(len(cols)))
    target = np.arange(len(cols))
    weight = np.array([0.30, 0.59, 0.11]) * 3
    while len(alive) > n:
        c = cols[alive]
        d = (((c[:, None, :] - c[None, :, :]) ** 2) * weight).sum(-1)
        np.fill_diagonal(d, np.inf)
        i, j = np.unravel_index(np.argmin(d), d.shape)
        keep, drop = (alive[i], alive[j]) if counts[alive[i]] >= counts[alive[j]] else (alive[j], alive[i])
        counts[keep] += counts[drop]
        target[target == drop] = keep
        alive.remove(drop)
    rgb = cols[target[inverse.ravel()]].astype(np.uint8)
    a[on, :3] = rgb
    return Image.fromarray(a, "RGBA")


def _noise(region, seed, cell=1):
    """Deterministic 0..1 noise per pixel (per `cell` × `cell` block)."""
    h, w = region.shape
    rng = np.random.default_rng(seed)
    coarse = rng.random((h // cell + 2, w // cell + 2))
    return np.kron(coarse, np.ones((cell, cell)))[:h, :w]


def _inset(region):
    """Each pixel's distance in from the region's edge, in pixels (1 on the edge)."""
    d = np.zeros(region.shape, int)
    cur = region.copy()
    k = 0
    while cur.any() and k < 40:
        k += 1
        d[cur] = k
        p = np.pad(cur, 1)
        cur = cur & p[:-2, 1:-1] & p[2:, 1:-1] & p[1:-1, :-2] & p[1:-1, 2:]
    return d


def _plate(region, ys, xs, top, left, bottom, right, seed):
    """Overlapping plates, two or three to a piece as RD draws them: each lit along its top edge and
    shadowed under the next; rivets at their ends."""
    period = max(6, (bottom - top + 1) // 3)
    r = (ys - top) % period
    t = np.where((r == period - 1) & (ys < bottom - 1), -0.5, np.where((r == 0) & (ys > top), 0.28, 0.0))
    ins = _inset(region)
    rivet = (r == 2) & (ins == 2) & (((xs - left) < 4) | ((right - xs) < 4))
    return t + np.where(rivet, 0.45, 0.0)


def _chain(region, ys, xs, top, left, bottom, right, seed):
    """Rings of mail: a dark hole in each, lit on its upper left, rows offset."""
    yy = ys - top
    xx = xs - left + (yy // 2) % 2
    hole = (yy % 2 == 1) & (xx % 2 == 1)
    lit = (yy % 2 == 0) & (xx % 2 == 0)
    return np.where(hole, -0.45, np.where(lit, 0.2, 0.0))


def _scales(region, ys, xs, top, left, bottom, right, seed):
    """Rows of scales, each lit at its top and shadowed along its round foot where the next overlaps."""
    row = (ys - top) // 3
    xo = (xs - left + 2 * (row % 2)) % 4
    yo = (ys - top) % 3
    foot = yo == 2
    return np.where(foot & ((xo == 0) | (xo == 3)), -0.48, np.where(foot, -0.26,
                    np.where((yo == 0) & (xo == 1), 0.3, 0.0)))


def _cloth(region, ys, xs, top, left, bottom, right, seed):
    """Long soft folds falling down the cloth, and the faintest weave."""
    folds = 0.17 * np.sin((xs - left) * 0.8 + (ys - top) * 0.12 + seed % 7)
    weave = np.where((xs + ys) % 2 == 0, 0.025, -0.025)
    return folds + weave


def _leather(region, ys, xs, top, left, bottom, right, seed):
    """Grain, and a seam stitched two pixels in from the edge."""
    grain = (_noise(region, seed, 1) - 0.5) * 0.18
    ins = _inset(region)
    stitch = (ins == 2) & ((xs + ys) % 2 == 0)
    return grain + np.where(stitch, 0.34, 0.0)


def _wood(region, ys, xs, top, left, bottom, right, seed):
    """Grain lines running along the wood's length, wavering a little."""
    py, px = np.nonzero(region)
    if len(px) < 3:
        return np.zeros(region.shape)
    cov = np.cov(np.stack([px, py]))
    vals, vecs = np.linalg.eigh(cov)
    ax = vecs[:, -1]                                  # the long axis
    across = -(xs - px.mean()) * ax[1] + (ys - py.mean()) * ax[0]
    waver = (_noise(region, seed, 3) - 0.5) * 1.2
    return 0.22 * np.sign(np.sin(across * 1.7 + waver)) * (np.abs(np.sin(across * 1.7 + waver)) > 0.55)


def _stone(region, ys, xs, top, left, bottom, right, seed):
    """A few cracks wandering across, and light flecks."""
    t = np.zeros(region.shape)
    rng = np.random.default_rng(seed)
    pts = np.argwhere(region)
    for _ in range(max(1, len(pts) // 90)):
        y, x = pts[rng.integers(len(pts))]
        dy, dx = rng.choice([-1, 1]), rng.choice([-1, 1])
        for _step in range(rng.integers(3, 7)):
            if 0 <= y < region.shape[0] and 0 <= x < region.shape[1] and region[y, x]:
                t[y, x] = -0.45
            if rng.random() < 0.5:
                y += dy
            else:
                x += dx
    fleck = _noise(region, seed + 1) > 0.93
    return t + np.where(fleck & (t == 0), 0.26, 0.0)


def _fur(region, ys, xs, top, left, bottom, right, seed):
    """Short strands of fur, dark and light, combed one way."""
    shift = (_noise(region, seed, 3) * 4).astype(int)
    k = (xs - ys + shift) % 4
    return np.where(k == 0, -0.22, np.where(k == 1, 0.14, 0.0))


def _crystal(region, ys, xs, top, left, bottom, right, seed):
    """Facets: a few planes, each its own tone, the edge between two lit where it faces the light."""
    rng = np.random.default_rng(seed)
    pts = np.argwhere(region)
    if len(pts) < 6:
        return np.zeros(region.shape)
    seeds = pts[rng.choice(len(pts), size=min(6, len(pts)), replace=False)]
    d = np.stack([(ys - sy) ** 2 + (xs - sx) ** 2 for sy, sx in seeds])
    cell = d.argmin(0)
    tones = rng.uniform(-0.28, 0.28, len(seeds))
    t = tones[cell]
    p = np.pad(cell, 1, mode="edge")
    ridge = (p[1:-1, 2:] != cell) | (p[2:, 1:-1] != cell)
    return t + np.where(ridge, 0.22, 0.0)


def _metal(region, ys, xs, top, left, bottom, right, seed):
    """Polished metal: a hard bright streak where it catches the light, the rest smooth."""
    across = (xs - left) + (ys - top)
    span = max(1, (right - left) + (bottom - top))
    return np.where(np.abs(across - span * 0.35) < 1.2, 0.3, 0.0)


# name: (pattern, finish overrides for the Material)
PRESETS = {
    "plate": (_plate, {"gloss": 0.9, "texture": 0.02, "variety": 3.0}),
    "chain": (_chain, {"gloss": 0.5, "texture": 0.015, "variety": 3.0}),
    "scales": (_scales, {"gloss": 0.45, "texture": 0.025}),
    "cloth": (_cloth, {"gloss": 0.0, "texture": 0.035}),
    "leather": (_leather, {"gloss": 0.15, "texture": 0.04}),
    "wood": (_wood, {"gloss": 0.0, "texture": 0.04}),
    "stone": (_stone, {"gloss": 0.0, "texture": 0.07}),
    "fur": (_fur, {"gloss": 0.0, "texture": 0.05}),
    "crystal": (_crystal, {"gloss": 0.95, "texture": 0.01, "variety": 4.0}),
    "metal": (_metal, {"gloss": 0.95, "texture": 0.03, "variety": 3.0}),
}


def preset_pattern(name, region, seed=11):
    """The preset's light and shade over `region` (1×, bool), 0 outside it."""
    if not region.any():
        return np.zeros(region.shape)
    ys, xs = np.mgrid[0:region.shape[0], 0:region.shape[1]]
    py, px = np.nonzero(region)
    t = PRESETS[name][0](region, ys, xs, py.min(), px.min(), py.max(), px.max(), seed)
    return np.where(region, t, 0.0)


# --- Restyle: an existing drawing brought to the look --------------------------------------------------

def _hsv(c):
    return colorsys.rgb_to_hsv(*(np.array(c[:3]) / 255))


def _scaled(arr, scale, src_centre, dst_centre, fill_value):
    """`arr` (hi-res) scaled by `scale` about `src_centre`, moved to `dst_centre` (nearest neighbour)."""
    H, W = arr.shape
    ys, xs = np.mgrid[0:H, 0:W]
    sy = np.round((ys + 0.5 - dst_centre[1]) / scale + src_centre[1] - 0.5).astype(int)
    sx = np.round((xs + 0.5 - dst_centre[0]) / scale + src_centre[0] - 0.5).astype(int)
    ok = (sy >= 0) & (sy < H) & (sx >= 0) & (sx < W)
    out = np.full(arr.shape, fill_value, dtype=arr.dtype)
    out[ok] = arr[sy[ok], sx[ok]]
    return out


def _deepen(base):
    """A design's colour brought to RD's depth: RD's armour sits darker and richer in its mid-tones than
    the flat designs' pastel fills (its icons' median luma 0.38 against the designs' 0.49)."""
    h, s_, v = colorsys.rgb_to_hsv(*(np.array(base[:3]) / 255))
    if v > 0.55:
        v = 0.55 + (v - 0.55) * 0.7
    if s_ > 0.15:
        s_ = min(1.0, s_ * 1.12)
    return tuple(int(round(c * 255)) for c in colorsys.hsv_to_rgb(h, s_, v))


def dominant_colour(img):
    """The main material's colour in a finished sprite (an RD armour icon): its commonest hue, at the
    middle of that hue's brightness; for a grey sprite (iron), its middle grey."""
    a = np.asarray(img.convert("RGBA")).astype(float) / 255
    on = (a[..., 3] > 0.5) & ~np.all(np.round(a[..., :3] * 255) == OUTLINE, axis=-1)
    px = a[..., :3][on]
    hsv = np.array([colorsys.rgb_to_hsv(*c) for c in px])
    sat = hsv[:, 1] > 0.15
    if sat.mean() > 0.4:
        bins = (hsv[sat, 0] * 18).astype(int) % 18
        top = np.bincount(bins, minlength=18).argmax()
        pick = hsv[sat][bins == top]
        # The median of each of hue, saturation and brightness: one desaturated pixel at the middle
        # brightness would otherwise give a ruby a dusty pink.
        hue = np.angle(np.mean(np.exp(2j * np.pi * pick[:, 0]))) / (2 * np.pi) % 1
        mid = colorsys.hsv_to_rgb(hue, float(np.median(pick[:, 1])), float(np.median(pick[:, 2])))
    else:
        lum = px @ np.array([0.299, 0.587, 0.114])
        mid = px[np.argsort(lum)[len(lum) // 2]]
    return "#%02x%02x%02x" % tuple(int(round(c * 255)) for c in mid)


def restyle(img, round_corners=0.6, texture=0.045, fill=0.84, preset=None, base=None, trim=()):
    """An icon drawn the old way (tools/item_art.py: flat three-tone fills, one outline) re-rendered in
    the look: its regions of colour become materials on hue-shifted ramps, its silhouette rounded at the
    corners, the whole lit from the top left as one form with each region swelling a little on it, the
    old drawing's own light and dark kept as detail (creases, slits, laces), textured, rim-lit and
    outlined afresh. Sparkles and soft glows are kept as drawn. `preset` (PRESETS: "plate", "chain",
    "cloth"…) is the main material's, its detail and finish laid on the biggest region; `base` (a hex
    colour) is that region's colour instead of the design's (a set piece takes its armour's)."""
    a = np.asarray(img.convert("RGBA")).copy()
    h, w = a.shape[:2]
    opaque = a[..., 3] >= 250
    outline = np.all(a[..., :3] == OUTLINE, axis=-1) & opaque
    # Sparkles (a lone pixel off the body) and glows (partly transparent) stay as they are.
    p = np.pad(opaque, 1)
    neigh = sum(p[1 + dy:h + 1 + dy, 1 + dx:w + 1 + dx] for dy in (-1, 0, 1) for dx in (-1, 0, 1) if dy or dx)
    lone = opaque & (neigh == 0)
    overlay = np.zeros_like(a)
    keep = lone | ((a[..., 3] > 0) & ~opaque)
    overlay[keep] = a[keep]
    body = opaque & ~lone
    # The old outline goes (the kit draws its own); dark lines inside the drawing stay as a material.
    q = np.pad(body, 1)
    touches_air = ~(q[:-2, 1:-1] & q[2:, 1:-1] & q[1:-1, :-2] & q[1:-1, 2:])
    body &= ~(outline & touches_air)
    # Regions: colours grouped into families by hue and saturation (a drawing's dark/mid/light of one
    # ramp land together), each family's commonest colour its base.
    keys = [tuple(c) for c in a[..., :3][body]]
    counts = {}
    for k in keys:
        counts[k] = counts.get(k, 0) + 1
    groups = []                                      # [base colour, [colours]]
    for col, _ in sorted(counts.items(), key=lambda kv: -kv[1]):
        hh, ss, vv = _hsv(col)
        home = None
        for g in groups:
            if OUTLINE in (tuple(col), tuple(g[0])):
                continue             # an opening drawn in the outline's colour is its own region, never a purple's
            gh, gs, gv = _hsv(g[0])
            dh = abs((hh - gh + 0.5) % 1 - 0.5) * 360
            grey = ss < 0.14 and gs < 0.14
            if (grey and abs(vv - gv) < 0.45) or (not grey and ss >= 0.1 and gs >= 0.1 and dh < 22 and abs(ss - gs) < 0.4):
                home = g
                break
        if home is None:
            groups.append([col, [col]])
        else:
            home[1].append(col)
    of = {c: i for i, g in enumerate(groups) for c in g[1]}
    gmap = np.full((h, w), -1)
    for y, x in zip(*np.nonzero(body)):
        gmap[y, x] = of[tuple(a[y, x, :3])]
    # Hi-res: the regions blown up, and (a drawing smaller than its tile) scaled up so it fills `fill`
    # of it, centred, as RD's icons do: re-rendered from 4×, nothing is stretched.
    big = np.kron(gmap, np.ones((SS, SS), int))
    every = (gmap >= 0) | (overlay[..., 3] > 0)
    ys, xs = np.nonzero(every)
    span = max(xs.max() - xs.min() + 1, ys.max() - ys.min() + 1) if len(xs) else w
    scale = min(1.5, fill * max(h, w) / span) if fill and span < fill * max(h, w) else 1.0
    if scale > 1.0:
        src = ((xs.min() + xs.max() + 1) / 2 * SS, (ys.min() + ys.max() + 1) / 2 * SS)
        dst = (w * SS / 2, h * SS / 2)
        big = _scaled(big, scale, src, dst, -1)
        # The 1× maps follow (the old drawing's shading, the sparkles), sampled at each pixel's middle.
        def at1(arr, fill_value):
            hi = np.kron(arr, np.ones((SS, SS) + arr.shape[2:], arr.dtype)) if arr.ndim == 2 else \
                np.repeat(np.repeat(arr, SS, 0), SS, 1)
            if hi.ndim == 2:
                moved = _scaled(hi, scale, src, dst, fill_value)
            else:
                moved = np.stack([_scaled(hi[..., k], scale, src, dst, fill_value) for k in range(hi.shape[2])], -1)
            return moved[SS // 2::SS, SS // 2::SS]
        overlay = at1(overlay, 0)
        gmap_scaled = at1(gmap, -1)
        a = np.where(gmap_scaled[..., None] >= 0, at1(a, 0), a * 0)
        gmap = gmap_scaled
    sil = Image.fromarray(((big >= 0) * 255).astype(np.uint8)).filter(ImageFilterGaussian(SS * round_corners))
    # The blur smooths the outline both ways, cutting corners and evening out dips, so the steps along a
    # slope change steadily (no jaggies); but it never closes a narrow gap (between a glove's fingers): an
    # empty pixel with the body close on both sides, across or up and down, stays empty.
    sil = np.asarray(sil) >= 128
    body = big >= 0
    gap = SS * 2
    def near(mask, axis, step):
        out = np.zeros_like(mask)
        for k in range(1, gap + 1):
            out |= np.roll(mask, step * k, axis=axis)
        return out
    narrow = ~body & ((near(body, 1, 1) & near(body, 1, -1)) | (near(body, 0, 1) & near(body, 0, -1)))
    sil &= ~narrow
    # Lines (a chain, a whip's lash) are never rounded away: a pixel with its body neighbours on opposite
    # sides (left and right, up and down, or corner to corner) is part of something thin, and stays. A
    # spur sticking out of an edge (one neighbour) is a corner, and goes.
    qb = np.pad(gmap >= 0, 1)
    n_, s_, w_, e_ = qb[:-2, 1:-1], qb[2:, 1:-1], qb[1:-1, :-2], qb[1:-1, 2:]
    nw, ne, sw, se = qb[:-2, :-2], qb[:-2, 2:], qb[2:, :-2], qb[2:, 2:]
    nb4 = n_.astype(int) + s_ + w_ + e_
    through = (n_ & s_) | (w_ & e_) | (nw & se) | (ne & sw)
    thin = (gmap >= 0) & (nb4 <= 2) & through
    sil |= np.kron(thin, np.ones((SS, SS), bool))
    cur = big.copy()
    for _ in range(SS * 3):
        empty = cur < 0
        if not (empty & sil).any():
            break
        pc = np.pad(cur, 1, constant_values=-1)
        for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
            nb = pc[1 + dy:cur.shape[0] + 1 + dy, 1 + dx:cur.shape[1] + 1 + dx]
            fill = (cur < 0) & (nb >= 0)
            cur[fill] = nb[fill]
    cur[~sil] = -1
    # Height: one round form over the silhouette, each region swelling a little on it.
    s = Sprite(w, h)
    s.contact, s.seams, s.rim = False, False, "silhouette"
    whole = s._distance(cur >= 0)
    t = whole / max(1.0, whole.max())
    height = np.sqrt(np.clip(1 - (1 - t) ** 2, 0, 1)) * (whole.max() / SS) * 0.55
    # The old drawing's own shading, as detail: each pixel's value against its region's base.
    tone = np.zeros((h, w))
    for y, x in zip(*np.nonzero(gmap >= 0)):
        g = groups[gmap[y, x]]
        vals = [_hsv(c)[2] for c in g[1]]
        spread = max(0.12, max(vals) - min(vals))
        tone[y, x] = np.clip((_hsv(a[y, x])[2] - _hsv(g[0])[2]) / spread, -1, 1)
    # Drawn dark lines (creases between fingers, seams, a slit) count double, so the new light doesn't
    # wash them out.
    detail = np.kron(np.where(tone < -0.5, tone * 2 * 0.3, tone * 0.15), np.ones((SS, SS)))
    # The main region is the biggest, leaving out a `trim` (colours drawn as a trim, a hood's fur, which
    # can outsize the cloth it edges and would take the set's colour from it).
    trims = {tuple(t[:3]) for t in trim}
    main = max(range(len(groups)), key=lambda i: (cur == i).sum()
               if tuple(groups[i][0]) != OUTLINE and not trims & {tuple(c) for c in groups[i][1]} else -1) \
        if groups else -1
    base_colour = base
    for i, (base, cols) in enumerate(groups):
        m = cur == i
        if not m.any():
            continue
        d = s._distance(m)
        own = np.sqrt(np.clip(d / max(1.0, d.max()), 0, 1)) * (d.max() / SS) * 0.3
        hh, ss, vv = _hsv(base)
        is_void = tuple(base) == OUTLINE
        is_trim = bool(trims & {tuple(c) for c in cols})
        if is_void:
            # An opening drawn in the outline's colour (a hood's, a helm's slit) is the inside of the thing:
            # the main region's own colour in shadow, on its own long ramp (its light set below), not black.
            base = (tuple(int(base_colour.lstrip("#")[k:k + 2], 16) for k in (0, 2, 4)) if base_colour
                    else _deepen(groups[main][0]))
        elif is_trim:
            pass                     # a trim keeps its drawn colours (fur stays cream)
        elif i == main and base_colour:
            base = tuple(int(base_colour.lstrip("#")[k:k + 2], 16) for k in (0, 2, 4))
        else:
            base = _deepen(base)
        bright = max(_hsv(c)[2] for c in cols)
        # Shiny stuff (glass, metal, gems: a near-white highlight drawn in it) is smooth and glossy;
        # everything else carries the surface texture.
        # (a white highlight drawn on it counts, though it lands in a group of its own).
        region = gmap == i
        po = np.pad(region, 1)
        beside = (po[:-2, 1:-1] | po[2:, 1:-1] | po[1:-1, :-2] | po[1:-1, 2:]) & ~region & (gmap >= 0)
        white_beside = any(_hsv(a[y, x])[1] < 0.15 and _hsv(a[y, x])[2] > 0.92 for y, x in zip(*np.nonzero(beside)))
        shiny = (any(_hsv(c)[1] < 0.3 and _hsv(c)[2] > 0.9 for c in cols) or (ss < 0.3 and bright > 0.85)
                 or white_beside) and not is_trim
        mat = Material("#%02x%02x%02x" % tuple(base), shades=8 if is_void else 6 if m.sum() > 40 * SS * SS else 5,
                       texture=texture * (0.45 if shiny else 0.2 if is_void else 1.0),
                       relief=0.0 if is_void else 1.0, gloss=0.6 if shiny and not is_void else 0.0,
                       variety=0.0 if is_void else (2.0 if shiny else 4.0))
        if preset and i == main:
            pattern, finish = PRESETS[preset]
            mat = Material("#%02x%02x%02x" % tuple(base), shades=mat.shades,
                           **{"texture": mat.texture, "gloss": mat.gloss, "variety": 4.0, **finish})
            region1 = (gmap == i)
            extra = np.kron(preset_pattern(preset, region1), np.ones((SS, SS)))
            # The preset's detail goes on top of the drawing's own shading (its planes and lines).
            s.mask(m, mat, height=height + own, detail=detail + extra)
        elif is_void:
            # The inside, in deep shadow but with depth, as RD paints a hood's: darkest at the back,
            # under the brim; the lower inner wall, facing up toward the light coming in, a few steps
            # lighter, and lightest along the lip where it turns out toward the opening.
            ys_, xs_ = np.nonzero(m)
            top, bottom = ys_.min(), ys_.max()
            yy, xx = np.mgrid[0:m.shape[0], 0:m.shape[1]]
            t = np.clip((yy - top) / max(1, bottom - top), 0, 1)
            rim = s._distance(m)
            near = np.clip(1 - rim / (SS * 2.5), 0, 1)
            lower = np.clip((t - 0.45) / 0.55, 0, 1)
            light = 0.0 + 0.18 * t ** 1.6 + near * (0.16 * lower - 0.05 * (1 - lower))
            s.mask(m, mat, height=np.zeros_like(height), detail=light - 0.55)
        else:
            s.mask(m, mat, height=height + own, detail=detail)
    # A trim is kept in its drawn colours, laid over the render: fur re-ramped turns from cream to a cold
    # grey (its shadows turned away from yellow), where RD's cloaks shade it toward a warm taupe.
    trim_groups = [i for i, (_, cols) in enumerate(groups) if trims & {tuple(c) for c in cols}]
    if trim_groups:
        kept = np.isin(gmap, trim_groups)
        overlay = overlay.copy()
        overlay[kept] = a[kept]
        overlay[kept, 3] = 255
    s.overlay = overlay
    return s


# --- Demo: code-drawn icons redrawn with the kit ------------------------------------------------------

def demo_sprites():
    """A few of tools/item_art.py's icons, redrawn: {item id: Sprite}."""
    out = {}

    gem = Material("#E3A22C", texture=0.1, gloss=0.8, shades=8)            # amber
    s = Sprite(32)
    # A cut gem as its planes, each with its own light: the table on top, the crown round it, the
    # pavilion below (lit on the left, in shade on the right).
    for pts, tone in (
        ([(3, 12), (9, 4), (12, 4), (9, 12)], 0.92),       # crown, left
        ([(12, 4), (20, 4), (22, 12), (9, 12)], 0.74),     # table
        ([(20, 4), (23, 4), (29, 12), (22, 12)], 0.42),    # crown, right
        ([(3, 12), (9, 12), (16, 29)], 0.6),               # pavilion, left
        ([(9, 12), (22, 12), (16, 29)], 0.34),             # pavilion, middle
        ([(22, 12), (29, 12), (16, 29)], 0.12),            # pavilion, right
    ):
        s.poly(pts, gem, profile="flat", tone=tone)
    out["amber"] = s

    agate = Material("#D9707F", texture=0.12, grain=1.2, gloss=0.5, shades=6)
    band = Material("#F2C2B8", texture=0.08, grain=1.0, gloss=0.4, shades=5)
    s = Sprite(32)
    s.ellipse(16, 16.5, 13.5, 11.5, agate)
    s.stroke([(5, 14), (12, 11), (19, 12), (27, 9)], 2.2, band)
    s.stroke([(6, 20), (13, 17), (20, 18), (27, 15)], 1.8, band)
    out["agate"] = s

    purple = Material("#7B4FC9", texture=0.05, gloss=0.35)
    gold = Material("#E5B23A", texture=0.04, gloss=0.6, shades=5)
    s = Sprite(32)
    s.poly([(9, 3), (20, 3), (20, 17), (27, 20), (29, 24), (29, 28), (9, 28)], purple)
    s.poly([(8, 3), (21, 3), (21, 7), (8, 7)], gold, bulge=0.5)            # cuff
    s.poly([(8, 25), (30, 25), (30, 29), (8, 29)], gold, bulge=0.5)        # sole
    for yy in (10, 14):                                                    # laces
        s.stroke([(12, yy), (17, yy + 1.5)], 1.3, gold)
    s.ellipse(24.5, 22.5, 1.3, 1.3, gold)                                  # toe stud
    out["amethyst_boots"] = s

    steel = Material("#8E98A8", texture=0.06, gloss=0.9, shades=6)
    visor = Material("#2C2440", texture=0.0, relief=0.4, shades=4)
    s = Sprite(32)
    s.poly([(4, 29), (4, 14), (8, 6), (16, 2), (24, 6), (28, 14), (28, 29)], purple, bulge=1.2)
    s.poly([(7, 15), (25, 15), (25, 19), (7, 19)], visor, profile="flat")
    s.stroke([(16, 2.5), (16, 14)], 2.4, gold)                              # crest
    s.stroke([(4.5, 27), (27.5, 27)], 2.2, gold)                             # rim band
    for xx in (8, 24):
        s.ellipse(xx, 23, 1.2, 1.2, gold)                                   # rivets
    out["amethyst_helm"] = s

    chain = Material("#D9A63A", texture=0.03, gloss=0.5, shades=5)
    amber = Material("#E0761F", texture=0.03, gloss=1.0, shades=7)
    s = Sprite(32)
    s.stroke([(6, 3), (16, 16), (26, 3)], 1.4, chain)
    s.ellipse(16, 21, 7.5, 7.5, chain)
    s.ellipse(16, 21, 5, 5, amber, profile="facet")
    out["amber_amulet"] = s

    blade = Material("#B9C4CF", texture=0.04, gloss=1.0, shades=6)
    grip = Material("#7A4A2A", texture=0.12, grain=1.0, shades=5)
    guard = Material("#C99A3A", texture=0.04, gloss=0.6, shades=5)
    s = Sprite(32)
    s.stroke([(9, 23), (5, 27)], 3.2, grip)
    s.ellipse(4.3, 27.8, 2.2, 2.2, guard)
    s.poly([(10, 20.5), (25.5, 5), (28, 4), (27, 6.5), (11.5, 22)], blade, profile="dome", bulge=0.8)
    s.stroke([(7, 19), (13, 25)], 2.6, guard)
    out["alloy_shortsword"] = s
    return out


def main(argv):
    if "--demo" not in argv:
        print(__doc__)
        return 0
    target = pathlib.Path(argv[argv.index("--demo") + 1])
    sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
    import io
    import tempfile
    import item_art
    import pixel_style as ps
    root = pathlib.Path(__file__).resolve().parent.parent
    tmp = pathlib.Path(tempfile.mkdtemp())
    rows = []
    for item_id, sprite in demo_sprites().items():
        new = tmp / f"item_{item_id}.png"
        sprite.render().save(new)
        # Before: the flat design as tools/item_art.py draws it, unfinished.
        old = tmp / f"flat_{item_id}.png"
        Image.open(io.BytesIO(item_art.render(item_id).png())).save(old)
        verdicts = []
        for p in (old, new):
            j = ps.judge(ps.measure(p), "icon")
            ok, soft = ps.verdict(j)
            verdicts.append((ok, soft, [n for n, *_, good in j if not good]))
        rows.append((item_id, old, new, verdicts))
        print(f"{item_id:18} flat: {'PASS' if verdicts[0][0] else 'FAIL'} {verdicts[0][2]}   "
              f"kit: {'PASS' if verdicts[1][0] else 'FAIL'} {verdicts[1][2]}")
    scale, cell = 6, 32 * 6 + 12
    # Three columns: as drawn now, the kit, and an icon RD drew (the target look), one per row.
    rd = [root / "art" / "sprites" / f"item_{i}.png" for i in
          ("iron_plate", "dragon_mail", "chain_mail", "mage_robe", "starfall_staff", "bronze_sword")]
    sheet = Image.new("RGBA", (cell * 3 + 16, cell * len(rows)), (58, 58, 70, 255))
    for r, (_, old, new, _) in enumerate(rows):
        for c, p in enumerate((old, new, rd[r % len(rd)])):
            im = Image.open(p).convert("RGBA").resize((32 * scale, 32 * scale), Image.NEAREST)
            sheet.alpha_composite(im, (c * (cell + 8) + 6, r * cell + 6))
    sheet.save(target)
    print(f"wrote {target} (left: the flat design, middle: the kit, right: drawn by RD, for the look)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
