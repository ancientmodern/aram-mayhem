extends Node
## [motion] animation-graph transition log: run->stop, attack->idle, attack->run, spell->idle,
## spell->run. Prints every change of the played League clip (top / atomic / glb anim).
## tools/check.sh 1500 --fixed-fps 60 -- --champ=Ahri --harness=res://src/debug/motion_trans.gd

var main
var match_ref
var _p = null
var _enemy = null
var _steps: Array = []
var _started := false
var _last := ""


func _at(t: float, f: Callable) -> void:
	_steps.append([t, f])


func _cast(slot: int, target) -> void:
	var ab: Ability = _p.abilities[slot]
	if ab.level <= 0:
		ab.level = 1
	ab.cd = 0.0
	_p.mana = _p.stats.max_mana
	var t: Dictionary = ab.make_target(target.global_position, target)
	print("[trans] cast slot %d ok=%s" % [slot, ab.try_cast(t)])


func _setup() -> void:
	_p = G.player
	_p.controller = null
	for c in match_ref.champions:
		if c.team != _p.team:
			_enemy = c
			break
	_enemy.controller = null
	_enemy.invulnerable_count += 1
	var mid: Vector3 = (_p.spawn_point + _enemy.spawn_point) * 0.5
	mid = match_ref.nav.nearest_walkable(mid)
	var fwd := Vector3(1, 0, 0)
	_p.teleport(mid - fwd * 2.5)
	_enemy.teleport(mid + fwd * 2.5)
	_enemy.issue_stop()
	var t0: float = match_ref.time
	_at(t0 + 0.5, func(): print("[trans] -- run then stop"); _p.issue_move(_p.global_position - fwd * 6.0))
	_at(t0 + 1.8, func(): _p.issue_stop())
	_at(t0 + 3.0, func(): print("[trans] -- attack then stop"); _p.issue_attack(_enemy))
	_at(t0 + 4.4, func(): _p.issue_stop())
	_at(t0 + 6.0, func(): print("[trans] -- attack then move"); _p.issue_attack(_enemy))
	_at(t0 + 7.3, func(): _p.issue_move(_p.global_position - fwd * 5.0))
	_at(t0 + 9.0, func(): print("[trans] -- Q then idle"); _p.issue_stop(); _p.face_toward(_enemy.global_position, 100.0); _cast(0, _enemy))
	_at(t0 + 11.0, func(): print("[trans] -- Q then move"); _cast(0, _enemy))
	_at(t0 + 11.35, func(): _p.issue_move(_p.global_position - fwd * 5.0))
	_at(t0 + 13.0, func(): print("[trans] -- W then idle"); _p.issue_stop(); _cast(1, _enemy))
	_at(t0 + 15.0, func(): get_tree().quit())


func _process(_d: float) -> void:
	if match_ref == null or G.player == null:
		return
	if not _started:
		if match_ref.time > 1.0:
			_started = true
			_setup()
		return
	var cur := "%s|%s|%s|%s" % [_p.cur_anim, _p._g_top, _p._g_atomic, _p.anim_player.current_animation]
	if cur != _last:
		_last = cur
		print("[trans] t=%.2f logical=%s top=%s atomic=%s anim=%s spd=%.2f moving=%s" % [match_ref.time, _p.cur_anim,
			_p._g_top, _p._g_atomic, _p.anim_player.current_animation, _p.anim_player.speed_scale, _p.moving])
	while not _steps.is_empty() and match_ref.time >= _steps[0][0]:
		var f: Callable = _steps.pop_front()[1]
		f.call()
