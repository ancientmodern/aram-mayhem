extends Node
## [spatial] Dumps the effective spatial numbers of every roster champion (attack range, gameplay radius,
## each ability's cast range / indicator radius / width / length / cone angle) as JSON lines, for
## docs/SPATIAL_AUDIT.md. Usage: godot --headless --path . -- --champ=Ezreal --harness=res://src/debug/spatial_ranges.gd
var main = null
var match_ref = null


func _ready() -> void:
	_run()


func _run() -> void:
	await get_tree().create_timer(0.5, true, false, true).timeout
	for alias in ChampionDB.ROSTER:
		var c := Champion.new()
		c.setup(alias, G.Team.CHAOS, 0)
		match_ref.add_unit(c, Vector3(64, 0, -64))
		var row := {"alias": alias, "attack_range": c.stats.attack_range, "radius_u": c.radius / G.U,
			"path_radius_u": c.path_radius / G.U, "selection_radius_u": c.selection_radius / G.U,
			"acq_u": c.get("acquisition_range") / G.U if c.get("acquisition_range") != null else -1.0,
			"missile_speed": c.attack_missile_speed, "abilities": []}
		for a in c.abilities:
			if a == null:
				continue
			row.abilities.append({"key": a.key, "class": a.get_script().resource_path.get_file() if a.get_script() else "",
				"name": a.display_name, "target": a.target_type, "ind": a.indicator, "cast_range": a.cast_range,
				"ring_u": a.indicator_range_m() / G.U, "edge": a.range_edge, "ind_radius": a.ind_radius, "ind_width": a.ind_width, "ind_length": a.ind_length, "ind_angle": a.ind_angle})
		print("SPATIAL ", JSON.stringify(row))
		c.queue_free()
	for s in match_ref.structures:
		print("SPATIAL_STRUCT ", s.display_name, " range=", s.stats.attack_range, " radius_u=", s.radius / G.U)
	get_tree().quit()
