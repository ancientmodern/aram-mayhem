import sys, os
from wad import Wad
w = Wad(sys.argv[1]); out = sys.argv[2]
for spec in sys.argv[3:]:
    h, name = spec.split('=')
    d = w.read(int(h, 16))
    open(os.path.join(out, name), 'wb').write(d)
    print(name, len(d))
