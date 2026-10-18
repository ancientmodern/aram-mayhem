class_name HudBuffIcons
extends RefCounted
## Buff icons for the HUD buff bars. League shows the icon of whatever applied the buff: the champion spell
## (data/characters/<champ>/hud/icons2d), the item, the summoner spell or the augment. Buffs created without an
## icon are resolved once (cached on the buff) in this order:
##   summoner spell  ->  source champion's spell (slot letter or spell / passive name in the buff id)
##   ->  item (name in the id)  ->  augment (name in the id)  ->  generic CC icon / the spell the source cast last
##   ->  source champion's passive (champion-prefixed ids)  ->  League's generic buff icon.

const SUMMONERS := {"ghost": "ghost", "heal": "heal", "heal_ms": "heal", "ignite": "ignite", "cleanse": "cleanse",
	"barrier": "barrier", "clarity": "clarity", "flash": "flash", "mark": "mark", "exhaust": "exhaust"}
## generic League buff icons (assets/spells/icons2d, extracted to assets/ui/hud/buffs)
const GENERIC_STUN := "res://assets/ui/hud/buffs/gsb_stun.png"
const GENERIC_BURN := "res://assets/ui/hud/buffs/burning.png"

static var _items := {}          ## word -> item id
static var _augs: PackedStringArray = []


static func icon_for(b) -> Texture2D:
	if b.icon != null:
		return b.icon
	if b.has_meta("_hud_icon"):
		return b.get_meta("_hud_icon")
	var t := _resolve(b)
	b.set_meta("_hud_icon", t)
	return t


static func _tokens(s: String) -> PackedStringArray:
	return s.to_lower().replace("-", "_").replace(" ", "_").replace("'", "").split("_", false)


static func _resolve(b) -> Texture2D:
	var id := String(b.id).to_lower()
	var toks := _tokens(id)
	var src = b.source if b.source != null and is_instance_valid(b.source) else null
	# 1. summoner spells (Ghost, Heal, Ignite ...)
	if SUMMONERS.has(id):
		var st := Assets.summoner_icon(SUMMONERS[id])
		if st != null:
			return st
	if src is Champion:
		for sp in src.summoners:
			if sp != null and sp.icon != null and String(sp.id).to_lower() in toks:
				return sp.icon
	# 2. the source champion's spell named in the id
	if src is Champion:
		var t := _champion_spell(src, id, toks)
		if t != null:
			return t
	# 3. items ("shojin", "guinsoo", "liandry", ...)
	var it := _item_icon(toks)
	if it != null:
		return it
	# 4. augments ("tap_dancer" -> aram_tapdancer)
	var at := _augment_icon(id)
	if at != null:
		return at
	# 5. crowd control without a spell icon: the spell the source cast last (it applied the CC), else League's icons
	if src is Champion and (b.cc != 0 or b.slow_amount > 0.0):
		var rt := _recent_cast(src)
		if rt != null:
			return rt
	if b.cc & Buff.CC.STUN or b.cc & Buff.CC.AIRBORNE or id == "stun":
		return Assets.tex(GENERIC_STUN)
	if "burn" in id or id == "ignite":
		return Assets.tex(GENERIC_BURN)
	# 6. champion-prefixed ids that name no spell: the passive (stacking marks, empowered states)
	if src is Champion:
		var pic := _passive_icon(src)
		if pic != null:
			return pic
		return Assets.champion_square(src.alias)
	return Assets.tex(GENERIC_STUN) if b.cc != 0 else null


static func _champion_spell(c: Champion, id: String, toks: PackedStringArray) -> Texture2D:
	var keys := ["q", "w", "e", "r"]
	for i in 4:
		if keys[i] in toks and c.abilities[i] != null and c.abilities[i].icon != null:
			return c.abilities[i].icon
	if "p" in toks or "passive" in toks:
		return _passive_icon(c)
	for ab in c.abilities:
		if ab == null or ab.icon == null:
			continue
		if ab.id != "" and id.contains(ab.id.to_lower()):
			return ab.icon
		if _words_match(toks, ab.display_name):
			return ab.icon
	var info: Dictionary = ChampionDB.client_data(c.alias).get("passive", {})
	if _words_match(toks, String(info.get("name", ""))):
		return _passive_icon(c)
	return null


## True when a meaningful token of the buff id starts a word of `name` ("wuju" -> "Wuju Style", "hemo" -> "Hemorrhage").
static func _words_match(toks: PackedStringArray, name: String) -> bool:
	if name == "":
		return false
	var words := _tokens(name.replace("!", "").replace(":", "").replace(",", ""))
	for t in toks:
		if t.length() < 4:
			continue
		for w in words:
			if w.length() >= 4 and (w.begins_with(t) or t.begins_with(w)):
				return true
	return false


static func _passive_icon(c: Champion) -> Texture2D:
	if c.passive != null and c.passive.get("icon") != null:
		return c.passive.icon
	return Assets.ability_icon(c.alias, "p")


static func _item_icon(toks: PackedStringArray) -> Texture2D:
	if _items.is_empty():
		for iid in ItemDB.CAT:
			for w in _tokens(String(ItemDB.CAT[iid][0]).replace(",", "").replace(".", "")):
				if w.length() >= 5 and not _items.has(w):
					_items[w] = iid
	for t in toks:
		if t.length() >= 5:
			for w in _items:
				if w.begins_with(t):
					return Assets.item_icon(_items[w])
	return null


static func _augment_icon(id: String) -> Texture2D:
	if _augs.is_empty():
		var d := DirAccess.open("res://assets/ui/augments_large")
		if d != null:
			for f in d.get_files():
				if f.ends_with(".png") or f.ends_with(".png.import"):
					_augs.append(f.get_slice(".", 0))
		if _augs.is_empty():
			_augs.append("")
	var key := "aram_" + id.replace("_", "")
	if key.length() < 9:
		return null
	for a in _augs:
		if a != "" and a.begins_with(key):
			return Assets.augment_icon(a)
	return null


## The ability `c` cast most recently (within 3 s), judged by how far into its cooldown it is.
static func _recent_cast(c: Champion) -> Texture2D:
	var best: Texture2D = null
	var best_el := 3.0
	for ab in c.abilities:
		if ab == null or ab.icon == null or ab.cd <= 0.0:
			continue
		var el: float = ab.cd_total - ab.cd
		if el >= 0.0 and el < best_el:
			best_el = el
			best = ab.icon
	return best
