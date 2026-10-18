extends Node
## [motion] staged close-up screenshots: idle, run (two frames for foot sliding), attack windup /
## release at base and high attack speed, champion death (stays down), brush transparency, minion
## fights and minion death fade.
## tools/preview.sh 240 -- --champ=Ezreal --harness=res://src/debug/motion_shots.gd [--mshots=dir]

var main
var match_ref
var dir := "user://motion_shots"
var _steps: Array = []        ## [time, Callable]
var _enemy = null
var _p = null
var _rig = null
var _started := false


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mshots="):
			dir = "user://" + a.substr(9)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))


func _cam(target: Node3D, dist: float) -> void:
	if _rig == null:
		return
	_rig.target = target
	_rig.locked = true
	_rig.min_dist = 3.0
	_rig.target_distance = dist
	_rig.distance = dist


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [dir, name]
	img.save_png(path)
	print("[mshot] ", ProjectSettings.globalize_path(path), " t=%.2f" % match_ref.time)


func _at(t: float, f: Callable) -> void:
	_steps.append([t, f])


func _setup() -> void:
	_p = G.player
	_rig = match_ref.camera_rig
	_p.controller = null
	for c in match_ref.champions:
		if c.team != _p.team:
			_enemy = c
			break
	_enemy.controller = null
	_enemy.invulnerable_count += 1
	var fwd := Vector3(1, 0, 0)
	var mid: Vector3 = _clear_spot((_p.spawn_point + _enemy.spawn_point) * 0.5)
	_p.teleport(mid - fwd * 2.0)
	_enemy.teleport(mid + fwd * 2.5)
	_enemy.issue_stop()
	_enemy.face_toward(_p.global_position, 100.0)
	_cam(_p, 7.0)
	var t0: float = match_ref.time
	_at(t0 + 1.0, func(): _shot("01_idle"))
	_at(t0 + 1.2, func(): _p.issue_move(_p.global_position - fwd * 7.0))
	_at(t0 + 2.0, func(): _shot("02_run_a"))
	_at(t0 + 2.1, func(): _shot("03_run_b"))
	_at(t0 + 3.3, func():
		_p.issue_stop()
		_p.teleport(mid - fwd * 2.6)
		_enemy.teleport(mid + fwd * 2.6)
		_p.face_toward(_enemy.global_position, 100.0)
		var mk := Node3D.new()
		match_ref.add_child(mk)
		mk.global_position = mid
		_cam(mk, 7.0))
	_at(t0 + 3.4, func():
		_p.issue_attack(_enemy)
		print("[mshot] windup%%=%.3f period=%.2f" % [_p.windup_pct, _p.stats.attack_period()]))
	for i in 8:
		var k := i
		_at(t0 + 3.5 + k * 0.07, func(): _shot("04_attack_%d" % k))
	_at(t0 + 5.5, func():
		_p.stats.base["attack_speed"] = 2.2
		_p.recompute_stats()
		print("[mshot] AS=%.2f" % _p.stats.attack_speed))
	for i in 6:
		var k2 := i
		_at(t0 + 6.0 + k2 * 0.05, func(): _shot("05_fastattack_%d" % k2))
	_at(t0 + 7.0, func():
		_p.issue_stop()
		_cam(_enemy, 7.0)
		_enemy.invulnerable_count = 0
		_enemy.die(_p))
	_at(t0 + 7.25, func(): _shot("06_death_a"))
	_at(t0 + 8.5, func(): _shot("07_death_b"))
	_at(t0 + 12.0, func(): _shot("08_death_c"))
	_at(t0 + 12.5, func():
		var bp = _find_brush(_p.global_position)
		if bp != null:
			_p.teleport(bp)
			_cam(_p, 9.0))
	_at(t0 + 13.5, func(): _shot("09_brush"))
	_at(t0 + 14.0, func():
		if "--mquick" in OS.get_cmdline_user_args():
			get_tree().quit()
		match_ref.game_speed = 4.0)
	_at(72.0, func():
		match_ref.game_speed = 1.0
		var m = _fight_minion()
		if m != null:
			_cam(m, 9.0))
	_at(73.0, func(): _shot("10_minions_a"))
	_at(76.0, func(): _shot("11_minions_b"))
	_at(79.0, func():
		var m = _fight_minion()
		if m != null:
			_cam(m, 8.0)
			m.die(_p))
	_at(79.4, func(): _shot("12_minion_death_a"))
	_at(80.6, func(): _shot("13_minion_death_b"))
	_at(81.6, func(): _shot("14_minion_death_c"))
	_at(82.5, func(): get_tree().quit())


## Nearest walkable point with no brush within 7 m (units in brush are hidden / see-through).
func _clear_spot(around: Vector3) -> Vector3:
	var nav = match_ref.nav
	for r in range(0, 60, 2):
		for k in 16:
			var q := around + Vector3(cos(k * TAU / 16.0), 0, sin(k * TAU / 16.0)) * r
			var ok: bool = nav.is_walkable(q)
			for j in 12:
				if not ok:
					break
				var e := q + Vector3(cos(j * TAU / 12.0), 0, sin(j * TAU / 12.0)) * 7.0
				var e2 := q + Vector3(cos(j * TAU / 12.0), 0, sin(j * TAU / 12.0)) * 3.5
				if nav.brush_id(e) > 0 or nav.brush_id(e2) > 0 or nav.brush_id(q) > 0 or not nav.is_walkable(e2):
					ok = false
			if ok:
				return q
	return around


func _fight_minion():
	for u in match_ref.units:
		if u is Minion and not u.dead and u.attack_target != null:
			return u
	for u in match_ref.units:
		if u is Minion and not u.dead:
			return u
	return null


func _find_brush(around: Vector3):
	var nav = match_ref.nav
	var best = null
	var bd := INF
	for ix in range(-120, 121, 2):
		for iz in range(-120, 121, 2):
			var q := around + Vector3(ix * 0.5, 0, iz * 0.5)
			if nav.brush_id(q) > 0 and nav.is_walkable(q):
				var d := q.distance_to(around)
				if d < bd:
					bd = d
					best = q
	return best


func _process(_d: float) -> void:
	if match_ref == null or G.player == null:
		return
	if not _started:
		if match_ref.time > 1.0:
			_started = true
			_setup()
		return
	while not _steps.is_empty():
		var nxt: float = INF
		var idx := -1
		for i in _steps.size():
			if _steps[i][0] < nxt:
				nxt = _steps[i][0]
				idx = i
		if match_ref.time < nxt:
			break
		var f: Callable = _steps[idx][1]
		_steps.remove_at(idx)
		f.call()
