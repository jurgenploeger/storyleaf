#!/usr/bin/env python3
"""Pixel art in Retro Diffusion's look, drawn in code: the rules docs/pixel-style.md measures, as a renderer.

A sprite is a list of shapes (ellipses, polygons, thick strokes) in the sprite's own pixels, back to front,
each of a material: a base colour and how its surface takes light. The kit renders them at SS× size, lit
from the top left (each shape bulges as its profile says: a dome, a cylinder along a stroke, flat, or cut
facets like a gem), adds the material's surface texture and a contact shadow under whatever lies on top,
then brings it down to the sprite's size, each pixel on its material's ramp: a few shades whose shadows
lean to blue and highlights to yellow, as RD's do. Then the house outline round the silhouette, a darker
line where one material meets the one over it, and a speck of highlight on anything glossy.

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

SS = 4                                   # supersampling: shapes are rendered this many times larger
OUTLINE = (35, 24, 52)                   # the item icons' house outline (tools/item_art.py OUTLINE)
LIGHT = np.array([-0.55, -0.7, 0.9])     # from the top left, a little in front
LIGHT = LIGHT / np.linalg.norm(LIGHT)
HALF = (LIGHT + np.array([0, 0, 1.0])) / np.linalg.norm(LIGHT + np.array([0, 0, 1.0]))

SHADOW_HUE, LIGHT_HUE = 245.0, 50.0      # shadows lean to blue-violet, highlights to warm yellow


def _rgb(hexcode):
    h = hexcode.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def _toward(h, target, amount):
    """Hue `h` turned up to `amount` degrees toward `target`, the short way, never past it."""
    d = (target - h + 180) % 360 - 180
    return (h + max(-abs(d), min(abs(d), amount)) * (1 if d >= 0 else -1)) % 360


def ramp(base, n=6, shift_dark=24.0, shift_light=14.0):
    """`n` shades of `base`, dark to light. The base sits a little above the middle; shadows go deeper,
    more saturated and toward blue; highlights paler and toward yellow. Greys (metal, stone) get a cool
    tint in shadow and a warm one in light, so they aren't dead grey."""
    r, g, b = _rgb(base) if isinstance(base, str) else base
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    h *= 360
    grey = s < 0.1
    out = []
    for i in range(n):
        t = i / (n - 1)                      # 0 darkest … 1 lightest
        k = t - 0.62                         # where the base sits
        vv = min(1.0, v * (1 + 1.25 * k)) if k < 0 else min(1.0, v + (1 - v) * 0.9 * k / 0.38 + 0.08 * k)
        vv = max(0.08, vv)
        if grey:
            hh = SHADOW_HUE if k < 0 else LIGHT_HUE
            ss = 0.16 * abs(k) / 0.62 if k < 0 else 0.07 * k / 0.38
        else:
            hh = _toward(h, SHADOW_HUE, shift_dark * -k / 0.62) if k < 0 else _toward(h, LIGHT_HUE, shift_light * k / 0.38)
            ss = min(1.0, s * (1 + 0.25 * -k / 0.62)) if k < 0 else s * (1 - 0.55 * (k / 0.38) ** 1.4)
        out.append(tuple(round(c * 255) for c in colorsys.hsv_to_rgb(hh / 360, ss, vv)))
    return out


class Material:
    """A surface: its base colour, how many shades, how bumpy (texture: noise on the light, at `grain`
    pixels), how glossy (a specular highlight), and how much it takes light at all (`relief`: 1 rounded
    by the light, 0 flat colour)."""

    def __init__(self, base, shades=8, texture=0.06, grain=1.5, gloss=0.0, relief=1.0, variety=8.0):
        self.base, self.shades, self.texture, self.grain = base, shades, texture, grain
        self.gloss, self.relief = gloss, relief
        self.colours = ramp(base, shades)
        # A sister ramp a few degrees round the wheel: the texture picks between the two, so a surface
        # carries the near-duplicate colours RD's do instead of one clean ramp (0 turns it off).
        r, g, b = _rgb(base)
        h, sat, v = colorsys.rgb_to_hsv(r, g, b)
        twin = colorsys.hsv_to_rgb(((h * 360 + variety) % 360) / 360, max(0, sat - 0.06), min(1, v * 0.97))
        self.twin = ramp(twin, shades) if variety else self.colours
        self.key = hashlib.md5(f"{base}{shades}{texture}{grain}".encode()).hexdigest()


