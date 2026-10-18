"""Extract League's in-game HUD layout, textures and font styles from UI.wad.client for the Godot HUD.

Output (assets/ui/hud/):
  layout.json    {"<Group>:<ElementName>": {c, p, s, src, a, t, uv, l, g, ha, fd, fr, fin, ec}}
                 c = element class (Icon/Text/Region/EffectCooldownRadial/EffectAnimation/...)
                 p/s = position/size in the source resolution `src` ([w, h]), a = anchor [x, y]
                 t = texture png name (in assets/ui/hud/tex/), uv = [x0, y0, x1, y1] in PNG pixels
                 l = layer, g = ignores global HUD scale, ha = horizontal text alignment
                 fd = font description name (key into fonts.json)
                 fr = [total frames, frames per atlas row, fps] for EffectAnimation flipbooks, fin = finish behaviour
                 ec = effect colour (RGBA 0-255) of cooldown / ammo effects
  fonts.json     {"<FontDescription>": {font, color, outline, shadow, glow, sizes: [[screenH, px, outline, sx, sy]], auto}}
                 colours are RGBA 0-255 (League stores BGRA; converted here), screenH 0 = default (1080)
  tex/*.png      every atlas / standalone texture referenced by the exported elements. Textures that the bins
                 reference by their source .png path live in per-scene auto atlases (uiautoatlas/.../atlas_N.tex);
                 the IMAA mapping files next to each scene give their UV rect, and they are cropped out here.
  pings/*.png    minimap / world ping icons (assets/ux/minimap/pings)
  buffs/*.png    generic buff icons (assets/spells/icons2d) used for CC without a spell icon
  minimap_map12.png  Howling Abyss minimap art (Map12.wad.client)
  icons/*.png    minimap icons (assets/ux/minimap/icons)
  fonts/*.otf    League fonts used by HUD styles that assets/fonts lacks (Gill Sans)

Texture names: bins store xxh64 path hashes. tools/lol/hud_hashes.txt caches the names of every hash the HUD needs;
it is refreshed from CommunityDragon's hashes.game.txt.* when those are present in tools/extracted/cdhash/
(https://github.com/CommunityDragon/Data/tree/master/hashes/lol).

Usage: python tools/lol/extract_hud.py
"""
import glob
import json
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from wad import Wad, path_hash  # noqa: E402
from binfile import BinFile, BinObject, BinFileRef, BinLink, fnv1a  # noqa: E402
from tex import decode_tex  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
GAME = "D:/Riot Games/League of Legends/Game/DATA/FINAL/"
OUT = os.path.join(HERE, "..", "..", "assets", "ui", "hud")
HASH_CACHE = os.path.join(HERE, "hud_hashes.txt")
CDHASH = os.path.join(HERE, "..", "extracted", "cdhash")

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
    "Ping": "ClientStates/Gameplay/UX/LoL/LoLPingRadial/UIBase/",
    "Chat": "ClientStates/Gameplay/UX/Chat/UIBase/",
}

PING_ICONS = """ping ping_cb ping_gray all_in assist on_my_way_new mia_new retreat push need_ward area_is_warded_small_red_new
enemychampsighted target hold bait ring2_tintable ring_tintable ring2_red ring2_yellow ring2_green ring2_danger
get_back_small get_back_small_blue get_back_small_purple focus group""".split()
BUFF_ICONS = ["assets/spells/icons2d/gsb_stun.dds", "assets/spells/icons2d/burning.dds"]

MINIMAP_ICONS = """icon_ui_tower_minimap icon_ui_tower_minimap_low icon_ui_tower_minimap_med icon_ui_inhibitor_minimap_v2
icon_ui_nexus_minimap_v2 minionmapcircle mapcircle champion_dead healthpack shop tower nexus inhibitor
recalloutline recallhostileoutline""".split()

CLS = {fnv1a(n): n.replace("UiElement", "").replace("Data", "") for n in """UiElementIconData UiElementTextData
UiElementRegionData UiElementGroupButtonData UiElementGroupData UiElementGroupMeterData UiElementGroupSliderData
UiElementEffectAnimationData UiElementEffectCooldownRadialData UiElementEffectFillPercentageData
UiElementEffectDesaturateData UiElementEffectGlowData UiElementEffectAmmoData UiElementEffectCooldownData
UiElementEffectArcFillData UiElementEffectLineData UiElementScissorRegionData UiSceneData
UiElementParticleSystemData UiElementEffectCircleMaskCooldownData""".split()}

