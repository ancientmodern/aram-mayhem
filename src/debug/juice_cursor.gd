extends Node
## [juice] Stages League's click markers: move (green), attack (red) and rapid clicks, with the animation clock
## driven by hand so each frame is an exact marker age.
## tools/preview.sh 120 -- --champ=Ezreal --harness=res://src/debug/juice_cursor.gd [--juicedir=NAME]

var main = null
var match_ref = null
var dir := "juice_cursor"
var m = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--juicedir="):
			dir = a.substr(11)
	_run()


func _marker_frames(prefix: String, pos: Vector3, attack: bool, ages: Array) -> void:
	CursorMarker.spawn(m, pos, attack)
	var hub: CursorMarker = m.get_meta("juice_cursor")
	hub.set_process(false)
	var slot = hub._slots[(hub._next + CursorMarker.POOL - 1) % CursorMarker.POOL]
	for a in ages:
		slot.age = a
		hub._set_age(slot, a)
		await JuiceUtil.wait(self, 0.12)
		await JuiceUtil.shot(self, JuiceUtil.out_dir(dir), "%s_%03d" % [prefix, int(a * 1000)])
	slot.age = -1.0
	slot.root.visible = false


func _run() -> void:
	await JuiceUtil.wait(self, 1.0)
	m = G.match
	var spot := JuiceUtil.park(m, 7.0)
	m.camera_rig.focus = spot
	m.paused = true
	await JuiceUtil.wait(self, 0.5)
	var ages := [0.0, 0.05, 0.1, 0.16, 0.22, 0.3, 0.37]
	await _marker_frames("move", spot + Vector3(2.0, 0, 0.5), false, ages)
	await _marker_frames("attack", spot + Vector3(2.0, 0, 0.5), true, ages)
	# rapid clicks: 4 markers 0.1 s apart, live clock
	var hub: CursorMarker = m.get_meta("juice_cursor")
	hub.set_process(true)
	for i in 4:
		CursorMarker.spawn(m, spot + Vector3(0.5 + i * 0.9, 0, 0.5 - i * 0.4), false)
		await JuiceUtil.wait(self, 0.1)
	await JuiceUtil.shot(self, JuiceUtil.out_dir(dir), "rapid_a")
	await JuiceUtil.wait(self, 0.1)
	await JuiceUtil.shot(self, JuiceUtil.out_dir(dir), "rapid_b")
	print("JUICE DONE")
	get_tree().quit()
