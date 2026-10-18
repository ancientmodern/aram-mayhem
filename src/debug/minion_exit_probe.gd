extends Node
## [bugfix] Wave-exit probe: for every minion records how long it stays within 10 m of its own barracks.
## Prints MEXIT lines for any minion stuck > 6 s and a final MEXIT SUMMARY. With --mexit_shots=a,b,c also saves screenshots.
## Usage: tools/preview.sh 200 -- --sim --time=300 --harness=res://src/debug/minion_exit_probe.gd
var match_ref = null
var main = null
var _rec := {}      ## Minion -> {t0, near, worst_logged}
var _worst := 0.0
var _worst_idle := 0.0
var _count := 0
var _stuck := 0
var _logged := {}
var _acc := 0.0
var _shot_busy := false
var _shots := []     ## [time, team] from --mexit_shots=52:0,52:1,56:0 ...
var _shot_dir := "user://bugfix_minions"


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--mexit_shots="):
			for it in a.substr(14).split(","):
				var p := it.split(":")
				_shots.append([float(p[0]), int(p[1])])
		elif a.begins_with("--shotdir="):
			_shot_dir = "user://" + a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_shot_dir))


func _physics_process(dt: float) -> void:
	if match_ref == null or match_ref.spawner == null:
		return
	if not _shots.is_empty() and not _shot_busy and match_ref.time >= _shots[0][0] - 0.5:
		var sh: Array = _shots.pop_front()
		_take_shot(sh)
	_acc += dt
	if _acc < 0.25:
		return
	var step := _acc
	_acc = 0.0
	for u in match_ref.units.duplicate():
		if not (u is Minion) or u.dead:
			continue
		if not _rec.has(u):
			_rec[u] = {"near": 0.0, "pos0": u.global_position, "last": u.global_position, "idle": 0.0, "max_idle": 0.0}
			_count += 1
		var r: Dictionary = _rec[u]
		var home: Vector3 = match_ref.spawner.barracks[u.team]
		# stationary (< 0.4 of walking pace) while not fighting anything = blocked
		var mv: float = G.flat_dist(u.global_position, r.last)
		r.last = u.global_position
		if mv < 0.4 * u.stats.move_speed * G.U * step and u.attack_target == null and G.flat_dist(u.global_position, home) < 10.0:
			r.idle += step
		else:
			r.idle = 0.0
		r.max_idle = maxf(r.max_idle, r.idle)
		_worst_idle = maxf(_worst_idle, r.idle)
		if G.flat_dist(u.global_position, home) < 10.0:
			r.near += step
			# fighting enemies right at the base is legitimate; only count idle/moving-lane minions
			if (r.near > 8.0 or r.idle > 2.0) and not _logged.has(u):
				_logged[u] = true
				_stuck += 1
				dump_detail(u)
				print("MEXIT STUCK t=%.1f team=%d type=%d near=%.1fs idle=%.1fs pos=%s lane_i=%d moving=%s attack=%s cmd=%s" % [match_ref.time, u.team, u.minion_type, r.near, r.idle, u.global_position, u.lane_i, u.moving, u.attack_target, u.cmd])
		_worst = maxf(_worst, r.near)
	if int(match_ref.time) % 60 == 0 and int(match_ref.time * 4) % 4 == 0:
		print("MEXIT t=%.0f minions_seen=%d stuck=%d worst_near=%.1fs worst_idle=%.1fs" % [match_ref.time, _count, _stuck, _worst, _worst_idle])
	# prune freed
	for k in _rec.keys():
		if not is_instance_valid(k):
			_rec.erase(k)


func _exit_tree() -> void:
	print("MEXIT SUMMARY minions_seen=%d stuck=%d worst_near=%.1fs worst_idle=%.1fs" % [_count, _stuck, _worst, _worst_idle])


## Detail dump for the first stuck minion of each team (path + positions every 0.5 s for 4 s).
func dump_detail(u) -> void:
	var inh = match_ref.inhibitor_units[u.team]
	print("MEXIT DETAIL team=%d inhib=%s dist_to_inhib=%.2f path=%s path_i=%d lane0=%s lane1=%s walkable_here=%s" % [u.team, inh.global_position, G.flat_dist(u.global_position, inh.global_position), u.path, u.path_i, u.lane[0] if u.lane.size() > 0 else "-", u.lane[1] if u.lane.size() > 1 else "-", match_ref.nav.is_walkable(u.global_position)])


func _take_shot(sh: Array) -> void:
	_shot_busy = true
	var inh: Vector3 = match_ref.inhibitor_units[sh[1]].global_position
	var rig = match_ref.camera_rig
	rig.locked = false
	rig.focus = inh + G.flat_dir(inh, match_ref.lane_path[match_ref.lane_path.size() / 2]) * 3.0
	rig.target_distance = 16.0
	rig.distance = 16.0
	await get_tree().create_timer(0.5, true, false, true).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/wave_t%d_team%d.png" % [_shot_dir, int(sh[0]), sh[1]]
	img.save_png(path)
	print("MEXIT shot ", path)
	_shot_busy = false
