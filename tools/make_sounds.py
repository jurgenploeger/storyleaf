#!/usr/bin/env python3
"""Synthesizes the game's sound effects into sound/*.wav (needs numpy and scipy).

The effects sit with the storybook soundtrack (TalesOfDorlune/Audio/SongSynth.swift: harp, piano, strings and
flute in a hall), so they come from the same world: struck bells, chimes, glass, wood and metal (modal
synthesis: many damped, inharmonic partials in slightly detuned pairs that beat, and a mallet), plucked
harp strings (Karplus-Strong), soft layered impacts (a sub thump with a falling pitch, a noise body and a
click, warmed with tanh), moving air (noise through a sweeping state-variable filter), a small choir
(formant-shaped voices) and one shared stereo reverb (a generated room and hall). A master stage
high-passes every sound, levels it to its loudness target, limits its peaks, trims the tail below -60 dBFS
(or at the recipe's length cap, which keeps sound/ under about 6 MB) and fades it out. Output: 44.1 kHz,
16-bit stereo. Each sound seeds its noise from its own name, so reruns
are byte-identical and a sound comes out the same alone or with the rest. Nothing is sampled, so there are
no licences to track. Tweak a recipe below and rerun:

    python3 tools/make_sounds.py              # all sounds
    python3 tools/make_sounds.py coins hit    # just these
    python3 tools/make_sounds.py --report     # a table of the files: length, peak, RMS, loudness, size

A recipe's name is its file name: the game plays sound/<name>.wav by the raw values of SoundEffects.Sound
(TalesOfDorlune/Audio/SoundEffects.swift). Its @sound(...) sets how loud it is: the loudest 400 ms in LUFS
(BS.1770 K-weighting), so each sits at its own level against the music whatever it's made of.
"""

import pathlib
import sys
import wave
import zlib

import numpy as np
from scipy import ndimage, signal

SR = 44100
OUT = pathlib.Path(__file__).resolve().parent.parent / "sound"
rng = np.random.default_rng(0)  # reseeded from each sound's name before it renders (see render)


# ---------------------------------------------------------------- time, pitch and mixing

def secs(seconds):
    """Samples in `seconds`."""
    return max(0, int(round(seconds * SR)))


def t(seconds):
    """The time axis (in seconds) of a sound `seconds` long."""
    return np.arange(secs(seconds)) / SR


def note(name):
    """The frequency of a note name: "A4", "C#5", "Eb4"."""
    names = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
    semis = names[name[0]] + (1 if "#" in name else -1 if name[1] == "b" else 0)
    return 440 * 2 ** ((12 * (int(name[-1]) + 1) + semis - 69) / 12)


def cents(amount):
    """The frequency ratio of `amount` cents (hundredths of a semitone)."""
    return 2 ** (np.asarray(amount) / 1200)


C_PENTATONIC = (0, 2, 4, 7, 9)   # semitones above C
D_PENTATONIC = (2, 4, 6, 9, 11)


def snap(freq, scale=C_PENTATONIC):
    """The note of `scale` nearest to `freq`, so scattered twinkles never clash."""
    midi = 69 + 12 * np.log2(freq / 440)
    base = 12 * np.floor(midi / 12)
    options = np.array([base + 12 * octave + step for octave in (-1, 0, 1) for step in scale])
    return 440 * 2 ** ((options[np.argmin(np.abs(options - midi))] - 69) / 12)


def stereo(x):
    """Stereo (n, 2) from mono; a stereo sound as it is."""
    return x if x.ndim == 2 else np.stack([x, x], axis=1)


def amp(x, level):
    """x scaled by a level that may change every sample (mono or stereo)."""
    level = np.asarray(level, dtype=float)
    return x * (level[:, None] if x.ndim == 2 and level.ndim == 1 else level)


def norm(x, peak=1.0):
    """x scaled so its loudest sample is `peak`."""
    top = np.max(np.abs(x))
    return x * (peak / top) if top > 0 else x


def delay(x, seconds):
    """x starting `seconds` later, cut to the same length."""
    d = min(len(x), secs(seconds))
    out = np.zeros_like(x)
    out[d:] = x[:len(x) - d]
    return out


def at(parts, total=0.0):
    """Mixes (start_seconds, sound) pairs; mono parts sit in the middle of a stereo mix. Each part ends
    on a 3 ms fade, so a layer cut off while it still rings can't click."""
    two = any(p.ndim == 2 for _, p in parts)
    end = max([secs(s) + len(p) for s, p in parts] + [secs(total)])
    out = np.zeros((end, 2) if two else end)
    for s, p in parts:
        i = secs(s)
        out[i:i + len(p)] += fade(stereo(p) if two else p, fade_out=0.003)
    return out


def pan(x, position=0.0):
    """x placed from left (-1) to right (+1): constant power, unchanged in the middle. `position` may
    move every sample; a stereo sound keeps its own width."""
    theta = (np.clip(position, -1, 1) + 1) * np.pi / 4
    x = stereo(x)
    return np.stack([x[:, 0] * np.cos(theta), x[:, 1] * np.sin(theta)], axis=1) * np.sqrt(2)


def wide(mid, side):
    """Stereo from a middle and a side: the side cancels in mono, so nothing ever vanishes there."""
    return np.stack([mid + side, mid - side], axis=1)


def chorus(make, amount=6.0, width=0.35):
    """Detune width: `make(ratio)` at its true pitch in the middle, a slightly sharp and a slightly flat
    copy only in the side, so it shimmers wide and stays whole in mono."""
    return wide(make(1.0), (make(cents(amount)) - make(cents(-amount))) * width / 2)


def widen(x, amount=0.3, gap=0.012, low=400.0):
    """Haas width, mono-safe: a delayed, high-passed echo of the middle, added to the side only."""
    x = stereo(x)
    mid, side = x.mean(axis=1), (x[:, 0] - x[:, 1]) / 2
    return wide(mid, side + highpass(delay(mid, gap), low) * amount)


# ---------------------------------------------------------------- envelopes and filters

def env(seconds, attack=0.002, decay=0.1, hold=0.0):
    """A raised-cosine attack, an optional hold, then an exponential decay (time constant `decay`)."""
    x = t(seconds)
    rise = np.where(x < attack, 0.5 - 0.5 * np.cos(np.pi * x / max(attack, 1e-9)), 1.0)
    return rise * np.exp(-np.maximum(0.0, x - attack - hold) / decay)


def swell(seconds, peak, rise=2.0, fall=1.5):
    """Grows from 0 to 1 at `peak` seconds, then dies away to 0 at the end; rise and fall bend the curves."""
    x = t(seconds)
    up = np.clip(x / peak, 0, 1) ** rise
    down = np.clip((seconds - x) / max(seconds - peak, 1e-9), 0, 1) ** fall
    return np.where(x < peak, up, down)


def fade(x, fade_in=0.0, fade_out=0.0):
    """Raised-cosine fades at either end (mono or stereo); the last sample lands on zero."""
    x = np.array(x, dtype=float)
    n = len(x)
    i, o = min(n, secs(fade_in)), min(n, secs(fade_out))
    if i:
        x[:i] = amp(x[:i], 0.5 - 0.5 * np.cos(np.pi * np.arange(i) / i))
    if o:
        x[n - o:] = amp(x[n - o:], 0.5 + 0.5 * np.cos(np.pi * np.arange(1, o + 1) / o))
    return x


def _run(sos, x):
    return signal.sosfilt(sos, x, axis=0)


def lowpass(x, freq, order=2):
    """Butterworth low-pass."""
    return _run(signal.butter(order, freq, "lowpass", fs=SR, output="sos"), x)


def highpass(x, freq, order=2):
    """Butterworth high-pass."""
    return _run(signal.butter(order, freq, "highpass", fs=SR, output="sos"), x)


def bandpass(x, low, high, order=2):
    """Butterworth band-pass."""
    return _run(signal.butter(order, (low, high), "bandpass", fs=SR, output="sos"), x)


def biquad(kind, freq, q=0.707, gain_db=0.0):
    """One biquad from the RBJ cookbook as a second-order section: "peak", "lowshelf", "highshelf",
    or "band" (a resonance, 0 dB at its peak)."""
    a_ = 10 ** (gain_db / 40)
    w = 2 * np.pi * freq / SR
    cw, alpha = np.cos(w), np.sin(w) / (2 * q)
    k = 2 * np.sqrt(a_) * alpha
    if kind == "peak":
        b, a = (1 + alpha * a_, -2 * cw, 1 - alpha * a_), (1 + alpha / a_, -2 * cw, 1 - alpha / a_)
    elif kind == "lowshelf":
        b = (a_ * ((a_ + 1) - (a_ - 1) * cw + k), 2 * a_ * ((a_ - 1) - (a_ + 1) * cw), a_ * ((a_ + 1) - (a_ - 1) * cw - k))
        a = ((a_ + 1) + (a_ - 1) * cw + k, -2 * ((a_ - 1) + (a_ + 1) * cw), (a_ + 1) + (a_ - 1) * cw - k)
    elif kind == "highshelf":
        b = (a_ * ((a_ + 1) + (a_ - 1) * cw + k), -2 * a_ * ((a_ - 1) + (a_ + 1) * cw), a_ * ((a_ + 1) + (a_ - 1) * cw - k))
        a = ((a_ + 1) - (a_ - 1) * cw + k, 2 * ((a_ - 1) - (a_ + 1) * cw), (a_ + 1) - (a_ - 1) * cw - k)
    elif kind == "band":
        b, a = (alpha, 0.0, -alpha), (1 + alpha, -2 * cw, 1 - alpha)
    else:
        raise ValueError(kind)
    return np.array([[b[0] / a[0], b[1] / a[0], b[2] / a[0], 1.0, a[1] / a[0], a[2] / a[0]]])


