"""Extract League animation-graph + attack/spell timing data for the runtime animation driver.

Writes data/anim/<alias>.json with:
  clips   : League clip name -> node (atomic clip mapped to the exported .glb clip name, selectors with
            probabilities, sequencers, parallel, condition-float/bool nodes with their updater, events)
  blends  : "from>to" -> blend seconds, or {"clip": transition clip}   ("*" = any)
  attacks / crits : CharacterRecord basic/extra/crit attacks with League timing + missile start bone
  spells  : Q/W/E/R spell animation names, castFrame, mCastTime, channel, missile start bone
  stats   : misc CharacterRecord numbers (collision radii, base attack time, ...)

Usage:
  python extract_anim.py               # roster + Howling Abyss minions
  python extract_anim.py Ezreal Ahri   # selection
"""
import json
import os
import sys

import xxhash

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "ref"))
from lolbin import read_bin, fnv1a32, BinStruct  # noqa: E402
from export_character import vocabulary, open_wads, BinSet, ROSTER  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "data", "anim")
MINIONS = ["HA_OrderMinionMelee", "HA_ChaosMinionMelee", "HA_OrderMinionRanged", "HA_ChaosMinionRanged",
           "HA_OrderMinionSiege", "HA_ChaosMinionSiege", "HA_OrderMinionSuper", "HA_ChaosMinionSuper"]

CLASS = {fnv1a32(n): n for n in (
    "AtomicClipData SelectorClipData SequencerClipData ParallelClipData ConditionFloatClipData "
    "ConditionBoolClipData ParametricClipData TimeBlendData TransitionClipBlendData ParticleEventData "
    "SoundEventData SubmeshVisibilityEventData FadeEventData EnableLookAtEventData StopAnimationEventData "
    "ConformToPathEventData IdleParticlesVisibilityEventData JointSnapEventData LockRootOrientationEventData "
    "FaceTargetEventData "
    "MoveSpeedParametricUpdater AttackSpeedParametricUpdater IsMovingParametricUpdater IsHomeguardParametricUpdater "
    "IsInTerrainParametricUpdater IsAllyParametricUpdater IsRangedParametricUpdater FacingParametricUpdater "
    "TurnAngleParametricUpdater TurnAngleRemainingParametricUpdater MovementDirectionParametricUpdater "
    "ParBarPercentParametricUpdater SkinScaleParametricUpdater LogicDriverFloatParametricUpdater "
    "LogicDriverBoolParametricUpdater IsTurningParametricUpdater LookAtSpellTargetAngleParametricUpdater "
    "LookAtSpellTargetDistanceParametricUpdater LookAtInterestAngleParametricUpdater "
    "LookAtInterestDistanceParametricUpdater DisplacementParametricUpdater HealthPercentParametricUpdater "
    "SpellRankParametricUpdater SpellRankIntParametricUpdater EquippedGearParametricUpdater "
    "IsMovingOrTurningParametricUpdater StatParametricUpdater BuffCounterParametricUpdater").split()}

EXTRA_NAMES = """Idle_In Idle1_In Idle_Out Run_In Run_Out Run_In_Base Run_Out_Base Run_Haste_In Run_Haste_Out Run_Fast_In
Run_Out_Fast Run_Exit Run_Stop Run_Start Run_ToIdle Idle_ToRun Turn_L Turn_R Turn_Left_90 Turn_Right_90 Turn_180
Attack1_ToIdle Attack2_ToIdle Attack3_ToIdle Attack4_ToIdle Crit_ToIdle Attack1_ToRun Attack2_ToRun Attack3_ToRun
Crit_ToRun Spell1_ToIdle Spell2_ToIdle Spell3_ToIdle Spell4_ToIdle Spell1_ToRun Spell2_ToRun Spell3_ToRun Spell4_ToRun
Attack Attack_Base Idle Run Death Death_Base Death_Loop Death_Idle Respawn Respawn_Base Recall Recall_Winddown Recall_Leadout
Dance Dance_In Dance_Loop Taunt Laugh Joke Channel Channel_Wndup Channel_Windup Idle_Variant Idle1_Variant
Idle_Variant1 Idle_Variant2 Idle_Variant3 Idle1_Var1 Idle1_Var2 Idle_Combat Idle_Haste Run_Haste Run_Fast Run_Slow
Spell1_Run Spell2_Run Spell3_Run Spell4_Run Spell1_Idle Spell2_Idle Spell3_Idle Spell4_Idle Spell4_Out Spell4_In
Attack1_Base Attack2_Base Crit_Base Idle1_Base Run_Base Run_Haste_Base Death1 Death2 Spawn Idle_Spawn
Attack_Mask Attack1_Mask Attack2_Mask Crit_Mask Attack1_Upper Attack2_Upper Crit_Upper Attack_Run Attack1_Run
Attack2_Run Crit_Run Idle_Turn Run_Turn Spell1_Upper Spell2_Upper Spell3_Upper Spell4_Upper
""".split()


