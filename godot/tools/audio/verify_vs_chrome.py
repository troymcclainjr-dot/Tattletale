#!/usr/bin/env python3
"""Check render_audio.py against the real js/audio.js running in Chrome.

    python godot/tools/audio/verify_vs_chrome.py              # everything, about 30 seconds
    python godot/tools/audio/verify_vs_chrome.py music tick   # some jobs

Optional: needs `pip install playwright` and the Chrome that is installed on the machine (it is
launched headless, nothing is downloaded). The real audio.js is loaded into a page, pointed at an
OfflineAudioContext instead of the speakers, and made to play the music (4 bars) and every sfx; the
same random numbers are given to render_audio.py as its noise, so the two can be compared.

Two Chrome quirks are switched off in the page first, because they are not part of the sound the
code asks for (see render_audio.py, DIFFERENCES FROM THE JS): an oscillator that starts off a
128-sample boundary is created with the wrong frequency for a few samples, and the 25 ms swing is
1102.5 samples (made 1102). Chrome also starts a source on ceil(t * rate) without any tolerance,
which render_audio.py is told to copy here, so late-starting voices line up to the sample.

One Chrome accident is removed from its output before comparing: at 0.07 s (3087.0000000000005 frames) the
shutter's second noise burst starts one frame before its gain automation does, so one full-gain sample
(-0.44) leaks through as a click. That is floating-point rounding, not the sound the code asks for.

Three kinds of check:
  exact    voices without noise at t > 0 must match sample for sample (max difference < 1 % of the peak)
  noise    shutter, knock and the music contain noise bursts that start between Chrome's sample frames,
           so the slices differ by a sub-sample shift; there the energy must match within 3 % and
           every third-octave band within 0.5 dB
  music    additionally the part below 1 kHz (kicks, bass, chords) must match within 1 %
"""
import base64
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render_audio as ra  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))

HARNESS = r"""
async ({job, sr, seconds}) => {
  const R = window.__R; let ri = 0;
  Math.random = () => R[ri++];
  ac = null;
  window.AudioContext = function () { return new OfflineAudioContext(1, Math.round(sr * seconds), sr); };
  window.setInterval = () => 0;      // initAudio() must not start its own scheduler
  S.musicOn = true;
  initAudio();                       // the real graph: master .8, musicG .3, sfxG .7, the noise buffer
  if (job.type === "music") {
    nextBar = 0; barN = 0;
    Object.defineProperty(ac, "currentTime", { get: () => 10.4, configurable: true });
    schedule();                      // the real scheduler: queues bars 0..3
  } else {
    sfx(job.name, job.arg);
  }
  const buf = await ac.startRendering();
  const f = buf.getChannelData(0);
  const u8 = new Uint8Array(f.buffer, f.byteOffset, f.byteLength);
  let s = ""; const CH = 0x8000;
  for (let i = 0; i < u8.length; i += CH) s += String.fromCharCode.apply(null, u8.subarray(i, i + CH));
  return btoa(s);
}
"""

NOISE_JOBS = {"shutter", "knock", "music"}
CHROME_CLICK = {"shutter": 3087}  # sample index of the rounding click described above


def decode(b64):
    return np.frombuffer(base64.b64decode(b64), dtype="<f4").astype(float)


