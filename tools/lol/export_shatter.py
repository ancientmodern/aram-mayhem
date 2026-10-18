"""Export Howling Abyss turret destruction meshes (League "Temp_MeshAnim" particle meshes) to .glb.

League turrets lose chunks at damage thresholds and collapse on death through animated-mesh particles
(HA_AP_<Team>_Turret_Shatter_01/02/03, 03_Left/Right, 03_Left/Right_Idle; see the turret animation graph
DATA/Characters/Turret/Animations/Skin28.bin). Each skeletal mesh + its clips becomes
assets/structures/<name>.glb (no textures: the game reuses the turret's own BaseState material).

Usage: python tools/lol/export_shatter.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
from export_character import (GAME, ROOT, S, Wad, read_skn, read_skl, read_anm, elf_hash, xxh, conv_t, conv_q,  # noqa
                              trs_mat, add_animation, Gltf, FLOAT, USHORT, ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER)

O = "ASSETS/Characters/Turret/Skins/Skin28/Particles/HA_AP_OrderTurretMesh_shatter_"
C = "ASSETS/Characters/Turret/Skins/Skin30/Particles/HA_AP_ChaosTurret_Shatter_"
JOBS = {
    "turret_shatter_order_1": (O + "1.skn", O + "1.skl", {"shatter": O + "1.anm"}),
    "turret_shatter_order_2": (O + "2.skn", O + "2.skl", {"shatter": O + "2.anm"}),
    "turret_shatter_order_3": (O + "3.skn", O + "3.skl", {
        "shatter": O + "3.anm", "left": O + "3_Left.anm", "right": O + "3_Right.anm",
        "left_idle": O + "3_Left_Idle.anm", "right_idle": O + "3_Right_Idle.anm"}),
    "turret_shatter_chaos_1": (C + "01.skn", C + "01.skl", {"shatter": C + "01.anm"}),
    "turret_shatter_chaos_2": (C + "02.skn", C + "02.skl", {"shatter": C + "02.anm"}),
    "turret_shatter_chaos_3n": (C + "03_Neutral.skn", C + "03_Neutral.skl", {"shatter": C + "03.anm"}),
    "turret_shatter_chaos_3": (C + "03.skn", C + "03.skl", {
        "left": C + "03_Left.anm", "right": C + "03_Right.anm",
        "left_idle": C + "03_Left_Idle.anm", "right_idle": C + "03_Right_Idle.anm"}),
}


def read(wads, path):
    for w in wads:
        d = w.get(path.lower())
        if d is not None:
            return d
    return None


def export(name, skn_path, skl_path, anims, wads):
    skn_d = read(wads, skn_path)
    skl_d = read(wads, skl_path)
    if skl_d is None:
        # some meshes share the plain skeleton name
        alt = skl_path.replace("_Neutral", "")
        skl_d = read(wads, alt)
    if skn_d is None or skl_d is None:
        print("!! missing", name, skn_d is None, skl_d is None)
        return
    skn = read_skn(skn_d)
    skl = read_skl(skl_d)
    gl = Gltf()
    joints = skl.joints
    nj = len(joints)
    joint_nodes = []
    for j in joints:
        joint_nodes.append(gl.add("nodes", {"name": j.name, "translation": list(conv_t(j.local_t)),
                                            "rotation": list(conv_q(j.local_r)), "scale": list(j.local_s)}))
    for j in joints:
        if j.parent >= 0:
            gl.j["nodes"][joint_nodes[j.parent]].setdefault("children", []).append(joint_nodes[j.id])
    roots = [joint_nodes[j.id] for j in joints if j.parent < 0]
    ibm = np.zeros((nj, 4, 4), np.float32)
    for j in joints:
        ibm[j.id] = trs_mat(conv_t(j.ibind_t), conv_q(j.ibind_r), j.ibind_s).T
    armature = gl.add("nodes", {"name": "Armature", "children": roots})
    skin_index = gl.add("skins", {"joints": joint_nodes, "skeleton": armature,
                                  "inverseBindMatrices": gl.accessor(ibm.reshape(nj, 16), FLOAT, "MAT4")})
    P = np.array(skn.positions, np.float32) * S
    P[:, 2] *= -1
    N = np.array(skn.normals, np.float32)
    N[:, 2] *= -1
    N = N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-6)
    UV = np.array(skn.uvs, np.float32)
    infl = np.array(skl.influences if skl.influences else list(range(nj)), np.int32)
    J = infl[np.clip(np.array(skn.joints, np.int32), 0, len(infl) - 1)]
    W = np.array(skn.weights, np.float32)
    W[W < 1e-5] = 0.0
    J[W == 0.0] = 0
    W = W / np.maximum(W.sum(axis=1, keepdims=True), 1e-6)
    I = np.array(skn.indices, np.uint32).reshape(-1, 3)
    mat = gl.add("materials", {"name": "BaseState", "pbrMetallicRoughness": {"metallicFactor": 0.0}})
    nodes = []
    for rg in skn.ranges:
        vs, vc = rg.start_vertex, rg.vertex_count
        tri = I[rg.start_index // 3: (rg.start_index + rg.index_count) // 3]
        if len(tri) == 0:
            continue
        tri = tri[:, [0, 2, 1]] - vs
        prim = {"attributes": {
            "POSITION": gl.accessor(P[vs:vs + vc], FLOAT, "VEC3", ARRAY_BUFFER, minmax=True),
            "NORMAL": gl.accessor(N[vs:vs + vc], FLOAT, "VEC3", ARRAY_BUFFER),
            "TEXCOORD_0": gl.accessor(UV[vs:vs + vc], FLOAT, "VEC2", ARRAY_BUFFER),
            "JOINTS_0": gl.accessor(J[vs:vs + vc].astype(np.uint16), USHORT, "VEC4", ARRAY_BUFFER),
            "WEIGHTS_0": gl.accessor(W[vs:vs + vc], FLOAT, "VEC4", ARRAY_BUFFER)},
            "indices": gl.accessor(tri.reshape(-1).astype(np.uint32), 5125, "SCALAR", ELEMENT_ARRAY_BUFFER),
            "material": mat}
        mi = gl.add("meshes", {"name": rg.material, "primitives": [prim]})
        nodes.append(gl.add("nodes", {"name": rg.material, "mesh": mi, "skin": skin_index}))
    root = gl.add("nodes", {"name": name, "children": [armature] + nodes})
    gl.j["scenes"][0]["nodes"] = [root]
    h2j = {elf_hash(j.name): j.id for j in joints}
    done = []
    for an, ap in anims.items():
        d = read(wads, ap)
        if d is None:
            print("   missing anim", ap)
            continue
        add_animation(gl, an, read_anm(d), joints, joint_nodes, h2j)
        done.append(an)
    out = os.path.join(ROOT, "assets", "structures", name + ".glb")
    os.makedirs(os.path.dirname(out), exist_ok=True)
    size = gl.write_glb(out)
    print(f"{name}: verts={len(P)} joints={nj} anims={done} {size / 1e3:.0f}KB")


if __name__ == "__main__":
    wads = [Wad(f"{GAME}/Maps/Shipping/Map12.wad.client")]
    for nm, (a, b, c) in JOBS.items():
        export(nm, a, b, c, wads)
