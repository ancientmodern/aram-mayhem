class_name Minion
extends Unit
## Lane minion: walks the lane, fights by League's minion targeting rules.

enum Type { MELEE, CASTER, SIEGE, SUPER }

## [numbers] League Map12 data (HA_<Team>Minion* CharacterRecords + the HA BarracksConfig MinionUpgradeStats): base stats,
## per-upgrade growth (every 49.99 s; the first 6 upgrades use hp_up, later ones hp_late), gold growth per upgrade (the
## BarracksConfig variant with MS +25 every 300 s from 600 s, i.e. 325 -> 425 like the wiki's ARAM minion page).
## Melee 455 HP / 12 AD / 64 XP / 20 gold, caster 290 / 23 / 32 / 17, siege 805 / 40 / 94 / 44, super 1500 HP (10 regen) / 306 AD /
## 60 armor / 10 MR / 100 XP / 45 gold. windup = mAttackCastTime / mAttackTotalTime.
const UPGRADES_BEFORE_LATE := 6
const STATS := {
	Type.MELEE: {"hp": 455.0, "ad": 12.0, "as": 1.25, "range": 110.0, "armor": 0.0, "mr": 0.0, "xp": 64.0, "gold": 20.0,
		"radius": 0.48, "missile": 0.0, "hp_up": 19.8, "hp_late": 6.75, "ad_up": 1.0, "armor_up": 0.0, "gold_up": 0.125, "regen": 0.0, "windup": 0.491},
	Type.CASTER: {"hp": 290.0, "ad": 23.0, "as": 0.667, "range": 550.0, "armor": 0.0, "mr": 0.0, "xp": 32.0, "gold": 17.0,
		"radius": 0.48, "missile": 650.0, "hp_up": 6.6, "hp_late": 2.25, "ad_up": 2.0, "armor_up": 0.0, "gold_up": 0.0, "regen": 0.0, "windup": 0.313},
	Type.SIEGE: {"hp": 805.0, "ad": 40.0, "as": 1.0, "range": 300.0, "armor": 0.0, "mr": 0.0, "xp": 94.0, "gold": 44.0,
		"radius": 0.65, "missile": 1200.0, "hp_up": 25.3, "hp_late": 25.0, "ad_up": 1.5, "armor_up": 0.0, "gold_up": 0.35, "regen": 0.0, "windup": 0.3},
	Type.SUPER: {"hp": 1500.0, "ad": 306.0, "as": 0.694, "range": 170.0, "armor": 60.0, "mr": 10.0, "xp": 100.0, "gold": 45.0,
		"radius": 0.65, "missile": 0.0, "hp_up": 100.0, "hp_late": 100.0, "ad_up": 5.0, "armor_up": 0.0, "gold_up": 0.35, "regen": 10.0, "windup": 0.347},
}
const MODEL_NAMES := {Type.MELEE: "MinionMelee", Type.CASTER: "MinionRanged", Type.SIEGE: "MinionSiege", Type.SUPER: "MinionSuper"}

var minion_type := Type.MELEE
var lane: Array = []             ## waypoints (world) toward the enemy base
var lane_i := 0
var xp_value := 60.0
var gold_value := 20.0
var _think_timer := 0.0
var leash_origin := Vector3.ZERO
var aura_buffed := false


func _init() -> void:
	super._init()
	kind = G.Kind.MINION
	path_radius = 0.42
	mass = 0.6
	height = 1.3
	selection_radius = 0.75
	stats.uses_mana = false


