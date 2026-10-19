extends Node
## [look2] Debug: override champion-shader uniforms on every character material during a normal match/sim, to judge
## candidate League lit_uber constants side by side (docs/ENV_LOOK.md section 6).
## Usage: tools/preview.sh 200 -- --sim --botplayer --seed=7 --shots=75 --shotdir=X \
##          --harness=res://src/debug/look2_cset.gd --l2_cset=lightgrid_scale=3,self_illum_scale=0.5
##   or freeze the match at --l2_at=SECONDS and shoot the identical frame once per candidate:
##          --l2_sets=2:0.8501;3:0.5 (lightgrid_scale:self_illum_scale) --l2_dir=NAME
var main = null
var match_ref = null
var _kv: Array = []
var _t := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--l2_cset="):
			for kv in a.substr(10).split(",", false):
				var p := kv.split("=")
				_kv.append([p[0], float(p[1])])


var _done := false


func _apply(kv: Array) -> void:
	for mi in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.get_surface_override_material_count():
			var mat := m.get_surface_override_material(i)
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader == Assets.CHAMP_SHADER:
				for p in kv:
					(mat as ShaderMaterial).set_shader_parameter(p[0], p[1])


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % name):
			return a.substr(name.length() + 3)
	return def


func _freeze_and_shoot() -> void:
	_done = true
	Engine.time_scale = 0.0
	var dir := "user://%s" % _arg("l2_dir", "l2_cset")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	for st in _arg("l2_sets", "2:0.8501").split(";", false):
		var ab := st.split(":")
		_apply([["lightgrid_scale", float(ab[0])], ["self_illum_scale", float(ab[1])]])
		for f in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/s_%s_%s.png" % [dir, ab[0], ab[1]]
		get_viewport().get_texture().get_image().save_png(path)
		print("L2CSET shot ", ProjectSettings.globalize_path(path))
	get_tree().quit()


func _process(dt: float) -> void:
	var at := float(_arg("l2_at", "-1"))
	if at > 0.0 and not _done and match_ref != null and match_ref.time >= at:
		_freeze_and_shoot()
		return
	_t -= dt
	if _t > 0.0 or _kv.is_empty():
		return
	_t = 0.5
	for mi in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for i in m.get_surface_override_material_count():
			var mat := m.get_surface_override_material(i)
			if mat is ShaderMaterial and (mat as ShaderMaterial).shader == Assets.CHAMP_SHADER:
				for kv in _kv:
					(mat as ShaderMaterial).set_shader_parameter(kv[0], kv[1])
