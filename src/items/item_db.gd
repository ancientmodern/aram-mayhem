class_name ItemDB
extends RefCounted
## Item database + shop rules for ARAM / ARAM Mayhem (map 12, mode ARAM + Kiwi).
##
## All numbers (cost, combine cost, recipe incl. duplicate components, sell value, purchase limits via item groups,
## stats, tooltips, nicknames, class / stat filters, quick-buy panels, recommendation overrides) are League's own,
## extracted from the client install by tools/lol/extract_items.py into data/items/items.json.
## Item behaviour: ItemFxExtra (src/items/item_fx_extra*.gd, new items and data-driven rewrites) takes priority, then the
## legacy ItemFx classes (EFFECT_OF) and finally a plain stat stick.
##
## Legacy accessor layout kept for older callers: CAT[id] = [name, total cost, stats, components, unique group, effect class,
## tags, description].

const DATA_PATH := "res://data/items/items.json"
const MAX_SLOTS := 6
const SELL_FRACTION := 0.7
## League's ItemShopGameModeData for ARAM: the all-items grid sections in display order (epicness -> group).
const GROUP_ORDER := ["unique", "anvil", "starter", "basic", "epic", "legendary"]
const GROUP_TITLES := {"unique": "UNIQUE", "anvil": "ANVIL", "starter": "STARTER", "basic": "BASIC", "epic": "EPIC", "legendary": "LEGENDARY"}
## Items that live outside the grid but are bought through the quick panels / auto purchase.
const LEGACY_ALIAS := {9999: 6032, 4011: 124011}

## Legacy effect classes (ItemFx) that already implement an item's passive.
const EFFECT_OF := {2051: "GuardianHorn", 3057: "Spellblade", 3077: "Cleave", 6660: "Immolate", 3047: "Steelcaps", 6672: "Kraken",
	3153: "Botrk", 3124: "Guinsoo", 3078: "Spellblade", 3071: "Cleaver", 3053: "Steraks", 3072: "Bloodthirster", 3074: "Cleave",
	3748: "TitanicCleave", 6333: "DeathsDance", 3087: "Statikk", 3085: "Runaans", 6676: "Collector", 3033: "Reminder",
	6675: "Navori", 3508: "Spellblade", 3142: "Youmuu", 6692: "Eclipse", 3161: "Shojin", 6631: "Stridebreaker", 3156: "Maw",
	6673: "Shieldbow", 3091: "WitsEnd", 6655: "Luden", 3157: "Zhonya", 6653: "Liandry", 3100: "LichBane", 3115: "Nashor",
	3116: "Rylai", 4645: "Shadowflame", 3102: "Banshee", 4633: "Riftmaker", 3003: "Archangel", 3152: "Rocketbelt",
	3084: "Heartsteel", 3068: "Immolate", 3075: "Thornmail", 3083: "Warmogs", 3065: "Visage", 3143: "Randuin", 3039: "Atma",
	124011: "Blossom", 3190: "Locket", 3107: "Redemption", 6032: "Anvil"}

## League's search keywords for stats / categories (the shop search matches these as well as names and nicknames).
const STAT_ALIASES := {"ad": "attack damage ad", "ap": "ability power ap", "hp": "health hp", "mana": "mana", "armor": "armor ar",
	"mr": "magic resist mr", "as": "attack speed as", "crit": "critical strike crit", "crit_dmg": "critical strike damage",
	"ms": "move speed movement ms", "ms%": "move speed movement ms", "ah": "ability haste ah cdr", "lifesteal": "life steal lifesteal ls",
	"omnivamp": "omnivamp vamp", "lethality": "lethality armor penetration", "armor_pen%": "armor penetration pen",
	"magic_pen": "magic penetration pen", "magic_pen%": "magic penetration pen", "tenacity": "tenacity", "heal_power": "heal shield power",
	"hp_regen": "health regen", "hp_regen%": "health regen", "mana_regen": "mana regen", "mana_regen%": "mana regen",
	"slow_resist": "slow resist", "range": "attack range"}

const STAT_NAMES := {"ad": "Attack Damage", "ap": "Ability Power", "hp": "Health", "mana": "Mana", "armor": "Armor", "mr": "Magic Resist",
	"as": "Attack Speed", "crit": "Critical Strike Chance", "crit_dmg": "Critical Strike Damage", "ms": "Move Speed", "ms%": "Move Speed",
	"ah": "Ability Haste", "lifesteal": "Life Steal", "omnivamp": "Omnivamp", "lethality": "Lethality", "armor_pen%": "Armor Penetration",
	"magic_pen": "Magic Penetration", "magic_pen%": "Magic Penetration", "tenacity": "Tenacity", "heal_power": "Heal and Shield Power",
	"hp_regen": "Health Regen", "mana_regen": "Mana Regen", "ap%": "Ability Power", "base_ad%": "Base Attack Damage",
	"summoner_haste": "Summoner Spell Haste", "slow_resist": "Slow Resist", "ult_ah": "Ultimate Haste", "range": "Attack Range",
	"hp_regen%": "Base Health Regen", "mana_regen%": "Base Mana Regen"}

