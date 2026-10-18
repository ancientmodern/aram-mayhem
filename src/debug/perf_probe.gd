extends Node
## Performance probe: every few seconds prints fps, frame-time spikes, CPU process time, GPU / render-thread
## time, draw calls, primitives, node count and the Prof per-section CPU breakdown (avg ms / worst-frame ms).
## Usage: tools/preview.sh 300 -- --sim --botplayer --time=200 --harness=res://src/debug/perf_probe.gd [--res=2560x1440]

var match_ref = null
var main = null
var _acc := 0.0
var _frames := 0
var _worst := 0.0
var _pc_last := 0.0
var _gpu := 0.0
var _cpu_r := 0.0
var _proc := 0.0
var _slow := 0   ## frames over 16.7 ms
var _vp_rid: RID
var _t := 0.0
var _dumped := false
var _abl := -1
const ABLATIONS := ["none", "models", "fx", "ambient", "ui", "units_tick", "none2"]


## Subtree ablation (headless, calm opening phase): every 3 s disable one scene branch, report proc per window.
func _ablate_step() -> void:
	var want := int(floor((_t - 6.0) / 3.0))
	if _t < 6.0 or want == _abl or want >= ABLATIONS.size():
		return
	if _abl >= 0:
		print("ABLWIN %-10s proc=%.2fms" % [ABLATIONS[_abl], _abl_proc / maxf(_abl_n, 1)])
	_abl = want
	_abl_proc = 0.0
	_abl_n = 0
	var mode: String = ABLATIONS[_abl]
	if match_ref == null:
		return
	var off_mode := Node.PROCESS_MODE_DISABLED
	for u in match_ref.units:
		if u.model != null:
			u.model.process_mode = off_mode if mode == "models" else Node.PROCESS_MODE_INHERIT
	match_ref.fx_root.process_mode = off_mode if mode == "fx" else Node.PROCESS_MODE_INHERIT
	for ch in match_ref.get_children():
		if ch is MapAmbient:
			ch.process_mode = off_mode if mode == "ambient" else Node.PROCESS_MODE_INHERIT
	for ch in get_tree().root.get_children():
		_set_canvas(ch, mode == "ui")
	match_ref.set_meta("perf_skip_units", mode == "units_tick")


func _set_canvas(n: Node, off: bool) -> void:
	if n is CanvasLayer or n is Control:
		n.process_mode = Node.PROCESS_MODE_DISABLED if off else Node.PROCESS_MODE_INHERIT
		if n is CanvasItem:
			n.visible = not off
		if n is CanvasLayer:
			n.visible = not off
		return
	for c in n.get_children():
		_set_canvas(c, off)


var _abl_proc := 0.0
var _g := -1
var _g_frames := 0
var _g_time := 0.0
var _g_worst := 0.0
const GFX := ["none", "msaa_off", "fxaa_off", "shadows_off", "glow_off", "particles_off", "ui_off", "scale_0.77", "all_off", "none2"]


## Graphics ablation (windowed): every 4 s from t=6 switch one rendering feature off, report fps per window.
func _gfx_step() -> void:
	_g_frames += 1
	_g_time += get_process_delta_time()
	_g_worst = maxf(_g_worst, get_process_delta_time())
	var want := int(floor((_t - 6.0) / 4.0))
	if _t < 6.0 or want == _g or want >= GFX.size():
		return
	if _g >= 0:
		print("GFXWIN %-14s fps=%.1f frame=%.2fms worst=%.1fms" % [GFX[_g], _g_frames / maxf(_g_time, 0.001), 1000.0 * _g_time / maxf(_g_frames, 1), _g_worst * 1000.0])
	_g = want
	_g_frames = 0
	_g_time = 0.0
	_g_worst = 0.0
	var mode: String = GFX[_g]
	var all := mode == "all_off"
	var vp := get_viewport()
	vp.msaa_3d = Viewport.MSAA_DISABLED if (mode == "msaa_off" or all) else Viewport.MSAA_2X
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED if (mode == "fxaa_off" or all) else Viewport.SCREEN_SPACE_AA_FXAA
	vp.scaling_3d_scale = 0.77 if (mode == "scale_0.77" or all) else 1.0
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if (mode == "scale_0.77" or all) else Viewport.SCALING_3D_MODE_BILINEAR
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is DirectionalLight3D:
			if not n.has_meta("had_shadow"):
				n.set_meta("had_shadow", n.shadow_enabled)
			n.shadow_enabled = n.get_meta("had_shadow") and not (mode == "shadows_off" or all)
		elif n is WorldEnvironment and n.environment != null:
			if not n.has_meta("had_glow"):
				n.set_meta("had_glow", n.environment.glow_enabled)
			n.environment.glow_enabled = n.get_meta("had_glow") and not (mode == "glow_off" or all)
		elif n is GPUParticles3D:
			n.visible = not (mode == "particles_off" or all)
		elif n is CanvasLayer:
			n.visible = not (mode == "ui_off" or all)
