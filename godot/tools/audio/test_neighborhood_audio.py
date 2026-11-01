"""Offline checks of shipped original audio, not a Godot playback substitute."""
import math
from pathlib import Path
import struct
import unittest
import wave

from render_neighborhood_audio import OUT, RATE, render


class NeighborhoodAudio(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.rendered = render()

    def test_shipped_pcm_matches_deterministic_generator(self):
        total = 0
        for name, samples in self.rendered.items():
            path = OUT / (name + ".wav")
            total += path.stat().st_size
            with wave.open(str(path), "rb") as wav:
                self.assertEqual((wav.getnchannels(), wav.getsampwidth(), wav.getframerate()), (1, 2, RATE))
                self.assertEqual(wav.getnframes(), len(samples))
                expected = struct.pack("<%dh" % len(samples), *(round(v * 32767) for v in samples))
                self.assertEqual(wav.readframes(wav.getnframes()), expected)
        self.assertLess(total, 540_000)

    def test_clips_have_headroom_no_dc_and_soft_ends(self):
        for name, samples in self.rendered.items():
            with self.subTest(clip=name):
                peak = max(map(abs, samples))
                rms = math.sqrt(sum(v*v for v in samples) / len(samples))
                self.assertGreater(rms, 0.003)
                self.assertLess(peak, 0.5)
                self.assertLess(abs(sum(samples) / len(samples)), 0.002)
                self.assertLess(abs(samples[0]), 0.0001)
                self.assertLess(abs(samples[-1]), 0.0001)

    def test_birds_are_short_phrases_with_silence_between(self):
        for name in ("neighborhood_bird_1", "neighborhood_bird_2"):
            samples = self.rendered[name]
            self.assertGreater(sum(abs(v) < 0.0001 for v in samples) / len(samples), 0.65)
        self.assertNotEqual(self.rendered["neighborhood_bird_1"], self.rendered["neighborhood_bird_2"])


if __name__ == "__main__":
    unittest.main()
