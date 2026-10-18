"""Extract + disassemble League's shipped DX11 shader cache (offline, data files only).

Source: DATA/FINAL/ShaderCache.dx11.wad.client. Layout (reversed by [shader-re]):

TOC file  <path>.ps-dx11 / <path>.vs-dx11:
    str   magic           ("TOC3.0"; str = u32 len + bytes)
    u32   nperm           permutations listed
    u32   ndef            number of defines below
    u32   nblob           unique compiled shaders (deduplicated)
    u32   stage           0 = vertex, 1 = pixel
    str   "baseDefines"
    ndef x (str name, str value)
    str   "shaders"
    nperm x u64           permutation hash = xxh64("".join(f"{k}={v}" for k,v in sorted(enabled_defines)))
    nperm x u32           blob index of that permutation
Blob bundle <path>.ps-dx11_<N> (N = blob_index // 100 * 100) holds blobs N..N+99 back to back:
    u32 n ; n bytes = DXBC container (n-1 bytes) + 1 trailing byte (always 0x35)

The define combination of every permutation is recovered from the hash by a flip-BFS over the define list
(seeds: every combination within Hamming distance 3 of "none" and of "all").

Usage:
    python tools/lol/extract_shaders.py                 # index everything + disassemble the key shaders fully,
                                                        # other shaders: blobs of the 2 smallest define sets
    python tools/lol/extract_shaders.py --filter quad_ps --all
Output: tools/extracted/shaders/<path without assets/shaders/>.<stage>/b<blob>.asm
        + per-shader index.txt (blob -> define sets) + tools/extracted/shaders/INDEX.txt / index.json
"""
import argparse
import ctypes
import glob
import itertools
import json
import os
import re
import struct
import sys

import xxhash

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wad import Wad  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GAME = r"D:\Riot Games\League of Legends\Game\DATA\FINAL"
WAD_PATH = os.path.join(GAME, "ShaderCache.dx11.wad.client")
HASHES = os.path.join(ROOT, "tools", "extracted", "cdhash", "hashes.game.txt.*")
OUT = os.path.join(ROOT, "tools", "extracted", "shaders")

# Shaders that get every unique blob disassembled (the ones that define how ARAM looks).
KEY = [
    r"hlsl/particlesystem/", r"hlsl/skinnedmesh/(lit_uber|default_vs|particle_|shadow_map|solid_color)",
    r"generated/shaders/particles/(defaultparticle|shaderpreset/)", r"hlsl/gamma/", r"hlsl/fogofwar/",
    r"hlsl/filters/", r"hlsl/fxaa", r"hlsl/smaa/", r"hlsl/environment/", r"hlsl/renderer/", r"hlsl/ssao/",
    r"hlsl/regions/", r"hlsl/lighting/", r"hlsl/decal/", r"hlsl/enveffectors/", r"hlsl/simple_vs",
    r"hlsl/single_color_ps", r"generated/shaders/staticmesh/defaultenv_flat", r"generated/shaders/postprocess/",
]


# ---------------------------------------------------------------- D3DDisassemble
_d3d = None


def disasm(dxbc: bytes) -> str:
    global _d3d
    if _d3d is None:
        _d3d = ctypes.WinDLL(r"C:\Windows\System32\d3dcompiler_47.dll")
    out = ctypes.c_void_p()
    hr = _d3d.D3DDisassemble(ctypes.c_char_p(dxbc), ctypes.c_size_t(len(dxbc)), ctypes.c_uint(0), None,
                             ctypes.byref(out))
    if hr != 0:
        return f"// D3DDisassemble failed hr=0x{hr & 0xffffffff:08x}\n"
    vt = ctypes.cast(ctypes.cast(out, ctypes.POINTER(ctypes.c_void_p))[0], ctypes.POINTER(ctypes.c_void_p))
    release = ctypes.WINFUNCTYPE(ctypes.c_ulong, ctypes.c_void_p)(vt[2])
    get_ptr = ctypes.WINFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p)(vt[3])
    get_size = ctypes.WINFUNCTYPE(ctypes.c_size_t, ctypes.c_void_p)(vt[4])
    s = ctypes.string_at(get_ptr(out), get_size(out))
    release(out)
    return s.rstrip(b"\0").decode("latin1").replace("\r\n", "\n")


