"""Renders songs from content/music.json to WAV files: the same algorithm as Storyleaf/Audio/SongSynth.swift,
written with numpy + scipy so songs can be tuned and listened to without a Mac.

    python3 tools/music_preview.py town battle        # writes music-preview/town.wav, battle.wav
    python3 tools/music_preview.py --all --seconds 30

Songs use music.json notation: `C5:2 F#5:1 Bb4:4 -:2`, chords `C4+E4+G4:4`, drums `K:1 S:1 H:1 T C R N`.
A step is an eighth note. Legacy tracks with "wave" square/triangle/noise render as before.
"""
import json, math, re
import numpy as np
from scipy.signal import lfilter

SR = 44100
SEMI = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}

def freq(name):
    m = re.fullmatch(r'([A-G])([#b]?)(-?\d)', name)
    if not m: return None
    s = SEMI[m.group(1)] + (1 if m.group(2) == '#' else -1 if m.group(2) == 'b' else 0)
    midi = 12 * (int(m.group(3)) + 1) + s
    return 440 * 2 ** ((midi - 69) / 12)

def parse(notes):
    out = []
    for tok in notes.split():
        if tok == '|' or ':' not in tok: continue
        name, steps = tok.rsplit(':', 1)
        out.append((name, int(steps)))
    return out

RNG = np.random.default_rng(7)

def noise(n): return RNG.uniform(-1, 1, n)
def onepole_lp(x, a): return lfilter([a], [1, -(1 - a)], x)

def pitched(inst, f, gate, n_total):
    """One strike of a pitched instrument: `gate` samples held, then its release."""
    rel = int(inst.get('release', 0.2) * SR)
    n = min(n_total, gate + rel)
    t = np.arange(n) / SR
    age = np.arange(n)
    a = np.minimum(1, age / max(1, inst.get('attack', 0.005) * SR))
    r = np.where(age < gate, 1.0, np.exp(-4.6 * (age - gate) / max(1, rel)))
    vib = np.ones(n)
    if inst.get('vibrato'):
        depth, rate, delay = inst['vibrato']
        ramp = np.clip((t - delay) / 0.3, 0, 1)
        vib = 2 ** (depth / 12 * np.sin(2 * np.pi * rate * t) * ramp)
    voices = inst.get('voices', 1)
    cents = inst.get('detune', 0)
    dets = [0.0] if voices == 1 else [(-cents if i == 0 else cents) if voices == 2 else (-cents, 0, cents)[i] for i in range(voices)]
    wave = np.zeros(n)
    for ratio, amp, decay in inst['partials']:
        level = amp * np.exp(-decay * t)
        for d in dets:
            mul = 2 ** (d / 1200)
            phase = np.cumsum(f * ratio * mul * vib / SR)
            wave += level * np.sin(2 * np.pi * phase)
    wave /= len(dets)
    if inst.get('breath'):
        wave += onepole_lp(noise(n), 0.08) * inst['breath'] * 3
    if inst.get('click'):
        wave += noise(n) * inst['click'] * np.exp(-age / (0.008 * SR))
    return wave * a * r * inst.get('gain', 0.5)

def drum(letter, n_total):
    n = min(n_total, int(1.2 * SR)); t = np.arange(n) / SR
    if letter == 'K':
        f = 48 + 110 * np.exp(-t / 0.035)
        w = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.28) + noise(n) * 0.2 * np.exp(-t / 0.003)
    elif letter == 'S':
        w = onepole_lp(noise(n), 0.35) * 0.8 * np.exp(-t / 0.11) + np.sin(2 * np.pi * 190 * t) * 0.25 * np.exp(-t / 0.04)
    elif letter in ('H', 'N'):
        x = noise(n); w = (x - onepole_lp(x, 0.3)) * np.exp(-t / 0.035) * 0.8
    elif letter == 'T':
        x = noise(n); w = (x - onepole_lp(x, 0.3)) * np.exp(-t / 0.12) * (0.6 + 0.4 * (np.sin(2 * np.pi * 23 * t) > 0))
    elif letter == 'C':
        x = noise(n); w = (x - onepole_lp(x, 0.2)) * np.exp(-t / 0.9) * 0.5
    elif letter == 'R':
        x = noise(n); w = (x - onepole_lp(x, 0.3)) * np.exp(-t / 0.018) * 0.7
    else:
        w = np.zeros(n)
    return w

def legacy(wave, duty, f, gate, n_total):
    """The old chiptune voices, for comparison."""
    n = min(n_total, gate); age = np.arange(n); t = age / SR
    if wave == 'noise':
        return np.sign(noise(n)) * np.exp(-age / (0.035 * SR))
    ph = (f * t) % 1
    raw = np.where(ph < duty, 1.0, -1.0) if wave == 'square' else 4 * np.abs(ph - 0.5) - 1
    sus = 0.9 if wave == 'triangle' else 0.55
    env = np.minimum(1, age / (0.004 * SR)) * (sus + (1 - sus) * np.exp(-age / (0.18 * SR)))
    env *= np.minimum(1, (gate - age) / (0.02 * SR))
    return raw * env

