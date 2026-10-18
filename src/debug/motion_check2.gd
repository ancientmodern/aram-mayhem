extends Node
## [motion] fog of war + high attack speed screenshot checks.
## tools/preview.sh 200 -- --champ=MasterYi --harness=res://src/debug/motion_check2.gd [--mshots=dir] [--mas=2.0]
##  a) enemy in the open (visible) -> enemy steps into brush away from the player's vision (fades out,
##     bar hidden) -> player walks into the same brush (enemy revealed, fades in)
##  b) player attacks a passive, invulnerable dummy at --mas attack speed: frame sequence of one cycle

var main
var match_ref
var dir := "user://motion_check2"
var _steps: Array = []
var _p = null
var _enemy = null
var _rig = null
var _started := false
var _as := 2.0
var _t_log_end := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mshots="):
			dir = "user://" + a.substr(9)
		elif a.begins_with("--mas="):
			_as = float(a.substr(6))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))


func _cam(target: Node3D, dist: float) -> void:
	_rig.target = target
	_rig.locked = true
	_rig.min_dist = 3.0
	_rig.target_distance = dist
	_rig.distance = dist


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])
	print("[mc2] %s t=%.3f enemy_vis=%s alpha=%.2f visible=%s on_screen=%s p_anim=%s/%s spd=%.2f windup=%.3f" % [name,
		match_ref.time, _enemy.visible_to[_p.team], _enemy._alpha, _enemy.visible, _enemy._on_screen,
		_p._g_top, _p._g_atomic, _p.anim_player.speed_scale, _p.windup_timer])


func _at(t: float, f: Callable) -> void:
	_steps.append([t, f])


func _brush_spot(around: Vector3) -> Vector3:
	var nav = match_ref.nav
	var best := Vector3.INF
	var bd := INF
	for ix in range(-80, 81, 2):
		for iz in range(-80, 81, 2):
			var q := around + Vector3(ix * 0.5, 0, iz * 0.5)
			if nav.brush_id(q) > 0 and nav.is_walkable(q):
				# deep inside: brush all around
				var deep := true
				for k in 8:
					if nav.brush_id(q + Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0)) * 1.2) != nav.brush_id(q):
						deep = false
						break
				if deep and q.distance_to(around) < bd:
					bd = q.distance_to(around)
					best = q
	return best


func _setup() -> void:
	_p = G.player
	_rig = match_ref.camera_rig
	for c in match_ref.champions:
		c.controller = null
		c.issue_stop()
	for c in match_ref.champions:
		if c.team != _p.team:
			_enemy = c
			break
	_enemy.invulnerable_count += 1
	_enemy.acquisition_range = 0.0   # passive dummy: never fights back
	# park everyone else far away so only the player gives vision near the brush
	var i := 0
	for c in match_ref.champions:
		if c != _p and c != _enemy:
			c.teleport(c.spawn_point + Vector3(0, 0, 2.0 * (i % 5)))
			i += 1
	var b := _brush_spot(match_ref.nav.nearest_walkable((_p.spawn_point + _enemy.spawn_point) * 0.5))
	var nav = match_ref.nav
	# an open spot ~5.5 m from the brush, with no brush between
	var open := b
	for r in [5.5, 6.5, 7.5]:
		for k in 16:
			var q: Vector3 = b + Vector3(cos(k * TAU / 16.0), 0, sin(k * TAU / 16.0)) * r
			if nav.is_walkable(q) and nav.brush_id(q) == 0:
				open = q
				break
		if open != b:
			break
	print("[mc2] brush=%s open=%s" % [b, open])
	var mk := Node3D.new()
	match_ref.add_child(mk)
	mk.global_position = (b + open) * 0.5
	_p.teleport(open)
	_enemy.teleport(open + (b - open).normalized() * 2.0)
	_cam(mk, 9.0)
	var t0: float = match_ref.time
	_t_log_end = t0 + 2.0
	_at(t0 + 0.6, func(): _shot("f1_enemy_open"))
	_at(t0 + 0.8, func(): _enemy.teleport(b))
	_at(t0 + 0.83, func(): _shot("f2_enemy_brush_fading"))
	_at(t0 + 1.4, func(): _shot("f3_enemy_brush_hidden"))
	_at(t0 + 1.6, func(): _p.teleport(b + (open - b).normalized() * 0.8))
	_at(t0 + 1.8, func(): _shot("f4_player_in_brush_revealed"))
	_at(t0 + 2.2, func(): _p.teleport(open); _enemy.teleport(b))
	_at(t0 + 2.7, func(): _shot("f5_hidden_again"))
	# --- high attack speed against a passive dummy
	_at(t0 + 3.0, func():
		_enemy.teleport(open + Vector3(2.4, 0, 0))
		_p.teleport(open - Vector3(0.6, 0, 0))
		_p.stats.base["attack_speed"] = _as
		_p.stats.base["attack_speed_ratio"] = 0.0
		_p.recompute_stats()
		_cam(_p, 6.0)
		print("[mc2] AS=%.2f period=%.3f windup%%=%.3f" % [_p.stats.attack_speed, _p.stats.attack_period(), _p.windup_pct])
		_p.issue_attack(_enemy))
	for k in 14:
		var kk := k
		_at(t0 + 5.0 + kk * 0.04, func(): _shot("a%02d" % kk))
	# --- haste run (MoveSpeed >= League run_haste threshold)
	_at(t0 + 6.0, func():
		_p.issue_stop()
		_p.stats.base["base_ms"] = 460.0
		_p.recompute_stats()
		_p.teleport(open + Vector3(4, 0, 0))
		_p.issue_move(_p.global_position - Vector3(14, 0, 0))
		_cam(_p, 7.0)
		print("[mc2] haste ms=%.0f" % _p.stats.move_speed))
	for k in 8:
		var kk := k
		_at(t0 + 7.2 + kk * 0.06, func(): _shot("h%02d" % kk))
	_at(t0 + 8.0, func(): get_tree().quit())


