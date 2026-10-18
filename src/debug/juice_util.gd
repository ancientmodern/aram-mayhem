class_name JuiceUtil
extends RefCounted
## [juice] helpers shared by the src/debug/juice_*.gd harnesses (staging key moments + screenshots).

static func wait(n: Node, s: float) -> void:
	await n.get_tree().create_timer(s, true, false, true).timeout


static func shot(n: Node, dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [dir, name]
	n.get_viewport().get_texture().get_image().save_png(path)
	print("JUICE SHOT ", ProjectSettings.globalize_path(path))


## Park the player in the open bridge area, camera close. Returns the spot.
static func park(m, dist: float = 12.0) -> Vector3:
	var c = G.player
	var spot: Vector3 = m.nav.nearest_walkable((m.outer_turrets[0].global_position + m.outer_turrets[1].global_position) * 0.5)
	c.controller = null if c.controller == null else c.controller
	c.teleport(spot)
	m.camera_rig.locked = true
	m.camera_rig.min_dist = 4.0
	m.camera_rig.target_distance = dist
	m.camera_rig.distance = dist
	return spot


static func out_dir(name: String) -> String:
	var d := "user://" + name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))
	return d


## Remove every other unit so a staged moment is readable (they stay frozen out of frame).
static func clear_stage(m, keep: Array) -> void:
	for u in m.units:
		if is_instance_valid(u) and not (u in keep) and u.kind in [G.Kind.MINION]:
			u.teleport(Vector3(0, -50, 0)) if false else null
