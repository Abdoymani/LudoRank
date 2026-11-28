"""Synthesizes LudoRank's game sound effects as small mono WAV files.

All sounds are generated from scratch (sine/noise synthesis), so they carry
no third-party license.

Usage: python3 tool/generate_sounds.py <output_dir> [name ...]
With names, only those sounds are written (the others stay byte-identical).
"""
import sys
import wave
import numpy as np

SR = 22050
rng = np.random.default_rng(7)


def t(d):
    return np.arange(int(SR * d)) / SR


def env(n, attack=0.004, decay=8.0):
    x = np.arange(n) / SR
    a = np.clip(x / attack, 0, 1)
    return a * np.exp(-decay * x)


def tone(freq, d, decay=8.0, harmonics=((1, 1.0),), attack=0.004):
    x = t(d)
    s = sum(a * np.sin(2 * np.pi * freq * h * x) for h, a in harmonics)
    return s * env(len(x), attack, decay)


def bell(freq, d, decay=6.0):
    return tone(freq, d, decay, ((1, 1.0), (2.01, 0.35), (3.02, 0.15), (4.2, 0.06)))


def sweep(f0, f1, d, decay=6.0):
    x = t(d)
    f = np.geomspace(f0, f1, len(x))
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * env(len(x), 0.003, decay)


def noise(d, decay=40.0, lp=0.3):
    n = rng.standard_normal(int(SR * d))
    # one-pole low-pass for a softer, woodier noise
    out = np.zeros_like(n)
    acc = 0.0
    for i, v in enumerate(n):
        acc += lp * (v - acc)
        out[i] = acc
    return out * env(len(n), 0.001, decay)


def place(buf, s, at):
    i = int(at * SR)
    end = min(len(buf), i + len(s))
    buf[i:end] += s[: end - i]
    return buf


def mix(*parts):
    n = max(len(p) for p in parts)
    out = np.zeros(n)
    for p in parts:
        out[: len(p)] += p
    return out


def silence(d):
    return np.zeros(int(SR * d))


def _wood_tap(freq, seed):
    # a soft, short wooden tap: a low-mid body with an inharmonic wood
    # partial, a very short filtered click on top, quick decay
    own = np.random.default_rng(seed)
    body = tone(freq, 0.07, 65, ((1, 1.0), (2.32, 0.18), (3.9, 0.05)), 0.002)
    n = own.standard_normal(int(SR * 0.012))
    click = np.convolve(n, np.ones(6) / 6, mode='same') * env(len(n), 0.0005, 300)
    return mix(body, 0.25 * click)


def step():
    # a token landing on a square; two pitches alternate per square so a
    # long move sounds like steps, not a machine-gun click
    noise(0.09, 70, 0.25)  # keeps the shared rng where the other sounds expect it
    return _wood_tap(430, 101)


def step_alt():
    return _wood_tap(490, 202)


def dice():
    # a die rattling in a cup, then settling on the table
    b = silence(0.9)
    at = 0.0
    gap = 0.03
    for k in range(9):
        click = mix(tone(rng.uniform(1700, 2600), 0.03, 140, ((1, 1.0), (1.6, 0.4))) * 0.45,
                    noise(0.03, 120, 0.6) * 0.5)
        place(b, click * (1 - k * 0.06), at)
        at += gap * rng.uniform(0.8, 1.3)
        gap *= 1.1
    place(b, mix(0.8 * tone(240, 0.12, 35, ((1, 1.0), (2.3, 0.3))), 0.3 * noise(0.1, 45, 0.15)), at)
    return b


def six():
    # bright two-note sparkle for rolling a six
    b = silence(0.42)
    place(b, 0.55 * bell(1046.5, 0.3, 9), 0.0)
    place(b, 0.55 * bell(1568.0, 0.32, 8), 0.09)
    return b


def enter():
    # a token leaves its base and enters the board: upward pop
    return mix(0.6 * sweep(330, 990, 0.16, 14), 0.25 * noise(0.04, 90, 0.5))


