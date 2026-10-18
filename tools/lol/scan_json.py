import sys, json
from wad import Wad, path_hash
w = Wad(sys.argv[1])
needles = [s.encode() for s in sys.argv[2:]]
res = []
for h, e in w.entries.items():
    if e.size > 30_000_000: continue
    try:
        d = w.read_entry(e)
    except Exception as ex:
        continue
    head = d[:1]
    if head in (b'{', b'['):
        hits = [n.decode() for n in needles if n in d]
        res.append((h, len(d), d[:70].replace(b'\n', b' '), hits))
print('json entries', len(res))
for h, n, head, hits in sorted(res, key=lambda r: -len(r[3])):
    if hits or len(sys.argv) == 2:
        print(f'{h:016x} {n:9d} {hits} {head}')
