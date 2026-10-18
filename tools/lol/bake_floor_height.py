"""Bake the ground height field units stand on (data/map/floor_height.bin + "floor" block in navgrid.json).

League keeps units on the navgrid's *sampled height* field (AIPath .ngrid v7: after the cells, flags, region
flags and 8x132 unknown bytes comes `u32 countX, countZ; f32 spacingX, spacingZ; f32 heights[countX*countZ]`,
a node grid spanning navgrid min..max at ~25 units, i.e. half a cell). Two problems with using raw data:

  * the per-cell `centerHeight` (what the old exporter used) is 0 on 278 walkable cells -> 1.8 m spikes;
  * the sampled field sits ~8-14 League units *above* the snow floor mesh we render, so feet float.

So this tool rasterizes the rendered terrain (assets/map/howling_abyss.glb, brush/grass excluded) onto the
sampled-height node grid and, on walkable nodes, takes the mesh surface closest to League's sampled height
(within +-0.6 m) -> feet sit exactly on the visible floor while League's field arbitrates between stacked
surfaces (bridges, decals, props). Nodes without a surface keep League's value; outliers vs a 5x5 median are
replaced; non-walkable nodes take the nearest walkable value so dashes over walls stay level.

Usage: python tools/lol/bake_floor_height.py  (after extract_map_geo.py)
"""
import json
import os
import struct
import sys
from collections import deque

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "ref"))
sys.path.insert(0, os.path.dirname(__file__))
from lolwad import Wad  # noqa: E402

GAME = "D:/Riot Games/League of Legends/Game/DATA/FINAL"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
NAVGRID_KEY = 0x6228ead3f44827ae
S = 0.01
SNAP = 0.6        # m: max distance between League's sampled height and the chosen mesh surface
OFF_BLUR = 2      # passes of the 5-tap binomial blur on the mesh-nav offset
OFF_MIN = -0.25   # m: mesh may pull feet at most this far below League's field
OFF_MAX = 0.10    # m: ... or this far above
OUTLIER = 0.12    # m: deviation from the 5x5 median that counts as a spike


def read_navgrid(w):
    d = w.read_entry(w.entries[NAVGRID_KEY])
    assert d[0] == 7
    mn = struct.unpack_from("<3f", d, 3)
    mx = struct.unpack_from("<3f", d, 15)
    cs, cx, cz = struct.unpack_from("<fii", d, 27)
    n = cx * cz
    flags = np.frombuffer(d, dtype=np.uint16, count=n, offset=39 + 48 * n).reshape(cz, cx)
    off = 39 + 48 * n + 2 * n + 4 * n + 8 * 132
    sx, sz = struct.unpack_from("<II", d, off)
    dx, dz = struct.unpack_from("<ff", d, off + 8)
    hs = np.frombuffer(d, dtype=np.float32, count=sx * sz, offset=off + 16).reshape(sz, sx).astype(np.float64)
    return mn, mx, cs, cx, cz, flags, hs, dx, dz


def load_glb(path):
    b = open(path, "rb").read()
    jl = struct.unpack_from("<I", b, 12)[0]
    J = json.loads(b[20:20 + jl])
    bo = 20 + jl
    BIN = b[bo + 8:bo + 8 + struct.unpack_from("<I", b, bo)[0]]

    def acc(i):
        a = J["accessors"][i]
        bv = J["bufferViews"][a["bufferView"]]
        comp = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[a["componentType"]]
        k = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[a["type"]]
        arr = np.frombuffer(BIN, dtype=comp, count=a["count"] * k, offset=bv.get("byteOffset", 0) + a.get("byteOffset", 0))
        return arr.reshape(a["count"], k) if k > 1 else arr

    for node in J["nodes"]:
        if "mesh" not in node:
            continue
        for prim in J["meshes"][node["mesh"]]["primitives"]:
            mat = J["materials"][prim["material"]]["name"] if "material" in prim else ""
            yield mat, acc(prim["attributes"]["POSITION"]).astype(np.float64), acc(prim["indices"]).astype(np.int64).reshape(-1, 3)


def median5(a):
    p = np.pad(a, 2, mode="edge")
    st = np.stack([p[j:j + a.shape[0], i:i + a.shape[1]] for j in range(5) for i in range(5)])
    return np.median(st, axis=0)


