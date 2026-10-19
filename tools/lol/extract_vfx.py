"""Extract League particle systems (VfxSystemDefinitionData) for the game's champions.

For each champion (base skin) this writes:
  data/vfx/<alias>.json             {system name: {"emitters": [...], "dur": seconds}}
  assets/vfx/<lowercase asset path>.png / .obj   textures and particle meshes

Emitter values are converted to the game's conventions: meters (League units * 0.01), Godot axes (x, y, -z),
colors 0..1, curves as {"t": [...], "v": [...]}. Random ranges come from League probability tables.

Usage: python tools/lol/extract_vfx.py [Alias ...]      (default: whole roster)
       python tools/lol/extract_vfx.py --shared | --map   (shared systems / Howling Abyss ambient particles)
"""
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(__file__))
from wad import Wad
from binfile import BinFile, to_py, fnv1a
from vfx_names import TABLE
from tex import decode_tex

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
GAME = "D:/Riot Games/League of Legends/Game/DATA/FINAL"
ROSTER = ["Ahri", "Garen", "Darius", "Yasuo", "MasterYi", "Malphite", "Leona", "Lux", "Jinx",
          "Ezreal", "MissFortune", "Annie", "Sona", "Veigar"]
U = 0.01

# semantic names for hashes we identified by context
for n, h in {"shape": 0x3bf0b4ed, "erosionDrive": 0xc6fbacd5, "VfxShapeLegacy2": 0xee39916f,
             "softParticle": 0x4ffce322, "postRotation": 0xfa45ef23, "boxSize": 0x23a0d95c,
             "VfxTextureMultDefinitionData": 0xb097c1bd, "VfxShapeLegacy": 0x4f4e2ed7, "VfxShapeSphere": 0x3dbe415d,
             "VfxShapeCylinder": 0x12ab94a6, "VfxShapeBox": 0xba945ee1, "birthUvScrollRateMult": 0x32356474,
             "uvScaleMult": 0xcd124686, "texDivMult": 0x164b5733, "height": 0xd5bdbb42}.items():
    TABLE[h] = n
for n in ["uvRotationMult", "mSubmeshesToDraw", "texAddressModeMult", "uvScrollClampMult", "linger",
          "particleUVScrollRate", "birthUVScrollRate", "uvScale", "particleUVRotateRate",
          # [vfx-runtime] names from the CommunityDragon hash lists (tools/extracted/cdhash) used by the gates /
          # render state below (see docs/VFX_COVERAGE.md)
          "disabled", "Filtering", "keywordsRequired", "keywordsIncluded", "keywordsExcluded", "spectatorPolicy",
          "miscRenderFlags", "isRotationEnabled", "AlignYawToCamera", "AlignPitchToCamera",
          "hasPostRotateOrientation", "postRotateOrientationAxis", "FlexShapeDefinition", "uvTransformCenter",
          "palleteSrcMixColor"]:
    TABLE[fnv1a(n)] = n

_wads = {}


def wad(path):
    if path not in _wads:
        _wads[path] = Wad(path)
    return _wads[path]


# ===================================================================== value helpers
def _ptable_range(dyn):
    """(min, max) multipliers from the first probability table, or None."""
    if not isinstance(dyn, dict):
        return None
    tabs = dyn.get("probabilityTables") or []
    out = []
    for t in tabs:
        kv = t.get("keyValues") if isinstance(t, dict) else None
        if kv and len(kv) >= 2:
            out.append((min(kv), max(kv)))
        else:
            out.append(None)
    return out or None


def val(v, default=None):
    """Value at t=0 (constant, or first key of the dynamics curve)."""
    if v is None:
        return default
    if not isinstance(v, dict):
        return v
    dyn = v.get("dynamics")
    if isinstance(dyn, dict) and dyn.get("values"):
        return dyn["values"][0]
    return v.get("constantValue", default)


def rand_mult(v):
    """Per-component random multiplier ranges [[min..], [max..]] or None."""
    if not isinstance(v, dict):
        return None
    r = _ptable_range(v.get("dynamics"))
    if not r or all(x is None for x in r):
        return None
    lo = [x[0] if x else 1.0 for x in r]
    hi = [x[1] if x else 1.0 for x in r]
    if all(abs(a - 1) < 1e-4 and abs(b - 1) < 1e-4 for a, b in zip(lo, hi)):
        return None
    return [lo, hi]


def curve(v):
    """Over-life curve {"t": [...], "v": [...]} or None (only when it has >1 keys)."""
    if not isinstance(v, dict):
        return None
    dyn = v.get("dynamics")
    if isinstance(dyn, dict) and dyn.get("times") and len(dyn["times"]) > 1:
        return {"t": dyn["times"], "v": dyn["values"]}
    return None


def _curve_at(times, values, t):
    if t <= times[0]:
        return values[0]
    for i in range(1, len(times)):
        if t <= times[i]:
            k = (t - times[i - 1]) / max(times[i] - times[i - 1], 1e-6)
            a, b = values[i - 1], values[i]
            if isinstance(a, list):
                return [x + (y - x) * k for x, y in zip(a, b)]
            return a + (b - a) * k
    return values[-1]


def sample_curve(v, n=16):
    """n samples over life of a ValueFloat-like (constant or curve)."""
    if not isinstance(v, dict):
        return None
    dyn = v.get("dynamics")
    if isinstance(dyn, dict) and dyn.get("times"):
        return [_curve_at(dyn["times"], dyn["values"], i / (n - 1)) for i in range(n)]
    c = v.get("constantValue")
    return [c] * n if c is not None else None


