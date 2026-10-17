#!/usr/bin/env python3
"""Previews each map's colour palette (theme.palette in content/maps.json) without a Mac build.

    pip install pillow numpy
    python3 tools/palette_preview.py                 # every map → palette-preview.png
    python3 tools/palette_preview.py frog_swamp moonglow -o swamp.png

Each row is a small patch of the map drawn roughly the way the game does it (isometric ground,
path, accent patch, pond, scattered props, the hero, the ambience tint and vignette): left without
the palette, right with it. The grade mirrors Recolor.grade in Fairyland/Art/Recolor.swift.
"""
import json, random, sys, math, colorsys
import numpy as np
from PIL import Image
R = str(__import__('pathlib').Path(__file__).resolve().parent.parent) + '/'
assets = {a['id']: a for a in json.load(open(R + 'art/assets.json'))['assets']}
maps = {m['id']: m for m in json.load(open(R + 'content/maps.json'))['maps']}

# ---------- colour maths (mirrors Recolor.swift) ----------
def rgb2hsv(c):
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    mx = c.max(-1); mn = c.min(-1); d = mx - mn
    h = np.zeros_like(mx)
    safe = np.where(d > 0, d, 1)
    hr = (60 * ((g - b) / safe)) % 360
    hg = 60 * ((b - r) / safe + 2)
    hb = 60 * ((r - g) / safe + 4)
    h = np.where(mx == r, hr, np.where(mx == g, hg, hb))
    h = np.where(d > 0, h, 0) % 360
    s = np.where(mx > 0, d / np.where(mx > 0, mx, 1), 0)
    return h, s, mx

def hsv2rgb(h, s, v):
    c = v * s; x = c * (1 - np.abs((h / 60) % 2 - 1)); m = v - c
    z = np.zeros_like(h)
    conds = [h < 60, h < 120, h < 180, h < 240, h < 300]
    r = np.select(conds, [c, x, z, z, x], c); g = np.select(conds, [x, c, c, x, z], z); b = np.select(conds, [z, z, x, c, c], x)
    return np.stack([r + m, g + m, b + m], -1)

def from_middle(h, rule):
    """How far each hue lies from the middle of the rule's hue window (RecolorRule.distanceFromMiddle)."""
    if 'hue' not in rule: return np.zeros_like(h)
    lo, hi = rule['hue']
    width = hi - lo if lo <= hi else hi + 360 - lo
    return (h - lo - width / 2 + 180) % 360 - 180

def recolor(img, rules):
    """img float RGBA 0..1 (straight alpha)."""
    rgb = img[..., :3]; a = img[..., 3]
    h, s, v = rgb2hsv(rgb)
    done = np.zeros(a.shape, bool) | (a == 0)
    nh, ns, nv = h.copy(), s.copy(), v.copy()
    for r in rules:
        m = (s >= r.get('minSaturation', 0.15)) & (s <= r.get('maxSaturation', 1)) & (v >= r.get('minValue', 0)) & (v <= r.get('maxValue', 1))
        if 'hue' in r:
            lo, hi = r['hue']
            m &= ((h >= lo) & (h <= hi)) if lo <= hi else ((h >= lo) | (h <= hi))
        m &= ~done
        if 'to' in r: nh = np.where(m, (r['to'] + r.get('spread', 0) * from_middle(h, r)) % 360, nh)
        elif 'shift' in r: nh = np.where(m, (h + r['shift']) % 360, nh)
        ns = np.where(m, np.minimum(1, s * r.get('saturation', 1)), ns)
        nv = np.where(m, np.minimum(1, v * r.get('value', 1)), nv)
        done |= m
    out = img.copy(); out[..., :3] = hsv2rgb(nh, ns, nv)
    return out

def hexrgb(x): x = x.lstrip('#'); return np.array([int(x[i:i + 2], 16) / 255 for i in (0, 2, 4)])

