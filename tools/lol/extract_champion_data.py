"""Extract authentic champion gameplay data (stats + spell numbers + tooltips)
from Champions/<Name>.wad.client into data/champions/<name>_game.json.

Usage: python extract_champion_data.py [Champion ...]
"""
import json
import os
import re
import sys

from binfile import BinFile, BinObject, BinLink, BinHash, fnv1a
from rst import StringTable
from wad import Wad
from extract_client import ROSTER, ROOT

GAME = "D:/Riot Games/League of Legends/Game/DATA/FINAL"

# CharacterRecord stat field hashes (new-style wrapped {b35aa769: value})
STAT_FIELDS = {
    0x8662cf12: "base_hp", 0x4d37af28: "hp_per_level", 0x9eedebad: "base_hp_regen", 0x913157bb: "hp_regen_per_level",
    0x4af40dc3: "base_ad", 0xe2b5d80d: "ad_per_level", 0xea6100d5: "base_armor", 0x18956a21: "armor_per_level",
    0x33c0bf27: "base_mr", 0x01262a25: "mr_per_level", 0xe62d9d92: "base_ms", 0x7bd4b298: "attack_range",
    0x836cc82a: "attack_speed", 0x4f89c991: "attack_speed_ratio", 0xb9f2b365: "attack_speed_per_level",
}
RES_FIELDS = {0x726ee5cd: "base", 0x6216bf7b: "per_level", 0xc4ab3550: "regen", 0x3a509002: "regen_per_level"}
WRAP = 0xb35aa769
STAT_NAMES = {0: "AP", 1: "Armor", 2: "AD", 3: "AttackSpeed", 5: "MR", 6: "MoveSpeed", 7: "CritChance", 8: "CritDamage",
              11: "MaxHealth", 12: "CurrentHealth", 13: "MissingHealth", 15: "LifeSteal", 18: "Lethality"}
FORMULA_NAMES = {0: "total", 1: "base", 2: "bonus"}
VALUES = 0x34474c3b


def unwrap(v):
    if isinstance(v, BinObject):
        return v.get(WRAP, v.fields.get(VALUES))
    return v


_names = {}


def name_of(h):
    return _names.get(int(h), f"#{int(h):08x}")


def formula(part, dv_names):
    """Convert a calculation part into a readable string."""
    if not isinstance(part, BinObject):
        return str(part)
    cls = part.cls
    cn = _names.get(cls, f"{cls:08x}")
    g = part.get
    if cn == "NamedDataValueCalculationPart":
        return dv_names.get(int(g("mDataValue") or 0), name_of(g("mDataValue") or 0))
    if cn == "StatByCoefficientCalculationPart":
        st = STAT_NAMES.get(g("mStat") or 0, f"stat{g('mStat')}")
        f = FORMULA_NAMES.get(g("mStatFormula") or 0, "")
        return f"{g('mCoefficient') or 0:g}*{'' if f == 'total' else f}{st}"
    if cn == "StatByNamedDataValueCalculationPart":
        st = STAT_NAMES.get(g("mStat") or 0, f"stat{g('mStat')}")
        f = FORMULA_NAMES.get(g("mStatFormula") or 0, "")
        dvn = dv_names.get(int(g("mDataValue") or 0), name_of(g("mDataValue") or 0))
        return f"{dvn}*{'' if f == 'total' else f}{st}"
    if cn == "NumberCalculationPart":
        return f"{g('mNumber') or 0:g}"
    if cn == "ByCharLevelInterpolationCalculationPart":
        return f"lerpByLevel({g('mStartValue') or 0:g}->{g('mEndValue') or 0:g})"
    if cn == "ByCharLevelBreakpointsCalculationPart":
        return f"byLevelBreakpoints(L1={g('mLevel1Value') or 0:g})"
    if cn == "SumOfSubPartsCalculationPart":
        return "(" + " + ".join(formula(p, dv_names) for p in (g("mSubparts") or [])) + ")"
    if cn == "ProductOfSubPartsCalculationPart":
        return "(" + formula(g("mPart1"), dv_names) + " * " + formula(g("mPart2"), dv_names) + ")"
    if cn == "EffectValueCalculationPart":
        return f"Effect{g('mEffectIndex')}"
    return cn


def calc_to_str(calc, dv_names):
    if not isinstance(calc, BinObject):
        return None
    cn = _names.get(calc.cls, f"{calc.cls:08x}")
    parts = calc.get("mFormulaParts") or []
    s = " + ".join(formula(p, dv_names) for p in parts)
    mult = calc.get("mMultiplier")
    if isinstance(mult, BinObject):
        s = f"({s}) * {formula(mult, dv_names)}"
    if calc.get("mDisplayAsPercent"):
        s += "  [as %]"
    if cn != "GameCalculation":
        s = f"{cn}: {s}"
    return s


