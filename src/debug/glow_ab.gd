extends Node
## A/B the post-process glow during a fight: screenshots with current glow, glow off, and a high HDR threshold.
## Usage: tools/preview.sh 200 -- --sim --botplayer --time=80 --seed=4 --res=2560x1440 --harness=res://src/debug/glow_ab.gd

var match_ref = null
var _t := 0.0
var _done := false
const AT := 62.0


func _process(dt: float) -> void:
	_t += dt
	if _done or match_ref == null or match_ref.time < AT:
		return
	_done = true
	_run()


func _env() -> Environment:
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is WorldEnvironment:
			return n.environment
	return null


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := "user://glow_ab"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])


func _run() -> void:
	var env := _env()
	if env == null:
		print("GLOWAB no environment")
		return
	match_ref.paused = true   # freeze the fight so all three shots show the same frame
	print("GLOWAB glow=%s threshold=%.2f intensity=%.2f bloom=%.2f" % [env.glow_enabled, env.glow_hdr_threshold, env.glow_intensity, env.glow_bloom])
	await get_tree().process_frame
	await _shot("a_current")
	env.glow_enabled = false
	await get_tree().process_frame
	await _shot("b_glow_off")
	env.glow_enabled = true
	env.glow_hdr_threshold = 3.0
	await get_tree().process_frame
	await _shot("c_threshold3")
	print("GLOWAB done")
	get_tree().quit()
