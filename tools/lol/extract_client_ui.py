"""Extract League client (LCU) UI art (png/jpg/webm/svg/fonts) referenced by the plugins' own JS/CSS bundles.

The Plugins/rcp-fe-*/assets.wad files address entries by hashed path, so names are recovered from the bundles'
`/fe/<plugin>/<path>.<ext>` references (same trick as extract_client_audio.py), hashed as
`plugins/rcp-fe-<plugin>/global/default/<path>` and looked up in every plugin WAD.

Usage:
  python tools/lol/extract_client_ui.py --scan                  # write the reference table to <out>/refs.txt
  python tools/lol/extract_client_ui.py <out_dir> <substr>...   # extract every found ref whose path contains a substr
"""
import glob
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wad import Wad, path_hash  # noqa: E402

P = "D:/Riot Games/League of Legends/Plugins"
EXT = r"(?:png|jpg|svg|webm|webp|gif|ttf|otf|woff2?)"


def open_wads():
    wads = {}
    for wp in sorted(glob.glob(P + "/*/*.wad")):
        pl = os.path.basename(os.path.dirname(wp))
        try:
            wads[(pl, os.path.basename(wp))] = Wad(wp)
        except Exception as ex:  # noqa: BLE001
            print("skip", wp, ex)
    return wads


def scan_refs(wads):
    refs = set()
    for w in wads.values():
        for e in w.entries.values():
            if e.size > 20_000_000 or e.size < 20:
                continue
            try:
                d = w.read_entry(e)
            except Exception:  # noqa: BLE001
                continue
            if not all(32 <= b < 127 or b in (9, 10, 13) for b in d[:64]):
                continue
            for m in re.finditer(rb"/?fe/([\w\-]+)/([\w\-/\.@ ]+\." + EXT.encode() + rb")", d):
                refs.add((m.group(1).decode(), m.group(2).decode()))
    return refs


def lookup(wads, plugin, path):
    name = plugin if plugin.startswith("rcp-") else "rcp-fe-" + plugin
    h = path_hash(f"plugins/{name}/global/default/{path}")
    for w in wads.values():
        e = w.entries.get(h)
        if e is not None:
            return w, e
    return None, None


def main():
    args = sys.argv[1:]
    out = args[1] if args and args[0] == "--scan" else args[0]
    os.makedirs(out, exist_ok=True)
    wads = open_wads()
    refs_file = os.path.join(out, "refs.txt")
    if args[0] == "--scan" or not os.path.exists(refs_file):
        refs = scan_refs(wads)
        found = []
        for pl, path in sorted(refs):
            w, e = lookup(wads, pl, path)
            if e is not None:
                found.append(f"{pl}/{path}\t{e.size}")
        with open(refs_file, "w", newline="\n") as f:
            f.write("\n".join(found) + "\n")
        print(len(refs), "refs,", len(found), "found ->", refs_file)
        if args[0] == "--scan":
            return
    subs = args[1:]
    n = 0
    for line in open(refs_file):
        rel = line.split("\t")[0]
        if not any(s in rel for s in subs):
            continue
        pl, path = rel.split("/", 1)
        w, e = lookup(wads, pl, path)
        if e is None:
            continue
        dst = os.path.join(out, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        with open(dst, "wb") as f:
            f.write(w.read_entry(e))
        n += 1
    print(n, "files extracted to", out)


if __name__ == "__main__":
    main()
