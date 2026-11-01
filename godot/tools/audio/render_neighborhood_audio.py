"""Original, deterministic neighborhood one-shots. No recordings or dependencies.

PCM16 mono at 22.05 kHz. All clips fade to silence; none is a looping bed.
Run: python godot/tools/audio/render_neighborhood_audio.py
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
    rng = random.Random(11012026)
    result = {}
    # Soft distant broadband air/road texture, without engine or horn imitation.
    air = []
    low = slow = 0.0
    for i in range(RATE * 8):
        t = i / RATE
        low += 0.075 * (rng.uniform(-1.0, 1.0) - low)
        slow += 0.012 * (low - slow)
        envelope = math.sin(math.pi * i / (RATE * 8 - 1)) ** 2
        air.append((low - slow) * 0.72 * envelope * (0.8 + 0.2 * math.sin(t * 1.7)))
    result["neighborhood_air"] = air
    # Short irregular chirrup phrases, not metronomic single sine beeps.
    for variant in range(2):
        birds = [0.0] * int(RATE * 1.8)
        for start, duration, base, sweep in ((0.12, 0.15, 2800, 1500),
                                             (0.38, 0.11, 3400, -900),
                                             (0.91, 0.23, 2600, 1700)):
            phase = 0.0
            start += variant * 0.065
            for j in range(int(duration * RATE)):
                u = j / (duration * RATE)
                phase += math.tau * (base + variant * 240 + sweep * math.sin(u * math.pi)) / RATE
                env = math.sin(math.pi * u) ** 2
                flutter = 0.7 + 0.3 * math.sin(u * math.tau * (3 + variant))
                birds[int(start * RATE) + j] += 0.16 * env * flutter * (math.sin(phase) + 0.16 * math.sin(phase * 2))
        result[f"neighborhood_bird_{variant + 1}"] = birds
    # A hollow rubber impact with a very short noise attack and resonant decay.
    bounce = []
    phase = 0.0
    for i in range(int(RATE * 0.32)):
        t = i / RATE
        phase += math.tau * (88 + 75 * math.exp(-t * 35)) / RATE
        attack = min(1.0, t / 0.002)
        tail = min(1.0, (0.32 - t) / 0.035)
        bounce.append(attack * tail * (0.32 * math.exp(-t * 22) * math.sin(phase)
                      + 0.10 * rng.uniform(-1, 1) * math.exp(-t * 110)))
    result["neighborhood_court_bounce"] = bounce
    return result


def write_assets(destination=OUT):
    destination.mkdir(parents=True, exist_ok=True)
    report = {}
    for name, samples in render().items():
        with wave.open(str(destination / (name + ".wav")), "wb") as wav:
            wav.setnchannels(1)
            wav.setsampwidth(2)
            wav.setframerate(RATE)
            wav.writeframes(struct.pack("<%dh" % len(samples), *(round(v * 32767) for v in samples)))
        report[name] = {"seconds": len(samples) / RATE,
                        "peak": round(max(map(abs, samples)), 5),
                        "rms": round(math.sqrt(sum(v*v for v in samples) / len(samples)), 5)}
    return report


if __name__ == "__main__":
    print(json.dumps(write_assets(), indent=2))
