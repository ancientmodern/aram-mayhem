extends "res://src/debug/kit_test_a.gd"
## [timing] Ezreal Q flying into fog of war: screenshots of the missile over fogged ground (verifies that the subtractive
## particle shader no longer leaves a black patch around it).
##   tools/preview.sh 150 -- --champ=Ezreal --harness=res://src/debug/timing_fog_shot.gd --shotdir=timing_fog --res=1920x1080
## Variant A: normal cast, the missile reaches the vision edge at the end of its range.
## Variant B: Ezreal blinks 12 m back right after the shot, so the whole flight is over fogged ground.

var shot_dir := "user://timing_fog"


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = "user://" + a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	await _wait(1.0)
	_setup()
	# nobody else around: no allied vision except Ezreal himself
	for d in dummies:
		d.teleport(d.spawn_point)
	await _wait(0.5)
	await _variant("A", false)
	await _variant("B", true)
	print("FOGSHOT DONE")
	get_tree().quit()


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [shot_dir, n]
	get_viewport().get_texture().get_image().save_png(path)
	print("FOGSHOT ", ProjectSettings.globalize_path(path))


func _variant(tag: String, blink_back: bool) -> void:
	var fwd := G.flat_dir(spot, m.nexus_units[1 if c.team == G.Team.ORDER else 0].global_position)
	c.teleport(spot)
	c.stop_moving()
	c.face_toward(spot + fwd, 1000.0)
	await _qwait(0.3)
	var ab: Ability = _ready_ability(0)
	var aim: Vector3 = spot + fwd * 11.5
	var t := ab.make_target(aim, null)
	ab.try_cast(t)
	var t0: float = m.time
	var shots := [0.36, 0.42, 0.48, 0.54, 0.6]
	var i := 0
	var did_blink := false
	while i < shots.size():
		await _frame()
		var el: float = m.time - t0
		var mid: Vector3 = spot + fwd * 9.0
		m.camera_rig.locked = false
		m.camera_rig.focus = mid
		m.camera_rig.target_distance = 14.0
		m.camera_rig.distance = 14.0
		if blink_back and not did_blink and el > 0.3 and c.casting.is_empty():
			did_blink = true
			c.teleport(m.nav.nearest_walkable(spot - fwd * 12.0))
		if el >= shots[i]:
			await _shot("%s_%03d" % [tag, int(shots[i] * 1000.0)])
			i += 1
	await _qwait(1.0)