def third_octave_db(x):
    frames = x[:len(x) // 2048 * 2048].reshape(-1, 2048) * np.hanning(2048)
    ps = np.mean(np.abs(np.fft.rfft(frames, axis=1)) ** 2, axis=0)
    f = np.fft.rfftfreq(2048, 1 / ra.SR)
    edges = [60 * 2 ** (i / 3) for i in range(0, 25)]
    return [10 * np.log10(ps[(f >= lo) & (f < hi)].sum() + 1e-30) for lo, hi in zip(edges[:-1], edges[1:])]


def lowpass(x, hz):
    spec = np.fft.rfft(x)
    spec[np.fft.rfftfreq(len(x), 1 / ra.SR) > hz] = 0
    return np.fft.irfft(spec, len(x))


def main():
    from playwright.sync_api import sync_playwright

    only = sys.argv[1:]
    # the Chrome quirks, switched off in the page and mirrored in render_audio
    js = open(os.path.join(ROOT, "js", "audio.js"), encoding="utf-8").read()
    for old, new in [("o.frequency.setValueAtTime(f,t);", "o.frequency.value=f;o.frequency.setValueAtTime(f,t);"),
                     ("(h%2?.025:0)", "(h%2?1102/44100:0)")]:
        assert old in js, "js/audio.js changed: update the patch list in verify_vs_chrome.py (%s)" % old
        js = js.replace(old, new)
    ra.SWING = 1102 / 44100
    ra._idx = lambda t: int(math.ceil(t * ra.SR))

    R = np.random.default_rng(2024).random(300000)

    def noise():  # the JS draws 44100 numbers for its noise buffer, then one per nz() call
        buf = (R[:ra.SR] * 2 - 1).astype(np.float32).astype(float)
        it = iter(R[ra.SR:])
        return ra.Noise(buf=buf, rand=lambda: next(it))

    jobs = [("music", {"type": "music"}, 13.7, 0.3 * 0.8, lambda: ra.render_music(noise())[0])]
    for n in ra.SFX_NAMES:
        jobs.append((n, {"type": "sfx", "name": n}, 3.0, 0.7 * 0.8, (lambda nm: lambda: ra.render_sfx(nm, noise()))(n)))
    jobs.append(("snore_x1.6", {"type": "sfx", "name": "snore", "arg": 1.6}, 3.0, 0.7 * 0.8, lambda: ra.render_sfx("snore", noise(), 1.6)))
    for k in "0123456789*#":
        jobs.append(("dtmf_" + k, {"type": "sfx", "name": "dtmf", "arg": k}, 3.0, 0.7 * 0.8, (lambda kk: lambda: ra.render_sfx("dtmf", noise(), kk))(k)))

    fails = 0
    with sync_playwright() as p:
        browser = p.chromium.launch(channel="chrome", headless=True)
        print("Chrome", browser.version)
        page = browser.new_page()
        page.set_content("<html><body></body></html>")
        page.evaluate("window.S = {musicOn: true, mode: 'play'}")
        page.add_script_tag(content=js)
        page.evaluate("R => { window.__R = R; }", R.tolist())
        print("%-11s %-6s %9s %9s %11s  %s" % ("job", "kind", "js peak", "py peak", "difference", "result"))
        for name, job, seconds, bus, render in jobs:
            if only and name not in only:
                continue
            chrome = decode(page.evaluate(HARNESS, {"job": job, "sr": ra.SR, "seconds": seconds}))
            if name in CHROME_CLICK:
                assert abs(chrome[CHROME_CLICK[name]]) > 0.2, "the Chrome click moved: update CHROME_CLICK"
                chrome[CHROME_CLICK[name]] = 0.0
            mine = render() * bus
            n = len(mine)
            ref = chrome[:n]
            peak = float(np.max(np.abs(chrome)))
            kind = "noise" if name in NOISE_JOBS else "exact"
            if kind == "exact":
                d = float(np.max(np.abs(ref - mine))) / peak
                ok, what = d < 0.01, "max diff %.4f %% of peak" % (100 * d)
            else:
                e = float(np.sum(ref * ref) / np.sum(mine * mine))
                bj, bp = third_octave_db(ref), third_octave_db(mine)
                band = max(abs(a - b) for a, b in zip(bj, bp) if a > max(bj) - 40)
                ok = abs(e - 1) < 0.03 and band < 0.5
                what = "energy x%.3f, worst band %.2f dB" % (e, band)
                if name == "music":
                    lo = float(np.sqrt(np.mean((lowpass(ref, 1000) - lowpass(mine, 1000)) ** 2) / np.mean(lowpass(mine, 1000) ** 2)))
                    ok = ok and lo < 0.01
                    what += ", below 1 kHz %.2f %%" % (100 * lo)
            tail = float(np.max(np.abs(chrome[n:]))) if len(chrome) > n else 0.0
            ok = ok and tail < 1e-4  # nothing rings on in Chrome after the file ends
            fails += not ok
            print("%-11s %-6s %9.5f %9.5f  %-40s %s" % (name, kind, peak, np.max(np.abs(mine)), what, "ok" if ok else "FAIL"))
        browser.close()
    print("RESULT:", "all match" if not fails else "%d differ" % fails)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
