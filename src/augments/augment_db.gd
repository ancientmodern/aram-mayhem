class_name AugmentDB
extends RefCounted
## Augment catalogue (names/rarities/icons from the game client) + implementations registry,
## offer generation and bot selection.

const SET_SCRIPTS := [
	"res://src/augments/sets/aug_stats.gd",
	"res://src/augments/sets/aug_combat.gd",
	"res://src/augments/sets/aug_ult.gd",
	"res://src/augments/sets/aug_survival.gd",
	"res://src/augments/sets/aug_utility.gd",
	"res://src/augments/sets/aug_auto.gd",
	"res://src/augments/sets/aug_snowball.gd",
	"res://src/augments/sets/aug_meta.gd",
	"res://src/augments/sets/aug_extra.gd",
]

const CHAMP_TAGS := {
	"Ahri": ["ap", "ability", "mana", "dash", "cc", "burst", "mage", "ranged", "missile"],
	"Garen": ["ad", "attack", "tank", "fighter", "melee", "spin", "no_mana", "empowered_attack", "duration"],
	"Darius": ["ad", "attack", "fighter", "melee", "cc", "empowered_attack", "tank"],
	"Yasuo": ["ad", "attack", "crit", "fighter", "melee", "dash", "no_mana", "cc", "missile"],
	"MasterYi": ["ad", "attack", "onhit", "melee", "dash", "assassin", "empowered_attack", "duration", "channel"],
	"Malphite": ["tank", "ap", "cc", "melee", "engage", "armor", "dash"],
	"Leona": ["tank", "cc", "melee", "engage", "dash", "support", "empowered_attack", "armor"],
	"Lux": ["ap", "ability", "mana", "cc", "mage", "ranged", "shield", "poke", "missile"],
	"Jinx": ["ad", "attack", "crit", "marksman", "ranged", "onhit", "missile"],
	"Ezreal": ["ad", "ability", "onhit", "marksman", "ranged", "dash", "poke", "mana", "missile"],
	"MissFortune": ["ad", "attack", "crit", "marksman", "ranged", "channel", "missile"],
	"Annie": ["ap", "ability", "mana", "cc", "burst", "mage", "ranged", "pet", "shield", "missile"],
	"Sona": ["ap", "ability", "mana", "heal", "shield", "support", "ranged", "cc"],
	"Veigar": ["ap", "ability", "mana", "cc", "mage", "ranged", "stacks", "burst", "missile"],
}

static var _catalog := {}         ## id -> {id, name, rarity, tooltip}
static var _impl := {}            ## id -> Callable() -> Augment
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var names = JSON.parse_string(FileAccess.get_file_as_string("res://data/augments/cherry-augments.json"))
	var lists = JSON.parse_string(FileAccess.get_file_as_string("res://data/augments/augment-lists.json"))
	var tips = JSON.parse_string(FileAccess.get_file_as_string("res://data/augments/mayhem_augments.json"))
	var kiwi := {}
	for p in lists[1].augmentList:
		kiwi[String(p).get_file().to_lower()] = true
	var rmap := {"kSilver": "Silver", "kGold": "Gold", "kPrismatic": "Prismatic"}
	for a in names:
		var aid := String(a.augmentNameId)
		if not kiwi.has(aid.to_lower()):
			continue
		_catalog[aid] = {"id": aid, "name": a.nameTRA, "rarity": rmap.get(a.rarity, "Silver"), "tooltip": ""}
	for r in tips:
		if r.has("id") and _catalog.has(r.id):
			_catalog[r.id].tooltip = r.get("tooltip", "")
	for path in SET_SCRIPTS:
		if not ResourceLoader.exists(path):
			continue
		var scr = load(path)
		if scr != null and scr.has_method("register"):
			scr.register(_impl)


static func catalog() -> Dictionary:
	ensure_loaded()
	return _catalog


static func is_implemented(aid: String) -> bool:
	ensure_loaded()
	return _impl.has(aid)


static func implemented_ids(rarity: String = "") -> Array:
	ensure_loaded()
	var out := []
	for aid in _impl:
		if rarity == "" or rarity_of(aid) == rarity:
			out.append(aid)
	return out


static func rarity_of(aid: String) -> String:
	var info: Dictionary = _catalog.get(aid, {})
	return info.get("rarity", "Silver")


static func name_of(aid: String) -> String:
	var info: Dictionary = _catalog.get(aid, {})
	return info.get("name", aid)


## Create an augment instance with catalogue metadata applied.
static func create(aid: String) -> Augment:
	ensure_loaded()
	if not _impl.has(aid):
		return null
	var a: Augment = _impl[aid].call()
	a.id = aid
	var info: Dictionary = _catalog.get(aid, {})
	if a.display_name == "" or a.display_name == aid:
		a.display_name = info.get("name", aid)
	a.rarity = info.get("rarity", a.rarity)
	if a.description == "":
		a.description = info.get("tooltip", "")
	a.icon = Assets.augment_icon(aid)
	return a


static func champion_tags(c) -> Array:
	var tags: Array = CHAMP_TAGS.get(c.alias, []).duplicate()
	if c.stats.bonus_ad > c.stats.ap + 20.0 and not ("ad" in tags):
		tags.append("ad")
	if c.stats.ap > c.stats.bonus_ad + 20.0 and not ("ap" in tags):
		tags.append("ap")
	if c.stats.uses_mana and not ("mana" in tags):
		tags.append("mana")
	if float(c.stats.base.get("attack_range", 550.0)) < 300.0:
		if not ("melee" in tags):
			tags.append("melee")
	elif not ("ranged" in tags):
		tags.append("ranged")
	return tags


## Pick `count` augment ids of a rarity for a champion, excluding ids in `exclude`.
static func roll(c, rarity: String, count: int, exclude: Dictionary) -> Array:
	ensure_loaded()
	var pool := []
	for aid in _impl:
		if rarity_of(aid) != rarity or exclude.has(aid) or c.has_augment(aid):
			continue
		var probe: Augment = create(aid)
		if probe == null:
			continue
		probe.owner = c
		if not probe.fits(c):
			continue
		pool.append(aid)
	pool.shuffle()
	return pool.slice(0, count)


## Bot choice among offered ids: power + champion synergy + noise.
static func bot_pick(c, ids: Array) -> int:
	var best := 0
	var best_s := -INF
	for i in ids.size():
		var a := create(ids[i])
		if a == null:
			continue
		a.owner = c
		var s := a.power + a.synergy(c) + G.rng.randf_range(-0.6, 0.6)
		if s > best_s:
			best_s = s
			best = i
	return best