# ---------------- reverb: Freeverb-style, 4 combs + 2 allpasses per side (mirrors SongSynth.swift)
COMBS = [1116, 1188, 1277, 1356]
ALLPASS = [556, 441]
def comb(x, delay, fb=0.84, damp=0.25):
    """Freeverb comb, block by block: y[n] = x[n-D] + fb * lp[n-D], lp[n] = (1-damp) * y[n] + damp * lp[n-1]."""
    n = len(x); y = np.zeros(n); lp = np.zeros(n); z = np.zeros(1)
    for start in range(0, n, delay):
        end = min(n, start + delay)
        prev = start - delay
        yb = (x[prev:prev + (end - start)] if prev >= 0 else np.zeros(end - start)) + (fb * lp[prev:prev + (end - start)] if prev >= 0 else 0)
        y[start:end] = yb
        lp[start:end], z = lfilter([1 - damp], [1, -damp], yb, zi=z)
    return y

def allpass(x, delay, g=0.5):
    """Freeverb allpass: out[n] = buf[n-D] - x[n]; buf[n] = x[n] + g * buf[n-D]."""
    n = len(x); buf = np.zeros(n); out = np.zeros(n)
    for start in range(0, n, delay):
        end = min(n, start + delay); prev = start - delay
        back = buf[prev:prev + (end - start)] if prev >= 0 else np.zeros(end - start)
        out[start:end] = back - x[start:end]
        buf[start:end] = x[start:end] + g * back
    return out

def reverb(x, spread=0):
    scale = SR / 44100
    y = sum(comb(x, int((d + spread) * scale)) for d in COMBS) * 0.25
    for d in ALLPASS: y = allpass(y, int((d + spread) * scale))
    return y

def render(song, instruments, seconds=None, legacy_mode=False):
    insts = {i['id']: i for i in instruments}
    step = int(30 / song['tempo'] * SR)
    tracks = song['tracks']
    length = max(sum(s for _, s in parse(t['notes'])) for t in tracks) * step
    loops = song.get('loops', True)
    total = int(seconds * SR) if seconds else length
    L = np.zeros(total + SR * 2); R = np.zeros_like(L); send = np.zeros_like(L)
    for tr in tracks:
        notes = parse(tr['notes'])
        steps = sum(s for _, s in notes)
        if steps == 0: continue
        inst = insts.get(tr.get('instrument'))
        pan = tr.get('pan', 0.0)
        gl, gr = math.cos((pan + 1) * math.pi / 4), math.sin((pan + 1) * math.pi / 4)
        buf = np.zeros_like(L)
        pos = 0
        while pos < total:
            for name, s in notes:
                if pos >= total: break
                gate = s * step
                left = len(buf) - pos
                if name != '-':
                    if inst is None or legacy_mode and tr.get('wave'):
                        f = freq(name) or 0
                        w = legacy(tr.get('wave', 'square'), tr.get('duty', 0.5), f, gate, left) if (f or name == 'N') else None
                        if w is not None: buf[pos:pos + len(w)] += w
                    elif inst['id'] == 'drums':
                        for letter in name.split('+'):
                            w = drum(letter, left); buf[pos:pos + len(w)] += w
                    else:
                        for part in name.split('+'):
                            f = freq(part)
                            if f: w = pitched(inst, f, gate, left); buf[pos:pos + len(w)] += w
                pos += gate
            if not loops: break
        vol = tr['volume'] * (1 if inst or tr.get('wave') else 1)
        buf *= vol
        L += buf * gl; R += buf * gr
        send += buf * tr.get('reverb', 1.0)
    wet = song.get('reverb', 0.25)
    if not legacy_mode:
        L += reverb(send) * wet * 0.7; R += reverb(send, 23) * wet * 0.7
    else:
        L = L * 0.8; R = R * 0.8
    out = np.stack([L[:total], R[:total]], 1)
    return np.tanh(out * 1.1) / 1.1 if not legacy_mode else np.clip(out, -1, 1)

def to_wav(stereo, path):
    import wave
    pcm = (np.clip(stereo, -1, 1) * 32767).astype('<i2')
    with wave.open(str(path), 'wb') as f:
        f.setnchannels(2); f.setsampwidth(2); f.setframerate(SR); f.writeframes(pcm.tobytes())

if __name__ == '__main__':
    import argparse, pathlib
    root = pathlib.Path(__file__).resolve().parent.parent
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('songs', nargs='*')
    ap.add_argument('--all', action='store_true')
    ap.add_argument('--seconds', type=float, help='length (default: one pass through the song)')
    ap.add_argument('--out', default=str(root / 'music-preview'))
    args = ap.parse_args()
    music = json.loads((root / 'content/music.json').read_text())
    wanted = [s for s in music['songs'] if args.all or s['id'] in args.songs]
    if not wanted: ap.error('name some songs or pass --all: ' + ' '.join(s['id'] for s in music['songs']))
    out = pathlib.Path(args.out); out.mkdir(exist_ok=True)
    for song in wanted:
        legacy = not any('instrument' in t for t in song['tracks'])
        to_wav(render(song, music.get('instruments', []), args.seconds, legacy), out / f"{song['id']}.wav")
        print('wrote', out / f"{song['id']}.wav")