def integrate(v, life, n=16):
    """UV offset over life (n samples) of an IntegratedValueVector2 rate (uv units / second)."""
    if not isinstance(v, dict):
        return None
    dyn = v.get("dynamics")
    times = dyn.get("times") if isinstance(dyn, dict) else None
    vals = dyn.get("values") if isinstance(dyn, dict) else None
    c = v.get("constantValue")
    if not times:
        if not isinstance(c, list):
            return None
        return [[c[0] * life * i / (n - 1), c[1] * life * i / (n - 1)] for i in range(n)]
    out = [[0.0, 0.0]]
    acc = [0.0, 0.0]
    steps = 64
    prev = _curve_at(times, vals, 0.0)
    for k in range(1, steps + 1):
        t = k / steps
        cur = _curve_at(times, vals, t)
        acc = [acc[0] + (prev[0] + cur[0]) * 0.5 * life / steps, acc[1] + (prev[1] + cur[1]) * 0.5 * life / steps]
        prev = cur
        if k % (steps // (n - 1)) == 0 and len(out) < n:
            out.append(list(acc))
    while len(out) < n:
        out.append(list(acc))
    return out


def _plife_max(e):
    v = val(e.get("particleLifetime"), 1.0)
    q = quantiles(e.get("particleLifetime"))
    m = max(r[0] for r in q) if q else 1.0
    return max(_f(v, 1.0) * m, 0.01)


def integrate_vec(v, life, mult=1.0, n=16):
    """Accumulated value over life (n samples, any component count) of an integrated rate. A bare constant is
    applied as one fixed amount c * life for the whole life (League integrates only dynamics curves)."""
    dyn = v.get("dynamics") if isinstance(v, dict) else None
    times = dyn.get("times") if isinstance(dyn, dict) else None
    vals = dyn.get("values") if isinstance(dyn, dict) else None
    if not times:
        c = v.get("constantValue") if isinstance(v, dict) else None
        if c is None:
            return None
        c = c if isinstance(c, list) else [c]
        return [[round(x * mult * life, 4) for x in c]] * n
    steps = 64
    prev = _curve_at(times, vals, 0.0)
    prev = prev if isinstance(prev, list) else [prev]
    acc = [0.0] * len(prev)
    out = [list(acc)]
    for k in range(1, steps + 1):
        cur = _curve_at(times, vals, k / steps)
        cur = cur if isinstance(cur, list) else [cur]
        acc = [a + (p + c) * 0.5 * life / steps * mult for a, p, c in zip(acc, prev, cur)]
        prev = cur
        if k % (steps // (n - 1)) == 0 and len(out) < n:
            out.append([round(x, 4) for x in acc])
    while len(out) < n:
        out.append([round(x, 4) for x in acc])
    return out


def gv(x):
    """League vector -> Godot axes (no scaling)."""
    return [x[0], x[1], -x[2]] if isinstance(x, list) and len(x) == 3 else x


def gvm(x):
    return [x[0] * U, x[1] * U, -x[2] * U] if isinstance(x, list) and len(x) == 3 else x


# ===================================================================== assets
def export_tex(w, path):
    if not path or not isinstance(path, str):
        return None
    rel = "assets/vfx/" + path.lower().replace("\\", "/").rsplit(".", 1)[0] + ".png"
    out = os.path.join(ROOT, rel)
    if not os.path.exists(out):
        data = w.read(path.lower())
        if data is None:
            for g in ("Global.wad.client", "Common.wad.client"):
                try:
                    data = wad(f"{GAME}/{g}").read(path.lower())
                except Exception:
                    data = None
                if data is not None:
                    break
        if data is None:
            return None
        try:
            img = decode_tex(data)
        except Exception as ex:
            print("   tex fail", path, ex)
            return None
        os.makedirs(os.path.dirname(out), exist_ok=True)
        img.save(out)
    return "res://" + rel


def _read_scb(d):
    if d[:8] != b"r3d2Mesh":
        return None
    major, minor = struct.unpack_from("<HH", d, 8)
    p = 12 + 128
    nv, nf, flags = struct.unpack_from("<III", d, p)
    p += 12 + 24
    vtype = 0
    if major == 3 and minor == 2:
        vtype = struct.unpack_from("<I", d, p)[0]
        p += 4
    verts = [struct.unpack_from("<3f", d, p + i * 12) for i in range(nv)]
    p += nv * 12
    cols = None
    if vtype == 1:
        # vertex colors, BGRA bytes (Ezreal's Q cone fades along its length through vertex alpha)
        cols = [(d[p + i * 4 + 2] / 255.0, d[p + i * 4 + 1] / 255.0, d[p + i * 4] / 255.0, d[p + i * 4 + 3] / 255.0)
                for i in range(nv)]
        p += nv * 4
    _read_scb.cols = cols
    p += 12  # central point
    faces = []
    for i in range(nf):
        i0, i1, i2 = struct.unpack_from("<3I", d, p)
        p += 12 + 64
        u = struct.unpack_from("<3f", d, p)
        v = struct.unpack_from("<3f", d, p + 12)
        p += 24
        faces.append(((i0, i1, i2), u, v))
    return verts, faces


def _read_sco(d):
    lines = d.decode("utf-8", "replace").splitlines()
    verts, faces = [], []
    i = 0
    while i < len(lines):
        ln = lines[i].strip()
        if ln.startswith("Verts="):
            n = int(ln.split("=")[1])
            for k in range(n):
                verts.append(tuple(float(x) for x in lines[i + 1 + k].split()[:3]))
            i += n
        elif ln.startswith("Faces="):
            n = int(ln.split("=")[1])
            for k in range(n):
                parts = lines[i + 1 + k].replace("\t", " ").split()
                idx = (int(parts[1]), int(parts[2]), int(parts[3]))
                uv = [float(x) for x in parts[5:11]]
                faces.append((idx, (uv[0], uv[2], uv[4]), (uv[1], uv[3], uv[5])))
            i += n
        i += 1
    return verts, faces


def _has_normals(path):
    try:
        with open(path) as f:
            for ln in f:
                if ln.startswith("vn "):
                    return True
                if ln.startswith("f "):
                    return False
    except OSError:
        pass
    return False


def export_mesh(w, path):
    if not path or not isinstance(path, str):
        return None
    rel = "assets/vfx/" + path.lower().replace("\\", "/").rsplit(".", 1)[0] + ".obj"
    out = os.path.join(ROOT, rel)
    if not os.path.exists(out) or not _has_normals(out) or not os.path.exists(out[:-4] + ".vmesh.json") \
            or os.environ.get("VFX_REMESH"):
        data = w.read(path.lower())
        if data is None:
            return None
        try:
            r = _read_scb(data) if path.lower().endswith(".scb") else _read_sco(data)
        except Exception as ex:
            print("   mesh fail", path, ex)
            return None
        if not r or not r[0]:
            return None
        verts, faces = r
        gverts = [(x * U, y * U, -z * U) for x, y, z in verts]
        # smooth vertex normals (fresnel / falloff need them), in the written (z-flipped, re-wound) winding
        nrm = [[0.0, 0.0, 0.0] for _ in gverts]
        for (i0, i1, i2), _u, _v in faces:
            a, b, c = gverts[i0], gverts[i2], gverts[i1]
            e1 = [b[k] - a[k] for k in range(3)]
            e2 = [c[k] - a[k] for k in range(3)]
            n = [e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0]]
            for i in (i0, i1, i2):
                for k in range(3):
                    nrm[i][k] += n[k]
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "w") as f:
            for x, y, z in gverts:
                f.write(f"v {x:.5f} {y:.5f} {z:.5f}\n")
            for n in nrm:
                l = max((n[0] ** 2 + n[1] ** 2 + n[2] ** 2) ** 0.5, 1e-9)
                f.write(f"vn {n[0] / l:.4f} {n[1] / l:.4f} {n[2] / l:.4f}\n")
            n = 1
            for (i0, i1, i2), u, v in faces:
                # one vt per corner; Godot's OBJ importer flips V (OBJ is bottom-left origin)
                for k in range(3):
                    f.write(f"vt {u[k]:.5f} {1.0 - v[k]:.5f}\n")
                # z flip mirrors the mesh -> swap winding
                f.write(f"f {i0 + 1}/{n}/{i0 + 1} {i2 + 1}/{n + 2}/{i2 + 1} {i1 + 1}/{n + 1}/{i1 + 1}\n")
                n += 3
        # sidecar for LolVfx: unrolled triangles with vertex colors incl. alpha (OBJ cannot carry them)
        cols = getattr(_read_scb, "cols", None) if path.lower().endswith(".scb") else None
        _read_scb.cols = None
        sv, sn, su, sc = [], [], [], []
        for (i0, i1, i2), u, v in faces:
            for idx, k in ((i0, 0), (i2, 2), (i1, 1)):
                sv += [round(c, 5) for c in gverts[idx]]
                nn = nrm[idx]
                ln = max((nn[0] ** 2 + nn[1] ** 2 + nn[2] ** 2) ** 0.5, 1e-9)
                sn += [round(nn[0] / ln, 4), round(nn[1] / ln, 4), round(nn[2] / ln, 4)]
                su += [round(u[k], 5), round(v[k], 5)]
                if cols:
                    sc += [round(c, 4) for c in cols[idx]]
        with open(out[:-4] + ".vmesh.json", "w") as f:
            json.dump({"v": sv, "n": sn, "uv": su, "c": sc or None}, f, separators=(",", ":"))
    return "res://" + rel


