extends Node
## [juice] Stages the player's death + respawn: death animation, grey fade, kill coin burst on the killer, then the
## fountain respawn pillar and the colour coming back. Frames at default League zoom and close up.
## tools/preview.sh 200 -- --champ=Lux --harness=res://src/debug/juice_death.gd --res=1920x1080 [--juicedir=NAME] [--audiolog]

var main = null
var match_ref = null
var dir := "juice_death"
var m = null
var c = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--juicedir="):
			dir = a.substr(11)
	_run()


func _burst(prefix: String, n: int, dt: float) -> void:
	for i in n:
		await JuiceUtil.shot(self, JuiceUtil.out_dir(dir), "%s_%02d" % [prefix, i])
		await JuiceUtil.wait(self, dt)


func _run() -> void:
	await JuiceUtil.wait(self, 1.5)
	m = G.match
	c = G.player
	var spot := JuiceUtil.park(m, 22.5)
	m.camera_rig.min_dist = 4.0
	m.camera_rig.target_distance = 12.0
	var killer = null
	for ch in m.champions:
		if ch.team != c.team:
			killer = ch
			break
	killer.teleport(m.nav.nearest_walkable(spot + Vector3(2.5, 0, 0.5)))
	for ch in m.champions:
		if ch != c and ch != killer:
			ch.teleport(m.nav.nearest_walkable(spot + Vector3(40, 0, 40)))
	await JuiceUtil.wait(self, 0.8)
	print("JUICE kill at match time ", m.time)
	c.die(killer, null)
	await _burst("death", 14, 0.1)
	await JuiceUtil.wait(self, 1.5)
	await JuiceUtil.shot(self, JuiceUtil.out_dir(dir), "death_hold")
	# respawn
	print("JUICE respawn forced at ", m.time)
	c.respawn_timer = 0.05
	await JuiceUtil.wait(self, 0.15)
	m.camera_rig.target_distance = 16.0
	await _burst("respawn", 16, 0.12)
	print("JUICE DONE")
	get_tree().quit()
