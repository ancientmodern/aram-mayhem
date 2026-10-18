"""Extract League's in-game HUD layout + textures from UI.wad.client for the Godot HUD.

Output (assets/ui/hud/):
  layout.json    {"<Group>:<ElementName>": {c, p, s, src, a, t, uv, l, g}}
                 c = element class (Icon/Text/Region/CooldownRadial/FillPercentage/Animation/...)
                 p/s = position/size in the source resolution `src` ([w, h]), a = anchor [x, y]
                 t = texture png name (in assets/ui/hud/tex/), uv = [x0, y0, x1, y1] in texture pixels
                 l = layer, g = ignores global HUD scale
  tex/*.png      every atlas / standalone texture referenced by the exported elements
  minimap_map12.png  Howling Abyss minimap art (Map12.wad.client)
  icons/*.png    minimap icons (assets/ux/minimap/icons)

Usage: python tools/lol/extract_hud.py
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wad import Wad, path_hash  # noqa: E402
from binfile import BinFile, BinObject, BinFileRef, fnv1a  # noqa: E402
from tex import decode_tex  # noqa: E402

GAME = "D:/Riot Games/League of Legends/Game/DATA/FINAL/"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assets", "ui", "hud")

GROUPS = {
    "PlayerFrame": "ClientStates/Gameplay/UX/LoL/PlayerFrame/UIBase/",
    "Inventory": "ClientStates/Gameplay/UX/LoL/PlayerInventory/UIBase/",
    "Stats": "ClientStates/Gameplay/UX/LoL/PlayerStats/UIBase/",
    "Minimap": "ClientStates/Gameplay/UX/LoL/LoLMinimap/UIBase/",
    "Header": "ClientStates/Gameplay/UX/LoL/LoLGameHeader/UIBase/",
    "TeamFrames": "ClientStates/Gameplay/UX/LoL/TeamFrames/UIBase/",
    "Kill": "ClientStates/Gameplay/UX/LoL/KillCallouts/UIBase/",
    "Target": "ClientStates/Gameplay/UX/LoL/TargetFrame/UIBase/",
    "Banner": "ClientStates/Gameplay/UX/AnnouncementBanners/ClassicBase/",
    "Scoreboard": "ClientStates/Gameplay/UX/Scoreboard/UIBase/",
    "Shop": "ClientStates/Gameplay/UX/ItemShop/UIBase/",
    "Tooltip": "ClientStates/LoLCommon/UX/Tooltips/UIBase/",
}

# texture paths known from the CommunityDragon directory listing (hashes resolve to these names)
KNOWN_TEX = """
assets/ux/lol/clarity_abilityatlas.tex assets/ux/lol/clarity_hudatlas.tex assets/ux/lol/clarity_hudatlasupdate.tex
assets/ux/lol/clarity_levelupatlas.tex assets/ux/lol/clarity_levelupatlas2.tex assets/ux/lol/clarity_resourceatlas.tex
assets/ux/lol/hudresetatlas.tex assets/ux/lol/itemshophud-default.tex assets/ux/lol/statspanel_atlas.tex
assets/ux/lol/animatedmeters.tex assets/ux/lol/perksatlas.tex assets/ux/lol/objectivealignment_atlas.tex
assets/ux/lol/offscreenping_atlas.tex assets/ux/lol/perkssummonerspecialistui_atlas.tex
assets/ux/itemshop/itemshop_texture_atlas.tex assets/ux/itemshop/itemshop_texture_atlas4.tex
assets/ux/itemshop/itemshop_texture_atlas_2.tex assets/ux/itemshop/itemshop_texture_atlas_3.tex
assets/ux/itemshop/itemshopatlas.tex assets/ux/itemshop/itemshopsupportatlas.tex
assets/ux/scoreboard/scoreboardatlas.tex assets/ux/scoreboard/neutraltimersatlas.tex
assets/ux/common/tooltipatlas.tex assets/ux/common/white.tex assets/ux/common/reconnectatlas.tex
assets/ux/announcements/announcementicons.tex
""".split()

MINIMAP_ICONS = """icon_ui_tower_minimap icon_ui_tower_minimap_low icon_ui_tower_minimap_med icon_ui_inhibitor_minimap_v2
icon_ui_nexus_minimap_v2 minionmapcircle mapcircle champion_dead healthpack shop tower nexus inhibitor
recalloutline recallhostileoutline""".split()

CLS = {fnv1a(n): n.replace("UiElement", "").replace("Data", "") for n in """UiElementIconData UiElementTextData
UiElementRegionData UiElementGroupButtonData UiElementGroupData UiElementGroupMeterData UiElementGroupSliderData
UiElementEffectAnimationData UiElementEffectCooldownRadialData UiElementEffectFillPercentageData
UiElementEffectDesaturateData UiElementEffectGlowData UiElementEffectAmmoData UiElementEffectCooldownData
UiElementEffectArcFillData UiElementEffectLineData UiElementScissorRegionData UiSceneData""".split()}

F = {n: fnv1a(n) for n in """name Layer Position UIRect Size SourceResolutionWidth SourceResolutionHeight Anchors
Anchor AnchorLeft AnchorRight TextureData mTextureName mTextureUv IgnoreGlobalScale TextAlignmentHorizontal
mFramesPerSecond mTotalNumberOfFrames mNumberOfFramesPerRowInAtlas mPerPixelUvsX""".split()}
# standalone-texture class (`TextureData: {b311d4ef: file}`) uses an unnamed field
F_STANDALONE_TEX = 0xB311D4EF


def f(o, name, default=None):
    return o.fields.get(F[name], default) if isinstance(o, BinObject) else default


def main():
    os.makedirs(os.path.join(OUT, "tex"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "icons"), exist_ok=True)
    ui = Wad(GAME + "UI.wad.client")
    known = {path_hash(p): os.path.basename(p).replace(".tex", "") for p in KNOWN_TEX}

    layout = {}
    used_tex = {}
    for h, e in ui.entries.items():
        try:
            d = ui.read_entry(e)
        except Exception:
            continue
        if d[:4] not in (b"PROP", b"PTCH"):
            continue
        try:
            bf = BinFile(d)
        except Exception:
            continue
        for o in bf.entries.values():
            nm = f(o, "name")
            if not isinstance(nm, str):
                continue
            grp = None
            for g, pref in GROUPS.items():
                if nm.startswith(pref):
                    grp = g
                    break
            if grp is None:
                continue
            el = {"c": CLS.get(o.cls, f"{o.cls:08x}")}
            pos = f(o, "Position")
            r = f(pos, "UIRect")
            if r is not None:
                el["p"] = list(f(r, "Position", (0, 0)))
                el["s"] = list(f(r, "Size", (0, 0)))
                el["src"] = [f(r, "SourceResolutionWidth", 1600), f(r, "SourceResolutionHeight", 1200)]
                anc = f(pos, "Anchors")
                a = f(anc, "Anchor")
                if a is None and f(anc, "AnchorLeft") is not None:
                    a = f(anc, "AnchorLeft")
                el["a"] = list(a) if a is not None else [0.5, 0.5]
                if f(pos, "IgnoreGlobalScale"):
                    el["g"] = 1
            if f(o, "Layer") is not None:
                el["l"] = f(o, "Layer")
            td = f(o, "TextureData")
            tref = None
            if isinstance(td, BinObject):
                tref = td.fields.get(F["mTextureName"]) or td.fields.get(F_STANDALONE_TEX)
                uv = td.fields.get(F["mTextureUv"])
                if uv is not None:
                    el["uv"] = list(uv)
            if isinstance(tref, BinFileRef):
                tn = known.get(int(tref), "h%016x" % int(tref))
                used_tex[int(tref)] = tn
                el["t"] = tn
            ha = f(o, "TextAlignmentHorizontal")
            if ha is not None:
                el["ha"] = ha
            if f(o, "mTotalNumberOfFrames") is not None:
                el["fr"] = [f(o, "mTotalNumberOfFrames"), f(o, "mNumberOfFramesPerRowInAtlas", 1), f(o, "mFramesPerSecond", 30)]
            if f(o, "mPerPixelUvsX"):
                el["ppx"] = 1
            key = grp + ":" + nm.split("/")[-1]
            if key in layout:  # disambiguate with the parent folder
                key = grp + ":" + "/".join(nm.split("/")[-2:])
            layout[key] = el

    # textures
    wads = [ui, Wad(GAME + "Global.wad.client")]
    for th, tn in sorted(used_tex.items(), key=lambda x: x[1]):
        for w in wads:
            if th in w.entries:
                img = decode_tex(w.read_entry(w.entries[th]))
                img.save(os.path.join(OUT, "tex", tn + ".png"))
                break
        else:
            print("missing texture", tn)
    for n in MINIMAP_ICONS:
        d = ui.read("assets/ux/minimap/icons/%s.tex" % n)
        if d:
            decode_tex(d).save(os.path.join(OUT, "icons", n + ".png"))
    m12 = Wad(GAME + "Maps/Shipping/Map12.wad.client")
    d = m12.read("assets/maps/info/map12/2dlevelminimap.tex")
    if d:
        decode_tex(d).save(os.path.join(OUT, "minimap_map12.png"))
    with open(os.path.join(OUT, "layout.json"), "w", encoding="utf-8", newline="\n") as fo:
        json.dump(layout, fo, indent=0, sort_keys=True)
    print("elements", len(layout), "textures", len(used_tex))


if __name__ == "__main__":
    main()
