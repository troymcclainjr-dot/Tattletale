#!/usr/bin/env python3
"""Render the sound of Tattletale 2-Pack (js/audio.js) to 16-bit 44.1 kHz mono WAV files.

    python godot/tools/audio/render_audio.py              # writes godot/assets/audio/*.wav
    python godot/tools/audio/render_audio.py --out DIR    # somewhere else
    python godot/tools/audio/render_audio.py --only music snore dtmf_5

Needs Python 3 and numpy only. Then run `python godot/tools/godot_run.py --import` so Godot
imports the new/changed WAVs (this script also sets their import to uncompressed PCM, see
ensure_pcm_import). About 3 seconds.

js/audio.js is the spec. Every voice below is the same call as there, with the same numbers:

    osc(type, f, t, dur, peak, f2)   oscillator + env(.005 s attack, peak, dur decay), stops at t+dur+.05
    nz(t, dur, peak, hp)             white noise -> highpass(hp, Q 1 dB) -> env(.002 s attack, peak, dur decay)
    env(...)                         gain 0.0001 -> peak (exponential ramp) -> 0.0001 (exponential ramp)

Files written:

    music.wav         the beat as ONE seamless loop of the 4-bar PROG at 90 BPM (4 bars = 10.667 s =
                      470400 samples). audio.gd loops it forward over the whole file. Every note and
                      hit has died away before its bar ends, so the loop point is silence; anything
                      that did ring past the end would be folded back onto the start (render_music).
    sfx_<name>.wav    one file per effect: shutter click tick buzz honk door pickup win siren whistle
                      snore hangup busy cuffs cash knock step, plus sfx_dtmf_0 .. sfx_dtmf_9,
                      sfx_dtmf_star (*) and sfx_dtmf_hash (#). snore is rendered at arg = 1;
                      audio.gd scales it for other loudness.

LEVELS. Each file holds the JS signal where the JS sends it into its bus (each sound's own peak)
times the JS master gain (MASTER = 0.8). The bus gains stay in Godot (audio.gd: Music .3, SFX .7), so
the final level is exactly what the web game plays and the relative levels match. Nothing is
peak-normalised: that would change the balance. The loudest file is the music (kick, bass and chords
land together on beat 1 of bar 3: raw peak 1.18, 0.94 after the master gain), so it fits in 16 bits;
the script refuses to write a file that would clip. The table it prints is the file's own peak/rms.

FIDELITY. Checked against the real js/audio.js running in Chrome 156 (verify_vs_chrome.py: an
OfflineAudioContext, the same random numbers fed to both). Every sound with no late noise burst matches
sample for sample within 0.15 % of its peak (sines, early noise bursts, filters, sweeps and the FM
whistle to float precision; the band-limited square, sawtooth and triangle to 0.15 % at worst). The
shutter, the knock and the 4-bar music have noise bursts that Chrome starts between two sample frames,
so only their statistics can agree: energy within 0.1 %, every third-octave band within 0.35 dB
(music: 0.01 dB), the part below 1 kHz within 0.4 %. Matched on purpose: the biquad Q formula, Chrome's
wavetable harmonic counts and amplitude (BIQUAD_Q_MODE, WAVE_GAIN) and per-sample phase accumulation.

DIFFERENCES FROM THE JS (all inaudible or unavoidable):
  * Noise is seeded (--seed), so renders are reproducible. In the JS every hi-hat and snare takes a
    new random slice of its noise buffer on every bar; a loop repeats the same 32 hats / 8 snares.
  * Chrome starts an oscillator that is created with setValueAtTime(f, t) a few samples at the wrong
    frequency when t is not on a 128-sample boundary, which leaves a tonal note with a small phase offset
    (up to a full cycle). Not reproduced: the files have the phase the code asks for.
  * No leading 0.1 s of silence before bar 1 (the JS schedules the first bar at currentTime + .1).
  * Godot reads the 16-bit samples as value / 32767, which is what is written here (round(x * 32767)).
"""
import argparse
import math
import os
import re
import sys
import wave
import zlib

import numpy as np

SR = 44100
BEAT = 60.0 / 90.0
BAR = 4 * BEAT
LOOP_BARS = 4
LOOP_SAMPLES = int(round(LOOP_BARS * BAR * SR))  # 470400: the loop is a whole number of samples
MASTER = 0.8  # js: master.gain.value (musicG .3 and sfxG .7 are the Godot bus gains)
LOW = 0.0001  # js: the floor of every env()
SWING = 0.025  # js: every second hi-hat of a bar is pushed 25 ms late

