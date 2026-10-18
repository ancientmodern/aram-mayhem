"""Extract League's in-game end-of-game banner art (UI.wad.client + UI.en_US.wad.client, assets/ux/endofgame/*) as PNGs
into assets/ui/eog/: crest bases (blue/gold victory, cracked red defeat) and the metallic VICTORY / DEFEAT lettering.
Usage: python tools/lol/extract_eog.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wad import Wad  # noqa: E402
from extract_hud import decode  # noqa: E402

G = "D:/Riot Games/League of Legends/Game/DATA/FINAL/"
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT = os.path.join(ROOT, "assets", "ui", "eog")
WANT = {"eog_base": "crest_victory", "eog_defeat_base": "crest_defeat", "en_us/victory": "text_victory",
        "en_us/defeat": "text_defeat", "eog_base_errosion": "erosion", "vanguard/vanguard_emblem_glow": "glow"}


def main():
    os.makedirs(OUT, exist_ok=True)
    wads = [Wad(G + "UI.wad.client"), Wad(G + "UI.en_US.wad.client")]
    for src, dst in WANT.items():
        p = "assets/ux/endofgame/%s.tex" % src
        data = None
        for w in wads:
            data = w.read(p)
            if data:
                break
        if not data:
            print("missing", p)
            continue
        im = decode(data)
        im.save(os.path.join(OUT, dst + ".png"))
        print(dst, im.size)


if __name__ == "__main__":
    main()