def grade(img, p):
    if not p: return img
    if p.get('recolor'): img = recolor(img, p['recolor'])
    out = img.copy(); rgb = out[..., :3]
    sat = p.get('saturation', 1)
    if sat != 1:
        h, s, v = rgb2hsv(rgb)
        s2 = np.where(s > 0.08, np.minimum(1, s * sat), s)
        rgb = hsv2rgb(h, s2, v)
    L = np.array([0.299, 0.587, 0.114])
    lum = rgb @ L
    tone = p.get('tone', 0.35)
    # Colour balance: dark pixels lean toward the shadow colour, bright ones toward the highlight
    # colour. Only the colour's offset from grey is added, so brightness stays put.
    if p.get('shadow'):
        c = hexrgb(p['shadow']); off = c - c @ L
        rgb = rgb + (tone * (1 - lum) ** 1.5)[..., None] * off
    if p.get('highlight'):
        c = hexrgb(p['highlight']); off = c - c @ L
        rgb = rgb + (p.get('glow', tone) * lum ** 1.5)[..., None] * off
    out[..., :3] = rgb.clip(0, 1)
    return out

# ---------- sprites ----------
_cache = {}
def raw(i, depth=0):
    if i in _cache: return _cache[i]
    try:
        im = np.asarray(Image.open(R + f'art/sprites/{i}.png').convert('RGBA')).astype(float) / 255
    except FileNotFoundError:
        d = assets[i]['derive']
        if d.get('layers'):
            # Paper-doll layers, each by its own rules or else the derive's, stacked (ArtLibrary.sourceImage).
            out = None
            for layer in d['layers']:
                im = recolor(raw(layer['id'], depth + 1), layer.get('recolor', d['recolor']))
                im = Image.fromarray((np.clip(im, 0, 1) * 255).astype(np.uint8), 'RGBA')
                out = im if out is None else Image.alpha_composite(out, im)
            im = np.asarray(out).astype(float) / 255
        else:
            im = recolor(raw(d['from'], depth + 1), d['recolor'])
    _cache[i] = im
    return im

def sprite(i, palette):
    im = grade(raw(i), palette)
    a = assets.get(i, {})
    scale = a.get('scale') or (assets.get(a.get('derive', {}).get('from'), {}).get('scale')) or 1
    if a.get('kind') == 'walk_sheet':
        im = im[96:144, 0:48]     # facing down
    if scale != 1:
        h, w = im.shape[:2]
        im = np.asarray(Image.fromarray((im * 255).astype(np.uint8)).resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.NEAREST)).astype(float) / 255
    return im

# ---------- map ----------
T = 44; C = math.sqrt(0.5)
def project(gx, gy): return ((gx - gy) * C, (gx + gy) * C * 0.5)

# ---------- ground (mirrors ArtLibrary.organicTile and WorldScene.makeGround) ----------
_S = 32
_py, _px = np.mgrid[0:_S, 0:_S]
_X = (_px + 0.5) / _S - 0.5; _Y = 0.5 - (_py + 0.5) / _S
_WOBBLE = 0.045 * np.sin(2 * np.pi * (2 * _X + _Y)) + 0.03 * np.sin(2 * np.pi * (3 * _Y - _X) + 1.3)
RADIUS = {'road': 0.36, 'patch': 0.42, 'water': 0.5}

M64 = (1 << 64) - 1
def variant_of(col, row):
    """Mirrors WorldScene.variant(of:)."""
    h = ((col & M64) * 0x9E3779B97F4A7C15) & M64
    h ^= ((row & M64) * 0xC2B2AE3D27D4EB4F) & M64
    h ^= h >> 29
    h = (h * 0xBF58476D1CE4E5B9) & M64
    h ^= h >> 32
    return h % 4

