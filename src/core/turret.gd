class_name Turret
extends Unit
## Howling Abyss turret: targeting priority, champion damage ramp, reinforced armor.

enum Tier { OUTER, INHIBITOR, NEXUS, FOUNTAIN }

var tier := Tier.OUTER
var guards: Array = []           ## structures that must die before this one is vulnerable
var ramp := 0                    ## consecutive shots on champions
var last_champ_shot := -100.0
var _retarget := 0.0
var shot_speed := 13.0
var backdoor_until := -1.0
var aggro_line_target: Unit = null
var base_ad := 185.0
var ad_per_min := 7.0


func _init() -> void:
	super._init()
	kind = G.Kind.TURRET
	radius = 1.1
	path_radius = 1.2
	mass = 0.0
	height = 6.2
	selection_radius = 1.8
	stats.uses_mana = false
	windup_pct = 0.15


func setup(p_team: int, p_tier: int) -> void:
	team = p_team
	tier = p_tier
	display_name = ["Outer Turret", "Inhibitor Turret", "Nexus Turret", "Fountain Turret"][p_tier]
	var hp_by_tier := [2550.0, 5150.0, 3000.0, 99999.0]
	var armor_by_tier := [60.0, 63.0, 60.0, 500.0]
	base_ad = [185.0, 205.0, 195.0, 999.0][p_tier]
	ad_per_min = [6.0, 9.0, 9.0, 0.0][p_tier]
	stats.set_base({
		"base_hp": hp_by_tier[p_tier], "hp_per_level": 0.0, "base_hp_regen": 0.0, "hp_regen_per_level": 0.0,
		"base_ad": base_ad, "ad_per_level": 0.0, "base_armor": armor_by_tier[p_tier], "armor_per_level": 0.0,
		"base_mr": armor_by_tier[p_tier], "mr_per_level": 0.0, "base_ms": 0.0,
		"attack_range": 750.0 if p_tier != Tier.FOUNTAIN else 1250.0,
		"attack_speed": 0.833 if p_tier != Tier.FOUNTAIN else 3.0, "attack_speed_ratio": 0.833, "attack_speed_per_level": 0.0,
		"mana_base": 0.0, "mana_per_level": 0.0, "mana_regen": 0.0, "mana_regen_per_level": 0.0,
	})
	recompute_stats()
	hp = stats.max_hp
	attack_missile_speed = 1300.0 if p_tier != Tier.FOUNTAIN else 3000.0
	var skin := 28 if team == G.Team.ORDER else (31 if p_tier == Tier.FOUNTAIN else 29)
	var m := Assets.unit_model("Turret", skin)
	if m == null:
		m = Assets.placeholder_model(team, 5.0, 1.0)
	set_model(m)
	anim_map = Assets.build_anim_map(anim_player, {})
	if p_tier == Tier.FOUNTAIN:
		invulnerable_count = 1
		height = 4.0


func is_vulnerable() -> bool:
	for g in guards:
		if is_instance_valid(g) and not g.dead:
			return false
	return true


func is_invulnerable() -> bool:
	return super.is_invulnerable() or not is_vulnerable()


func sight_range() -> float:
	return 13.5


func auto_attacks_when_idle() -> bool:
	return false


func think(dt: float) -> void:
	if match_ref == null:
		return
	# damage scales with game minute
	var minutes: float = match_ref.time / 60.0
	stats.base["base_ad"] = base_ad + ad_per_min * clampf(minutes, 0.0, 15.0)
	if match_ref.time - last_champ_shot > 5.0:
		ramp = 0
	_retarget -= dt
	if attack_valid(attack_target) and in_attack_range(attack_target) and _retarget > 0.0:
		return
	_retarget = 0.25
	var t := _pick_target()
	if t != attack_target:
		attack_target = t
		if windup_timer >= 0.0 and t != _windup_target:
			cancel_windup()
	cmd = Cmd.HOLD if t == null else Cmd.ATTACK
	aggro_line_target = t


