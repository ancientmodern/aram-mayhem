extends "res://src/debug/kit_shots_a.gd"
## [motion3] minion look check: a row of order + chaos minions beside the player champion (idle, then running),
## camera at the default gameplay distance. tools/preview.sh 200 -- --champ=Garen --res=2560x1440 --harness=res://src/debug/m3_minions.gd --shotdir=m3_min

var mins: Array = []


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = "user://" + a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	await _wait(1.0)
	_setup()
	await _wait(0.3)
	var fwd := G.flat_dir(spot, m.nexus_units[1].global_position)
	var side := Vector3(-fwd.z, 0, fwd.x)
	var types := [Minion.Type.MELEE, Minion.Type.MELEE, Minion.Type.CASTER, Minion.Type.SIEGE, Minion.Type.SUPER]
	for team in 2:
		for i in types.size():
			var mn := Minion.new()
			mn.setup(team, types[i], 0, [], 325.0)
			mn.acquisition_range = 0.0
			var p: Vector3 = spot + fwd * (2.5 + team * 3.0) + side * (-5.0 + i * 2.2)
			m.add_unit(mn, m.nav.nearest_walkable(p))
			mn.facing = side if team == 0 else -side
			mins.append(mn)
	c.teleport(m.nav.nearest_walkable(spot - fwd * 3.0))
	c.face_toward(spot + fwd, 100.0)
	for t in [0.6, 1.2]:
		await _wait(0.6)
		_cam()
		await _shot("idle_%d" % int(t * 10))
	# run toward the enemy base
	for mn in mins:
		mn.lane = [mn.global_position + fwd * 14.0]
		mn.lane_i = 0
		mn.acquisition_range = 0.0
	for t in [0.5, 1.0, 1.5]:
		await _wait(0.5)
		_cam()
		await _shot("run_%d" % int(t * 10))
	print("KSHOTS DONE minions")
	get_tree().quit()


func _cam() -> void:
	m.camera_rig.locked = false
	m.camera_rig.focus = spot + G.flat_dir(spot, m.nexus_units[1].global_position) * 4.0
	m.camera_rig.target_distance = shot_dist
	m.camera_rig.distance = shot_dist