# ===================================================================== emitters
PRIMS = {"VfxPrimitiveArbitraryQuad": "aquad", "VfxPrimitiveMesh": "mesh", "VfxPrimitiveCameraTrail": "ctrail",
         "VfxPrimitiveArbitraryTrail": "atrail", "VfxPrimitiveAttachedMesh": "amesh", "VfxPrimitiveRay": "ray",
         "VfxPrimitiveBeam": "beam", "VfxPrimitivePlanarProjection": "proj", "VfxPrimitiveCameraUnitQuad": "quad",
         "VfxPrimitiveCameraSegmentBeam": "beam"}
NQ = 32   # quantile samples per random table
NE = 16   # emitter-time samples for birth curves


def quantiles(v):
    """Inverse-CDF samples (NQ per component) of the value's probability tables, or None.

    League probability tables are piecewise-linear inverse CDFs: keyTimes = cumulative probability, keyValues = the
    multiplier at that probability (e.g. keyTimes [0, .5, .51, 1] / keyValues [1, 1, -1, -1] = 50% +1, 50% -1)."""
    if not isinstance(v, dict):
        return None
    dyn = v.get("dynamics")
    tabs = dyn.get("probabilityTables") if isinstance(dyn, dict) else None
    if not tabs:
        return None
    cols = []
    any_rand = False
    for t in tabs:
        kv = t.get("keyValues") if isinstance(t, dict) else None
        if not kv:
            cols.append([1.0] * NQ)
            continue
        kt = t.get("keyTimes") or [i / max(len(kv) - 1, 1) for i in range(len(kv))]
        col = [float(_curve_at(kt, kv, (i + 0.5) / NQ)) for i in range(NQ)]
        if any(abs(c - 1.0) > 1e-4 for c in col):
            any_rand = True
        cols.append(col)
    if not any_rand:
        return None
    return [[round(c[i], 4) for c in cols] for i in range(NQ)]


def ecurve(v):
    """Emitter-time samples (NE) of a birth value whose dynamics have several keys, else None.
    Birth values are evaluated at the emitter's normalized age when each particle is born."""
    if not isinstance(v, dict):
        return None
    dyn = v.get("dynamics")
    if not (isinstance(dyn, dict) and dyn.get("times") and len(dyn["times"]) > 1):
        return None
    out = []
    for i in range(NE):
        x = _curve_at(dyn["times"], dyn["values"], i / (NE - 1))
        out.append([round(a, 4) for a in x] if isinstance(x, list) else round(x, 4))
    return out


def _r(x, n=4):
    if isinstance(x, list):
        return [_r(a, n) for a in x]
    if isinstance(x, float):
        return round(x, n)
    return x


def _f(x, d=0.0):
    try:
        return float(x)
    except (TypeError, ValueError):
        return d


H = {  # unnamed hashes identified by context
    "lingerColor": "6b77a8ca", "useLingerColor": "2fec8a25", "birthUVOffsetMult": "740ca9c0",
    "particleUVScrollRateMult": "22c3cf3e", "emitterUvScrollRateMult": "e19d1593",
}


def emitter_gate(e):
    """League's load-time spawn gates (LeagueToolkit meta-wiki VfxEmitterDefinitionData "Spawn gates"): a
    `disabled` emitter is dropped while the system definition is prepared; `Filtering` drops it unless the
    instance carries every `keywordsRequired` keyword (our base skins carry none) and its spectatorPolicy
    allows a player client (2 = EnableWhenSpectating only). Returns True when the emitter exists."""
    if e.get("disabled"):
        return False
    f = e.get("Filtering") or e.get("filtering")
    if isinstance(f, dict):
        if f.get("keywordsRequired") or f.get("keywordsIncluded"):
            return False
        sp = f.get("spectatorPolicy")
        if sp is not None and int(sp) >= 2:
            return False
    return True