## League's shop stat filter column (top to bottom): [layout key, label, League mCategories that match].
const STAT_FILTERS := [
	["PhysicalDamage", "Attack Damage", ["Damage"]],
	["CriticalStrike", "Critical Strike", ["CriticalStrike"]],
	["AttackSpeed", "Attack Speed", ["AttackSpeed"]],
	["OnHit", "On-Hit Effects", ["OnHit"]],
	["ArmorPen", "Armor Penetration", ["ArmorPenetration"]],
	["AbilityPower", "Ability Power", ["SpellDamage"]],
	["Mana", "Mana & Regeneration", ["Mana", "ManaRegen"]],
	["MagicPen", "Magic Penetration", ["MagicPenetration"]],
	["Health", "Health & Regeneration", ["Health", "HealthRegen"]],
	["Armor", "Armor", ["Armor"]],
	["MagicResist", "Magic Resist", ["SpellBlock", "MagicResist"]],
	["AbilityHaste", "Ability Haste", ["AbilityHaste", "CooldownReduction"]],
	["Movespeed", "Movement", ["NonbootsMovement", "Boots"]],
	["Vamp", "Life Steal & Vamp", ["LifeSteal", "SpellVamp", "Omnivamp"]],
]

## Hand-curated finished builds (Mayhem roster). Bots follow these; the player's Recommended tab uses them when the
## champion has an entry, otherwise League's own recommendation overrides (RECS).
const BUILDS := {
	"Ahri": [3112, 6655, 3020, 4645, 3089, 3135, 3157],
	"Garen": [3177, 6631, 3047, 3071, 3053, 3742, 6333],
	"Darius": [3177, 6631, 3047, 3053, 3742, 6333, 4401],
	"Yasuo": [3184, 3006, 3031, 6672, 3072, 6333, 6673],
	"MasterYi": [3184, 3153, 3006, 3124, 3091, 6672, 6333],
	"Malphite": [2051, 3068, 3047, 3075, 3110, 3143, 6665],
	"Leona": [2051, 3190, 3111, 3068, 3075, 4401, 3065],
	"Lux": [3112, 6655, 3020, 4645, 3089, 3135, 3102],
	"Jinx": [3184, 6672, 3006, 3031, 3085, 3036, 3072],
	"Ezreal": [3177, 3078, 3158, 3004, 3071, 3036, 6333],
	"MissFortune": [3184, 6676, 3006, 3031, 3036, 3072, 6673],
	"Annie": [3112, 6655, 3020, 4645, 3089, 3157, 3135],
	"Sona": [3112, 6617, 3158, 3107, 124011, 3065, 3089],
	"Veigar": [3112, 6655, 3020, 3089, 4645, 3135, 3157],
}
const DEFAULT_BUILD := [3177, 3047, 3071, 3053, 6333, 3742]

## Stats granted by a passive that the flat stat fields do not carry: item id -> {engine stat key: item data value name}.
const PASSIVE_STATS := {3089: {"ap%": "APAmp"}, 3158: {"summoner_haste": "SummonerHaste"}}

# --- loaded data (declared before CAT so CAT's initialiser can fill them)
static var META: Dictionary = {}          ## int id -> data/items/items.json entry
static var SHOP: Dictionary = {}          ## quick panels, starters, store ids
static var RECS: Dictionary = {}          ## champion alias -> recommendation override data
static var VERSION := ""
static var CAT: Dictionary = _load_db()


static func _load_db() -> Dictionary:
	var cat := {}
	if not FileAccess.file_exists(DATA_PATH):
		push_error("ItemDB: missing %s (run tools/lol/extract_items.py)" % DATA_PATH)
		return cat
	var d = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not (d is Dictionary):
		push_error("ItemDB: cannot parse " + DATA_PATH)
		return cat
	VERSION = String(d.get("version", ""))
	SHOP = d.get("shop", {})
	RECS = d.get("recs", {})
	for k in d.items:
		var e: Dictionary = d.items[k]
		var id := int(k)
		META[id] = e
		var tags := _tags(id, e)
		var grp := ""
		for g in e.groups:
			if String(g.id) != str(id):
				grp = String(g.id)
				break
		var plain := []
		for i in range(2, (e.text as Array).size()):
			var s := ItemText.plain(String(e.text[i]))
			if s != "":
				plain.append(s)
		cat[id] = [e.name, int(e.total), (e.stats as Dictionary).duplicate(), (e["from"] as Array).map(func(x): return int(x)),
			grp, EFFECT_OF.get(id, ""), tags, "\n\n".join(plain)]
	for al in LEGACY_ALIAS:                       # old ids keep working for callers that index CAT directly
		if cat.has(LEGACY_ALIAS[al]):
			cat[al] = cat[LEGACY_ALIAS[al]]
	return cat


