import sys, re
from wad import Wad
# scan .bin entries (PROP/PTCH magic) of a wad for a needle and print nearby ascii strings
w = Wad(sys.argv[1]); needle = sys.argv[2].encode(); maxhits = int(sys.argv[3]) if len(sys.argv) > 3 else 3
hits = 0
for h, e in w.entries.items():
    if e.size > 80_000_000: continue
    try: d = w.read_entry(e)
    except Exception: continue
    if d[:4] not in (b'PROP', b'PTCH'): continue
    i = d.find(needle)
    if i < 0: continue
    print(f'== entry {h:016x} size {len(d)} first hit @{i}')
    seg = d[max(0, i-600): i+1500]
    for m in re.finditer(rb'[\x20-\x7e]{5,}', seg): print('   ', m.group().decode())
    hits += 1
    if hits >= maxhits: break