PROG = [(45, (57, 60, 64)), (41, (53, 57, 60)), (48, (55, 60, 64)), (40, (56, 59, 64))]
DTMF = {"1": (697, 1209), "2": (697, 1336), "3": (697, 1477), "4": (770, 1209), "5": (770, 1336),
        "6": (770, 1477), "7": (852, 1209), "8": (852, 1336), "9": (852, 1477), "*": (941, 1209),
        "0": (941, 1336), "#": (941, 1477)}
DTMF_FILE = {"*": "star", "#": "hash"}
SFX_NAMES = ["shutter", "click", "tick", "buzz", "honk", "door", "pickup", "win", "siren", "whistle",
             "snore", "hangup", "busy", "cuffs", "cash", "knock", "step"]

# How a lowpass/highpass BiquadFilterNode turns its Q (the default 1 is in dB for these two types) into
# a biquad. "spec" is the Web Audio spec's cookbook formula, linear Q = 10^(Q/20); it matches Chrome
# 156 to float precision (checked against a real OfflineAudioContext). "old" is the pre-2019 WebKit
# formula, kept only so the difference can be tested.
BIQUAD_Q_MODE = "spec"

# WebAudio's square / sawtooth / triangle are band-limited wavetables. Chrome (and Edge) build them as
# below, and the numbers here reproduce its output to about 0.001 (checked against a real
# OfflineAudioContext), including how many harmonics survive at each pitch:
#  * 4096-point tables at 44.1 kHz = 2048 partials at the lowest pitch, 3 tables per octave, each
#    culled to 2048 * 2^(-i/3) partials; a note blends the two tables just above its pitch.
#  * every wave is scaled so the Gibbs overshoot of the full series peaks at 1.0, which leaves the
#    flat part of a square or sawtooth at 1 / 1.17898 (= 1 / ((2/pi) * Si(pi))).
PW_PARTIALS = 2048
PW_LOWEST_HZ = SR / 2 / PW_PARTIALS
PW_RANGES = int(0.5 + 3 * math.log2(2 * PW_PARTIALS))
GIBBS = 1.0 / 1.178979744
WAVE_GAIN = {"sine": 1.0, "triangle": 1.0, "square": GIBBS, "sawtooth": GIBBS}


