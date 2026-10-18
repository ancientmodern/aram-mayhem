extends Node
## QA (read-only reviewer) harness #2: world / flow scenarios. Modes via --qamode=:
##   end    : kills the enemy nexus and screenshots the end sequence in real time (explosion, camera, banner, stats).
##   relic  : spawns a health relic, walks the player onto it and captures the pickup + beam (2.5 s later).
##   gates  : screenshots every hexgate prop and the spawn platform / base.
##   lane   : stages minion waves + the enemy outer turret to review aggro, projectiles and turret behaviour.
##   brush  : player stands in brush; enemy outside; feet / transparency / zoom review.
##   zoom   : default / min / max zoom framing at 1440p with all 10 champions lined up for size comparison.
##   walk   : player walks around terrain edges / over the bridge for foot-on-floor review at min zoom.
## Usage: tools/preview.sh 200 -- --champ=Jinx --harness=res://src/debug/qa_flow.gd --qamode=end --shotdir=qa_end --res=2560x1440

var main = null
var match_ref = null
var mode := "end"
var shot_dir := "user://qa_flow"
var m = null
var c = null


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qamode="):
			mode = a.substr(9)
		elif a.begins_with("--shotdir="):
			shot_dir = "user://" + a.substr(10)
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


func _level_all(lv: int) -> void:
	for ch in m.champions:
		while ch.level < lv:
			ch.gain_xp(1000.0)
		ch.auto_level_abilities()


func _run() -> void:
	await _wait(1.5)
	m = G.match
	c = G.player
	match mode:
		"end":
			await _end()
		"relic":
			await _relic()
		"gates":
			await _gates()
		"lane":
			await _lane()
		"brush":
			await _brush()
		"zoom":
			await _zoom()
		"walk":
			await _walk()
	print("QA DONE")
	get_tree().quit()


func _end() -> void:
	_level_all(9)
	m.spawner = null
	var enemy_team: int = 1 - c.team
	var nx = m.nexus_units[enemy_team]
	c.controller = null
	c.teleport(m.nav.nearest_walkable(nx.global_position + (m.nexus_units[c.team].global_position - nx.global_position).normalized() * 14.0))
	m.camera_rig.locked = true
	await _wait(1.0)
	await _shot("end_before")
	# kill the nexus
	print("QA END kill nexus")
	nx.die(c, null)
	for i in 30:
		await _shot("end_%02d" % i)
		await _wait(0.3)
	# try to press continue
	await _wait(2.0)
	await _shot("end_after_banner")
	var es = m.end_screen
	print("QA END end_screen=", es, " phase=", es._phase if es != null else -1)


func _relic() -> void:
	m.spawner = null
	for r in m.relics:
		r.respawn_at = 0.0
	await _wait(0.5)
	var r = m.relics[0]
	print("QA RELIC positions: ", m.relics.map(func(x): return x.global_position))
	var tr: Vector3 = m.nav.nearest_walkable(r.global_position + Vector3(4, 0, 0))
	c.controller = null
	c.hp = c.stats.max_hp * 0.4
	c.mana = c.stats.max_mana * 0.3
	c.teleport(tr)
	m.camera_rig.locked = true
	await _wait(0.8)
	await _burst("relic_idle", 3, 0.2)
	c.issue_move(r.global_position)
	await _burst("relic_walk", 6, 0.15)
	await _burst("relic_pickup", 12, 0.12)
	await _burst("relic_beam", 14, 0.25)
	print("QA RELIC hp=", c.hp, "/", c.stats.max_hp)


func _gates() -> void:
	m.spawner = null
	m.camera_rig.locked = false
	var i := 0
	for g in m.hexgates:
		m.camera_rig.focus = g.pos
		m.camera_rig.target_distance = 18.0
		await _wait(0.6)
		print("QA GATE %d pos=%s exit=%s team=%d" % [i, g.pos, g.exit, g.team])
		await _shot("gate_%d" % i)
		i += 1
	# spawn platform + shop
	m.camera_rig.focus = m.spawn_points[c.team]
	m.camera_rig.target_distance = 22.5
	await _wait(0.8)
	await _shot("spawn_platform")
	m.camera_rig.focus = m.nexus_units[c.team].global_position
	await _wait(0.8)
	await _shot("nexus_ally")
	m.camera_rig.focus = m.nexus_units[1 - c.team].global_position
	await _wait(0.8)
	await _shot("nexus_enemy")
	m.camera_rig.focus = m.inhibitor_units[1 - c.team].global_position
	await _wait(0.8)
	await _shot("inhib_enemy")


