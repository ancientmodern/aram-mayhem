extends "res://src/debug/kit_test_a.gd"
## Visual QA for the kits-a champions: casts each ability (and a basic attack / crit) on a parked enemy and
## screenshots the sequence. Run through tools/preview.sh (needs a window):
##   tools/preview.sh 200 -- --champ=Leona --harness=res://src/debug/kit_shots_a.gd --shotdir=kshots_leona
##   [--shotslots=P,Q,W,E,R,BA,CRIT] [--shottimes=0.05,0.25,0.5,0.9,1.5] [--shotdist=11]
## Files: user://<shotdir>/<slot>_<ms>.png

var shot_dir := "user://kshots"
var shot_times: Array = [0.05, 0.25, 0.5, 0.9, 1.5]
var shot_slots: Array = ["BA", "CRIT", "Q", "W", "E", "R"]
var shot_dist := 11.0


func _run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = "user://" + a.substr(10)
		elif a.begins_with("--shottimes="):
			shot_times = []
			for t in a.substr(12).split(","):
				shot_times.append(float(t))
		elif a.begins_with("--shotslots="):
			shot_slots = Array(a.substr(12).split(","))
		elif a.begins_with("--shotdist="):
			shot_dist = float(a.substr(11))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	await _wait(1.0)
	_setup()
	await _wait(0.5)
	for s in shot_slots:
		await _slot(String(s))
	print("KSHOTS DONE ", c.alias)
	get_tree().quit()


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [shot_dir, n]
	get_viewport().get_texture().get_image().save_png(path)
	print("KSHOT ", ProjectSettings.globalize_path(path))


func _cam() -> void:
	var d: Champion = dummies[0]
	m.camera_rig.locked = false
	m.camera_rig.focus = (c.global_position + d.global_position) * 0.5
	m.camera_rig.target_distance = shot_dist
	m.camera_rig.distance = shot_dist


func _shots(prefix: String) -> void:
	var prev := 0.0
	for t in shot_times:
		var w := maxf(float(t) - prev, 0.0)
		var e := 0.0
		while e < w:
			_cam()
			await _frame()
			e += 1.0 / 60.0
		prev = float(t)
		await _shot("%s_%04d" % [prefix, int(float(t) * 1000.0)])


func _slot(s: String) -> void:
	var d: Champion = dummies[0]
	var melee: bool = c.attack_range_m() < 3.0
	_reset_positions(2.0 if melee else 5.0)
	await _qwait(0.6)
	_cam()
	await _frame()
	match s:
		"BA", "CRIT":
			c.stats.mark_dirty()
			var crit_b: Buff = null
			if s == "CRIT":
				crit_b = K.buff(c, "kshot_crit", 5.0, {"crit": 1.0}, c, {"hidden": true})
			c.issue_attack(d)
			await _shots(s)
			c.issue_move(c.global_position)
			if crit_b != null:
				c.remove_buff(crit_b)
		"P":
			await _shots(s)
		_:
			var slot: int = "QWER".find(s)
			if slot < 0:
				return
			var ab: Ability = c.abilities[slot]
			var self_target: bool = ab.target_type == Ability.Target.NONE
			var tgt = c if self_target else (d if ab.target_type == Ability.Target.UNIT else d.global_position)
			_ready_ability(slot)
			var t := ab.make_target(tgt.global_position if tgt is Node3D else tgt, tgt if tgt is Unit else null)
			ab.try_cast(t)
			# empowered-attack abilities (Leona/Garen Q, Darius W): swing at the dummy
			if self_target and (c.alias in ["Leona", "Garen"] and slot == 0 or c.alias == "Darius" and slot == 1):
				c.issue_attack(d)
			await _shots(s)
			c.issue_move(c.global_position)
	# let timed states (Leona W stance + detonation, Ahri recasts...) finish so they never leak into the next slot
	var w := 0.0
	while w < 8.0 and (not _buff_ids(c).is_empty() or not c.channel.is_empty()):
		await _qwait(0.25)
		w += 0.25
	for u in _units():
		for b in u.buffs.duplicate():
			if not b.permanent and not (b.id in PERSIST):
				u.remove_buff(b)
	await _qwait(1.2)