def main():
    w = Wad(f"{GAME}/Maps/Shipping/Map12.wad.client")
    mn, mx, cs, cx, cz, flags, hs, dx, dz = read_navgrid(w)
    sz, sx = hs.shape
    walk = (flags & 2) == 0
    kz, kx = np.mgrid[0:sz, 0:sx]
    # a node is walkable if any of the (up to 4) cells touching it is walkable
    sw = np.zeros((sz, sx), bool)
    for ox in (-0.25, 0.25):
        for oz in (-0.25, 0.25):
            ci = np.clip(np.floor(kx * dx / cs + ox).astype(int), 0, cx - 1)
            cj = np.clip(np.floor(kz * dz / cs + oz).astype(int), 0, cz - 1)
            sw |= walk[cj, ci]
    nav = hs * S
    mats = {m["gltf_name"]: m for m in json.load(open(os.path.join(ROOT, "data", "map", "map_materials.json")))}
    best = np.full(hs.shape, np.inf)   # signed (mesh - nav) of the surface closest to nav
    for mat, P, I in load_glb(os.path.join(ROOT, "assets", "map", "howling_abyss.glb")):
        if mats.get(mat, {}).get("grass"):
            continue
        X = P[:, 0] / S
        Z = -P[:, 2] / S
        Y = P[:, 1]
        for a, b, c in I:
            xs = (X[a], X[b], X[c])
            zs = (Z[a], Z[b], Z[c])
            i0 = max(int(np.ceil((min(xs) - mn[0]) / dx)), 0)
            i1 = min(int(np.floor((max(xs) - mn[0]) / dx)), sx - 1)
            j0 = max(int(np.ceil((min(zs) - mn[2]) / dz)), 0)
            j1 = min(int(np.floor((max(zs) - mn[2]) / dz)), sz - 1)
            if i1 < i0 or j1 < j0:
                continue
            x0, x1, x2 = xs
            z0, z1, z2 = zs
            den = (z1 - z2) * (x0 - x2) + (x2 - x1) * (z0 - z2)
            if abs(den) < 1e-9:
                continue
            GX, GZ = np.meshgrid(mn[0] + np.arange(i0, i1 + 1) * dx, mn[2] + np.arange(j0, j1 + 1) * dz)
            l0 = ((z1 - z2) * (GX - x2) + (x2 - x1) * (GZ - z2)) / den
            l1 = ((z2 - z0) * (GX - x2) + (x0 - x2) * (GZ - z2)) / den
            l2 = 1 - l0 - l1
            ins = (l0 >= -1e-6) & (l1 >= -1e-6) & (l2 >= -1e-6)
            if not ins.any():
                continue
            sub = (slice(j0, j1 + 1), slice(i0, i1 + 1))
            d = np.where(ins, l0 * Y[a] + l1 * Y[b] + l2 * Y[c] - nav[sub], np.inf)
            bs = best[sub]
            upd = np.abs(d) < np.abs(bs)
            bs[upd] = d[upd]
    have = sw & (np.abs(best) <= SNAP)
    floor = np.where(have, nav + np.where(np.isfinite(best), best, 0.0), nav)
    # walkable nodes without a mesh surface: League's field shifted by the local mean offset
    off_med = float(np.median(best[have]))
    floor = np.where(sw & ~have, nav + off_med, floor)
    # spike removal on walkable nodes (props/decals poking through)
    tmp = np.where(sw, floor, np.nan)
    med = np.nan_to_num(median5(np.where(np.isnan(tmp), floor, tmp)))
    spikes = sw & (np.abs(floor - med) > OUTLIER)
    floor = np.where(spikes, med, floor)
    # League's own sampled field is perfectly smooth (no step > 0.2 m on any walkable node pair) while the raw
    # mesh snap jumps 0.2-0.5 m between neighbouring nodes where a decal/prop layer wins. Keep League's field as
    # the base and apply only the *smoothed, bounded* mesh offset, so feet follow the visible floor but cannot
    # pop or lift on stacked geometry.
    off = np.where(sw, floor - nav, 0.0)
    wgt = sw.astype(np.float64)
    k5 = np.array([1, 4, 6, 4, 1], np.float64) / 16.0
    for _ in range(OFF_BLUR):
        for ax in (0, 1):
            off = np.apply_along_axis(lambda v: np.convolve(v, k5, mode="same"), ax, off)
            wgt = np.apply_along_axis(lambda v: np.convolve(v, k5, mode="same"), ax, wgt)
    off = np.where(wgt > 1e-3, off / np.maximum(wgt, 1e-3), 0.0)
    off = np.clip(off, OFF_MIN, OFF_MAX)
    floor = np.where(sw, nav + off, floor)
    # non-walkable: nearest walkable value (BFS) so wall crossings stay level
    known = sw.copy()
    q = deque(map(tuple, np.argwhere(known)))
    while q:
        j, i = q.popleft()
        for dj, di in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nj, ni = j + dj, i + di
            if 0 <= nj < sz and 0 <= ni < sx and not known[nj, ni]:
                known[nj, ni] = True
                floor[nj, ni] = floor[j, i]
                q.append((nj, ni))
    # Godot space: row 0 = most negative z' = League max z
    fg = floor[::-1, :].astype(np.float32)
    open(os.path.join(ROOT, "data", "map", "floor_height.bin"), "wb").write(fg.tobytes())
    meta_path = os.path.join(ROOT, "data", "map", "navgrid.json")
    meta = json.load(open(meta_path))
    meta["floor"] = {"origin_x": mn[0] * S, "origin_z": -(mn[2] + (sz - 1) * dz) * S, "dx": dx * S, "dz": dz * S,
                     "width": sx, "height": sz,
                     "source": "mesh floor snapped to ngrid sampled heights (tools/lol/bake_floor_height.py)"}
    json.dump(meta, open(meta_path, "w"), indent=1)
    print(f"floor {sx}x{sz}: walkable nodes={int(sw.sum())} mesh-snapped={int(have.sum())} "
          f"fallback={int((sw & ~have).sum())} spikes fixed={int(spikes.sum())} median mesh-nav={off_med*100:.1f}u")


if __name__ == "__main__":
    main()
