"""[numbers] Resolve League WAD paths / bin hashes with the CommunityDragon hash lists and dump bins as readable JSON.

Usage:
  python numbers_dump.py find <wad> <regex>              list wad entries whose resolved path matches regex
  python numbers_dump.py dump <wad> <path> <out.json>    dump a bin (all entries, names resolved)
  python numbers_dump.py grep <json> <regex>             print "path: value" for keys / string values matching regex

Hash lists: tools/extracted/cdhash (hashes.game.txt.*, hashes.binentries/binfields/binhashes/bintypes).
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from binfile import BinFile, to_py, fnv1a  # noqa: E402
from wad import Wad, path_hash  # noqa: E402

HASH_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "extracted", "cdhash")
GAME = "D:/Riot Games/League of Legends/Game/DATA/FINAL"


def load_bin_names():
    names = {}
    for fn in ("hashes.binfields.txt", "hashes.binentries.txt", "hashes.bintypes.txt", "hashes.binhashes.txt"):
        with open(os.path.join(HASH_DIR, fn), encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.rstrip("\n")
                if len(line) < 9:
                    continue
                try:
                    names[int(line[:8], 16)] = line[9:]
                except ValueError:
                    pass
    return names


def load_game_paths(wad):
    out = {}
    import glob
    for fn in sorted(glob.glob(os.path.join(HASH_DIR, "hashes.game.txt*"))):
        with open(fn, encoding="utf-8", errors="replace") as f:
            for line in f:
                line = line.rstrip("\n")
                h = int(line[:16], 16)
                if h in wad.entries:
                    out[h] = line[17:]
    return out


def cmd_find(wadpath, rx):
    w = Wad(wadpath)
    paths = load_game_paths(w)
    pat = re.compile(rx, re.I)
    n = 0
    for h, p in sorted(paths.items(), key=lambda kv: kv[1]):
        if pat.search(p):
            e = w.entries[h]
            print(f"{h:016x} {e.size:>9} {p}")
            n += 1
    print(f"-- {n} matches of {len(paths)} resolved / {len(w.entries)} entries", file=sys.stderr)


def cmd_dump(wadpath, path, out):
    w = Wad(wadpath)
    names = load_bin_names()
    d = w.read(path)
    if d is None:
        sys.exit("not found: " + path)
    bf = BinFile(d)
    res = {"__links": bf.links}
    for k, v in bf.entries.items():
        res["entry_" + names.get(k, f"{k:08x}")] = to_py(v, names)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(res, f, indent=1)
    print("entries", len(bf.entries), "->", out, file=sys.stderr)


def walk(o, path, pat, out):
    if isinstance(o, dict):
        for k, v in o.items():
            p = path + "/" + k
            if pat.search(k) and not isinstance(v, (dict, list)):
                out.append(f"{p}: {v}")
            walk(v, p, pat, out)
    elif isinstance(o, list):
        for i, v in enumerate(o):
            walk(v, f"{path}[{i}]", pat, out)
    elif isinstance(o, str) and pat.search(o):
        out.append(f"{path}: {o}")


def cmd_grep(jpath, rx):
    j = json.load(open(jpath, encoding="utf-8"))
    out = []
    walk(j, "", re.compile(rx, re.I), out)
    print("\n".join(out))


if __name__ == "__main__":
    c = sys.argv[1]
    if c == "find":
        cmd_find(sys.argv[2], sys.argv[3])
    elif c == "dump":
        cmd_dump(sys.argv[2], sys.argv[3], sys.argv[4])
    elif c == "grep":
        cmd_grep(sys.argv[2], sys.argv[3])