def first_or_list(v):
    if isinstance(v, list) and v and all(isinstance(x, (int, float)) for x in v):
        if all(abs(x - v[0]) < 1e-6 for x in v):
            return round(v[0], 4)
        return [round(x, 4) for x in v]
    return v


def spell_info(sobj, st):
    sp = sobj.get("mSpell")
    out = {"script": sobj.get("mScriptName")}
    if not isinstance(sp, BinObject):
        return out
    dvs = {}
    dv_names = {}
    for dv in sp.get("DataValues") or sp.get("mDataValues") or []:
        if isinstance(dv, BinObject):
            n = dv.get("name") or dv.get(0x8d39bde6)
            vals = dv.get(VALUES)
            if n is not None:
                dvs[n] = first_or_list([round(x, 4) for x in (vals or [])])
                dv_names[fnv1a(n)] = n
    out["data_values"] = dvs
    calcs = {}
    for k, c in (sp.get("mSpellCalculations") or {}).items():
        calcs[name_of(k)] = calc_to_str(c, dv_names)
    if calcs:
        out["calcs"] = calcs
    for key in ("cooldownTime", "mana", "castRange", "castRangeDisplayOverride", "castRadius", "castConeAngle",
                "castConeDistance", "missileSpeed", "mLineWidth", "mCastTime", "mChannelDuration", "mAnimationName",
                "mMaxAmmo", "mAmmoRechargeTime", "mAlternateName"):
        v = sp.get(key)
        if v is not None:
            out[key] = first_or_list(v)
    tip = sp.get("mClientData")
    if isinstance(tip, BinObject):
        td = tip.get("mTooltipData")
        if isinstance(td, BinObject):
            lk = td.get("mLocKeys") or {}
            for kk in ("keyName", "keyTooltip", "keySummary"):
                key = lk.get(kk)
                if key:
                    s = st.get(key)
                    if s:
                        out[kk.replace("key", "").lower()] = s
    return out


def extract(alias, st):
    w = Wad(f"{GAME}/Champions/{alias}.wad.client")
    low = alias.lower()
    bf = BinFile(w.read(f"data/characters/{low}/{low}.bin"))
    cr = next((o for o in bf.entries.values() if _names.get(o.cls) == "CharacterRecord"), None)
    stats = {}
    for h, n in STAT_FIELDS.items():
        if h in cr.fields:
            stats[n] = round(unwrap(cr.fields[h]), 4)
    res = cr.get("primaryAbilityResource")
    if isinstance(res, BinObject):
        stats["resource_type"] = res.get("arType", 0)
        for h, n in RES_FIELDS.items():
            if h in res.fields:
                stats["mana_" + n] = round(unwrap(res.fields[h]), 4)
    for k in ("critDamageMultiplier", "acquisitionRange", "selectionHeight", "selectionRadius",
              "pathfindingCollisionRadius", "overrideGameplayCollisionRadius", "healthBarHeight"):
        v = cr.get(k)
        if v is not None:
            stats[k] = v
    ba = cr.get("basicAttack")
    if isinstance(ba, BinObject):
        stats["attack_cast_offset"] = ba.get("mAttackDelayCastOffsetPercent", 0.0)
        stats["attack_total_time"] = ba.get("mAttackTotalTime")
        stats["attack_cast_time"] = ba.get("mAttackCastTime")
    by_script = {}
    for key, o in bf.entries.items():
        if _names.get(o.cls) == "SpellObject" and isinstance(o.get("mSpell"), BinObject):
            by_script[o.get("mScriptName")] = spell_info(o, st)
    main = []
    for link in cr.get("spells") or []:
        o = bf.entries.get(int(link))
        if o is not None:
            main.append(o.get("mScriptName"))
    passive_key = cr.get(0xe96f0412)
    passive = bf.entries.get(int(passive_key)).get("mScriptName") if passive_key and bf.entries.get(int(passive_key)) else None
    out = {
        "alias": alias,
        "name": st.get(cr.get("name") or "") or alias,
        "stats": stats,
        "spell_slots": dict(zip(["Q", "W", "E", "R"], main)),
        "passive": passive,
        "passive_name": st.get(cr.get("passiveName") or ""),
        "passive_desc": st.get(cr.get(0xa2bea925) or ""),
        "spells": by_script,
    }
    path = os.path.join(ROOT, "data", "champions", f"{low}_game.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    json.dump(out, open(path, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
    print(alias, stats.get("base_hp"), stats.get("base_ad"), stats.get("attack_range"), "spells", len(by_script), out["spell_slots"])


if __name__ == "__main__":
    from names import TABLE
    _names.update(TABLE)
    st = StringTable(Wad(f"{GAME}/Localized/Global.en_US.wad.client").read("data/menu/en_us/lol.stringtable"))
    for alias in (sys.argv[1:] or ROSTER.keys()):
        try:
            extract(alias, st)
        except Exception as ex:
            import traceback
            traceback.print_exc()
            print("!! failed", alias, ex)
