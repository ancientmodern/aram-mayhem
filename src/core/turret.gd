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
## [numbers] League Howling Abyss turret scaling = the "Tower Power-Up" item (Global Items/1522) + HA_* CharacterRecords:
## attack damage +9/min (outer, until 12:00) or +12/min (inhibitor / nexus turret, until 15:00) on top of 185 / 205 / 195,
## armor and magic resist +3/min until 8:10 (StatAddEndTime 490: +21, published 60-81 / 63-84 / 60-81), and the outer turret's
## resists fall to 40 at 12:00 (BonusStatsFalloffTime 720). The wiki's published ranges (185-293, 205-385, 195-375) match.
const AD_PER_MIN := [9.0, 12.0, 12.0, 0.0]
const AD_RAMP_END := [720.0, 900.0, 900.0, 0.0]
const RESIST_GAIN := 21.0
const RESIST_START := 60.0
const RESIST_END := 490.0
const OUTER_DECAY_TIME := 720.0
const OUTER_DECAY_RESIST := 40.0
const FORTIFY_REDUCTION := 0.35            ## Fortification (Items/1521): blocks 35% of damage for 60 s once the outer turret falls
const FORTIFY_TIME := 60.0
var base_resist := 60.0
var _regen_t := 0.0


func _init() -> void:
	super._init()
	kind = G.Kind.TURRET
	radius = 0.884                 ## [spatial] League overrideGameplayCollisionRadius 88.4 (HA_Outer / HA_Nexus / shrine)
	path_radius = 1.2
	mass = 0.0
	height = 6.2
	selection_radius = 1.3   # [path] League turret selectionRadius 130 u (was 1.8: a click in the brush beside the outer turret attacked it)
	stats.uses_mana = false
	windup_pct = 0.139             # [numbers] mAttackDelayCastOffsetPercent -0.161 -> 0.3 - 0.161 (was 0.15)


