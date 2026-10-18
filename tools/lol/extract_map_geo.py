"""Export Howling Abyss (Map12) terrain + navigation grid for Godot.

Outputs:
  assets/map/howling_abyss.glb             terrain mesh (2 UV sets: material, lightmap)
  assets/map/textures/*.png                diffuse textures
  assets/map/lightmaps/*.png               baked lightmaps
  data/map/map_materials.json              per-surface material info
  data/map/navgrid.json + navgrid_*.bin    walkability / height / brush grid (Godot space)

Coordinates: League (x, y, z) -> Godot (x, y, -z) * 0.01 (see docs/research/league_formats.md).
"""
import io
import json
import os
import struct
import sys
from collections import deque

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "ref"))
from lolwad import Wad  # noqa: E402
from lolbin import read_bin, fnv1a32  # noqa: E402
from lolmapgeo import read_mapgeo, mesh_vertex_layout  # noqa: E402
from lolfmt_tex import any_texture_to_image  # noqa: E402
from gltf import Gltf, FLOAT, UINT, ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER  # noqa: E402

GAME = "D:/Riot Games/League of Legends/Game/DATA/FINAL"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
S = 0.01
NAVGRID_KEY = 0x6228ead3f44827ae


def out(*parts):
    p = os.path.join(ROOT, *parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    return p


# ---------------------------------------------------------------------------- navgrid
def export_navgrid(w: Wad):
    d = w.read_entry(w.entries[NAVGRID_KEY])
    major = d[0]
    minor = struct.unpack_from("<H", d, 1)[0]
    mn = struct.unpack_from("<3f", d, 3)
    mx = struct.unpack_from("<3f", d, 15)
    cs, cx, cz = struct.unpack_from("<fii", d, 27)
    assert major == 7, f"navgrid major {major}"
    n = cx * cz
    base = 39
    cells = np.frombuffer(d, dtype=np.uint8, count=48 * n, offset=base).reshape(n, 48)
    heights = cells[:, 0:4].copy().view(np.float32).reshape(cz, cx)
    flags = np.frombuffer(d, dtype=np.uint16, count=n, offset=base + 48 * n).reshape(cz, cx)
    walk = ((flags & 2) == 0).astype(np.uint8)
    brush_mask = ((flags & 1) != 0) & (walk == 1)
    # fill wall heights from nearest walkable cell (BFS) so terrain sampling is smooth
    h = heights.copy()
    known = walk.astype(bool)
    q = deque()
    for z in range(cz):
        for x in range(cx):
            if known[z, x]:
                q.append((z, x))
    while q:
        z, x = q.popleft()
        for dz, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nz, nx = z + dz, x + dx
            if 0 <= nz < cz and 0 <= nx < cx and not known[nz, nx]:
                known[nz, nx] = True
                h[nz, nx] = h[z, x]
                q.append((nz, nx))
    # brush connected components (8-neighborhood)
    brush = np.zeros((cz, cx), dtype=np.uint8)
    label = 0
    for z in range(cz):
        for x in range(cx):
            if brush_mask[z, x] and brush[z, x] == 0:
                label += 1
                q = deque([(z, x)])
                brush[z, x] = label
                while q:
                    a, b = q.popleft()
                    for dz in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            nz, nx = a + dz, b + dx
                            if 0 <= nz < cz and 0 <= nx < cx and brush_mask[nz, nx] and brush[nz, nx] == 0:
                                brush[nz, nx] = label
                                q.append((nz, nx))
    # Godot space: x' = x*S, z' = -z*S. Godot row j=0 is the most negative z' (= max League z).
    walk_g = walk[::-1, :].copy()
    h_g = (h[::-1, :] * S).astype(np.float32)
    brush_g = brush[::-1, :].copy()
    meta = {
        "origin_x": mn[0] * S,
        "origin_z": -(mn[2] + cz * cs) * S,
        "cell": cs * S,
        "width": cx,
        "height": cz,
        "brush_regions": label,
        "source": f"navgrid v{major}.{minor}",
    }
    json.dump(meta, open(out("data", "map", "navgrid.json"), "w"), indent=1)
    open(out("data", "map", "navgrid_walk.bin"), "wb").write(walk_g.tobytes())
    open(out("data", "map", "navgrid_height.bin"), "wb").write(h_g.tobytes())
    open(out("data", "map", "navgrid_brush.bin"), "wb").write(brush_g.tobytes())
    print(f"navgrid {cx}x{cz} walkable={int(walk.sum())} brush regions={label}")


# ---------------------------------------------------------------------------- mapgeo
DTYPES = {
    "X_Float32": ("<f4", 1), "XY_Float32": ("<f4", 2), "XYZ_Float32": ("<f4", 3), "XYZW_Float32": ("<f4", 4),
    "BGRA_Packed8888": ("u1", 4), "ZYXW_Packed8888": ("u1", 4), "RGBA_Packed8888": ("u1", 4),
    "XY_Packed1616": ("<f2", 2), "XYZ_Packed161616": ("<f2", 3), "XYZW_Packed16161616": ("<f2", 4),
}


def read_stream(data: bytes, vb, stride, layout, vcount):
    _vis, off, size = vb
    fields = []
    for (name, fmt, o) in layout:
        dt, n = DTYPES[fmt]
        fields.append((name, dt, (n,)))
    dtype = np.dtype({"names": [f[0] for f in fields], "formats": [(f[1], f[2]) for f in fields],
                      "offsets": [o for (_, _, o) in layout], "itemsize": stride})
    return np.frombuffer(data, dtype=dtype, count=vcount, offset=off)


def export_mapgeo(w: Wad, variant="base"):
    raw = w.get(f"data/maps/mapgeometry/map12/{variant}.mapgeo")
    g = read_mapgeo(raw)
    mats_bin = read_bin(w.get(f"data/maps/mapgeometry/map12/{variant}.materials.bin"))
    F = {n: fnv1a32(n) for n in ["samplerValues", "textureName", "texturePath", "paramValues", "name", "value",
                                 "techniques", "passes", "blendEnable", "switches", "on"]}
    tex_cache = {}

    def save_tex(key_or_path, folder):
        if key_or_path in tex_cache:
            return tex_cache[key_or_path]
        if isinstance(key_or_path, str):
            data = w.get(key_or_path)
            name = os.path.splitext(os.path.basename(key_or_path))[0]
            if "lightmaps" in key_or_path.lower():
                name = "lm_" + name
        else:
            e = w.entries.get(key_or_path)
            data = w.read_entry(e) if e else None
            name = f"{key_or_path:016x}"
        if data is None:
            tex_cache[key_or_path] = None
            return None
        img = any_texture_to_image(data)
        rel = f"assets/map/{folder}/{name}.png"
        img.save(out(*rel.split("/")))
        tex_cache[key_or_path] = rel
        return rel

    def material_info(mat_name):
        o = mats_bin.objects.get(fnv1a32(mat_name))
        info = {"name": mat_name, "diffuse": None, "blend": False, "alpha_test": 0.0, "tint": [1, 1, 1, 1],
                "grass": "Wall_of_Grass" in mat_name, "no_lightmap": False}
        if o is None:
            return info
        for s in o.get("samplerValues") or []:
            tn = s.get("textureName") or ""
            tp = s.get("texturePath")
            if "Diffuse" in tn and tp:
                info["diffuse"] = save_tex(tp if isinstance(tp, int) else tp.lower(), "textures")
        if info["diffuse"] is None:
            for s in o.get("samplerValues") or []:
                tp = s.get("texturePath")
                if tp:
                    info["diffuse"] = save_tex(tp if isinstance(tp, int) else tp.lower(), "textures")
                    break
        for p in o.get("paramValues") or []:
            n = p.get("name")
            v = p.get("value") or (0, 0, 0, 0)
            if n == "AlphaTestValue":
                info["alpha_test"] = v[0]
            elif n == "TintColor":
                info["tint"] = list(v)
        for t in o.get("techniques") or []:
            for ps in t.get("passes") or []:
                if ps.get("blendEnable"):
                    info["blend"] = True
        extra = o.get(0xe6d67ded) or {}
        if isinstance(extra, dict) and "NO_BAKED_LIGHTING" in extra:
            info["no_lightmap"] = True
        return info

    # group triangles by (material, lightmap)
    groups = {}
    skipped = 0
    for m in g.meshes:
        (bx0, by0, bz0), (bx1, by1, bz1) = m.bbox
        layout = mesh_vertex_layout(g, m)
        streams = [read_stream(raw, g.vertex_buffers[vb], stride, lay, m.vertex_count) for (vb, stride, lay) in layout]
        cols = {}
        for st in streams:
            for name in st.dtype.names:
                cols[name] = st[name]
        if "Position" not in cols:
            skipped += 1
            continue
        pos = cols["Position"].astype(np.float32)
        nrm = cols["Normal"].astype(np.float32) if "Normal" in cols else np.tile([0, 1, 0], (m.vertex_count, 1)).astype(np.float32)
        uv0 = cols["Texcoord0"].astype(np.float32) if "Texcoord0" in cols else np.zeros((m.vertex_count, 2), np.float32)
        uv7 = cols["Texcoord7"].astype(np.float32) if "Texcoord7" in cols else None
        _ivis, ioff, isize = g.index_buffers[m.index_buffer_id]
        idx = np.frombuffer(raw, dtype="<u2", count=isize // 2, offset=ioff).astype(np.uint32)
        lm_tex, lm_scale, lm_bias = m.baked_light
        if uv7 is not None and lm_tex:
            uv1 = uv7 * np.array(lm_scale, np.float32) + np.array(lm_bias, np.float32)
        else:
            uv1 = np.zeros((m.vertex_count, 2), np.float32)
            lm_tex = ""
        # convert to Godot space
        P = pos * S
        P[:, 2] *= -1.0
        N = nrm.copy()
        N[:, 2] *= -1.0
        for sm in m.submeshes:
            tri = idx[sm.start_index: sm.start_index + sm.index_count].reshape(-1, 3)
            tri = tri[:, [0, 2, 1]]
            key = (sm.material, lm_tex)
            gr = groups.setdefault(key, {"P": [], "N": [], "U0": [], "U1": [], "I": [], "n": 0})
            used = np.unique(tri)
            remap = -np.ones(m.vertex_count, np.int64)
            remap[used] = np.arange(len(used)) + gr["n"]
            gr["P"].append(P[used])
            gr["N"].append(N[used])
            gr["U0"].append(uv0[used])
            gr["U1"].append(uv1[used])
            gr["I"].append(remap[tri].astype(np.uint32))
            gr["n"] += len(used)
    gl = Gltf()
    prims = []
    mat_infos = {}
    materials_json = []
    for (mat_name, lm_tex), gr in sorted(groups.items()):
        if mat_name not in mat_infos:
            mat_infos[mat_name] = material_info(mat_name)
        info = dict(mat_infos[mat_name])
        info["lightmap"] = save_tex(lm_tex.lower(), "lightmaps") if lm_tex else None
        P = np.concatenate(gr["P"])
        N = np.concatenate(gr["N"])
        nl = np.linalg.norm(N, axis=1, keepdims=True)
        N = N / np.maximum(nl, 1e-6)
        U0 = np.concatenate(gr["U0"])
        U1 = np.concatenate(gr["U1"])
        I = np.concatenate(gr["I"]).reshape(-1)
        mat_index = len(materials_json)
        mname = f"mapmat_{mat_index:03d}"
        info["gltf_name"] = mname
        materials_json.append(info)
        gl.add("materials", {"name": mname, "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 1.0},
                             "doubleSided": True})
        prims.append({
            "attributes": {
                "POSITION": gl.accessor(P, FLOAT, "VEC3", ARRAY_BUFFER, minmax=True),
                "NORMAL": gl.accessor(N, FLOAT, "VEC3", ARRAY_BUFFER),
                "TEXCOORD_0": gl.accessor(U0, FLOAT, "VEC2", ARRAY_BUFFER),
                "TEXCOORD_1": gl.accessor(U1, FLOAT, "VEC2", ARRAY_BUFFER),
            },
            "indices": gl.accessor(I, UINT, "SCALAR", ELEMENT_ARRAY_BUFFER),
            "material": mat_index,
        })
    gl.add("meshes", {"name": "HowlingAbyss", "primitives": prims})
    node = gl.add("nodes", {"name": "HowlingAbyss", "mesh": 0})
    gl.j["scenes"][0]["nodes"].append(node)
    size = gl.write_glb(out("assets", "map", "howling_abyss.glb"))
    json.dump(materials_json, open(out("data", "map", "map_materials.json"), "w"), indent=1)
    tris = sum(len(np.concatenate(gr["I"])) // 3 for gr in groups.values())
    print(f"mapgeo v{g.version}: meshes={len(g.meshes)} groups={len(groups)} tris={tris} skipped={skipped} glb={size/1e6:.1f}MB")


if __name__ == "__main__":
    w = Wad(f"{GAME}/Maps/Shipping/Map12.wad.client")
    export_navgrid(w)
    export_mapgeo(w, sys.argv[1] if len(sys.argv) > 1 else "base")
