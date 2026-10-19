extends "res://src/debug/kit_test_a.gd"
## [vfx-calib] Side-by-side VFX calibration against Riot's ability preview videos (tools/vfx_compare.py drives it).
## Casts one ability of the player champion, HUD hidden, camera centred on the champion at a fixed distance, and
## saves a baseline frame just before the cast plus frames at the given times after it, so the "added light"
## (frame - baseline) can be compared with the same difference taken from the reference video.
##   tools/preview.sh 200 -- --champ=Leona --harness=res://src/debug/vfx_compare.gd --shotdir=vc_leona_W \
##       --cmpslot=W --cmptimes=0.3,1.0,2.0 [--cmpdist=20.2] [--cmpdummy=3.0] [--cmpwait=4]
## Files: user://<shotdir>/base.png, t_<ms>.png

var shot_dir := "user://vcmp"
var times: Array = [0.3, 1.0, 2.0]
var slot := "W"
var dist := CameraRig.MAX_ZOOM
var dummy_dist := 3.0
var focus_target := false   ## --cmpfocus=target: centre the camera on the dummy's cast-time position (ground spells)
var focus_pos = null
var settle := 4.0   ## seconds to idle before the cast (lets the level-up flash and spawn effects fade)


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = "user://" + a.substr(10)
		elif a.begins_with("--cmptimes="):
			times = []
			for t in a.substr(11).split(","):
				times.append(float(t))
		elif a.begins_with("--cmpslot="):
			slot = a.substr(10)
		elif a.begins_with("--cmpdist="):
			dist = float(a.substr(10))
		elif a.begins_with("--cmpdummy="):
			dummy_dist = float(a.substr(11))
		elif a == "--cmpfocus=target":
			focus_target = true
		elif a.begins_with("--cmpwait="):
			settle = float(a.substr(10))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	await _wait(1.0)
	_setup()
	if m.hud != null:
		m.hud.visible = false
	_reset_positions(dummy_dist)
	await _qwait(settle)
	_cam()
	await _frame()
	await _shot("base")
	var s := slot
	if s == "BA":
		c.issue_attack(dummies[0])
	else:
		var si: int = "QWER".find(s)
		var ab: Ability = _ready_ability(si)
		var d: Champion = dummies[0]
		var self_target: bool = ab.target_type == Ability.Target.NONE
		var tgt = c if self_target else (d if ab.target_type == Ability.Target.UNIT else d.global_position)
		var tp: Vector3 = tgt.global_position if tgt is Node3D else tgt
		var t := ab.make_target(tp, tgt if tgt is Unit else null)
		ab.try_cast(t)
	var prev := 0.0
	for t in times:
		var w := maxf(float(t) - prev, 0.0)
		var e := 0.0
		while e < w:
			_quiet()
			_cam()
			await _frame()
			e += get_process_delta_time()
		prev = float(t)
		await _shot("t_%05d" % int(round(float(t) * 1000.0)))
	for fx in m.fx_root.get_children():
		if fx is LolVfx:
			var np: Vector3 = fx.global_position
			var nv := 0
			var ne := 0
			for ch in fx.find_children("*", "GPUParticles3D", true, false):
				nv += 1 if ch.is_visible_in_tree() else 0
				ne += 1 if ch.emitting else 0
				if "--cmpdumpall" in OS.get_cmdline_user_args():
					var mt = ch.draw_pass_1.surface_get_material(0) if ch.draw_pass_1 != null else null
					print("VCMP GPU %s vis=%s emit=%s amount=%d life=%.2f oneshot=%s speed=%.2f started=%s y=%.2f pal=%s prio=%s" % [ch.name,
							ch.is_visible_in_tree(), ch.emitting, ch.amount, ch.lifetime, ch.one_shot, ch.speed_scale, str(ch.get_meta("started", "?")),
							ch.global_position.y, str(mt.get_shader_parameter("palette_v")) if mt != null else "-", str(mt.render_priority) if mt != null else "-"])
			print("VCMP FX %s pos=%s terrain=%.2f gpu_visible=%d emitting=%d culled=%s" % [fx.name, np.snapped(Vector3.ONE * 0.01),
					m.nav.height_at(np), nv, ne, str(fx._culled)])
	print("VCMP DONE ", c.alias)
	get_tree().quit()


func _cam() -> void:
	m.camera_rig.locked = false
	if focus_target and focus_pos == null:
		focus_pos = dummies[0].global_position
	m.camera_rig.focus = focus_pos if focus_target else c.global_position
	m.camera_rig.target_distance = dist
	m.camera_rig.distance = dist


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [shot_dir, n]
	get_viewport().get_texture().get_image().save_png(path)
	print("VCMP SHOT ", ProjectSettings.globalize_path(path))
