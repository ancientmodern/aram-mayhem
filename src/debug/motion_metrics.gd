extends Node
## QA: measures how natural champion movement looks (bots).
## Per champion: direction reversals per minute while moving, stop/start toggles per minute,
## share of time standing still while enemies are near, and average sideways "dither" distance.
## Usage: godot --headless --path . --fixed-fps 60 -- --harness=res://src/debug/motion_metrics.gd [--time=240]

var match_ref = null
var main = null
var dur := 240.0
var _t := 0.0
var _acc := 0.0
var _data := {}   ## champ -> stats dict


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--time="):
			dur = float(a.substr(7))


func _physics_process(dt: float) -> void:
	if match_ref == null or match_ref.champions.is_empty():
		return
	_t += dt
	_acc += dt
	if _acc >= 0.1:
		_acc = 0.0
		for c in match_ref.champions:
			if c != G.player:
				_sample(c)
	if _t >= dur:
		_report()
		get_tree().quit()


func _sample(c) -> void:
	if not _data.has(c):
		_data[c] = {"pos": c.global_position, "dir": Vector3.ZERO, "moving": false, "rev": 0, "toggles": 0,
				"move_t": 0.0, "near_t": 0.0, "idle_near_t": 0.0, "alive_t": 0.0, "short_moves": 0, "seg_len": 0.0, "mode": "", "mode_sw": 0, "flip": 0, "last_sw": -9.0, "trans": {}}
	var d: Dictionary = _data[c]
	if c.dead:
		d.pos = c.global_position
		d.moving = false
		return
	d.alive_t += 0.1
	var br = c.controller
	if br != null and "mode" in br and br.mode != d.mode:
		if d.mode != "":
			d.mode_sw += 1
			var key: String = d.mode + ">" + br.mode
			d.trans[key] = d.trans.get(key, 0) + 1
			if _t - d.last_sw < 1.5:
				d.flip += 1
		d.last_sw = _t
		d.mode = br.mode
	var delta: Vector3 = c.global_position - d.pos
	delta.y = 0.0
	d.pos = c.global_position
	var mv: bool = delta.length() > 0.05
	if mv != d.moving:
		d.toggles += 1
		if not mv and d.seg_len < 0.6:
			d.short_moves += 1
		d.seg_len = 0.0
	d.moving = mv
	if mv:
		d.move_t += 0.1
		d.seg_len += delta.length()
		var nd := delta.normalized()
		if d.dir != Vector3.ZERO and nd.dot(d.dir) < -0.5:
			d.rev += 1
		d.dir = nd
	var near := false
	for o in match_ref.champions:
		if o.team != c.team and not o.dead and G.flat_dist(o.global_position, c.global_position) < 9.0:
			near = true
			break
	if near:
		d.near_t += 0.1
		if not mv and not c.is_busy() and c.windup_timer < 0.0 and c.attack_target == null:
			d.idle_near_t += 0.1


func _report() -> void:
	print("MOTION METRICS (%.0fs)" % dur)
	print("%-14s %8s %8s %8s %9s %8s %8s %8s" % ["champ", "rev/min", "tog/min", "short/m", "idleNear%", "move%", "mode/m", "flip/m"])
	var tot := {"rev": 0.0, "tog": 0.0, "short": 0.0, "idle": 0.0}
	for c in _data:
		var d: Dictionary = _data[c]
		var mins: float = maxf(d.alive_t / 60.0, 0.01)
		var rev: float = d.rev / mins
		var tog: float = d.toggles / mins
		var sh: float = d.short_moves / mins
		var idle: float = 100.0 * d.idle_near_t / maxf(d.near_t, 0.1)
		print("%-14s %8.1f %8.1f %8.1f %9.1f %8.1f %8.1f %8.1f  %s" % [c.display_name, rev, tog, sh, idle, 100.0 * d.move_t / maxf(d.alive_t, 0.1), d.mode_sw / mins, d.flip / mins, str(d.trans)])
		tot.rev += rev
		tot.tog += tog
		tot.short += sh
		tot.idle += idle
	var n := float(maxi(_data.size(), 1))
	print("AVG rev/min=%.1f tog/min=%.1f short/min=%.1f idleNear=%.1f%%" % [tot.rev / n, tot.tog / n, tot.short / n, tot.idle / n])
