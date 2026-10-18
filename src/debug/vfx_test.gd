class_name VfxTest
extends Node
## QA: spawn League VFX systems next to a champion and screenshot them.
## Usage: godot --path . -- --champ=Ahri --vfxtest[=Name1,Name2,...] [--windowed]

var names: Array = []
var shot_dir := "user://vfxtest"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--vfxtest="):
			names = a.substr(10).split(",")
		elif a.begins_with("--vfxdir="):
			shot_dir = "user://" + a.substr(9)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [shot_dir, n]
	get_viewport().get_texture().get_image().save_png(path)
	print("VFXTEST SHOT ", ProjectSettings.globalize_path(path))


func _run() -> void:
	await _wait(1.0)
	var m = G.match
	var c = G.player
	if c.augments_pending > 0:
		m.get_offer(c)
		m.choose_augment(c, 0)
	LolVfx.load_set(c.alias)
	if names.is_empty():
		var p := "%s_Base_" % c.alias
		names = [p + "BA_mis", p + "BA_tar", p + "Q_mis", p + "Q_tar", p + "W_cas", p + "E_mis", p + "R_cas", p + "Q_cas"]
	# park the champion in an open area and freeze the match so nothing walks into frame
	var spot: Vector3 = m.nav.nearest_walkable((m.outer_turrets[0].global_position + m.outer_turrets[1].global_position) * 0.5)
	c.teleport(spot)
	m.camera_rig.locked = false
	m.camera_rig.focus = spot + Vector3(2.5, 0, 0)
	m.camera_rig.target_distance = 15.0
	await _wait(0.5)
	m.paused = true
	var i := 0
	for n in names:
		if not LolVfx.has(n):
			print("VFXTEST missing ", n)
			continue
		var pos: Vector3 = spot + Vector3(2.5 + (i % 4) * 3.2 - 4.0, 0.9, -2.0 + (i / 4) * 3.5)
		pos.y = m.nav.height_at(pos) + 0.9
		if n.contains("_mis"):
			# moving carrier so trails show
			var carrier := Node3D.new()
			m.fx_root.add_child(carrier)
			carrier.global_position = pos + Vector3(-3, 0, 0)
			var fx := LolVfx.attach(carrier, n, {"loop": true})
			carrier.look_at(carrier.global_position + Vector3.RIGHT, Vector3.UP)
			var tw := carrier.create_tween()
			tw.tween_property(carrier, "global_position", pos + Vector3(3, 0, 0), 0.5)
			tw.tween_callback(func(): fx.detach_and_fade())
		else:
			LolVfx.spawn(m, n, pos, {"dir": Vector3.RIGHT})
		i += 1
	for t in [0.12, 0.35, 0.7, 1.4]:
		await _wait(t if t == 0.12 else t - 0.0)
		await _shot("vfx_%04d" % int(t * 1000))
	print("VFXTEST DONE")
	get_tree().quit()