def emitter(w, e, ctx):
    if not emitter_gate(e):
        return None
    o = {"name": e.get("emitterName", "")}
    prim = e.get("primitive")
    pcls = prim.get("__class") if isinstance(prim, dict) else None
    o["prim"] = PRIMS.get(pcls, "quad")
    # ---- children (spawned per particle) - keep the emitter even without a texture
    ch = e.get("childParticleSetDefinition")
    children = []
    if isinstance(ch, dict):
        for c in ch.get("childrenIdentifiers") or []:
            k = c.get("effectKey") if isinstance(c, dict) else None
            nm = ctx["resolve"](k) if k else None
            if nm is None and isinstance(c, dict) and c.get("effectName"):
                nm = c["effectName"]
            if nm:
                children.append(nm)
        if children:
            o["children"] = children
            bones = ch.get("boneToSpawnAt")
            if bones:
                o["child_bones"] = bones
    if o["prim"] == "mesh":
        m = prim.get("mMesh") or {}
        mesh = export_mesh(w, m.get("mSimpleMeshName") or m.get("mMeshName"))
        if mesh is None and not children:
            return None
        o["mesh"] = mesh
        if mesh is None:
            o["prim"] = "quad"
    if o["prim"] == "amesh":
        m = prim.get("mMesh") or {}
        o["amesh"] = {"submeshes": len(m.get("mSubmeshesToDraw") or []), "lock": bool(m.get("mLockMeshToAttachment", False))}
    if o["prim"] in ("ctrail", "atrail"):
        t = prim.get("mTrail") or {}
        til = t.get("mBirthTilingSize")
        o["trail"] = {"cutoff": _f(t.get("mCutoff")) * U, "mode": int(t.get("mMode", 0) or 0),
                      "smooth": int(t.get("mSmoothingMode", 0) or 0), "max_add": int(t.get("mMaxAddedPerFrame", 0) or 0),
                      "tiling": _f((val(til, [0, 0, 0]) or [0])[0]) * U if isinstance(val(til), list) else _f(val(til)) * U,
                      "tiling_ec": [round(_f(x[0] if isinstance(x, list) else x) * U, 4) for x in ecurve(til)] if ecurve(til) else None}
    if o["prim"] == "beam":
        b = prim.get("mBeam") or {}
        o["beam_segments"] = int(b.get("mSegments", 0) or 0)
    if o["prim"] == "proj":
        pj = prim.get("mProjection") or {}
        o["proj"] = {"yrange": _f(pj.get("mYRange"), 0.0) * U, "fade": _f(pj.get("mFading"), 0.0) * U}
    tex = export_tex(w, e.get("texture"))
    if tex is None and o["prim"] != "amesh" and not children:
        return None
    o["tex"] = tex
    o["blend"] = int(e.get("blendMode", 0) or 0)
    # ---- timing
    # isSingleParticle: one burst of `rate` particles when the emitter starts (rate is the count)
    o["single"] = bool(e.get("isSingleParticle", False))
    rate = e.get("rate")
    o["rate"] = float(val(rate, 1.0) or 0.0)
    o["rate_ec"] = ecurve(rate)
    if o["rate_ec"]:
        o["rate"] = max(o["rate_ec"])
    o["life"] = float(e["lifetime"]) if e.get("lifetime") is not None else -1.0
    o["delay"] = _f(e.get("timeBeforeFirstEmission"))
    if e.get("period"):
        o["period"] = _f(e.get("period"))
        o["active"] = _f(e.get("timeActiveDuringPeriod"), o["period"])
    pl_v = e.get("particleLifetime")
    pl = float(val(pl_v, 1.0) if val(pl_v, 1.0) is not None else 1.0)
    q = quantiles(pl_v)
    if q:
        m0 = [r[0] for r in q]
        o["plife"] = [pl * min(m0), pl * max(m0)]
        o["plife_q"] = [round(x / max(m0), 4) if max(m0) > 0 else 1.0 for x in m0]
    else:
        o["plife"] = [pl, pl]
    o["linger"] = _f(e.get("particleLinger"))
    o["elinger"] = _f(e.get("emitterLinger"))
    lg = e.get("linger")
    if isinstance(lg, dict):
        lc = curve(lg.get(H["lingerColor"]))
        if lc:
            o["linger_color"] = lc
    # ---- placement / space
    o["pos"] = gvm(val(e.get("emitterPosition"), [0, 0, 0]))
    bw = val(e.get("bindWeight"), None)
    o["bind"] = _f(bw, 0.0) if bw is not None else 0.0
    o["local"] = o["bind"] >= 0.5
    o["lorient"] = bool(e.get("isLocalOrientation", True))
    o["plorient"] = bool(e.get("particleIsLocalOrientation", False))
    o["ground"] = bool(e.get("isGroundLayer", False))
    o["terrain"] = bool(e.get("isFollowingTerrain", False))
    o["dir"] = bool(e.get("isDirectionOriented", False))
    if e.get("directionVelocityScale"):
        o["dvs"] = _f(e.get("directionVelocityScale"))
        o["dvmin"] = _f(e.get("directionVelocityMinScale"), 0.0)
    o["uniform"] = bool(e.get("isUniformScale", False))
    o["pass"] = int(e.get("pass", 0) or 0)
    # alphaRef is declared with default 5 (Riot's writer omits defaults: 1422 emitters write an explicit 0, none
    # write 5); 0 turns the test off. Under Add / None blending it is what drops transparent texels.
    ar = e.get("alphaRef")
    o["alpha_ref"] = 5 if ar is None else int(ar)
    # miscRenderFlags bit 0x1 = DisableZBuffer (depth test off), 0x4 = DisableFow; the byte is also the last
    # draw-order key (meta-wiki VfxEmitterDefinitionData; ltk-manager ParticleSystem::MISC_RENDER_FLAG)
    if e.get("miscRenderFlags"):
        o["misc"] = int(e.get("miscRenderFlags"))
    db = e.get("depthBiasFactors")
    if isinstance(db, list) and len(db) == 2:
        o["dbias"] = [_f(db[0]), _f(db[1])]
    o["disable_cull"] = bool(e.get("disableBackfaceCull", False))
    # ---- color
    bcv = e.get("birthColor")
    bc = val(bcv, [1, 1, 1, 1])
    o["bcolor"] = bc if isinstance(bc, list) and len(bc) == 4 else [1, 1, 1, 1]
    o["bcolor_ec"] = ecurve(bcv)
    o["bcolor_q"] = quantiles(bcv)
    o["color"] = curve(e.get("color"))
    if o["color"] is None and isinstance(e.get("color"), dict) and e["color"].get("constantValue"):
        o["bcolor"] = [a * b for a, b in zip(o["bcolor"], e["color"]["constantValue"])]
        if o["bcolor_ec"]:
            o["bcolor_ec"] = [[round(a * b, 4) for a, b in zip(x, e["color"]["constantValue"])] for x in o["bcolor_ec"]]
    o["ctex"] = export_tex(w, e.get("particleColorTexture"))
    # colour lookup drivers: 0 Constant (coord = scale), 1 Lifetime (scale*age+offset), 2 Velocity, 3 BirthRandom.
    # Declared defaults X = 1, Y = 0 (explicit X=0 / Y=1..3 occur, never X=1 / Y=0), so the default sample point
    # is (age fraction, 1).
    o["clut"] = [int(e.get("colorLookUpTypeX", 1)), int(e.get("colorLookUpTypeY", 0))]
    if e.get("colorLookUpScales"):
        o["cscale"] = e.get("colorLookUpScales")
    if e.get("colorLookUpOffsets"):
        o["coff"] = e.get("colorLookUpOffsets")
    # ---- scale
    bsv = e.get("birthScale0")
    bs = val(bsv, [1, 1, 1])
    if not isinstance(bs, list):
        bs = [bs, bs, bs]
    o["bscale"] = bs
    o["bscale_ec"] = ecurve(bsv)
    o["bscale_q"] = quantiles(bsv)
    o["scale"] = curve(e.get("scale0"))
    if o["scale"] is None:
        s0 = val(e.get("scale0"))
        if isinstance(s0, list) and any(abs(x - 1) > 1e-4 for x in s0):
            o["bscale"] = [a * b for a, b in zip(bs, s0)]
    # ---- rotation (degrees)
    o["brot"] = val(e.get("birthRotation0"), [0, 0, 0])
    o["brot_q"] = quantiles(e.get("birthRotation0"))
    o["rotvel"] = val(e.get("birthRotationalVelocity0"), [0, 0, 0])
    o["rotvel_q"] = quantiles(e.get("birthRotationalVelocity0"))
    o["rot"] = curve(e.get("rotation0"))
    # rotation0 is an integrated spin RATE in degrees per 1/60 s, active only with isRotationEnabled; a bare
    # constantValue is a fixed extra angle c * 60 * lifetime (meta-wiki rotation0 / isRotationEnabled)
    r0 = e.get("rotation0")
    if e.get("isRotationEnabled") and isinstance(r0, dict):
        o["rotint"] = integrate_vec(r0, _plife_max(e), 60.0)
    # ---- motion (League units -> meters, z flipped)
    bvv = e.get("birthVelocity")
    o["bvel"] = gvm(val(bvv, [0, 0, 0]))
    o["bvel_ec"] = [gvm(x) for x in ecurve(bvv)] if ecurve(bvv) else None
    o["bvel_q"] = quantiles(bvv)
    o["drag"] = val(e.get("birthDrag"), [0, 0, 0])
    o["drag_q"] = quantiles(e.get("birthDrag"))
    acc = val(e.get("birthAcceleration"), [0, 0, 0]) or [0, 0, 0]
    wacc = val(e.get("worldAcceleration"), [0, 0, 0]) or [0, 0, 0]
    o["laccel"] = gvm(acc)
    o["accel"] = gvm(wacc)
    ov = e.get("birthOrbitalVelocity")
    if ov is not None:
        o["orbit"] = gv(val(ov, [0, 0, 0]))   # radians / second around the emitter's axes
        o["orbit_q"] = quantiles(ov)
    fc = e.get("fieldCollectionDefinition")
    if isinstance(fc, dict):
        f = {}
        for a in fc.get("fieldAccelerationDefinitions") or []:
            f.setdefault("accel", [0, 0, 0])
            v = gvm(val(a.get("acceleration"), [0, 0, 0]) or [0, 0, 0])
            f["accel"] = [x + y for x, y in zip(f["accel"], v)]
        for a in fc.get("fieldDragDefinitions") or []:
            f["drag"] = f.get("drag", 0.0) + _f(val(a.get("strength"), 1.0), 1.0)
        for a in fc.get("fieldNoiseDefinitions") or []:
            f["noise"] = {"freq": _f(val(a.get("frequency"), 1.0), 1.0), "delta": _f(val(a.get("velocityDelta"), 0.0)) * U,
                          "axis": gv(a.get("axisFraction") or [1, 1, 1])}
        for a in fc.get("fieldAttractionDefinitions") or []:
            f["attract"] = {"pos": gvm(val(a.get("position"), [0, 0, 0])), "accel": _f(val(a.get("acceleration"), 0.0)) * U,
                            "radius": _f(val(a.get("radius"), 0.0)) * U}
        for a in fc.get("fieldOrbitalDefinitions") or []:
            d = val(a.get("direction"), None)
            if isinstance(d, list):
                f["orbital"] = gv(d)
        if f:
            o["fields"] = f
    # ---- emission shape
    sh = e.get("shape")
    shape = None
    if isinstance(sh, dict):
        c = sh.get("__class", "")
        flags = int(sh.get("flags", 0) or 0)
        if c == "VfxShapeSphere":
            shape = {"type": "sphere", "radius": _f(sh.get("radius")) * U, "flags": flags}
        elif c == "VfxShapeBox":
            # Size holds HALF extents (meta-wiki SpawnShape table)
            shape = {"type": "box", "half": [abs(x) * U for x in (sh.get("boxSize") or [0, 0, 0])], "flags": flags}
        elif c == "VfxShapeCylinder":
            shape = {"type": "cyl", "radius": _f(sh.get("radius")) * U, "height": _f(sh.get("height")) * U, "flags": flags}
        else:
            shape = {"type": "offset"}
            off = sh.get("emitOffset")
            if isinstance(off, dict):
                shape["offset"] = gvm(val(off, [0, 0, 0]) or [0, 0, 0])
                qo = quantiles(off)
                if qo:
                    shape["offset_q"] = qo
            elif isinstance(off, list):
                shape["offset"] = gvm(off)
            angs = sh.get("emitRotationAngles") or []
            axes = sh.get("emitRotationAxes") or []
            rots = []
            for a, ax in zip(angs, axes):
                if not isinstance(ax, list) or sum(abs(x) for x in ax) < 1e-4:
                    continue
                base = _f(val(a, 0.0), 0.0) if isinstance(a, dict) else _f(a)
                qa = quantiles(a) if isinstance(a, dict) else None
                lo = base * (min(r[0] for r in qa) if qa else 1.0)
                hi = base * (max(r[0] for r in qa) if qa else 1.0)
                if abs(lo) < 1e-4 and abs(hi) < 1e-4:
                    continue
                rots.append({"axis": gv(ax), "q": [round(base * r[0], 3) for r in qa] if qa else [base] * NQ})
            if rots:
                shape["rots"] = rots[:2]
            if not shape.get("offset") and not rots:
                shape = None
    o["shape"] = shape
    # ---- flipbook / uv
    td = e.get("texDiv")
    o["texdiv"] = [int(td[0]), int(td[1])] if isinstance(td, list) and len(td) == 2 else [1, 1]
    o["frames"] = int(val(e.get("numFrames"), 0) or 0)
    o["fps"] = float(val(e.get("frameRate"), 0) or val(e.get("birthFrameRate"), 0) or 0)
    o["start_frame"] = int(val(e.get("startFrame"), 0) or 0)
    o["rand_frame"] = bool(e.get("isRandomStartFrame", False))
    life_max = o["plife"][1] if o["plife"][1] > 0 else 1.0
    o["uvscale"] = val(e.get("uvScale"), None)
    o["uvrate"] = val(e.get("birthUVScrollRate"), None)
    o["uvrate_q"] = quantiles(e.get("birthUVScrollRate"))
    o["uvint"] = integrate(e.get("particleUVScrollRate"), life_max)
    o["uvrot"] = _f(val(e.get("uvRotation"), 0.0))
    o["uvrotrate"] = _f(val(e.get("birthUVRotateRate"), 0.0))
    o["uvmode"] = int(e.get("uvMode", 0) or 0)
    o["uvclamp"] = bool(e.get("uvScrollClamp", False))
    o["addr"] = int(e.get("texAddressModeBase", 0) or 0)
    if e.get("emitterUvScrollRate"):
        o["emuv"] = e.get("emitterUvScrollRate")
    o["flip"] = [bool(e.get("textureFlipU", False)), bool(e.get("textureFlipV", False))]
    uo = val(e.get("birthUVOffset"), None)
    ur = quantiles(e.get("birthUVOffset"))
    if isinstance(uo, list) and len(uo) == 2:
        if ur:
            xs = [r[0] for r in ur]
            ys = [r[1] if len(r) > 1 else 1.0 for r in ur]
            o["uvoff"] = [[uo[0] * min(xs), uo[1] * min(ys)], [uo[0] * max(xs), uo[1] * max(ys)]]
        else:
            o["uvoff"] = [uo, uo]
    # ---- multiply texture layer
    tm = e.get("texturemult")
    if isinstance(tm, dict) and tm.get("texturemult"):
        o["tex2"] = export_tex(w, tm.get("texturemult"))
        o["uv2scale"] = val(tm.get("uvScaleMult"), None)
        tdm = tm.get("texDivMult")
        if isinstance(tdm, list) and len(tdm) == 2:
            s2 = o["uv2scale"] or [1.0, 1.0]
            o["uv2scale"] = [s2[0] / max(tdm[0], 1e-3), s2[1] / max(tdm[1], 1e-3)]
        o["uv2rate"] = val(tm.get("birthUvScrollRateMult"), None)
        o["uv2int"] = integrate(tm.get(H["particleUVScrollRateMult"]), life_max)
        o["uv2rot"] = _f(val(tm.get("uvRotationMult"), 0.0))
        o["uv2off"] = val(tm.get(H["birthUVOffsetMult"]), None)
        o["addr2"] = int(tm.get("texAddressModeMult", 0) or 0)
        o["uv2clamp"] = bool(tm.get("uvScrollClampMult", False))
        if tm.get(H["emitterUvScrollRateMult"]):
            o["emuv2"] = tm.get(H["emitterUvScrollRateMult"])
    # ---- erosion (dissolve)
    er = e.get("alphaErosionDefinition")
    if isinstance(er, dict) and er.get("erosionMapName"):
        o["ero_tex"] = export_tex(w, er.get("erosionMapName"))
        o["ero_curve"] = sample_curve(er.get("erosionDrive"), 16)
        ch2 = val(er.get("erosionMapChannelMixer"), [1, 0, 0, 0])
        o["ero_ch"] = ch2 if isinstance(ch2, list) and len(ch2) == 4 else [1, 0, 0, 0]
        o["ero_feather"] = _f(er.get("erosionFeatherIn"), 0.1) or 0.1
        o["ero_slice"] = _f(er.get("erosionSliceWidth"), 0.0)
        # [vfx-calib] quad_ps / mesh_ps band: a *= sat((t-e+slice)/featherIn) - sat((t-e)/featherOut)
        o["ero_feather_out"] = _f(er.get("erosionFeatherOut"), 0.0)
    # ---- soft particles (depth fade), League units
    sp = e.get("softParticleParams")
    if isinstance(sp, dict):
        o["soft"] = True
        o["soft_in"] = (_f(sp.get("beginIn")) + _f(sp.get("deltaIn"), 0.0)) * U or 0.3
        if _f(sp.get("beginIn")) > 0:
            o["soft_begin"] = _f(sp.get("beginIn")) * U   # fade = smoothstep(beginIn, beginIn + deltaIn, depth gap)
        if _f(sp.get("deltaOut")) > 0:
            o["soft_out"] = [_f(sp.get("beginOut")) * U, _f(sp.get("deltaOut")) * U]   # optional far fade
    else:
        o["soft"] = False
    # ---- distortion / reflection / falloff
    dd = e.get("distortionDefinition")
    if isinstance(dd, dict):
        o["distort"] = {"strength": _f(dd.get("distortion"), 0.1), "mode": int(dd.get("distortionMode", 0) or 0),
                        "normal": export_tex(w, dd.get("normalMapTexture"))}
    rd = e.get("reflectionDefinition")
    if isinstance(rd, dict):
        o["fresnel"] = {"f": _f(rd.get("fresnel"), 0.0), "color": rd.get("fresnelColor") or [0, 0, 0, 0],
                        "rf": _f(rd.get("reflectionFresnel"), 0.0), "glance": _f(rd.get("reflectionOpacityGlancing"), 0.0),
                        "direct": _f(rd.get("reflectionOpacityDirect"), 0.0)}
    if e.get("falloffTexture"):
        o["falloff"] = export_tex(w, e.get("falloffTexture"))
    pd = e.get("paletteDefinition")
    if isinstance(pd, dict):
        sel = val(pd.get("paletteSelector"), [0, 0, 0])
        o["palette"] = {"row": _f(sel[0] if isinstance(sel, list) else sel), "count": int(pd.get("paletteCount", 1) or 1),
                        "tex": export_tex(w, pd.get("paletteTexture"))}
        mx = val(pd.get("palleteSrcMixColor"), None)
        if isinstance(mx, list) and len(mx) == 4:
            o["palette"]["mix"] = mx   # quad_ps: u = saturate(dot(texel, mixer))
    if o.get("clut") == [1, 0]:
        del o["clut"]   # the default lookup (age fraction, 1)
    # drop keys that carry no information (smaller json)
    for k in [k for k, v in o.items() if v is None or v is False or v == [] or v == {}]:
        if k not in ("tex", "single", "local", "ground", "dir", "uniform", "soft", "lorient"):
            del o[k]
    return _r(o)


