import json, os
from wad import Wad
P = "D:/Riot Games/League of Legends/Plugins/rcp-be-lol-game-data"
wads = [Wad(P + "/default-assets.wad"), Wad(P + "/default-assets2.wad")]
def read_client(path):
    # '/lol-game-data/assets/X' -> 'plugins/rcp-be-lol-game-data/global/default/X'
    p = path.replace('/lol-game-data/assets/', 'plugins/rcp-be-lol-game-data/global/default/').lower()
    for w in wads:
        d = w.read(p)
        if d is not None: return d
    return None
aug = json.load(open('../extracted/client/cherry-augments.json', encoding='utf-8'))
kiwi = set(p.split('/')[-1].lower() for p in json.load(open('../extracted/client/augment-lists.json', encoding='utf-8'))[1]['augmentList'])
out = '../../assets/ui/augments'; os.makedirs(out, exist_ok=True)
ok = miss = 0
for a in aug:
    if a['augmentNameId'].lower() not in kiwi: continue
    sp = a['augmentSmallIconPath']
    got = False
    for cand in (sp.replace('_small.png', '_large.png'), sp):
        d = read_client(cand)
        if d:
            open(os.path.join(out, a['augmentNameId'].lower() + '.png'), 'wb').write(d); got = True; break
    ok += got; miss += (not got)
    if not got: print('missing icon', a['augmentNameId'], sp)
print('icons ok', ok, 'missing', miss)
