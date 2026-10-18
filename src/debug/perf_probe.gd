extends Node
## Performance probe: every few seconds prints fps, frame-time spikes, CPU process time, GPU / render-thread
## time, draw calls, primitives, node count and the Prof per-section CPU breakdown (avg ms / worst-frame ms).
## Usage: tools/preview.sh 300 -- --sim --botplayer --time=200 --harness=res://src/debug/perf_probe.gd [--res=2560x1440]

var match_ref = null
var main = null
var _acc := 0.0
var _frames := 0
var _worst := 0.0
var _gpu := 0.0
var _cpu_r := 0.0
var _proc := 0.0
var _slow := 0   ## frames over 16.7 ms
var _vp_rid: RID
var _t := 0.0


func _ready() -> void:
	Prof.enabled = true
	process_priority = 1000   # run after everything else
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)


func _process(delta: float) -> void:
	Prof.end_frame()
	_t += delta
	_acc += delta
	_frames += 1
	_worst = maxf(_worst, delta)
	if delta > 1.0 / 60.0 + 0.0005:
		_slow += 1
	_gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	_cpu_r += RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid)
	_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	if _acc >= 5.0:
		var f := float(_frames)
		var fights := 0
		if match_ref != null:
			for c in match_ref.champions:
				if not c.dead and c.controller != null and "mode" in c.controller and c.controller.mode == "fight":
					fights += 1
		print("PERF t=%.0f fps=%.0f worst=%.1fms slow%%=%.0f proc=%.2fms gpu=%.2fms rcpu=%.2fms draws=%d objs=%d prims=%dk nodes=%d fighting=%d | %s" % [
			_t, f / _acc, _worst * 1000.0, 100.0 * _slow / f, _proc / f, _gpu / f, _cpu_r / f,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000),
			get_tree().get_node_count(), fights, Prof.report(_frames)])
		_acc = 0.0
		_frames = 0
		_worst = 0.0
		_slow = 0
		_gpu = 0.0
		_cpu_r = 0.0
		_proc = 0.0
