"""Extract League's item data for ARAM / ARAM Mayhem (map 12, mode ARAM + Kiwi) into data/items/items.json.

Sources (all from the local client install, no guessing):
  * Global.wad.client      items bin (ItemData / ItemGroup / ItemRecommendationOverrideSet / "Characters/<X>" Champion entries)
  * Maps/Shipping/Map12    GameModeMapData for ARAM + Kiwi -> item lists, quick-buy panels, item shop data
  * Localized/Global.en_US lol.stringtable -> names, tooltips (GeneratedTip_Item_<id>_TooltipShop), nicknames
  * rcp-be-lol-game-data   items.json (cross-check of names / recipes only)

Output data/items/items.json:
  {
    "version": "<game version>",
    "items": { "<id>": { name, price, total, from[], into[], sell, stats{engine keys}, raw_stats{League names}, tier, classes[],
                          categories[], groups[{id,max}], max_stack, consumed, clickable, req_level, restricted, nick[],
                          brief, cooldown, data{...}, text[...], text_ranged[...] } },
    "shop":  { "quick_consumables": [...], "quick_boots": [...], "starters": [...], "store": [...] },
    "recs":  { "<ChampAlias>": { "starting": [[ids]], "ranges": [{"items": [...], "max": n}] } }
  }

Usage: python tools/lol/extract_items.py            (needs tools/extracted/cdhash/hashes.*.txt; fetched on demand)
"""
import json
import os
import re
import sys
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from wad import Wad  # noqa: E402
from binfile import BinFile, BinObject, to_py, fnv1a  # noqa: E402
from rst import StringTable  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
GAME = "D:/Riot Games/League of Legends/Game/DATA/FINAL"
PLUGINS = "D:/Riot Games/League of Legends/Plugins"
HASHDIR = os.path.join(ROOT, "tools", "extracted", "cdhash")
OUT = os.path.join(ROOT, "data", "items", "items.json")
ITEMS_BIN_HASH = 0x1D720F4F42640C18   # Global.wad: the combined ItemData bin
CHAMPS_BIN_HASH = 0xB3CC3B6AC3EA0472  # Global.wad: "Characters/<Champ>" Champion records (item recommendation override links)
MODE_KEYS = ("ARAM", "Kiwi")          # DataValuesModeOverride keys applied in order (Mayhem = Kiwi, built on ARAM)

# League stat field (ItemData) -> engine stat key (see src/core/stats.gd)
STAT_FIELDS = {
    "mFlatHPPoolMod": "hp", "flatMPPoolMod": "mana", "mFlatPhysicalDamageMod": "ad", "mFlatMagicDamageMod": "ap",
    "mFlatArmorMod": "armor", "mFlatSpellBlockMod": "mr", "mPercentAttackSpeedMod": "as", "mFlatCritChanceMod": "crit",
    "mFlatCritDamageMod": "crit_dmg", "mFlatMovementSpeedMod": "ms", "mPercentMovementSpeedMod": "ms%",
    "mAbilityHasteMod": "ah", "mPercentLifeStealMod": "lifesteal", "PercentOmniVampMod": "omnivamp",
    "PhysicalLethality": "lethality", "mFlatMagicPenetrationMod": "magic_pen", "mPercentMagicPenetrationMod": "magic_pen%",
    "mPercentArmorPenetrationMod": "armor_pen%", "mFlatHPRegenMod": "hp_regen", "mPercentBaseHPRegenMod": "hp_regen%",
    "flatMPRegenMod": "mana_regen", "percentBaseMPRegenMod": "mana_regen%", "mPercentHealingAmountMod": "heal_power",
    "mPercentTenacityItemMod": "tenacity", "mPercentSlowResistMod": "slow_resist", "mFlatAttackRangeMod": "range",
}
# mItemAttributes list values -> shop class filter
CLASS_BITS = {1: "fighter", 2: "marksman", 4: "assassin", 8: "tank", 16: "mage", 32: "support"}
# calc stat enum (StatByCoefficientCalculationPart.mStat) -> tooltip label
CALC_STATS = {0: "AP", 1: "Armor", 2: "AD", 3: "Attack Speed", 5: "Magic Resist", 6: "Move Speed", 7: "Crit Chance",
              8: "Crit Damage", 11: "Max Health", 12: "Health", 13: "Missing Health", 15: "Life Steal", 18: "Lethality"}


