import json, os
from wad import Wad
from tex import decode_tex
rows = json.load(open('../extracted/mayhem_augments.json', encoding='utf-8'))
m12 = Wad("D:/Riot Games/League of Legends/Game/DATA/FINAL/Maps/Shipping/Map12.wad.client")
m30 = Wad("D:/Riot Games/League of Legends/Game/DATA/FINAL/Maps/Shipping/Map30.wad.client")
out = '../../assets/ui/augments_large'; os.makedirs(out, exist_ok=True)
ok = 0; bad = []
for r in rows:
    if r.get('missing'): continue
    h = int(r['icon_hash'], 16)
    d = m12.read(h) or m30.read(h)
    if not d: bad.append(r['id']); continue
    try:
        im = decode_tex(d); im.save(os.path.join(out, r['id'].lower() + '.png')); ok += 1
    except Exception as ex:
        bad.append((r['id'], str(ex)))
print('ok', ok, 'bad', len(bad), bad[:10])