def eq(x, *bands):
    """x through a chain of biquads, each (kind, freq, q, gain_db)."""
    return _run(np.vstack([biquad(*band) for band in bands]), x)


def resonate(x, freq, q=4.0):
    """x through a resonance at `freq` (0 dB at its peak)."""
    return _run(biquad("band", freq, q), x)


def svf(x, cutoff, q=0.8, mode="band"):
    """A state-variable filter (Simper's trapezoidal SVF) whose cutoff (Hz) may move every sample: for
    sweeping whooshes and vowel-like wahs. mode: "low", "band" (0 dB at the cutoff) or "high"."""
    if x.ndim == 2:
        return np.stack([svf(x[:, side], cutoff, q, mode) for side in range(2)], axis=1)
    n = len(x)
    g = np.tan(np.pi * np.clip(np.broadcast_to(cutoff, (n,)), 10.0, SR * 0.45) / SR)
    k = 1.0 / q
    a1 = 1 / (1 + g * (g + k))
    a2 = g * a1
    a3 = g * a2
    band, low = [], []
    s1 = s2 = 0.0
    for v0, c1, c2, c3 in zip(x.tolist(), a1.tolist(), a2.tolist(), a3.tolist()):
        v3 = v0 - s2
        v1 = c1 * s1 + c2 * v3
        v2 = s2 + c2 * s1 + c3 * v3
        s1 = 2 * v1 - s1
        s2 = 2 * v2 - s2
        band.append(v1)
        low.append(v2)
    band, low = np.array(band), np.array(low)
    if mode == "low":
        return low
    if mode == "band":
        return band * k
    return x - k * band - low


# ---------------------------------------------------------------- sources

def noise(seconds):
    """White noise (RMS 0.35) from this sound's own seeded generator."""
    return rng.standard_normal(secs(seconds)) * 0.35


def colored(seconds, slope=-3.0):
    """Noise tilted by `slope` dB per octave (-3 is pink, -6 brown), RMS 0.35."""
    n = secs(seconds)
    spectrum = np.fft.rfft(rng.standard_normal(n)) * np.maximum(np.fft.rfftfreq(n, 1 / SR), 20.0) ** (slope / 6.0206)
    out = np.fft.irfft(spectrum, n)
    return out / (np.sqrt(np.mean(out ** 2)) + 1e-12) * 0.35


def phase(freq, seconds=0.0):
    """The running phase (radians, from 0) of a frequency that may change every sample."""
    f = np.full(secs(seconds), float(freq)) if np.ndim(freq) == 0 else np.asarray(freq, dtype=float)
    return 2 * np.pi * np.concatenate([[0.0], np.cumsum(f[:-1])]) / SR


def glide(f0, f1, seconds, curve=1.0):
    """A frequency moving from f0 to f1 in even musical steps; curve > 1 lingers near f0 first."""
    return f0 * (f1 / f0) ** ((t(seconds) / seconds) ** curve)


def path(*points):
    """A frequency through (seconds, Hz) points, moving in even musical steps between them."""
    times, freqs = zip(*points)
    return np.exp(np.interp(t(times[-1]), times, np.log(freqs)))


def drop(f0, f1, seconds, tau):
    """A frequency falling fast from f0 towards f1 (time constant `tau`), like a drum's pitch."""
    return f1 + (f0 - f1) * np.exp(-t(seconds) / tau)


def tone(freq, seconds, partials=((1, 1.0),)):
    """Additive oscillator: (multiple, level) partials over a fixed or moving pitch, none above 20 kHz."""
    ph = phase(freq, seconds)
    out = np.zeros(len(ph))
    for k, level in partials:
        if k * np.max(freq) < 20000:
            out += level * np.sin(k * ph)
    return out


def saw(count=24, tilt=1.0):
    """The partials of a soft sawtooth: harmonic k at 1/k^tilt."""
    return tuple((k, 1 / k ** tilt) for k in range(1, count + 1))


# Modes of struck things: (frequency ratio, level, decay relative to the fundamental's), from the
# textbook ratios (Rossing; Fletcher & Rossing) of each shape.
BAR = ((1, 1.0, 1.0), (2.756, 0.5, 0.42), (5.404, 0.25, 0.2), (8.933, 0.12, 0.11), (13.34, 0.06, 0.07))
TINE = ((1, 1.0, 1.0), (6.267, 0.25, 0.3), (17.55, 0.08, 0.1))
GLASS = ((1, 1.0, 1.0), (2.828, 0.4, 0.62), (5.424, 0.18, 0.38), (8.77, 0.08, 0.22), (12.9, 0.03, 0.12))
HANDBELL = ((1, 1.0, 1.0), (2.0, 0.12, 0.7), (2.98, 0.45, 0.55), (4.2, 0.1, 0.35), (5.14, 0.16, 0.3), (7.69, 0.07, 0.18))
PLATE = ((1, 1.0, 1.0), (1.73, 0.55, 0.85), (2.33, 0.7, 0.8), (3.91, 0.42, 0.6), (4.11, 0.45, 0.58), (6.30, 0.3, 0.45),
         (6.71, 0.24, 0.42), (7.34, 0.18, 0.36), (8.90, 0.13, 0.3), (9.83, 0.1, 0.26), (12.1, 0.05, 0.2))
WOOD = ((1, 1.0, 1.0), (2.57, 0.32, 0.4), (4.07, 0.12, 0.22), (6.3, 0.05, 0.14))
TIMPANI = ((1, 1.0, 1.0), (1.504, 0.55, 0.8), (1.742, 0.25, 0.6), (2.0, 0.3, 0.55), (2.245, 0.15, 0.45), (2.494, 0.12, 0.4), (2.8, 0.08, 0.35))
STONE = ((1, 1.0, 1.0), (1.47, 0.7, 0.75), (2.09, 0.55, 0.6), (2.56, 0.4, 0.5), (3.18, 0.3, 0.4), (3.89, 0.2, 0.3), (4.7, 0.12, 0.25))


def modal(freq, modes, seconds, ring=0.5, mallet=6000.0, click=0.0, beat=1.0, spread=0.0):
    """Something struck, by modal synthesis: a bar, bell, glass, plate, wood block or drum head.

    Each mode rings as a pair of damped sines `beat` Hz apart (varied per mode), so it beats like a real
    bell's doublets. `ring` is the fundamental's decay time constant (s); every mode decays in proportion.
    A soft `mallet` (low Hz) dulls the upper modes, `click` adds its contact noise, and `spread` > 0 makes
    it stereo, each pair's halves leaning left and right, so the beating moves gently across.
    """
    x = t(seconds)
    left, right = np.zeros(len(x)), np.zeros(len(x))
    lean = 0.5 + 0.5 * min(spread, 1.0)
    for ratio, level, decay in modes:
        f = freq * ratio
        if f > 18000:
            continue
        split = beat * rng.uniform(0.5, 1.5)
        e = level / (1 + (f / mallet) ** 2) * np.exp(-x / (ring * decay))
        a = np.sin(2 * np.pi * (f - split / 2) * x) * e
        b = np.sin(2 * np.pi * (f + split / 2) * x) * e
        left += lean * a + (1 - lean) * b
        right += (1 - lean) * a + lean * b
    out = np.stack([left, right], axis=1) if spread else left
    if click:
        contact = highpass(noise(0.006), max(150.0, freq * 0.7)) * env(0.006, 0.0001, 0.0012)
        out = at([(0, out), (0, norm(lowpass(contact, min(mallet * 1.5, 18000.0))) * click * np.max(np.abs(out)))])
    return fade(out, fade_in=0.0004, fade_out=seconds / 4)


def pluck(freq, seconds, ring=1.0, bright=3.0, soft=3000.0, position=0.2):
    """A plucked string (Karplus-Strong): a burst of noise circling a tuned delay line that loses a little
    every trip. `ring` is the fundamental's T60 (s) and `bright` how many times faster the 6th harmonic
    dies; `soft` is the finger (the burst's low-pass, Hz) and `position` where it plucks (0 to 0.5)."""
    period = SR / freq
    lag = int(period) - 2                      # whole samples; a Lagrange interpolator does the rest
    d = period - 1 - lag                       # its delay, in [1, 2) for the flattest response
    lagrange = np.array([np.prod([(d - j) / (k - j) for j in range(4) if j != k]) for k in range(4)])
    # The loss filter [a, 1-2a, a] (one sample of delay) and gain g let the fundamental and the 6th
    # harmonic die in `ring` and `ring / bright` seconds (Jaffe and Smith's decay stretching).
    c1, c6 = 1 - np.cos(2 * np.pi * freq / SR), 1 - np.cos(2 * np.pi * 6 * freq / SR)
    r = 10 ** (-3 * (bright - 1) / (freq * ring))
    a = float(np.clip((1 - r) / (2 * (c6 - r * c1)), 0.0, 0.25))
    taps = np.convolve(lagrange, (a, 1 - 2 * a, a)) * 10 ** (-3 / (freq * ring)) / (1 - 2 * a * c1)
    taps *= min(1.0, 0.99999 / np.max(np.abs(np.fft.rfft(taps, 8192))))   # never any gain round the loop
    burst = lowpass(noise(period / SR), soft)
    burst -= burst.mean()
    pick = max(1, int(round(position * period)))
    burst = burst - np.concatenate([np.zeros(pick), burst[:-pick]])       # where along the string
    n = secs(seconds)
    drive = np.zeros(n)
    drive[:min(n, len(burst))] = burst[:n]
    pad = lag + len(taps)
    y = np.zeros(pad + n)
    for start in range(0, n, lag):             # a block of `lag` samples only hears earlier blocks
        stop = min(n, start + lag)
        block = drive[start:stop].copy()
        for k, c in enumerate(taps):
            block += c * y[pad + start - lag - k:pad + stop - lag - k]
        y[pad + start:pad + stop] = block
    return norm(fade(y[pad:], fade_in=0.0008, fade_out=seconds / 4))


