extends Node
## QA (read-only reviewer) harness. Modes via --qamode=:
##   fight  : teleports all 10 champions to the bridge centre at level 11 and lets the bots brawl; burst shots.
##   kit    : player casts Q, W, E, R on two parked enemies; consecutive frames per cast (0.08 s apart).
##   move   : player walks / turns around; consecutive frames for animation + turning review.
##   death  : kills the player and screenshots the death / grey screen / respawn flow.
## Usage: tools/preview.sh 200 -- --champ=Lux --harness=res://src/debug/qa_fight.gd --qamode=kit --res=2560x1440

var main = null
var match_ref = null
var mode := "fight"
var shot_dir := "user://qa"
var m = null
var c = null
var dist := 22.5


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qamode="):
			mode = a.substr(9)
		elif a.begins_with("--shotdir="):
			shot_dir = "user://" + a.substr(10)
		elif a.begins_with("--qadist="):
			dist = float(a.substr(9))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [shot_dir, n]
	get_viewport().get_texture().get_image().save_png(path)
	print("QA SHOT ", ProjectSettings.globalize_path(path))


func _burst(prefix: String, n: int, dt: float) -> void:
	for i in n:
		await _shot("%s_%02d" % [prefix, i])
		await _wait(dt)


func _mid() -> Vector3:
	return m.nav.nearest_walkable((m.outer_turrets[0].global_position + m.outer_turrets[1].global_position) * 0.5)


func _run() -> void:
	await _wait(1.5)
	m = G.match
	c = G.player
	match mode:
		"fight":
			await _fight()
		"kit":
			await _kit()
		"move":
			await _move()
		"death":
			await _death()
	print("QA DONE")
	get_tree().quit()


func _level_all(lv: int) -> void:
	for ch in m.champions:
		while ch.level < lv:
			ch.gain_xp(1000.0)
		ch.auto_level_abilities()


func _fight() -> void:
	_level_all(11)
	var spot := _mid()
	var fwd := G.flat_dir(m.nexus_units[0].global_position, m.nexus_units[1].global_position)
	for ch in m.champions:
		var off: Vector3 = (-fwd if ch.team == 0 else fwd) * 6.0 + Vector3(randf_range(-3, 3), 0, randf_range(-3, 3))
		ch.teleport(m.nav.nearest_walkable(spot + off))
		if ch.controller == null or not (ch.controller is BotBrain):
			var b := BotBrain.new()
			b.setup(ch, m)
			ch.controller = b
			ch.is_bot = true
	m.camera_rig.locked = false
	m.camera_rig.focus = spot
	m.camera_rig.target_distance = dist
	await _wait(0.4)
	await _burst("fight", 40, 0.15)
	await _wait(2.0)
	await _burst("fight_late", 10, 0.3)


func _kit() -> void:
	_level_all(13)
	m.spawner = null
	for u in m.units.duplicate():
		if u.kind == G.Kind.MINION:
			m.remove_unit(u)
	var spot := _mid()
	var fwd := G.flat_dir(m.nexus_units[c.team].global_position, m.nexus_units[1 - c.team].global_position)
	var side := Vector3(-fwd.z, 0, fwd.x)
	var dummies := []
	for ch in m.champions:
		if ch == c:
			continue
		ch.controller = null
		ch.is_bot = false
		if ch.team != c.team and dummies.size() < 2:
			dummies.append(ch)
		else:
			ch.teleport(ch.spawn_point)
			ch.issue_move(ch.spawn_point)
	c.controller = null
	c.teleport(spot)
	c.issue_move(spot)
	for i in dummies.size():
		dummies[i].teleport(m.nav.nearest_walkable(spot + fwd * (6.0 + i * 1.5) + side * (i * 1.2)))
		dummies[i].issue_move(dummies[i].global_position)
	m.camera_rig.locked = false
	m.camera_rig.focus = spot + fwd * 3.0
	m.camera_rig.target_distance = dist
	await _wait(0.8)
	await _shot("kit_idle")
	# auto attacks
	c.issue_attack(dummies[0])
	await _burst("kit_aa", 14, 0.06)
	c.issue_move(spot)
	await _wait(0.6)
	for slot in [0, 1, 2, 3]:
		var ab = c.abilities[slot]
		ab.cd = 0.0
		if ab.max_charges > 0:
			ab.charges = ab.max_charges
		c.mana = c.stats.max_mana
		for d in dummies:
			d.hp = d.stats.max_hp
		var tgt = dummies[0]
		var t = ab.make_target(tgt.global_position, tgt)
		var ok = ab.try_cast(t)
		print("QA CAST slot=%d ok=%s" % [slot, ok])
		await _burst("kit_%s" % "QWER"[slot], 16, 0.08)
		await _wait(1.5)
		c.teleport(spot)
		c.issue_move(spot)
		for i in dummies.size():
			if dummies[i].dead:
				dummies[i].respawn()
			dummies[i].teleport(m.nav.nearest_walkable(spot + fwd * (6.0 + i * 1.5) + side * (i * 1.2)))
			dummies[i].issue_move(dummies[i].global_position)
		await _wait(0.6)


func _move() -> void:
	m.camera_rig.locked = true
	var spot := _mid()
	c.controller = null
	c.teleport(spot)
	c.issue_move(spot)
	await _wait(0.8)
	var fwd := G.flat_dir(m.nexus_units[0].global_position, m.nexus_units[1].global_position)
	var side := Vector3(-fwd.z, 0, fwd.x)
	c.issue_move(m.nav.nearest_walkable(spot + fwd * 8.0))
	await _burst("move_start", 12, 0.05)
	await _wait(0.4)
	# 180 turn while running
	c.issue_move(m.nav.nearest_walkable(spot - fwd * 4.0))
	await _burst("move_turn", 12, 0.04)
	await _wait(0.3)
	c.issue_move(m.nav.nearest_walkable(c.global_position + side * 5.0))
	await _burst("move_side", 10, 0.05)
	await _wait(1.5)
	await _burst("move_stop", 6, 0.05)
	m.camera_rig.target_distance = 15.0
	await _wait(0.8)
	await _shot("move_zoomin")
	c.issue_move(m.nav.nearest_walkable(c.global_position + fwd * 6.0))
	await _burst("move_zoomin_run", 8, 0.05)


func _death() -> void:
	var spot := _mid()
	c.controller = null
	c.teleport(spot)
	await _wait(0.6)
	var killer = null
	for ch in m.champions:
		if ch.team != c.team:
			killer = ch
			break
	killer.teleport(m.nav.nearest_walkable(spot + Vector3(3, 0, 0)))
	c.die(killer, null)
	await _burst("death", 10, 0.12)
	await _wait(2.0)
	await _shot("death_grey")
	await _wait(4.0)
	await _shot("death_later")
	while c.dead:
		await _wait(0.5)
	await _burst("respawn", 6, 0.2)
