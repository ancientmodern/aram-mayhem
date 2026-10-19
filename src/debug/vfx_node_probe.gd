extends Node
## [vfx-calib] Spawns one League system at the camera focus (ground point), screenshots it and dumps every emitter
## node (visibility, transform, AABB, key material / process parameters).
## tools/preview.sh 120 -- --champ=Lux --harness=res://src/debug/vfx_node_probe.gd --probesys=Lux_Base_E_tar_aoe_green \
##     [--probet=2.0] [--vfxemit=Temp_GroundGlow] [--shotdir=vprobe]
var match_ref = null
var main = null


func _ready() -> void:
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _run() -> void:
	var sys := "Lux_Base_E_tar_aoe_green"
	var t := 2.0
	var yoff := 0.0
	var dir := "user://vprobe"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--probesys="):
			sys = a.substr(11)
		elif a.begins_with("--probet="):
			t = float(a.substr(9))
		elif a.begins_with("--probey="):
			yoff = float(a.substr(9))
		elif a.begins_with("--shotdir="):
			dir = "user://" + a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	await _wait(1.0)
	var m = G.match
	var c = G.player
	if m.hud != null:
		m.hud.visible = false
	LolVfx.load_set(sys.get_slice("_", 0))
	LolVfx.load_set("shared")
	var spot: Vector3 = m.nav.nearest_walkable((m.outer_turrets[0].global_position + m.outer_turrets[1].global_position) * 0.5)
	c.teleport(spot + Vector3(-4, 0, 0))
	m.camera_rig.locked = false
	m.camera_rig.focus = spot
	m.camera_rig.target_distance = 14.0
	m.camera_rig.distance = 14.0
	await _wait(1.0)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/base.png")
	var gp: Vector3 = spot
	gp.y = m.nav.height_at(spot) + yoff
	var fx := LolVfx.spawn(m, sys, gp, {"dir": Vector3.RIGHT})
	await _wait(t)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir + "/shot.png")
	print("PROBE ground y=", gp.y, " terrain=", m.nav.height_at(spot))
	_dump(fx, 0)
	print("PROBE DONE")
	get_tree().quit()


func _dump(n: Node, depth: int) -> void:
	if n == null:
		return
	var pad := "  ".repeat(depth)
	if n is GPUParticles3D:
		var p: GPUParticles3D = n
		var mat: ShaderMaterial = p.draw_pass_1.surface_get_material(0) if p.draw_pass_1 != null and p.draw_pass_1.get_surface_count() > 0 else null
		if mat == null and p.material_override is ShaderMaterial:
			mat = p.material_override
		var info := ""
		if mat != null:
			for k in ["palette_v", "has_palette", "alpha_ref", "billboard", "depth_bias", "intensity", "has_erosion"]:
				info += " %s=%s" % [k, str(mat.get_shader_parameter(k))]
			info += " prio=%d shader_has_nodepth=%s" % [mat.render_priority, str(mat.shader.code.contains("depth_test_disabled"))]
		print("PROBE %sGPU %s vis=%s emit=%s amount=%d pos=%s basis_scale=%s aabb=%s%s" % [pad, n.name, p.visible, p.emitting, p.amount,
				p.global_position.snapped(Vector3.ONE * 0.01), p.global_transform.basis.get_scale().snapped(Vector3.ONE * 0.01), p.visibility_aabb, info])
	elif n is MeshInstance3D:
		print("PROBE %sMESH %s vis=%s pos=%s" % [pad, n.name, n.visible, n.global_position])
	elif n is Node3D:
		print("PROBE %sN3D %s vis=%s pos=%s" % [pad, n.name, n.visible, (n as Node3D).global_position.snapped(Vector3.ONE * 0.01)])
	for ch in n.get_children():
		_dump(ch, depth + 1)