VOWELS = {  # formants: (centre Hz, level, bandwidth Hz)
    "ah": ((800, 1.0, 130), (1150, 0.55, 150), (2900, 0.3, 220), (3900, 0.14, 260), (4950, 0.06, 300)),
    "oo": ((350, 1.0, 110), (700, 0.35, 130), (2500, 0.06, 220), (3400, 0.03, 260)),
}


def voice(freq, seconds, vowel="ah", attack=0.15, release=0.3, vibrato=0.005, breath=0.05):
    """One sung note: harmonics shaped by the vowel's formants, a vibrato that comes in late, a slow
    drift and a little breath. `freq` may move every sample (a wobble)."""
    x = t(seconds)
    base = float(np.mean(freq))
    shake = vibrato * np.clip(x / 0.35, 0, 1) * np.sin(2 * np.pi * rng.uniform(4.6, 5.6) * x + rng.uniform(0, 2 * np.pi))
    drift = 0.0015 * norm(lowpass(rng.standard_normal(len(x)), 4.0))
    ph = phase(freq * (1 + shake + drift))
    formants = VOWELS[vowel]
    sung = np.zeros(len(x))
    for k in range(1, int(7000 / base) + 1):
        level = (0.03 + sum(a / (1 + ((k * base - c) / bw) ** 2) for c, a, bw in formants)) / k ** 0.6
        sung += level * np.sin(k * ph + rng.uniform(0, 2 * np.pi))
    breathy = sum(resonate(noise(seconds), c, c / bw) * a for c, a, bw in formants[:2])
    return fade(norm(sung) + norm(breathy) * breath, attack, release)


def choir(freqs, seconds, vowel="ah", attack=0.15, release=0.4, voices=3, detune=7.0, width=0.7):
    """A small choir: every note sung by a few voices spread evenly from left to right, each a little apart
    in pitch (stereo)."""
    out = np.zeros((secs(seconds), 2))
    for freq in freqs:
        for v in range(voices):
            place = (width * (2 * v / (voices - 1) - 1) if voices > 1 else 0.0) + rng.uniform(-0.1, 0.1)
            sung = voice(freq * cents(rng.uniform(-detune, detune)), seconds, vowel, attack * rng.uniform(0.8, 1.25), release)
            out += pan(sung, place)
    return norm(out)


# ---------------------------------------------------------------- textures

def sparkles(seconds, count, low, high, ring=0.1, width=0.7, scale=C_PENTATONIC):
    """Twinkles: tiny glassy pings scattered over `seconds`, climbing from `low` to `high` Hz on a
    pentatonic scale (stereo)."""
    parts = []
    for when in np.sort(rng.uniform(0, seconds, count)):
        freq = snap(low * (high / low) ** (when / seconds) * cents(rng.uniform(-200, 200)), scale)
        ping = modal(freq, GLASS, ring * 7, ring * rng.uniform(0.7, 1.3), mallet=10000.0, beat=2.0, spread=0.3)
        parts.append((when, pan(norm(ping) * rng.uniform(0.45, 1.0), rng.uniform(-width, width))))
    return at(parts)


def shimmer(seconds, low=3000.0, high=8000.0, count=14, width=0.8):
    """A cloud of high sines, each twinkling at its own pace (stereo)."""
    x = t(seconds)
    out = np.zeros((len(x), 2))
    for _ in range(count):
        freq = low * (high / low) ** rng.uniform()
        twinkle = (0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(3, 11) * x + rng.uniform(0, 2 * np.pi))) ** 3
        out += pan(np.sin(2 * np.pi * freq * x) * twinkle * rng.uniform(0.4, 1.0), rng.uniform(-width, width))
    return norm(out)


def air(seconds, sweep, q=0.9, mode="band", width=0.4, slope=0.0):
    """Moving air: noise through a filter following `sweep` (Hz, one per sample). Stereo and mono-safe:
    the side is a second noise through the same filter."""
    def source():
        return noise(seconds) if slope == 0 else colored(seconds, slope)
    return wide(svf(source(), sweep, q, mode), svf(source(), sweep, q, mode) * width)


def warm(x, drive=1.5):
    """Gentle tanh saturation at the same peak: rounder transients and a few warm harmonics."""
    top = np.max(np.abs(x)) or 1.0
    return np.tanh(drive * x / top) / np.tanh(drive) * top


def impact(seconds=0.35, thump=(160.0, 55.0), thump_decay=0.08, body=(180.0, 1500.0), body_decay=0.035,
           click=0.25, drive=1.8, weight=1.0):
    """A soft hit in layers: a sub thump (a sine whose pitch drops fast, like a kick drum), a body of
    band-passed noise and a short click, warmed together with tanh, which also gives the thump harmonics
    a phone's speaker can play."""
    sub = np.sin(phase(drop(*thump, seconds, 0.03))) * env(seconds, 0.001, thump_decay)
    thud = bandpass(noise(seconds), *body) * env(seconds, 0.0005, body_decay)
    blow = warm(norm(sub) * weight + norm(thud) * 0.8, drive)
    if click:
        tick = highpass(noise(0.008), 2500.0) * env(0.008, 0.0001, 0.0012)
        blow = at([(0, blow), (0, norm(tick) * click)])
    return norm(blow)


def bubble(freq, rise=0.1):
    """One bubble (van den Doel's model): a sine at the bubble's resonance, damped, its pitch rising as
    it nears the surface."""
    radius = 3.26 / freq                                     # metres (Minnaert)
    damping = 0.13 / radius + 0.0072 * radius ** -1.5        # per second
    x = t(min(0.3, 7 / damping))
    return fade(np.sin(phase(freq * (1 + rise * damping * x))) * np.exp(-damping * x), fade_in=0.0006)


def crackle(seconds, rate, band=(1500.0, 7000.0), width=0.7):
    """Crackling: sparse pops, `rate` a second (which may change over time), each its own size and place."""
    n = secs(seconds)
    hits = np.nonzero(rng.random(n) < np.broadcast_to(rate, (n,)) / SR)[0]
    sizes = np.minimum(1.0, 0.12 * (1 + rng.pareto(2.2, len(hits)))) * rng.choice((-1.0, 1.0), len(hits))
    theta = (rng.uniform(-width, width, len(hits)) + 1) * np.pi / 4
    pops = np.zeros((n, 2))
    pops[hits, 0], pops[hits, 1] = sizes * np.cos(theta), sizes * np.sin(theta)
    grain = noise(0.003) * np.exp(-t(0.003) / 0.0006)
    return bandpass(np.stack([np.convolve(pops[:, side], grain)[:n] for side in range(2)], axis=1), *band)


def creak(seconds, rate, body=((390, 9, 1.0), (840, 11, 0.7), (1480, 12, 0.45), (2350, 14, 0.25))):
    """Wood creaking (stick-slip): an uneven train of tiny slips, `rate` a second, ringing the wood's
    resonances (Hz, Q, level)."""
    n = secs(seconds)
    jitter = 1 + 0.25 * norm(lowpass(rng.standard_normal(n), 30.0))
    slips = np.nonzero(np.diff(np.floor(np.cumsum(np.broadcast_to(rate, (n,)) * jitter) / SR)) > 0)[0] + 1
    train = np.zeros(n)
    train[slips] = rng.uniform(0.5, 1.0, len(slips))
    return norm(lowpass(sum(resonate(train, f, q) * level for f, q, level in body), 4000.0))


def rustle(seconds, density, band=(1800.0, 7500.0), width=0.8):
    """Leaves rustling: many tiny scratches of noise, `density` a second (which may change over time)."""
    n = secs(seconds)
    out = np.zeros((n + secs(0.02), 2))
    for start in np.nonzero(rng.random(n) < np.broadcast_to(density, (n,)) / SR)[0]:
        scratch = noise(rng.uniform(0.002, 0.012))
        scratch *= np.hanning(len(scratch))
        out[start:start + len(scratch)] += pan(scratch * rng.uniform(0.3, 1.0), rng.uniform(-width, width))
    return bandpass(out[:n], *band)


# ---------------------------------------------------------------- space: the shared room and hall

# length (s); T60 (s) at 125 Hz, 1 kHz and 8 kHz; early reflections between two times (s) and their share
# of the energy; the tail's high-pass and low-pass (Hz); a seed of its own.
SPACES = {
    "room": dict(length=0.8, t60=(0.5, 0.42, 0.22), early=(0.002, 0.03), share=0.25, low=180.0, high=7500.0, seed=11),
    "hall": dict(length=2.6, t60=(2.0, 1.8, 0.9), early=(0.012, 0.09), share=0.12, low=120.0, high=9000.0, seed=23),
}
_impulses = {}


