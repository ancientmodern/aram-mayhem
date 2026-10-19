"""[vfx-calib] Side-by-side of one ability: Riot's official preview video vs our render (src/debug/vfx_compare.gd).

Both sides are shown as the frame and as the "added light" (frame - pre-cast baseline, same camera), which is
independent of the map and lighting: for League's gamma-space additive blending the difference IS the colour the
effect added. Metrics per time: added-light energy (sum over the crop / crop area, x1000), the 99th percentile of
the added value and the share of pixels the effect brightened by > 0.12 or darkened by > 0.12.

Usage:
  python tools/vfx_compare.py --video tools/extracted/ability_videos/Leona_W1.webm --cast 1.15 \
      --center 745,315 --ours "%APPDATA%/Godot/app_userdata/ARAM- Mayhem/vc_leona_W" --times 0.5,2.0 \
      --scale 1.5 --crop 260 --out tools/extracted/ability_videos/cmp/leona_W.png
  --center: champion feet in the video frame (px); ours are at the screen centre (camera focus).
  --scale: video px per our px (zoom difference); --crop: crop size in OUR px (square around the champion,
  shifted up by --lift of it so effects above the feet fit).
Needs imageio-ffmpeg (pip) for the decoder; frames are cached in tools/extracted/ability_videos/frames/.
"""
import argparse
import os
import subprocess

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))


def ffmpeg():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def video_frame(video, t):
    cache = os.path.join(ROOT, "tools/extracted/ability_videos/frames", os.path.splitext(os.path.basename(video))[0])
    os.makedirs(cache, exist_ok=True)
    p = os.path.join(cache, "t%06d.png" % int(round(t * 1000)))
    if not os.path.exists(p):
        subprocess.run([ffmpeg(), "-hide_banner", "-loglevel", "error", "-y", "-ss", "%.3f" % t, "-i", video,
                        "-frames:v", "1", p], check=True)
    return np.asarray(Image.open(p).convert("RGB")).astype(np.float32) / 255.0


def crop(img, cx, cy, size, lift):
    h, w = img.shape[:2]
    x0 = int(round(cx - size / 2))
    y0 = int(round(cy - size / 2 - size * lift))
    out = np.zeros((size, size, 3), np.float32)
    xs0, ys0 = max(x0, 0), max(y0, 0)
    xs1, ys1 = min(x0 + size, w), min(y0 + size, h)
    if xs1 > xs0 and ys1 > ys0:
        out[ys0 - y0:ys1 - y0, xs0 - x0:xs1 - x0] = img[ys0:ys1, xs0:xs1]
    return out


def resize(img, size):
    return np.asarray(Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).resize((size, size), Image.BILINEAR)).astype(np.float32) / 255.0


def metrics(d):
    lum = d.mean(2)
    pos = np.clip(lum, 0, None)
    return {"energy": float(pos.mean() * 1000), "p99": float(np.percentile(lum, 99)),
            "bright": float((lum > 0.12).mean()), "dark": float((lum < -0.12).mean()),
            "peak_rgb": [round(float(np.percentile(d[..., i], 99)), 3) for i in range(3)]}


def diff_img(d):
    # added light on black; darkening shown in blue
    out = np.clip(d, 0, 1)
    dark = np.clip(-d.mean(2), 0, 1)
    out[..., 2] = np.maximum(out[..., 2], dark * 0.8)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--video", required=True)
    ap.add_argument("--cast", type=float, required=True, help="cast moment in the video (s)")
    ap.add_argument("--center", required=True)
    ap.add_argument("--ours", required=True)
    ap.add_argument("--times", required=True)
    ap.add_argument("--reftimes", default="", help="video times (s after --cast) if they differ from --times")
    ap.add_argument("--scale", type=float, default=1.5)
    ap.add_argument("--crop", type=int, default=260)
    ap.add_argument("--lift", type=float, default=0.15)
    ap.add_argument("--tile", type=int, default=300)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    cx, cy = [float(v) for v in a.center.split(",")]
    times = [float(t) for t in a.times.split(",")]
    rtimes = [float(t) for t in a.reftimes.split(",")] if a.reftimes else times
    rsize = int(round(a.crop * a.scale))
    rbase = crop(video_frame(a.video, max(a.cast - 0.15, 0.0)), cx, cy, rsize, a.lift)
    obase_full = np.asarray(Image.open(os.path.join(a.ours, "base.png")).convert("RGB")).astype(np.float32) / 255.0
    oh, ow = obase_full.shape[:2]
    ocx, ocy = ow / 2, oh / 2
    obase = crop(obase_full, ocx, ocy, a.crop, a.lift)
    T = a.tile
    cols = []
    lines = []
    for t, rt in zip(times, rtimes):
        rf = crop(video_frame(a.video, a.cast + rt), cx, cy, rsize, a.lift)
        of_path = os.path.join(a.ours, "t_%05d.png" % int(round(t * 1000)))
        of = crop(np.asarray(Image.open(of_path).convert("RGB")).astype(np.float32) / 255.0, ocx, ocy, a.crop, a.lift)
        rd, od = rf - rbase, of - obase
        mr, mo = metrics(resize(rd * 0.5 + 0.5, T) * 2 - 1), metrics(resize(od * 0.5 + 0.5, T) * 2 - 1)
        lines.append("t=%.2f  REF energy %6.1f p99 %.2f bright %.3f dark %.3f rgb99 %s | OURS energy %6.1f p99 %.2f bright %.3f dark %.3f rgb99 %s"
                     % (t, mr["energy"], mr["p99"], mr["bright"], mr["dark"], mr["peak_rgb"],
                        mo["energy"], mo["p99"], mo["bright"], mo["dark"], mo["peak_rgb"]))
        col = np.concatenate([resize(rf, T), resize(of, T), resize(diff_img(rd), T), resize(diff_img(od), T)], 0)
        cols.append(np.pad(col, ((0, 0), (0, 4), (0, 0))))
    sheet = np.concatenate(cols, 1)
    im = Image.fromarray((np.clip(sheet, 0, 1) * 255).astype(np.uint8))
    dr = ImageDraw.Draw(im)
    for i, t in enumerate(times):
        dr.text((i * (T + 4) + 4, 4), "t=%.2f ref" % t, fill=(255, 255, 0))
        dr.text((i * (T + 4) + 4, T + 4), "ours", fill=(0, 255, 255))
        dr.text((i * (T + 4) + 4, 2 * T + 4), "ref added", fill=(255, 255, 0))
        dr.text((i * (T + 4) + 4, 3 * T + 4), "ours added", fill=(0, 255, 255))
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    im.save(a.out)
    print("\n".join(lines))
    print("wrote", a.out)


if __name__ == "__main__":
    main()