func setup(p_team: int, p_tier: int) -> void:
	team = p_team
	tier = p_tier
	display_name = ["Outer Turret", "Inhibitor Turret", "Nexus Turret", "Fountain Turret"][p_tier]
	# [numbers] HA_Outer 1300 / HA_Inhibitor 3900 / HA_Nexus 1800 base HP + 250 per enemy champion (5v5: +1250); armor and
	# magic resist 60 / 63 / 60 (grown per minute in think()); base AD 185 / 205 / 195; attack speed 0.833, range 750.
	var hp_by_tier := [1300.0 + 5.0 * Rules.TURRET_HP_PER_ENEMY_CHAMP, 3900.0 + 5.0 * Rules.TURRET_HP_PER_ENEMY_CHAMP,
			1800.0 + 5.0 * Rules.TURRET_HP_PER_ENEMY_CHAMP, 99999.0]
	var armor_by_tier := [60.0, 63.0, 60.0, 0.0]
	base_resist = armor_by_tier[p_tier]
	base_ad = [185.0, 205.0, 195.0, 999.0][p_tier]
	ad_per_min = AD_PER_MIN[p_tier]
	stats.set_base({
		"base_hp": hp_by_tier[p_tier], "hp_per_level": 0.0, "base_hp_regen": 0.0, "hp_regen_per_level": 0.0,
		"base_ad": base_ad, "ad_per_level": 0.0, "base_armor": armor_by_tier[p_tier], "armor_per_level": 0.0,
		"base_mr": armor_by_tier[p_tier], "mr_per_level": 0.0, "base_ms": 0.0,
		"attack_range": 750.0 if p_tier != Tier.FOUNTAIN else 1100.0,   # [spatial] League HA shrine attackRange 1100
		"attack_speed": 0.833 if p_tier != Tier.FOUNTAIN else 2.5, "attack_speed_ratio": 0.833 if p_tier != Tier.FOUNTAIN else 2.5,
		"attack_speed_per_level": 0.0,
		"mana_base": 0.0, "mana_per_level": 0.0, "mana_regen": 0.0, "mana_regen_per_level": 0.0,
	})
	recompute_stats()
	hp = stats.max_hp
	attack_missile_speed = 1200.0 if p_tier != Tier.FOUNTAIN else 3000.0   # [numbers] TurretBasicAttack missileSpeed 1200 (was 1300)
	if p_tier == Tier.FOUNTAIN:
		windup_pct = 0.4   # [timing] HA_AP_OrderShrineTurret mAttackDelayCastOffsetPercent +0.1 -> 0.3 + 0.1 (the lane turrets use 0.139)
	var skin := 28 if team == G.Team.ORDER else (31 if p_tier == Tier.FOUNTAIN else 29)
	var m := Assets.unit_model("Turret", skin)
	if m == null:
		m = Assets.placeholder_model(team, 5.0, 1.0)
	set_model(m)
	anim_map = Assets.build_anim_map(anim_player, {})
	_index_turret_meshes()
	# [anim-events] the skin's idle particle (HA_<team>_Turret_Weapon_Glow on joint2); this script runs the
	# damage-state clips itself
	setup_anim_events("turret_skin%d" % skin, null, true)
	# League ships Left/Right collapse variants per turret; alternate them so the two nexus turrets differ
	_nexus_count += 1 if p_tier == Tier.NEXUS else 0
	rubble_side = "right" if p_tier == Tier.INHIBITOR or (p_tier == Tier.NEXUS and _nexus_count % 2 == 0) else "left"
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
	# damage and resists scale with game time ([numbers] see AD_PER_MIN above)
	var gt: float = match_ref.time
	stats.base["base_ad"] = base_ad + AD_PER_MIN[tier] * minf(gt, AD_RAMP_END[tier]) / 60.0
	if tier != Tier.FOUNTAIN:
		var res := base_resist + RESIST_GAIN * clampf((gt - RESIST_START) / (RESIST_END - RESIST_START), 0.0, 1.0)
		if tier == Tier.OUTER and gt >= OUTER_DECAY_TIME:
			res = OUTER_DECAY_RESIST
		stats.base["base_armor"] = res
		stats.base["base_mr"] = res
	if match_ref.time - last_champ_shot > 5.0:
		ramp = 0
	_regen_t -= dt
	if _regen_t <= 0.0:
		_regen_t = 1.0
		_structure_regen()
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
			Minion.Type.SUPER: dmg = t.stats.max_hp * 0.05   # [numbers] wiki Turret (V6.22): melee 45%, caster 70%, siege 14%, super 5% of max HP (was 7%)
	# [numbers] the per-shot percentages are of max health and ignore armor (a super minion with 60 armor still dies in 20 shots)
	var dtype: int = G.DmgType.TRUE if (tier == Tier.FOUNTAIN or t.kind == G.Kind.MINION) else G.DmgType.PHYSICAL
	var info := Combat.deal(self, t, dmg, dtype, {"is_attack": true, "no_vamp": true})
	return info


func on_damaged(info: DamageInfo) -> void:
	super.on_damaged(info)


## Called by Combat: Howling Abyss Fortification on the inhibitor turret (35% less damage for 60 s once the outer turret has
## fallen). [numbers] HA turrets have no "Reinforced Armor" (that item says lane minions / Rift Herald, Summoner's Rift only)
## and no generic melee weakness: the Howling Abyss aura gives melee AP champions +20% vs structures instead (Combat).
func damage_taken_multiplier(_src) -> float:
	if match_ref != null and match_ref.time < backdoor_until:
		return 1.0 - FORTIFY_REDUCTION
	return 1.0


## [numbers] wiki Turret: inhibitor turrets regenerate 3 HP/s and nexus turrets 6 HP/s, but only up to the next health
## threshold (30/75/100% resp. 40/70/100% of max health) above their current health.
func _structure_regen() -> void:
	if dead or hp >= stats.max_hp:
		return
	var rate := 0.0
	var steps: Array = []
	if tier == Tier.INHIBITOR:
		rate = 3.0
		steps = [0.3, 0.75, 1.0]
	elif tier == Tier.NEXUS:
		rate = 6.0
		steps = [0.4, 0.7, 1.0]
	if rate <= 0.0:
		return
	var ratio := hp / stats.max_hp
	var cap := 1.0
	for st in steps:
		if ratio < st:
			cap = st
			break
	hp = minf(hp + rate, cap * stats.max_hp)