# ---------------------------------------------------------------- TOC
def parse_toc(d: bytes) -> dict:
    p = 0

    def u32():
        nonlocal p
        v = struct.unpack_from("<I", d, p)[0]
        p += 4
        return v

    def s():
        nonlocal p
        n = u32()
        v = d[p:p + n].decode("latin1")
        p += n
        return v

    magic = s()
    if magic != "TOC3.0":
        raise ValueError(magic)
    nperm, ndef, nblob, stage = u32(), u32(), u32(), u32()
    s()  # baseDefines
    defs = [(s(), s()) for _ in range(ndef)]
    s()  # shaders
    hashes = list(struct.unpack_from(f"<{nperm}Q", d, p))
    p += 8 * nperm
    idx = list(struct.unpack_from(f"<{nperm}I", d, p))
    return dict(nperm=nperm, ndef=ndef, nblob=nblob, stage=stage, defs=defs, hashes=hashes, idx=idx)


def perm_hash(defs, mask: int) -> int:
    on = sorted(defs[i] for i in range(len(defs)) if mask >> i & 1)
    return xxhash.xxh64("".join(f"{k}={v}" for k, v in on).encode()).intdigest()


def recover_defines(toc) -> dict:
    """hash -> bitmask over toc['defs']."""
    defs = toc["defs"]
    n = len(defs)
    want = set(toc["hashes"])
    found = {}
    full = (1 << n) - 1
    if n <= 16:
        for m in range(1 << n):
            h = perm_hash(defs, m)
            if h in want:
                found[h] = m
        return found
    # Some defines appear several times with different values (USE_RIM=0 / USE_RIM=1): mutually exclusive
    # choices. Moves = flip one define, or swap one value of a group for another.
    groups = {}
    for i, (k, _v) in enumerate(defs):
        groups.setdefault(k, []).append(i)
    moves = [1 << i for i in range(n)]
    for idxs in groups.values():
        for a, b in itertools.combinations(idxs, 2):
            moves.append((1 << a) | (1 << b))
    singles = sum(1 << g[0] for g in groups.values() if len(g) == 1)
    bases = {0, full}
    for vi in range(max(len(g) for g in groups.values())):
        pick = sum(1 << g[min(vi, len(g) - 1)] for g in groups.values() if len(g) > 1)
        bases.add(pick)
        bases.add(singles | pick)
    frontier = []
    seen = set()
    depth = 3 if len(moves) <= 80 else 2
    for base in bases:
        for r in range(0, depth + 1):
            for comb in itertools.combinations(moves, r):
                m = base
                for mv in comb:
                    m ^= mv
                if m in seen:
                    continue
                seen.add(m)
                h = perm_hash(defs, m)
                if h in want and h not in found:
                    found[h] = m
                    frontier.append(m)
    while frontier and len(found) < len(want):
        nxt = []
        for m in frontier:
            for mv in moves:
                m2 = m ^ mv
                if m2 in seen:
                    continue
                seen.add(m2)
                h = perm_hash(defs, m2)
                if h in want and h not in found:
                    found[h] = m2
                    nxt.append(m2)
        frontier = nxt
    return found


