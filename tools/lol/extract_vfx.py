"""Extract League particle systems (VfxSystemDefinitionData) for the game's champions.

For each champion (base skin) this writes:
  data/vfx/<alias>.json             {system name: {"emitters": [...], "dur": seconds}}
  assets/vfx/<lowercase asset path>.png / .obj   textures and particle meshes

Emitter values are converted to the game's conventions: meters (League units * 0.01), Godot axes (x, y, -z),
colors 0..1, curves as {"t": [...], "v": [...]}. Random ranges come from League probability tables.

Usage: python tools/lol/extract_vfx.py [Alias ...]      (default: whole roster)
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
          "particleUVScrollRate", "birthUVScrollRate", "uvScale", "particleUVRotateRate"]:
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
    if vtype == 1:
        p += nv * 4
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


def export_mesh(w, path):
    if not path or not isinstance(path, str):
        return None
    rel = "assets/vfx/" + path.lower().replace("\\", "/").rsplit(".", 1)[0] + ".obj"
    out = os.path.join(ROOT, rel)
    if not os.path.exists(out):
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
        os.makedirs(os.path.dirname(out), exist_ok=True)
        with open(out, "w") as f:
            for x, y, z in verts:
                f.write(f"v {x * U:.5f} {y * U:.5f} {-z * U:.5f}\n")
            n = 1
            for (i0, i1, i2), u, v in faces:
                # one vt per corner; Godot's OBJ importer flips V (OBJ is bottom-left origin)
                for k in range(3):
                    f.write(f"vt {u[k]:.5f} {1.0 - v[k]:.5f}\n")
                # z flip mirrors the mesh -> swap winding
                f.write(f"f {i0 + 1}/{n} {i2 + 1}/{n + 2} {i1 + 1}/{n + 1}\n")
                n += 3
    return "res://" + rel


# ===================================================================== emitters
PRIMS = {"VfxPrimitiveArbitraryQuad": "aquad", "VfxPrimitiveMesh": "mesh", "VfxPrimitiveCameraTrail": "ctrail",
         "VfxPrimitiveArbitraryTrail": "atrail", "VfxPrimitiveAttachedMesh": "amesh", "VfxPrimitiveRay": "ray",
         "VfxPrimitiveBeam": "beam", "VfxPrimitivePlanarProjection": "proj", "VfxPrimitiveCameraUnitQuad": "quad",
         "VfxPrimitiveCameraSegmentBeam": "beam"}


def emitter(w, e):
    o = {"name": e.get("emitterName", "")}
    prim = e.get("primitive")
    pcls = prim.get("__class") if isinstance(prim, dict) else None
    o["prim"] = PRIMS.get(pcls, "quad")
    if o["prim"] == "mesh":
        m = prim.get("mMesh") or {}
        mesh = export_mesh(w, m.get("mSimpleMeshName") or m.get("mMeshName"))
        if mesh is None:
            return None
        o["mesh"] = mesh
    if o["prim"] in ("ctrail", "atrail"):
        t = prim.get("mTrail") or {}
        o["trail"] = {"cutoff": t.get("mCutoff", 0.0) * U if t.get("mCutoff") else 0.0,
                      "tiling": t.get("mBirthTilingSize", [0, 0]), "mode": t.get("mMode", 0)}
    tex = export_tex(w, e.get("texture"))
    if tex is None and o["prim"] not in ("amesh",):
        return None
    o["tex"] = tex
    o["blend"] = e.get("blendMode", 0)
    o["single"] = bool(e.get("isSingleParticle", False))
    o["rate"] = float(val(e.get("rate"), 1.0) or 0.0)
    o["life"] = float(e.get("lifetime", -1.0)) if e.get("lifetime") is not None else -1.0
    o["delay"] = float(e.get("timeBeforeFirstEmission", 0.0) or 0.0)
    pl = float(val(e.get("particleLifetime"), 1.0) or 1.0)
    rm = rand_mult(e.get("particleLifetime"))
    o["plife"] = [pl * rm[0][0], pl * rm[1][0]] if rm else [pl, pl]
    o["linger"] = float(e.get("particleLinger", 0.0) or 0.0)
    o["pos"] = gvm(val(e.get("emitterPosition"), [0, 0, 0]))
    bw = val(e.get("bindWeight"), 0.0)
    o["local"] = bool(e.get("isLocalOrientation", False)) or (bw is not None and bw >= 0.5)
    o["ground"] = bool(e.get("isGroundLayer", False))
    o["dir"] = bool(e.get("isDirectionOriented", False))
    o["uniform"] = bool(e.get("isUniformScale", False))
    o["pass"] = int(e.get("pass", 0) or 0)
    o["alpha_ref"] = int(e.get("alphaRef", 0) or 0)
    # color
    bc = val(e.get("birthColor"), [1, 1, 1, 1])
    o["bcolor"] = bc if isinstance(bc, list) and len(bc) == 4 else [1, 1, 1, 1]
    o["bcolor_rand"] = rand_mult(e.get("birthColor"))
    o["color"] = curve(e.get("color"))
    if o["color"] is None and isinstance(e.get("color"), dict) and e["color"].get("constantValue"):
        o["bcolor"] = [a * b for a, b in zip(o["bcolor"], e["color"]["constantValue"])]
    o["ctex"] = export_tex(w, e.get("particleColorTexture"))
    o["ctype"] = [e.get("colorLookUpTypeX", 0), e.get("colorLookUpTypeY", 0)]
    # scale
    bs = val(e.get("birthScale0"), [1, 1, 1])
    if not isinstance(bs, list):
        bs = [bs, bs, bs]
    o["bscale"] = bs
    o["bscale_rand"] = rand_mult(e.get("birthScale0"))
    o["scale"] = curve(e.get("scale0"))
    if o["scale"] is None:
        s0 = val(e.get("scale0"))
        if isinstance(s0, list) and any(abs(x - 1) > 1e-4 for x in s0):
            o["bscale"] = [a * b for a, b in zip(bs, s0)]
    # rotation (degrees)
    o["brot"] = val(e.get("birthRotation0"), [0, 0, 0])
    o["brot_rand"] = rand_mult(e.get("birthRotation0"))
    o["rotvel"] = val(e.get("birthRotationalVelocity0"), [0, 0, 0])
    o["rotvel_rand"] = rand_mult(e.get("birthRotationalVelocity0"))
    o["rot"] = curve(e.get("rotation0"))
    # motion
    o["bvel"] = gvm(val(e.get("birthVelocity"), [0, 0, 0]))
    o["bvel_rand"] = rand_mult(e.get("birthVelocity"))
    o["drag"] = val(e.get("birthDrag"), [0, 0, 0])
    acc = val(e.get("birthAcceleration"), [0, 0, 0]) or [0, 0, 0]
    wacc = val(e.get("worldAcceleration"), [0, 0, 0]) or [0, 0, 0]
    o["accel"] = gvm([a + b for a, b in zip(acc, wacc)]) if isinstance(acc, list) and isinstance(wacc, list) else [0, 0, 0]
    # emission shape
    sh = e.get("shape")
    shape = None
    if isinstance(sh, dict):
        c = sh.get("__class", "")
        if c == "VfxShapeSphere":
            shape = {"type": "sphere", "radius": float(sh.get("radius", 0.0)) * U}
        elif c == "VfxShapeBox":
            shape = {"type": "box", "size": [abs(x) * U for x in (sh.get("boxSize") or [0, 0, 0])]}
        elif c == "VfxShapeCylinder":
            shape = {"type": "cyl", "radius": float(sh.get("radius", 0.0)) * U, "height": float(sh.get("height", 0.0)) * U}
        else:
            off = sh.get("emitOffset")
            if isinstance(off, dict):
                off = val(off)
            if isinstance(off, list):
                shape = {"type": "offset", "offset": gvm(off)}
    o["shape"] = shape
    # flipbook / uv
    td = e.get("texDiv")
    o["texdiv"] = [int(td[0]), int(td[1])] if isinstance(td, list) and len(td) == 2 else [1, 1]
    o["frames"] = int(val(e.get("numFrames"), 0) or 0)
    o["fps"] = float(val(e.get("frameRate"), 0) or val(e.get("birthFrameRate"), 0) or 0)
    o["start_frame"] = int(val(e.get("startFrame"), 0) or 0)
    o["rand_frame"] = bool(e.get("isRandomStartFrame", False))
    us = val(e.get("particleUVScrollRate"), None) or val(e.get("birthUVScrollRate"), None)
    o["uvscroll"] = us if isinstance(us, list) else None
    o["disable_cull"] = bool(e.get("disableBackfaceCull", False))
    life_max = o["plife"][1] if o["plife"][1] > 0 else 1.0
    # uv transforms
    o["uvscale"] = val(e.get("uvScale"), None)
    o["uvrate"] = val(e.get("birthUVScrollRate"), None)
    o["uvint"] = integrate(e.get("particleUVScrollRate"), life_max)
    uo = val(e.get("birthUVOffset"), None)
    ur = rand_mult(e.get("birthUVOffset"))
    if isinstance(uo, list) and len(uo) == 2:
        if ur:
            o["uvoff"] = [[uo[0] * ur[0][0], uo[1] * ur[0][1]], [uo[0] * ur[1][0], uo[1] * ur[1][1]]]
        else:
            o["uvoff"] = [uo, uo]
    # multiply texture layer
    tm = e.get("texturemult")
    if isinstance(tm, dict):
        o["tex2"] = export_tex(w, tm.get("texturemult"))
        o["uv2scale"] = val(tm.get("uvScaleMult"), None)
        o["uv2rate"] = val(tm.get("birthUvScrollRateMult"), None)
        o["uv2int"] = integrate(tm.get("22c3cf3e"), life_max)
    # erosion (dissolve)
    er = e.get("alphaErosionDefinition")
    if isinstance(er, dict) and er.get("erosionMapName"):
        o["ero_tex"] = export_tex(w, er.get("erosionMapName"))
        drive = er.get("erosionDrive")
        o["ero_curve"] = sample_curve(drive, 16)
        ch = val(er.get("erosionMapChannelMixer"), [1, 0, 0, 0])
        o["ero_ch"] = ch if isinstance(ch, list) and len(ch) == 4 else [1, 0, 0, 0]
        o["ero_feather"] = float(er.get("erosionFeatherIn", 0.1) or 0.1)
    o["soft"] = isinstance(e.get("softParticle"), dict) or isinstance(e.get("softParticleParams"), dict)
    if isinstance(e.get("distortionDefinition"), dict):
        o["distort"] = True
    return o


def system(w, sysobj):
    name = sysobj.get("particleName")
    if not name:
        return None, None
    ems = []
    for key in ("complexEmitterDefinitionData", "simpleEmitterDefinitionData"):
        for e in sysobj.get(key) or []:
            if isinstance(e, dict):
                try:
                    r = emitter(w, e)
                except Exception as ex:
                    print("   emitter fail", name, e.get("emitterName"), ex)
                    r = None
                if r is not None:
                    ems.append(r)
    if not ems:
        return name, None
    dur = 0.0
    for e in ems:
        life = e["life"] if e["life"] >= 0 else 2.0
        dur = max(dur, e["delay"] + life + e["plife"][1] + e["linger"])
    return name, {"emitters": ems, "dur": round(dur, 3), "loop": any(e["life"] < 0 for e in ems)}


def extract_champion(alias):
    low = alias.lower()
    w = wad(f"{GAME}/Champions/{alias}.wad.client")
    sk = BinFile(w.read(f"data/characters/{low}/skins/skin0.bin"))
    bins = [f"data/characters/{low}/skins/skin0.bin"] + [l.lower() for l in sk.links]
    out = {}
    for b in bins:
        d = w.read(b)
        if d is None:
            continue
        try:
            bf = BinFile(d)
        except Exception:
            continue
        for k, v in bf.entries.items():
            if v.cls != 0x45cd899f:
                continue
            name, s = system(w, to_py(v, TABLE))
            if s is not None and name not in out:
                out[name] = s
    path = os.path.join(ROOT, "data", "vfx", f"{low}.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(out, open(path, "w", encoding="utf-8"), separators=(",", ":"))
    print(f"{alias}: {len(out)} systems")
    return out


SHARED_PATTERNS = [
    r"^Cursor_Moveto$", r"^Summoner_Snowball_", r"^Global_SS_Ignite", r"^Global_Haste$", r"^Jade_Summoner_Cleanse$",
    r"^Monster_Heal_Impact$", r"^Item_Redemption_Hit_Heal$", r"^Global_Slow$", r"^ARAMHealthPickup_",
    r"^Turret_Skin24_", r"^HA_(Order|Chaos)_(Inhibitor|Nexus)_", r"^SRU_(Order|Chaos)Minion(Ranged|Siege)_Base_",
    r"^ARAM_Hexgate_Base_(OpenLoop|PortalGroundLoop)", r"^LOC_(Stun|Silence|Taunt)$",
]


def extract_shared():
    import re
    out = {}
    pats = [re.compile(p) for p in SHARED_PATTERNS]
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
                name, sysd = system(w, to_py(v, TABLE))
                if sysd is not None:
                    out[name] = sysd
    path = os.path.join(ROOT, "data", "vfx", "shared.json")
    json.dump(out, open(path, "w", encoding="utf-8"), separators=(",", ":"))
    print(f"shared: {len(out)} systems")
    print("   ", sorted(out))


if __name__ == "__main__":
    args = sys.argv[1:]
    if args == ["--shared"]:
        extract_shared()
    else:
        for a in (args or ROSTER):
            extract_champion(a)
