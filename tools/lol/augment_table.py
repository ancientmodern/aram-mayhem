import json, re, sys
from wad import Wad
from binfile import BinFile, BinObject, fnv1a, to_py
from rst import StringTable
G = "D:/Riot Games/League of Legends/Game/DATA/FINAL"
m12 = Wad(G + "/Maps/Shipping/Map12.wad.client")
bf = BinFile(m12.read(0x410b3796f165ef3e))
st = StringTable(Wad(G + "/Localized/Global.en_US.wad.client").read("data/menu/en_us/lol.stringtable"))
H = fnv1a
kiwi = json.load(open('../extracted/client/augment-lists.json', encoding='utf-8'))[1]['augmentList']
RAR = {0: 'Silver', 1: 'Gold', 2: 'Prismatic'}

def data_values(spell_obj):
    out = {}
    if spell_obj is None: return out
    sp = spell_obj.get('mSpell')
    if not isinstance(sp, BinObject): return out
    for dv in (sp.get('DataValues') or sp.get('mDataValues') or []):
        if isinstance(dv, BinObject):
            vals = dv.get(0x34474c3b)
            out[dv.get(0x8d39bde6)] = vals
    return out, sp

def fmt_num(x):
    if abs(x - round(x)) < 1e-4: return str(int(round(x)))
    return f"{x:.2f}".rstrip('0').rstrip('.')

def resolve(text, dv):
    def rep(m):
        expr = m.group(1)
        mm = re.match(r'^([A-Za-z0-9_]+)(?:\*([\-0-9.]+))?$', expr)
        if mm and mm.group(1) in dv and dv[mm.group(1)]:
            vals = dv[mm.group(1)]
            v = vals[0]
            if mm.group(2): v *= float(mm.group(2))
            return fmt_num(v)
        return '{' + expr + '}'
    return re.sub(r'@([^@]+)@', rep, text)

def strip_tags(s):
    s = re.sub(r'<br\s*/?>', ' ', s)
    return re.sub(r'<[^>]+>', '', s)

rows = []
for p in kiwi:
    e = bf.get(p)
    if e is None:
        rows.append({'path': p, 'missing': True}); continue
    nid = e.get('augmentNameId')
    name = st.get(e.get('NameTra') or '') or nid
    tip_key = e.get(0x366935fc) or e.get('DescriptionTra')
    tip = st.get(tip_key or '') or ''
    summ = st.get(e.get('DescriptionTra') or '') or ''
    root = e.get('RootSpell')
    spell = bf.entries.get(int(root)) if root is not None else None
    dv, sp = ({}, None)
    if spell is not None:
        r = data_values(spell)
        if r: dv, sp = r
    rows.append({
        'id': nid, 'name': name, 'rarity': RAR.get(e.get('rarity', 0), e.get('rarity')),
        'summary': strip_tags(resolve(summ, dv)), 'tooltip': strip_tags(resolve(tip, dv)),
        'values': {k: (v[0] if v else None) for k, v in dv.items()},
        'icon_hash': f"{int(e.get('AugmentLargeIconPath') or 0):016x}",
        'small_icon_hash': f"{int(e.get('AugmentSmallIconPath') or 0):016x}",
        'spell_found': spell is not None,
    })
json.dump(rows, open('../extracted/mayhem_augments.json', 'w', encoding='utf-8'), indent=1, ensure_ascii=False)
print('rows', len(rows), 'missing', sum(1 for r in rows if r.get('missing')), 'with spell', sum(1 for r in rows if r.get('spell_found')))
with open('../../docs/research/mayhem_augments_client.md', 'w', encoding='utf-8') as f:
    f.write('# ARAM: Mayhem augments (extracted from local game client)\n\n')
    for rar in ('Silver', 'Gold', 'Prismatic'):
        f.write(f'\n## {rar}\n\n')
        for r in sorted([r for r in rows if r.get('rarity') == rar], key=lambda r: r['name']):
            f.write(f"- **{r['name']}** (`{r['id']}`): {r['tooltip'] or r['summary']}\n")
