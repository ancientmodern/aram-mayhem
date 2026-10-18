extends Node
## [juice] Stages the end of the game: the enemy (or, with --lose, our) nexus is destroyed and the sequence is
## captured on the real-time clock (camera glide, slow-mo, explosion, banner).
## tools/preview.sh 200 -- --champ=Lux --harness=res://src/debug/juice_end.gd --res=1920x1080 [--lose] [--juicedir=NAME]

var main = null
var match_ref = null
var dir := "juice_end"
var lose := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--juicedir="):
			dir = a.substr(11)
		elif a == "--lose":
			lose = true
	_run()


func _run() -> void:
	await JuiceUtil.wait(self, 1.5)
	var m = G.match
	var c = G.player
	# put the player at a plausible spot (mid lane) at default zoom
	var spot := JuiceUtil.park(m, 22.5)
	m.camera_rig.target_distance = 22.5
	await JuiceUtil.wait(self, 0.6)
	var victim = m.nexus_units[c.team if lose else 1 - c.team]
	var t0 := Time.get_ticks_msec()
	print("JUICE nexus dies, match time ", m.time)
	victim.die(c if not lose else m.champions.filter(func(x): return x.team != c.team)[0], null)
	var i := 0
	while Time.get_ticks_msec() - t0 < 9000:
		await JuiceUtil.shot(self, JuiceUtil.out_dir(dir), "end_%02d_t%04d" % [i, Time.get_ticks_msec() - t0])
		i += 1
		await JuiceUtil.wait(self, 0.35)
	print("JUICE DONE")
	get_tree().quit()
