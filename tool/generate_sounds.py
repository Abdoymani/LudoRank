"""Synthesizes LudoRank's game sound effects as small mono WAV files.

All sounds are generated from scratch (sine/noise synthesis), so they carry
no third-party license. Usage: python3 synth.py <output_dir>
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


def step():
    # soft wooden "tok" of a token landing on a square
    return mix(0.7 * tone(620, 0.09, 55, ((1, 1.0), (2.7, 0.25))), 0.35 * noise(0.09, 70, 0.25))


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


SOUNDS = {
    'step': step,
    'dice': dice,
    'six': six,
    'enter': enter,
    'capture': capture,
    'home': home,
    'cancelled': cancelled,
    'win': win,
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
    for name, fn in SOUNDS.items():
        write(f'{out}/{name}.wav', fn())
        print('wrote', name)
