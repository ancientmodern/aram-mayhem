"""Export a League character skin (mesh, skeleton, animations, textures) to a Godot-ready .glb.

Usage:
  python export_character.py Ahri 0 [out.glb]
  python export_character.py --roster            # all roster champions, base skins
  python export_character.py --map               # minions / turrets / structures from Map12

Coordinate conversion (League left-handed -> Godot): (x, y, z) -> (x, y, -z) * 0.01,
quaternion (x, y, z, w) -> (-x, -y, z, w), triangle winding swapped.
"""
import io
import json
import math
import os
import sys
import time

import numpy as np
import xxhash

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "ref"))
from lolwad import Wad  # noqa: E402
from lolbin import read_bin, fnv1a32, BinStruct  # noqa: E402
from lolmesh import read_skn, read_skl, elf_hash  # noqa: E402
from lolanim import read_anm, CompressedAnm  # noqa: E402
from lolfmt_tex import any_texture_to_image  # noqa: E402
from gltf import Gltf, FLOAT, USHORT, UBYTE, ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER  # noqa: E402

GAME = "D:/Riot Games/League of Legends/Game/DATA/FINAL"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
S = 0.01
FPS = 30.0

ROSTER = ["Ahri", "Garen", "Darius", "Yasuo", "MasterYi", "Malphite", "Leona", "Lux", "Jinx", "Ezreal",
          "MissFortune", "Annie", "Sona", "Veigar"]


def xxh(path):
    return xxhash.xxh64_intdigest(path.lower().encode("utf-8"), 0)


# ------------------------------------------------------------------ clip-name vocabulary
def vocabulary(char: str):
    c = char.lower()
    base = ["idle", "idle1", "idle2", "idle3", "idle4", "idle5", "idle_base", "idle1_base", "idle2_base", "idle3_base",
            "idle4_base", "idle01", "idle02", "idle_01", "idle_02", "idle_in", "idle_var1", "idle_var2", "idle_var3",
            "idle_var4", "idle1_loop", "idle_loop", "idle1a", "idle1b", "idle_a", "idle_b", "idle_variant1",
            "idle_variant2", "idle_variant3", "idle_leadin", "idle_lead_in", "idle_activate", "idle1_in", "idle3_base",
            "idlein", "idle_spawn", "idle_combat", "idle_1", "idle_2", "idle_3", "idle1_anim",
            "run", "run_base", "run1", "run2", "run_01", "run01", "run_fast", "run_haste", "run_homeguard", "run_in",
            "run_out", "run_var1", "run_var2", "run_slow", "run_spell4", "run_ult", "run_r", "walk", "walk_base",
            "run_fast_base", "run_haste_base", "run1_base", "run_loop", "run_a", "run_b", "run_1", "run_2", "haste",
            "run_homeguard_base", "run_injured", "run_lowhealth", "run_combat",
            "attack", "attack_base", "attack1", "attack2", "attack3", "attack4", "attack5", "attack_1", "attack_2",
            "attack_3", "attack01", "attack02", "attack03", "attack1_base", "attack2_base", "attack3_base",
            "attack4_base", "attack1a", "attack2a", "attack_a", "attack_b", "attack_c", "attack1_toidle",
            "attack2_toidle", "attack1_torun", "attack2_torun", "attack3_toidle", "attack3_torun",
            "crit", "crit_base", "crit1", "crit2", "critical", "attack_crit", "crit_toidle", "crit_torun",
            "death", "death_base", "death1", "death2", "death_in", "death_loop", "death_01", "death_idle",
            "dance", "dance_base", "dance_loop", "dance_in", "dance_intro", "dance_base_loop", "dance_loop_base",
            "dance1", "dance_01", "dance_start", "dance_into",
            "taunt", "taunt_base", "taunt1", "taunt_loop", "taunt_in", "laugh", "laugh_base", "laugh_loop",
            "laugh_in", "joke", "joke_base", "joke_in", "joke_loop", "joke_intro",
            "recall", "recall_base", "recall_winddown", "recall_leadout", "recall_loop", "recall_in", "recall_out",
            "respawn", "spawn", "channel", "channel_loop", "channel_wndup", "channel_windup", "channel_base",
            "stunned", "stun", "stunned_base", "knockup", "knockup_loop", "airborne", "airborne_base", "taunted",
            "homeguard", "idle_toshop", "turn", "turn_left", "turn_right", "emote", "flinch", "hit", "pain"]
    for sp in ("spell1", "spell2", "spell3", "spell4", "spell5", "spell6"):
        for suf in ("", "_base", "a", "b", "c", "d", "_a", "_b", "_c", "_in", "_out", "_loop", "_cast", "_channel",
                    "_windup", "_winddown", "_wndup", "_toidle", "_torun", "_to_idle", "_to_run", "_idle", "_run",
                    "_end", "_start", "_1", "_2", "_3", "_4", "_fire", "_hit", "_dash", "_recast", "_upper", "_lower",
                    "_left", "_right", "_north", "_south", "_east", "_west", "_attack", "_attack1", "_attack2",
                    "_crit", "_land", "_jump", "_leap", "_charge", "_release", "_pull", "_throw", "_catch", "_spin",
                    "_spin_loop", "_spin_end", "_idle1", "_run_base", "_base_loop", "_toidle_base", "a_base", "b_base",
                    "_01", "_02", "_03", "_short", "_long", "_mid", "_full", "_into", "_outro", "_intro", "_activate",
                    "_deactivate", "_on", "_off", "_off_loop", "_on_loop", "1", "2", "3", "_air", "_ground", "_rush"):
            base.append(sp + suf)
    # ultimate / transform variants
    for pre in ("ult", "r", "spell4", "transform", "rocket", "minigun", "weapon"):
        for suf in ("_idle", "_run", "_attack1", "_attack2", "_crit", "_death", "_idle1", "_run_base", "_in", "_out",
                    "_loop", "_toidle", "_torun", "_end", "_start"):
            base.append(pre + suf)
    prefixes = ["", c + "_", c + "_base_", c + "base_", c + "_2013_", c + "_2014_", c + "_2015_", c + "_2016_",
                c + "_2017_", c + "_2018_", c + "_2019_", c + "_2020_", c + "_2021_", c + "_skin0_", c + "_old_",
                c + "_v2_", c + "_new_", "base_"]
    names = set()
    for p in prefixes:
        for b in base:
            names.add(p + b)
    return names