F = {n: fnv1a(n) for n in """name Layer Position UIRect Size SourceResolutionWidth SourceResolutionHeight Anchors
Anchor AnchorLeft AnchorRight TextureData mTextureName mTextureUv IgnoreGlobalScale TextAlignmentHorizontal
FramesPerSecond TotalNumberOfFrames NumberOfFramesPerRowInAtlas mFinishBehavior mPerPixelUvsX FontDescription
mTextureSourceResolutionWidth mTextureSourceResolutionHeight mEffectColor0
typeData resolutionData Color outlineColor shadowColor glowColor localeResolutions localeName resolutions
screenHeight fontSize outlineSize shadowDepthX shadowDepthY autoScale localeTypes mFontFilePath""".split()}
C_FONTDESC = fnv1a("GameFontDescription")
C_FONTTYPE = fnv1a("FontType")
C_FONTRES = fnv1a("FontResolutionData")
# standalone-texture class (`TextureData: {b311d4ef: file}`) uses an unnamed field
F_STANDALONE_TEX = 0xB311D4EF


def f(o, name, default=None):
    return o.fields.get(F[name], default) if isinstance(o, BinObject) else default


def bgra(c):
    """League colours are stored B, G, R, A."""
    if c is None:
        return None
    c = list(c)
    return [c[2], c[1], c[0], c[3]]


def load_names(wanted):
    """hash -> path for every hash in `wanted` (cache file, refreshed from CommunityDragon lists when present)."""
    names = {}
    if os.path.exists(HASH_CACHE):
        for line in open(HASH_CACHE, encoding="utf-8"):
            h, _, p = line.rstrip("\n").partition(" ")
            names[int(h, 16)] = p
    missing = set(wanted) - set(names)
    lists = sorted(glob.glob(os.path.join(CDHASH, "hashes.game.txt*")))
    if missing and lists:
        for fn in lists:
            for line in open(fn, encoding="utf-8", errors="replace"):
                h = int(line[:16], 16)
                if h in missing:
                    names[h] = line[17:].rstrip("\n")
        with open(HASH_CACHE, "w", encoding="utf-8", newline="\n") as fo:
            for h in sorted(names):
                fo.write("%016x %s\n" % (h, names[h]))
    return names


def read_imaa(d):
    """IMAA auto-atlas map: u32 magic, u32 n_atlases, n * u64 atlas, u32 count, count * (u64 tex, 4 f32 uv01, u32 atlas idx)."""
    n_at = struct.unpack_from("<I", d, 4)[0]
    off = 8
    atlases = list(struct.unpack_from("<%dQ" % n_at, d, off))
    off += 8 * n_at
    cnt = struct.unpack_from("<I", d, off)[0]
    off += 4
    out = {}
    for _ in range(cnt):
        th, u0, v0, u1, v1, ai = struct.unpack_from("<Q4fI", d, off)
        off += 28
        out[th] = (atlases[ai] if ai < len(atlases) else atlases[0], (u0, v0, u1, v1))
    return out


def decode(data):
    """decode_tex plus TEX format 13 (BC7, used by the UI auto atlases), which tools/lol/tex.py does not handle."""
    if data[:4] == b"TEX\x00" and data[9] == 13:
        from PIL import Image
        w, h = struct.unpack_from("<HH", data, 4)
        has_mips = bool(data[11] & 1)
        size = max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * 16
        payload = data[12:]
        raw = payload[len(payload) - size:] if has_mips else payload[:size]
        return Image.frombytes("RGBA", (w, h), raw, "bcn", 7)
    return decode_tex(data)


def tex_name(path, used):
    base = os.path.splitext(os.path.basename(path))[0].lower().replace(" ", "_")
    if base in used and used[base] != path:
        base = os.path.basename(os.path.dirname(path)).lower() + "_" + base
    used[base] = path
    return base


