"""SKN (SimpleSkin) and SKL (RigResource / legacy r3d2sklt) parsers. Pure Python (struct only)."""
from __future__ import annotations

import math
import struct
from dataclasses import dataclass, field


def elf_hash(name: str) -> int:
    """Joint-name hash used by SKL joint index table and ANM tracks (ELF hash of lower-cased name)."""
    h = 0
    for c in name.lower().encode("ascii"):
        h = ((h << 4) + c) & 0xFFFFFFFF
        high = h & 0xF0000000
        if high:
            h ^= high >> 24
        h &= ~high & 0xFFFFFFFF
    return h


# ----------------------------------------------------------------------------- SKN
@dataclass
class SknRange:
    material: str
    start_vertex: int
    vertex_count: int
    start_index: int
    index_count: int


@dataclass
class Skn:
    major: int
    minor: int
    flags: int
    ranges: list
    vertex_type: int          # 0 basic(52B) 1 color(56B) 2 tangent(72B)
    vertex_size: int
    bbox: tuple | None
    bsphere: tuple | None
    indices: list             # flat u16 list
    positions: list
    joints: list              # 4 x u8, indices INTO SKL influences table
    weights: list             # 4 x f32
    normals: list
    uvs: list
    colors: list | None       # 4 x u8 (B,G,R,A in memory)
    tangents: list | None     # 4 x f32


def read_skn(d: bytes) -> Skn:
    magic, major, minor = struct.unpack_from("<IHH", d, 0)
    if magic != 0x00112233:
        raise ValueError("bad SKN magic")
    p = 8
    flags = 0
    vtype, vsize = 0, 52
    bbox = bsphere = None
    if major == 0:
        icount, vcount = struct.unpack_from("<II", d, p); p += 8
        ranges = [SknRange("Base", 0, vcount, 0, icount)]
    else:
        (nr,) = struct.unpack_from("<I", d, p); p += 4
        ranges = []
        for _ in range(nr):
            name = d[p:p + 64].split(b"\0", 1)[0].decode("ascii", "replace")
            sv, vc, si, ic = struct.unpack_from("<4I", d, p + 64)
            ranges.append(SknRange(name, sv, vc, si, ic))
            p += 80
        if major == 4:
            (flags,) = struct.unpack_from("<I", d, p); p += 4
        icount, vcount = struct.unpack_from("<II", d, p); p += 8
        if major == 4:
            vsize, vtype = struct.unpack_from("<II", d, p); p += 8
            bbox = (struct.unpack_from("<3f", d, p), struct.unpack_from("<3f", d, p + 12)); p += 24
            bsphere = (struct.unpack_from("<3f", d, p), struct.unpack_from("<f", d, p + 12)[0]); p += 16
    indices = list(struct.unpack_from(f"<{icount}H", d, p)); p += 2 * icount
    pos, jnt, wgt, nrm, uv, col, tan = [], [], [], [], [], [], []
    for i in range(vcount):
        b = p + i * vsize
        pos.append(struct.unpack_from("<3f", d, b))
        jnt.append(struct.unpack_from("<4B", d, b + 12))
        wgt.append(struct.unpack_from("<4f", d, b + 16))
        nrm.append(struct.unpack_from("<3f", d, b + 32))
        uv.append(struct.unpack_from("<2f", d, b + 44))
        if vtype >= 1:
            col.append(struct.unpack_from("<4B", d, b + 52))
        if vtype == 2:
            tan.append(struct.unpack_from("<4f", d, b + 56))
    return Skn(major, minor, flags, ranges, vtype, vsize, bbox, bsphere, indices,
               pos, jnt, wgt, nrm, uv, col or None, tan or None)


# ----------------------------------------------------------------------------- SKL
@dataclass
class Joint:
    name: str
    flags: int
    id: int
    parent: int
    radius: float
    name_hash: int
    local_t: tuple
    local_s: tuple
    local_r: tuple            # quaternion x,y,z,w
    ibind_t: tuple
    ibind_s: tuple
    ibind_r: tuple


