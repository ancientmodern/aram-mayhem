extends Node
## [env] visual check harness: moves the camera to fixed spots and takes screenshots.
## Usage: tools/preview.sh 200 -- --champ=Ezreal --harness=res://src/env/env_harness.gd --envplan=look --shotdir=env_x
## Plans: look (map tour), turret (damage states + collapse of the Order outer turret), player (locked camera),
##        brush (player walks into brush), zoom (min/max zoom), chaos (Chaos outer turret collapse)

var match_ref = null
var main = null
var _t := 0.0
var _steps: Array = []     ## [time, Callable]
var _dir := "user://env_shots"
var _plan := "look"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--envplan="):
			_plan = a.substr(10)
		elif a.begins_with("--shotdir="):
			_dir = "user://" + a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_dir))
	G.settings.edge_pan = false
	call_deferred("_build")


func _build() -> void:
	var m = match_ref
	var rig = m.camera_rig
	var t := 2.0
	match _plan:
		"look":
			var spots := {
				"fountain": m.spawn_points[0],
				"order_outer": m.outer_turrets[0].global_position,
				"mid": m.lane_path[m.lane_path.size() / 2],
				"chaos_outer": m.outer_turrets[1].global_position,
				"order_inhib": m.inhibitor_units[0].global_position,
				"chaos_base": m.nexus_units[1].global_position,
			}
			for k in spots:
				var p: Vector3 = spots[k]
				_at(t, func(): _free_cam(p))
				_at(t + 2.5, func(): _shot(k))
				t += 3.0
		"player":
			_at(3.0, func(): _shot("player_locked"))
			_at(3.5, func():
				rig.target_distance = rig.min_dist
				rig.distance = rig.min_dist)
			_at(4.5, func(): _shot("player_minzoom"))
		"turret", "chaos":
			var tur = m.outer_turrets[0 if _plan == "turret" else 1]
			_at(t, func(): _free_cam(tur.global_position + Vector3(0, 0, 3)))
			_at(t + 1.5, func(): _shot("t_full"))
			_at(t + 2.0, func(): tur.hp = tur.stats.max_hp * 0.6)
			_at(t + 2.25, func(): _shot("t_break1_a"))
			_at(t + 2.8, func(): _shot("t_break1_b"))
			_at(t + 4.5, func(): _shot("t_state1"))
			_at(t + 5.0, func(): tur.hp = tur.stats.max_hp * 0.3)
			_at(t + 5.4, func(): _shot("t_break2"))
			_at(t + 7.5, func(): _shot("t_state2"))
			_at(t + 8.0, func(): tur.die(null))
			_at(t + 8.4, func(): _shot("t_die_a"))
			_at(t + 9.0, func(): _shot("t_die_b"))
			_at(t + 9.8, func(): _shot("t_die_c"))
			_at(t + 11.0, func(): _shot("t_die_d"))
			_at(t + 14.0, func(): _shot("t_rubble"))
			_at(t + 15.0, func(): _free_cam(tur.global_position + Vector3(4, 0, 6)))
			_at(t + 16.0, func(): _shot("t_rubble_wide"))
		"brazier":
			# brazier on the Order side of the bridge (Env_MB_brazierFire_particles2) and base snow (Env_MB_Snow_01_1)
			var bz := G.lol_pos(4916.87, 221.47, 3617.64)
			var sn := G.lol_pos(1396.12, -182.37, 1569.6)
			_at(t, func(): _free_cam(Vector3(bz.x, 0, bz.z)))
			_at(t + 2.0, func(): _shot("brazier_far"))
			_at(t + 2.2, func():
				rig.target_distance = 8.0
				rig.distance = 8.0)
			_at(t + 3.0, func(): _shot("brazier_near"))
			_at(t + 3.2, func(): _free_cam(Vector3(sn.x, -1.8, sn.z)))
			_at(t + 5.0, func(): _shot("snow_near"))
		"inhib":
			var inh = m.inhibitor_units[0]
			_at(t, func(): _free_cam(inh.global_position + Vector3(0, 0, 2)))
			_at(t + 1.5, func(): _shot("i_alive"))
			_at(t + 2.0, func(): inh.die(null))
			_at(t + 2.5, func(): _shot("i_die_a"))
			_at(t + 4.0, func(): _shot("i_die_b"))
			_at(t + 11.0, func(): _shot("i_dead"))
		"nav":
			_draw_nav_edges()
			var spots2 := {
				"nav_order_outer": m.outer_turrets[0].global_position,
				"nav_mid": m.lane_path[m.lane_path.size() / 2],
				"nav_q1": m.lane_path[m.lane_path.size() / 4],
				"nav_q3": m.lane_path[m.lane_path.size() * 3 / 4],
				"nav_order_base": m.inhibitor_units[0].global_position,
			}
			for k in spots2:
				var p2: Vector3 = spots2[k]
				_at(t, func(): _free_cam(p2))
				_at(t + 1.0, func(): _shot(k))
				t += 1.5
		"brush":
			var pl = G.player
			var target := Vector3.INF
			# nearest brush cell to the outer turret side of the lane
			var nav: NavGrid = m.nav
			var best := INF
			for p in m.lane_path:
				for dx in range(-12, 13, 2):
					for dz in range(-12, 13, 2):
						var q: Vector3 = p + Vector3(dx, 0, dz)
						if nav.brush_id(q) != 0 and nav.is_walkable(q):
							var d := G.flat_dist(q, m.spawn_points[0])
							if d < best:
								best = d
								target = q
			if target != Vector3.INF:
				# centroid of that brush region
				var rid := nav.brush_id(target)
				var acc := Vector3.ZERO
				var cnt := 0
				var c0 := nav.to_cell(target)
				for j in range(c0.y - 40, c0.y + 41):
					for i in range(c0.x - 40, c0.x + 41):
						if nav.in_bounds(Vector2i(i, j)) and nav.brush[j * nav.w + i] == rid:
							acc += nav.cell_center(Vector2i(i, j))
							cnt += 1
				var cen: Vector3 = acc / maxf(1, cnt)
				print("BRUSH region ", rid, " cells ", cnt, " centroid ", cen, " id_at_centroid ", nav.brush_id(cen))
				_at(1.0, func(): pl.teleport(cen + Vector3(4, 0, 0)))
				_at(1.5, func(): _shot("brush_before"))
				_at(2.0, func(): pl.teleport(cen))
				_at(2.3, func(): _shot("brush_enter"))
				_at(3.5, func():
					print("BRUSH player id ", nav.brush_id(pl.global_position))
					_shot("brush_inside"))
				_at(4.0, func():
					rig.target_distance = 12.0
					rig.distance = 12.0)
				_at(4.8, func(): _shot("brush_inside_near"))
	_at(_last() + 1.0, func(): get_tree().quit())