def system(w, sysobj, ctx=None):
    ctx = ctx or {"resolve": lambda k: None}
    name = sysobj.get("particleName")
    if not name:
        return None, None
    ems = []
    for key in ("complexEmitterDefinitionData", "simpleEmitterDefinitionData"):
        for e in sysobj.get(key) or []:
            if isinstance(e, dict):
                try:
                    r = emitter(w, e, ctx)
                except Exception as ex:
                    import traceback
                    traceback.print_exc()
                    print("   emitter fail", name, e.get("emitterName"), ex)
                    r = None
                if r is not None:
                    ems.append(r)
    if not ems:
        return name, None
    dur = 0.0
    for e in ems:
        life = e["life"] if e["life"] >= 0 else 2.0
        pl = e["plife"][1] if e["plife"][1] > 0 else 0.0
        # `lifetime` is the emission END time measured from the system start, not from timeBeforeFirstEmission
        # (meta-wiki: "with a delay of 1 and a lifetime of 3 the emitter emits for 2 seconds")
        d0 = e.get("delay", 0.0)
        dur = max(dur, (d0 if e.get("single") else max(life, d0)) + pl)
    out = {"emitters": ems, "dur": round(dur, 3), "loop": any(e["life"] < 0 for e in ems)}
    xf = sysobj.get("transform")
    if isinstance(xf, list) and len(xf) == 16:
        # system transform (meta-wiki particle update step 7); only uniform scale is used by shipped data we play
        sc = round((abs(xf[0]) + abs(xf[5]) + abs(xf[10])) / 3.0, 4)
        if abs(sc - 1.0) > 1e-3:
            out["sys_scale"] = sc
    if sysobj.get("overrideScaleCap"):
        out["scale_cap"] = _f(sysobj.get("overrideScaleCap"))
    return name, out


