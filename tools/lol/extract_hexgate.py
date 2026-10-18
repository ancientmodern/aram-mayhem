"""Extract the Howling Abyss hexgate + health relic particle systems that data/vfx/shared.json does not carry.

Writes data/vfx/hexgate.json (ARAM_Hexgate_*, HA_Hexgate_*; the HA_Hexgate_Base_* / _Exit_Base_* names are the ones the
HA_Hexgate character's resource resolvers dde709c7 / 30b093d2 map for Skin0). Textures/meshes land in assets/vfx/ via the
same converter as extract_vfx.py. (Relic systems live in shared.json, extracted by extract_vfx.py --shared.)

Usage: python tools/lol/extract_hexgate.py
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import extract_vfx as X
from binfile import BinFile, to_py
from vfx_names import TABLE

SETS = {
    "hexgate": [r"^ARAM_Hexgate_", r"^HA_Hexgate_"],
}


def main():
    out = {k: {} for k in SETS}
    pats = {k: [re.compile(p) for p in v] for k, v in SETS.items()}
    found = {}
    ctx = {"resolve": lambda k: None}
    for wp in (f"{X.GAME}/Maps/Shipping/Map12.wad.client", f"{X.GAME}/Global.wad.client"):
        w = X.wad(wp)
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
                if not nm:
                    continue
                for sname, pl in pats.items():
                    if nm in out[sname] or not any(p.search(nm) for p in pl):
                        continue
                    name, sysd = X.system(w, to_py(v, TABLE), ctx)
                    if sysd is not None:
                        out[sname][name] = sysd
                    else:
                        print("  no system for", nm)
    for sname, d in out.items():
        path = os.path.join(X.ROOT, "data", "vfx", f"{sname}.json")
        json.dump(d, open(path, "w", encoding="utf-8"), separators=(",", ":"))
        print(sname, len(d), sorted(d))


if __name__ == "__main__":
    main()
