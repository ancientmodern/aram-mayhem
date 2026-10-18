class_name Structure
extends Unit
## Inhibitor or Nexus.

var guards: Array = []
var respawn_at := -1.0
var is_inhibitor := true


func _init() -> void:
	super._init()
	kind = G.Kind.INHIBITOR
	radius = 2.0
	path_radius = 2.2
	mass = 0.0
	height = 3.0
	selection_radius = 2.5
	stats.uses_mana = false


func setup(p_team: int, inhibitor: bool) -> void:
	team = p_team
	is_inhibitor = inhibitor
	kind = G.Kind.INHIBITOR if inhibitor else G.Kind.NEXUS
	display_name = "Inhibitor" if inhibitor else "Nexus"
	radius = 2.0 if inhibitor else 3.4
	path_radius = radius + 0.2
	height = 3.0 if inhibitor else 5.0
	selection_radius = radius + 0.5
	stats.set_base({
		"base_hp": 4000.0 if inhibitor else 3000.0, "hp_per_level": 0.0,
		"base_hp_regen": 15.0 if inhibitor else 10.0, "hp_regen_per_level": 0.0,
		"base_ad": 0.0, "ad_per_level": 0.0, "base_armor": 20.0, "armor_per_level": 0.0,
		"base_mr": 20.0, "mr_per_level": 0.0, "base_ms": 0.0, "attack_range": 0.0,
		"attack_speed": 0.1, "attack_speed_ratio": 0.1, "attack_speed_per_level": 0.0,
		"mana_base": 0.0, "mana_per_level": 0.0, "mana_regen": 0.0, "mana_regen_per_level": 0.0,
	})
	recompute_stats()
	hp = stats.max_hp
	var skin: int
	var name: String
	if inhibitor:
		name = "Inhibitor"
		skin = 22 if team == G.Team.ORDER else 23
	else:
		name = "Nexus"
		skin = 24 if team == G.Team.ORDER else 25
	var m := Assets.unit_model(name, skin)
	if m == null:
		m = Assets.placeholder_model(team, 2.5 if inhibitor else 4.0, 2.0)
	set_model(m)
	anim_map = Assets.build_anim_map(anim_player, {})
	LolVfx.load_set("shared")
	_idle_fx = LolVfx.attach(self, "HA_%s_%s_Idle" % ["Order" if team == G.Team.ORDER else "Chaos", "Inhibitor" if inhibitor else "Nexus"], {"loop": true})


var _idle_fx: LolVfx = null
var _timer_fx: LolVfx = null


func is_vulnerable() -> bool:
	for g in guards:
		if is_instance_valid(g) and not g.dead:
			return false
	return true


func is_invulnerable() -> bool:
	return super.is_invulnerable() or not is_vulnerable()


func auto_attacks_when_idle() -> bool:
	return false


func damage_taken_multiplier(_src) -> float:
	return 1.0


func on_died(_killer) -> void:
	if match_ref == null:
		return
	if is_inhibitor:
		respawn_at = match_ref.time + Rules.INHIBITOR_RESPAWN
		match_ref.on_structure_fell(self)
	var m = match_ref
	var p := global_position
	var col := Color(1.0, 0.75, 0.4) if team == G.Team.CHAOS else Color(0.55, 0.8, 1.0)
	if _idle_fx != null and is_instance_valid(_idle_fx):
		_idle_fx.stop()
	var tname := "Order" if team == G.Team.ORDER else "Chaos"
	var boom := LolVfx.spawn(m, "HA_Order_Inhibitor_Explosion" if is_inhibitor else "HA_Order_Nexus_Explosion", p, {"max_life": 14.0})
	if is_inhibitor:
		_timer_fx = LolVfx.attach(self, "HA_%s_Inhibitor_runeTimer" % tname, {"loop": true})
		LolVfx.attach(self, "HA_%s_Inhibitor_Rubble_dust" % tname)
	if has_anim("death"):
		_play_once("death")
	elif model != null:
		create_tween().tween_property(model, "scale", model.scale * Vector3(1.0, 0.25, 1.0), 1.5)
	# explosions: the nexus goes off in a rolling chain
	var blasts := (1 if is_inhibitor else 6) if boom == null else (0 if is_inhibitor else 2)
	for i in blasts:
		m.after(i * 0.32, func():
			var off := Vector3(G.rng.randf_range(-1.5, 1.5), G.rng.randf_range(0.5, 3.0), G.rng.randf_range(-1.5, 1.5)) * (0.4 if is_inhibitor else 1.0)
			Vfx.burst(m, p + off, col, 2.2 if is_inhibitor else 3.2, {"sparks": 60})
			Vfx.ring(m, p, col, 4.5 if is_inhibitor else 7.0, 0.6, 0.12, 0.2)
			if m.camera_rig != null and G.flat_dist(m.camera_rig.focus, p) < 30.0:
				m.camera_rig.shake(0.35 if is_inhibitor else 0.55))


## Play a clip once and hold its last frame (death poses).
func _play_once(logical: String) -> void:
	var names: Array = anim_map.get(logical, [])
	var n: String = names[0] if not names.is_empty() else _raw_clip(logical)
	if n == "" or anim_player == null or not anim_player.has_animation(n):
		return
	anim_player.get_animation(n).loop_mode = Animation.LOOP_NONE
	anim_player.play(n, 0.1)
	cur_anim = logical
	anim_lock = 9999.0


func tick_dead(_dt: float) -> void:
	if is_inhibitor and respawn_at > 0.0 and match_ref != null and match_ref.time >= respawn_at:
		dead = false
		respawn_at = -1.0
		hp = stats.max_hp
		if model != null:
			model.scale = Vector3.ONE * stats.size * display_scale
		anim_lock = 0.0
		if _timer_fx != null and is_instance_valid(_timer_fx):
			_timer_fx.stop()
		_idle_fx = LolVfx.attach(self, "HA_%s_Inhibitor_Idle" % ("Order" if team == G.Team.ORDER else "Chaos"), {"loop": true})
		if has_anim("respawn_in"):
			_play_once("respawn_in")
			anim_lock = 1.5
		else:
			play_anim("idle", 1.0, 0.0)
		G.announce("Inhibitor respawned", "", G.COLOR_ALLY if team == G.player.team else G.COLOR_ENEMY)