def _resolver(entries, rr_maps):
    """effectKey (resource-resolver hash or entry link) -> particleName."""
    def res(k):
        s = str(k)
        h = None
        if s.startswith("hash:") or s.startswith("link:"):
            h = int(s[5:], 16)
        elif isinstance(k, int):
            h = int(k)
        if h is None:
            return None
        if h in entries:
            return entries[h]
        for m in rr_maps:
            ln = m.get(h)
            if ln is not None and ln in entries:
                return entries[ln]
        return None
    return res


def _rr_map(pyobj):
    out = {}
    rm = pyobj.get("resourceMap") if isinstance(pyobj, dict) else None
    if isinstance(rm, dict):
        for a, b in rm.items():
            try:
                out[int(str(a).split(":")[-1], 16)] = int(str(b).split(":")[-1], 16)
            except ValueError:
                pass
    return out


SPELL_MISSILE_HASH = "fdfac367"   # mMissileSpec.movement
MOV_START_BONE = "b886d871"
MOV_END_BONE = "95bb67b8"
MOV_START_H = "90d578dd"
MOV_END_H = "f20fdeef"


def spell_meta(sp):
    """Per-spell VFX placement data: hit bone, missile start/end bones and heights (League units -> m)."""
    s = sp.get("mSpell") if isinstance(sp, dict) else None
    if not isinstance(s, dict):
        return None
    o = {}
    if s.get("mHitBoneName"):
        o["hit_bone"] = s["mHitBoneName"]
    ms = s.get("mMissileSpec")
    if isinstance(ms, dict):
        mv = ms.get(SPELL_MISSILE_HASH)
        if isinstance(mv, dict):
            if mv.get(MOV_START_BONE):
                o["start_bone"] = mv[MOV_START_BONE]
            if mv.get(MOV_END_BONE):
                o["end_bone"] = mv[MOV_END_BONE]
            if mv.get(MOV_START_H) is not None:
                o["start_h"] = round(_f(mv[MOV_START_H]) * U, 3)
            if mv.get(MOV_END_H) is not None:
                o["end_h"] = round(_f(mv[MOV_END_H]) * U, 3)
    return o or None