static func _tags(id: int, e: Dictionary) -> Array:
	var t: Array = (e.classes as Array).duplicate()
	if tier_group(id, e) == "starter" and not e.consumed:
		t.append("starter")
	if _in_group(e, "Boots"):
		t.append("boots")
	if e.consumed or e.max_stack > 1:
		t.append("consumable")
	if (e["from"] as Array).is_empty() and not (e.groups as Array).is_empty() and not t.has("starter") and not t.has("consumable"):
		t.append("basic")
	elif (e["from"] as Array).is_empty() and e.tier == null and not t.has("consumable"):
		t.append("basic")
	if "OnHit" in e.categories:
		t.append("onhit")
	return t


static func _in_group(e: Dictionary, gid: String) -> bool:
	for g in e.groups:
		if String(g.id) == gid:
			return true
	return false


# ===================================================================== lookups
static func canon(item_id: int) -> int:
	return LEGACY_ALIAS.get(item_id, item_id)


static func has(item_id: int) -> bool:
	return META.has(canon(item_id))


static func meta(item_id: int) -> Dictionary:
	return META.get(canon(item_id), {})


static func name_of(item_id: int) -> String:
	var e := meta(item_id)
	return e.get("name", str(item_id))


## Total gold cost (what League calls "total cost").
static func cost_of(item_id: int) -> int:
	return int(meta(item_id).get("total", 0))


## Combine cost (League's "recipe cost").
static func combine_cost(item_id: int) -> int:
	return int(meta(item_id).get("price", 0))


static func sell_value_of(item_id: int) -> int:
	return int(meta(item_id).get("sell", 0))


static func components_of(item_id: int) -> Array:
	var f: Array = meta(item_id).get("from", [])
	return f.map(func(x): return int(x))


static func group_of(item_id: int) -> String:
	return CAT[canon(item_id)][4] if CAT.has(canon(item_id)) else ""


static func tags_of(item_id: int) -> Array:
	return CAT[canon(item_id)][6] if CAT.has(canon(item_id)) else []


static func brief(item_id: int) -> String:
	return String(meta(item_id).get("brief", ""))


static func blurb(item_id: int) -> String:
	return brief(item_id)


static func data(item_id: int, key: String, default = 0.0):
	var d: Dictionary = meta(item_id).get("data", {})
	return d.get(key, default)


static func cooldown_of(item_id: int) -> float:
	var c = meta(item_id).get("cooldown")
	return float(c) if c != null else 0.0


## League shop section ("unique" ... "legendary") by epicness; "" = not listed in the grid.
static func tier_group(item_id: int, e: Dictionary = {}) -> String:
	if e.is_empty():
		e = meta(item_id)
	if e.is_empty():
		return ""
	var t = e.get("tier")
	if t == null:
		return "basic"
	match int(t):
		1:
			return "starter"
		2:
			return "basic"
		3, 4:
			return "epic"
		5, 6:
			return "legendary"
		7:
			return "unique"
		8:
			return "anvil"
	return ""


## Shop tier label used by the HUD ("Starter", "Basic", "Epic", "Legendary", "Unique", "Anvil").
static func tier_of(item_id: int) -> String:
	var g := tier_group(item_id)
	return g.capitalize() if g != "" else "Basic"


static func is_boots(item_id: int) -> bool:
	return _in_group(meta(item_id), "Boots")


static func is_consumable(item_id: int) -> bool:
	var e := meta(item_id)
	return bool(e.get("consumed", false))


static func max_stack(item_id: int) -> int:
	return maxi(1, int(meta(item_id).get("max_stack", 1)))


## True when the champion's attack range class is "ranged" (for melee/ranged split tooltips).
static func champ_ranged(c) -> bool:
	return c != null and float(c.stats.base.get("attack_range", 550.0)) >= 300.0


## Tooltip sections (markup strings, League's own text) for the champion's range class.
static func sections(item_id: int, ranged := false) -> Array:
	var e := meta(item_id)
	if e.is_empty():
		return []
	if ranged and e.has("text_ranged"):
		return e.text_ranged
	return e.text


## Is the item visible in the shop for this champion?
static func visible_in_shop(item_id: int, c = null) -> bool:
	var e := meta(item_id)
	if e.is_empty() or not e.in_store:
		return false
	if e.req_spell != "" or e.req_currency != "":
		return false
	if e.req_champion != "" and (c == null or String(c.alias).to_lower() != String(e.req_champion).to_lower()):
		return false
	return true