func on_died(_killer) -> void:
	aggro_line_target = null
	if match_ref != null:
		match_ref.on_structure_fell(self)
	if match_ref != null:
		if match_ref.camera_rig != null and G.flat_dist(match_ref.camera_rig.focus, global_position) < 30.0:
			match_ref.camera_rig.shake(0.45)
	_start_collapse()


# ===================================================================== visuals [env]
# League (DATA/Characters/Turret/Animations/Skin28.bin): the turret mesh has BaseState + State1-3 submeshes.
# Damage transitions swap the visible state and fire an animated-mesh "shatter" particle (chunks breaking off,
# HA_AP_<Team>_Turret_Shatter_01/02). On death State3 shows while Shatter_03_Left/Right plays the collapse; at
# frame 39 (1.3 s) the stump is replaced by a rubble submesh (MedRubble_Left / MedRubble_Right) and the fallen
# chunks rest in their *_Idle pose. The graph has no HP numbers; thresholds at 2/3 and 1/3 HP are our choice.
const SHATTER_DIR := "res://assets/structures/"
var _state_meshes: Array = []        ## [BaseState, State1, State2, State3]
var _rubble := {}                    ## submesh name -> MeshInstance3D
var _dmg_state := 0
var _collapse_t := -1.0
var _shatter: Node3D = null
static var _nexus_count := 0
var rubble_side := "left"            ## which way this turret falls (set per placement by tier)


func _index_turret_meshes() -> void:
	_state_meshes = [null, null, null, null]
	_rubble.clear()
	if model == null:
		return
	var stack: Array = [model]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not (n is MeshInstance3D):
			continue
		var nm := String(n.name).replace("HIDDEN__", "")
		var idx := ["BaseState", "State1", "State2", "State3"].find(nm)
		if idx >= 0:
			_state_meshes[idx] = n
		elif nm.contains("Rubble"):
			_rubble[nm] = n
	_show_state(0)


func _show_state(i: int) -> void:
	for k in _state_meshes.size():
		if _state_meshes[k] != null:
			_state_meshes[k].visible = k == i
	if i >= 0:
		for r in _rubble.values():
			r.visible = false


func _team_key() -> String:
	return "order" if team == G.Team.ORDER else "chaos"


## Animated debris mesh (League Temp_MeshAnim particle) placed in the turret's frame, using its material.
func _spawn_shatter(file: String, clip: String, life: float, fade_at: float) -> Node3D:
	var path := SHATTER_DIR + file + ".glb"
	if model == null or not ResourceLoader.exists(path) or _state_meshes[0] == null:
		return null
	var inst: Node3D = (load(path) as PackedScene).instantiate()
	var holder := Node3D.new()
	holder.add_child(inst)
	var base_inst: Node3D = _state_meshes[0].get_parent()
	while base_inst != null and base_inst.get_parent() != model:
		base_inst = base_inst.get_parent()
	holder.transform = base_inst.transform if base_inst != null else Transform3D.IDENTITY
	holder.rotate_object_local(Vector3.UP, PI)     # League particle birthRotation (0, 180, 0)
	model.add_child(holder)
	var src_mi: MeshInstance3D = _state_meshes[0]
	var mat: Material = src_mi.get_surface_override_material(0)
	var meshes: Array = []
	var stack: Array = [inst]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			for si in mi.mesh.get_surface_count():
				mi.set_surface_override_material(si, mat)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			meshes.append(mi)
	var ap := Assets._find_anim(inst)
	if ap != null and ap.has_animation(clip):
		var a := ap.get_animation(clip)
		a.loop_mode = Animation.LOOP_LINEAR if clip.ends_with("idle") else Animation.LOOP_NONE
		ap.play(clip)
	if life > 0.0:
		var tw := holder.create_tween()
		tw.tween_interval(fade_at)
		tw.tween_method(func(v: float):
			for mi in meshes:
				if is_instance_valid(mi):
					mi.set_instance_shader_parameter("fade", v), 1.0, 0.0, maxf(0.1, life - fade_at))
		tw.tween_callback(holder.queue_free)
	return holder