class Sprite:
    def __init__(self, size=32, height=None):
        self.w, self.h = size, height or size
        self.shapes = []         # (mask hi-res bool, material, profile, extra)

    # --- shapes, in the sprite's own pixels -----------------------------------------------------------

    def _grid(self):
        ys, xs = np.mgrid[0:self.h * SS, 0:self.w * SS]
        return (xs + 0.5) / SS, (ys + 0.5) / SS

    def ellipse(self, cx, cy, rx, ry, mat, profile="dome", rot=0.0, bulge=1.0):
        x, y = self._grid()
        c, s = math.cos(math.radians(rot)), math.sin(math.radians(rot))
        u, v = (x - cx) * c + (y - cy) * s, -(x - cx) * s + (y - cy) * c
        self.shapes.append((u * u / rx / rx + v * v / ry / ry <= 1, mat, profile, {"centre": (cx, cy), "bulge": bulge}))
        return self

    def poly(self, points, mat, profile="dome", bulge=1.0, tone=None):
        x, y = self._grid()
        inside = np.zeros(x.shape, bool)
        pts = list(points)
        for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
            crosses = ((y0 > y) != (y1 > y)) & (x < (x1 - x0) * (y - y0) / (y1 - y0 + 1e-12) + x0)
            inside ^= crosses
        cx, cy = np.mean([p[0] for p in pts]), np.mean([p[1] for p in pts])
        self.shapes.append((inside, mat, profile, {"centre": (cx, cy), "bulge": bulge, "tone": tone}))
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
        self.shapes.append((mask, mat, profile, {"centre": (cx, cy), "bulge": bulge, "axis_dist": best / (width / 2)}))
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
        if profile == "cylinder" and "axis_dist" in extra:
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
        diffuse = np.clip(n @ LIGHT, 0, 1)
        lit = 0.08 + 0.78 * diffuse ** 1.3
        if profile == "flat":
            cx, cy = extra["centre"]
            span = max(2.0, np.sqrt(mask.sum()) / SS)
            lit = 0.55 + 0.25 * (-(x - cx) - (y - cy)) / span
        lit = (1 - mat.relief) * 0.55 + mat.relief * lit
        toned = extra.get("tone") is not None
        if toned:
            # A plane given its own light (a gem's facet, a cut face): 0 dark … 1 lit.
            lit = np.full(mask.shape, float(extra["tone"]))
        if mat.gloss and not toned:
            lit = lit + mat.gloss * np.clip(n @ HALF, 0, 1) ** 24
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
        for i, (mask, mat, *_rest) in enumerate(self.shapes):
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
            if self.shapes[i][2] == "flat" or self.shapes[i][3].get("tone") is not None:
                near_step = np.zeros_like(near_step)
            v = v + np.where(near_step, dither * 0.5, 0)
            level[sel] = np.clip(np.round(v[sel]), 0, steps)
        # Rim light and core shadow: along each shape's own edge, a step lighter where it faces the light
        # (up, left) and a step darker where it turns away (down, right), as RD rounds every form.
        for i, (_, mat, profile, _e) in enumerate(self.shapes):
            if profile == "flat" or mat.relief < 0.5 or _e.get("tone") is not None:
                continue
            sel = idx == i
            p = np.pad(sel, 1)
            up, down, left, right = p[:-2, 1:-1], p[2:, 1:-1], p[1:-1, :-2], p[1:-1, 2:]
            lit_edge = sel & (~up | ~left)
            dark_edge = sel & (~down | ~right) & ~lit_edge
            level[lit_edge] = np.minimum(level[lit_edge] + 1, mat.shades - 1)
            level[dark_edge] = np.maximum(level[dark_edge] - 1, 0)
        # A darker line where a shape meets one lying over it (on the lower one's side).
        for y in range(self.h):
            for x in range(self.w):
                i = idx[y, x]
                if i < 0:
                    continue
                for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1)):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < self.h and 0 <= xx < self.w and idx[yy, xx] > i \
                            and self.shapes[idx[yy, xx]][1] is not self.shapes[i][1]:
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
        # Highlight specks: each glossy shape's brightest pixel gets its lightest shade.
        for i, (_, mat, *_r) in enumerate(self.shapes):
            sel = np.argwhere(idx == i)
            if mat.gloss and len(sel):
                y, x = sel[np.argmax(val[idx == i])]
                out[y, x, :3] = mat.colours[-1]
        if outline:
            solid = out[..., 3] > 0
            p = np.pad(solid, 1)
            ring = ~solid & (p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:])
            for y, x in np.argwhere(ring):
                if outline == "house":
                    out[y, x] = (*OUTLINE, 255)
                else:
                    near = [idx[y + dy, x + dx] for dy, dx in ((-1, 0), (1, 0), (0, -1), (0, 1))
                            if 0 <= y + dy < self.h and 0 <= x + dx < self.w and idx[y + dy, x + dx] >= 0]
                    c = self.shapes[near[0]][1].colours[0]
                    out[y, x] = (*[int(v * 0.6) for v in c], 255)
        return Image.fromarray(out, "RGBA")


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
    import pixel_style as ps
    root = pathlib.Path(__file__).resolve().parent.parent
    tmp = target.parent / "kit"
    tmp.mkdir(exist_ok=True)
    rows = []
    for item_id, sprite in demo_sprites().items():
        new = tmp / f"item_{item_id}.png"
        sprite.render().save(new)
        old = root / "art" / "sprites" / f"item_{item_id}.png"
        verdicts = []
        for p in (old, new):
            j = ps.judge(ps.measure(p), "icon")
            ok, soft = ps.verdict(j)
            verdicts.append((ok, soft, [n for n, *_, good in j if not good]))
        rows.append((item_id, old, new, verdicts))
        print(f"{item_id:18} old: {'PASS' if verdicts[0][0] else 'FAIL'} {verdicts[0][2]}   "
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
    print(f"wrote {target} (left: as drawn now, middle: the kit, right: drawn by RD, for the look)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