# --------------------------------------------------------------------------- names / strings
def load_names():
    names = {}
    need = ["hashes.binfields.txt", "hashes.bintypes.txt", "hashes.binentries.txt", "hashes.binhashes.txt"]
    os.makedirs(HASHDIR, exist_ok=True)
    for fn in need:
        p = os.path.join(HASHDIR, fn)
        if not os.path.exists(p):
            url = "https://raw.githubusercontent.com/CommunityDragon/Data/master/hashes/lol/" + fn
            print("fetching", url)
            urllib.request.urlretrieve(url, p)
        with open(p, encoding="utf-8") as f:
            for ln in f:
                parts = ln.rstrip("\n").split(" ", 1)
                if len(parts) == 2:
                    names[int(parts[0], 16)] = parts[1]
    return names


def link_id(s):
    """'link:Items/3031' / 'hash:Items/3031' -> 3031 (or None)."""
    m = re.search(r"Items/(\d+)$", s or "")
    return int(m.group(1)) if m else None


# --------------------------------------------------------------------------- tooltip text
class Resolver:
    def __init__(self, st, item, data, calcs):
        self.st, self.item, self.data, self.calcs = st, item, data, calcs
        self.range_mode = 1   # 1 melee, 2 ranged (ChampRange conditional)

    # ---- numbers
    @staticmethod
    def fmt(v, pct=False):
        if pct:
            v = v * 100.0
        if abs(v - round(v)) < 0.005:
            return str(int(round(v)))
        return ("%.2f" % v).rstrip("0").rstrip(".")

    def stat_value(self, name):
        it = self.item
        for key in (name, "m" + name, name[0].lower() + name[1:], "m" + name[0].upper() + name[1:]):
            if key in it and isinstance(it[key], (int, float)):
                return float(it[key])
        return None

    def calc_eval(self, name, depth=0):
        """-> (const_value | None, [scaling strings], is_pct)"""
        if depth > 6:
            return None, [], False
        c = self.calcs.get(name)
        if c is None:
            c = self.calcs.get("hash:" + name)
        if c is None:
            return None, [], False
        return self.calc_obj(c, depth)

    def calc_obj(self, c, depth=0):
        cls = c.get("__class", "")
        pct = bool(c.get("mDisplayAsPercent"))
        if cls == "GameCalculationConditional":
            ranged = self.range_mode == 2
            key = c.get("mConditionalGameCalculation" if ranged else "mDefaultGameCalculation")
            return self.calc_ref(key, depth + 1)
        if cls == "GameCalculationModified":
            base = c.get("mModifiedGameCalculation")
            k, sc, p = self.calc_ref(base, depth + 1)
            mult = c.get("mMultiplier") or {}
            mv = mult.get("mNumber")
            if mv is None and mult.get("mDataValue") is not None:
                mv = self.dv(mult["mDataValue"])
            if k is not None and mv is not None:
                return k * mv, [self.scale_mult(s, mv) for s in sc], p
            return k, sc, p
        const, scal = 0.0, []
        has_const = False
        for part in c.get("mFormulaParts") or []:
            pc = part.get("__class", "")
            if pc == "NumberCalculationPart":
                const += float(part.get("mNumber", 0))
                has_const = True
            elif pc == "NamedDataValueCalculationPart":
                v = self.dv(part.get("mDataValue"))
                if v is not None:
                    const += v
                    has_const = True
            elif pc == "StatByCoefficientCalculationPart":
                scal.append(self.scale_str(float(part.get("mCoefficient", 0)), part))
            elif pc == "StatByNamedDataValueCalculationPart":
                v = self.dv(part.get("mDataValue"))
                if v is not None:
                    scal.append(self.scale_str(v, part))
            elif pc == "ByCharLevelInterpolationCalculationPart":
                a, b = float(part.get("mStartValue", 0)), float(part.get("mEndValue", 0))
                scal.append("%s - %s (based on level)" % (self.fmt(a), self.fmt(b)))
            elif pc == "ByCharLevelBreakpointsCalculationPart":
                scal.append("%s (based on level)" % self.fmt(float(part.get("mLevel1Value", 0))))
            elif pc == "SumOfSubPartsCalculationPart":
                for sp in part.get("mSubparts") or []:
                    if sp.get("__class") == "NumberCalculationPart":
                        const += float(sp.get("mNumber", 0))
                        has_const = True
                    elif sp.get("__class") == "NamedDataValueCalculationPart":
                        v = self.dv(sp.get("mDataValue"))
                        if v is not None:
                            const += v
                            has_const = True
                    elif sp.get("__class") in ("StatByCoefficientCalculationPart", "StatByNamedDataValueCalculationPart"):
                        v = sp.get("mCoefficient") if "mCoefficient" in sp else self.dv(sp.get("mDataValue"))
                        scal.append(self.scale_str(float(v or 0), sp))
            elif pc == "ProductOfSubPartsCalculationPart":
                p1, p2 = part.get("mPart1") or {}, part.get("mPart2") or {}
                def pv(x):
                    if x.get("__class") == "NumberCalculationPart":
                        return float(x.get("mNumber", 0))
                    if x.get("__class") == "NamedDataValueCalculationPart":
                        return self.dv(x.get("mDataValue"))
                    return None
                a, b = pv(p1), pv(p2)
                if a is not None and b is not None:
                    const += a * b
                    has_const = True
        mult = c.get("mMultiplier")
        if mult and mult.get("__class") == "NumberCalculationPart":
            m = float(mult.get("mNumber", 1))
            const *= m
        return (const if has_const else None), scal, pct

    def calc_ref(self, ref, depth):
        if isinstance(ref, str):
            nm = ref.split(":", 1)[-1]
            return self.calc_eval(nm, depth)
        return None, [], False

    def scale_mult(self, s, m):
        return s

    def scale_str(self, coef, part):
        stat = CALC_STATS.get(int(part.get("mStat", 0)), "stat")
        form = int(part.get("mStatFormula", 0))
        label = ("bonus " if form == 2 else ("base " if form == 1 else "")) + stat
        if stat in ("AP", "AD", "Armor", "Magic Resist", "Max Health", "Health", "Missing Health", "Attack Speed", "Move Speed"):
            return "%s%% %s" % (self.fmt(coef, True), label if stat != "AP" else "AP")
        return "%s%% %s" % (self.fmt(coef, True), label)

    def calc_text(self, name):
        k, sc, pct = self.calc_eval(name)
        if k is None and not sc:
            return None
        if k is not None and pct:
            return self.fmt(k, True) + "%"
        if k is None:
            return " + ".join(sc)
        out = self.fmt(k)
        if sc:
            out += " (+ " + " + ".join(sc) + ")"
        return out

    def dv(self, ref):
        if isinstance(ref, str):
            ref = ref.split(":", 1)[-1]
        v = self.data.get(ref)
        if isinstance(v, (int, float)):
            return float(v)
        return None

    # ---- placeholders
    def token(self, expr):
        expr = expr.strip()
        mul = None
        m = re.match(r"^(.*?)\*(-?[\d.]+)$", expr)
        if m:
            expr, mul = m.group(1), float(m.group(2))
        if expr == "ChampRange":
            return str(self.range_mode)
        if expr == "ItemActiveness":
            return ""
        v = None
        if expr in self.data and isinstance(self.data[expr], (int, float)):
            v = float(self.data[expr])
        else:
            txt = self.calc_text(expr)
            if txt is not None and mul is None:
                return txt
            if txt is not None:
                k, sc, pct = self.calc_eval(expr)
                if k is not None:
                    v = k
            if v is None:
                v = self.stat_value(expr)
            if v is None:
                mm = re.match(r"^Effect(\d+)Amount$", expr)
                if mm:
                    ea = self.item.get("mEffectAmount") or []
                    idx = int(mm.group(1)) - 1
                    if 0 <= idx < len(ea) and isinstance(ea[idx], (int, float)):
                        v = float(ea[idx])
        if v is None:
            return None
        if mul is not None:
            v *= mul
        return self.fmt(v)

    def resolve(self, s, depth=0):
        if not s or depth > 8:
            return s or ""
        # {{ Key }} -> string table (key may itself contain @tokens@)
        def sub_loc(m):
            key = m.group(1).strip()
            key = re.sub(r"@([^@]+)@", lambda mm: self.token(mm.group(1)) or "", key)
            t = self.st.get(key)
            if t is None:
                return ""
            if key.startswith("Item_Gold_Value"):
                return ""
            return t
        out = re.sub(r"\{\{\s*([^}]+?)\s*\}\}", sub_loc, s)
        if out != s:
            return self.resolve(out, depth + 1)
        out = re.sub(r"@([^@\s]+)@", lambda m: self.token(m.group(1)) if self.token(m.group(1)) is not None else "?", out)
        out = re.sub(r"%i:[A-Za-z]+%\s*", "", out)
        return out


