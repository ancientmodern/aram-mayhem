extends Node
## [juice] Stages combat feel: forced critical auto attacks (hit sound events, crit number, hit VFX) and a level-up
## (LevelUp_glb + "Level Up!" text + sound).
## tools/preview.sh 120 -- --champ=Ezreal --harness=res://src/debug/juice_combat.gd --res=1920x1080 --audiolog

var main = null
var match_ref = null
var dir := "juice_combat"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--juicedir="):
			dir = a.substr(11)
	_run()


func _run() -> void:
	await JuiceUtil.wait(self, 1.5)
	var m = G.match
	var c = G.player
	var spot := JuiceUtil.park(m, 11.0)
	var foe = m.champions.filter(func(x): return x.team != c.team)[0]
	for ch in m.champions:
		if ch != c and ch != foe:
			ch.teleport(m.nav.nearest_walkable(spot + Vector3(40, 0, 40)))
	foe.teleport(m.nav.nearest_walkable(spot + Vector3(2.2, 0, 0.4)))
	foe.stats.max_hp = 99999.0
	foe.hp = 99999.0
	c.stats.crit_chance = 1.0
	await JuiceUtil.wait(self, 0.6)
	c.issue_attack(foe)
	for i in 14:
		await JuiceUtil.shot(self, JuiceUtil.out_dir(dir), "crit_%02d" % i)
		await JuiceUtil.wait(self, 0.1)
	c.issue_stop()
	print("JUICE level up")
	c.gain_xp(Rules.xp_to_next(c.level) + 1.0)
	for i in 10:
		await JuiceUtil.shot(self, JuiceUtil.out_dir(dir), "lvl_%02d" % i)
		await JuiceUtil.wait(self, 0.12)
	print("JUICE DONE")
	get_tree().quit()