def xxh(path):
    return xxhash.xxh64_intdigest(path.lower().encode("utf-8"), 0)


def h32(v):
    return f"#{v & 0xffffffff:08x}"


def file_key(v):
    if isinstance(v, str):
        return xxh(v.lower())
    return v


def glb_clip_names(char, skin, clipmap, graph_bins_char, skip_transitions=True, keep_unnamed=False):
    """Replicates export_character.py's naming so atomic clips map onto the .glb clip names."""
    cl = char.lower()
    vocab = vocabulary(char)
    folder = "base" if skin == 0 else f"skin{skin:02d}"
    key_names = {fnv1a32(v): v for v in vocab}
    path_names = {}
    for v in vocab:
        for fol in {folder, "base", f"skin{skin}"}:
            path_names[xxh(f"assets/characters/{cl}/skins/{fol}/animations/{v}.anm")] = v

    def clip_file(co):
        ard = co.get("mAnimationResourceData") if co is not None else None
        if ard is None:
            return None
        return file_key(ard.get("mAnimationFilePath"))

    def refs(v, acc):
        if isinstance(v, BinStruct):
            for _k, (_t, x) in v.fields.items():
                refs(x, acc)
        elif isinstance(v, list):
            for x in v:
                refs(x, acc)
        elif isinstance(v, dict):
            for x in v.values():
                refs(x, acc)
        elif isinstance(v, int) and v in clipmap and v not in acc:
            acc.append(v)
        return acc

    graph_names = {}

    def assign(ck, nm, depth=0):
        co = clipmap.get(ck)
        if co is None or depth > 4:
            return
        fk2 = clip_file(co)
        if fk2 is not None:
            graph_names.setdefault(fk2, nm)
            return
        rs = refs(co, [])
        if not rs:
            return
        seq = co.get("mClipNameList")
        if seq:
            last = seq[-1]
            assign(last, nm, depth + 1)
            for i, c2 in enumerate(dict.fromkeys(seq)):
                if c2 != last:
                    assign(c2, nm + ("_in" if i == 0 else f"_seq{i}"), depth + 1)
        else:
            for i, c2 in enumerate(rs):
                assign(c2, nm if i == 0 else f"{nm}_var{i + 1}", depth + 1)

    std_names = ["Idle1", "Idle2", "Idle3", "Idle4", "Idle_Base", "Idle1_Base", "Run", "Run_Base", "Run_Fast",
                 "Run_Haste", "Attack1", "Attack2", "Attack3", "Attack4", "Crit", "Crit2", "Spell1", "Spell2",
                 "Spell3", "Spell4", "Spell1A", "Spell1B", "Spell1C", "Death", "Dance", "Taunt", "Laugh", "Joke",
                 "Recall", "Channel", "Respawn", "Stunned", "KnockUp", "Spell4_Idle", "Spell4_Run", "Spell2_Idle",
                 "Spell2_Run", "Spell3_Idle", "Spell3_Run", "Spell1_Idle", "Spell1_Run", "Idle_Spell4",
                 "Run_Spell4", "Attack_Spell4", "Spell1_Dash", "Homeguard", "Run_Homeguard"]
    for sn in std_names:
        ck0 = fnv1a32(sn)
        if ck0 in clipmap:
            assign(ck0, sn.lower())
    files = {}
    for ck, co in clipmap.items():
        if co is None:
            continue
        fk = clip_file(co)
        if fk is None:
            continue
        nm = graph_names.get(fk) or path_names.get(fk) or key_names.get(ck)
        if fk in files:
            if nm and not files[fk]:
                files[fk] = nm
            continue
        files[fk] = nm
    out = {}
    used = set()
    for fk, nm in files.items():
        if not nm:
            if not keep_unnamed:
                continue
            nm = f"clip_{fk & 0xffffffff:08x}"
        if skip_transitions and any(x in nm for x in ("_toidle", "_torun", "_to_idle", "_to_run", "attack1_to",
                                                      "idle_in", "_leadin", "_lead_in")):
            continue   # transitions are not exported to the main .glb
        short = nm
        for p in (cl + "_base_", cl + "base_", cl + "_"):
            if short.startswith(p):
                short = short[len(p):]
                break
        if short in used:
            short = nm
        used.add(short)
        out[fk] = short
    return out