func _lane() -> void:
	_level_all(6)
	for ch in m.champions:
		if ch != c:
			ch.teleport(ch.spawn_point)
			ch.controller = null
	c.controller = null
	var tur = m.outer_turrets[1 - c.team]
	var fwd: Vector3 = G.flat_dir(m.nexus_units[c.team].global_position, m.nexus_units[1 - c.team].global_position)
	var spot: Vector3 = m.nav.nearest_walkable(tur.global_position - fwd * 22.0)
	c.teleport(spot)
	m.camera_rig.locked = true
	m.camera_rig.target_distance = 22.5
	# let waves run
	if m.spawner != null:
		m.time = maxf(m.time, 41.0)
	await _wait(1.0)
	await _burst("lane_a", 10, 0.5)
	# walk into turret range with the minions
	c.issue_move(m.nav.nearest_walkable(tur.global_position - fwd * 12.0))
	await _burst("lane_b", 20, 0.35)
	await _burst("lane_c", 12, 0.6)


func _brush() -> void:
	m.spawner = null
	# find brush cell
	var found := Vector3.ZERO
	var p0 := _mid()
	for dx in range(-30, 31, 2):
		for dz in range(-30, 31, 2):
			var p := p0 + Vector3(dx, 0, dz)
			if m.nav.is_walkable(p) and m.nav.brush_id(p) > 0:
				found = p
				break
		if found != Vector3.ZERO:
			break
	print("QA BRUSH found=", found)
	if found == Vector3.ZERO:
		return
	c.controller = null
	c.teleport(found)
	m.camera_rig.locked = true
	m.camera_rig.target_distance = 15.0
	await _wait(1.0)
	await _burst("brush_in", 4, 0.3)
	c.issue_move(found + Vector3(5, 0, 0))
	await _burst("brush_out", 8, 0.2)
	m.camera_rig.target_distance = 22.5
	await _shot("brush_wide")


func _zoom() -> void:
	m.spawner = null
	for u in m.units.duplicate():
		if u.kind == G.Kind.MINION:
			m.remove_unit(u)
	var spot := _mid()
	var side := Vector3(0, 0, 1)
	c.controller = null
	var i := 0
	for ch in m.champions:
		ch.controller = null
		ch.is_bot = false
		ch.teleport(m.nav.nearest_walkable(spot + side * (i - 5) * 2.2))
		ch.issue_move(ch.global_position)
		i += 1
	m.camera_rig.locked = false
	m.camera_rig.focus = spot
	for d in [22.5, 18.0, 15.0]:
		m.camera_rig.target_distance = d
		await _wait(1.2)
		await _shot("zoom_%d" % int(d))
	# idle for a few seconds then burst (idle anim variants, shadows)
	await _burst("zoom_idle", 5, 0.8)


func _walk() -> void:
	m.spawner = null
	for u in m.units.duplicate():
		if u.kind == G.Kind.MINION:
			m.remove_unit(u)
	c.controller = null
	var spot := _mid()
	c.teleport(spot)
	m.camera_rig.locked = true
	m.camera_rig.target_distance = 15.0
	await _wait(0.8)
	var fwd := G.flat_dir(m.nexus_units[0].global_position, m.nexus_units[1].global_position)
	var side := Vector3(-fwd.z, 0, fwd.x)
	var pts := [spot + side * 9.0, spot + side * 9.0 + fwd * 8.0, spot - side * 9.0 + fwd * 8.0, spot - side * 9.0 - fwd * 8.0, spot]
	var k := 0
	for p in pts:
		c.issue_move(m.nav.nearest_walkable(p))
		await _burst("walk_%d" % k, 5, 0.5)
		k += 1
