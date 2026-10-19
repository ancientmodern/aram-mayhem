"""Dump League's raw Map12 navgrid (v7) to tools/extracted/navgrid_raw.bin for src/debug/nav_audit.gd."""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "ref"))
from lolwad import Wad  # noqa: E402

GAME = "D:/Riot Games/League of Legends/Game/DATA/FINAL"
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
w = Wad(f"{GAME}/Maps/Shipping/Map12.wad.client")
d = w.read_entry(w.entries[0x6228ead3f44827ae])
p = os.path.join(ROOT, "tools", "extracted", "navgrid_raw.bin")
os.makedirs(os.path.dirname(p), exist_ok=True)
open(p, "wb").write(d)
print("wrote", p, len(d))
