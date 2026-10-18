class_name ChampionKit
extends RefCounted
## Base champion kit: builds model, abilities and passive for a Champion.
## Per-champion kits live in src/champions/kits/<alias>.gd and override build_kit().

var c: Champion


func build(champ: Champion) -> void:
	c = champ
	setup_model()
	build_kit()
	for i in 4:
		var a: Ability = c.abilities[i]
		if a != null:
			a.slot = i
			a.key = "QWER"[i]
			a.is_ult = i == 3
			if a.is_ult:
				a.max_level = 3
			if a.icon == null:
				a.icon = Assets.ability_icon(c.alias, a.key.to_lower())
	if c.passive != null and c.passive.icon == null:
		c.passive.icon = Assets.ability_icon(c.alias, "p")


func setup_model() -> void:
	var m := Assets.champion_model(c.alias, c.skin)
	if m == null:
		m = Assets.placeholder_model(c.team, 1.8)
	c.set_model(m)
	c.anim_map = Assets.build_anim_map(c.anim_player, anim_overrides())


## Override to remap logical animation names, e.g. {"run": ["Run_Haste"]}.
func anim_overrides() -> Dictionary:
	return {}


## Override: create abilities and passive.
func build_kit() -> void:
	pass


## Spell json for a slot key ("Q".."R") or a script name.
func spell(key_or_script: String) -> Dictionary:
	var slots: Dictionary = c.data.get("spell_slots", {})
	var script_name: String = slots.get(key_or_script, key_or_script)
	return c.data.get("spells", {}).get(script_name, {})


## Configure an ability with authentic numbers from the game data.
func init_ability(a: Ability, key: String, script_name: String = "") -> Ability:
	a.owner = c
	var sd := spell(script_name if script_name != "" else key)
	a.data = sd.get("data_values", {})
	a.calcs = sd.get("calcs", {})
	if sd.has("cooldownTime"):
		a.cooldowns = _ranks(sd.cooldownTime, key == "R")
	if sd.has("mana"):
		a.costs = _ranks(sd.mana, key == "R")
	# [spatial] League measures unit-targeted spells centre-to-centre unless castRangeUseBoundingBoxes (then edge to
	# edge, like basic attacks). castRangeDisplayOverride is only the drawn ring for unit-targeted spells (MF Q:
	# castRange 550 edge range, ring 650); for skillshots / ground spells it is the real reach (missile range).
	a.range_edge = bool(sd.get("castRangeUseBoundingBoxes", false))
	if sd.has("castRangeDisplayOverride") and a.target_type == Ability.Target.UNIT and sd.has("castRange") \
			and _first(sd.castRange) < 20000.0:
		a.cast_range = _first(sd.castRange)
		a.display_range = _first(sd.castRangeDisplayOverride)
	elif sd.has("castRangeDisplayOverride"):
		a.cast_range = _first(sd.castRangeDisplayOverride)
	elif sd.has("castRange"):
		var cr := _first(sd.castRange)
		if cr < 20000.0:
			a.cast_range = cr
	if sd.has("mCastTime"):
		a.cast_time = _first(sd.mCastTime)
	if sd.has("mAnimationName"):
		var an := str(_first_s(sd.mAnimationName)).to_lower()
		if an.begins_with("spell"):
			a.anim = an.substr(0, 6)
	a.tooltip_raw = sd.get("tooltip", "")
	if sd.has("missileSpeed"):
		a.set_meta("missile_speed", _first(sd.missileSpeed) * G.U)
	var cd := ChampionDB.client_data(c.alias)
	for s in cd.get("spells", []):
		if str(s.get("spellKey", "")).to_upper() == key:
			a.display_name = s.get("name", key)
			a.description = s.get("description", "")
	if a.display_name == "":
		a.display_name = sd.get("name", key)
	return a


func _ranks(v, is_ult: bool) -> Array:
	if not (v is Array):
		return [float(v)]
	var arr: Array = v
	# game arrays: index0 = rank0 when length 7, client arrays when 6
	if arr.size() >= 7:
		arr = arr.slice(1, 6 if not is_ult else 4)
	elif arr.size() == 6:
		arr = arr.slice(0, 5 if not is_ult else 3)
	return arr


func _first(v) -> float:
	if v is Array:
		return float(v[1] if v.size() > 1 else v[0])
	return float(v)


func _first_s(v):
	if v is Array:
		return v[0]
	return v


## Display name of the passive from client data.
func passive_info() -> Dictionary:
	return ChampionDB.client_data(c.alias).get("passive", {})