func _pick_target() -> Unit:
	var now: float = match_ref.time
	var r := attack_range_m() + radius
	var cands: Array = match_ref.units_in_radius(global_position, r, G.enemy_team(team))
	# keep current target if still valid unless a champion attacks an allied champion
	var best: Unit = null
	var best_p := 99
	var best_d := INF
	for u in cands:
		if u.dead or not u.is_targetable_by(team):
			continue
		if G.flat_dist(global_position, u.global_position) > r + u.radius:
			continue
		var p := 9
		match u.kind:
			G.Kind.SUMMON: p = 1
			G.Kind.MINION:
				var mt: int = u.minion_type
				p = 2 if mt == Minion.Type.SIEGE or mt == Minion.Type.SUPER else (3 if mt == Minion.Type.MELEE else 4)
			G.Kind.CHAMPION:
				p = 5
				if now - u.get_meta("last_hit_ally_champ", -100.0) < 2.0:
					p = 0   # defends allied champions
		var d := G.flat_dist(global_position, u.global_position)
		if p < best_p or (p == best_p and d < best_d):
			best_p = p
			best_d = d
			best = u
	if attack_valid(attack_target) and in_attack_range(attack_target) and best != null and best_p != 0:
		return attack_target
	return best


func attack_hit(t: Unit, crit: bool, mult: float = 1.0) -> DamageInfo:
	if t == null or not is_instance_valid(t) or t.dead:
		return null
	var dmg := stats.ad * mult
	if t.kind == G.Kind.CHAMPION:
		dmg *= 1.0 + 0.5 * ramp
		ramp = mini(ramp + 1, 3)
		last_champ_shot = match_ref.time
	elif t.kind == G.Kind.MINION:
		# League turrets kill minions in a fixed number of shots
		match t.minion_type:
			Minion.Type.MELEE: dmg = t.stats.max_hp * 0.45
			Minion.Type.CASTER: dmg = t.stats.max_hp * 0.7
			Minion.Type.SIEGE: dmg = t.stats.max_hp * 0.14
			Minion.Type.SUPER: dmg = t.stats.max_hp * 0.07
	var info := Combat.deal(self, t, dmg, G.DmgType.PHYSICAL if tier != Tier.FOUNTAIN else G.DmgType.TRUE,
			{"is_attack": true, "no_vamp": true})
	return info


func on_damaged(info: DamageInfo) -> void:
	super.on_damaged(info)


## Called by Combat via effects: reinforced armor (-80% without enemy minions nearby) & backdoor.
func damage_taken_multiplier(src) -> float:
	var mult := 1.0
	if match_ref == null:
		return mult
	var minions_near := false
	for u in match_ref.units_in_radius(global_position, attack_range_m() + 2.0, G.enemy_team(team)):
		if u.kind == G.Kind.MINION and not u.dead:
			minions_near = true
			break
	if not minions_near:
		mult *= 0.2
	if match_ref.time < backdoor_until:
		mult *= 0.6
	if src != null and src.kind == G.Kind.CHAMPION and src.attack_missile_speed <= 0.0:
		mult *= 1.2
	return mult


func on_died(_killer) -> void:
	aggro_line_target = null
	if match_ref != null:
		match_ref.on_structure_fell(self)
	if match_ref != null:
		var col := Color(1.0, 0.7, 0.4) if team == G.Team.CHAOS else Color(0.55, 0.8, 1.0)
		Vfx.burst(match_ref, global_position + Vector3(0, 3.0, 0), col, 3.0, {"sparks": 70})
		Vfx.ring(match_ref, global_position, col, 6.0, 0.7, 0.12, 0.25)
		if match_ref.camera_rig != null and G.flat_dist(match_ref.camera_rig.focus, global_position) < 30.0:
			match_ref.camera_rig.shake(0.45)
	if model != null:
		var tw := create_tween()
		tw.tween_property(model, "position:y", -4.0, 2.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(func(): model.visible = false)


func _update_visual(dt: float) -> void:
	if model != null and not dead:
		pass
	super._update_visual(dt)
