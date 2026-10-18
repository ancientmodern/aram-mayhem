"""Extract Howling Abyss (Map12) gameplay layout: structures, spawn points,
health relics, lane nav points, barracks, props -> data/map/howling_abyss_layout.json
"""
import json
import os
import re

from binfile import BinFile, BinObject, BinHash, BinLink, fnv1a
from wad import Wad
from extract_client import ROOT

GAME = "D:/Riot Games/League of Legends/Game/DATA/FINAL"
XFORM = 0xe1ad931b


def collect_strings(o, out, depth=0):
    if depth > 4:
        return
    if isinstance(o, BinObject):
        for k, v in o.fields.items():
            if isinstance(v, str):
                out.append(v)
            elif isinstance(v, (BinObject, list, dict)):
                collect_strings(v, out, depth + 1)
    elif isinstance(o, list):
        for v in o:
            collect_strings(v, out, depth + 1)
    elif isinstance(o, dict):
        for k, v in o.items():
            if isinstance(k, str):
                out.append(k)
            collect_strings(v, out, depth + 1)


def walk(o, key, results, names):
    if isinstance(o, BinObject):
        x = o.fields.get(XFORM)
        if isinstance(x, tuple) and len(x) == 16:
            strs = []
            collect_strings(o, strs)
            nm = o.get("name")
            if isinstance(nm, BinHash):
                nm = names.get(int(nm), f"#{int(nm):08x}")
            results.append({
                "key": names.get(int(key), f"#{int(key):08x}") if isinstance(key, int) else str(key),
                "class": f"{o.cls:08x}",
                "name": nm,
                "pos": [round(x[12], 2), round(x[13], 2), round(x[14], 2)],
                "fwd": [round(x[8], 4), round(x[9], 4), round(x[10], 4)],
                "strings": strs[:12],
            })
        for k, v in o.fields.items():
            walk(v, k, results, names)
    elif isinstance(o, dict):
        for k, v in o.items():
            walk(v, k, results, names)
    elif isinstance(o, list):
        for v in o:
            walk(v, key, results, names)


def main():
    w = Wad(f"{GAME}/Maps/Shipping/Map12.wad.client")
    data = w.read("data/maps/mapgeometry/map12/base.materials.bin")
    bf = BinFile(data)
    # build name table from every string in the file (placeable names are hashed strings)
    names = {}
    for m in re.finditer(rb"[\x20-\x7e]{3,}", data):
        s = m.group().decode()
        for cut in range(len(s), 2, -1):  # strings may carry trailing garbage bytes
            names.setdefault(fnv1a(s[:cut]), s[:cut])
    extract_extras(bf, names)
    if "--env-only" in os.sys.argv:
        return
    results = []
    for k, e in bf.entries.items():
        walk(e, k, results, names)
    # classify
    out = {"structures": [], "spawns": [], "relics": [], "nav": [], "barracks": [], "props": [], "other": []}
    for r in results:
        s = " ".join([str(r["name"]), r["key"]] + r["strings"])
        if "CharacterRecords" in s and re.search(r"Turret|Inhibitor|Nexus|Shrine", s):
            out["structures"].append(r)
        elif "__Spawn" in s:
            out["spawns"].append(r)
        elif re.search(r"Relic|HealthPack", s):
            out["relics"].append(r)
        elif "__NAV" in s or "LANE_" in s:
            out["nav"].append(r)
        elif "Barracks" in s:
            out["barracks"].append(r)
        elif "LevelProp" in s or "CharacterRecords" in s:
            out["props"].append(r)
        else:
            out["other"].append(r)
    path = os.path.join(ROOT, "data", "map", "howling_abyss_layout.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(out, open(path, "w", encoding="utf-8"), indent=1)
    for k, v in out.items():
        print(k, len(v))
    for r in out["structures"] + out["spawns"] + out["relics"] + out["barracks"]:
        cr = [x for x in r["strings"] if "CharacterRecords" in x]
        print(f"  {str(r['name'])[:34]:34s} {r['pos']}  {cr[:1]}")


# [env] Map lighting + level props (base.materials.bin MapContainer / GdsMapObject type 10)
def extract_extras(bf, names):
    """data/map/map12_env.json: MapSunProperties of the Base MapContainer and every LevelProp placement
    (animated map characters: chains, bridge statues, banners, decorative poros...). A LevelProp named
    LevelProp_<Character><n> is the character <Character> with skin mapObjectSkinID (default 0)."""
    sun = {}
    props = []
    sun_cls = fnv1a("MapSunProperties")
    for k, e in bf.entries.items():
        if e.cls == fnv1a("MapContainer"):
            for c in e.get("components") or []:
                if isinstance(c, BinObject) and c.cls == sun_cls:
                    for f in ("sunColor", "sunDirection", "skyLightColor", "horizonColor", "groundColor",
                              "skyLightScale", "lightMapColorScale", "fogColor", "fogAlternateColor", "fogStartAndEnd"):
                        v = c.get(f)
                        if v is not None:
                            sun[f] = list(v) if isinstance(v, tuple) else v
        if e.cls != fnv1a("MapPlaceableContainer"):
            continue
        items = e.get("items") or {}
        for it in items.values():
            if not isinstance(it, BinObject) or it.cls != fnv1a("GdsMapObject") or it.get("type") != 10:
                continue
            nm = it.get("name")
            if not isinstance(nm, str) or not nm.startswith("LevelProp_"):
                continue
            ch = re.sub(r"\d+$", "", nm[len("LevelProp_"):])
            props.append({"name": nm, "character": ch, "skin": int(it.get("mapObjectSkinID") or 0),
                          "xform": [round(x, 5) for x in it.get("Transform")]})
    props.sort(key=lambda r: r["name"])
    path = os.path.join(ROOT, "data", "map", "map12_env.json")
    json.dump({"sun": sun, "level_props": props}, open(path, "w", encoding="utf-8", newline=chr(10)), indent=1)
    print("sun", sun.get("sunDirection"), "level props", len(props))


if __name__ == "__main__":
    main()