## All items listed in the all-items grid for the champion (unsorted).
static func grid_items(c = null) -> Array:
	var out := []
	for id in META:
		if not visible_in_shop(id, c):
			continue
		if tier_group(id) == "":
			continue
		if int(META[id].tier if META[id].tier != null else 2) == 0:
			continue
		if META[id].req_champion != "":
			continue
		out.append(id)
	return out


## Items that build directly out of `item_id` and are sold in the shop (League's "Builds Into"), by price.
static func builds_into(item_id: int) -> Array:
	var into: Array = meta(item_id).get("into", [])
	return into.map(func(x): return int(x))


# ===================================================================== filters / search
static func matches_class(item_id: int, cls: String) -> bool:
	return cls == "" or cls in meta(item_id).get("classes", [])


static func matches_stat_filter(item_id: int, filter_idx: int) -> bool:
	if filter_idx < 0 or filter_idx >= STAT_FILTERS.size():
		return true
	var cats: Array = meta(item_id).get("categories", [])
	for k in STAT_FILTERS[filter_idx][2]:
		if k in cats:
			return true
	return false


static func _passive_names(e: Dictionary) -> String:
	var out := ""
	var re := RegEx.create_from_string("<(?:passive|active)>([^<]+)</")
	for s in e.text:
		for m in re.search_all(String(s)):
			out += " " + m.get_string(1).to_lower()
	return out


static func _haystack(item_id: int) -> Dictionary:
	var e := meta(item_id)
	var name: String = String(e.get("name", "")).to_lower()
	var initials := ""
	for w in name.replace("'", "").replace("-", " ").split(" "):
		if w != "":
			initials += w[0]
	var stats := ""
	for k in e.get("stats", {}):
		stats += " " + String(STAT_ALIASES.get(k, STAT_NAMES.get(k, k))).to_lower()
	var cats := " ".join(PackedStringArray((e.get("categories", []) as Array).map(func(x): return String(x).to_lower())))
	return {"name": name, "nick": e.get("nick", []), "initials": initials, "stats": stats,
		"extra": _passive_names(e) + " " + cats + " " + String(e.get("brief", "")).to_lower()}


## League's shop search: item name, nicknames (colloquialisms such as "ie", "bc", "dcap"), initials, stat names and passive names.
## Every whitespace separated term must match somewhere.
static func matches_search(item_id: int, q: String) -> bool:
	return search_score(item_id, q) > 0


## 0 = no match; larger = better (exact nickname > name prefix > word prefix > contains > stat / passive match).
static func search_score(item_id: int, q: String) -> int:
	q = q.strip_edges().to_lower()
	if q == "":
		return 1
	var h := _haystack(item_id)
	var total := 0
	for term in q.split(" ", false):
		var s := 0
		if term in h.nick:
			s = 100
		elif h.name == term:
			s = 95
		elif String(h.name).begins_with(term):
			s = 80
		elif h.initials == term or String(h.initials).begins_with(term) and term.length() >= 2:
			s = 70
		elif (" " + String(h.name)).contains(" " + term):
			s = 60
		elif String(h.name).contains(term):
			s = 50
		else:
			for nk in h.nick:
				if String(nk).begins_with(term):
					s = 55
					break
			if s == 0:
				if (" " + String(h.stats)).contains(" " + term):
					s = 30
				elif (" " + String(h.extra)).contains(" " + term):
					s = 20
				elif String(h.extra).contains(term) and term.length() >= 3:
					s = 10
		if s == 0:
			return 0
		total += s
	return total


# ===================================================================== recommendations
static func _champ_alias(c) -> String:
	return String(c.alias) if c != null else ""


## Build order [starting items bundles, steps] for the champion's Recommended tab.
## -> {"starting": [[ids]...], "steps": [{"items": [ids], "max": n}...], "full": [ids]}
static var _plan_cache: Dictionary = {}


static func rec_plan(c) -> Dictionary:
	var alias := _champ_alias(c)
	if not _plan_cache.has(alias):
		_plan_cache[alias] = _build_rec_plan(c, alias)
	return _plan_cache[alias]


static func _build_rec_plan(c, alias: String) -> Dictionary:
	var plan := {"starting": [], "steps": [], "full": []}
	if BUILDS.has(alias):
		var build: Array = BUILDS[alias]
		var boots_done := false
		for id in build:
			var t := tier_group(id)
			if t == "starter" and not is_consumable(id):
				plan.starting.append([id])
			else:
				plan.steps.append({"items": [id], "max": 1})
		plan.full = build.duplicate()
		return plan
	var r: Dictionary = RECS.get(alias, {})
	var pick: Dictionary = r.get("aram", {})
	var roles := _roles(alias)
	if pick.is_empty() or not _rec_sane(pick, roles):
		pick = r.get("classic", pick)
	if pick.is_empty():
		for id in DEFAULT_BUILD:
			plan.steps.append({"items": [id], "max": 1})
		plan.starting = [[3177], [3184]]
		plan.full = DEFAULT_BUILD.duplicate()
		return plan
	for b in pick.starting:
		var ids := []
		for x in b:
			if x != null and visible_in_shop(int(x), c):
				ids.append(int(x))
		if not ids.is_empty():
			plan.starting.append(ids)
	for st in pick.ranges:
		var items := []
		for x in st["items"]:
			if x != null and visible_in_shop(int(x), c):
				items.append(int(x))
		if not items.is_empty():
			plan.steps.append({"items": items, "max": maxi(1, int(st["max"]))})
	for st in plan.steps:
		if not (st.items[0] in plan.full):
			plan.full.append(st.items[0])
	return plan