@dataclass
class Skl:
    modern: bool
    flags: int
    name: str
    asset_name: str
    joints: list
    influences: list          # influence slot -> joint id (SKN vertex joint byte indexes this)
    hash_to_id: dict = field(default_factory=dict)


def _cstr(d, p):
    e = d.index(b"\0", p)
    return d[p:e].decode("ascii", "replace")


def read_skl(d: bytes) -> Skl:
    if struct.unpack_from("<I", d, 4)[0] == 0x22FD4FC3:
        file_size, token, version, flags, jcount, icount = struct.unpack_from("<IIIHHI", d, 0)
        (j_off, jidx_off, inf_off, name_off, asset_off, names_off) = struct.unpack_from("<6i", d, 20)
        joints = []
        for i in range(jcount):
            b = j_off + i * 100
            fl, jid, par, _pad, nh, rad = struct.unpack_from("<HhhhIf", d, b)
            lt = struct.unpack_from("<3f", d, b + 16); ls = struct.unpack_from("<3f", d, b + 28)
            lr = struct.unpack_from("<4f", d, b + 40)
            it = struct.unpack_from("<3f", d, b + 56); is_ = struct.unpack_from("<3f", d, b + 68)
            ir = struct.unpack_from("<4f", d, b + 80)
            (noff,) = struct.unpack_from("<i", d, b + 96)
            name = _cstr(d, b + 96 + noff)      # relative to the position of the offset field itself
            joints.append(Joint(name, fl, jid, par, rad, nh, lt, ls, lr, it, is_, ir))
        infl = list(struct.unpack_from(f"<{icount}h", d, inf_off)) if inf_off > 0 else []
        h2i = {}
        if jidx_off > 0:
            for i in range(jcount):
                jid, _pad, h = struct.unpack_from("<hHI", d, jidx_off + 8 * i)
                h2i[h] = jid
        name = _cstr(d, name_off) if name_off > 0 else ""
        asset = _cstr(d, asset_off) if asset_off > 0 else ""
        return Skl(True, flags, name, asset, joints, infl, h2i)
    # legacy r3d2sklt v1/v2: global 3x4 matrices
    if d[:8] != b"r3d2sklt":
        raise ValueError("bad SKL")
    version, skel_id, jcount = struct.unpack_from("<III", d, 8)
    p = 20
    raw = []
    for i in range(jcount):
        name = d[p:p + 32].split(b"\0", 1)[0].decode("ascii", "replace")
        par, rad = struct.unpack_from("<if", d, p + 32)
        m = struct.unpack_from("<12f", d, p + 40)   # stored 3 rows x 4 cols (row-major, translation in col 3)
        raw.append((name, par, rad, m)); p += 88
    if version == 2:
        (n,) = struct.unpack_from("<I", d, p); p += 4
        infl = list(struct.unpack_from(f"<{n}I", d, p))
    else:
        infl = list(range(jcount))
    joints = [Joint(n, 0, i, par, rad, elf_hash(n), None, None, None, None, None, None)
              for i, (n, par, rad, m) in enumerate(raw)]
    # (Converting global matrices -> local TRS is left to the caller; see spec.)
    s = Skl(False, 0, "", "", joints, infl, {j.name_hash: j.id for j in joints})
    s.legacy_global_matrices = [m for (_, _, _, m) in raw]
    return s


# ----------------------------------------------------------------------------- helpers
def quat_to_mat3(q):
    x, y, z, w = q
    return ((1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)),
            (2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)),
            (2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)))


def trs_to_mat4(t, r, s):
    """Column-vector convention: M = T * R * S (what glTF uses)."""
    m = quat_to_mat3(r)
    return [[m[0][0] * s[0], m[0][1] * s[1], m[0][2] * s[2], t[0]],
            [m[1][0] * s[0], m[1][1] * s[1], m[1][2] * s[2], t[1]],
            [m[2][0] * s[0], m[2][1] * s[1], m[2][2] * s[2], t[2]],
            [0.0, 0.0, 0.0, 1.0]]


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
