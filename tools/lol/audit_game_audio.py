"""[juice] Audit data/audio/<champ>.json against the in-game event mapping: which events GameAudio can route
(basic attack cast/hit, crit, spell cast/launch/hit, death, vo) and which stay unused. Prints a table + the leftovers.
Usage: python tools/lol/audit_game_audio.py [alias ...]
"""
import json, os, re, sys, glob

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CAST_SUF = ("_oncast", "_cast", "_missilecast", "_castself", "_cast_self")
LAUNCH_SUF = ("_onmissilelaunch", "_missilelaunch")
ACT_SUF = ("_buffactivate", "_onbuffactivate")
HIT_SUF = ("_hit", "_onhit", "_beamend", "_onmisshit")


def suffix_kind(low):
    for s in CAST_SUF:
        if low.endswith(s):
            return "cast", low[: -len(s)]
    for s in LAUNCH_SUF:
        if low.endswith(s):
            return "launch", low[: -len(s)]
    for s in ACT_SUF:
        if low.endswith(s):
            return "act", low[: -len(s)]
    for s in HIT_SUF:
        if low.endswith(s):
            return "hit", low[: -len(s)]
    return "other", low


def classify(alias):
    path = os.path.join(ROOT, "data", "audio", alias.lower() + ".json")
    d = json.load(open(path))
    ev = list(d.get("sfx", {}))
    g = json.load(open(os.path.join(ROOT, "data", "champions", alias.lower() + "_game.json")))
    slots = {k: v.replace("1Wrapper", "").replace("Wrapper", "") for k, v in g.get("spell_slots", {}).items()}
    pre = "Play_sfx_%s_" % alias
    out = {k: {"cast": [], "launch": [], "act": [], "hit": []} for k in "QWER"}
    ba = {"cast": [], "hit": [], "crit_cast": [], "crit_hit": []}
    used = set()
    for e in ev:
        if not e.startswith(pre):
            continue
        mid = e[len(pre):]
        low = mid.lower()
        kind, fam = suffix_kind(low)
        if low in ("death3d_cast",):
            used.add(e)
            continue
        if "basicattack" in low or "critattack" in low:
            key = ("crit_" if "crit" in low else "") + ("hit" if kind == "hit" else "cast")
            ba[key].append(e)
            used.add(e)
            continue
        for k, base in slots.items():
            if fam.startswith(base.lower()) or (base.lower().startswith(fam) and len(fam) > 4):
                if kind in out[k]:
                    out[k][kind].append(e)
                    used.add(e)
                break
    left = [e for e in ev if e not in used and e.startswith(pre)]
    return slots, out, ba, left


def main():
    aliases = sys.argv[1:] or sorted(os.path.basename(p)[:-10] for p in glob.glob(os.path.join(ROOT, "data", "champions", "*_game.json")))
    for a in aliases:
        al = json.load(open(os.path.join(ROOT, "data", "champions", a + "_game.json")))["alias"]
        try:
            slots, out, ba, left = classify(al)
        except Exception as ex:  # noqa: BLE001
            print(al, "ERR", ex)
            continue
        row = " ".join("%s:%d/%d/%d/%d" % (k, len(v["cast"]), len(v["launch"]), len(v["act"]), len(v["hit"])) for k, v in out.items())
        print("%-12s BA cast %d hit %d crit %d/%d | %s | left %d" % (al, len(ba["cast"]), len(ba["hit"]), len(ba["crit_cast"]), len(ba["crit_hit"]), row, len(left)))
        for e in left:
            print("      unmatched:", e.replace("Play_sfx_", ""))


if __name__ == "__main__":
    main()
