class_name Champion
extends Unit
## A playable champion (human or bot).

signal leveled_up(level)
signal gold_changed(gold)
signal items_changed
signal augments_changed
signal ability_leveled(slot)
signal cast_failed(ability, reason)

var alias := ""
var kit = null                      ## ChampionKit
var data := {}                      ## game json
var client_data := {}               ## client json (names, descriptions)
var abilities: Array = [null, null, null, null]
var summoners: Array = [null, null]
var passive: Effect = null
var items: Array = []               ## Item effects (max 6)
var augments: Array = []            ## Augment effects
var gold := 0.0
var total_gold := 0.0
var xp := 0.0
var ability_points := 0
var kills := 0
var deaths := 0
var assists := 0
var cs := 0
var respawn_timer := 0.0
var respawn_total := 0.0
var controller = null               ## PlayerController or BotBrain
var skin := 0
var is_player := false
var augment_offers: Array = []      ## queued offers: each is Array of augment ids
var augments_pending := 0
var augment_round := 0
var rerolls := 0
var resource_name := "Mana"
var level_order := "QWEQQRQWQWRWWEEREE"  ## bot skill order (index = level-1)
var attack_vfx := {}                ## color / style for basic attack missile
var role := "mage"                  ## for bots: mage, marksman, tank, fighter, support, assassin
var ai_profile := {}                ## kit-provided AI tuning
var spawn_point := Vector3.ZERO
var in_fountain := false
var last_combat_time := -100.0
var dance_until := 0.0
var augment_rarity_bias := 0.0
var attack_color := Color(0.5, 0.75, 1.0)


func _init() -> void:
	super._init()
	kind = G.Kind.CHAMPION
	radius = 0.65
	path_radius = 0.3
	height = 2.0
	selection_radius = 1.0
	mass = 1.0
	acquisition_range = 8.0


func setup(p_alias: String, p_team: int, p_skin: int = 0) -> void:
	alias = p_alias
	team = p_team
	skin = p_skin
	data = ChampionDB.game_data(alias)
	client_data = ChampionDB.client_data(alias)
	display_name = client_data.get("name", alias)
	var s: Dictionary = data.get("stats", {})
	var base := {}
	for k in ["base_hp", "hp_per_level", "base_hp_regen", "hp_regen_per_level", "base_ad", "ad_per_level",
			"base_armor", "armor_per_level", "base_mr", "mr_per_level", "base_ms", "attack_range",
			"attack_speed", "attack_speed_ratio", "attack_speed_per_level"]:
		if s.has(k):
			base[k] = float(s[k])
	base["mana_base"] = float(s.get("mana_base", 0.0))
	base["mana_per_level"] = float(s.get("mana_per_level", 0.0))
	base["mana_regen"] = float(s.get("mana_regen", 0.0))
	base["mana_regen_per_level"] = float(s.get("mana_regen_per_level", 0.0))
	stats.uses_mana = int(s.get("resource_type", 0)) == 0 and base.mana_base > 0.0
	windup_pct = clampf(0.3 + float(s.get("attack_cast_offset", 0.0)), 0.1, 0.5)
	if s.has("overrideGameplayCollisionRadius"):
		radius = float(s.overrideGameplayCollisionRadius) * G.U
	selection_radius = maxf(0.9, float(s.get("selectionRadius", 100.0)) * G.U)
	height = maxf(1.6, float(s.get("selectionHeight", 150.0)) * G.U * 1.15)
	acquisition_range = float(s.get("acquisitionRange", 600.0)) * G.U + 2.0
	level = Rules.START_LEVEL
	stats.set_base(base)
	kit = ChampionDB.make_kit(alias)
	if kit != null:
		kit.build(self)
	recompute_stats()
	hp = stats.max_hp
	mana = stats.max_mana
	ability_points = level
	gold = Rules.START_GOLD
	total_gold = gold
	is_bot = not is_player


func sight_range() -> float:
	return 12.0


func xp_bounty() -> float:
	return Rules.kill_xp(level)


func ability(slot: int) -> Ability:
	if slot < 4:
		return abilities[slot]
	if slot == 5:
		return summoners[0]
	if slot == 6:
		return summoners[1]
	return null


# ===================================================================== tick
func tick(dt: float) -> void:
	for a in abilities:
		if a != null:
			a.tick(dt)
	for sm in summoners:
		if sm != null:
			sm.tick(dt)
	if not dead and match_ref != null:
		_fountain(dt)
		gold += Rules.PASSIVE_GOLD_PER_SEC * (1.0 + stats.gold_gen) * dt if match_ref.time > Rules.PASSIVE_GOLD_START else 0.0
	super.tick(dt)


func _fountain(dt: float) -> void:
	# ARAM: the platform only enables shopping / augment picks (no regen)
	in_fountain = G.flat_dist(global_position, spawn_point) <= Rules.SHOP_RADIUS


func can_shop() -> bool:
	return dead or in_fountain


func think(dt: float) -> void:
	if controller != null and controller.has_method("think"):
		controller.think(dt)


func tick_dead(dt: float) -> void:
	respawn_timer -= dt
	if controller != null and controller.has_method("think_dead"):
		controller.think_dead(dt)
	if respawn_timer <= 0.0 and match_ref != null and not match_ref.over:
		respawn()