static func _roles(alias: String) -> Array:
	if alias == "" or not ClassDB.class_exists("Node"):
		return []
	var cd = ChampionDB.client_data(alias)
	return cd.get("roles", []) if cd is Dictionary else []


## ARAM override sets are shared between whole champion groups; accept it only when its legendary picks fit the champion.
static func _rec_sane(pick: Dictionary, roles: Array) -> bool:
	if roles.is_empty():
		return true
	var want := []
	for r in roles:
		match String(r):
			"mage": want.append("mage")
			"marksman": want.append("marksman")
			"assassin": want.append("assassin")
			"fighter": want.append("fighter")
			"tank": want.append("tank")
			"support": want.append("support")
	var ok := 0
	var n := 0
	for st in pick.ranges:
		for x in st["items"]:
			if x == null or not has(int(x)):
				continue
			n += 1
			for w in want:
				if w in meta(int(x)).classes:
					ok += 1
					break
	return n > 0 and float(ok) / float(n) >= 0.5


static func _owned_ids(c) -> Array:
	var out := []
	for it in c.items:
		out.append(it.item_id)
	return out


## Up to `n` suggested items for the Recommended tab, given what the champion owns (League's "Suggested items").
static func suggested(c, n := 3) -> Array:
	var plan := rec_plan(c)
	var owned := _owned_ids(c)
	var out := []
	if c.items.is_empty():
		for b in plan.starting:
			if not (b[0] in out):
				out.append(b[0])
			if out.size() >= n:
				return out
	for st in plan.steps:
		var done := 0
		for id in st.items:
			if _owned_or_upgraded(owned, id):
				done += 1
		if done >= int(st["max"]):
			continue
		for id in st.items:
			if _owned_or_upgraded(owned, id) or id in out:
				continue
			if is_boots(id) and _owns_boots(owned) and not _owns_exact(owned, id):
				continue
			out.append(id)
			if out.size() >= n:
				return out
			if int(st["max"]) <= 1 and st.items.size() > 1 and out.size() >= 1 and false:
				break
	for id in plan.full:
		if out.size() >= n:
			break
		if not _owned_or_upgraded(owned, id) and not (id in out):
			out.append(id)
	return out


static func _owns_exact(owned: Array, id: int) -> bool:
	return id in owned


static func _owns_boots(owned: Array) -> bool:
	for id in owned:
		if is_boots(id):
			return true
	return false


## Owned, or owned something that was built out of it (e.g. a completed item).
static func _owned_or_upgraded(owned: Array, id: int) -> bool:
	if id in owned:
		return true
	for o in owned:
		if _builds_from(o, id):
			return true
	return false


static func _builds_from(top: int, part: int, depth := 0) -> bool:
	if depth > 4:
		return false
	for c in components_of(top):
		if c == part or _builds_from(c, part, depth + 1):
			return true
	return false


## League's "commonly built" row: the full finished build (starter, boots, legendaries), max 9.
static func commonly_built(c) -> Array:
	var full: Array = rec_plan(c).full
	return full.slice(0, 9)


## Legacy API (older callers): {"starter": [...], "boots": [...], "core": [...]}.
static func recommended(alias: String) -> Dictionary:
	var build: Array = BUILDS.get(alias, DEFAULT_BUILD)
	var out := {"starter": [], "boots": [], "core": []}
	for id in build:
		var t := tier_of(id)
		if t == "Starter":
			out.starter.append(id)
		elif is_boots(id):
			out.boots.append(id)
		else:
			out.core.append(id)
	return out


## Quick-buy panels of the ARAM shop (League: ConsumablesQuickBuyData / BootsQuickBuyData).
static func quick_consumables() -> Array:
	return (SHOP.get("quick_consumables", []) as Array).map(func(x): return int(x))


static func quick_boots() -> Array:
	return (SHOP.get("quick_boots", []) as Array).map(func(x): return int(x))


