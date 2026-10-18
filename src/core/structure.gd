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
	if model != null:
		var tw := create_tween()
		tw.tween_property(model, "scale", model.scale * Vector3(1.0, 0.25, 1.0), 1.5)


func tick_dead(_dt: float) -> void:
	if is_inhibitor and respawn_at > 0.0 and match_ref != null and match_ref.time >= respawn_at:
		dead = false
		respawn_at = -1.0
		hp = stats.max_hp
		if model != null:
			model.scale = Vector3.ONE * stats.size * display_scale
		play_anim("idle", 1.0, 0.0)
		G.announce("Inhibitor respawned", "", G.COLOR_ALLY if team == G.player.team else G.COLOR_ENEMY)