def spell_data(objs, name):
    """SpellObject by script name -> its SpellDataResource (mSpell)."""
    for o in objs.values():
        if o.get("mScriptName") == name:
            return o.get("mSpell"), o
    return None, None


def missile_bones(sd):
    if sd is None:
        return None, None
    ms = sd.get("mMissileSpec")
    mv = ms.get("movementComponent") if ms is not None else None
    if mv is None and ms is not None:
        for _k, (_t, x) in ms.fields.items():
            if isinstance(x, BinStruct) and x.get("mSpeed") is not None:
                mv = x
                break
    if mv is None:
        return None, None
    return mv.get("mStartBoneName"), mv.get("mTargetBoneName")


def attack_entry(a, objs, default_name=None):
    nm = a.get("mAttackName") or default_name
    sd, _ = spell_data(objs, nm) if nm else (None, None)
    sb, tb = missile_bones(sd)
    e = {
        "name": nm,
        "prob": a.get("mAttackProbability"),
        "cast_offset": a.get("mAttackDelayCastOffsetPercent"),
        "cast_offset_as_ratio": a.get("mAttackDelayCastOffsetPercentAttackSpeedRatio"),
        "total_time": a.get("mAttackTotalTime"),
        "cast_time": a.get("mAttackCastTime"),
    }
    if sd is not None:
        e.update({
            "clip": sd.get("mAnimationName"),
            "cast_frame": sd.get("castFrame"),
            "missile_speed": sd.get("missileSpeed"),
            "start_bone": sb,
            "target_bone": tb,
            "hit_bone": sd.get("mHitBoneName"),
            "use_attack_cast_time": sd.get("mUseAutoattackCastTime"),
        })
    return {k: v for k, v in e.items() if v is not None}


def spell_entry(nm, objs):
    sd, _ = spell_data(objs, nm)
    if sd is None:
        return {"name": nm}
    sb, tb = missile_bones(sd)

    def first(v):
        if isinstance(v, list):
            return v[0] if v else None
        return v
    e = {
        "name": nm,
        "clip": sd.get("mAnimationName"),
        "loop": sd.get("mAnimationLoopName"),
        "winddown": sd.get("mAnimationWinddownName"),
        "leadout": sd.get("mAnimationLeadOutName"),
        "cast_frame": sd.get("castFrame"),
        "cast_time": sd.get("mCastTime"),
        "channel": first(sd.get("mChannelDuration")),
        "missile_speed": sd.get("missileSpeed"),
        "start_bone": sb,
        "target_bone": tb,
        "hit_bone": sd.get("mHitBoneName"),
    }
    return {k: v for k, v in e.items() if v is not None}


