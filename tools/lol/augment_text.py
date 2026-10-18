import re, json, sys
from wad import Wad
from rst import StringTable
G = "D:/Riot Games/League of Legends/Game/DATA/FINAL"
m12 = Wad(G + "/Maps/Shipping/Map12.wad.client")
binb = m12.read(0x410b3796f165ef3e)
st = StringTable(Wad(G + "/Localized/Global.en_US.wad.client").read("data/menu/en_us/lol.stringtable"))
print('strings', len(st.strings), file=sys.stderr)
keys = sorted(set(k.decode() for k in re.findall(rb'(?:Kiwi|Cherry)_[A-Za-z0-9_\']+', binb)))
out = {}
for k in keys:
    for cand in (k, k.rstrip("'")):
        s = st.get(cand)
        if s is not None:
            out[cand] = s; break
json.dump(out, open('../extracted/kiwi_strings.json', 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
print(len(keys), 'keys', len(out), 'resolved', file=sys.stderr)