def split_sections(main_text):
    return re.findall(r"<section>(.*?)</section>", main_text, flags=re.S)


# --------------------------------------------------------------------------- build
def main():
    names = load_names()
    gw = Wad(GAME + "/Global.wad.client")
    ib = BinFile(gw.read(ITEMS_BIN_HASH))
    G = {}
    for k, o in ib.entries.items():
        G[names.get(k, f"{k:08x}")] = (o.cls, to_py(o, names))
    CH = {}
    for k, o in BinFile(gw.read(CHAMPS_BIN_HASH)).entries.items():
        CH[names.get(k, f"{k:08x}")] = to_py(o, names)
    st = StringTable(Wad(GAME + "/Localized/Global.en_US.wad.client").read("data/menu/en_us/lol.stringtable"))
    m12 = Wad(GAME + "/Maps/Shipping/Map12.wad.client")
    mb = BinFile(m12.read("data/maps/shipping/map12/map12.bin"))
    M = {names.get(k, f"{k:08x}"): to_py(o, names) for k, o in mb.entries.items()}

    version = json.load(open(GAME + "/../../content-metadata.json"))["version"] if os.path.exists(GAME + "/../../content-metadata.json") else ""
    # ---- ARAM item list: GameModeItemLists of the ARAM + Kiwi modes, restricted to mInStore
    lists = set()
    for mode in ("Maps/Shipping/Map12/Modes/ARAM", "Maps/Shipping/Map12/Modes/KIWI"):
        for ref in M[mode]["itemLists"]:
            for it in M[ref.split(":", 1)[1]]["mItems"]:
                lists.add(link_id(it))
    raw = {}
    for key, (cls, v) in G.items():
        if v.get("__class") == "ItemData":
            raw[int(v["itemID"])] = v
    groups = {}
    for key, (cls, v) in G.items():
        if v.get("__class") == "ItemGroup":
            groups[key] = v
    store = sorted(i for i in lists if i in raw and (raw[i].get("mItemDataAvailability") or {}).get("mInStore"))
    print(f"{len(lists)} listed, {len(store)} in store")

    def total_cost(i, memo={}):
        if i in memo:
            return memo[i]
        v = raw[i]
        t = int(v.get("price", 0)) + sum(total_cost(link_id(x)) for x in (v.get("recipeItemLinks") or []))
        memo[i] = t
        return t

    # recipe components may be items outside the store list (e.g. Glowing Mote) -> include them as buildable parts
    parts = set()
    def add_parts(i):
        for x in raw[i].get("recipeItemLinks") or []:
            c = link_id(x)
            if c in raw and c not in parts:
                parts.add(c)
                add_parts(c)
    for i in store:
        add_parts(i)
    wanted = sorted(set(store) | parts)

    items = {}
    catalogue_extra = {}
    for iid in wanted:
        v = raw[iid]
        client = v.get("mItemDataClient") or {}
        tip = (client.get("mTooltipData") or {})
        keys = tip.get("mLocKeys") or {}
        # data values with ARAM/Kiwi overrides
        data = {}
        for dv in v.get("mDataValues") or []:
            if "mValue" in dv:
                data[dv["mName"]] = dv["mValue"]
            else:
                data[dv["mName"]] = 0.0
        ovr = v.get("DataValuesModeOverride") or {}
        for mk in MODE_KEYS:
            for dv in (ovr.get("hash:" + mk) or {}).get("DataValues") or []:
                data[dv["mName"]] = dv.get("mValue", 0.0)
        calcs = v.get("mItemCalculations") or {}
        calcs = {k.split(":", 1)[-1]: c for k, c in calcs.items()}
        stats, raw_stats = {}, {}
        for fld, key in STAT_FIELDS.items():
            if fld in v and isinstance(v[fld], (int, float)) and v[fld] != 0:
                stats[key] = round(float(v[fld]), 6)
                raw_stats[fld] = v[fld]
        frm = [link_id(x) for x in (v.get("recipeItemLinks") or [])]
        total = total_cost(iid)
        epic = v.get("epicness")
        if epic is None:
            epic = client.get("epicness")
        gl = []
        for g in v.get("mItemGroups") or []:
            gk = g.split(":", 1)[1]
            go = groups.get(gk)
            if go is None:
                continue
            gid = str(go.get("mItemGroupID", gk)).split(":", 1)[-1]
            mx = go.get("mMaxGroupOwnable")
            if mx:
                gl.append({"id": gid, "max": int(mx)})
        sell_mod = v.get("sellBackModifier", 0.7)
        classes = [CLASS_BITS[a] for a in (v.get("mItemAttributes") or []) if a in CLASS_BITS]
        name = st.get(v.get("mDisplayName", "")) or key_name(iid, st)
        nick = [s.strip().lower() for s in (st.get(keys.get("keyColloquialism", "")) or "").split(";") if s.strip()]
        brief = st.get(keys.get("keyBrief", "")) or ""
        cd = data.get("Cooldown")
        if cd is None:
            cd = _spell_cd(G, v.get("spellName"))
        shop_tip = st.get(client.get("mShopTooltip", "")) or st.get(client.get("mDescription", "")) or ""
        texts = []
        for rm in (1, 2):
            r = Resolver(st, v, data, calcs)
            r.range_mode = rm
            main_t = re.search(r"<mainText>(.*)</mainText>", shop_tip, flags=re.S)
            secs = split_sections(main_t.group(1)) if main_t else []
            texts.append([r.resolve(s).strip() for s in secs])
        text = texts[0]
        rr = Resolver(st, v, data, calcs)
        calc_txt = {}
        for cn in calcs:
            t = rr.calc_text(cn)
            if t is not None:
                calc_txt[cn] = t
        item = {
            "name": name, "price": int(v.get("price", 0)), "total": total, "from": frm, "sell": int(round(total * sell_mod)),
            "sell_mod": round(float(sell_mod), 4), "can_sell": bool(v.get("mCanBeSold", True)),
            "stats": stats, "raw_stats": raw_stats, "tier": epic, "classes": classes,
            "categories": v.get("mCategories") or [], "groups": gl, "max_stack": int(v.get("MaxStack", 1)),
            "consumed": bool(v.get("consumed")), "clickable": bool(v.get("clickable")),
            "consume_on_acquire": bool(v.get("consumeOnAcquire")), "usable_in_store": bool(v.get("usableInStore")),
            "req_level": int(v.get("mRequiredLevel", 0)), "restricted": v.get("RestrictedBuffName", ""),
            "req_champion": v.get("mRequiredChampion", ""), "in_store": iid in store,
            "req_spell": v.get("mRequiredSpellName", ""), "req_currency": v.get("mRequiredBuffCurrencyName", ""),
            "nick": nick, "brief": brief, "cooldown": cd, "data": data, "text": text,
            "icon": os.path.basename(client.get("InventoryIconLarge", "")) if client else "",
            "effect_amount": v.get("mEffectAmount") or [],
            "special_recipe": int(v.get("specialRecipe", 0)), "scripts": v.get("mScripts") or [],
            "melee_ranged": texts[0] != texts[1],
        }
        catalogue_extra[str(iid)] = calc_txt
        if texts[0] != texts[1]:
            item["text_ranged"] = texts[1]
        if v.get("clearUndoHistory") is not None:
            item["clear_undo"] = True
        items[str(iid)] = item
    # builds-into among shop items
    for iid in items:
        items[iid]["into"] = []
    for iid, it in items.items():
        for c in it["from"]:
            tgt = items.get(str(c))
            if tgt is not None and int(iid) not in tgt["into"]:
                tgt["into"].append(int(iid))
    for it in items.values():
        it["into"] = sorted((i for i in it["into"] if items[str(i)]["in_store"]), key=lambda i: (items[str(i)]["total"], i))

    # ---- shop panels (ARAM mode)
    shop_ref = M["Maps/Shipping/Map12/Modes/ARAM"]["mItemShopData"].split(":", 1)[1]
    sd = M[shop_ref]
    def qb(d):
        return [link_id(e["Item"]) for e in d["ItemsList"]]
    shop = {
        "quick_consumables": qb(sd["ConsumablesQuickBuyData"]), "quick_boots": qb(sd["BootsQuickBuyData"]),
        "starters": [link_id(x) for x in M[M["Maps/Shipping/Map12/Modes/ARAM"]["itemLists"][1].split(":", 1)[1]]["mItems"]],
        "store": store, "groups": {"7": "unique", "8": "anvil", "1": "starter", "2": "basic", "3": "superior", "4": "epic", "5": "legendary", "6": "mythic"},
        "rec_fallback": "ARAM",
    }
    # ---- champion recommendation overrides (ARAM context first)
    sets = {k: v for k, (c, v) in G.items() if v.get("__class") == "ItemRecommendationOverrideSet"}
    recs = {}
    for key, v in CH.items():
        if not key.startswith("Characters/") or v.get("__class") != "Champion":
            continue
        alias = key.split("/", 1)[1]
        rec = (v.get("mChampionItemRecommendations") or {})
        link = rec.get("mOverrideSetLink")
        entry = {"damage": (v.get("ChampionMetadata") or {}).get("playStyleDamage")}
        if link:
            sk = link.split(":", 1)[1]
            sv = sets.get(sk)
            if sv:
                for ov in sv.get("mOverrides") or []:
                    for ctx in ov.get("mOverrideContexts") or []:
                        mid, mode = ctx.get("mMapID"), str(ctx.get("mModeNameStringId", "")).lower()
                        slot = "aram" if (mid == 12 and mode.endswith("aram")) else ("classic" if (mid == 11 and mode.endswith("classic")) else None)
                        if slot is None:
                            continue
                        entry[slot] = {
                            "starting": [[link_id(x) for x in b.get("items", [])] for b in ov.get("StartingItemBundles") or []],
                            "ranges": [{"items": [link_id(x) for x in r.get("items", [])], "max": int(r.get("MaxCompletedItems", 1))}
                                       for r in ov.get("mRecItemRanges") or []]}
        recs[alias] = entry
    write_catalogue(items, catalogue_extra)
    out = {"version": version, "items": items, "shop": shop, "recs": recs}
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))
    print("wrote", OUT, os.path.getsize(OUT) // 1024, "KB;", len(items), "items;", sum(1 for r in recs.values() if "aram" in r), "champion rec sets")
    # cross-check names vs the client's items.json
    try:
        cd = {x["id"]: x for x in json.load(open(os.path.join(ROOT, "tools", "extracted", "client", "items.json"), encoding="utf-8"))}
        for iid, it in items.items():
            c = cd.get(int(iid))
            if c and c["name"] != it["name"]:
                print("name differs", iid, it["name"], "|", c["name"])
    except OSError:
        pass


def write_catalogue(items, calcs):
    """tools/extracted/items/catalogue.txt: one block per store item (developer reference for item behaviour)."""
    def plain(t):
        t = re.sub(r"<br>", " / ", t)
        t = re.sub(r"<[^>]+>", "", t)
        return re.sub(r"\s+", " ", t).strip()
    lines = []
    for k, x in sorted(items.items(), key=lambda kv: ((kv[1]["tier"] or 0), kv[1]["total"], int(kv[0]))):
        if not x["in_store"]:
            continue
        secs = [plain(s) for s in x["text"]]
        body = " || ".join(s for s in secs[2:4] if s)
        lines.append("%s | %s | total %d (combine %d) | from %s | stats %s | cd %s | clickable %s | req_champ %s" % (
            k, x["name"], x["total"], x["price"], x["from"], x["stats"], x["cooldown"], x["clickable"], x["req_champion"]))
        lines.append("    " + body)
        if x.get("text_ranged") and x["text_ranged"] != x["text"]:
            lines.append("    (ranged) " + " || ".join(s for s in (plain(t) for t in x["text_ranged"][2:4]) if s))
        lines.append("    data %s effect_amount %s" % (x["data"], x["effect_amount"]))
        if calcs.get(k):
            lines.append("    calcs %s" % calcs[k])
    path = os.path.join(ROOT, "tools", "extracted", "items", "catalogue.txt")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


def key_name(iid, st):
    return st.get(f"Item_{iid}_Name") or str(iid)


def _spell_cd(G, spell_name):
    if not spell_name:
        return None
    ent = G.get("Items/Spells/" + spell_name)
    if not ent:
        return None
    sp = (ent[1].get("mSpell") or {})
    cds = sp.get("CooldownTime")
    if isinstance(cds, list) and cds:
        return cds[0]
    return None


if __name__ == "__main__":
    main()
