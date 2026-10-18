"""Extract the legacy (.troybin) summoner-spell systems that live outside the champion/shared bins into
data/vfx/summoners.json (kept separate from shared.json so `extract_vfx.py --shared` never drops them).

Systems: Global_SS_Heal / Global_SS_Heal_02 (Heal), Global_SS_Clarity (Clarity), Global_SS_Cleanse (Cleanse),
Global_SS_Ghost (Ghost). Flash / Barrier / Ignite already ship in shared.json.
Usage: python tools/lol/extract_summoner_vfx.py          (textures land in assets/vfx like every other system)
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import extract_vfx as X

SYSTEMS = {
    "Global_SS_Heal": "data/particles/global_ss_heal.troybin",
    "Global_SS_Heal_02": "data/particles/global_ss_heal_02.troybin",
    "Global_SS_Clarity": "data/particles/global_ss_clarity.troybin",
    "Global_SS_Cleanse": "data/particles/global_ss_cleanse.troybin",
    "Global_SS_Ghost": "data/particles/global_ss_ghost.troybin",
}

if __name__ == "__main__":
    out = {}
    for name, path in SYSTEMS.items():
        try:
            s = X.troy_system(path)
        except Exception as ex:
            print("fail", name, ex)
            s = None
        if s is not None:
            out[name] = s
            print(name, "emitters", len(s["emitters"]), "dur", s["dur"])
    p = os.path.join(X.ROOT, "data", "vfx", "summoners.json")
    json.dump(out, open(p, "w", encoding="utf-8"), separators=(",", ":"))
    print("wrote", p, sorted(out))