def impulse_response(kind):
    """A generated stereo impulse response: sparse early reflections, then noise that dies faster in the
    highs than in the lows and fills in over the first tens of milliseconds. Left and right are
    independent, so the tail is wide; each has unit energy, so `wet` in space() is a plain level."""
    if kind not in _impulses:
        p = SPACES[kind]
        gen = np.random.default_rng(p["seed"])
        n = secs(p["length"])
        x = np.arange(n) / SR
        first, last = p["early"]
        ir = np.zeros((n, 2))
        for side in range(2):
            white = gen.standard_normal(n)
            tail = np.zeros(n)
            for centre in 125 * 2.0 ** np.arange(8):          # octave bands, 125 Hz to 16 kHz
                edges = (centre / 2 ** 0.5, min(centre * 2 ** 0.5, SR * 0.48))
                band = signal.sosfiltfilt(signal.butter(2, edges, "bandpass", fs=SR, output="sos"), white)
                t60 = np.interp(np.log2(centre), np.log2([125, 1000, 8000]), p["t60"])
                tail += band * np.exp(-6.91 * x / t60)
            tail *= np.clip((x - first) / (last - first), 0, 1) ** 1.5
            early = np.zeros(n)
            times = gen.uniform(first, last, 24)
            early[(times * SR).astype(int)] = gen.choice((-1.0, 1.0), 24) * gen.uniform(0.3, 1.0, 24) * np.exp(-(times - first) / (last - first))
            early = lowpass(early, 6000.0)
            ir[:, side] = early / np.sqrt(np.sum(early ** 2)) * np.sqrt(p["share"]) + tail / np.sqrt(np.sum(tail ** 2)) * np.sqrt(1 - p["share"])
        ir = fade(lowpass(highpass(ir, p["low"]), p["high"]), fade_out=p["length"] / 5)
        _impulses[kind] = ir / np.sqrt(np.sum(ir ** 2, axis=0))
    return _impulses[kind]


def reverb(x, kind="room"):
    """Only the reverb of x (stereo): each side through its own impulse response."""
    ir, dry = impulse_response(kind), stereo(x)
    return np.stack([signal.fftconvolve(dry[:, side], ir[:, side]) for side in range(2)], axis=1)


def space(x, kind="room", wet=0.25, predelay=0.01, even=0.45):
    """x with the shared room or hall behind it: the reverb at `wet` level, `predelay` seconds late.

    A random impulse response colours each held note differently on the two sides, so a bell's tail can
    lean. The reverb's sides are levelled against each other (by up to `even`: 1 ± even) until the whole
    sound sits in the middle, its dry part untouched."""
    dry = stereo(fade(x, fade_out=0.003))
    tail = reverb(dry, kind) * wet
    start = secs(predelay)
    d = np.zeros((max(len(dry), start + len(tail)), 2))
    d[:len(dry)] = dry
    w = np.zeros_like(d)
    w[start:start + len(tail)] = tail
    kd, kw = _run(k_weighting(), d), _run(k_weighting(), w)

    def lean(s):   # how much louder the right is than the left with the reverb's sides at 1 - s, 1 + s
        return np.sum((kd[:, 1] + (1 + s) * kw[:, 1]) ** 2) - np.sum((kd[:, 0] + (1 - s) * kw[:, 0]) ** 2)
    low, high = -even, even
    if lean(low) < 0 < lean(high):
        for _ in range(30):
            middle = (low + high) / 2
            low, high = (middle, high) if lean(middle) < 0 else (low, middle)
        s = (low + high) / 2
    else:
        s = low if abs(lean(low)) < abs(lean(high)) else high
    return d + w * np.array([1 - s, 1 + s])


def reverse_reverb(x, seconds, kind="hall"):
    """The reverb of x played backwards: a swell breathing in towards the moment x is struck."""
    return fade(reverb(x, kind)[:secs(seconds)][::-1], fade_in=seconds / 5)


# ---------------------------------------------------------------- instruments (dry; peak about 1)

def chime(freq, seconds=1.0, ring=0.35, mallet=8000.0):
    """A glassy chime: wine-glass modes under a light, hard mallet."""
    return norm(modal(freq, GLASS, seconds, ring, mallet, click=0.06, beat=1.6, spread=0.4))


def handbell(freq, seconds=1.4, ring=0.5, mallet=3500.0):
    """A warm handbell: a strong fundamental and its twelfth, a leather mallet."""
    return norm(modal(freq, HANDBELL, seconds, ring, mallet, click=0.03, beat=1.0, spread=0.4))


def tine(freq, seconds=1.4, ring=0.5):
    """A music-box tine: nearly pure, with its high comb overtones and a tiny pluck."""
    return norm(modal(freq, TINE, seconds, ring, mallet=14000.0, click=0.1, beat=0.5, spread=0.2))


def glock(freq, seconds=0.9, ring=0.3, mallet=6000.0):
    """A glockenspiel or celesta bar."""
    return norm(modal(freq, BAR, seconds, ring, mallet, click=0.05, beat=1.2, spread=0.3))


def wood(freq, seconds=0.12, ring=0.03, mallet=2500.0):
    """A small wooden block or bamboo tube under a felt beater (mono)."""
    return norm(modal(freq, WOOD, seconds, ring, mallet, click=0.15, beat=0.0))


def metal(freq, seconds=0.8, ring=0.25, mallet=9000.0, click=0.3):
    """A struck metal plate: a shield, armour, a blade."""
    return norm(modal(freq, PLATE, seconds, ring, mallet, click=click, beat=2.5, spread=0.5))


def coin(freq):
    """A small coin: a bright little disk ringing briefly."""
    return norm(modal(freq, PLATE[:6], 0.5, ring=0.11, mallet=10000.0, click=0.2, beat=6.0, spread=0.3))


def harp(freq, seconds=1.4, ring=1.2, bright=3.0, soft=3500.0):
    """A harp string: a finger's pluck (`soft`: its low-pass, Hz) through a small soundboard."""
    string = pluck(freq, seconds, ring, bright, soft, position=0.3)
    return norm(eq(string, ("peak", 240, 1.0, 3.0), ("peak", 1200, 1.5, 1.5), ("highshelf", 6000, 0.707, -4.0)))


def footfall(seconds=0.13, toe=0.024, grit=0.9, bright=3500.0):
    """One step on soft ground: a muffled heel thump and the earth giving under it, then the toe (mono)."""
    heel = np.sin(phase(drop(150, 75, seconds, 0.012))) * env(seconds, 0.0015, 0.018)
    press = env(seconds, 0.002, 0.016) + 0.55 * delay(env(seconds, 0.003, 0.012), toe)
    earth = resonate(noise(seconds), 320, 1.2) * press                    # the soft "thup" of the ground
    blades = bandpass(noise(seconds), 1400, 4500) * press                 # grass brushing the foot
    return lowpass(warm(norm(heel) * 0.35 + norm(earth) * grit + norm(blades) * grit * 0.3, 1.3), bright)


def glug(freq, seconds=0.09):
    """One glug: a big bubble whose pitch leaps up as it breaks free, with a little slosh (mono)."""
    body = tone(glide(freq, freq * 1.75, seconds, 0.7), seconds, ((1, 1.0), (2, 0.18))) * env(seconds, 0.005, 0.028)
    slosh = resonate(noise(seconds), freq * 2.6, 3.0) * env(seconds, 0.003, 0.02)
    return norm(body) + norm(slosh) * 0.25


def pop(freq=420.0, seconds=0.08):
    """A happy pop: a bubble-like blip leaping up (mono)."""
    return norm(tone(glide(freq, freq * 2.3, seconds, 0.5), seconds, ((1, 1.0), (2, 0.25))) * env(seconds, 0.002, 0.025))


def shell_crack(clicks=5, spread=0.018):
    """An eggshell giving way: a cluster of tiny crisp clicks over a thin tick (stereo)."""
    parts = [(0, wood(2300, 0.05, ring=0.008, mallet=6000.0) * 0.4)]
    for when in np.sort(rng.uniform(0, spread, clicks)):
        snip = bandpass(noise(0.01), 1800, 7500) * env(0.01, 0.0001, rng.uniform(0.0008, 0.002))
        parts.append((when, pan(norm(snip) * rng.uniform(0.4, 1.0), rng.uniform(-0.3, 0.3))))
    return at(parts)


# ---------------------------------------------------------------- recipes

RECIPES = {}


def sound(target, longest=None, fade_out=0.03):
    """Registers a recipe; its name is its file name. `target`: its loudness in LUFS (the loudest 400 ms,
    K-weighted); `longest`: an optional cap on its length; `fade_out`: its last fade (both seconds)."""
    def register(recipe):
        RECIPES[recipe.__name__] = (recipe, target, longest, fade_out)
        return recipe
    return register


@sound(-24.0, longest=0.08, fade_out=0.015)
def tap():
    """A soft wooden tick for buttons: a felt beater on a small block."""
    s = 0.08
    thock = np.sin(2 * np.pi * 310 * t(s)) * env(s, 0.0008, 0.009)
    return space(lowpass(wood(760, s, ring=0.02, mallet=1700.0) + thock * 0.4, 4500), "room", wet=0.05, predelay=0.002)