_variants = {}
def tile_variant(tex, index):
    """Mirrors ArtLibrary.variantPixels: the texture shifted/mirrored inside a soft frame of itself."""
    index %= 4
    if index == 0: return tex
    key = (hash(tex.tobytes()), index)
    if key in _variants: return _variants[key]
    n = tex.shape[0]
    dx, dy, mx, my = [(0, 0, 0, 0), (n // 2, n // 2, 0, 0), (n // 4, n * 5 // 8, 1, 0), (n * 5 // 8, n // 4, 0, 1)][index]
    ys, xs = np.mgrid[0:n, 0:n]
    sx = (xs + dx) % n; sy = (ys + dy) % n
    if mx: sx = n - 1 - sx
    if my: sy = n - 1 - sy
    edge = np.minimum(np.minimum(xs, ys), np.minimum(n - 1 - xs, n - 1 - ys)).astype(float)
    t = np.clip((edge - 1) / (n / 5), 0, 1); inside = (t * t * (3 - 2 * t))[..., None]
    out = tex * (1 - inside) + tex[sy, sx] * inside
    _variants[key] = out
    return out

def strokes(mask):
    pts = [(b % 3 - 1, 1 - b // 3) for b in range(9) if mask & (1 << b)]
    segs = []
    for i, p in enumerate(pts):
        segs.append((*p, *p))
        for q in pts[i + 1:]:
            if abs(p[0] - q[0]) <= 1 and abs(p[1] - q[1]) <= 1: segs.append((*p, *q))
    return segs

def seg_distance(x0, y0, x1, y1):
    dx, dy = x1 - x0, y1 - y0; L = dx * dx + dy * dy
    t = np.zeros_like(_X) if L == 0 else np.clip(((_X - x0) * dx + (_Y - y0) * dy) / L, 0, 1)
    return np.hypot(x0 + t * dx - _X, y0 + t * dy - _Y)

def organic_tile(base, layers, col=0, row=0):
    out = base.copy(); rim = 1.2 / _S
    for tex, mask, style in layers:
        if style == 'water':
            # mirrors ArtLibrary.waterDepth: soft blobs from the 5x5 water cells
            gx, gy = col + _X, row + _Y
            wobble = 0.08 * np.sin(1.7 * gx + 0.9 * gy) + 0.05 * np.sin(2.3 * gy - 1.1 * gx + 1.7) + 0.03 * np.sin(3.1 * gx + 2.9 * gy + 0.4)
            field = np.zeros_like(_X)
            for b in range(25):
                if mask & (1 << b):
                    cx, cy = b % 5 - 2, 2 - b // 5
                    field += np.exp(-((_X - cx) ** 2 + (_Y - cy) ** 2) / 0.49)
            depth = (field + wobble * 1.8 - 0.55) / 1.2
        else:
            d = np.min([seg_distance(*sg) for sg in strokes(mask)], axis=0)
            depth = RADIUS[style] + _WOBBLE - d
        on = depth > 0
        if style in ('road', 'patch'):
            shade = np.where((style == 'road') & (depth < rim), 0.72, 1.0)[..., None]
            out[on, :3] = (tex[..., :3] * shade)[on]
        else:
            foam = np.where(depth < 0.05, 0.35, 0.0)[..., None]
            out[on, :3] = (tex[..., :3] * (1 - foam) + foam)[on]
            bank = (depth <= 0) & (depth > -0.06)
            out[bank, :3] *= 0.8
        out[on, 3] = 1
    return out

def ground_tiles(m, kinds, palette, col0=0, row0=0):
    """kinds[row][col] in 'g' ground, 'p' path, 'a' accent, 'w' water, 'b' border; row 0 south."""
    th = m['theme']; N = len(kinds); Wd = len(kinds[0])
    tex = {k: grade(raw(v), palette) for k, v in (('g', th['ground']), ('p', th['path']), ('a', th.get('accent')),
                                                   ('w', th.get('water') or 'tile_water'), ('b', th.get('border'))) if v}
    patch_accent = (th.get('accentPatches') or 0) > 0 and th.get('accent') and th.get('accent') != th['ground']
    def pool_mask(r, c):
        bits = 0
        for dy in range(-2, 3):
            for dx in range(-2, 3):
                rr, cc = r + dy, c + dx
                if 0 <= rr < N and 0 <= cc < Wd and kinds[rr][cc] == 'w': bits |= 1 << ((2 - dy) * 5 + dx + 2)
        return bits
    def mask(r, c, k):
        own = kinds[r][c] == k; bits = 0
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                rr, cc = r + dy, c + dx
                hit = kinds[rr][cc] == k if 0 <= rr < N and 0 <= cc < Wd else (own and k != 'w')
                if hit: bits |= 1 << ((1 - dy) * 3 + dx + 1)
        return bits
    cache = {}; out = np.zeros((N, Wd, _S, _S, 4))
    for r in range(N):
        for c in range(Wd):
            k = kinds[r][c]
            road, pond = mask(r, c, 'p'), mask(r, c, 'w'); patch = mask(r, c, 'a') if patch_accent else 0
            if k == 'g': base = 'g'
            elif k == 'b': base = 'b' if 'b' in tex else 'g'
            elif k == 'a' and not patch_accent: base = 'a'
            else: base = 'b' if ('b' in tex and mask(r, c, 'b') & 0b010101010) else 'g'
            layers = []
            if patch: layers.append(('a', patch, 'patch'))
            if road: layers.append(('p', road, 'road'))
            if pond: layers.append(('w', pool_mask(r, c), 'water'))
            v = variant_of(c + col0, r + row0)
            if pond == 511: key = ('w', v)
            elif road == 511 and pond == 0: key = ('p', v)
            elif not layers: key = (base, v)
            elif patch == 511 and road == 0 and pond == 0: key = ('a', v)
            else: key = (base, tuple(layers), (c, r, v) if pond else None)
            if key not in cache:
                if len(key) == 2: cache[key] = tile_variant(tex[key[0]], v)
                else:
                    pick = v if pond else 0
                    cache[key] = organic_tile(tile_variant(tex[base], pick), [(tile_variant(tex[t], pick), mk, st) for t, mk, st in layers], c + col0, r + row0)
            out[r, c] = cache[key]
    return out

def blend_light(s, m):
    """Mirrors Walker.lit: SpriteKit multiplies the texture by the colour, mixed in by the strength."""
    p = m['theme'].get('palette') or {}
    if not p.get('light'): return s
    k = p.get('lightStrength', 0.4); s = s.copy()
    s[..., :3] = s[..., :3] * (1 - k) + s[..., :3] * hexrgb(p['light']) * k
    return s

def _soft(w, h):
    """SoftTextures.glow: white fading linearly to clear from the middle."""
    ys, xs = np.mgrid[0:max(1, int(h)), 0:max(1, int(w))]
    r = np.hypot((xs + 0.5) / max(1, w) * 2 - 1, (ys + 0.5) / max(1, h) * 2 - 1)
    return np.clip(1 - r, 0, 1)

def _paint(img, x0, y0, alpha, color, add):
    """Blends an alpha mask of colour into img at (x0, y0): additive light or normal paint."""
    h, w = alpha.shape; H, W = img.shape[:2]
    xa, ya = max(0, x0), max(0, y0); xb, yb = min(W, x0 + w), min(H, y0 + h)
    if xa >= xb or ya >= yb: return
    a = alpha[ya - y0:yb - y0, xa - x0:xb - x0][..., None]
    if add: img[ya:yb, xa:xb, :3] += a * color
    else: img[ya:yb, xa:xb, :3] = img[ya:yb, xa:xb, :3] * (1 - a) + a * color

def _variation(m, palette, gx, gy, seed=5):
    """Mirrors Lighting.groundVariation (smooth value noise leaning to shadow and highlight)."""
    strength = (palette or {}).get('variation', 0.12)
    if not palette or strength <= 0: return None
    rng = np.random.default_rng(seed)
    def noise(step):
        grid = rng.random((64, 64))
        fx, fy = gx / step, gy / step
        ix, iy = np.floor(fx).astype(int) % 63, np.floor(fy).astype(int) % 63
        tx, ty = fx - np.floor(fx), fy - np.floor(fy)
        tx, ty = tx * tx * (3 - 2 * tx), ty * ty * (3 - 2 * ty)
        a, b, c, d = grid[iy, ix], grid[iy, ix + 1], grid[iy + 1, ix], grid[iy + 1, ix + 1]
        return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * ty
    n = noise(7) * 0.7 + noise(3) * 0.3
    lean = (n - 0.5) * 2
    alpha = strength * np.minimum(1, np.abs(lean) * 1.6)
    dark = hexrgb(palette.get('shadow', '#333A4D')); light = hexrgb(palette.get('highlight', '#FFF2CC'))
    color = np.where((lean < 0)[..., None], dark, light)
    return alpha[..., None], color

def focus_blur(s, sy, h, W, H, amb):
    """DepthOfField.swift: scenery toward the top of the screen (and less so the bottom) is swapped
    for one of 3 blurred copies. Returns the sprite (padded when blurred), its padding and soft=True."""
    f = amb.get('focus') or {}
    blur, band, near = f.get('blur', 1.5), min(0.9, f.get('band', 0.4)), f.get('near', 0.5)
    if blur <= 0: return s, 0, False
    offset = (H / 2 - (sy - h * 0.45)) / (H / 2)          # the sprite's middle: +1 top edge, -1 bottom
    amount = min(1, max(0, (abs(offset) - band) / (1 - band)))
    amount = amount * amount * (3 - 2 * amount) * (1 if offset > 0 else near)
    level = round(amount * 3)
    if level == 0: return s, 0, False
    from PIL import ImageFilter
    sigma = blur * level / 3; pad = int(np.ceil(sigma * 2.5))
    pm = np.zeros((s.shape[0] + 2 * pad, s.shape[1] + 2 * pad, 4)); pm[pad:-pad, pad:-pad] = s
    pm[..., :3] *= pm[..., 3:]                              # blur premultiplied, like Core Image
    out = np.stack([np.asarray(Image.fromarray((pm[..., k] * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(sigma))).astype(float) / 255
                    for k in range(4)], -1)
    out[..., :3] /= np.maximum(out[..., 3:], 1e-4)
    return out.clip(0, 1), pad, True

def draw_scene(mid, palette, kinds, items, W=420, H=300, seed=3, tint=True, organic=True, light=True, origin=(0, 0), lighting=True, focus=True):
    """items: (art, col, row, scale). Walkers (walk sheets) keep their colours, lit by the map's light.
    lighting=True adds what Lighting.swift does: ground colour patches, light pools, prop shadows and
    glows, sunbeams, haze and the sun flare."""
    m = maps[mid]; rng = random.Random(seed); N = len(kinds); Wd = len(kinds[0])
    amb = m.get('ambience') or {}
    props = {p['art']: p for p in m['theme']['props']}
    if organic:
        tiles = ground_tiles(m, kinds, palette, *origin)
    else:
        th = m['theme']
        plain = {k: grade(raw(v), palette) for k, v in (('g', th['ground']), ('p', th['path']), ('a', th.get('accent')), ('w', th.get('water') or 'tile_water')) if v}
        tiles = np.array([[plain.get(k, plain['g']) for k in row] for row in kinds])
    img = np.zeros((H, W, 4)); img[..., 3] = 1; img[..., :3] = 0.1
    ox, oy = project(Wd * T / 2, N * T / 2)
    ys, xs = np.mgrid[0:H, 0:W]
    px = xs - W / 2 + ox; py = (H / 2 - ys) + oy
    diff = px / C; summ = py / (C * 0.5)
    gx = (summ + diff) / 2; gy = (summ - diff) / 2
    cc = np.floor(gx / T).astype(int); rr = np.floor(gy / T).astype(int)
    inside = (cc >= 0) & (cc < Wd) & (rr >= 0) & (rr < N)
    u = ((gx / T) % 1 * _S).astype(int).clip(0, _S - 1); v = ((1 - (gy / T) % 1) * _S).astype(int).clip(0, _S - 1)
    img[inside] = tiles[rr[inside], cc[inside], v[inside], u[inside]]
    img[..., 3] = 1
    if lighting and organic:
        var = _variation(m, palette, gx / T + origin[0], gy / T + origin[1])
        if var is not None:
            a, col = var
            img[..., :3] = np.where(inside[..., None], img[..., :3] * (1 - a) + col * a, img[..., :3])
        lp = amb.get('lightPatches')
        if lp:
            density = lp['count'] / (m['width'] * m['height'])
            for _ in range(max(1, int(density * N * Wd))):
                w = rng.uniform(*(lp.get('size') or [60, 140])); a = _soft(w, w * 0.5) * lp.get('alpha', 0.2)
                _paint(img, rng.randint(0, W) - int(w / 2), rng.randint(0, H) - int(w / 4), a, hexrgb(lp['color']), True)
    def screen(c, r):
        x, y = project((c + 0.5) * T, (r + 0.5) * T)
        return x - ox + W / 2, H / 2 - (y - 4 - oy)
    drawn = []
    for art, c, r, scale in sorted(items, key=lambda t: screen(t[1], t[2])[1]):   # back first, like the game
        walker = assets[art]['kind'] == 'walk_sheet'
        s = sprite(art, None if walker else palette)
        if walker and light: s = blend_light(s, m)
        if scale != 1:
            h, w = s.shape[:2]
            s = np.asarray(Image.fromarray((s * 255).astype(np.uint8)).resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.NEAREST)).astype(float) / 255
        h, w = s.shape[:2]
        sx, sy = screen(c, r)
        if walker: foot = 0
        else:   # WorldScene.foot(of:): scenery stands on its lowest opaque row
            rows = np.where((s[..., 3] > 0.5).any(1))[0]
            foot = (h - 1 - rows[-1]) / h if len(rows) else 0
        x0 = int(sx - w / 2 + (0 if walker else rng.randint(-7, 7))); y0 = int(sy - h * (0.95 - min(0.45, foot)))
        drawn.append((art, s, x0, y0, w, h, walker, 0))
    if lighting:
        for art, s, x0, y0, w, h, walker, _ in drawn:   # shadows lie under everything that stands
            if props.get(art, {}).get('shadow'):
                sw = w * 0.8
                _paint(img, int(x0 + w / 2 - sw / 2 + sw * 0.12), int(y0 + h * 0.95 - sw * 0.18 + 1), _soft(sw, sw * 0.36) * 0.3, np.zeros(3), False)
    if focus and lighting:
        for i, (art, s, x0, y0, w, h, walker, _) in enumerate(drawn):
            if walker: continue
            b, pad, soft = focus_blur(s, y0 + h * 0.95, h, W, H, amb)
            if soft: drawn[i] = (art, b, x0, y0, w, h, walker, pad)
    for art, s, x0, y0, w, h, walker, pad in drawn:
        g = props.get(art, {}).get('glow') if lighting else None
        if g:
            gw, gh = w * 1.9, w * 1.5
            _paint(img, int(x0 + w / 2 - gw / 2), int(y0 + h * 0.95 - h * 0.4 - gh / 2), _soft(gw, gh) * 0.38, hexrgb(g), True)
        x0 -= pad; y0 -= pad; h2, w2 = s.shape[:2]   # a blurred copy is padded on every side
        xa, ya = max(0, x0), max(0, y0); xb, yb = min(W, x0 + w2), min(H, y0 + h2)
        if xa >= xb or ya >= yb: continue
        part = s[ya - y0:yb - y0, xa - x0:xb - x0]
        al = part[..., 3:] if pad else (part[..., 3:] > 0.5).astype(float)
        img[ya:yb, xa:xb, :3] = img[ya:yb, xa:xb, :3] * (1 - al) + part[..., :3] * al
    if lighting:
        sb = amb.get('sunbeams')
        if sb:
            density = sb['count'] / (m['width'] * m['height'])
            for _ in range(max(1, int(density * N * Wd * 1.5))):
                w = rng.uniform(*(sb.get('size') or [30, 70])); beam = _soft(w, w * 7) * sb.get('alpha', 0.12)
                beam = np.asarray(Image.fromarray((beam * 255).astype(np.uint8)).rotate(26, expand=True, resample=Image.BILINEAR)).astype(float) / 255
                _paint(img, rng.randint(-40, W), rng.randint(-int(w * 5), H - int(w * 3)), beam, hexrgb(sb['color']), True)
    if tint:
        tc, ta = amb.get('tint'), amb.get('tintAlpha', 0.15)
        if tc: img[..., :3] = img[..., :3] * (1 - ta) + hexrgb(tc) * ta
        if lighting and amb.get('haze'):
            hz = np.clip(1 - ys / (H * 0.55), 0, 1)
            hz = np.where(hz > 0.55, 0.35 + (hz - 0.55) / 0.45 * 0.65, hz / 0.55 * 0.35) * amb.get('hazeAlpha', 0.2)
            img[..., :3] = img[..., :3] * (1 - hz[..., None]) + hexrgb(amb['haze']) * hz[..., None]
        if lighting and amb.get('sun'):
            sun = (W / 2 - W * 0.42, H / 2 - H * 0.45)
            for size, alpha, along in [(1.1, 0.4, 0), (0.2, 0.1, 0.45), (0.12, 0.08, 0.7), (0.3, 0.05, 1.3)]:
                side = H * size; cx = W / 2 + (sun[0] - W / 2) * (1 - along); cy = H / 2 + (sun[1] - H / 2) * (1 - along)
                _paint(img, int(cx - side / 2), int(cy - side / 2), _soft(side, side) * alpha, hexrgb(amb['sun']), True)
        vg = amb.get('vignette', 0)
        if vg:
            d = np.sqrt(((xs - W / 2) / (W * 0.62)) ** 2 + ((ys - H / 2) / (H * 0.62)) ** 2)
            f = (np.clip(d - 0.35, 0, 1) / 0.65) ** 1.6 * vg
            img[..., :3] *= (1 - f)[..., None]
    return Image.fromarray((img[..., :3].clip(0, 1) * 255).astype(np.uint8))

def render(mid, palette, W=420, H=300, seed=3, tint=True, organic=True, light=True, sizes=True):
    """A small made-up patch of the map: a winding path, an accent patch, a pond, props and the hero."""
    m = maps[mid]; th = m['theme']; rng = random.Random(seed)
    N = 16
    kinds = [['g'] * N for _ in range(N)]
    col = N // 2
    for r in range(N):
        kinds[r][col] = 'p'
        if rng.random() < 0.3: col = max(2, min(N - 3, col + rng.choice([-1, 1]))); kinds[r][col] = 'p'
    if th.get('accent'):
        cx, cy = rng.randrange(2, 6), rng.randrange(8, 13)
        for r in range(N):
            for c in range(N):
                if (c - cx) ** 2 + (r - cy) ** 2 < 6 and kinds[r][c] == 'g': kinds[r][c] = 'a'
    if th.get('water'):
        cx, cy = rng.randrange(10, 13), rng.randrange(2, 6)
        for r in range(N):
            for c in range(N):
                if (c - cx) ** 2 + (r - cy) ** 2 < 5 and kinds[r][c] == 'g': kinds[r][c] = 'w'
    items, occupied, pool = [], set(), []
    for p in th['props']:
        if not p.get('within'): pool += [p] * max(1, min(6, p['count'] // 6))
    rng.shuffle(pool)
    for p in pool[:34]:
        for _ in range(20):
            c, r = rng.randrange(N), rng.randrange(N)
            if kinds[r][c] == 'g' and (c, r) not in occupied and abs(c - N / 2) + abs(r - N / 2) > 2: break
        else: continue
        occupied.add((c, r))
        lo, hi = p.get('size', [1, 1]) if sizes else (1, 1)
        items.append((p['art'], c, r, rng.uniform(lo, hi)))
    items.append(('player_walk', N // 2 - 1, N // 2, 1))
    return draw_scene(mid, palette, kinds, items, W, H, seed, tint, organic, light)

if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Preview map palettes.')
    parser.add_argument('maps', nargs='*', help='map ids (default: all)')
    parser.add_argument('-o', '--out', default='palette-preview.png')
    args = parser.parse_args()
    ids = args.maps or list(maps)
    W, H = 420, 280
    sheet = Image.new('RGB', (W * 2 + 12, (H + 8) * len(ids)), (20, 20, 24))
    for n, mid in enumerate(ids):
        sheet.paste(render(mid, None, W, H), (0, n * (H + 8)))
        sheet.paste(render(mid, maps[mid]['theme'].get('palette'), W, H), (W + 12, n * (H + 8)))
    sheet.save(args.out)
    print('wrote', args.out)
