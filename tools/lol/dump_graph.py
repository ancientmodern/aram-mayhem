import sys, json
sys.path.insert(0, 'ref')
from lolwad import Wad
from lolbin import read_bin, fnv1a32, BinStruct
from export_character import vocabulary
ch = sys.argv[1]
w = Wad(f'D:/Riot Games/League of Legends/Game/DATA/FINAL/Champions/{ch}.wad.client')
bf = read_bin(w.get(f'data/characters/{ch.lower()}/animations/skin0.bin'))
voc = vocabulary(ch) | {x for x in ['Spell1', 'Spell4', 'Spell1_Run', 'Spell4_Run', 'Spell1_In', 'Spell1_Out']}
N = {fnv1a32(n): n for n in voc}
cls = {fnv1a32(n): n for n in 'AtomicClipData SelectorClipData SequencerClipData ParallelClipData ConditionBoolClipData ConditionFloatClipData ParametricClipData'.split()}
g = list(bf.objects.values())[0]
cm = g.get('mClipDataMap')
for k, v in cm.items():
    if v is None: continue
    def refs(x, acc):
        if isinstance(x, BinStruct):
            for _k, (_t, y) in x.fields.items(): refs(y, acc)
        elif isinstance(x, list):
            for y in x: refs(y, acc)
        elif isinstance(x, int) and x in cm: acc.append(N.get(x, hex(x)))
        return acc
    print(f"{N.get(k, hex(k)):24s} {cls.get(v.class_hash, hex(v.class_hash)):24s} {refs(v, [])}")