@sound(-24.3, longest=0.08, fade_out=0.015)
def close():
    """A lower, softer felt tock for closing."""
    s = 0.08
    thock = np.sin(2 * np.pi * 220 * t(s)) * env(s, 0.001, 0.011)
    return space(lowpass(wood(540, s, ring=0.024, mallet=1300.0) + thock * 0.5, 3500), "room", wet=0.05, predelay=0.002)


@sound(-13.7, longest=0.4, fade_out=0.1)
def talk():
    """A friendly two-note chime blip: a celesta, A then E."""
    first = pan(glock(note("A5"), 0.45, ring=0.1, mallet=2000.0), -0.12)
    second = pan(glock(note("E6"), 0.45, ring=0.1, mallet=2000.0), 0.12)
    return space(at([(0, first), (0.065, second * 0.75)]), "room", wet=0.12, predelay=0.004)


@sound(-35.3, longest=0.16, fade_out=0.03)
def step():
    """A quiet footfall on grass and earth. It plays every step, so it stays soft and plain (and dry)."""
    return footfall(0.14)


@sound(-14.5, longest=0.35, fade_out=0.08)
def hit():
    """A satisfying soft impact: thump, body and click, in a small room."""
    blow = impact(0.3, thump=(170, 60), thump_decay=0.075, body=(200, 1600), body_decay=0.03, click=0.2, drive=1.6, weight=0.85)
    return space(blow, "room", wet=0.15, predelay=0.004)


@sound(-13.5, longest=0.45, fade_out=0.1)
def crit():
    """A heavier hit with a bright crack and a glint of ring."""
    blow = impact(0.4, thump=(150, 50), thump_decay=0.11, body=(150, 2200), body_decay=0.045, click=0.35, drive=2.2, weight=0.8)
    crack = highpass(noise(0.03), 3500) * env(0.03, 0.0002, 0.005)
    glint = metal(note("E6"), 0.5, ring=0.1, mallet=10000.0, click=0.0)
    return space(at([(0, blow), (0, norm(crack) * 0.45), (0.003, glint * 0.22)]), "room", wet=0.2, predelay=0.005)


@sound(-12.0, longest=0.65, fade_out=0.15)
def strike():
    """A physical special landing: a sharp swish into a heavy, meaty impact, with a short room."""
    s = 0.1
    swish = amp(air(s, glide(700, 5200, s, 1.4), q=1.4, width=0.3), np.linspace(0, 1, secs(s)) ** 3)
    swish = pan(fade(swish, fade_out=0.006), np.linspace(-0.5, 0.0, secs(s)))
    blow = impact(0.55, thump=(190, 45), thump_decay=0.14, body=(110, 1100), body_decay=0.07, click=0.4, drive=2.6, weight=0.7)
    meat = resonate(noise(0.25), 220, 2.5) * env(0.25, 0.001, 0.05)
    smack = bandpass(noise(0.1), 500, 2500) * env(0.1, 0.0005, 0.018)     # the slap a phone's speaker carries
    crack = bandpass(noise(0.02), 1800, 6500) * env(0.02, 0.0002, 0.004)
    landing = widen(at([(0, blow), (0, norm(meat) * 0.75), (0, norm(smack) * 0.7), (0, norm(crack) * 0.4)]), 0.25)
    return space(at([(0, swish * 0.5), (s, landing)]), "room", wet=0.25, predelay=0.006)


@sound(-9.0, longest=0.9, fade_out=0.3)
def magic():
    """A rising sparkle-shimmer: glassy partials gliding up, twinkles climbing, a breath of air."""
    s = 0.65
    rise = glide(520, 1250, s, 0.8)
    flutter = 0.7 + 0.3 * np.sin(phase(glide(7, 15, s)))
    glow = amp(chorus(lambda r: tone(rise * r, s, ((1, 1.0), (2, 0.3), (3, 0.12)))), flutter * swell(s, 0.3, 1.5, 1.2))
    breath = amp(air(s, glide(1500, 7000, s), q=1.0), swell(s, 0.35, 1.5, 1.5))
    twinkles = sparkles(0.45, 9, note("C6"), note("C7"), ring=0.09)
    return space(at([(0, norm(glow) * 0.5), (0.04, twinkles * 0.6), (0, norm(breath) * 0.25)]), "hall", wet=0.3, predelay=0.015)


@sound(-8.5, longest=1.15, fade_out=0.35)
def heal():
    """Warm rising chimes (handbells: C E G C E) over a soft sung swell."""
    notes = ("C5", "E5", "G5", "C6", "E6")
    bells = [(0.075 * i, pan(handbell(note(n), 1.2, ring=0.4, mallet=3000.0), -0.3 + 0.15 * i) * (0.85 - 0.02 * i))
             for i, n in enumerate(notes)]
    pad = choir((note("C4"), note("E4"), note("G4"), note("C5")), 1.1, "oo", attack=0.35, release=0.55)
    twinkle = sparkles(0.5, 5, note("C7"), note("E7"), ring=0.08)
    return space(at(bells + [(0, pad * 0.35), (0.3, twinkle * 0.22)]), "hall", wet=0.3, predelay=0.02)


@sound(-15.4, longest=0.5, fade_out=0.08)
def potion():
    """A drink going down: four liquid glugs, rising."""
    glugs = [(0, glug(250)), (0.105, glug(290) * 0.9), (0.2, glug(335) * 0.85), (0.29, glug(300) * 0.6)]
    return space(lowpass(at(glugs), 3500), "room", wet=0.15, predelay=0.004)


@sound(-11.4, longest=0.65, fade_out=0.2)
def guard():
    """A shield's metallic ting, braced with a soft thunk."""
    ting = metal(740, 0.9, ring=0.22, mallet=9000.0, click=0.3)
    thunk = impact(0.2, thump=(240, 130), thump_decay=0.03, body=(300, 1500), body_decay=0.02, click=0.0, drive=1.3)
    return space(at([(0, ting * 0.8), (0, thunk * 0.35)]), "room", wet=0.18, predelay=0.004)


@sound(-7.0, longest=1.25, fade_out=0.35)
def capture():
    """A sparkle rising into a happy pop and a bright bell chord."""
    s = 0.42
    rise = glide(600, 1600, s, 1.2)
    glow = fade(amp(chorus(lambda r: tone(rise * r, s, ((1, 1.0), (2, 0.3)))), swell(s, s, 1.8)), fade_out=0.02)
    climb = sparkles(s, 8, note("E6"), note("C7"), ring=0.07)
    chord = at([(0, pan(chime(note("G6"), 1.0, ring=0.35), -0.2)), (0.015, pan(chime(note("C7"), 1.0, ring=0.35), 0.2)),
                (0, handbell(note("C6"), 1.0, ring=0.4) * 0.6)])
    burst = sparkles(0.25, 7, note("C7"), note("C8"), ring=0.06)
    return space(at([(0, norm(glow) * 0.4), (0.02, climb * 0.5), (s, pop() * 0.5), (s + 0.01, chord * 0.55), (s + 0.04, burst * 0.3)]),
                 "hall", wet=0.3, predelay=0.015)


@sound(-14.1, longest=0.55, fade_out=0.08)
def break_free():
    """A comic boing downwards: a spring letting go."""
    s = 0.5
    x = t(s)
    pitch = 430 * 2 ** (-2.6 * x) * (1 + 0.07 * np.exp(-x / 0.25) * np.sin(2 * np.pi * 17 * x))
    spring = tone(pitch, s, ((1, 1.0), (2, 0.6), (3, 0.4), (4, 0.25), (5, 0.15), (6, 0.1)))
    boing = fade(svf(spring, pitch * 2.6, q=4.0, mode="low") * env(s, 0.003, 0.17), fade_out=0.12)
    return space(norm(boing), "room", wet=0.12, predelay=0.004)


@sound(-15.8, longest=0.6, fade_out=0.08)
def run():
    """Feet scampering off to one side, with a rush of air."""
    times = (0, 0.055, 0.105, 0.15, 0.19, 0.226, 0.258)
    feet = [(when, pan(footfall(0.1, toe=0.015, grit=1.0, bright=4500 - 450 * i) * (1 - 0.1 * i), -0.2 + 0.1 * i))
            for i, when in enumerate(times)]
    s = 0.55
    rush = amp(air(s, path((0, 400), (0.2, 1600), (s, 700)), q=0.8), swell(s, 0.2, 1.5, 1.5))
    rush = pan(rush, np.linspace(-0.2, 0.5, len(rush)))
    return space(at(feet + [(0, norm(rush) * 0.6)]), "room", wet=0.1, predelay=0.004)


@sound(-15.6, longest=0.55, fade_out=0.1)
def poof():
    """A puff of smoke: a soft burst of air closing down, a low whump and a wisp of glitter."""
    s = 0.5
    puff = amp(air(s, path((0, 4000), (0.15, 1200), (s, 400)), q=0.6, mode="low", slope=-3), env(s, 0.008, 0.11))
    whump = warm(np.sin(phase(drop(280, 85, s, 0.03))) * env(s, 0.002, 0.06), 1.5)
    wisp = sparkles(0.15, 3, note("G6"), note("C7"), ring=0.06)
    return space(at([(0, norm(puff)), (0, norm(whump) * 0.2), (0.04, wisp * 0.12)]), "room", wet=0.22, predelay=0.006)


@sound(-11.2, longest=0.95, fade_out=0.3)
def faint():
    """A friend going down: a gentle harp motif falling E, C, A."""
    plucks = [(0.14 * i, pan(harp(note(n), 1.0, ring=0.9, bright=4.0, soft=2200.0), 0.15 - 0.15 * i) * (1 - 0.1 * i))
              for i, n in enumerate(("E5", "C5", "A4"))]
    return space(at(plucks), "hall", wet=0.22, predelay=0.015)