def clip_node(co, name_of, glb_of, x_of=None):
    cls = CLASS.get(co.class_hash, f"{co.class_hash:08x}")
    n = {"type": cls.replace("ClipData", "")}
    fl = co.get("mFlags")
    if fl is not None:
        n["flags"] = fl
    tr = co.get("mTrackDataName")
    if tr is not None:
        n["track"] = name_of(tr)
    mk = co.get("mMaskDataName")
    if mk is not None:
        n["mask"] = name_of(mk)
    sg = co.get("mSyncGroupDataName")
    if sg is not None:
        n["sync"] = name_of(sg)
    td = co.get("mTickDuration")
    if td is not None:
        n["tick"] = td
    ard = co.get("mAnimationResourceData")
    if ard is not None:
        fk = file_key(ard.get("mAnimationFilePath"))
        n["anim"] = glb_of.get(fk)
        if n["anim"] is None and x_of and x_of.get(fk):
            n["xanim"] = "x/" + x_of[fk]   # companion data/anim/clips/<alias>.glb
        n["file"] = f"{fk:016x}" if isinstance(fk, int) else None
    sel = co.get("mSelectorPairDataList")
    if sel:
        n["pairs"] = [[name_of(p.get("mClipName")), p.get("mProbability", 1.0)] for p in sel]
    seq = co.get("mClipNameList")
    if seq:
        n["list"] = [name_of(x) for x in seq]
    cf = co.get("mConditionFloatPairDataList")
    if cf:
        n["pairs"] = [[name_of(p.get("mClipName")), p.get("mValue", 0.0),
                       p.get("mHoldAnimationToHigher"), p.get("mHoldAnimationToLower")] for p in cf]
    t = co.get("mTrueConditionClipName")
    if t is not None:
        n["true"] = name_of(t)
    f = co.get("mFalseConditionClipName")
    if f is not None:
        n["false"] = name_of(f)
    up = co.get("updater")
    if isinstance(up, BinStruct):
        n["updater"] = CLASS.get(up.class_hash, f"{up.class_hash:08x}").replace("ParametricUpdater", "")
    for k in ("mChangeAnimationMidPlay", "mPlayAnimChangeFromBeginning", "mChildAnimDelaySwitchTime",
              "mDontStompTransitionClip"):
        v = co.get(k)
        if v is not None:
            n[k[1].lower() + k[2:]] = v
    ev = co.get("mEventDataMap")
    if ev:
        evs = []
        for _ek, e in ev.items():
            if e is None:
                continue
            ecls = CLASS.get(e.class_hash, f"{e.class_hash:08x}").replace("EventData", "")
            d = {"type": ecls, "start": e.get("mStartFrame", 0.0)}
            if e.get("mEndFrame") is not None:
                d["end"] = e.get("mEndFrame")
            if ecls == "Particle":
                d["effect"] = name_of(e.get("mEffectKey")) if isinstance(e.get("mEffectKey"), int) else e.get("mEffectKey")
                pl = e.get("mParticleEventDataPairList") or []
                d["bones"] = [p.get("mBoneName") for p in pl if p.get("mBoneName")]
            elif ecls == "Sound":
                d["sound"] = e.get("mSoundName")
            elif ecls == "SubmeshVisibility":
                d["show"] = e.get("mShowSubmeshList")
                d["hide"] = e.get("mHideSubmeshList")
            elif ecls == "Fade":
                d["alpha"] = e.get("mTargetAlpha")
                d["time"] = e.get("mTimeToFade")
            evs.append({k: v for k, v in d.items() if v is not None})
        if evs:
            n["events"] = sorted(evs, key=lambda x: x.get("start", 0.0))
    return n


