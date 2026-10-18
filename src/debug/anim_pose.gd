extends "res://src/debug/kit_shots_b.gd"
## [kitvfx-b] Pose viewer: plays one logical/raw animation on the player's champion at several facings and
## screenshots (no particles). tools/preview.sh 120 -- --champ=MasterYi --harness=res://src/debug/anim_pose.gd
##   --pose=spell2 --kdir=yi_pose [--kpitch=15] [--kdist=5] [--ktimes=0.5,1.5]


func _shots() -> void:
	await _wait(1.0)
	_setup()
	var pose := "spell2"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--pose="):
			pose = a.substr(7)
	_place(5.0)
	c.controller = null
	var idx := 0
	for yaw in [0.0, 90.0, 180.0, 270.0]:
		var dir := Vector3(sin(deg_to_rad(yaw)), 0, cos(deg_to_rad(yaw)))
		c.face_toward(c.global_position + dir, 100.0)
		c.facing = dir
		c.play_anim(pose, 1.0, 0.05)
		c.anim_lock = 10.0
		kself = true
		for t in ktimes:
			await _wait(0.5)
			_cam()
			await _snap("%02d_%s_yaw%03d_%d" % [idx, pose, int(yaw), int(t * 1000)])
			break
		idx += 1
	print("KSHOT DONE")
	get_tree().quit()