def main():
    for sub in ("tex", "icons", "pings", "buffs"):
        os.makedirs(os.path.join(OUT, sub), exist_ok=True)
    ui = Wad(GAME + "UI.wad.client")
    glob_wad = Wad(GAME + "Global.wad.client")

    layout = {}
    tex_refs = {}        # element key -> texture hash
    font_refs = set()
    fontdesc = {}        # entry hash -> BinObject
    fonttype = {}
    fontres = {}
    imaa = {}
    for h, e in ui.entries.items():
        try:
            d = ui.read_entry(e)
        except Exception:
            continue
        if d[:4] == b"IMAA":
            try:
                imaa.update(read_imaa(d))
            except Exception:
                pass
            continue
        if d[:4] not in (b"PROP", b"PTCH"):
            continue
        try:
            bf = BinFile(d)
        except Exception:
            continue
        for ek, o in bf.entries.items():
            if o.cls == C_FONTDESC:
                fontdesc[ek] = o
                continue
            if o.cls == C_FONTTYPE:
                fonttype[ek] = o
                continue
            if o.cls == C_FONTRES:
                fontres[ek] = o
                continue
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
                tsw = td.fields.get(F["mTextureSourceResolutionWidth"])
                tsh = td.fields.get(F["mTextureSourceResolutionHeight"])
                if tsw and tsh:
                    el["_tsr"] = [tsw, tsh]
            ha = f(o, "TextAlignmentHorizontal")
            if ha is not None:
                el["ha"] = ha
            fd = f(o, "FontDescription")
            if isinstance(fd, int):
                el["_fd"] = int(fd)
                font_refs.add(int(fd))
            tot = f(o, "TotalNumberOfFrames")
            if tot is not None:
                el["fr"] = [int(tot), int(f(o, "NumberOfFramesPerRowInAtlas", 1) or 1), float(f(o, "FramesPerSecond", 30) or 30)]
                if f(o, "mFinishBehavior") is not None:
                    el["fin"] = f(o, "mFinishBehavior")
            ec = f(o, "mEffectColor0")
            if ec is not None:
                el["ec"] = bgra(ec)
            if f(o, "mPerPixelUvsX"):
                el["ppx"] = 1
            key = grp + ":" + nm.split("/")[-1]
            if key in layout:  # disambiguate with the parent folder
                key = grp + ":" + "/".join(nm.split("/")[-2:])
            layout[key] = el
            if isinstance(tref, BinFileRef):
                tex_refs[key] = int(tref)

    # ---------------------------------------------------------------- textures
    names = load_names(set(tex_refs.values()) | set(imaa.keys()))
    used = {}
    hname = {}        # texture hash -> png name
    tex_size = {}     # png name -> (w, h)
    missing = []
    for th in sorted(set(tex_refs.values())):
        path = names.get(th)
        tn = tex_name(path, used) if path else "h%016x" % th
        img = None
        cands = [th]
        if path and not path.endswith(".tex"):
            cands.append(path_hash(os.path.splitext(path)[0] + ".tex"))
        for w in (ui, glob_wad):
            for c in cands:
                if c in w.entries:
                    img = decode(w.read_entry(w.entries[c]))
                    break
            if img is not None:
                break
        if img is None and th in imaa:
            ah, (u0, v0, u1, v1) = imaa[th]
            for w in (ui, glob_wad):
                if ah in w.entries:
                    atlas = decode(w.read_entry(w.entries[ah]))
                    aw, ahh = atlas.size
                    img = atlas.crop((round(u0 * aw), round(v0 * ahh), round(u1 * aw), round(v1 * ahh)))
                    break
        if img is None:
            missing.append(path or tn)
            continue
        img.save(os.path.join(OUT, "tex", tn + ".png"))
        hname[th] = tn
        tex_size[tn] = img.size
    for key, th in tex_refs.items():
        el = layout[key]
        tn = hname.get(th)
        tsr = el.pop("_tsr", None)
        if tn is None:
            continue
        el["t"] = tn
        # UVs are given in the texture's source resolution; rescale to the PNG we actually ship
        if "uv" in el and tsr:
            sx = tex_size[tn][0] / float(tsr[0])
            sy = tex_size[tn][1] / float(tsr[1])
            if abs(sx - 1.0) > 1e-3 or abs(sy - 1.0) > 1e-3:
                u = el["uv"]
                el["uv"] = [u[0] * sx, u[1] * sy, u[2] * sx, u[3] * sy]
    for el in layout.values():
        el.pop("_tsr", None)

    # ---------------------------------------------------------------- fonts
    def font_file(type_link):
        ft = fonttype.get(type_link)
        if ft is None:
            return "BeaufortforLOL-Bold"
        for lt in f(ft, "localeTypes", []) or []:
            if f(lt, "localeName") is None:
                return os.path.splitext(os.path.basename(f(lt, "mFontFilePath", "")))[0]
        return "BeaufortforLOL-Bold"

    fonts = {}
    fd_name = {}
    for ek, o in fontdesc.items():
        nm = f(o, "name") or "%08x" % ek
        fd_name[ek] = nm
        if ek not in font_refs and nm in fonts:
            continue
        res = fontres.get(int(f(o, "resolutionData", 0) or 0))
        sizes = []
        auto = True
        if res is not None:
            auto = bool(f(res, "autoScale", True))
            for lr in f(res, "localeResolutions", []) or []:
                if f(lr, "localeName") is not None:
                    continue
                for rr in f(lr, "resolutions", []) or []:
                    sizes.append([f(rr, "screenHeight", 0) or 0, f(rr, "fontSize", 0) or 0, f(rr, "outlineSize", 0) or 0,
                                  f(rr, "shadowDepthX", 0) or 0, f(rr, "shadowDepthY", 0) or 0])
        fonts[nm] = {"font": font_file(int(f(o, "typeData", 0) or 0)), "color": bgra(f(o, "Color", (255, 255, 255, 255))),
                     "outline": bgra(f(o, "outlineColor")), "shadow": bgra(f(o, "shadowColor")), "glow": bgra(f(o, "glowColor")),
                     "sizes": sorted(sizes), "auto": auto}
    for el in layout.values():
        fd = el.pop("_fd", None)
        if fd is not None and fd in fd_name:
            el["fd"] = fd_name[fd]

    # ---------------------------------------------------------------- extra icons
    for n in MINIMAP_ICONS:
        d = ui.read("assets/ux/minimap/icons/%s.tex" % n)
        if d:
            decode(d).save(os.path.join(OUT, "icons", n + ".png"))
    for n in PING_ICONS:
        d = ui.read("assets/ux/minimap/pings/%s.tex" % n)
        if d:
            decode(d).save(os.path.join(OUT, "pings", n + ".png"))
        else:
            missing.append("ping " + n)
    for p in BUFF_ICONS:
        d = glob_wad.read(p) or ui.read(p)
        if d:
            decode(d).save(os.path.join(OUT, "buffs", os.path.splitext(os.path.basename(p))[0] + ".png"))
    # League fonts the HUD styles use that assets/fonts does not ship (chat / tooltip body: Gill Sans)
    os.makedirs(os.path.join(OUT, "fonts"), exist_ok=True)
    for fp in ("assets/ux/fonts/gillsansmtpro-medium.otf",):
        d = ui.read(fp)
        if d:
            with open(os.path.join(OUT, "fonts", os.path.basename(fp)), "wb") as fo:
                fo.write(d)
    m12 = Wad(GAME + "Maps/Shipping/Map12.wad.client")
    d = m12.read("assets/maps/info/map12/2dlevelminimap.tex")
    if d:
        decode(d).save(os.path.join(OUT, "minimap_map12.png"))
    with open(os.path.join(OUT, "layout.json"), "w", encoding="utf-8", newline="\n") as fo:
        json.dump(layout, fo, indent=0, sort_keys=True)
    with open(os.path.join(OUT, "fonts.json"), "w", encoding="utf-8", newline="\n") as fo:
        json.dump(fonts, fo, indent=0, sort_keys=True)
    for m in missing:
        print("missing texture", m)
    print("elements", len(layout), "textures", len(hname), "fonts", len(fonts), "imaa", len(imaa))


if __name__ == "__main__":
    main()
