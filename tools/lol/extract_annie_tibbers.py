"""Tibbers (Annie's R summon) ships inside Annie.wad.client as its own character (data/characters/annietibbers).
Extract its particle systems into data/vfx/annietibbers.json with the regular extractor.
Usage: python tools/lol/extract_annie_tibbers.py"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import extract_vfx as X

if __name__ == "__main__":
    X._wads[f"{X.GAME}/Champions/AnnieTibbers.wad.client"] = X.wad(f"{X.GAME}/Champions/Annie.wad.client")
    out = X.extract_champion("AnnieTibbers")
    print(sorted(k for k in out if not k.startswith("_")))