# ===================================================================== stats / items
static func stat_line(k: String, v: float) -> String:
	var nm: String = STAT_NAMES.get(k, k)
	var pct := k.ends_with("%") or k in ["as", "crit", "crit_dmg", "lifesteal", "omnivamp", "tenacity", "heal_power", "slow_resist"]
	if pct:
		return "+%d%% %s" % [int(round(v * 100.0)), nm]
	return "+%d %s" % [int(round(v)), nm]


static func create(item_id: int) -> Item:
	var id := canon(item_id)
	if not META.has(id):
		return null
	var e: Dictionary = META[id]
	var it: Item = null
	if ItemFxExtra.has(id):
		it = ItemFxExtra.make(id)
	else:
		var cls: String = EFFECT_OF.get(id, "")
		if cls != "" and ItemFx.has_class(cls):
			it = ItemFx.make(cls)
	if it == null:
		it = Item.new()
	it.item_id = id
	it.id = "item_%d" % id
	it.display_name = e.name
	it.cost = int(e.total)
	it.stats = (e.stats as Dictionary).duplicate()
	if PASSIVE_STATS.has(id):
		for k in PASSIVE_STATS[id]:
			it.stats[k] = float(e.data.get(PASSIVE_STATS[id][k], 0.0))
	it.components = components_of(id)
	var cat: Array = CAT[id]
	it.unique_group = cat[4]
	it.item_tags = cat[6]
	it.description = cat[7]
	it.icon = Assets.item_icon(id)
	if it.active_cd <= 0.0 and bool(e.get("clickable", false)) and not bool(e.get("consumed", false)):
		pass
	ItemFxExtra.configure(it, id, e)
	return it


# ===================================================================== purchasing
## Price to buy `item_id` for champion c after owned components are consumed. Returns [price, consumed_items].
static func price_for(c, item_id: int) -> Array:
	var id := canon(item_id)
	var owned: Array = c.items.duplicate()
	var consumed := []
	var price := cost_of(id)
	_discount(id, owned, consumed)
	for it in consumed:
		price -= it.cost
	return [maxi(0, price), consumed]


## League's auto-combine: every recipe slot is satisfied by an owned copy of that exact component if there is one, else by
## recursively consuming owned parts of that component's own recipe. Duplicate components consume one owned item each.
static func _discount(item_id: int, owned: Array, consumed: Array) -> void:
	var comps := components_of(item_id)
	# first pass: slots satisfied by an exact owned component
	var open := []
	for comp in comps:
		var found = null
		for it in owned:
			if it.item_id == comp:
				found = it
				break
		if found != null:
			owned.erase(found)
			consumed.append(found)
		else:
			open.append(comp)
	# second pass: partially built slots
	for comp in open:
		_discount(comp, owned, consumed)


## "" when the champion can buy `item_id` right now, else a reason code:
## far (not at the shop), unavailable, level, gold, full, unique.
static func buy_block_reason(c, item_id: int) -> String:
	var id := canon(item_id)
	if not META.has(id) or not visible_in_shop(id, c) and not (id in quick_consumables() or id in quick_boots()):
		return "unavailable"
	if not c.can_shop():
		return "far"
	var e: Dictionary = META[id]
	if int(e.req_level) > int(c.level):
		return "level"
	var p := price_for(c, id)
	if c.gold < p[0]:
		return "gold"
	var stack_target = _stack_target(c, id)
	var instant := bool(e.get("consume_on_acquire", false))   # Stat Bonus / Cappa Juice never take an inventory slot
	if instant and id != 6032 and ItemFxExtra.acquire_count(c, id) >= max_stack(id):
		return "full"
	if stack_target == null and not instant:
		var slots_after: int = c.items.size() - p[1].size() + 1
		if slots_after > MAX_SLOTS:
			return "full"
	elif stack_target != null and _stack_count(stack_target) >= max_stack(id):
		return "full"
	if stack_target == null:
		var conflict = group_conflict(c, id, p[1])
		if conflict != null:
			return "unique"
	return ""


## The owned item that blocks `id` through a purchase-limited item group (excluding items consumed by the purchase), or null.
static func group_conflict(c, item_id: int, consumed: Array = []):
	var e := meta(item_id)
	for g in e.get("groups", []):
		var cnt := 0
		var other = null
		for it in c.items:
			if it in consumed:
				continue
			if _in_group(meta(it.item_id), String(g.id)):
				cnt += 1
				other = it
		if cnt >= int(g.max):
			return other
	return null


static func reason_text(reason: String, c = null, item_id := -1) -> String:
	match reason:
		"far":
			return "You can only shop while dead or on the spawn platform"
		"unavailable":
			return "Item unavailable"
		"level":
			return "Requires level %d" % int(meta(item_id).get("req_level", 0))
		"gold":
			return "Not enough gold"
		"full":
			return "Inventory full"
		"unique":
			var other = group_conflict(c, item_id) if c != null else null
			if other != null:
				return "You already own %s" % name_of(other.item_id)
			return "You already own a conflicting item"
	return ""