def extract_champion(alias):
    low = alias.lower()
    w = wad(f"{GAME}/Champions/{alias}.wad.client")
    sk = BinFile(w.read(f"data/characters/{low}/skins/skin0.bin"))
    bins = [f"data/characters/{low}/skins/skin0.bin"] + [l.lower() for l in sk.links]
    parsed = []
    for b in bins:
        d = w.read(b)
        if d is None:
            continue
        try:
            parsed.append(BinFile(d))
        except Exception:
            continue
    # pass 1: names of every particle system and the resource resolvers (for child effect keys)
    entries, rr, spells = {}, [], {}
    for bf in parsed:
        for k, v in bf.entries.items():
            if v.cls == 0x45cd899f:
                p = to_py(v, TABLE)
                if p.get("particleName"):
                    entries[k] = p["particleName"]
            elif TABLE.get(v.cls) == "ResourceResolver":
                rr.append(_rr_map(to_py(v, TABLE)))
            elif TABLE.get(v.cls) == "SpellObject":
                p = to_py(v, TABLE)
                sm = spell_meta(p)
                if sm and p.get("mScriptName"):
                    spells[p["mScriptName"]] = sm
    ctx = {"resolve": _resolver(entries, rr)}
    out = {}
    for bf in parsed:
        for k, v in bf.entries.items():
            if v.cls != 0x45cd899f:
                continue
            name, s = system(w, to_py(v, TABLE), ctx)
            if s is not None and name not in out:
                out[name] = s
    if spells:
        out["_spells"] = spells
    path = os.path.join(ROOT, "data", "vfx", f"{low}.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(out, open(path, "w", encoding="utf-8"), separators=(",", ":"))
    print(f"{alias}: {len(out)} systems")
    return out


SHARED_PATTERNS = [
    r"^Cursor_Moveto$", r"^Summoner_Snowball_", r"^Global_SS_Ignite", r"^Global_Haste$", r"^Jade_Summoner_Cleanse$",
    r"^Monster_Heal_Impact$", r"^Item_Redemption_Hit_Heal$", r"^Global_Slow$", r"^ARAMHealthPickup_",
    r"^Turret_Skin2[45]_", r"^HA_(Order|Chaos)_(Inhibitor|Nexus)_", r"^SRU_(Order|Chaos)Minion(Ranged|Siege)_Base_",
    r"^ARAM_Hexgate_Base_(OpenLoop|PortalGroundLoop)", r"^LOC_(Stun|Silence|Taunt)$",
    # Howling Abyss relic pickup / heal, turret weapon glows
    r"^HowlingAbyss_HealthPickup_", r"^HA_Health", r"^HA_(Order|Chaos)_Turret_Weapon_Glow$",
]


def extract_shared():
    import re
    out = {}
    pats = [re.compile(p) for p in SHARED_PATTERNS]
    ctx = {"resolve": lambda k: None}
    for wp in (f"{GAME}/Global.wad.client", f"{GAME}/Maps/Shipping/Map12.wad.client"):
        w = wad(wp)
        es = w.entries.values() if isinstance(w.entries, dict) else w.entries
        for e in es:
            if e.size > 30_000_000:
                continue
            try:
                d = w.read_entry(e)
            except Exception:
                continue
            if d[:4] not in (b"PROP", b"PTCH"):
                continue
            try:
                bf = BinFile(d)
            except Exception:
                continue
            for k, v in bf.entries.items():
                if v.cls != 0x45cd899f:
                    continue
                nm = None
                for fk, fv in v.fields.items():
                    if TABLE.get(fk) == "particleName":
                        nm = fv
                if not nm or nm in out or not any(p.search(nm) for p in pats):
                    continue
                name, sysd = system(w, to_py(v, TABLE), ctx)
                if sysd is not None:
                    out[name] = sysd
    for name, tpath in LEGACY_TROY.items():
        try:
            sysd = troy_system(tpath)
        except Exception as ex:
            print("   troy fail", tpath, ex)
            sysd = None
        if sysd is not None:
            out[name] = sysd
    path = os.path.join(ROOT, "data", "vfx", "shared.json")
    json.dump(out, open(path, "w", encoding="utf-8"), separators=(",", ":"))
    print(f"shared: {len(out)} systems")
    print("   ", sorted(out))


# ===================================================================== legacy .troybin systems
# Summoner Flash / Barrier and the champion level-up burst still ship as legacy troy particles (inibin v2 in
# DATA.wad.client). They are converted to bin-like emitter dicts and run through emitter() above.
LEGACY_TROY = {
    "Global_SS_Flash": "data/particles/global_ss_flash.troybin",          # cast (departure)
    "Global_SS_Flash_02": "data/particles/global_ss_flash_02.troybin",    # arrival
    "Global_SS_Barrier": "data/particles/global_ss_barrier.troybin",      # shield bubble
    "LevelUp_glb": "data/particles/levelup_glb.troybin",                  # champion level up
    # [anim-events] Order melee minion swing (Attack1-3 ParticleEventData mEffectName "DATA/Particles/...troy")
    "SRU_Order_MM_BA1_cas": "data/particles/sru_order_mm_ba1_cas.troybin",
}


def _ihash(s):
    h = 0
    for c in s.lower():
        h = (ord(c) + 65599 * h) & 0xffffffff
    return h


def _parse_inibin2(d):
    if d[0] != 2:
        raise ValueError("inibin version %d" % d[0])
    _slen, flags = struct.unpack_from("<HH", d, 1)
    p = 5
    out = {}
    for bit in range(16):
        if not flags & (1 << bit):
            continue
        n = struct.unpack_from("<H", d, p)[0]
        p += 2
        ks = struct.unpack_from("<%dI" % n, d, p)
        p += 4 * n
        if bit == 0:
            vs = struct.unpack_from("<%di" % n, d, p); p += 4 * n
        elif bit == 1:
            vs = struct.unpack_from("<%df" % n, d, p); p += 4 * n
        elif bit == 2:
            vs = [b / 10.0 for b in d[p:p + n]]; p += n
        elif bit == 3:
            vs = struct.unpack_from("<%dh" % n, d, p); p += 2 * n
        elif bit == 4:
            vs = list(d[p:p + n]); p += n
        elif bit == 5:
            nb = (n + 7) // 8
            bits = d[p:p + nb]; p += nb
            vs = [int(bits[i // 8] >> (i % 8) & 1) for i in range(n)]
        elif bit == 6:
            vs = [[b / 10.0 for b in d[p + 3 * i:p + 3 * i + 3]] for i in range(n)]; p += 3 * n
        elif bit == 7:
            vs = [list(struct.unpack_from("<3f", d, p + 12 * i)) for i in range(n)]; p += 12 * n
        elif bit == 8:
            vs = [[b / 10.0 for b in d[p + 2 * i:p + 2 * i + 2]] for i in range(n)]; p += 2 * n
        elif bit == 9:
            vs = [list(struct.unpack_from("<2f", d, p + 8 * i)) for i in range(n)]; p += 8 * n
        elif bit == 10:
            vs = [[b / 10.0 for b in d[p + 4 * i:p + 4 * i + 4]] for i in range(n)]; p += 4 * n
        elif bit == 11:
            vs = [list(struct.unpack_from("<4f", d, p + 16 * i)) for i in range(n)]; p += 16 * n
        elif bit == 12:
            offs = struct.unpack_from("<%dH" % n, d, p); p += 2 * n
            base = p
            vs = []
            for o in offs:
                e = d.index(b"\x00", base + o)
                vs.append(d[base + o:e].decode("latin1"))
        else:
            raise ValueError("inibin type bit %d" % bit)
        for k, v in zip(ks, vs):
            out[k] = v
    return out


def _troy_nums(v):
    if isinstance(v, str):
        try:
            return [float(x) for x in v.split()]
        except ValueError:
            return None
    if isinstance(v, (list, tuple)):
        return [float(x) for x in v]
    return [float(v)]


def troy_system(tpath):
    w = wad(f"{GAME}/DATA.wad.client")
    d = w.read(tpath)
    if d is None:
        return None
    kv = _parse_inibin2(d)

    def get(sec, key):
        return kv.get(_ihash(sec + "*" + key))

    def nums(sec, key):
        v = get(sec, key)
        return _troy_nums(v) if v is not None else None

    def ptable(sec, key, comp=""):
        kt, vals = [], []
        for i in range(1, 9):
            r = nums(sec, f"{key}{comp}P{i}")
            if not r or len(r) < 2:
                break
            kt.append(r[0])
            vals.append(r[1])
        return {"__class": "VfxProbabilityTableData", "keyTimes": kt, "keyValues": vals} if len(kt) >= 2 else {}

    def value(sec, key, n, default=None, rand=True):
        base = nums(sec, key)
        if base is None:
            base = default
        if base is None:
            return None
        base = (base + [base[-1]] * n)[:n] if n > 1 else base[:1]
        out = {"constantValue": base if n > 1 else base[0]}
        if rand:
            tabs = [ptable(sec, key, c) for c in (["X", "Y", "Z", "W"][:n] if n > 1 else [""])]
            if any(tabs):
                out["dynamics"] = {"probabilityTables": tabs, "times": [0.0], "values": [out["constantValue"]]}
        return out

    def curve(sec, key, n):
        ts, vs = [], []
        for i in range(1, 12):
            r = nums(sec, f"{key}{i}")
            if not r or len(r) < 2:
                break
            ts.append(r[0])
            row = r[1:1 + n]
            vs.append((row + [row[-1]] * n)[:n] if n > 1 else row[0])
        return {"dynamics": {"times": ts, "values": vs}} if len(ts) >= 2 else None

    groups = []
    for i in range(1, 20):
        g = get("System", f"GroupPart{i}")
        if isinstance(g, str):
            groups.append(g)
    ems = []
    for g in groups:
        tex = get(g, "p-texture")
        if not isinstance(tex, str):
            tex = get(g, "p-meshtex")   # mesh groups name their texture p-meshtex (Ghost's swirl)
        e = {"emitterName": g, "texture": tex}
        if not isinstance(e["texture"], str):
            continue
        mesh = get(g, "p-mesh")
        ptype = int((nums(g, "p-type") or [0])[0])
        if isinstance(mesh, str):
            e["primitive"] = {"__class": "VfxPrimitiveMesh", "mMesh": {"mSimpleMeshName": mesh}}
        elif ptype == 11:
            e["primitive"] = {"__class": "VfxPrimitiveAttachedMesh", "mMesh": {}}   # avatar copies (Ghost)
        elif ptype == 1:
            e["primitive"] = {"__class": "VfxPrimitiveArbitraryQuad"}
        nm_tex = get(g, "p-normal-map")
        if isinstance(nm_tex, str):
            # refraction group (Cleanse's "distort"): its texture is only a mask, never draw it as a quad
            pw = _troy_nums(get(g, "p-distortion-power")) or [1.0]   # "1d" style strings parse as None
            e["distortionDefinition"] = {"distortion": min(float(pw[0]), 1.0) * 0.05, "normalMapTexture": nm_tex}
        uvs = nums(g, "p-uvscroll-rgb")
        if uvs and len(uvs) >= 2:
            e["birthUVScrollRate"] = {"constantValue": uvs[:2]}
        e["blendMode"] = int((nums(g, "rendermode") or [0])[0])
        e["rate"] = value(g, "e-rate", 1, [1.0], rand=False)
        el = nums(g, "e-life")
        if el:
            e["lifetime"] = el[0]
        to = nums(g, "e-timeoffset")
        if to:
            e["timeBeforeFirstEmission"] = to[0]
        e["particleLifetime"] = value(g, "p-life", 1, [1.0])
        lg = nums(g, "p-linger")
        if lg and lg[0] > 0:
            e["particleLinger"] = lg[0]
        off = value(g, "p-offset", 3)
        if off:
            e["shape"] = {"__class": "VfxShapeLegacy", "emitOffset": off}
        po = nums(g, "p-postoffset")
        if po:
            e["emitterPosition"] = {"constantValue": (po + [0, 0, 0])[:3]}
        e["birthScale0"] = value(g, "p-scale", 3, [10.0])
        sc = curve(g, "p-xscale", 3)
        if sc:
            e["scale0"] = sc
        rgba = get(g, "p-rgba")
        if isinstance(rgba, str) and "/" in rgba:
            e["particleColorTexture"] = rgba
        base = nums(g, "p-xrgba")
        col = curve(g, "p-xrgba", 4)
        if col:
            if base and len(base) >= 4:
                col["dynamics"]["values"] = [[a * b for a, b in zip(v, base)] for v in col["dynamics"]["values"]]
            e["color"] = col
        elif base and len(base) >= 4:
            e["birthColor"] = {"constantValue": base[:4]}
        for k_src, k_dst in (("p-vel", "birthVelocity"), ("p-accel", "birthAcceleration"), ("p-drag", "birthDrag"),
                             ("p-orbitvel", "birthOrbitalVelocity"), ("p-quadrot", "birthRotation0"),
                             ("p-rotvel", "birthRotationalVelocity0")):
            v = value(g, k_src, 3)
            if v and nums(g, k_src) is not None:
                e[k_dst] = v
        td = nums(g, "p-texdiv")
        if td and len(td) >= 2:
            e["texDiv"] = td[:2]
        nf = nums(g, "p-numframes")
        if nf:
            e["numFrames"] = {"constantValue": nf[0]}
        if (nums(g, "p-randomstartframe") or [0])[0]:
            e["isRandomStartFrame"] = True
        b = nums(g, "p-bindtoemitter")
        if b:
            e["bindWeight"] = {"constantValue": b[0]}
        ps = nums(g, "pass")
        if ps:
            e["pass"] = int(ps[0])
        ems.append(e)
    sysobj = {"particleName": os.path.basename(tpath).rsplit(".", 1)[0], "complexEmitterDefinitionData": ems}
    _n, sysd = system(w, sysobj, {"resolve": lambda k: None})
    return sysd


# ===================================================================== map environment (--map)
MAP_BIN = "data/maps/mapgeometry/map12/base.materials.bin"
MAP_EXTRA_PATTERNS = [r"^HA_AP_(Order|Chaos)_Turret_Shatter", r"^SRU_(Order|Chaos)_Turret_BA_Cas_Champ_0\d$"]
PLACEMENT_CLS = 0x592ef6c3   # map particle placement: name, transform (0xe1ad931b), system link (0x491e0a9c)


def extract_map():
    """Howling Abyss ambient particles: every VfxSystemDefinitionData in the map materials bin goes to
    data/vfx/map12.json; every particle placement (snow, braziers, wind, sparkles, gem glows, god rays...)
    goes to data/map/map12_particles.json as {name, system, xform (16 floats, League space), group}."""
    w = wad(f"{GAME}/Maps/Shipping/Map12.wad.client")
    bf = BinFile(w.read(MAP_BIN))
    systems = {}
    by_key = {}
    for k, v in bf.entries.items():
        if v.cls != 0x45cd899f:
            continue
        name, sysd = system(w, to_py(v, TABLE))
        if sysd is not None:
            systems[name] = sysd
            by_key[k] = name
    placements = []

    def walk(o):
        if hasattr(o, "cls") and hasattr(o, "fields"):
            if o.cls == PLACEMENT_CLS:
                f = o.fields
                link = f.get(0x491e0a9c)
                xf = f.get(0xe1ad931b)
                sysname = by_key.get(int(link)) if link is not None else None
                if sysname and isinstance(xf, tuple) and len(xf) == 16:
                    placements.append({"name": f.get(fnv1a("name"), ""), "system": sysname,
                                       "xform": [round(x, 4) for x in xf],
                                       "group": f.get(0xd0e71bc7, "")})
            for v in o.fields.values():
                walk(v)
        elif isinstance(o, dict):
            for v in o.values():
                walk(v)
        elif isinstance(o, (list, tuple)):
            for v in o:
                walk(v)
    for k, v in bf.entries.items():
        walk(v)
    # structure damage / destruction systems used by the map's turrets (animation-graph particle events)
    import re
    pats = [re.compile(x) for x in MAP_EXTRA_PATTERNS]
    es = w.entries.values() if isinstance(w.entries, dict) else w.entries
    for e in es:
        if e.size > 30_000_000:
            continue
        try:
            d = w.read_entry(e)
        except Exception:
            continue
        if d[:4] not in (b"PROP", b"PTCH"):
            continue
        try:
            bf2 = BinFile(d)
        except Exception:
            continue
        for k, v in bf2.entries.items():
            if v.cls != 0x45cd899f:
                continue
            nm = None
            for fk, fv in v.fields.items():
                if TABLE.get(fk) == "particleName":
                    nm = fv
            if not nm or nm in systems or not any(p.search(nm) for p in pats):
                continue
            name, sysd = system(w, to_py(v, TABLE))
            if sysd is not None:
                systems[name] = sysd
    json.dump(systems, open(os.path.join(ROOT, "data", "vfx", "map12.json"), "w", encoding="utf-8"),
              separators=(",", ":"))
    json.dump(placements, open(os.path.join(ROOT, "data", "map", "map12_particles.json"), "w", encoding="utf-8"),
              indent=0)
    print(f"map12: {len(systems)} systems, {len(placements)} placements")
    print("   ", sorted(systems))


if __name__ == "__main__":
    args = sys.argv[1:]
    if args == ["--shared"]:
        extract_shared()
    elif args == ["--map"]:
        extract_map()
    else:
        for a in (args or ROSTER):
            extract_champion(a)
