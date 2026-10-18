"""Extract League client (LCU) UI sounds and music (plain .ogg) from Plugins/*/assets.wad.
Names are recovered by hashing paths referenced from the plugins' own JS bundles.
Usage: python tools/lol/extract_client_audio.py <out_dir>"""
import sys, re, os, glob
sys.path.insert(0, os.path.dirname(__file__))
from wad import Wad, path_hash

P = "D:/Riot Games/League of Legends/Plugins"
out = sys.argv[1] if len(sys.argv) > 1 else "assets/audio/client"
os.makedirs(out, exist_ok=True)
plugins = sorted(os.path.basename(os.path.dirname(p)) for p in glob.glob(P + "/*/assets.wad"))
wads = {}
refs = set()
for pl in plugins:
    try:
        w = Wad(f"{P}/{pl}/assets.wad")
    except Exception as ex:
        print("skip", pl, ex); continue
    wads[pl] = w
    es = w.entries.values() if isinstance(w.entries, dict) else w.entries
    for e in es:
        if e.size > 20_000_000:
            continue
        try:
            d = w.read_entry(e)
        except Exception:
            continue
        if d[:4] == b'OggS' or d[:4] == b'\x1aE\xdf\xa3':
            continue
        if not all(32 <= b < 127 or b in (9, 10, 13) for b in d[:64]):
            continue
        for m in re.finditer(rb'[\w\-/\.]+\.ogg', d):
            refs.add(m.group(0).decode().lstrip('/'))
print(len(refs), "ogg refs")
subdirs = ["", "sounds/", "audio/", "sfx/", "sound/", "assets/sounds/", "assets/audio/"]
found = {}
for r in refs:
    cands = set()
    m = re.match(r'fe/(?:rcp-fe-)?(lol-[\w\-]+|[\w\-]+)/(.*)', r)
    if m:
        name = m.group(1)
        pl = name if name.startswith("rcp-") else "rcp-fe-" + name
        cands.add(f"plugins/{pl}/global/default/{m.group(2)}")
    base = r.split('/')[-1]
    for pl in plugins:
        for sd in subdirs:
            cands.add(f"plugins/{pl}/global/default/{sd}{r}")
            cands.add(f"plugins/{pl}/global/default/{sd}{base}")
    for c in cands:
        h = path_hash(c)
        for pl, w in wads.items():
            ents = w.entries
            e = ents.get(h) if isinstance(ents, dict) else None
            if e is not None and base not in found:
                d = w.read_entry(e)
                if d[:4] == b'OggS':
                    found[base] = (pl, c)
                    with open(os.path.join(out, base), "wb") as f:
                        f.write(d)
print(len(found), "extracted")
for b, (pl, c) in sorted(found.items()):
    print(f"  {b:60s} {pl}")
