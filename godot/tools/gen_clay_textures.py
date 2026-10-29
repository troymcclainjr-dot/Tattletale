"""Generates the shared clay textures used by every clay material in Godot.

Same recipe as the thumbprinted bump canvas in js/engine.js (overlapping soft
ellipses on mid-gray), at 1024px and tileable, plus a normal map and a faint
albedo mottle. Run:  python godot/tools/gen_clay_textures.py
"""
import os, struct, zlib
import numpy as np

OUT = os.path.join(os.path.dirname(__file__), "..", "assets", "materials")
N = 1024
rng = np.random.default_rng(2009)  # the year Gary moved into the gutter


def write_png(path, arr):
    """arr: HxW (gray) or HxWx3/4 uint8."""
    arr = np.ascontiguousarray(arr)
    if arr.ndim == 2:
        ctype, ch = 0, 1
    else:
        ch = arr.shape[2]
        ctype = {3: 2, 4: 6}[ch]
    h, w = arr.shape[:2]
    raw = b"".join(b"\x00" + arr[y].tobytes() for y in range(h))
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def thumbprints(count, rmin, rmax, seed_shift=0):
    """Tileable height field of overlapping soft ellipse dents/bumps, 0..1, mean ~0.5."""
    h = np.full((N, N), 0.5, np.float32)
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    for _ in range(count):
        cx, cy = rng.uniform(0, N, 2)
        a = rng.uniform(rmin, rmax)
        b = a * rng.uniform(0.35, 0.7)
        th = rng.uniform(0, np.pi)
        v = rng.uniform(-1, 1)  # dent or ridge
        r = int(a * 1.6) + 2
        x0, y0 = int(cx) - r, int(cy) - r
        ys = (np.arange(y0, y0 + 2 * r)) % N
        xs = (np.arange(x0, x0 + 2 * r)) % N
        dx = xx[:2 * r, :2 * r] + x0 - cx
        dy = yy[:2 * r, :2 * r] + y0 - cy
        c, s = np.cos(th), np.sin(th)
        u = (dx * c + dy * s) / a
        w = (-dx * s + dy * c) / b
        d2 = u * u + w * w
        # a thumb press: soft dish with a slightly raised rim
        prof = np.exp(-d2 * 2.2) - 0.35 * np.exp(-((np.sqrt(d2) - 1.05) ** 2) * 9.0)
        h[np.ix_(ys, xs)] += 0.055 * v * prof
    return h


def blur(h, k=2):
    for _ in range(k):
        h = (h + np.roll(h, 1, 0) + np.roll(h, -1, 0) + np.roll(h, 1, 1) + np.roll(h, -1, 1)) / 5.0
    return h


def normal_from_height(h, strength):
    dx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * 0.5 * strength
    dy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * 0.5 * strength
    nz = np.ones_like(h)
    n = np.stack([-dx, dy, nz], -1)  # OpenGL-style (green up), what Godot expects
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).clip(0, 255).astype(np.uint8)


def main():
    os.makedirs(OUT, exist_ok=True)
    # big soft thumb presses + small fingertip dabs, like hand-worked plasticine
    h = thumbprints(900, 14, 46) + (thumbprints(1100, 5, 13) - 0.5) * 0.4
    h = blur(h, 2)
    h = (h - h.min()) / (h.max() - h.min())
    write_png(os.path.join(OUT, "clay_height.png"), (h * 255).astype(np.uint8))
    write_png(os.path.join(OUT, "clay_normal.png"), normal_from_height(h, 30.0))
    # faint mottle: low-frequency value variation, 0.88..1.0 (multiplies albedo)
    m = blur(thumbprints(260, 40, 120), 6)
    m = (m - m.min()) / (m.max() - m.min())
    write_png(os.path.join(OUT, "clay_mottle.png"), ((0.88 + 0.12 * m) * 255).astype(np.uint8))
    print("wrote", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
