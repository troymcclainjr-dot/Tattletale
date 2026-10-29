#!/usr/bin/env python3
"""Convert the music video media/still_there.mp4 to godot/assets/video/still_there.ogv.

    python godot/tools/audio/convert_video.py              # default quality
    python godot/tools/audio/convert_video.py --quality 8  # 0..10, higher = bigger and cleaner

Godot plays Ogg Theora video with Vorbis audio natively (VideoStreamTheora; no import step), and
nothing else, so the H.264/AAC mp4 has to be re-encoded. Needs ffmpeg (with libtheora and libvorbis)
on PATH. The mp4 stays where it is: the web game plays that one.

What the command does, and why:
  * Same size (854x480) and frame rate (12 fps) as the source: no scaling, no frame dropping.
  * -c:v libtheora -q:v 7: constant quality. Against the source, q7 gives SSIM 0.98 / PSNR 39 dB at
    about 0.6 Mbit/s, and looks identical to the mp4 at 2x zoom; q8 and q9 add about 0.003 SSIM each
    for 30% more bytes. The source is itself only 0.4 Mbit/s H.264, so there is nothing to gain above that.
  * -g 120: a keyframe every 10 s. Godot plays the video start to end (its Theora player cannot seek),
    and keyframes are the expensive frames.
  * The colorspace filter re-codes the picture from the mp4's BT.709 YCbCr to BT.601 YCbCr with the same
    RGB values. Theora has no matrix flag and Godot's player decodes every Theora file as BT.601, so
    without this the colors would drift (about 2 levels on average, 15 at the saturated edges).
  * -c:a libvorbis -q:a 5: about 160 kbit/s stereo, 48 kHz like the source.
"""
import argparse
import os
import subprocess
import sys


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.normpath(os.path.join(here, "..", "..", ".."))
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--src", default=os.path.join(root, "media", "still_there.mp4"))
    ap.add_argument("--dst", default=os.path.join(root, "godot", "assets", "video", "still_there.ogv"))
    ap.add_argument("--quality", type=int, default=7, help="libtheora -q:v, 0..10 (default 7)")
    a = ap.parse_args()
    os.makedirs(os.path.dirname(a.dst), exist_ok=True)
    part = a.dst + ".part"  # written under another name so Godot never sees a half-written video
    cmd = ["ffmpeg", "-hide_banner", "-loglevel", "warning", "-nostats", "-y", "-i", a.src,
           "-vf", "colorspace=space=smpte170m:trc=bt709:primaries=bt709:range=tv:iall=bt709:format=yuv420p",
           "-c:v", "libtheora", "-q:v", str(a.quality), "-g", "120", "-pix_fmt", "yuv420p",
           "-c:a", "libvorbis", "-q:a", "5",
           "-f", "ogg", part]
    print(" ".join(cmd))
    code = subprocess.call(cmd)
    if code == 0:
        os.replace(part, a.dst)
        print("wrote %s (%.1f MB)" % (a.dst, os.path.getsize(a.dst) / 1e6))
    elif os.path.exists(part):
        os.remove(part)
    return code


if __name__ == "__main__":
    sys.exit(main())