static func _stack_target(c, id: int):
	if not is_consumable(id) or max_stack(id) <= 1:
		return null
	for it in c.items:
		if it.item_id == id:
			return it
	return null


static func _stack_count(it) -> int:
	return int(it.get("stacks")) if it.get("stacks") != null else 1


## Buy one `item_id` exactly (consumes owned components). Returns true on success.
static func buy(c, item_id: int) -> bool:
	var id := canon(item_id)
	if buy_block_reason(c, id) != "":
		return false
	var p := price_for(c, id)
	c.gold -= p[0]
	for it in p[1]:
		c.remove_item(it)
	if id != 6032 and bool(meta(id).get("consume_on_acquire", false)):
		if ItemFxExtra.acquire(c, id):
			return true
	var tgt = _stack_target(c, id)
	if tgt != null:
		if tgt.has_method("add_stack"):
			tgt.add_stack(1)
		c.items_changed.emit()
		return true
	if id == 6032:
		# ARAM Mayhem "Stat Bonus" anvil: consumed at once, grants a random stat shard
		var anvil := create(6032)
		anvil.stats = AnvilShard.roll(c)
		anvil.hidden = true
		c.add_effect(anvil)
		c.anvils.append(anvil)
		c.items_changed.emit()
		return true
	var it := create(id)
	if it == null:
		c.gold += p[0]
		return false
	c.add_item(it)
	return true


## What the shop's Purchase button does for the player. Returns {"ok": bool, "kind": "basic"|"upgrade"|"legendary"|"components"|"stack"|"none",
## "bought": [ids], "reason": code}. When the complete item is out of reach but components can be bought, buys the
## components (most expensive affordable first), exactly like League's "PURCHASE COMPONENTS".
static func purchase(c, item_id: int) -> Dictionary:
	var id := canon(item_id)
	var reason := buy_block_reason(c, id)
	if reason == "":
		var consumed: Array = price_for(c, id)[1]
		var stacked := _stack_target(c, id) != null
		var ok := buy(c, id)
		var kind := "basic"
		if stacked:
			kind = "stack"
		elif not consumed.is_empty():
			kind = "upgrade"
		elif tier_group(id) == "legendary":
			kind = "legendary"
		return {"ok": ok, "kind": kind, "bought": [id] if ok else [], "reason": "" if ok else "unavailable"}
	if reason != "gold":
		return {"ok": false, "kind": "none", "bought": [], "reason": reason}
	var plan := components_to_buy(c, id)
	if plan.is_empty():
		return {"ok": false, "kind": "none", "bought": [], "reason": "gold"}
	var bought := []
	for cid in plan:
		if buy(c, cid):
			bought.append(cid)
	return {"ok": not bought.is_empty(), "kind": "components", "bought": bought, "reason": "" if not bought.is_empty() else "gold"}


## The component purchases that League's PURCHASE COMPONENTS would make now (simulated against the champion's gold / slots).
static func components_to_buy(c, item_id: int) -> Array:
	var id := canon(item_id)
	if not META.has(id) or not c.can_shop():
		return []
	var sim_gold: float = c.gold
	var sim_items: Array = c.items.duplicate()
	var plan := []
	_plan_parts(c, id, sim_items, plan, [sim_gold])
	return plan


static func _plan_parts(c, id: int, owned: Array, plan: Array, gold: Array) -> void:
	# owned components are free; walk the open slots, expensive first
	var open := []
	var tmp_owned := owned.duplicate()
	for comp in components_of(id):
		var found = null
		for it in tmp_owned:
			if it.item_id == comp:
				found = it
				break
		if found != null:
			tmp_owned.erase(found)
		else:
			open.append(comp)
	open.sort_custom(func(a, b): return cost_of(a) > cost_of(b))
	for comp in open:
		var price := _sim_price(comp, owned)
		if gold[0] >= price and (owned.size() + 1) <= MAX_SLOTS and not _sim_conflict(comp, owned):
			plan.append(comp)
			gold[0] -= price
			# the consumed owned parts disappear, the new component takes a slot
			var cons := []
			var o2 := owned.duplicate()
			_discount_sim(comp, o2, cons)
			for x in cons:
				owned.erase(x)
			owned.append(_FakeItem.new(comp))
		elif not components_of(comp).is_empty():
			_plan_parts(c, comp, owned, plan, gold)


class _FakeItem extends RefCounted:
	var item_id := 0
	var cost := 0

	func _init(i: int) -> void:
		item_id = i
		cost = ItemDB.cost_of(i)


static func _discount_sim(item_id: int, owned: Array, consumed: Array) -> void:
	_discount(item_id, owned, consumed)


