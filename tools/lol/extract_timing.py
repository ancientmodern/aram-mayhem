"""[timing] Extract every timing-relevant field of a champion's spells, missiles and basic attacks from the raw bins.

Reads Champions/<Name>.wad.client data/characters/<name>/<name>.bin with the CommunityDragon hash lists (numbers_dump.py)
and writes data/timing/<name>.json:

  attack   {attackSpeed, attackSpeedRatio, castOffset, castOffsetRatio, totalTime, castTime, windupPct, attacks{name -> ...}}
  spells   {script -> {castTime, castTimeSrc, mCastTime, spellCastTime, spellTotalTime, castFrame, cantCancelWhileWindingUp,
                       useAnimatorFramerate, lineWidth, legacyMissileSpeed, missile{...}, ...}}

Effective cast time rule (checked against the wiki cast times of the whole roster): mCastTime when present, else
spellCastTime, else castFrame / 30 (animation frame at 30 fps).  Missile speeds come from mMissileSpec.movementComponent
(mSpeed / mInitialSpeed / mMinSpeed / mMaxSpeed / mAcceleration / mTravelTime), NOT from the legacy `missileSpeed` field
(Ezreal W: legacy 1200, real 1700; Veigar / Annie attacks: legacy 1100 / 1200, real 1500).

Usage: python extract_timing.py [Champion ...]
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from binfile import BinFile, to_py  # noqa: E402
from wad import Wad  # noqa: E402
from numbers_dump import load_bin_names, GAME  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
ROSTER = {"Ahri": "ahri", "Annie": "annie", "Darius": "darius", "Ezreal": "ezreal", "Garen": "garen", "Jinx": "jinx",
          "Leona": "leona", "Lux": "lux", "Malphite": "malphite", "MasterYi": "masteryi", "MissFortune": "missfortune",
          "Sona": "sona", "Veigar": "veigar", "Yasuo": "yasuo"}
CAST_FPS = 30.0
MV_KEYS = ("mSpeed", "mInitialSpeed", "mMinSpeed", "mMaxSpeed", "mAcceleration", "mTravelTime", "mTracksTarget",
           "mProjectTargetToCastRange", "mInferDirectionFromFacingIfNeeded", "mOffsetInitialTargetHeight", "mUseHeightOffsetAtEnd")


def rank_list(v):
    """First real value of a per-rank list (index 0 is rank 0 in 7-long game arrays)."""
    if isinstance(v, list):
        return v[1] if len(v) > 1 else (v[0] if v else None)
    return v


def num(v):
    return None if v is None else round(float(v), 5)


def movement(ms):
    if not isinstance(ms, dict):
        return None
    mc = ms.get("movementComponent")
    if not isinstance(mc, dict):
        return None
    out = {"type": str(mc.get("__class", "")).replace("Movement", "")}
    for k in MV_KEYS:
        if k in mc:
            out[k[1:] if k.startswith("m") else k] = mc[k] if isinstance(mc[k], bool) else num(mc[k])
    # any other scalar param (circle / parametric movements): keep numbers
    for k, v in mc.items():
        if k not in MV_KEYS and k != "__class" and isinstance(v, (int, float)) and not isinstance(v, bool):
            out[k] = num(v)
    out["width"] = num(ms.get("mMissileWidth"))
    return out


def cast_time(sp):
    m = sp.get("mCastTime")
    s = sp.get("spellCastTime")
    f = sp.get("castFrame")
    if m is not None:
        return float(m), "mCastTime"
    if s is not None:
        return float(s), "spellCastTime"
    if f is not None:
        return float(f) / CAST_FPS, "castFrame/30"
    return None, ""


def spell_timing(sobj):
    sp = sobj.get("mSpell")
    if not isinstance(sp, dict):
        return None
    ct, src = cast_time(sp)
    out = {
        "castTime": num(ct), "castTimeSrc": src,
        "mCastTime": num(sp.get("mCastTime")), "spellCastTime": num(sp.get("spellCastTime")),
        "spellTotalTime": num(sp.get("spellTotalTime")), "castFrame": num(sp.get("castFrame")),
        "cantCancelWhileWindingUp": sp.get("mCantCancelWhileWindingUp"),
        "useAnimatorFramerate": sp.get("useAnimatorFramerate"),
        "autoattackCastTime": sp.get("mUseAutoattackCastTimeData") is not None,
        "lineWidth": num(sp.get("mLineWidth")),
        "castRange": num(rank_list(sp.get("CastRange") or sp.get("castRangeValues", {}).get("values"))),
        "castRangeDisplayOverride": num(rank_list(sp.get("castRangeDisplayOverride"))),
        "castRadius": num(rank_list(sp.get("castRadius"))),
        "castConeAngle": num(sp.get("castConeAngle")),
        "legacyMissileSpeed": num(sp.get("missileSpeed")),
        "channelDuration": num(rank_list(sp.get("mChannelDuration"))),
        "canMoveWhileChanneling": sp.get("mCanMoveWhileChanneling"),
        "cantCancelWhileChanneling": sp.get("mCantCancelWhileChanneling"),
        "channelIsInterruptedByAttacking": sp.get("mChannelIsInterruptedByAttacking"),
        "channelIsInterruptedByDisables": sp.get("mChannelIsInterruptedByDisables"),
        "overrideAttackTime": sp.get("mOverrideAttackTime"),
        "turnSpeedScalar": num(sp.get("mTurnSpeedScalar")),
        "animation": sp.get("mAnimationName") or None,
        "missile": movement(sp.get("mMissileSpec")),
    }
    return {k: v for k, v in out.items() if v is not None and v != ""}


def extract(alias, names):
    low = ROSTER[alias]
    w = Wad(f"{GAME}/Champions/{alias}.wad.client")
    bf = BinFile(w.read(f"data/characters/{low}/{low}.bin"))
    ents = {}
    for k, v in bf.entries.items():
        ents[k] = to_py(v, names)
    spells = {}
    rec = None
    for k, e in ents.items():
        if not isinstance(e, dict):
            continue
        if e.get("__class") == "SpellObject":
            t = spell_timing(e)
            if t is not None and e.get("mScriptName"):
                spells[e["mScriptName"]] = t
        elif e.get("__class") == "CharacterRecord":
            rec = e
    ba = rec.get("basicAttack") or {}

    def mod(key):
        v = rec.get(key)
        return v.get("BaseValue") if isinstance(v, dict) else v

    attack = {
        "attackSpeed": num(mod("attackSpeedModifiable")), "attackSpeedRatio": num(mod("attackSpeedRatioModifiable")),
        "castOffset": num(ba.get("mAttackDelayCastOffsetPercent")),
        "castOffsetRatio": num(ba.get("mAttackDelayCastOffsetPercentAttackSpeedRatio")),
        "totalTime": num(ba.get("mAttackTotalTime")), "castTime": num(ba.get("mAttackCastTime")),
        "attackRange": num(mod("attackRangeModifiable")),
    }
    if attack["castTime"] and attack["totalTime"]:
        attack["windupPct"] = round(attack["castTime"] / attack["totalTime"], 5)
    else:
        attack["windupPct"] = round(0.3 + (attack["castOffset"] or 0.0), 5)
    atks = {}
    slots = [rec.get("basicAttack")] + list(rec.get("ExtraAttacks") or []) + list(rec.get("critAttacks") or [])
    names_seen = []
    for s in slots:
        if isinstance(s, dict) and s.get("mAttackName"):
            names_seen.append(s["mAttackName"])
    for n in names_seen + [n for n in spells if n.startswith((alias + "BasicAttack", alias + "CritAttack"))]:
        if n in spells and n not in atks:
            t = spells[n]
            atks[n] = {"speed": (t.get("missile") or {}).get("Speed"),
                       "legacySpeed": t.get("legacyMissileSpeed"),
                       "castFrameTime": round(t["castFrame"] / CAST_FPS, 5) if t.get("castFrame") else None}
    attack["attacks"] = atks
    out = {"alias": alias, "attack": attack, "spells": spells}
    path = os.path.join(ROOT, "data", "timing", f"{low}.json")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, indent=1, sort_keys=True)
        f.write("\n")
    print(alias, "spells", len(spells), "attack", {k: v for k, v in attack.items() if k != "attacks"})


if __name__ == "__main__":
    names = load_bin_names()
    for a in (sys.argv[1:] or ROSTER.keys()):
        extract(a, names)
