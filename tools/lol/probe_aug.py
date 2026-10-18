import json, sys
from wad import Wad
from binfile import BinFile, fnv1a, to_py
G = "D:/Riot Games/League of Legends/Game/DATA/FINAL"
m12 = Wad(G + "/Maps/Shipping/Map12.wad.client")
bf = BinFile(m12.read(0x410b3796f165ef3e))
print('version', bf.version, 'entries', len(bf.entries), 'links', bf.links[:5])
NAMES = ["mDataValues","mName","mValues","mSpell","mSpellCalculations","mScriptName","mBuffName","mClientData","mTooltipData",
 "DataValues","mFormula","mFormulaParts","mCoefficient","mDataValue","mMultiplier","mStyleTag","mPrecision","mDisplayAsPercent",
 "mEffectAmount","mCoefficient","mStartValue","mByCharLevelFormula", "rootSpell","RootSpell","AugmentData","NameTra","DescriptionTra",
 "keyName","keyTooltip","keySummary","mObjectName","mLocKeys","mLists","mFloats","mFormat","mAnimationName","mCastTime","cooldownTime",
 "mCooldownTime","castRange","mAffectsStatusFlags","mAffectsTypeFlags","SpellObject","SpellDataResource","GameCalculation","NamedDataValueCalculationPart",
 "ByCharLevelInterpolationCalculationPart","StatByCoefficientCalculationPart","NumberCalculationPart","mNumber","mStat","mStatFormula",
 "mDataValue","ProductOfSubPartsCalculationPart","SumOfSubPartsCalculationPart","mSubparts","mPart1","mPart2","mModifiedGameCalculation",
 "mBuff","mScript","mSpells","mParticle","mIcon","mImgIconName","mAlternateName","augmentNameId","rarity","AugmentSmallIconPath","AugmentLargeIconPath",
 "mClientData","mTooltipData","mLocKeys","keyTooltipExtendedBelowLine","mFloatVars","mAiData"]
names = {fnv1a(n): n for n in NAMES}
target = fnv1a("Maps/ModeSpecificData/Augments/ARAM_GetExcited")
e = bf.entries.get(target)
print('found', e)
from collections import Counter
print(Counter(f"{o.cls:08x}" for o in bf.entries.values()).most_common(10))
if e:
    print(json.dumps(to_py(e, names), indent=1)[:6000])
sp = bf.entries.get(int(e.get('RootSpell')))
print('ROOT SPELL', sp)
if sp: print(json.dumps(to_py(sp, names), indent=1)[:5000])