var _abl_n := 0


## Which nodes run per-frame code (by class + script), to find unprofiled CPU cost.
func _dump_processing() -> void:
	var counts := {}
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		var proc := n.is_processing() or n.is_physics_processing() or n.is_processing_internal() or n.is_physics_processing_internal()
		if not proc and not (n is AnimationMixer) and not (n is GPUParticles3D) and not (n is Skeleton3D):
			continue
		var scr = n.get_script()
		var key: String = n.get_class() + ("|" + scr.resource_path.get_file() if scr != null else "")
		key += " P" if n.is_processing() else ""
		key += " Pi" if n.is_processing_internal() else ""
		key += " Ph" if n.is_physics_processing() else ""
		counts[key] = counts.get(key, 0) + 1
	var keys := counts.keys()
	keys.sort_custom(func(a, b): return counts[a] > counts[b])
	for k in keys:
		print("PROCNODES %4d  %s" % [counts[k], k])


class FrameStart extends Node:
	var probe = null
	func _process(_d: float) -> void:
		var now := Time.get_ticks_usec()
		if probe._last_end > 0:
			probe._outside += now - probe._last_end    # draw / render / physics / idle since last frame's process end
		probe._start = now


var _start := 0
var _last_end := 0
var _outside := 0
var _inside := 0


func _ready() -> void:
	var fs := FrameStart.new()
	fs.probe = self
	fs.process_priority = -100000
	get_tree().root.add_child.call_deferred(fs)
	Prof.enabled = true
	process_priority = 1000   # run after everything else
	_vp_rid = get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(_vp_rid, true)


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _start > 0:
		_inside += now - _start
	_last_end = now
	Prof.end_frame()
	_t += delta
	_acc += delta
	_frames += 1
	_worst = maxf(_worst, delta)
	# hitch attribution: pipeline compiles (first use of a shader variant / vertex format) vs everything else
	var pc := 0.0
	for m in [Performance.PIPELINE_COMPILATIONS_CANVAS, Performance.PIPELINE_COMPILATIONS_MESH,
			Performance.PIPELINE_COMPILATIONS_SURFACE, Performance.PIPELINE_COMPILATIONS_DRAW,
			Performance.PIPELINE_COMPILATIONS_SPECIALIZATION]:
		pc += Performance.get_monitor(m)
	if delta > 0.05:
		print("HITCH t=%.2f %.1fms pipeline_compiles_total=%d (+%d since last hitch check)" % [_t, delta * 1000.0, int(pc), int(pc - _pc_last)])
	_pc_last = pc
	if delta > 1.0 / 60.0 + 0.0005:
		_slow += 1
	_gpu += RenderingServer.viewport_get_measured_render_time_gpu(_vp_rid)
	_cpu_r += RenderingServer.viewport_get_measured_render_time_cpu(_vp_rid)
	_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_abl_proc += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_abl_n += 1
	if "--ablate" in OS.get_cmdline_user_args():
		_ablate_step()
	if "--gfxablate" in OS.get_cmdline_user_args():
		_gfx_step()
	if not _dumped and _t > 70.0:
		_dumped = true
		_dump_processing()
	if _acc >= (2.5 if "--ablate" in OS.get_cmdline_user_args() else 5.0):
		var f := float(_frames)
		var fights := 0
		if match_ref != null:
			for c in match_ref.champions:
				if not c.dead and c.controller != null and "mode" in c.controller and c.controller.mode == "fight":
					fights += 1
		print("FRAME t=%.0f tree_process=%.2fms outside_process(draw+render+physics)=%.2fms" % [_t, _inside / 1000.0 / f, _outside / 1000.0 / f])
		_inside = 0
		_outside = 0
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