@sound(-10.4, longest=1.7, fade_out=0.5)
def lose():
    """The whole party fainting: a soft, sad bell motif falling G, E-flat, C over a low hum."""
    notes = (("G4", 0.0, -0.2, 0.85), ("Eb4", 0.3, 0.0, 0.8), ("C4", 0.62, 0.2, 0.9))
    bells = [(when, pan(handbell(note(n), 1.6, ring=0.55, mallet=2200.0), place) * level) for n, when, place, level in notes]
    hum = choir((note("C3"), note("G3"), note("Eb4")), 1.3, "oo", attack=0.45, release=0.6)
    return space(at(bells + [(0.5, hum * 0.22)]), "hall", wet=0.32, predelay=0.02)


@sound(-6.5, longest=1.9, fade_out=0.55)
def level_up():
    """A bright, rich arpeggio with sparkles and a hall tail: the treat."""
    notes = ("C5", "E5", "G5", "C6", "E6", "G6")
    arp = [(0.055 * i, pan(harp(note(n), 1.6, ring=1.3), -0.35 + 0.15 * i) * 0.8) for i, n in enumerate(notes)]
    glints = [(0.055 * i + 0.003, pan(glock(note(n) * 2, 0.8, ring=0.22), 0.3 - 0.12 * i) * 0.16) for i, n in enumerate(notes)]
    crown = at([(0, chime(note("C7"), 1.6, ring=0.55)), (0.02, chime(note("G6"), 1.6, ring=0.55) * 0.8),
                (0.04, handbell(note("E6"), 1.6, ring=0.55) * 0.6)])
    glitter = sparkles(0.7, 12, note("C7"), note("C8"), ring=0.08)
    pad = choir((note("C4"), note("E4"), note("G4"), note("C5")), 1.4, "ah", attack=0.25, release=0.7)
    return space(at(arp + glints + [(0.33, crown * 0.6), (0.36, glitter * 0.3), (0.1, pad * 0.22)]), "hall", wet=0.35, predelay=0.02)


@sound(-9.6, longest=0.55, fade_out=0.12)
def coins():
    """Coins clinking: three small bright disks."""
    clinks = ((0.0, 2200, -0.25, 1.0), (0.07, 2750, 0.25, 0.8), (0.125, 2450, 0.0, 0.6))
    return space(at([(when, pan(coin(f), place) * level) for when, f, place, level in clinks]), "room", wet=0.15, predelay=0.003)


@sound(-9.2, longest=1.2, fade_out=0.4)
def quest_accept():
    """A hopeful two-note chime: handbells rising a fifth, G to D, warmed by a low harp G."""
    first = pan(handbell(note("G5"), 1.4, ring=0.5), -0.15)
    second = pan(handbell(note("D6"), 1.4, ring=0.5), 0.15)
    return space(at([(0, first), (0, harp(note("G4"), 1.2, ring=0.8) * 0.3), (0.13, second)]), "hall", wet=0.3, predelay=0.02)


@sound(-6.9, longest=1.6, fade_out=0.5)
def quest_done():
    """A small music-box and harp fanfare: C E G, then a ringing C over a strummed chord."""
    box = (("C6", 0.0, -0.25), ("E6", 0.1, 0.25), ("G6", 0.2, -0.1), ("C7", 0.34, 0.1))
    tines = [(when, pan(tine(note(n), 1.6, ring=0.5), place)) for n, when, place in box]
    strum = [(0.34 + 0.014 * i, pan(harp(note(n), 1.6, ring=1.2), place) * 0.5)
             for i, (n, place) in enumerate((("C4", 0.0), ("G4", -0.25), ("C5", 0.25), ("E5", 0.1)))]
    glitter = sparkles(0.4, 6, note("G6"), note("G7"), ring=0.07)
    return space(at(tines + strum + [(0.38, glitter * 0.2)]), "hall", wet=0.32, predelay=0.02)


@sound(-9.2, longest=1.35, fade_out=0.35)
def chest():
    """A chest opening: the wooden lid creaks, settles with a clunk, and a chime rings out."""
    s = 0.34
    lid = amp(creak(s, path((0, 34), (0.2, 58), (s, 44))), swell(s, 0.12, 1.2, 1.0))
    opening = space(at([(0, lid * 0.7), (0.3, wood(170, 0.15, ring=0.04, mallet=1200.0) * 0.5)]), "room", wet=0.18, predelay=0.004)
    first, second = pan(handbell(note("G5"), 1.3, ring=0.45), -0.15), pan(handbell(note("D6"), 1.3, ring=0.45), 0.15)
    shine = space(at([(0, first), (0.12, second), (0.15, sparkles(0.3, 6, note("C7"), note("G7"), ring=0.07) * 0.3)]),
                  "hall", wet=0.3, predelay=0.02)
    return at([(0, opening), (0.36, shine)])


@sound(-9.2, longest=1.3, fade_out=0.35)
def hatch():
    """An egg hatching: the shell cracks twice, then a sparkle."""
    cracks = space(at([(0, shell_crack(4)), (0.13, shell_crack(7, 0.03) * 1.2)]), "room", wet=0.12, predelay=0.003)
    chimes = [(0.06 * i, pan(chime(note(n), 1.0, ring=0.32), -0.3 + 0.2 * i) * (1 - 0.08 * i)) for i, n in enumerate(("C6", "E6", "G6", "C7"))]
    shine = space(at(chimes + [(0.1, sparkles(0.35, 6, note("C7"), note("C8"), ring=0.06) * 0.3)]), "hall", wet=0.3, predelay=0.02)
    return at([(0, cracks), (0.3, shine * 0.8)])


@sound(-16.1, longest=0.4, fade_out=0.08)
def equip():
    """Armour settling into place: two plates clink over a little chain jingle."""
    first = pan(metal(620, 0.4, ring=0.07, mallet=7000.0, click=0.3), -0.15)
    second = pan(metal(930, 0.4, ring=0.06, mallet=8000.0, click=0.3), 0.15)
    links = at([(when, pan(norm(modal(rng.uniform(3000, 5500), PLATE[:4], 0.06, ring=0.012, mallet=12000.0, click=0.3)) * rng.uniform(0.3, 0.8),
                           rng.uniform(-0.4, 0.4))) for when in np.sort(rng.uniform(0.01, 0.12, 6))])
    thunk = impact(0.15, thump=(220, 140), thump_decay=0.025, body=(250, 1200), body_decay=0.02, click=0.0, drive=1.2)
    return space(at([(0, first), (0.055, second * 0.8), (0, links * 0.3), (0, thunk * 0.3)]), "room", wet=0.15, predelay=0.003)


@sound(-9.3, longest=0.75, fade_out=0.25)
def learn():
    """A quick sparkle: four glass chimes climbing, with a breath of air."""
    chimes = [(0.045 * i, pan(chime(note(n), 0.8, ring=0.22), -0.3 + 0.2 * i) * (1 - 0.08 * i)) for i, n in enumerate(("E6", "G6", "B6", "E7"))]
    breath = amp(air(0.35, glide(2500, 8000, 0.35), q=1.2), swell(0.35, 0.15, 1.5, 1.5))
    return space(at(chimes + [(0, norm(breath) * 0.12)]), "hall", wet=0.25, predelay=0.015)


@sound(-16.7, longest=0.75, fade_out=0.06)
def whoosh():
    """Travelling to a new map: a gust of air sweeping across."""
    s = 0.75
    sweep = path((0, 220), (0.35, 1700), (s, 420))
    gust = amp(air(s, sweep, q=1.0), swell(s, 0.33, 1.6, 1.4))
    whistle = amp(air(s, sweep * 2.2, q=3.0), swell(s, 0.36, 2.0, 2.0))
    rumble = lowpass(colored(s, -6), 220) * swell(s, 0.3, 1.5, 1.5)
    gusting = at([(0, norm(gust)), (0, norm(whistle) * 0.22), (0, norm(rumble) * 0.3)])
    return space(pan(gusting, np.linspace(-0.5, 0.5, len(gusting))), "room", wet=0.08, predelay=0.004)


@sound(-13.2, longest=0.85, fade_out=0.25)
def encounter():
    """A monster jumps out: a swoosh, then a short dramatic sting (timpani, low pizzicato, a tense chord)."""
    s = 0.24
    swoosh = fade(amp(air(s, glide(350, 3200, s, 1.3), q=1.1), np.linspace(0, 1, secs(s)) ** 2), fade_out=0.01)
    timpani = norm(modal(note("A2"), TIMPANI, 0.9, ring=0.28, mallet=1100.0, click=0.15))
    stab = at([(0.008 * i, pan(harp(note(n), 0.9, ring=0.6), -0.3 + 0.3 * i)) for i, n in enumerate(("A4", "C5", "D#5"))])
    return space(at([(0, swoosh * 0.5), (s, timpani * 0.6), (s, harp(note("A2"), 0.7, ring=0.35) * 0.45), (s + 0.005, stab * 0.75)]),
                 "hall", wet=0.22, predelay=0.012)