def capture():
    # knock-out: punchy hit plus a falling "bonk"
    b = silence(0.42)
    place(b, 0.7 * noise(0.08, 45, 0.35), 0.0)
    place(b, 0.75 * sweep(700, 140, 0.38, 7), 0.0)
    return b


def home():
    # a token reaches home: rising major arpeggio
    b = silence(0.75)
    for i, f in enumerate((523.25, 659.25, 783.99, 1046.5)):
        place(b, 0.45 * bell(f, 0.45, 7), i * 0.075)
    return b


def cancelled():
    # third six: turn lost, two falling soft tones
    b = silence(0.6)
    place(b, 0.5 * tone(392.0, 0.25, 9, ((1, 1.0), (3, 0.2))), 0.0)
    place(b, 0.5 * tone(311.13, 0.35, 7, ((1, 1.0), (3, 0.2))), 0.18)
    return b


def win():
    # match finished: short fanfare and a held chord
    b = silence(1.6)
    for i, f in enumerate((523.25, 659.25, 783.99)):
        place(b, 0.4 * bell(f, 0.3, 8), i * 0.11)
    for f in (523.25, 659.25, 783.99, 1046.5):
        place(b, 0.28 * bell(f, 1.2, 2.6), 0.36)
    return b


def token_return():
    # a captured token slides back to its base: soft falling whoosh that
    # lands with a small wooden plop when the token reaches its pad
    r = np.random.default_rng(11)
    d = 0.34
    n = int(SR * d)
    x = np.arange(n) / SR
    raw = r.standard_normal(n)
    # noise swept down by a moving one-pole low-pass
    cutoff = np.linspace(0.35, 0.04, n)
    whoosh = np.zeros(n)
    acc = 0.0
    for i in range(n):
        acc += cutoff[i] * (raw[i] - acc)
        whoosh[i] = acc
    swell = np.sin(np.pi * np.clip(x / 0.30, 0, 1)) ** 1.5
    b = silence(0.42)
    place(b, 1.6 * whoosh * swell, 0.0)
    place(b, 0.35 * sweep(880, 330, 0.28, 5), 0.0)
    place(b, 0.6 * tone(260, 0.1, 40, ((1, 1.0), (2.4, 0.3))), 0.29)
    return b


def reveal():
    # the final ranking appears: a short, bright two-note sparkle
    b = silence(0.5)
    place(b, 0.5 * bell(1318.5, 0.32, 10), 0.0)
    place(b, 0.42 * bell(1975.5, 0.36, 9), 0.06)
    place(b, 0.18 * bell(2637.0, 0.3, 12), 0.12)
    return b


# name -> (synth, sample rate). The original set is 22.05kHz; sounds added
# later are 44.1kHz.
SOUNDS = {
    'step': (step, 22050),
    'dice': (dice, 22050),
    'six': (six, 22050),
    'enter': (enter, 22050),
    'capture': (capture, 22050),
    'home': (home, 22050),
    'cancelled': (cancelled, 22050),
    'win': (win, 22050),
    'return': (token_return, 44100),
    'reveal': (reveal, 44100),
    'step2': (step_alt, 22050),
}


def write(path, s):
    # trim trailing near-silence
    loud = np.nonzero(np.abs(s) > 1e-3 * np.max(np.abs(s)))[0]
    s = s[: loud[-1] + 1]
    peak = np.max(np.abs(s)) or 1.0
    s = s / peak * 0.85
    # 5 ms fade-out to avoid clicks
    fade = int(0.005 * SR)
    s[-fade:] *= np.linspace(1, 0, fade)
    data = (s * 32767).astype('<i2').tobytes()
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data)


if __name__ == '__main__':
    out = sys.argv[1]
    only = set(sys.argv[2:])
    for name, (fn, rate) in SOUNDS.items():
        SR = rate
        s = fn()  # the shared rng advances even when the file is skipped
        if only and name not in only:
            continue
        write(f'{out}/{name}.wav', s)
        print('wrote', name)
