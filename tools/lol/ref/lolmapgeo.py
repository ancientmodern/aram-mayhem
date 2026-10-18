"""Map geometry (.mapgeo, magic 'OEGM') reader, versions 5..18 (layout ported from LeagueToolkit EnvironmentAsset).
Stops after the mesh table (bucketed scene graph / planar reflectors are not needed for rendering)."""
from __future__ import annotations

import struct
from dataclasses import dataclass, field

ELEM_NAMES = ["Position", "BlendWeight", "Normal", "FogCoordinate", "PrimaryColor", "SecondaryColor",
              "BlendIndex", "Texcoord0", "Texcoord1", "Texcoord2", "Texcoord3", "Texcoord4", "Texcoord5",
              "Texcoord6", "Texcoord7", "Tangent"]
FMT = {0: ("X_Float32", 4), 1: ("XY_Float32", 8), 2: ("XYZ_Float32", 12), 3: ("XYZW_Float32", 16),
       4: ("BGRA_Packed8888", 4), 5: ("ZYXW_Packed8888", 4), 6: ("RGBA_Packed8888", 4),
       7: ("XY_Packed1616", 4), 8: ("XYZ_Packed161616", 8), 9: ("XYZW_Packed16161616", 8),
       10: ("XY_Packed88", 2), 11: ("XYZ_Packed888", 3), 12: ("XYZW_Packed8888", 4)}


class R:
    def __init__(self, d):
        self.d, self.p = d, 0

    def u(self, fmt):
        v = struct.unpack_from(fmt, self.d, self.p); self.p += struct.calcsize(fmt)
        return v if len(v) > 1 else v[0]

    def sstr(self):
        n = self.u("<i"); s = self.d[self.p:self.p + n].decode("utf-8", "replace"); self.p += n
        return s


@dataclass
class Submesh:
    hash: int
    material: str
    start_index: int
    index_count: int
    min_vertex: int
    max_vertex: int


@dataclass
class Mesh:
    name: str
    vertex_count: int
    vertex_decl_id: int
    vertex_buffer_ids: list
    index_count: int
    index_buffer_id: int
    visibility: int
    submeshes: list
    disable_backface_culling: bool
    bbox: tuple
    transform: tuple            # 16 floats, row-major (row-vector convention, translation in last row)
    quality: int
    render_flags: int
    baked_light: tuple          # (texture, scale, bias)
    stationary_light: tuple
    texture_overrides: list = field(default_factory=list)


@dataclass
class MapGeo:
    version: int
    sampler_defs: list
    vertex_decls: list          # [(usage, [(elem_name, fmt), ...])]
    vertex_buffers: list        # [(visibility, offset, size)]
    index_buffers: list         # [(visibility, offset, size)]
    meshes: list


def read_mapgeo(d: bytes) -> MapGeo:
    r = R(d)
    assert r.d[:4] == b"OEGM"; r.p = 4
    v = r.u("<i")
    sep_point_lights = r.u("<?") if v < 7 else False
    samplers = []
    if v >= 17:
        for _ in range(r.u("<i")):
            samplers.append((r.u("<i"), r.sstr()))
    else:
        if v >= 9:
            samplers.append((0, r.sstr()))
        if v >= 11:
            samplers.append((1, r.sstr()))
    decls = []
    for _ in range(r.u("<I")):
        usage, n = r.u("<II")
        elems = [r.u("<II") for _ in range(n)]
        r.p += 8 * (15 - n)                       # always 15 element slots on disk
        decls.append((usage, elems))
    vbs = []
    for _ in range(r.u("<I")):
        vis = r.u("<B") if v >= 13 else 0xFF
        size = r.u("<I"); vbs.append((vis, r.p, size)); r.p += size
    ibs = []
    for _ in range(r.u("<I")):
        vis = r.u("<B") if v >= 13 else 0xFF
        size = r.u("<i"); ibs.append((vis, r.p, size)); r.p += size
    meshes = []
    for mi in range(r.u("<I")):
        name = r.sstr() if v <= 11 else f"MapGeo_Instance_{mi}"
        vcount, ndecl, decl_id = r.u("<iIi")
        vb_ids = [r.u("<i") for _ in range(ndecl)]
        icount, ib_id = r.u("<Ii")
        vis = 0xFF
        if v >= 13:
            vis = r.u("<B")
        if v >= 18:
            _region_hash = r.u("<I")
        if v >= 15:
            _vis_controller = r.u("<I")
        subs = []
        for _ in range(r.u("<I")):
            h = r.u("<I"); mat = r.sstr(); si, ic, mnv, mxv = r.u("<4i")
            subs.append(Submesh(h, mat, si, ic, mnv, mxv))
        dbc = r.u("<?") if v != 5 else False
        bbox = (r.u("<3f"), r.u("<3f"))
        xf = r.u("<16f")
        quality = r.u("<B")
        if 7 <= v <= 12:
            vis = r.u("<B")
        rflags = 0
        if 11 <= v < 14:
            rflags = r.u("<B")
        elif v >= 14:
            _layer_transition = r.u("<B")
            rflags = r.u("<B") if v < 16 else r.u("<H")
        if sep_point_lights and v < 7:
            r.u("<3f")
        if v < 9:
            r.p += 9 * 12                          # spherical harmonics
            baked = (r.sstr(), r.u("<2f"), r.u("<2f")); stat = None; tov = []
        else:
            baked = (r.sstr(), r.u("<2f"), r.u("<2f"))
            stat = (r.sstr(), r.u("<2f"), r.u("<2f"))
            tov = []
            if 12 <= v < 17:
                tov.append((0, r.sstr())); r.u("<2f"); r.u("<2f")
            if v >= 17:
                for _ in range(r.u("<i")):
                    tov.append((r.u("<i"), r.sstr()))
                r.u("<2f"); r.u("<2f")             # baked paint scale, bias
        meshes.append(Mesh(name, vcount, decl_id, vb_ids, icount, ib_id, vis, subs, dbc, bbox, xf, quality,
                           rflags, baked, stat, tov))
    return MapGeo(v, samplers, decls, vbs, ibs, meshes)


def mesh_vertex_layout(g: MapGeo, m: Mesh):
    """List of (buffer_id, stride, [(elem_name, fmt_name, offset)]) for the mesh's vertex streams."""
    out = []
    for i, vb in enumerate(m.vertex_buffer_ids):
        usage, elems = g.vertex_decls[m.vertex_decl_id + i]
        off = 0; lay = []
        for (en, ef) in elems:
            fname, sz = FMT[ef]
            lay.append((ELEM_NAMES[en], fname, off)); off += sz
        out.append((vb, off, lay))
    return out