# ------------------------------------------------------------------ helpers
def conv_t(t):
    return (t[0] * S, t[1] * S, -t[2] * S)


def conv_q(q):
    return (-q[0], -q[1], q[2], q[3])


def quat_mat(q):
    x, y, z, w = q
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]], np.float64)


def trs_mat(t, r, s):
    m = np.eye(4)
    m[:3, :3] = quat_mat(r) * np.array(s)[None, :]
    m[:3, 3] = t
    return m


class BinSet:
    """Skin bin + its dependency bins (resolved within the WADs)."""

    def __init__(self, wads, first_path):
        self.wads = wads
        self.objects = {}
        self.loaded = set()
        self.load(first_path)

    def read(self, path):
        for w in self.wads:
            d = w.get(path)
            if d is not None:
                return d
        return None

    def load(self, path, depth=0):
        p = path.lower()
        if p in self.loaded or depth > 3:
            return
        self.loaded.add(p)
        d = self.read(p)
        if d is None:
            return
        bf = read_bin(d)
        for k, o in bf.objects.items():
            self.objects.setdefault(k, o)
        for dep in bf.dependencies:
            dl = dep.lower()
            if "/characters/" in dl and ("/animations/" in dl or "/skins/" in dl or dl.endswith(".bin")):
                self.load(dl, depth + 1)

    def get(self, path_or_hash):
        h = path_or_hash if isinstance(path_or_hash, int) else fnv1a32(path_or_hash)
        return self.objects.get(h)


def find_file(wads, key):
    for w in wads:
        e = w.entries.get(key)
        if e is not None:
            return w.read_entry(e)
    return None


