"""Deterministic original vehicle sounds; standard-library-only, no samples.

Run from any directory. Writes three 22.05 kHz mono PCM16 assets, ~190KB.
The loops are cyclic by construction; no network, DAW, external engine, or
recording dependency. Sound pitch/load/attenuation is handled in Godot.
"""
import json
import math
from pathlib import Path
import random
import struct
import wave

RATE = 22050
OUT = Path(__file__).resolve().parents[2] / "assets" / "audio"


def render():
    rng = random.Random(20550)
    n = RATE * 2
    # Integer harmonics over a two-second period: no loop-boundary impulse.
    engine = []
    for i in range(n):
        t = i / RATE
        pulse = sum(math.sin(2 * math.pi * 44 * k * t + k * 0.23) / k**1.3 for k in range(1, 13))
        firing = (0.78 + 0.13 * math.sin(2 * math.pi * 22 * t)
                  + 0.06 * math.sin(2 * math.pi * 3 * t))
        engine.append(0.24 * math.tanh(pulse * 1.3) * firing
                      + 0.018 * math.sin(2 * math.pi * 176 * t))
    # Cyclic random-phase noise band, broad and textured without tonal beeps.
    skid = [0.0] * n
    for harmonic in range(900, 6001, 31):
        frequency = harmonic * 0.5
        phase = rng.uniform(0, math.tau)
        amplitude = 0.018 * (1.0 - 0.45 * frequency / 3000)
        for i in range(n):
            skid[i] += amplitude * math.sin(math.tau * frequency * i / RATE + phase)
    horn = []
    for i in range(int(RATE * 0.42)):
        t = i / RATE
        envelope = min(1.0, t / 0.018, (0.42 - t) / 0.07)
        voice = 0.0
        for frequency in (349, 440):
            for k in range(1, 6):
                voice += math.sin(math.tau * frequency * k * t) * (0.1 / k**1.5)
        horn.append(envelope * voice)
    return {"vehicle_engine": engine, "vehicle_skid": skid, "vehicle_horn": horn}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    report = {}
    for name, samples in render().items():
        peak = max(abs(v) for v in samples)
        assert peak < 0.85, (name, peak)
        assert abs(sum(samples) / len(samples)) < 0.001, name
        if name != "vehicle_horn":
            # Adjacent-boundary jump cannot exceed normal sample-to-sample slope.
            slope = max(abs(b - a) for a, b in zip(samples, samples[1:]))
            assert abs(samples[-1] - samples[0]) <= slope * 1.01, name
        with wave.open(str(OUT / (name + ".wav")), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(RATE)
            wav.writeframes(struct.pack("<%dh" % len(samples), *(round(v * 32767) for v in samples)))
        report[name] = {"frames": len(samples), "seconds": len(samples) / RATE,
                        "peak": round(peak, 5), "rms": round(math.sqrt(sum(v*v for v in samples) / len(samples)), 5)}
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
