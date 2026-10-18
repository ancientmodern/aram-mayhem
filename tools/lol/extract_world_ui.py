"""Extract League's in-world UI data/textures into assets/ui/world/ (world-ui owner).

Sources (patch 16.20, all from the local game install):
  UI.wad.client
    bin 0x3db39d2f8cdb8a4c  ClientStates/Gameplay/UX/LoL/LoLFloatingInfoBars  (floating health bar layout)
    bin 0xfebbef8e54eaea1   FloatingTextTypeData (damage/heal/gold/xp text physics)
    bin 0x957ccb5182db61f8  FontDescriptions (FloatText_* / HealthBar* fonts, colours, sizes)
    bin 0xaba32b154dd30ab2  CursorConfig (cursor textures + hotspots)
    tex 37b03fb998093e20    floating health bar atlas (512x512)
    assets/ux/floatingtext/*.tex, assets/ux/cursors/*.tga
  Global.wad.client / Map12.wad.client
    assets/spells/textures/*.tex  (spell targeter textures: additive, black = transparent)

Colours in these UI bins are stored B,G,R,A; they are converted to R,G,B,A here.
Run:  cd tools/lol && python extract_world_ui.py
"""
import io, json, os, sys
from wad import Wad
from binfile import BinFile, to_py, fnv1a
from tex import decode_tex
from PIL import Image

GAME = "D:/Riot Games/League of Legends/Game/DATA/FINAL/"
OUT = os.path.join(os.path.dirname(__file__), "../../assets/ui/world")
os.makedirs(OUT, exist_ok=True)
ui = Wad(GAME + "UI.wad.client")
glob = Wad(GAME + "Global.wad.client")
m12 = Wad(GAME + "Maps/Shipping/Map12.wad.client")

# field names recovered by brute force (fnv1a of the lower-cased name)
FIELDS = """name color position mTextureName mTextureUV mTextureSourceResolutionWidth mTextureSourceResolutionHeight
TextureData mFontDescription mTypeName Priority Decay DecayDelay IsAnimated MinXVelocity MaxXVelocity MinYVelocity
MaxYVelocity StartOffsetX StartOffsetY ContinualForceX ContinualForceY ShrinkTime ShrinkScale Scale AlternateRightLeft
FollowSource DisableVerticalReverse Icons mDisplaySize mOffset mColor mAlignment CombinableNumberFormat MaxInstances
OutlineColor ShadowColor FontSize OutlineSize TypeData mHotspot CursorData mData colorblindColor colorblindOutlineColor
HangTime RandomStartOffsetMinX RandomStartOffsetMaxX RandomStartOffsetMinY RandomStartOffsetMaxY IgnoreQueue
DisableHorizontalReverse mTunables mMaxFloatingTextItems mAnimatedTextQueueDelay mComparisonByLevel
mMinionComparisonMultiplier""".split()
N = {fnv1a(f): f for f in FIELDS}
N[fnv1a("UiElementRect")] = "UiElementRect"
SIZE = "23a0d95c"         # UiElementRect size (unnamed hash)
# NOTE: there is no fill gradient in League's floating-text fonts. f0ec2f06 / 8be090f2 are colorblindColor /
# colorblindOutlineColor (CommunityDragon hashes.binfields.txt); they replace color/outline in colourblind mode.
# FloatText fonts carry no shadowColor, so the engine default (opaque black) is used with shadowDepthX/Y.
SHADOW_X, SHADOW_Y = "18a801ba", "19a8034d"


def bgra(c):
    return [c[2], c[1], c[0], c[3]] if isinstance(c, list) and len(c) == 4 else c


def load_bin(h):
    bf = BinFile(ui.read(h))
    return {f"{k:08x}": to_py(v, N) for k, v in bf.entries.items()}


def save_tex(wad, key, name):
    d = wad.read(key)
    if d is None:
        print("missing", key)
        return None
    im = decode_tex(d) if d[:3] == b"TEX" else Image.open(io.BytesIO(d))
    im.convert("RGBA").save(os.path.join(OUT, name))
    return im.size


# ---------------------------------------------------------------- floating health bars
fib = load_bin(0x3db39d2f8cdb8a4c)
ATLAS = "file:37b03fb998093e20"
layout = {}
for v in fib.values():
    nm = str(v.get("name", ""))
    if "/LoLFloatingInfoBars/UIBase/" not in nm:
        continue
    short = nm.split("/UIBase/")[1]
    if not short.split("/")[0] in ("ChampBars", "FHBMinionSmall", "FHBMinionMed", "FHBMinionLarge", "FHBStructure", "FHBEpicStructure"):
        continue
    pos = v.get("position", {})
    r = pos.get("3a8bfbed", {}) if isinstance(pos, dict) else {}
    if not r:
        continue
    e = {"pos": r.get("position"), "size": r.get(SIZE)}
    td = v.get("TextureData", {})
    if td.get("mTextureName") == ATLAS:
        e["uv"] = td.get("mTextureUV")
    if "color" in v:
        e["color"] = bgra(v["color"])
    layout[short.split("/")[-1]] = e
json.dump(layout, open(os.path.join(OUT, "fhb_layout.json"), "w"), indent=1, sort_keys=True)
print("fhb elements", len(layout), "atlas", save_tex(ui, 0x37b03fb998093e20, "fhb_atlas.png"))

