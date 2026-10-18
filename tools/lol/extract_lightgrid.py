"""Map12 light grid -> assets/map/lightgrid.png (League character ambient cube).

lightgrid.dat (Map12.wad): header u32 version=3, u32 headerSize=32, u32 w, u32 h, f32 extentX, f32 extentZ,
f32, f32 (lightGridCharacterFullBrightIntensity); then w*h cells x 6 faces (+X,-X,+Y,-Y,+Z,-Z) x BGRA8.
Rows run along League +z, columns along +x (cell (0,0) at League origin). See docs/LEAGUE_SHADERS.md section 3.
Output: an RGB atlas of the 6 faces side by side (width 6*w, height h), raw (gamma) values.
Usage: python tools/lol/extract_lightgrid.py
"""
import os
import struct
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wad import Wad, path_hash  # noqa: E402

GAME = "D:/Riot Games/League of Legends/Game/DATA/FINAL"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def main():
    w = Wad(GAME + "/Maps/Shipping/Map12.wad.client")
    d = w.read_entry(w.entries[path_hash("assets/maps/lightmaps/maps/mapgeometry/map12/base/lightgrid.dat")])
    ver, hs, gw, gh, ex, ez, _f0, full = struct.unpack_from("<IIIIffff", d, 0)
    a = np.frombuffer(d, np.uint8, offset=hs, count=gw * gh * 24).reshape(gh, gw, 6, 4)
    atlas = np.concatenate([a[:, :, f, :][:, :, [2, 1, 0]] for f in range(6)], axis=1)
    out = os.path.join(ROOT, "assets", "map", "lightgrid.png")
    Image.fromarray(np.ascontiguousarray(atlas)).save(out)
    print("lightgrid v%d %dx%d extent %.2f x %.2f fullbright %.2f -> %s" % (ver, gw, gh, ex, ez, full, out))


if __name__ == "__main__":
    main()