## Red line strips along every walkable/unwalkable cell edge (0.5 m cells), slightly above the ground.
func _draw_nav_edges() -> void:
	var nav: NavGrid = match_ref.nav
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for j in nav.h - 1:
		for i in nav.w - 1:
			var a: int = nav.walk[j * nav.w + i]
			var b: int = nav.walk[j * nav.w + i + 1]
			var c: int = nav.walk[(j + 1) * nav.w + i]
			if a != b:
				var x := nav.origin.x + (i + 1) * nav.cell
				var z0 := nav.origin.y + j * nav.cell
				var y := nav._h(i, j) + 0.08
				im.surface_add_vertex(Vector3(x, y, z0))
				im.surface_add_vertex(Vector3(x, y, z0 + nav.cell))
			if a != c:
				var z := nav.origin.y + (j + 1) * nav.cell
				var x0 := nav.origin.x + i * nav.cell
				var y2 := nav._h(i, j) + 0.08
				im.surface_add_vertex(Vector3(x0, y2, z))
				im.surface_add_vertex(Vector3(x0 + nav.cell, y2, z))
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 0.1, 0.1)
	mat.no_depth_test = true
	mi.material_override = mat
	match_ref.add_child(mi)


func _last() -> float:
	var mx := 0.0
	for s in _steps:
		mx = maxf(mx, s[0])
	return mx


func _at(time: float, fn: Callable) -> void:
	_steps.append([time, fn])


func _free_cam(p: Vector3) -> void:
	var rig = match_ref.camera_rig
	rig.target = null
	rig.locked = false
	rig.focus = p
	rig.snap_to(p)


func _shot(nm: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_dir, nm]
	img.save_png(path)
	print("SHOT ", ProjectSettings.globalize_path(path), " fps=", Engine.get_frames_per_second())


func _process(dt: float) -> void:
	_t += dt
	var i := 0
	while i < _steps.size():
		if _t >= _steps[i][0]:
			var fn: Callable = _steps[i][1]
			_steps.remove_at(i)
			fn.call()
		else:
			i += 1