func on_died(_killer) -> void:
	respawn_total = Rules.respawn_time(level, match_ref.time if match_ref != null else 0.0)
	respawn_timer = respawn_total
	if model != null:
		var tw := create_tween()
		tw.tween_interval(2.5)


func respawn() -> void:
	dead = false
	hp = stats.max_hp
	mana = stats.max_mana
	cc = 0
	damage_log.clear()
	teleport(spawn_point)
	cmd = Cmd.IDLE
	attack_target = null
	play_anim("idle", 1.0, 0.0)
	cur_anim = "idle"
	for e in effects.duplicate():
		e.on_respawn()
	recompute_stats()
	hp = stats.max_hp
	mana = stats.max_mana


# ===================================================================== xp / levels
func gain_xp(amount: float) -> void:
	if level >= Rules.MAX_LEVEL or amount <= 0.0:
		return
	xp += amount
	while level < Rules.MAX_LEVEL and xp >= Rules.xp_to_next(level):
		xp -= Rules.xp_to_next(level)
		level_up()
	if level >= Rules.MAX_LEVEL:
		xp = 0.0


func level_up() -> void:
	level += 1
	ability_points += 1
	recompute_stats()
	for e in effects.duplicate():
		e.on_level_up(level)
	leveled_up.emit(level)
	G.level_up.emit(self, level)
	if Rules.AUGMENT_LEVELS.has(level) and match_ref != null and match_ref.has_method("offer_augment"):
		match_ref.offer_augment(self)
	if match_ref != null and match_ref.overlay != null:
		match_ref.overlay.level_up_fx(self)


func xp_ratio() -> float:
	if level >= Rules.MAX_LEVEL:
		return 1.0
	return clampf(xp / Rules.xp_to_next(level), 0.0, 1.0)


## Max rank allowed for a slot at the current level (League rules).
func max_rank_for(slot: int) -> int:
	if slot == 3:
		if level >= 16:
			return 3
		if level >= 11:
			return 2
		if level >= 6:
			return 1
		return 0
	return mini(5, int(ceil(level / 2.0)))


func can_level_ability(slot: int) -> bool:
	var a: Ability = abilities[slot]
	if a == null or ability_points <= 0 or a.sealed:
		return false
	return a.level < a.max_level and a.level < max_rank_for(slot)


func level_ability(slot: int) -> bool:
	if not can_level_ability(slot):
		return false
	var a: Ability = abilities[slot]
	a.level += 1
	ability_points -= 1
	if a.has_method("on_level_changed"):
		a.on_level_changed()
	ability_leveled.emit(slot)
	return true


## Spend points automatically following level_order (bots, or the player on request).
func auto_level_abilities() -> void:
	var guard := 0
	while ability_points > 0 and guard < 20:
		guard += 1
		var done := false
		# ultimate first whenever possible
		if can_level_ability(3):
			level_ability(3)
			continue
		for i in range(level_order.length()):
			var ch := level_order[i]
			var slot := "QWER".find(ch)
			var target_rank := level_order.substr(0, i + 1).count(ch)
			if slot >= 0 and abilities[slot] != null and abilities[slot].level < target_rank and can_level_ability(slot):
				level_ability(slot)
				done = true
				break
		if not done:
			for s in [0, 1, 2]:
				if can_level_ability(s):
					level_ability(s)
					done = true
					break
		if not done:
			break


# ===================================================================== gold / items
func add_gold(amount: float, from_unit = null) -> void:
	if amount <= 0.0:
		return
	gold += amount
	total_gold += amount
	gold_changed.emit(gold)
	G.gold_earned.emit(self, amount, from_unit)
	if is_player and match_ref != null and from_unit != null and is_instance_valid(from_unit):
		match_ref.fx_gold(from_unit, amount)


func add_item(it: Effect) -> void:
	items.append(it)
	add_effect(it)
	items_changed.emit()


func remove_item(it: Effect) -> void:
	items.erase(it)
	remove_effect(it)
	items_changed.emit()


func add_augment(a: Effect) -> void:
	augments.append(a)
	add_effect(a)
	augments_changed.emit()
	G.augment_chosen.emit(self, a)


## Multiplier for permanent stacks gained from abilities (Stackosaurus Rex etc.).
func permanent_stack_mult() -> float:
	var k := 1.0
	for e in effects:
		if e.has_method("permanent_stack_mult"):
			k *= e.permanent_stack_mult()
	return k


func has_augment(aid: String) -> bool:
	for a in augments:
		if a.id == aid:
			return true
	return false


# ===================================================================== hooks
func on_cast_failed(ab, reason: String) -> void:
	cast_failed.emit(ab, reason)


func on_ability_executed(_ab, _t) -> void:
	last_combat_time = match_ref.time if match_ref != null else 0.0


func on_damaged(info: DamageInfo) -> void:
	super.on_damaged(info)
	if match_ref != null and info.source != null and info.source.kind == G.Kind.CHAMPION:
		last_combat_time = match_ref.time
		info.source.last_combat_time = match_ref.time


func base_run_speed() -> float:
	return 345.0


func auto_attacks_when_idle() -> bool:
	return true
