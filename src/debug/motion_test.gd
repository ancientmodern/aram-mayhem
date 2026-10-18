extends Node
## [motion] diagnostics harness: --harness=res://src/debug/motion_test.gd
## Logs animation-graph state, run calibration, attack timing and sockets.

var main
var match_ref
var _t := 0.0
var _next := 1.0
var _done_static := false


var _foot_samples: Array = []
var _proc_acc := 0.0
var _proc_n := 0


## Foot-sliding metric: world speed of the planted foot while the player runs (0 = perfect).
func _sample_foot(delta: float) -> void:
	var p = G.player
	if p == null or not p.moving or p.cur_anim != "run":
		return
	var f: Node3D = p.socket("L_Buffbone_Glb_Foot_Loc")
	_foot_samples.append([f.global_position, delta, p.global_position])
	if _foot_samples.size() >= 240:
		var ys: Array = _foot_samples.map(func(x): return x[0].y - x[2].y)
		var ymin: float = ys.min()
		var ymax: float = ys.max()
		var sp: Array = []
		for i in range(1, _foot_samples.size()):
			if ys[i] < ymin + (ymax - ymin) * 0.12 and ys[i - 1] < ymin + (ymax - ymin) * 0.12:
				var a: Vector3 = _foot_samples[i - 1][0]
				var b: Vector3 = _foot_samples[i][0]
				sp.append(Vector2(b.x - a.x, b.z - a.z).length() / maxf(_foot_samples[i][1], 0.001))
		sp.sort()
		print("[motion] planted-foot world speed median=%.3f m/s (unit speed %.2f m/s, n=%d)" % [
			sp[sp.size() / 2] if not sp.is_empty() else -1.0, p.stats.move_speed * G.U, sp.size()])
		_foot_samples.clear()


func _process(delta: float) -> void:
	if match_ref == null:
		return
	_sample_foot(delta)
	_t += delta
	if not _done_static and _t > 0.5:
		_done_static = true
		for c in match_ref.champions:
			print("[motion] %s graph=%s strides=%s windup%%=%.3f mod=%.2f bone=%s path_r=%.2f" % [c.alias,
				c.graph != null, c._strides, c.windup_pct, c.windup_mod, c.attack_bone, c.path_radius])
			var s: Node3D = c.socket("BUFFBONE_GLB_WEAPON_1")
			var o: Vector3 = c.missile_origin()
			print("   socket=%s (%s) origin_h=%.2f" % [s.name, s.get_class(), o.y - c.global_position.y])
	_proc_acc += Performance.get_monitor(Performance.TIME_PROCESS)
	_proc_n += 1
	if _t < _next:
		return
	_next += 1.0
	if int(_t) % 10 == 0:
		print("[motion] process avg %.2f ms units=%d" % [_proc_acc / maxf(_proc_n, 1) * 1000.0, match_ref.units.size()])
		_proc_acc = 0.0
		_proc_n = 0
	var p = G.player
	if p != null:
		print("[motion] t=%.1f %s anim=%s top=%s atomic=%s spd=%.2f ms=%.0f moving=%s lock=%.2f cur=%s" % [_t, p.alias,
			p.cur_anim, p._g_top, p._g_atomic, p.anim_player.speed_scale if p.anim_player else 0.0,
			p.stats.move_speed, p.moving, p.anim_lock, p.anim_player.current_animation if p.anim_player else ""])
	for u in match_ref.units:
		if u is Minion and not u.dead:
			print("   minion %s anim=%s top=%s spd=%.2f strides=%s" % [u.display_name, u.cur_anim, u._g_top,
				u.anim_player.speed_scale if u.anim_player else 0.0, u._strides])
			break