static func _sim_price(id: int, owned: Array) -> int:
	var o := owned.duplicate()
	var cons := []
	_discount(id, o, cons)
	var price := cost_of(id)
	for it in cons:
		price -= it.cost
	return maxi(0, price)


static func _sim_conflict(id: int, owned: Array) -> bool:
	var e := meta(id)
	for g in e.get("groups", []):
		var cnt := 0
		for it in owned:
			if _in_group(meta(it.item_id), String(g.id)):
				cnt += 1
		if cnt >= int(g.max):
			return true
	return false


## Gold League gives back for selling `it` (whole stack for consumables).
static func sell_price(it) -> int:
	var e := meta(it.item_id)
	var each := int(e.get("sell", int(it.cost * SELL_FRACTION)))
	return each * _stack_count(it)


static func can_sell(it) -> bool:
	return bool(meta(it.item_id).get("can_sell", true))


static func sell(c, it) -> void:
	if not c.can_shop() or not can_sell(it):
		return
	c.gold += sell_price(it)
	c.remove_item(it)


# ---- undo support: items + stack counts + gold + consumed anvils
static func snapshot(c) -> Dictionary:
	var stacks := {}
	for it in c.items:
		if it.get("stacks") != null:
			stacks[it] = int(it.get("stacks"))
	return {"gold": c.gold, "items": c.items.duplicate(), "stacks": stacks, "anvils": c.anvils.size()}


static func restore(c, snap: Dictionary) -> void:
	for it in c.items.duplicate():
		if not (it in snap.items):
			c.remove_item(it)
	for it in snap.items:
		if not (it in c.items):
			it.removed = false
			c.add_item(it)
	c.items = snap.items.duplicate()
	for it in snap.stacks:
		it.set("stacks", snap.stacks[it])
	while c.anvils.size() > snap.anvils:
		var a = c.anvils.pop_back()
		c.remove_effect(a)
	c.gold = snap.gold
	c.items_changed.emit()
	c.stats.mark_dirty()


# ===================================================================== bots
## Next purchase for a bot following its build. Returns item id or -1. (Sells the starter item when a slot is needed.)
static func bot_next_purchase(c) -> int:
	var build: Array = BUILDS.get(c.alias, DEFAULT_BUILD)
	if c.controller != null and c.controller.has_method("shape_build"):   # [bot-diff] the bot's difficulty level shapes its build
		build = c.controller.shape_build(build)
	for target in build:
		if _owns(c, target) or _owns_upgrade(c, target):
			continue
		if tier_group(target) == "starter" and (c.items.size() > 0 or c.level > 3):
			continue
		if _bot_free_slot(c, target):
			if buy_block_reason(c, target) == "":
				return target
		# buy the most expensive affordable component on the path
		var comp := _best_component(c, target)
		if comp > 0:
			return comp
		return -1
	if c.level >= int(meta(6032).get("req_level", 9)) and c.gold >= cost_of(6032) and c.anvils.size() < 20:
		return 6032
	return -1


## Make room for `target` by selling a starter item that has not been built into anything (bots only).
static func _bot_free_slot(c, target: int) -> bool:
	if c.items.size() < MAX_SLOTS:
		return true
	if not c.can_shop():
		return false
	var p := price_for(c, target)
	if c.items.size() - p[1].size() + 1 <= MAX_SLOTS:
		return true
	for it in c.items:
		if tier_group(it.item_id) == "starter" and not (it.item_id in build_ids(c)):
			sell(c, it)
			return c.items.size() < MAX_SLOTS
	for it in c.items:
		if tier_group(it.item_id) == "starter":
			sell(c, it)
			return c.items.size() < MAX_SLOTS
	return false


static func build_ids(c) -> Array:
	return BUILDS.get(c.alias, DEFAULT_BUILD)


static func _owns(c, item_id: int) -> bool:
	for it in c.items:
		if it.item_id == item_id:
			return true
	return false


static func _owns_upgrade(c, item_id: int) -> bool:
	for it in c.items:
		if _builds_from(it.item_id, item_id):
			return tier_group(item_id) == "legendary" and false
	return false


static func _best_component(c, target: int) -> int:
	var best := -1
	var best_cost := 0
	var stack: Array = components_of(target).duplicate()
	while not stack.is_empty():
		var comp: int = stack.pop_back()
		if _owns(c, comp):
			continue
		if buy_block_reason(c, comp) == "" and cost_of(comp) > best_cost and c.items.size() < MAX_SLOTS + 1:
			best = comp
			best_cost = cost_of(comp)
		stack += components_of(comp)
	return best


class AnvilShard extends RefCounted:
	static func roll(c) -> Dictionary:
		var r := G.rng.randf()
		var tier := "Silver" if r < 0.5 else ("Gold" if r < 0.88 else "Prismatic")
		var meta = load("res://src/augments/sets/aug_meta.gd")
		return meta.StatAnvils.pick_shard(c, tier)
