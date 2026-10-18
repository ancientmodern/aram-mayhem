extends "res://src/debug/kit_test_b.gd"
## Visual QA (kits-b): casts the player's abilities through the real kit code onto parked dummies and
## screenshots each one at a few moments (so VFX are seen exactly as spawned in game: bones, timing, follow).
## Usage (via tools/preview.sh, never headless):
##   tools/preview.sh 200 -- --champ=MasterYi --harness=res://src/debug/kit_shots_b.gd --kshots=W,Q,E,R,A,C
##     --kdir=yi_shots [--ktimes=0.1,0.4,1.0,2.0] [--kdist=12] [--kgap=2.5]
## Steps: Q W E R = cast that slot at dummy A (unit / point / direction / self as the ability needs),
##        A = basic attack A for ~2 s, C = forced crits on A, Q2/E2/R2 = recast, P<n> = place at n m.
## Screenshots: %APPDATA%/Godot/app_userdata/ARAM- Mayhem/<kdir>/<idx>_<step>_<ms>.png

var steps: Array = ["Q", "W", "E", "R", "A", "C"]
var kdir := "user://kitshots"
var ktimes: Array = [0.1, 0.35, 0.8, 1.6]
var kdist := 12.0
var kgap := 2.5
var place_dist := 5.0
var kpitch := 0.0   ## --kpitch=deg: override camera pitch (side views)
var kself := false   ## --kself: camera centred on the champion (self-buff close-ups)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--kshots="):
			steps = Array(a.substr(9).split(","))
		elif a.begins_with("--kdir="):
			kdir = "user://" + a.substr(7)
		elif a.begins_with("--ktimes="):
			ktimes = []
			for t in a.substr(9).split(","):
				ktimes.append(float(t))
		elif a.begins_with("--kdist="):
			kdist = float(a.substr(8))
		elif a.begins_with("--kpitch="):
			kpitch = float(a.substr(9))
		elif a == "--kself":
			kself = true
		elif a.begins_with("--kgap="):
			kgap = float(a.substr(7))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(kdir))
	get_tree().create_timer(400.0, true, false, true).timeout.connect(func(): get_tree().quit(2))
	_shots()


func _snap(n: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [kdir, n]
	get_viewport().get_texture().get_image().save_png(path)
	print("KSHOT ", ProjectSettings.globalize_path(path))


func _cam() -> void:
	m.camera_rig.locked = false
	m.camera_rig.focus = (c.global_position + Vector3(0, 1.2, 0)) if kself else (c.global_position + foes[0].global_position) * 0.5
	m.camera_rig.target_distance = kdist
	m.camera_rig.distance = kdist
	if kpitch > 0.0:
		m.camera_rig.pitch_deg = kpitch


func _shots() -> void:
	await _wait(1.0)
	if G.match == null or G.player == null:
		get_tree().quit(2)
		return
	_setup()
	for f in foes:
		f.remove_buffs_by_id("kitb_disarm")
		_disarm(f)
	await _wait(0.3)
	var idx := 0
	for st in steps:
		var s: String = String(st)
		if s.begins_with("P"):
			place_dist = float(s.substr(1))
			continue
		_place(place_dist)
		_cam()
		await _wait(0.4)
		var a = foes[0]
		match s:
			"A":
				_attack(a)
			"C":
				var cb := Buff.new("kshot_crit", 4.0)
				cb.hidden = true
				cb.stats = {"crit": 1.0}
				c.add_buff(cb, c)
				_attack(a)
			_:
				var slot := "QWER".find(s.substr(0, 1))
				if slot < 0:
					continue
				var ab := _ab(slot)
				if s.length() > 1:
					# recast: the ability is still in its recast window
					var t2 := ab.make_target(a.global_position, a)
					ab.try_cast(t2)
				else:
					_cast(slot, a.global_position, a)
		var prev := 0.0
		for t in ktimes:
			await _wait(maxf(t - prev, 0.0))
			prev = t
			_cam()
			await _snap("%02d_%s_%04d" % [idx, s, int(t * 1000)])
		_stop_attack()
		c.remove_buffs_by_id("kshot_crit")
		await _wait(kgap)
		idx += 1
	print("KSHOT DONE")
	get_tree().quit()