var _feet: Array = []


## Planted-foot world speed while hasted (0 = no sliding; run_haste stride is capped, so it slides a bit).
func _sample_feet(delta: float) -> void:
	if _p == null or not _p.moving or _p.stats.move_speed < 420.0 or _p.cur_anim != "run":
		return
	var f: Node3D = _p.socket("L_Buffbone_Glb_Foot_Loc")
	_feet.append([f.global_position, delta, _p.global_position, _p.anim_player.current_animation])
	if _feet.size() == 50:
		var ys: Array = _feet.map(func(x): return x[0].y - x[2].y)
		var ymin: float = ys.min()
		var ymax: float = ys.max()
		var sp: Array = []
		for i in range(1, _feet.size()):
			if ys[i] < ymin + (ymax - ymin) * 0.12 and ys[i - 1] < ymin + (ymax - ymin) * 0.12:
				var a: Vector3 = _feet[i - 1][0]
				var b: Vector3 = _feet[i][0]
				sp.append(Vector2(b.x - a.x, b.z - a.z).length() / maxf(_feet[i][1], 0.001))
		sp.sort()
		print("[mc2] haste planted-foot world speed median=%.2f m/s (unit %.2f m/s) anim=%s rate=%.2f" % [
			sp[sp.size() / 2] if not sp.is_empty() else -1.0, _p.stats.move_speed * G.U, _feet[-1][3], _p.anim_player.speed_scale])


func _process(_d: float) -> void:
	_sample_feet(_d)
	if match_ref == null or G.player == null:
		return
	if not _started:
		if match_ref.time > 1.5:
			_started = true
			_setup()
		return
	if _enemy != null and match_ref.time < _t_log_end:
		print("[mc2v] t=%.3f vis=%s d=%.2f e_brush=%d p_brush=%d alpha=%.2f" % [match_ref.time, _enemy.visible_to[_p.team],
			G.flat_dist(_p.global_position, _enemy.global_position), _enemy.in_brush, _p.in_brush, _enemy._alpha])
	if _p != null and match_ref.time > _t_log_end + 2.9 and match_ref.time < _t_log_end + 4.0:
		var ap: AnimationPlayer = _p.anim_player
		print("[mc2a] t=%.3f top=%s atomic=%s cur=%s pos=%.3f/%.3f spd=%.2f playing=%s hold=%s lock=%.3f windup=%.3f atk_t=%.3f g_t=%.3f w=%s" % [
			match_ref.time, _p._g_top, _p._g_atomic, ap.current_animation, ap.current_animation_position if ap.current_animation != "" else -1.0,
			ap.current_animation_length if ap.current_animation != "" else -1.0, ap.speed_scale, ap.is_playing(), _p._g_hold,
			_p.anim_lock, _p.windup_timer, _p.attack_timer, _p._g_t, (_p.socket("BUFFBONE_GLB_WEAPON_1").global_position - _p.global_position).snappedf(0.01)])
	while not _steps.is_empty() and match_ref.time >= _steps[0][0]:
		var f: Callable = _steps.pop_front()[1]
		f.call()
