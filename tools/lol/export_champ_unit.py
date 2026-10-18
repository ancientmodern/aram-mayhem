"""Export a non-champion unit that ships inside a champion WAD (Jinx's chomper "JinxMine", Annie's Tibbers...)
to assets/units/<name>/<name>.glb.   Usage: python tools/lol/export_champ_unit.py <ChampionWad> <UnitName>"""
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import export_character as E

if __name__ == "__main__":
    wad_name, unit = sys.argv[1], sys.argv[2]
    p = E.model_path(unit, 0)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    wp = f"{E.GAME}/Champions/{wad_name}.wad.client"
    E.export(unit, 0, p, E.open_wads(unit, extra=[wp]), max_tex=1024)
    print("wrote", p)
