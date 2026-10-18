"""Extract League client (LCU) assets for the game: champion data, icons,
splash/loadscreen art, champion select voice lines, items, summoner spells, fonts.

Usage: python extract_client.py
"""
import io
import json
import os
import re
import sys

from PIL import Image

from wad import Wad

LOL = "D:/Riot Games/League of Legends"
PLUG = LOL + "/Plugins"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
ASSETS = os.path.join(ROOT, "assets")
DATA = os.path.join(ROOT, "data")

ROSTER = {
    "Ahri": 103, "Garen": 86, "Darius": 122, "Yasuo": 157, "MasterYi": 11, "Malphite": 54,
    "Leona": 89, "Lux": 99, "Jinx": 222, "Ezreal": 81, "MissFortune": 21, "Annie": 1,
    "Sona": 37, "Veigar": 45,
}

_wads = None


def wads():
    global _wads
    if _wads is None:
        _wads = [Wad(PLUG + "/rcp-be-lol-game-data/default-assets.wad"),
                 Wad(PLUG + "/rcp-be-lol-game-data/default-assets2.wad")]
    return _wads


def client_path(p: str) -> str:
    p = p.replace("/lol-game-data/assets/", "plugins/rcp-be-lol-game-data/global/default/")
    return p.lower()


def read_client(p: str):
    cp = client_path(p)
    for w in wads():
        d = w.read(cp)
        if d is not None:
            return d
    return None


def save(rel, data):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as f:
        f.write(data)
    return path


def save_img(rel, data, max_size=None, fmt=None):
    im = Image.open(io.BytesIO(data))
    if max_size and max(im.size) > max_size:
        im.thumbnail((max_size, max_size), Image.LANCZOS)
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    if path.lower().endswith(".jpg"):
        im.convert("RGB").save(path, quality=90)
    else:
        im.save(path)


def extract_champions():
    for alias, cid in ROSTER.items():
        raw = read_client(f"/lol-game-data/assets/v1/champions/{cid}.json")
        if raw is None:
            print("!! missing champion json", alias)
            continue
        c = json.loads(raw)
        low = alias.lower()
        base = f"assets/champions/{low}/ui"
        save(f"data/champions/{low}_client.json", json.dumps(c, indent=1, ensure_ascii=False).encode("utf-8"))
        d = read_client(c["squarePortraitPath"])
        if d:
            save_img(f"{base}/square.png", d)
        icons = {"p": c["passive"]["abilityIconPath"]}
        for s in c["spells"]:
            icons[s["spellKey"]] = s["abilityIconPath"]
        for k, p in icons.items():
            d = read_client(p)
            if d:
                save_img(f"{base}/{k}.png", d)
            else:
                print("  missing icon", alias, k, p)
        for key, p in (("choose_vo", c.get("chooseVoPath")), ("stinger", c.get("stingerSfxPath")),
                       ("ban_vo", c.get("banVoPath"))):
            if p:
                d = read_client(p)
                if d:
                    save(f"assets/champions/{low}/audio/{key}.ogg", d)
        # skins: loadscreen + centered splash (downscaled)
        skins_out = []
        for sk in c["skins"]:
            num = sk["id"] % 1000
            entry = {"id": sk["id"], "num": num, "name": sk["name"], "rarity": sk.get("rarity"),
                     "legacy": sk.get("isLegacy")}
            for key, size in (("loadScreenPath", 512), ("splashPath", 1280), ("tilePath", 380)):
                p = sk.get(key)
                if not p:
                    continue
                d = read_client(p)
                if d:
                    tag = {"loadScreenPath": "load", "splashPath": "splash", "tilePath": "tile"}[key]
                    save_img(f"{base}/skins/{num}_{tag}.jpg", d, max_size=size)
                    entry[tag] = True
            skins_out.append(entry)
        save(f"data/champions/{low}_skins.json", json.dumps(skins_out, indent=1, ensure_ascii=False).encode("utf-8"))
        print("champion", alias, "skins", len(skins_out))


def extract_items():
    raw = read_client("/lol-game-data/assets/v1/items.json")
    items = json.loads(raw)
    save("data/client/items.json", json.dumps(items, indent=1, ensure_ascii=False).encode("utf-8"))
    n = 0
    for it in items:
        p = it.get("iconPath")
        if not p:
            continue
        d = read_client(p)
        if d:
            try:
                save_img(f"assets/ui/items/{it['id']}.png", d, max_size=64)
                n += 1
            except Exception:
                pass
    print("items", len(items), "icons", n)


def extract_summoners():
    raw = read_client("/lol-game-data/assets/v1/summoner-spells.json")
    if raw is None:
        print("!! no summoner-spells.json")
        return
    sums = json.loads(raw)
    save("data/client/summoner-spells.json", json.dumps(sums, indent=1, ensure_ascii=False).encode("utf-8"))
    for s in sums:
        p = s.get("iconPath")
        d = read_client(p) if p else None
        if d:
            name = re.sub(r"[^a-z0-9]+", "_", s["name"].lower()).strip("_") or f"id{s['id']}"
            save_img(f"assets/ui/summoners/{name}.png", d, max_size=64)
    print("summoners", len(sums))


def extract_fonts():
    w = Wad(PLUG + "/rcp-fe-lol-typekit/default-assets.wad")
    from PIL import ImageFont
    os.makedirs(os.path.join(ASSETS, "fonts"), exist_ok=True)
    for h, e in w.entries.items():
        d = w.read_entry(e)
        kind = None
        if d[:4] == b"wOF2":
            kind = "woff2"
        elif d[:4] == b"wOFF":
            kind = "woff"
        elif d[:4] == b"OTTO":
            kind = "otf"
        elif d[:4] == b"\x00\x01\x00\x00":
            kind = "ttf"
        if kind is None:
            continue
        name = f"{h:016x}"
        try:
            f = ImageFont.truetype(io.BytesIO(d), 12)
            fam, style = f.getname()
            name = re.sub(r"[^A-Za-z0-9]+", "_", f"{fam}_{style}")
        except Exception:
            pass
        save(f"assets/fonts/{name}.{kind}", d)
        print("font", name, kind, len(d))


if __name__ == "__main__":
    what = sys.argv[1:] or ["champions", "items", "summoners", "fonts"]
    if "champions" in what:
        extract_champions()
    if "items" in what:
        extract_items()
    if "summoners" in what:
        extract_summoners()
    if "fonts" in what:
        extract_fonts()