@sound(-9.5, longest=0.95, fade_out=0.25)
def spell_fire():
    """Fire: a whoomp of flame catching, then crackling as it burns down."""
    s = 1.0
    x = t(s)
    whoomp = amp(air(s, path((0, 250), (0.05, 3200), (0.5, 800), (s, 600)), q=0.9, mode="low", slope=-2), env(s, 0.035, 0.22))
    sub = warm(np.sin(phase(drop(110, 48, s, 0.05))) * env(s, 0.004, 0.13), 1.8)
    flutter = 0.7 + 0.3 * norm(lowpass(rng.standard_normal(secs(s)), 12.0))
    roar = lowpass(colored(s, -4), 900) * flutter * env(s, 0.06, 0.35)
    crackles = crackle(s, 45 * np.exp(-x / 0.45) * (x > 0.06))
    return space(at([(0, norm(whoomp)), (0, norm(sub) * 0.5), (0, norm(roar) * 0.4), (0, norm(crackles) * 0.35)]),
                 "room", wet=0.2, predelay=0.006)


@sound(-10.0, longest=0.9, fade_out=0.2)
def spell_water():
    """Water: a splash, then bubbles and droplets."""
    s = 0.35
    splash = amp(air(s, path((0, 3500), (s, 2000)), q=0.4, width=0.5), env(s, 0.004, 0.07))
    slap = bandpass(noise(0.2), 180, 1200) * env(0.2, 0.002, 0.04)
    bubbles = []
    for _ in range(22):
        when = 0.02 + min(0.7, rng.exponential(0.12))
        freq = np.exp(rng.uniform(np.log(450), np.log(2200)))
        bubbles.append((when, pan(bubble(freq, rise=0.12) * rng.uniform(0.25, 0.6) * (1 - when), rng.uniform(-0.6, 0.6))))
    for _ in range(5):
        freq = np.exp(rng.uniform(np.log(1400), np.log(3200)))
        bubbles.append((rng.uniform(0.25, 0.8), pan(bubble(freq, rise=0.35) * rng.uniform(0.2, 0.45), rng.uniform(-0.7, 0.7))))
    return space(at([(0, norm(splash)), (0, norm(slap) * 0.6)] + bubbles), "room", wet=0.22, predelay=0.006)


@sound(-10.5, longest=0.95, fade_out=0.25)
def spell_wood():
    """Wood: leaves rustling, and the hollow knock of bamboo chimes."""
    s = 0.8
    leaves = eq(rustle(s, 60 + 220 * swell(s, 0.2, 1.2, 1.5)), ("peak", 3200, 1.5, 3.0), ("peak", 5200, 2.0, 2.0))
    knocks = (("D6", 0.0, -0.3), ("G5", 0.09, 0.2), ("A5", 0.2, -0.1), ("E6", 0.31, 0.3))
    bamboo = [(when, pan(norm(modal(note(n), BAR, 0.4, ring=0.07, mallet=5000.0, click=0.2)), place) * 0.7) for n, when, place in knocks]
    return space(at([(0, norm(leaves) * 0.6)] + bamboo), "hall", wet=0.18, predelay=0.012)


@sound(-10.0, longest=1.1, fade_out=0.3)
def spell_earth():
    """Earth: a deep rumble and a rock cracking, then pebbles settling."""
    s = 1.1
    x = t(s)
    shake = 0.75 + 0.25 * np.sin(2 * np.pi * 9 * x + 2 * np.sin(2 * np.pi * 1.3 * x))
    rumble = warm(lowpass(colored(s, -6), 160) * shake * env(s, 0.05, 0.35), 2.5)
    grind = bandpass(colored(s, -3), 200, 900) * shake * env(s, 0.04, 0.25)
    sub = np.sin(phase(drop(70, 42, s, 0.15))) * env(s, 0.01, 0.35)
    crack = at([(0, norm(bandpass(noise(0.05), 900, 7000) * env(0.05, 0.0002, 0.007))),
                (0, norm(modal(380, STONE, 0.3, ring=0.035, mallet=4000.0, click=0.3)) * 0.6)])
    pebbles = [(when, pan(norm(modal(rng.uniform(900, 2500), STONE, 0.08, ring=0.01, mallet=8000.0, click=0.4)) * rng.uniform(0.15, 0.5) * (1.2 - when),
                          rng.uniform(-0.6, 0.6))) for when in np.minimum(0.9, 0.1 + rng.exponential(0.18, 12))]
    return space(at([(0, norm(rumble) * 0.6), (0, norm(grind) * 0.7), (0, norm(sub) * 0.4), (0.05, crack)] + [(w, p * 1.5) for w, p in pebbles]),
                 "room", wet=0.2, predelay=0.008)


@sound(-9.5, longest=1.15, fade_out=0.35)
def spell_light():
    """Light: a radiant chime shimmer over a choir-like glow (G major)."""
    s = 1.1
    glow = choir((note("G4"), note("B4"), note("D5"), note("G5")), s, "ah", attack=0.12, release=0.6, width=0.8)
    chimes = at([(when, pan(chime(note(n), 1.2, ring=0.45), place))
                 for n, when, place in (("G6", 0.0, -0.3), ("D7", 0.05, 0.3), ("B6", 0.11, -0.1), ("G7", 0.18, 0.15))])
    halo = amp(shimmer(s, 4000, 10000, count=24), swell(s, 0.3, 1.5, 1.5))
    return space(at([(0, glow * 0.5), (0, chimes * 0.6), (0.03, halo * 0.3)]), "hall", wet=0.4, predelay=0.02)


@sound(-11.0, longest=1.15, fade_out=0.35)
def spell_dark():
    """Darkness: a low, eerie swell: ghostly voices on a wobbling tritone over a soft drone, and a hiss."""
    s = 1.2
    wobble = cents(30 * np.sin(phase(glide(3.4, 2.2, s))))
    ghost = choir((note("A2") * wobble, note("Eb3") / wobble, note("A3") * wobble), s, "oo", attack=0.2, release=0.5,
                  voices=2, detune=12.0, width=0.6)
    drone = svf(tone(note("A2") * wobble, s, saw(30, 1.1)), path((0, 400), (0.55, 1500), (s, 500)), q=1.2, mode="low")
    deep = np.sin(phase(note("A1") * wobble))
    body = amp(at([(0, ghost), (0, norm(drone) * 0.35), (0, deep * 0.25)]), 0.2 + 0.8 * swell(s, 0.45, 1.6, 1.5))
    hiss = amp(air(s, glide(6000, 2500, s), q=0.8), swell(s, 0.5, 2.0, 1.5))
    return space(at([(0, norm(body)), (0, norm(hiss) * 0.3)]), "hall", wet=0.35, predelay=0.02)


@sound(-10.0, longest=1.05, fade_out=0.35)
def spell_metal():
    """Metal: a bright metallic clang that rings on."""
    clang = metal(520, 1.3, ring=0.35, mallet=10000.0, click=0.4)
    singing = chime(note("E6"), 1.3, ring=0.5)
    shing = amp(air(0.35, glide(9000, 6000, 0.35), q=0.7, mode="high"), env(0.35, 0.001, 0.06))
    blow = impact(0.2, thump=(200, 110), thump_decay=0.03, body=(400, 2500), body_decay=0.015, click=0.3, drive=1.5)
    return space(at([(0, clang), (0.004, singing * 0.45), (0, norm(shing) * 0.2), (0, blow * 0.35)]), "hall", wet=0.22, predelay=0.012)


@sound(-10.0, longest=1.0, fade_out=0.3)
def buff():
    """A power-up: a warm tone gliding up an octave, a climbing arpeggio and a rising shimmer."""
    s = 0.85
    rise = path((0, note("C4")), (0.5, note("C5")), (s, note("C5")))
    flutter = 0.75 + 0.25 * np.sin(phase(glide(5, 14, s)))
    lift = amp(chorus(lambda r: tone(rise * r, s, saw(12, 1.4))), flutter * swell(s, 0.5, 1.2, 1.5))
    lift = svf(lift, path((0, 600), (0.5, 3500), (s, 2000)), q=0.9, mode="low")
    arp = [(0.15 + 0.07 * i, pan(glock(note(n), 0.7, ring=0.2), -0.4 + 0.2 * i) * 0.6) for i, n in enumerate(("C5", "E5", "G5", "C6", "E6"))]
    climb = sparkles(0.6, 9, note("C6"), note("C8"), ring=0.07)
    return space(at([(0, norm(lift) * 0.5)] + arp + [(0.2, climb * 0.35)]), "hall", wet=0.3, predelay=0.015)


@sound(-11.0, longest=1.0, fade_out=0.3)
def curse():
    """A hex: a descending, slightly sour, wobbly tone."""
    s = 1.0
    fall = path((0, 660), (0.85, 300), (s, 290))
    wobble = cents(30 * np.sin(phase(glide(6.0, 4.5, s))))
    hollow = ((1, 1.0), (3, 0.33), (5, 0.18), (7, 0.1), (9, 0.06))
    one = tone(fall * wobble, s, hollow)
    other = tone(fall * cents(65) / wobble, s, hollow)           # a little off from the first: sour
    hexed = amp(lowpass(wide(one + other, (one - other) * 0.3), 2200), env(s, 0.03, 0.45, hold=0.2))
    hiss = amp(air(s, glide(5000, 2000, s), q=1.0), swell(s, 0.4, 1.5, 1.5))
    return space(at([(0, norm(hexed)), (0, norm(hiss) * 0.12)]), "hall", wet=0.3, predelay=0.015)