func setup(p_team: int, t: int, upgrades: int, lane_points: Array, ms: float) -> void:
	team = p_team
	minion_type = t
	var d: Dictionary = STATS[t]
	display_name = ["Melee", "Caster", "Siege", "Super"][t] + " Minion"
	radius = d.radius
	path_radius = d.radius * 0.85
	if t == Type.SIEGE or t == Type.SUPER:
		mass = 1.2
		height = 1.8
	windup_pct = d.windup
	attack_missile_speed = d.missile
	xp_value = d.xp
	gold_value = d.gold + d.gold_up * upgrades
	var n_early := mini(upgrades, UPGRADES_BEFORE_LATE)
	var n_late := maxi(upgrades - UPGRADES_BEFORE_LATE, 0)
	lane = lane_points
	stats.set_base({
		"base_hp": d.hp + d.hp_up * n_early + d.hp_late * n_late, "hp_per_level": 0.0, "base_hp_regen": d.regen, "hp_regen_per_level": 0.0,
		"base_ad": d.ad + d.ad_up * upgrades, "ad_per_level": 0.0,
		"base_armor": d.armor + d.armor_up * upgrades, "armor_per_level": 0.0,
		"base_mr": d.mr, "mr_per_level": 0.0, "base_ms": ms, "attack_range": d.range,
		"attack_speed": d.as, "attack_speed_ratio": d.as, "attack_speed_per_level": 0.0,
		"mana_base": 0.0, "mana_per_level": 0.0, "mana_regen": 0.0, "mana_regen_per_level": 0.0,
	})
	recompute_stats()
	hp = stats.max_hp
	acquisition_range = 7.0 if t != Type.CASTER else 7.5
	var model_name: String = ("HA_Order" if team == G.Team.ORDER else "HA_Chaos") + MODEL_NAMES[t]
	var m := Assets.unit_model(model_name, 0)
	if m == null:
		m = Assets.placeholder_model(team, 1.0 if t != Type.SIEGE else 1.4)
	set_model(m)
	anim_map = Assets.build_anim_map(anim_player, {})
	display_scale = 1.0
	# League minion graph + attack timing (windup = mAttackCastTime / mAttackTotalTime, missile bone)
	var g := AnimGraph.load_for(model_name)
	set_anim_graph(g)
	# League minions keep apart by their gameplay radius (overrideGameplayCollisionRadius 48 for
	# melee/caster): waves spread out instead of stacking
	if g != null:
		var gr := float(g.stats.get("overrideGameplayCollisionRadius", 0.0))
		if gr > 0.0:
			path_radius = gr * G.U * 0.95


func sight_range() -> float:
	return 11.0


func base_run_speed() -> float:
	return 325.0


func auto_attacks_when_idle() -> bool:
	return false


func think(dt: float) -> void:
	_think_timer -= dt
	if _think_timer > 0.0:
		return
	_think_timer = 0.2 + G.rng.randf() * 0.1
	if windup_timer >= 0.0:
		return
	var t := _choose_target()
	if t != null:
		if t != attack_target:
			attack_target = t
			cmd = Cmd.ATTACK
			_repath_timer = 0.0
		return
	attack_target = null
	_follow_lane()


func _follow_lane() -> void:
	while lane_i < lane.size() and G.flat_dist(global_position, lane[lane_i]) < 2.0:
		lane_i += 1
	# skip waypoints we've already passed (minions pushed around)
	if lane_i < lane.size() - 1:
		var a: Vector3 = lane[lane_i]
		var b: Vector3 = lane[lane_i + 1]
		if G.flat_dist(global_position, b) < G.flat_dist(a, b):
			lane_i += 1
	if lane_i >= lane.size():
		return
	var goal: Vector3 = lane[lane_i]
	cmd = Cmd.MOVE
	if not moving or G.flat_dist(move_goal, goal) > 0.5:
		_set_path_to(goal)


func _choose_target() -> Unit:
	if match_ref == null:
		return null
	var now: float = match_ref.time
	var keep := attack_valid(attack_target) and G.flat_dist(global_position, attack_target.global_position) <= acquisition_range + 3.0
	# call for help: an enemy champion damaging an allied champion nearby
	var best: Unit = null
	var best_score := INF
	var near: Array = match_ref.units_in_radius(global_position, acquisition_range, -1)
	for u in near:
		if u.team == team or u.dead or not u.is_targetable_by(team):
			continue
		var d := G.flat_dist(global_position, u.global_position)
		var score := d
		match u.kind:
			G.Kind.CHAMPION:
				score += 30.0
				if now - u.get_meta("last_hit_ally_champ", -100.0) < 2.5:
					score -= 60.0   # aggro: attacked one of our champions
			G.Kind.MINION, G.Kind.SUMMON:
				score += 0.0
			G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS:
				score += 12.0
		if score < best_score:
			best_score = score
			best = u
	if keep and best != null and attack_target != best:
		# stick with current target unless the new one is a call-for-help champion
		if not (best.kind == G.Kind.CHAMPION and now - best.get_meta("last_hit_ally_champ", -100.0) < 2.5):
			return attack_target
	if best == null and keep:
		return attack_target
	return best


func on_died(_killer) -> void:
	# League: the minion plays its death clip, the corpse lies briefly, then fades out while sinking
	var death_len := 1.0
	if anim_player != null and anim_player.current_animation != "":
		death_len = anim_player.current_animation_length / maxf(absf(anim_player.get_playing_speed()), 0.05)
	var tw := create_tween()
	tw.tween_interval(clampf(death_len, 0.5, 2.5) + 0.35)
	var fade_fn := func(v: float) -> void:
		corpse_fade = v
		_apply_transparency(v)
		if model != null:
			model.position.y = -0.35 * v
	tw.tween_method(fade_fn, 0.0, 1.0, 0.7)
	tw.tween_callback(func():
		if match_ref != null:
			match_ref.remove_unit(self)
		else:
			queue_free())


func _update_visual(dt: float) -> void:
	super._update_visual(dt)
