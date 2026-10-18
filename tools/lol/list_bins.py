import sys, re
from collections import Counter
from wad import Wad
from binfile import BinFile
w = Wad(sys.argv[1])
pat = re.compile(sys.argv[2].encode()) if len(sys.argv) > 2 else None
for h, e in w.entries.items():
    if e.size > 60_000_000: continue
    try: d = w.read_entry(e)
    except Exception: continue
    if d[:4] not in (b'PROP', b'PTCH'): continue
    hits = pat.findall(d) if pat else []
    if pat and not hits: continue
    try:
        bf = BinFile(d); n = len(bf.entries)
    except Exception as ex:
        n = f'ERR {ex}'
    print(f'{h:016x} size={len(d)} entries={n} hits={len(hits)} sample={[x.decode(errors="replace") for x in hits[:6]]}')