# ---------------------------------------------------------------- main
def load_names():
    names = {}
    for f in glob.glob(HASHES):
        with open(f, encoding="utf-8") as fh:
            for line in fh:
                h, _, path = line.rstrip("\n").partition(" ")
                if path.startswith("assets/shaders/"):
                    names[int(h, 16)] = path
    return names


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--filter", default="", help="regex on shader path")
    ap.add_argument("--all", action="store_true", help="disassemble every unique blob of matching shaders")
    ap.add_argument("--base", type=int, default=2, help="non-key shaders: blobs of the N smallest define sets")
    ap.add_argument("--index-only", action="store_true")
    args = ap.parse_args()

    names = load_names()
    w = Wad(WAD_PATH)
    by_path = {}
    for h, e in w.entries.items():
        if h in names:
            by_path[names[h]] = e
    tocs = sorted(p for p in by_path if re.search(r"\.(ps|vs)-dx11$", p))
    key_re = re.compile("|".join(KEY))
    flt = re.compile(args.filter) if args.filter else None

    index = {}
    lines = []
    tot_blobs = tot_asm = 0
    for path in tocs:
        if flt and not flt.search(path):
            continue
        toc = parse_toc(w.read_entry(by_path[path]))
        masks = recover_defines(toc)
        defs = toc["defs"]
        dup = {k for k, _ in defs if sum(1 for k2, _ in defs if k2 == k) > 1}
        lab = [k if k not in dup else f"{k}={v}" for k, v in defs]   # repeated names: show the value
        blob_perms = {}
        unresolved = 0
        for h, b in zip(toc["hashes"], toc["idx"]):
            m = masks.get(h)
            if m is None:
                unresolved += 1
                continue
            if m not in blob_perms.setdefault(b, []):   # TOCs can list the same permutation twice
                blob_perms[b].append(m)
        rel = path[len("assets/shaders/"):].replace(".ps-dx11", ".ps").replace(".vs-dx11", ".vs")
        odir = os.path.join(OUT, *rel.split("/"))
        is_key = bool(key_re.search(path))
        if args.all or is_key:
            pick = sorted(set(toc["idx"]))
        else:
            order = sorted(blob_perms.items(), key=lambda kv: min(bin(m).count("1") for m in kv[1]))
            pick = [b for b, _ in order[:args.base]]
        if args.index_only:
            pick = []
        index[path] = dict(stage="ps" if toc["stage"] else "vs", nperm=toc["nperm"], nblob=toc["nblob"],
                           defines=[f"{k}={v}" for k, v in defs], unresolved=unresolved,
                           blobs={str(b): [[lab[i] for i in range(len(defs)) if m >> i & 1] for m in ms]
                                  for b, ms in sorted(blob_perms.items())},
                           disassembled=pick)
        lines.append(f"{rel:90s} defs={toc['ndef']:3d} perms={toc['nperm']:6d} blobs={toc['nblob']:5d}"
                     f" unresolved={unresolved} asm={len(pick)}")
        tot_blobs += toc["nblob"]
        if not pick:
            continue
        os.makedirs(odir, exist_ok=True)
        with open(os.path.join(odir, "index.txt"), "w", newline="\n") as fh:
            fh.write(f"# {path}\n# stage={'ps' if toc['stage'] else 'vs'} perms={toc['nperm']} "
                     f"blobs={toc['nblob']} unresolved={unresolved}\n# defines: "
                     + " ".join(f"{k}={v}" for k, v in defs) + "\n")
            for b, ms in sorted(blob_perms.items()):
                for m in sorted(ms, key=lambda x: bin(x).count("1")):
                    fh.write(f"b{b:04d}: " + " ".join(lab[i] for i in range(len(defs)) if m >> i & 1) + "\n")
        bundles = {}
        for b in pick:
            base = b // 100 * 100
            if base not in bundles:
                data = w.read(f"{path}_{base}")
                offs = []
                p = 0
                while data is not None and p < len(data):
                    n = struct.unpack_from("<I", data, p)[0]
                    offs.append((p + 4, n - 1))
                    p += 4 + n
                bundles[base] = (data, offs)
            data, offs = bundles[base]
            if data is None or b - base >= len(offs):
                continue
            o, n = offs[b - base]
            dx = data[o:o + n]
            hdr = [f"// {path}  blob {b}", "// permutations using this blob (enabled defines):"]
            for m in sorted(blob_perms.get(b, []), key=lambda x: bin(x).count("1")):
                hdr.append("//   " + (" ".join(lab[i] for i in range(len(defs)) if m >> i & 1) or "(none)"))
            with open(os.path.join(odir, f"b{b:04d}.asm"), "w", newline="\n") as fh:
                fh.write("\n".join(hdr) + "\n" + disasm(dx))
            tot_asm += 1
    os.makedirs(OUT, exist_ok=True)
    if not flt:
        with open(os.path.join(OUT, "index.json"), "w", newline="\n") as fh:
            json.dump(index, fh, indent=1)
        with open(os.path.join(OUT, "INDEX.txt"), "w", newline="\n") as fh:
            fh.write("\n".join(lines) + "\n")
    print(f"shaders={len(index)} unique_blobs={tot_blobs} disassembled={tot_asm}")
    bad = [p for p, v in index.items() if v["unresolved"]]
    if bad:
        print("unresolved permutation hashes in:", len(bad))
        for p in bad[:20]:
            print("  ", p, index[p]["unresolved"], "/", index[p]["nperm"])


if __name__ == "__main__":
    main()