# ------------------------------------------------------------------ the pieces of audio.js
def mf(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def _idx(t):
    """First sample frame at or after time t (seconds)."""
    return int(math.ceil(t * SR - 1e-6))


def env(tau, a, peak, dec):
    """env(g,t,a,peak,dec) at tau seconds after t: LOW -> peak over a, peak -> LOW over dec, then LOW."""
    g = np.full(tau.shape, LOW)
    up = tau < a
    g[up] = LOW * (peak / LOW) ** (tau[up] / a)
    dn = (tau >= a) & (tau < a + dec)
    g[dn] = peak * (LOW / peak) ** ((tau[dn] - a) / dec)
    return g


def _wave(kind, ph, f):
    """One of WebAudio's built-in waveforms (phase ph in radians), as Chrome builds it. f is the pitch in
    Hz, a number or one value per sample; it decides how many harmonics are kept."""
    if kind == "sine":
        return np.sin(ph)
    f = np.asarray(f, dtype=float)
    pr = np.clip(1 + 3 * np.log2(f / PW_LOWEST_HZ), 0, PW_RANGES - 1)  # position between the pitch tables
    i1 = np.floor(pr)
    i2 = np.minimum(i1 + 1, PW_RANGES - 1)
    fac = pr - i1
    n1 = np.floor(PW_PARTIALS * 2.0 ** (-i1 / 3))  # partials in the lower and the higher table
    n2 = np.floor(PW_PARTIALS * 2.0 ** (-i2 / 3))
    y = np.zeros(ph.shape)
    for k in range(1, int(np.max(n1)) + 1):
        if kind == "square":
            if k % 2 == 0:
                continue
            b = 4.0 / (math.pi * k)
        elif kind == "triangle":
            if k % 2 == 0:
                continue
            b = 8.0 / (math.pi * k) ** 2 * (1 if (k // 2) % 2 == 0 else -1)
        elif kind == "sawtooth":
            b = 2.0 / (math.pi * k) * (1 if k % 2 == 1 else -1)
        else:
            raise ValueError(kind)
        y += ((1 - fac) * (k <= n1) + fac * (k <= n2)) * b * np.sin(k * ph)
    return y * WAVE_GAIN[kind]


def _accum(freq):
    """Oscillator phase (radians) for a frequency given at every sample: WebAudio adds freq / SR cycles per
    sample, and the first sample is at phase 0."""
    inc = 2 * math.pi / SR * np.asarray(freq, dtype=float)
    return np.concatenate(([0.0], np.cumsum(inc[:-1])))


def _freq_exp(f, f2, dur, tau):
    """Frequency f -> f2 as exponentialRampToValueAtTime(f2, t+dur), then f2 held."""
    return f * (f2 / f) ** (np.minimum(tau, dur) / dur)


def _freq_lin(points, tau):
    """Frequency made of setValueAtTime + linearRampToValueAtTime(...) points = [(time, freq), ...]."""
    return np.interp(tau, [p[0] for p in points], [p[1] for p in points])


class Noise:
    """The JS noise buffer (one second of uniform white noise) and the random slice every nz() takes."""

    def __init__(self, seed=1, buf=None, rand=None):
        rng = np.random.default_rng(seed)
        self.rand = rand if rand is not None else rng.random
        self.buf = buf if buf is not None else rng.uniform(-1.0, 1.0, SR)

    def slice(self, n):
        off = int(self.rand() * 0.5 * SR)  # start(t, Math.random()*.5)
        return self.buf[off:off + n]


def biquad_coeffs(kind, hz):
    """BiquadFilterNode lowpass / highpass at hz with the default Q of 1 (dB)."""
    w0 = 2 * math.pi * hz / SR
    q_db = 1.0
    if BIQUAD_Q_MODE == "old":
        g = 10 ** (0.05 * q_db)
        d = math.sqrt((4 - math.sqrt(16 - 16 / (g * g))) / 2)
        alpha = 0.5 * d * math.sin(w0)
    else:
        alpha = math.sin(w0) / (2 * 10 ** (q_db / 20))
    c = math.cos(w0)
    if kind == "lowpass":
        b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
    else:
        b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2
    a0, a1, a2 = 1 + alpha, -2 * c, 1 - alpha
    return b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0


def biquad(x, kind, hz):
    b0, b1, b2, a1, a2 = biquad_coeffs(kind, hz)
    out = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, xi in enumerate(x.tolist()):
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        out[i] = yi
        x2, x1 = x1, xi
        y2, y1 = y1, yi
    return np.array(out)


class Mix:
    """A mono mix buffer. Each voice comes back as (first_sample, samples) and is added where it belongs."""

    def __init__(self, seconds=0.0):
        self.buf = np.zeros(int(math.ceil(seconds * SR)))

    def add(self, voice):
        i0, y = voice
        end = i0 + len(y)
        if end > len(self.buf):
            self.buf = np.pad(self.buf, (0, end - len(self.buf)))
        self.buf[i0:end] += y


def osc(kind, f, t, dur, peak, f2=None):
    """osc(type,f,t,dur,peak,dest,f2): f -> f2 exponential sweep over dur if f2 is given."""
    i0 = _idx(t)
    n = _idx(t + dur + 0.05) - i0
    tau = np.maximum(np.arange(i0, i0 + n) / SR - t, 0.0)
    pitch = _freq_exp(f, f2, dur, tau) if f2 else np.full(tau.shape, float(f))
    return i0, _wave(kind, _accum(pitch), pitch) * env(tau, 0.005, peak, dur)


def nz(noise, t, dur, peak, hp):
    """nz(t,dur,peak,hp,dest): noise slice -> highpass -> env(.002 s attack)."""
    i0 = _idx(t)
    n = _idx(t + dur + 0.05) - i0
    tau = np.maximum(np.arange(i0, i0 + n) / SR - t, 0.0)
    return i0, biquad(noise.slice(n), "highpass", hp) * env(tau, 0.002, peak, dur)


# ------------------------------------------------------------------ the music
def render_music(noise):
    """schedule() for four bars, folded into one loop. Returns (loop_samples, folded_peak)."""
    pad = 3.0
    mix = Mix(LOOP_BARS * BAR + pad)
    for barn in range(LOOP_BARS):
        t = barn * BAR
        root, ch = PROG[barn % 4]
        mix.add(osc("sine", 150, t, .32, .9, 42))
        mix.add(osc("sine", 150, t + 2 * BEAT, .3, .6, 42))
        mix.add(osc("sine", 150, t + 2.5 * BEAT, .3, .5, 42))
        mix.add(nz(noise, t + BEAT, .16, .35, 1500))
        mix.add(nz(noise, t + 3 * BEAT, .16, .35, 1500))
        for h in range(8):
            mix.add(nz(noise, t + h * BEAT / 2 + (SWING if h % 2 else 0), .04, .12 if h % 2 else .08, 7000))
        mix.add(osc("sine", mf(root), t, BAR * .9, .28))
        for n in ch:
            mix.add(osc("triangle", mf(n), t, 2.2, .045))
        for n in ch:
            mix.add(osc("triangle", mf(n), t + 2.5 * BEAT, .6, .025))
    buf = mix.buf
    loop = np.zeros(LOOP_SAMPLES)
    folded = 0.0
    for start in range(0, len(buf), LOOP_SAMPLES):  # whatever rings past the end lands on the start
        chunk = buf[start:start + LOOP_SAMPLES]
        loop[:len(chunk)] += chunk
        if start:
            folded = max(folded, float(np.max(np.abs(chunk))))
    return loop, folded


# ------------------------------------------------------------------ the sound effects
def render_sfx(name, noise, arg=None):
    """sfx(name, arg) at t = 0. For dtmf, arg is the key ("0".."9", "*", "#")."""
    m = Mix()
    t = 0.0
    if name == "shutter":
        m.add(nz(noise, t, .05, .6, 2000)); m.add(nz(noise, t + .07, .04, .4, 3000))
    elif name == "click":
        m.add(osc("square", 900, t, .03, .12))
    elif name == "tick":
        m.add(osc("sine", 1200, t, .08, .2))
    elif name == "buzz":
        m.add(osc("sawtooth", 110, t, .35, .25))
    elif name == "honk":
        m.add(osc("square", 330, t, .28, .12)); m.add(osc("square", 415, t, .28, .12))
    elif name == "door":
        m.add(nz(noise, t, .12, .4, 400))
    elif name == "pickup":
        m.add(nz(noise, t, .06, .3, 800))
        m.add(osc("sine", 350, t + .15, .6, .1)); m.add(osc("sine", 440, t + .15, .6, .1))
    elif name == "win":
        for i, f in enumerate([523, 659, 784, 1046]):
            m.add(osc("triangle", f, t + i * .08, .25, .18))
    elif name == "siren":
        i0, n = _idx(t), _idx(t + 2.6)
        tau = np.maximum(np.arange(i0, n) / SR - t, 0.0)
        pts = [(0.0, 700.0)]
        for i in range(4):
            pts += [(i * .6 + .3, 1000.0), (i * .6 + .6, 700.0)]
        m.add((i0, np.sin(_accum(_freq_lin(pts, tau))) * env(tau, .05, .12, 2.4)))
    elif name == "whistle":
        i0, n = _idx(t), _idx(t + .3)
        tau = np.maximum(np.arange(i0, n) / SR - t, 0.0)
        # 2500 Hz sine whose frequency is pushed by a 38 Hz sine LFO of depth 160 Hz
        lfo = np.sin(_accum(np.full(tau.shape, 38.0)))
        m.add((i0, np.sin(_accum(2500.0 + 160.0 * lfo)) * env(tau, .01, .22, .22)))
    elif name == "snore":
        L = arg or 1
        i0, n = _idx(t), _idx(t + 1.5)
        tau = np.maximum(np.arange(i0, n) / SR - t, 0.0)
        pitch = _freq_lin([(0.0, 70.0), (.7, 95.0), (1.3, 60.0)], tau)
        saw = _wave("sawtooth", _accum(pitch), pitch)
        g = np.full(tau.shape, LOW)
        up = tau < .4  # g: .0001 -> .12*L (t+.4) -> .0001 (t+1.4); same shape as env()
        g[up] = LOW * (.12 * L / LOW) ** (tau[up] / .4)
        dn = (tau >= .4) & (tau < 1.4)
        g[dn] = .12 * L * (LOW / (.12 * L)) ** ((tau[dn] - .4) / 1.0)
        m.add((i0, biquad(saw, "lowpass", 500) * g))
    elif name == "hangup":
        m.add(osc("sine", 120, t, .25, .6, 60))
    elif name == "busy":
        for i in range(4):
            m.add(osc("sine", 480, t + i * .5, .25, .15)); m.add(osc("sine", 620, t + i * .5, .25, .15))
    elif name == "cuffs":
        m.add(osc("sine", 2400, t, .12, .3)); m.add(osc("sine", 1800, t + .05, .25, .2))
        m.add(nz(noise, t, .05, .3, 4000))
    elif name == "cash":
        m.add(osc("square", 1320, t, .06, .1)); m.add(osc("square", 1760, t + .07, .12, .1))
    elif name == "knock":
        for i in range(3):
            m.add(osc("sine", 140, t + i * .18, .1, .5, 70)); m.add(nz(noise, t + i * .18, .03, .25, 600))
    elif name == "step":
        m.add(osc("triangle", 660, t, .08, .14)); m.add(osc("triangle", 990, t + .07, .12, .14))
    elif name == "dtmf":
        for f in DTMF.get(str(arg), DTMF["1"]):
            m.add(osc("sine", f, t, .16, .12))
    else:
        raise ValueError(name)
    return m.buf


# ------------------------------------------------------------------ files
def all_jobs():
    """(file stem, function(noise) -> (float samples before the master gain, note)) for every file."""
    def music(nz_):
        loop, folded = render_music(nz_)
        return loop, "ringing past the loop end, folded onto the start: peak %.1e" % folded

    def sfx(name, arg=None):
        return lambda nz_: (render_sfx(name, nz_, arg), "")

    jobs = [("music", music)]
    for n in SFX_NAMES:
        jobs.append(("sfx_" + n, sfx(n)))
    for key in "0123456789*#":
        jobs.append(("sfx_dtmf_" + DTMF_FILE.get(key, key), sfx("dtmf", key)))
    return jobs


def to_pcm16(x):
    peak = float(np.max(np.abs(x))) if len(x) else 0.0
    if peak >= 1.0:
        raise SystemExit("this would clip (peak %.3f); lower MASTER or fix the render" % peak)
    return np.clip(np.round(x * 32767.0), -32768, 32767).astype("<i2")


def write_wav(path, pcm):
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


# Godot imports a WAV as lossy QOA by default (compress/mode=2). These files are tiny, so keep them
# uncompressed (compress/mode=0, 16-bit PCM). The next `godot_run.py --import` picks the change up.
IMPORT_FILE = """[remap]

importer="wav"
type="AudioStreamWAV"

[params]

force/8_bit=false
force/mono=false
force/max_rate=false
force/max_rate_hz=44100
edit/trim=false
edit/normalize=false
edit/loop_mode=0
edit/loop_begin=0
edit/loop_end=-1
compress/mode=0
"""


def ensure_pcm_import(wav_path):
    """Make sure <wav>.import asks for uncompressed PCM; create it (Godot fills in the rest) if missing."""
    path = wav_path + ".import"
    if not os.path.exists(path):
        text = IMPORT_FILE
    else:
        with open(path, encoding="utf-8", newline="") as f:
            old = f.read()
        text = re.sub(r"^compress/mode=\d+", "compress/mode=0", old, flags=re.M)
        if text == old:
            return
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def in_godot_project(path):
    """True if some folder above path holds a project.godot."""
    d = os.path.abspath(path)
    while True:
        if os.path.exists(os.path.join(d, "project.godot")):
            return True
        parent = os.path.dirname(d)
        if parent == d:
            return False
        d = parent


def main(argv=None):
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--out", default=os.path.normpath(os.path.join(here, "..", "..", "assets", "audio")))
    ap.add_argument("--seed", type=int, default=1, help="seed for the noise (default 1)")
    ap.add_argument("--only", nargs="*", help="file stems to render, e.g. music snore sfx_dtmf_5 (default: all)")
    a = ap.parse_args(argv)
    os.makedirs(a.out, exist_ok=True)
    godot = in_godot_project(a.out)
    print("%-18s %8s %8s %9s %9s  (peak and rms of the file, i.e. after the master gain)" % ("file", "seconds", "samples", "peak", "rms"))
    for stem, fn in all_jobs():
        short = stem[4:] if stem.startswith("sfx_") else stem
        if a.only and stem not in a.only and short not in a.only:
            continue
        noise = Noise(seed=[a.seed, zlib.crc32(stem.encode())])  # every file draws its own slices
        x, note = fn(noise)
        x = x * MASTER
        pcm = to_pcm16(x)
        write_wav(os.path.join(a.out, stem + ".wav"), pcm)
        if godot:
            ensure_pcm_import(os.path.join(a.out, stem + ".wav"))
        print("%-18s %8.3f %8d %9.4f %9.4f  %s" % (stem + ".wav", len(x) / SR, len(x), np.max(np.abs(x)),
                                                  math.sqrt(float(np.mean(x * x))), note))
    return 0


if __name__ == "__main__":
    sys.exit(main())
