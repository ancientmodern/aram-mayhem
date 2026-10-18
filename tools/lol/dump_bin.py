import json, sys
from wad import Wad
from binfile import BinFile, to_py
from names import TABLE
w = Wad(sys.argv[1]); p = sys.argv[2]
d = w.read(p)
print('bytes', None if d is None else len(d), file=sys.stderr)
bf = BinFile(d)
print('links', bf.links, file=sys.stderr)
out = {('entry_' + TABLE.get(k, f'{k:08x}')): to_py(v, TABLE) for k, v in bf.entries.items()}
json.dump(out, open(sys.argv[3], 'w', encoding='utf-8'), indent=1)
print('entries', len(out), file=sys.stderr)
