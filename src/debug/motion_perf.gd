extends Node
## [motion] perf probe for the animation / visual / collision systems: like perf_probe.gd plus the share
## of mixer updates skipped by the animation LOD. A/B: add --animlod=0 to disable the LOD.
## tools/preview.sh 200 -- --sim --botplayer --seed=7 --harness=res://src/debug/motion_perf.gd --res=2560x1440

var match_ref = null
var main = null
var _acc := 0.0
var _frames := 0
var _proc := 0.0
var _t := 0.0
var _tot := {}
var _tot_frames := 0
var _tot_proc := 0.0
var _tot_fps_t := 0.0


func _ready() -> void:
	Prof.enabled = true
	process_priority = 1000


func _process(delta: float) -> void:
	Prof.end_frame()
	_t += delta
	_acc += delta
	_frames += 1
	_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	if _acc >= 10.0:
		var f := float(_frames)
		var st: Array = Unit.anim_stats
		var n := maxi(st[0] + st[1], 1)
		var keys := ["u.anim", "u.visual", "collide", "u.move"]
		var line := ""
		for k in keys:
			var v: float = Prof.acc.get(k, 0) / 1000.0 / f
			line += " %s=%.3f" % [k, v]
			if _t > 15.0:
				_tot[k] = _tot.get(k, 0.0) + Prof.acc.get(k, 0) / 1000.0
		if _t > 15.0:
			_tot_frames += _frames
			_tot_proc += _proc
			_tot_fps_t += _acc
		print("MPERF t=%.0f fps=%.0f proc=%.2fms adv/frame=%.1f skipped=%.0f%% lod=%s |%s" % [_t, f / _acc, _proc / f,
			st[0] / f, 100.0 * st[1] / n, Unit.anim_lod, line])
		if _tot_frames > 0:
			var tl := ""
			for k in _tot:
				tl += " %s=%.3f" % [k, _tot[k] / _tot_frames]
			print("MPERF_AVG frames=%d fps=%.1f proc=%.2fms |%s" % [_tot_frames, _tot_frames / _tot_fps_t, _tot_proc / _tot_frames, tl])
		Prof.report(_frames)   # clears acc / peak
		Unit.anim_stats[0] = 0
		Unit.anim_stats[1] = 0
		_acc = 0.0
		_frames = 0
		_proc = 0.0