@sound(-9.5, longest=1.4, fade_out=0.35)
def surge():
    """A strong skill gathering power. It starts with the skill's own sound and peaks after half a second,
    as the charge before the skill ends (BattleScene.castSkill): a deep body and a shimmer climb in pitch
    and swell, with the hall breathing in backwards, then a bright chord rings out as the skill lets go
    and the swell falls away into the hall."""
    s, peak = 1.3, 0.5

    def climb(f0, f1, curve):   # rises from f0 to f1 by the peak, then holds
        return np.concatenate([glide(f0, f1, peak, curve), np.full(secs(s) - secs(peak), f1)])
    grow = swell(s, peak, rise=2.2, fall=3.0)
    root = climb(note("D2"), note("A2"), 1.0)                     # the deep body climbs a fifth
    body = svf(tone(root, s, saw(30, 1.0)), path((0, 150), (peak, 2000), (s, 500)), q=1.3, mode="low")
    sub = np.sin(phase(root / 2))
    high = climb(note("D5"), note("D7"), 1.4)
    tremolo = 0.65 + 0.35 * np.sin(phase(climb(4, 18, 1.2)))
    shine = amp(chorus(lambda r: tone(high * r, s, ((1, 1.0), (1.5, 0.5), (2, 0.6), (3, 0.25)))), tremolo)
    rush = air(s, path((0, 400), (peak, 7000), (s, 2500)), q=1.0)
    chord = at([(0.01 * i, pan(chime(note(n), s - peak, ring=0.4), place)) for i, (n, place) in enumerate((("D6", -0.4), ("A6", 0.4), ("D7", 0.0), ("F#7", 0.2)))])
    breath_in = reverse_reverb(chord, peak)
    mix = at([(0, amp(norm(body), grow) * 0.7), (0, norm(sub) * grow * 0.4), (0, amp(norm(shine), grow ** 1.3) * 0.4),
              (0, amp(norm(rush), grow ** 1.5) * 0.3), (0, norm(breath_in) * 0.6), (peak, norm(chord) * 0.45)])
    return space(mix, "hall", wet=0.3, predelay=0.01)


@sound(-6.0, longest=2.2, fade_out=0.6)
def ultimate():
    """A mastered skill's grand finale: a big warm boom, a choir-like shimmer and a long hall tail."""
    boom = widen(impact(1.2, thump=(120, 42), thump_decay=0.24, body=(60, 700), body_decay=0.12, click=0.12, drive=3.0, weight=0.7), 0.25)
    drum = norm(modal(note("D2"), TIMPANI, 1.5, ring=0.5, mallet=700.0, click=0.15))
    voices = choir(tuple(note(n) for n in ("D3", "A3", "D4", "F#4", "A4", "E5")), 1.7, "ah", attack=0.07, release=1.0, width=0.9)
    bells = at([(0.02 * i, pan(chime(note(n), 1.8, ring=0.6), place)) for i, (n, place) in enumerate((("D6", -0.4), ("A6", 0.4), ("D7", -0.1), ("F#7", 0.2)))])
    glitter = sparkles(1.0, 16, note("D7"), note("D8"), ring=0.09, scale=D_PENTATONIC)
    wash = amp(air(1.2, glide(9000, 4000, 1.2), q=0.6), env(1.2, 0.02, 0.35))
    mix = at([(0, boom * 0.6), (0.004, drum * 0.45), (0.01, voices * 0.7), (0, bells * 0.45), (0.05, glitter * 0.25), (0, norm(wash) * 0.12)])
    return space(mix, "hall", wet=0.45, predelay=0.025)


# ---------------------------------------------------------------- master and files

def k_weighting(rate=SR):
    """BS.1770's K-weighting as second-order sections: a +4 dB high shelf and a 38 Hz high-pass."""
    k = np.tan(np.pi * 1681.974450955533 / rate)
    vh, q = 10 ** (3.999843853973347 / 20), 0.7071752369554196
    vb = vh ** 0.4996667741545416
    a0 = 1 + k / q + k * k
    shelf = [(vh + vb * k / q + k * k) / a0, 2 * (k * k - vh) / a0, (vh - vb * k / q + k * k) / a0, 1, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]
    k, q = np.tan(np.pi * 38.13547087602444 / rate), 0.5003270373238773
    a0 = 1 + k / q + k * k
    return np.array([shelf, [1, -2, 1, 1, 2 * (k * k - 1) / a0, (1 - k / q + k * k) / a0]])


def loudness(x, rate=SR):
    """How loud x feels: its loudest 400 ms in LUFS (K-weighted, both channels: BS.1770's momentary
    loudness). A shorter sound counts as if padded with silence, as the ear hears it."""
    weighted = signal.sosfilt(k_weighting(rate), stereo(x), axis=0)
    power = np.sum(weighted ** 2, axis=1)
    window = int(0.4 * rate)
    sums = np.concatenate([[0.0], np.cumsum(np.pad(power, (0, max(0, window - len(power)))))])
    return -0.691 + 10 * np.log10(max(np.max(sums[window:] - sums[:-window]) / window, 1e-12))


def limit(x, ceiling_db=-1.0, ahead=0.003, recovery=60.0):
    """A look-ahead peak limiter: the gain dips smoothly just before a peak and recovers `recovery` dB a
    second after it, so no sample passes the ceiling and nothing clips or pumps."""
    need = np.minimum(0.0, ceiling_db - 20 * np.log10(np.maximum(np.max(np.abs(x), axis=1), 1e-12)))
    if need.min() >= 0:
        return x
    a = secs(ahead)
    lowest = ndimage.minimum_filter1d(need, 2 * a + 1, mode="nearest")     # the dip needed within ±`ahead`
    slope = recovery / SR * np.arange(len(need))
    held = np.minimum.accumulate(lowest - slope) + slope                   # ...then climbing back slowly
    # Smoothed over ±`ahead`: the average around a peak only takes in dips at least as deep as its own.
    window = np.hanning(2 * a + 3)[1:-1]
    gain_db = np.convolve(np.pad(held, a, mode="edge"), window / window.sum(), mode="valid")
    ceiling = 10 ** (ceiling_db / 20)
    return np.clip(amp(x, 10 ** (gain_db / 20)), -ceiling, ceiling)


def trim(x, floor_db=-60.0, tail=0.01):
    """Cuts the tail once it stays below `floor_db`, keeping `tail` seconds that fade to zero."""
    loud = np.nonzero(np.max(np.abs(x), axis=1) > 10 ** (floor_db / 20))[0]
    end = (loud[-1] + 1 if len(loud) else 0) + secs(tail)
    return fade(x[:end], fade_out=tail) if end < len(x) else x


def master(x, target, longest=None, fade_out=0.03):
    """The master stage: a 30 Hz high-pass (no DC or rumble), a few samples of fade-in and the sound's
    last fade (at its length cap, if it has one); then the sound levelled to its loudness target with its
    peaks limited to -1 dBFS; then its tail trimmed where it stays below -60 dBFS."""
    x = stereo(np.asarray(x, dtype=float))[:secs(longest) if longest else None]
    x = fade(highpass(x, 30.0), fade_in=0.0005, fade_out=fade_out)
    for _ in range(8):
        miss = target - loudness(x)
        if abs(miss) < 0.05:
            break
        x = limit(x * 10 ** (miss / 20))
    return trim(x)


def render(name):
    """One sound, mastered, its noise seeded from its name (so it's the same alone or with the rest)."""
    global rng
    rng = np.random.default_rng(zlib.crc32(name.encode()))
    recipe, target, longest, fade_out = RECIPES[name]
    return master(recipe(), target, longest, fade_out)


def write(name, x):
    OUT.mkdir(exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as f:
        f.setnchannels(2)
        f.setsampwidth(2)
        f.setframerate(SR)
        f.writeframes(np.round(np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())


def read(file):
    """A WAV file's samples, (frames, channels) in -1..1, and its sample rate."""
    with wave.open(str(file), "rb") as f:
        frames = np.frombuffer(f.readframes(f.getnframes()), dtype="<i2")
        return frames.reshape(-1, f.getnchannels()) / 32768, f.getframerate()


def report():
    """Prints every sound's length, peak, RMS, loudness (its loudest 400 ms) and size, and the total."""
    print(f"{'sound':13} {'length':>8} {'peak':>9} {'RMS':>9} {'loudness':>10} {'size':>9}")
    total = 0
    for name in RECIPES:
        file = OUT / f"{name}.wav"
        if not file.exists():
            print(f"{name:13} missing")
            continue
        x, rate = read(file)
        total += file.stat().st_size
        print(f"{name:13} {len(x) / rate:6.2f} s {20 * np.log10(max(np.max(np.abs(x)), 1e-9)):6.1f} dB"
              f" {10 * np.log10(max(np.mean(x ** 2), 1e-18)):6.1f} dB {loudness(x, rate):5.1f} LUFS"
              f" {file.stat().st_size / 1024:6.0f} KB")
    print(f"{len(RECIPES)} sounds, {total / 1e6:.2f} MB ({total / 2 ** 20:.2f} MiB)")


def main(args):
    names = [a for a in args if not a.startswith("-")]
    unknown = [n for n in names if n not in RECIPES]
    if unknown:
        sys.exit(f"unknown sound: {', '.join(unknown)}\nknown: {', '.join(RECIPES)}")
    if names or "--report" not in args:
        for name in names or RECIPES:
            write(name, render(name))
        print(f"wrote {len(names or RECIPES)} sounds to {OUT}")
    if "--report" in args:
        report()


if __name__ == "__main__":
    main(sys.argv[1:])