# ------------------------------------------------------------------ export
def export(char: str, skin: int, out_path: str, wads, max_tex=2048, keep_unnamed=False, verbose=True,
           skip_transitions=True):
    t0 = time.time()
    cl = char.lower()
    skin_bin_path = f"data/characters/{cl}/skins/skin{skin}.bin"
    bins = BinSet(wads, skin_bin_path)
    skin_obj = bins.get(f"Characters/{char}/Skins/Skin{skin}")
    if skin_obj is None:
        for o in bins.objects.values():
            if o.get("skinMeshProperties") is not None:
                skin_obj = o
                break
    if skin_obj is None:
        raise RuntimeError(f"no skin object for {char} skin {skin}")
    smp = skin_obj.get("skinMeshProperties")
    skl_path = smp.get("skeleton")
    skn_path = smp.get("simpleSkin")
    skn = read_skn(bins.read(skn_path.lower()))
    skl = read_skl(bins.read(skl_path.lower()))
    skin_scale = smp.get("skinScale") or 1.0
    hidden = set((smp.get("initialSubmeshToHide") or "").lower().split())

    # ---------------- materials / textures
    def resolve_material_texture(mat_link):
        mo = bins.get(mat_link) if mat_link is not None else None
        if mo is None:
            return None
        best = None
        for s in mo.get("samplerValues") or []:
            tn = (s.get("textureName") or "")
            tp = s.get("texturePath")
            if tp is None:
                continue
            if "diffuse" in tn.lower() and best is None:
                best = tp
        if best is None:
            for s in mo.get("samplerValues") or []:
                if s.get("texturePath") is not None:
                    best = s.get("texturePath")
                    break
        return best

    def tex_key(v):
        if v is None:
            return None
        if isinstance(v, str):
            return xxh(v.lower())
        return v

    default_tex = tex_key(smp.get("texture"))
    if default_tex is None and smp.get("material") is not None:
        default_tex = tex_key(resolve_material_texture(smp.get("material")))
    overrides = {}
    for ov in smp.get("materialOverride") or []:
        sub = (ov.get("submesh") or "").lower()
        tk = tex_key(ov.get("texture"))
        if tk is None and ov.get("material") is not None:
            tk = tex_key(resolve_material_texture(ov.get("material")))
        if sub and tk is not None:
            overrides[sub] = tk

    gl = Gltf()
    image_cache = {}

    def material_for(range_name):
        tk = overrides.get(range_name.lower(), default_tex)
        if tk in image_cache:
            return image_cache[tk]
        mat = {"name": range_name, "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 1.0}}
        alpha = False
        if tk is not None:
            data = find_file(wads, tk)
            if data is not None:
                img = any_texture_to_image(data)
                if max(img.size) > max_tex:
                    img.thumbnail((max_tex, max_tex))
                if img.mode == "RGBA":
                    a = np.asarray(img)[:, :, 3]
                    alpha = (a < 200).mean() > 0.02
                buf = io.BytesIO()
                img.save(buf, "PNG", optimize=False)
                ii = gl.image_png(buf.getvalue(), range_name)
                ti = gl.texture(ii)
                mat["pbrMetallicRoughness"]["baseColorTexture"] = {"index": ti}
        if alpha:
            mat["alphaMode"] = "MASK"
            mat["alphaCutoff"] = 0.3
        mi = gl.add("materials", mat)
        image_cache[tk] = mi
        return mi

    # ---------------- skeleton nodes
    joints = skl.joints
    nj = len(joints)
    joint_nodes = []
    for j in joints:
        t = conv_t(j.local_t)
        r = conv_q(j.local_r)
        n = {"name": j.name, "translation": list(t), "rotation": list(r), "scale": list(j.local_s)}
        joint_nodes.append(gl.add("nodes", n))
    for j in joints:
        if j.parent >= 0:
            gl.j["nodes"][joint_nodes[j.parent]].setdefault("children", []).append(joint_nodes[j.id])
    roots = [joint_nodes[j.id] for j in joints if j.parent < 0]
    ibm = np.zeros((nj, 4, 4), np.float32)
    for j in joints:
        m = trs_mat(conv_t(j.ibind_t), conv_q(j.ibind_r), j.ibind_s)
        ibm[j.id] = m.T  # column-major
    ibm_acc = gl.accessor(ibm.reshape(nj, 16), FLOAT, "MAT4")
    armature = gl.add("nodes", {"name": "Armature", "children": roots})
    skin_index = gl.add("skins", {"joints": joint_nodes, "inverseBindMatrices": ibm_acc, "skeleton": armature,
                                  "name": f"{char}_skin"})

    # ---------------- meshes (one node per submesh range)
    P = np.array(skn.positions, np.float32) * S
    P[:, 2] *= -1
    N = np.array(skn.normals, np.float32)
    N[:, 2] *= -1
    nl = np.linalg.norm(N, axis=1, keepdims=True)
    N = N / np.maximum(nl, 1e-6)
    UV = np.array(skn.uvs, np.float32)
    infl = np.array(skl.influences if skl.influences else list(range(nj)), np.int32)
    JB = np.array(skn.joints, np.int32)
    J = infl[np.clip(JB, 0, len(infl) - 1)]
    W = np.array(skn.weights, np.float32)
    W[W < 1e-5] = 0.0
    J[W == 0.0] = 0
    ws = W.sum(axis=1, keepdims=True)
    W = W / np.maximum(ws, 1e-6)
    I = np.array(skn.indices, np.uint32).reshape(-1, 3)
    mesh_nodes = []
    hidden_names = []
    for rg in skn.ranges:
        vs, vc = rg.start_vertex, rg.vertex_count
        tri = I[rg.start_index // 3: (rg.start_index + rg.index_count) // 3]
        if len(tri) == 0:
            continue
        tri = tri[:, [0, 2, 1]] - vs
        prim = {
            "attributes": {
                "POSITION": gl.accessor(P[vs:vs + vc], FLOAT, "VEC3", ARRAY_BUFFER, minmax=True),
                "NORMAL": gl.accessor(N[vs:vs + vc], FLOAT, "VEC3", ARRAY_BUFFER),
                "TEXCOORD_0": gl.accessor(UV[vs:vs + vc], FLOAT, "VEC2", ARRAY_BUFFER),
                "JOINTS_0": gl.accessor(J[vs:vs + vc].astype(np.uint16), USHORT, "VEC4", ARRAY_BUFFER),
                "WEIGHTS_0": gl.accessor(W[vs:vs + vc], FLOAT, "VEC4", ARRAY_BUFFER),
            },
            "indices": gl.accessor(tri.reshape(-1).astype(np.uint32), 5125, "SCALAR", ELEMENT_ARRAY_BUFFER),
            "material": material_for(rg.material),
        }
        mesh_i = gl.add("meshes", {"name": rg.material, "primitives": [prim]})
        is_hidden = rg.material.lower() in hidden
        nname = ("HIDDEN__" if is_hidden else "") + rg.material
        if is_hidden:
            hidden_names.append(rg.material)
        mesh_nodes.append(gl.add("nodes", {"name": nname, "mesh": mesh_i, "skin": skin_index}))
    root_children = [armature] + mesh_nodes
    root = gl.add("nodes", {"name": char, "children": root_children,
                            "extras": {"skin_scale": skin_scale, "hidden": hidden_names}})
    gl.j["scenes"][0]["nodes"] = [root]

    # ---------------- animations
    anim_report = {"named": [], "unnamed": 0}
    aliases = {}
    agl = skin_obj.get("skinAnimationProperties")
    graph = bins.get(agl.get("animationGraphData")) if agl is not None else None
    hash_to_joint = {elf_hash(j.name): j.id for j in joints}
    if graph is not None:
        clipmap = graph.get("mClipDataMap") or {}
        vocab = vocabulary(char)
        folder = "base" if skin == 0 else f"skin{skin:02d}"
        key_names = {}
        for v in vocab:
            key_names[fnv1a32(v)] = v
        path_names = {}
        for v in vocab:
            for fol in {folder, "base", f"skin{skin}"}:
                path_names[xxh(f"assets/characters/{cl}/skins/{fol}/animations/{v}.anm")] = v
        files = {}
        # Resolve standard clip names through the graph (sequencers/selectors -> atomic clips)
        def clip_file(co):
            ard = co.get("mAnimationResourceData") if co is not None else None
            if ard is None:
                return None
            fk2 = ard.get("mAnimationFilePath")
            if isinstance(fk2, str):
                fk2 = xxh(fk2.lower())
            return fk2

        def refs(v, acc):
            if isinstance(v, BinStruct):
                for _k, (_t, x) in v.fields.items():
                    refs(x, acc)
            elif isinstance(v, list):
                for x in v:
                    refs(x, acc)
            elif isinstance(v, dict):
                for x in v.values():
                    refs(x, acc)
            elif isinstance(v, int) and v in clipmap and v not in acc:
                acc.append(v)
            return acc

        graph_names = {}
        aliases = {}

        def assign(ck, nm, depth=0):
            co = clipmap.get(ck)
            if co is None or depth > 4:
                return
            fk2 = clip_file(co)
            if fk2 is not None:
                if fk2 in graph_names and graph_names[fk2] != nm:
                    aliases.setdefault(nm, graph_names[fk2])
                graph_names.setdefault(fk2, nm)
                return
            rs = refs(co, [])
            if not rs:
                return
            seq = co.get("mClipNameList")
            if seq:
                # sequencer: the last distinct clip is the loop, earlier ones are intros
                last = seq[-1]
                assign(last, nm, depth + 1)
                for i, c2 in enumerate(dict.fromkeys(seq)):
                    if c2 != last:
                        assign(c2, nm + ("_in" if i == 0 else f"_seq{i}"), depth + 1)
            else:
                for i, c2 in enumerate(rs):
                    assign(c2, nm if i == 0 else f"{nm}_var{i + 1}", depth + 1)

        std_names = ["Idle1", "Idle2", "Idle3", "Idle4", "Idle_Base", "Idle1_Base", "Run", "Run_Base", "Run_Fast",
                     "Run_Haste", "Attack1", "Attack2", "Attack3", "Attack4", "Crit", "Crit2", "Spell1", "Spell2",
                     "Spell3", "Spell4", "Spell1A", "Spell1B", "Spell1C", "Death", "Dance", "Taunt", "Laugh", "Joke",
                     "Recall", "Channel", "Respawn", "Stunned", "KnockUp", "Spell4_Idle", "Spell4_Run", "Spell2_Idle",
                     "Spell2_Run", "Spell3_Idle", "Spell3_Run", "Spell1_Idle", "Spell1_Run", "Idle_Spell4",
                     "Run_Spell4", "Attack_Spell4", "Spell1_Dash", "Homeguard", "Run_Homeguard"]
        for sn in std_names:
            ck0 = fnv1a32(sn)
            if ck0 in clipmap:
                assign(ck0, sn.lower())
        for ck, co in clipmap.items():
            if co is None:
                continue
            ard = co.get("mAnimationResourceData")
            if ard is None:
                continue
            fk = ard.get("mAnimationFilePath")
            if fk is None:
                continue
            if isinstance(fk, str):
                fk = xxh(fk.lower())
            nm = graph_names.get(fk) or path_names.get(fk)
            if nm is None:
                nm = key_names.get(ck)
            if fk in files:
                if nm and not files[fk]:
                    files[fk] = nm
                continue
            files[fk] = nm
        used_names = set()
        for fk, nm in files.items():
            if not nm:
                anim_report["unnamed"] += 1
                if not keep_unnamed:
                    continue
                nm = f"clip_{fk & 0xffffffff:08x}"
            # strip champion prefixes for clean logical names
            if skip_transitions and any(x in nm for x in ("_toidle", "_torun", "_to_idle", "_to_run", "attack1_to",
                                                         "idle_in", "_leadin", "_lead_in")):
                continue
            short = nm
            for p in (cl + "_base_", cl + "base_", cl + "_"):
                if short.startswith(p):
                    short = short[len(p):]
                    break
            if short in used_names:
                short = nm
            used_names.add(short)
            data = find_file(wads, fk)
            if data is None:
                continue
            try:
                anm = read_anm(data)
            except Exception as ex:
                print("   anm error", nm, ex)
                continue
            add_animation(gl, short, anm, joints, joint_nodes, hash_to_joint)
            anim_report["named"].append(short)
    exported = set(anim_report["named"])
    alias_out = {}
    if graph is not None:
        for a, b in aliases.items():
            if a not in exported:
                alias_out[a] = b
    with open(os.path.splitext(out_path)[0] + ".anims.json", "w") as f:
        json.dump({"anims": sorted(exported), "aliases": alias_out, "hidden": hidden_names,
                   "skin_scale": skin_scale}, f, indent=1)
    size = gl.write_glb(out_path)
    if verbose:
        print(f"{char} skin{skin}: verts={len(P)} joints={nj} ranges={len(skn.ranges)} anims={len(anim_report['named'])} "
              f"(unnamed skipped {anim_report['unnamed']}) -> {size / 1e6:.1f}MB in {time.time() - t0:.1f}s")
        print("   anims:", " ".join(sorted(anim_report["named"])))
    return anim_report


def add_animation(gl, name, anm, joints, joint_nodes, hash_to_joint):
    duration = max(anm.duration, 1.0 / FPS)
    nframes = max(2, int(round(duration * FPS)) + 1)
    times = np.linspace(0.0, duration, nframes).astype(np.float32)
    nj = len(joints)
    R = np.zeros((nframes, nj, 4), np.float64)
    T = np.zeros((nframes, nj, 3), np.float64)
    Sc = np.ones((nframes, nj, 3), np.float64)
    has = np.zeros(nj, bool)
    if isinstance(anm, CompressedAnm):
        curves = anm.curves()
        for ji, h in enumerate(anm.joint_hashes):
            jid = hash_to_joint.get(h)
            if jid is None:
                continue
            has[jid] = True
            for typ in range(3):
                keys = curves.get((ji, typ))
                if not keys:
                    continue
                for f, t in enumerate(times):
                    ct = int(min(max(float(t), 0.0), anm.duration) / anm.duration * 65535) if anm.duration > 0 else 0
                    v = anm.sample_curve(keys, ct, typ == 0)
                    if typ == 0:
                        R[f, jid] = v
                    elif typ == 1:
                        T[f, jid] = v
                    else:
                        Sc[f, jid] = v
    else:
        src_fps = anm.fps
        for h, frames in anm.tracks.items():
            jid = hash_to_joint.get(h)
            if jid is None:
                continue
            has[jid] = True
            nf = len(frames)
            for f, t in enumerate(times):
                x = float(t) * src_fps
                i0 = int(math.floor(x))
                k = x - i0
                a = frames[min(i0, nf - 1)]
                b = frames[min(i0 + 1, nf - 1)]
                qa = np.array(a[0], np.float64)
                qb = np.array(b[0], np.float64)
                if np.dot(qa, qb) < 0:
                    qb = -qb
                q = qa * (1 - k) + qb * k
                R[f, jid] = q / max(np.linalg.norm(q), 1e-9)
                T[f, jid] = np.array(a[1]) * (1 - k) + np.array(b[1]) * k
                Sc[f, jid] = np.array(a[2]) * (1 - k) + np.array(b[2]) * k
    # bind pose for joints without tracks
    for j in joints:
        if not has[j.id]:
            R[:, j.id] = j.local_r
            T[:, j.id] = j.local_t
            Sc[:, j.id] = j.local_s
    # convert coordinates
    R[:, :, 0] *= -1
    R[:, :, 1] *= -1
    T *= S
    T[:, :, 2] *= -1
    # sign continuity
    for f in range(1, nframes):
        d = np.sum(R[f] * R[f - 1], axis=1)
        R[f][d < 0] *= -1
    t_acc = gl.accessor(times, FLOAT, "SCALAR", minmax=True)
    t1_acc = None
    samplers = []
    channels = []

    time_acc_cache = {}

    def reduce_keys(values, tol):
        # greedy linear keyframe reduction: keep a key when skipping it would exceed tol
        n = len(values)
        keep = [0]
        i = 0
        while i < n - 1:
            j = i + 2
            while j < n:
                seg = values[i:j + 1]
                k = np.linspace(0.0, 1.0, j - i + 1)[:, None]
                interp = values[i] * (1 - k) + values[j] * k
                if np.abs(interp - seg).max() > tol:
                    break
                j += 1
            keep.append(j - 1)
            i = j - 1
        if keep[-1] != n - 1:
            keep.append(n - 1)
        return keep

    def add_channel(jid, path, values, typ):
        nonlocal t1_acc
        const = np.allclose(values, values[0:1], atol=1e-5)
        if const:
            # constant and equal to the bind pose: omit (Godot falls back to the RESET pose)
            j = joints[jid]
            if path == "rotation":
                bq = np.array(conv_q(j.local_r))
                if abs(abs(float(np.dot(bq, values[0]))) - 1.0) < 1e-5:
                    return
            elif path == "translation":
                if np.allclose(values[0], conv_t(j.local_t), atol=1e-5):
                    return
            elif np.allclose(values[0], j.local_s, atol=1e-5):
                return
            if t1_acc is None:
                t1_acc = gl.accessor(np.array([0.0], np.float32), FLOAT, "SCALAR", minmax=True)
            acc = gl.accessor(values[0:1].astype(np.float32), FLOAT, typ)
            samplers.append({"input": t1_acc, "output": acc, "interpolation": "STEP"})
        else:
            tol = 0.0012 if path == "rotation" else 0.0015
            keep = reduce_keys(values, tol)
            kt = tuple(keep)
            if len(keep) == nframes:
                tin = t_acc
            else:
                tin = time_acc_cache.get(kt)
                if tin is None:
                    tin = gl.accessor(times[keep], FLOAT, "SCALAR", minmax=True)
                    time_acc_cache[kt] = tin
            acc = gl.accessor(values[keep].astype(np.float32), FLOAT, typ)
            samplers.append({"input": tin, "output": acc, "interpolation": "LINEAR"})
        channels.append({"sampler": len(samplers) - 1, "target": {"node": joint_nodes[jid], "path": path}})

    for j in joints:
        add_channel(j.id, "rotation", R[:, j.id], "VEC4")
        add_channel(j.id, "translation", T[:, j.id], "VEC3")
        add_channel(j.id, "scale", Sc[:, j.id], "VEC3")
    gl.add("animations", {"name": name, "samplers": samplers, "channels": channels})


def open_wads(char, extra=()):
    paths = []
    cpath = f"{GAME}/Champions/{char}.wad.client"
    if os.path.exists(cpath):
        paths.append(cpath)
    paths += [f"{GAME}/Maps/Shipping/Map12.wad.client", f"{GAME}/Maps/Shipping/Common.wad.client",
              f"{GAME}/Global.wad.client", f"{GAME}/DATA.wad.client"] + list(extra)
    out = []
    for p in paths:
        if os.path.exists(p):
            out.append(Wad(p))
    return out


def model_path(char, skin):
    low = char.lower()
    folder = "champions" if char in ROSTER else "units"
    name = low if skin == 0 else f"{low}_skin{skin}"
    return os.path.join(ROOT, "assets", folder, low, name + ".glb")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "--roster":
        skins = [int(x) for x in args[1:]] or [0]
        for ch in ROSTER:
            for sk in skins:
                p = model_path(ch, sk)
                os.makedirs(os.path.dirname(p), exist_ok=True)
                try:
                    export(ch, sk, p, open_wads(ch))
                except Exception as ex:
                    import traceback
                    traceback.print_exc()
                    print("!! failed", ch, sk, ex)
    elif args and args[0] == "--map":
        units = args[1:] or ["HA_OrderMinionMelee", "HA_ChaosMinionMelee", "HA_OrderMinionRanged",
                             "HA_ChaosMinionRanged", "HA_OrderMinionSiege", "HA_ChaosMinionSiege",
                             "HA_OrderMinionSuper", "HA_ChaosMinionSuper"]
        for ch in units:
            sk = 0
            if ":" in ch:
                ch, sk = ch.split(":")
                sk = int(sk)
            p = model_path(ch, sk)
            os.makedirs(os.path.dirname(p), exist_ok=True)
            try:
                export(ch, sk, p, open_wads(ch), max_tex=1024, keep_unnamed=False)
            except Exception as ex:
                import traceback
                traceback.print_exc()
                print("!! failed", ch, ex)
    else:
        ch = args[0]
        sk = int(args[1]) if len(args) > 1 else 0
        p = args[2] if len(args) > 2 else model_path(ch, sk)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        export(ch, sk, p, open_wads(ch), keep_unnamed="--all" in args)
