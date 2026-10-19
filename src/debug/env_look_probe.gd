extends Node
## [env-look] Environment colour probe: frames the camera like a League reference capture and saves the normal
## frame plus the map shader's debug views (diffuse only, baked light, sun term, sun mask) for offline fitting
## against the reference (docs/ENV_LOOK.md).
## Usage: tools/preview.sh 150 -- --champ=Ezreal --nofow --res=2000x1127 --harness=res://src/debug/env_look_probe.gd \
##          --el_pin=4943,4929:170,1180 --el_dir=envlook_r1 [--el_views=0,1,2,3,4] [--el_units=1]
##   --el_pin=x,z:px,py  League point (x, z) placed at that pixel of a 2000-px-wide reference frame
##   --el_cam=fov:pitch:dist  default: the rig's own (League ARAM camera)
##   --el_units=1        keep champions/minions visible (default: hidden, the map alone)
##   --el_shaders=DIR    use DIR/map_lightmap.gdshader and DIR/map_blend.gdshader instead (before/after shots)
##   --el_nocal=1        disable the fitted colour calibration of the map shaders (pure League formula)
##   --el_cviews=1,2,4,5 [look2] champion-shader debug views (VFX hidden): 1 diffuse, 2 ambient cube, 3 L, 4 white, 5 black
##   --el_cset=k=v,...   [look2] champion-shader uniforms for every shot (e.g. lightgrid_scale=2,self_illum_scale=1)
##   --el_novfx=1        [look2] hide every LolVfx in the normal shot too
var main = null
var match_ref = null


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return def


func _ready() -> void:
	_run()


func _map_materials(blend := false) -> Array:
	var out: Array = []
	var shader := load("res://src/vfx/shaders/map_blend.gdshader" if blend else "res://src/vfx/shaders/map_lightmap.gdshader")
	for mi in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.get_surface_override_material_count():
			var mat := m.get_surface_override_material(i)
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader == shader and not out.has(mat):
				out.append(mat)
	return out


func _run() -> void:
	await get_tree().create_timer(float(_arg("el_wait", "2.5")), true, false, true).timeout
	var rig: CameraRig = match_ref.camera_rig
	var vp := get_viewport().get_visible_rect().size
	var k := vp.x / 2000.0
	if _arg("el_units", "0") != "1":
		for u in match_ref.units:
			if is_instance_valid(u) and u.kind != G.Kind.TURRET and u.kind != G.Kind.INHIBITOR and u.kind != G.Kind.NEXUS:
				u.visible = false
	if match_ref.hud != null:
		match_ref.hud.visible = false
	for n in get_tree().root.find_children("*", "CanvasLayer", true, false):
		(n as CanvasLayer).visible = false
	var cam := _arg("el_cam", "")
	if cam != "":
		var c := cam.split(":")
		rig.fov = float(c[0])
		rig.cam.fov = float(c[0])
		rig.pitch_deg = float(c[1])
		rig.distance = float(c[2])
		rig.target_distance = float(c[2])
	rig.target = null
	rig.locked = true
	var pin := _arg("el_pin", "")
	if pin != "":
		var a := pin.split(":")
		var w := a[0].split(",")
		var s := a[1].split(",")
		var pw := G.lol_pos(float(w[0]), 0.0, float(w[1]))
		pw.y = match_ref.nav.height_at(pw) if match_ref.nav != null else 0.0
		var px := Vector2(float(s[0]), float(s[1])) * k
		var fp := pw
		# solve the focus so the pinned point lands on the pixel (ground-plane Newton steps)
		for it in 20:
			rig.snap_to(fp)
			await get_tree().process_frame
			var err: Vector2 = rig.cam.unproject_position(pw) - px
			if err.length() < 0.5:
				break
			var g0 := rig.screen_to_ground(vp * 0.5, null)
			var g1 := rig.screen_to_ground(vp * 0.5 + err * 0.8, null)
			fp += Vector3(g1.x - g0.x, 0.0, g1.z - g0.z)
		print("ELPROBE pin err px ", rig.cam.unproject_position(pw) - px)
	await get_tree().create_timer(0.5, true, false, true).timeout
	_apply_cset()
	if _arg("el_novfx", "0") == "1":
		_hide_vfx()
	var dir := "user://%s" % _arg("el_dir", "envlook")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var mats := _map_materials()
	print("ELPROBE map materials ", mats.size())
	var before := _arg("el_shaders", "")   # a folder with older map_lightmap / map_blend sources: "before" shots
	if before != "":
		for pair in [[mats, "map_lightmap"], [_map_materials(true), "map_blend"]]:
			var sh := Shader.new()
			sh.code = FileAccess.get_file_as_string(before.path_join(pair[1] + ".gdshader"))
			for m in pair[0]:
				(m as ShaderMaterial).shader = sh
		print("ELPROBE map shaders from ", before)
	if _arg("el_nocal", "0") == "1":   # the pure League formula, without the fitted calibration
		for m in mats + _map_materials(true) + _champ_materials():
			(m as ShaderMaterial).set_shader_parameter("calibrate", false)
	for v in _arg("el_views", "0").split(",", false):
		for m in mats:
			(m as ShaderMaterial).set_shader_parameter("debug_view", int(v))
		for f in 3:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/view%s.png" % [dir, v]
		get_viewport().get_texture().get_image().save_png(path)
		print("ELPROBE shot ", ProjectSettings.globalize_path(path))
	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("debug_view", 0)
	# [look2] champion-shader views: d, ambient, L and a unit mask, with every VFX hidden
	var cv := _arg("el_cviews", "")
	if cv != "":
		_hide_vfx()
		var cm := _champ_materials()
		for v in cv.split(",", false):
			for m in cm:
				(m as ShaderMaterial).set_shader_parameter("debug_view", int(v))
			for f in 3:
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var cpath := "%s/cview%s.png" % [dir, v]
			get_viewport().get_texture().get_image().save_png(cpath)
			print("ELPROBE shot ", ProjectSettings.globalize_path(cpath))
		for m in cm:
			(m as ShaderMaterial).set_shader_parameter("debug_view", 0)
	get_tree().quit()


func _champ_materials() -> Array:
	var out: Array = []
	for mi in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.get_surface_override_material_count():
			var mat := m.get_surface_override_material(i)
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader == Assets.CHAMP_SHADER and not out.has(mat):
				out.append(mat)
	return out


func _hide_vfx() -> void:
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is LolVfx:
			(n as Node3D).visible = false
			continue
		stack.append_array(n.get_children())


func _apply_cset() -> void:
	var cs := _arg("el_cset", "")
	if cs == "":
		return
	for m in _champ_materials():
		for kv in cs.split(",", false):
			var p := kv.split("=")
			(m as ShaderMaterial).set_shader_parameter(p[0], float(p[1]))
