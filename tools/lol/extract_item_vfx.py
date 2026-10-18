"""Extract League's item particle systems (Global.wad.client item bins) into data/vfx/items.json.

Item effects are named by item id ("3087_Statikk_Shiv_Beam", "3157_Zhonya_Buf", "Item_Redemption_Cast" ...). Every
bin that holds one of the wanted systems is parsed completely (its own ResourceResolver included), so child systems
resolve like they do for champions. Uses the converters of extract_vfx.py (not modified).

Usage: python tools/lol/extract_item_vfx.py            (writes data/vfx/items.json + assets/vfx/...)
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(__file__))
import extract_vfx as ev  # noqa: E402
from binfile import BinFile, to_py  # noqa: E402
from vfx_names import TABLE  # noqa: E402

WANT = [
    r"^(3074|3077|3748|3068|3087|3085|3142|6692|6631|3156|3157|3102|4633|3084|3143|3190|3152|6655|3153|6676|3124|6653|3116|"
    r"3075|3071|3508|6662|6632|3078|6672|3053|3040|3109|3193|3155|3865|6617|6620|6657|6667|3050|4005|4628|6696|3139|3140|"
    r"6699|6695|3146|3128|3135|3089|3033|6694|3036|3134|3814|6676|6675|6035|7000|3161|3107|3504|3222)_",
    r"^(Item_|BlackCleaver_|BansheeVeilVFX|ItemHurricane_mis|Redemption_Ally_Indicator|Goredrinker_|AbsorbLifeHeal|"
    r"Global_Debuff_ArmorShred|SRI_6673_|Whipchain_|TargetBurn|Ardent_Censer_Hand_Buff|globalhit_physical)",
]
GAME = ev.GAME

# the systems the game uses (item_fx*.gd); everything else in the big Global bin is dropped (children are kept)
KEEP = """
Item_3078_TrinityForce_Hand_Glow 6662_Iceborn_Hand_Glow 6662_Slow_Field 3508_Buff_Active 3508_Hit_Tar 3508_Buff_Mana
6632_BuffOn 6632_Heal Item_TrinityForce_3078_Haste 3077_AoE 3077_AoE_Activated 3074_AoE 3074_AoE_Activated 3748_Arc
3748_Arc_Activated 3077_Sweep 3068_AA_AoE 3068_AA_Burn 3068_Indicator_On 3068_Indicator_Max 3087_Statikk_Shiv_Beam
3087_Statikk_Shiv_Impact 3087_Statikk_Shiv_Ready ItemHurricane_mis 3142_Activate 3142_Activate_Child 3142_SpeedTrail
6692_Shield 6692_Shield_Break 6692_tar 6692_SpeedBuff 6692_Ready 6631_Shockwave Item_Stridebreaker_6631_Haste
3156_Shield_Burst 3156_Shield_Duration SRI_6673_Shield SRI_6673_Shield_Deactivate 3157_Zhonya_Buf BansheeVeilVFX
3190_Locket_Shield_Buff 3190_Buff_Activate 3190_Shield_Pop Item_Redemption_Cast Item_Redemption_Heal_AOE
Item_Redemption_Hit_Enemy Item_Redemption_Hit_Heal Item_Redemption_Indicator_Red Redemption_Ally_Indicator
3152_Dash_Cast 3152_Missile_Cast 3152_Missile_Projectile 3152_Missile_Impact_Tar 3152_Speed_Self 6655_Hit_Missile
6655_Hit_Missile_Tar 6655_Buff_Ready 3153_Max_Stacks 6676_Execute_Tar 3124_tar 6653_Dot_Tar 3116_Slow_Hit 3075_Tar
BlackCleaver_itm_shred BlackCleaver_Full_stack_hit_effect 3084_Goliath_Impact 3084_Goliath_Impact_Chest 3143_Active_Cas
3143_Active_Debuff 4633_Buff_Self 4633_Damage_Tar
""".split()


def main():
    pats = [re.compile(p) for p in WANT]
    w = ev.wad(f"{GAME}/Global.wad.client")
    es = w.entries.values() if isinstance(w.entries, dict) else w.entries
    out = {}
    for e in es:
        if e.size > 30_000_000:
            continue
        try:
            d = w.read_entry(e)
        except Exception:
            continue
        if d[:4] not in (b"PROP", b"PTCH"):
            continue
        try:
            bf = BinFile(d)
        except Exception:
            continue
        entries, rr, objs = {}, [], []
        hit = False
        for k, v in bf.entries.items():
            if v.cls == 0x45cd899f:
                p = to_py(v, TABLE)
                nm = p.get("particleName")
                if nm:
                    entries[k] = nm
                    objs.append(p)
                    if any(pt.search(nm) for pt in pats):
                        hit = True
            elif TABLE.get(v.cls) == "ResourceResolver":
                rr.append(ev._rr_map(to_py(v, TABLE)))
        if not hit:
            continue
        ctx = {"resolve": ev._resolver(entries, rr)}
        for p in objs:
            nm, s = ev.system(w, p, ctx)
            if s is not None and nm not in out:
                out[nm] = s
    keep = set(k for k in KEEP if k in out)
    print("missing:", [k for k in KEEP if k not in out])
    todo = list(keep)
    while todo:
        for e in out[todo.pop()]["emitters"]:
            for ch in e.get("children", []) or []:
                if ch in out and ch not in keep:
                    keep.add(ch)
                    todo.append(ch)
    out = {k: v for k, v in out.items() if k in keep}
    path = os.path.join(ev.ROOT, "data", "vfx", "items.json")
    json.dump(out, open(path, "w", encoding="utf-8"), separators=(",", ":"))
    print(f"items: {len(out)} systems")
    print("   ", sorted(out))


if __name__ == "__main__":
    main()