# ---------------------------------------------------------------- fonts + floating text
fonts = load_bin(0x957ccb5182db61f8)
ft = load_bin(0xfebbef8e54eaea1)


def font_desc(link):
    f = fonts.get(link[5:]) if isinstance(link, str) and link.startswith("link:") else None
    if not f:
        return {}
    res = fonts.get(str(f.get("11413a17", ""))[5:], {})
    sz = {}
    for grp in res.get("de214652", []):
        for s in grp.get("d78560b4", []):
            if "ScreenHeight" not in s:
                sz = s
    ty = fonts.get(str(f.get("TypeData", ""))[5:], {})
    files = [x.get("8764b624") for x in ty.get("8c9d92f4", []) if "1a9f4554" not in x]
    return {"font": files[0].split("/")[-1] if files else None, "color": bgra(f.get("color")),
            "colorblind": bgra(f.get("colorblindColor")), "outline": bgra(f.get("OutlineColor")),
            "colorblind_outline": bgra(f.get("colorblindOutlineColor")), "shadow": bgra(f.get("ShadowColor")),
            "size": sz.get("FontSize"), "outline_size": sz.get("OutlineSize"),
            "shadow_offset": [sz.get(SHADOW_X, 0), sz.get(SHADOW_Y, 0)]}


types = {}
for v in ft.values():
    fd = font_desc(v.get("mFontDescription"))
    f = fonts.get(str(v.get("mFontDescription", ""))[5:], {})
    nm = str(f.get("name", "")).replace("FloatText_", "")
    if not nm or nm in types:
        continue
    t = {k: v[k] for k in ("Priority", "Decay", "DecayDelay", "MinXVelocity", "MaxXVelocity", "MinYVelocity", "MaxYVelocity",
                           "StartOffsetX", "StartOffsetY", "ContinualForceX", "ContinualForceY", "ShrinkTime", "ShrinkScale",
                           "Scale", "AlternateRightLeft", "FollowSource", "MaxInstances", "HangTime", "RandomStartOffsetMinX",
                           "RandomStartOffsetMaxX", "RandomStartOffsetMinY", "RandomStartOffsetMaxY", "IgnoreQueue",
                           "DisableHorizontalReverse") if k in v}
    t.update(fd)
    if v.get("Icons"):
        ic = v["Icons"][0]
        t["icon"] = ic.get("10537b0c")
        t["icon_size"] = ic.get("mDisplaySize")
        t["icon_offset"] = ic.get("mOffset")
    types[nm] = t
for nm in ("HealthBarTitle", "HealthBarSelfTitle", "HealthBarLevel", "HealthBarStatusTitle"):
    for k, f in fonts.items():
        if f.get("name") == nm:
            types[nm] = font_desc("link:" + k)
for v in ft.values():
    if isinstance(v.get("mTunables"), dict):   # FloatingTextGlobalConfig: item cap, queue delay, size comparison
        types["_tunables"] = {k: x for k, x in v["mTunables"].items() if not k.startswith("__")}
json.dump(types, open(os.path.join(OUT, "floating_text.json"), "w"), indent=1, sort_keys=True)
print("floating text types", len(types))
for key, name in (("8ed7f356e9ba1237", "ft_crit_physical.png"), ("6f67e151f193d7cb", "ft_crit_magic.png"),
                  ("29e3324fac0adaf1", "ft_crit_true.png"), ("4683803252ad73b6", "ft_gold.png")):
    save_tex(ui, int(key, 16), name)

# ---------------------------------------------------------------- cursors (classic CursorConfig)
for src, dst in (("Hand1", "cursor_hand"), ("HoverEnemy", "cursor_hover_enemy"), ("HoverFriendly", "cursor_hover_ally"),
                 ("SingleTarget", "cursor_target"), ("SingleTargetEnemy", "cursor_target_enemy"),
                 ("SingleTargetAlly", "cursor_target_ally"), ("SingleTargetEnemyCannoyAttack", "cursor_enemy_cannot_attack"),
                 ("HoverShop", "cursor_shop")):
    save_tex(ui, f"assets/ux/cursors/{src}.tga", dst + ".png")
# hotspots straight from the CursorConfig entry (index order documented in the bin)
cur = load_bin(0xaba32b154dd30ab2)
hot = {}
for v in cur.values():
    for lst in v.values() if isinstance(v, dict) else []:
        for e in lst if isinstance(lst, list) else []:
            for d in ([e] + e.get("mData", [])) if isinstance(e, dict) else []:
                p = str(d.get("mTextureName", ""))
                if p.startswith("ASSETS/UX/Cursors/") and "/Upscaled/" not in p:
                    hot.setdefault(p.split("/")[-1][:-4], d.get("mHotspot", [0, 0]))
json.dump(hot, open(os.path.join(OUT, "cursor_hotspots.json"), "w"), indent=1, sort_keys=True)

# ---------------------------------------------------------------- spell targeter textures
for n in ("aoe", "circularrangeindicator", "conicrangeindicator", "locallinemissilebase", "locallinemissiletarget",
          "crosshair", "directionalcircle", "aoe_microtarget", "pos_microtarget"):
    for w in (glob, m12):
        if w.read(f"assets/spells/textures/{n}.tex") is not None:
            print(n, save_tex(w, f"assets/spells/textures/{n}.tex", f"ind_{n}.png"))
            break