func _update_damage_state() -> void:
	if _state_meshes.is_empty() or dead or tier == Tier.FOUNTAIN:
		return
	var r := hp_ratio()
	var want := 0 if r > 2.0 / 3.0 else (1 if r > 1.0 / 3.0 else 2)
	if want == _dmg_state:
		return
	var up := want > _dmg_state
	_dmg_state = want
	_show_state(want)
	if up:
		# Shatter_01 / _02: chunks break off and fade (League colour curve fades out by 30% of 6.2 s)
		_spawn_shatter("turret_shatter_%s_%d" % [_team_key(), want], "shatter", 2.2, 1.2)
		if match_ref != null and match_ref.camera_rig != null 				and G.flat_dist(match_ref.camera_rig.focus, global_position) < 25.0:
			match_ref.camera_rig.shake(0.15)


func _start_collapse() -> void:
	_collapse_t = 0.0
	_dmg_state = 3
	_show_state(3)
	var file := "turret_shatter_%s_3" % _team_key()
	_shatter = _spawn_shatter(file, rubble_side, 0.0, 0.0)
	# the particle half of League's Shatter_03 system (dust, ground flash, debris); the mesh half is the glb above
	LolVfx.load_set("map12")
	_shatter_fx(_shatter_name(), false)


func _shatter_name() -> String:
	var tn := "Order" if team == G.Team.ORDER else "Chaos"
	var nm := "HA_AP_%s_Turret_Shatter_03_%s" % [tn, "Left" if rubble_side == "left" else "Right"]
	if not LolVfx.has(nm):
		nm = "HA_AP_%s_Turret_Shatter_03_Left" % tn
	return nm


func _shatter_fx(nm: String, loop: bool) -> void:
	if not LolVfx.has(nm) or model == null:
		return
	var fx := LolVfx.make(nm, {"loop": loop, "max_life": 8.0})
	if fx != null:
		add_child(fx)
		fx.global_position = global_position
		fx.global_basis = model.global_basis.orthonormalized().rotated(Vector3.UP, PI)


func tick_dead(dt: float) -> void:
	if _collapse_t < 0.0:
		return
	var prev := _collapse_t
	_collapse_t += dt
	if prev < 1.3 and _collapse_t >= 1.3:
		# frame 39: the stump becomes rubble
		_show_state(-1)
		for k in _state_meshes.size():
			if _state_meshes[k] != null:
				_state_meshes[k].visible = false
		var nm := "MedRubble_Left" if rubble_side == "left" else "MedRubble_Right"
		_show_rubble(nm)
	if prev < 4.0 and _collapse_t >= 4.0 and _shatter != null and is_instance_valid(_shatter):
		var ap := Assets._find_anim(_shatter)
		var idle := rubble_side + "_idle"
		if ap != null and ap.has_animation(idle):
			ap.get_animation(idle).loop_mode = Animation.LOOP_LINEAR
			ap.play(idle, 0.2)
		_shatter_fx(_shatter_name() + "_Idle", true)   # smouldering rubble
		_collapse_t = -1.0


func _show_rubble(nm: String) -> void:
	var mi: MeshInstance3D = _rubble.get(nm)
	if mi == null:
		return
	# Assets hides rubble surfaces with an invisible material; restore the real textured one
	for si in mi.mesh.get_surface_count():
		var src := mi.mesh.surface_get_material(si)
		if src != null:
			mi.set_surface_override_material(si, Assets._champion_material(src, 0.0))
	mi.visible = true


## League attack windup: the crystal charges up (SRU_<Team>_Turret_BA_Cas_Champ_0N on champion shots).
func _start_attack(t: Unit) -> void:
	super._start_attack(t)
	if t != null and is_instance_valid(t) and t.kind == G.Kind.CHAMPION and tier != Tier.FOUNTAIN:
		LolVfx.load_set("map12")
		var nm := "SRU_%s_Turret_BA_Cas_Champ_%02d" % ["Order" if team == G.Team.ORDER else "Chaos", clampi(ramp + 1, 1, 4)]
		var fx := LolVfx.make(nm, {})
		if fx != null:
			add_child(fx)
			fx.global_position = missile_origin()


func _update_visual(dt: float) -> void:
	_update_damage_state()
	super._update_visual(dt)