def extract(char, skin=0):
    wads = open_wads(char)
    cl = char.lower()
    rec_bins = BinSet(wads, f"data/characters/{cl}/{cl}.bin")
    objs = rec_bins.objects
    rec = None
    for o in objs.values():
        if o.get("basicAttack") is not None or o.get("mCharacterName") is not None:
            if o.get("basicAttack") is not None:
                rec = o
                break
            rec = rec or o
    out = {"alias": char, "attacks": [], "crits": [], "spells": [], "stats": {}}
    names = set(EXTRA_NAMES) | vocabulary(char)
    if rec is not None:
        ba = rec.get("basicAttack")
        if ba is not None:
            out["attacks"].append(attack_entry(ba, objs, char + "BasicAttack"))
        for a in rec.get("extraAttacks") or []:
            out["attacks"].append(attack_entry(a, objs))
        for i, a in enumerate(rec.get("critAttacks") or []):
            out["crits"].append(attack_entry(a, objs, char + "CritAttack" if i == 0 else None))
        for i, sn in enumerate(rec.get("spellNames") or []):
            if sn:
                se = spell_entry(sn.split("/")[-1], objs)
                se["slot"] = i
                out["spells"].append(se)
        for k in ("pathfindingCollisionRadius", "overrideGameplayCollisionRadius", "selectionRadius",
                  "selectionHeight", "attackSpeed", "attackSpeedRatio", "baseMoveSpeed", "attackRange",
                  "healthBarHeight"):
            v = rec.get(k)
            if v is not None:
                out["stats"][k] = v
        for e in out["attacks"] + out["crits"] + out["spells"]:
            for k in ("clip", "loop", "winddown", "leadout"):
                if e.get(k):
                    names.add(e[k])
    # ---- animation graph
    sk_bins = BinSet(wads, f"data/characters/{cl}/skins/skin{skin}.bin")
    skin_obj = sk_bins.get(f"Characters/{char}/Skins/Skin{skin}")
    if skin_obj is None:
        for o in sk_bins.objects.values():
            if o.get("skinMeshProperties") is not None:
                skin_obj = o
                break
    agl = skin_obj.get("skinAnimationProperties") if skin_obj is not None else None
    graph = sk_bins.get(agl.get("animationGraphData")) if agl is not None else None
    if graph is None:
        print("  no graph for", char)
        return out
    clipmap = graph.get("mClipDataMap") or {}
    for nm in list(names):
        for p in ("", char + "_", char + "_Base_"):
            names.add(p + nm)
    by_hash = {}
    for nm in names:
        by_hash.setdefault(fnv1a32(nm), nm)
    # track / mask / sync names
    for nm in ("Default", "Base", "Upper", "Lower", "UpperBody", "LowerBody", "Additive", "Override", "Face",
               "Attack", "Spell", "Run", "Idle", "Head", "Torso", "Legs", "Arms", "Weapon", "Root", "Mask"):
        by_hash.setdefault(fnv1a32(nm), nm)

    def name_of(h):
        if h is None:
            return None
        if isinstance(h, str):
            return h
        return by_hash.get(h, h32(h))
    glb_of = glb_clip_names(char, skin, clipmap, None)
    x_of = glb_clip_names(char, skin, clipmap, None, skip_transitions=False, keep_unnamed=True)
    clips = {}
    for ck, co in clipmap.items():
        if co is None:
            continue
        clips[name_of(ck)] = clip_node(co, name_of, glb_of, x_of)
    out["clips"] = clips
    blends = {}
    for bk, bd in (graph.get("mBlendDataTable") or {}).items():
        if bd is None:
            continue
        fr, to = (bk >> 32) & 0xffffffff, bk & 0xffffffff
        key = f"{name_of(fr) if fr else '*'}>{name_of(to) if to else '*'}"
        bc = CLASS.get(bd.class_hash, "")
        if bc == "TimeBlendData":
            blends[key] = bd.get("mTime", 0.0)
        elif bc == "TransitionClipBlendData":
            blends[key] = {"clip": name_of(bd.get("mClipName"))}
    out["blends"] = blends
    tracks = {}
    for tk, td in (graph.get("mTrackDataMap") or {}).items():
        if td is None:
            continue
        tracks[name_of(tk)] = {"priority": td.get("mPriority"), "blend_mode": td.get("mBlendMode"),
                               "weight": td.get("mBlendWeight")}
    out["tracks"] = tracks
    out["masks"] = sorted(name_of(k) for k in (graph.get("mMaskDataMap") or {}))
    out["cascade_blend"] = graph.get("mCascadeBlendValue")
    out["use_cascade_blend"] = graph.get("mUseCascadeBlend")
    return out


def main():
    args = sys.argv[1:]
    chars = args or (ROSTER + MINIONS)
    os.makedirs(OUT, exist_ok=True)
    for ch in chars:
        try:
            d = extract(ch)
        except Exception as ex:
            import traceback
            traceback.print_exc()
            print("!! failed", ch, ex)
            continue
        p = os.path.join(OUT, ch.lower() + ".json")
        with open(p, "w", newline="\n") as f:
            json.dump(d, f, indent=1)
        nclip = len(d.get("clips", {}))
        unres = sum(1 for k in d.get("clips", {}) if k.startswith("#"))
        print(f"{ch}: clips={nclip} (unnamed {unres}) blends={len(d.get('blends', {}))} "
              f"attacks={[(a.get('name'), a.get('clip'), a.get('start_bone')) for a in d['attacks']]}")


if __name__ == "__main__":
    main()
