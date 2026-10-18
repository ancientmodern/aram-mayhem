extends Node
## A/B the League gamma-space colour pipeline against Godot's linear blending on the SAME frozen frame.
## Usage: tools/preview.sh 200 -- --sim --botplayer --time=80 --seed=4 --res=2560x1440 --harness=res://src/debug/gamma_ab.gd
## Shots: user://gamma_ab/<t>_gamma.png and <t>_linear.png

var match_ref = null
var _times := [58.0, 61.0, 63.0, 65.0]
var _busy := false


func _process(_dt: float) -> void:
	if _busy or match_ref == null or _times.is_empty() or match_ref.time < _times[0]:
		return
	_busy = true
	_run(_times.pop_front())


func _we() -> WorldEnvironment:
	var stack: Array = [get_tree().root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is WorldEnvironment:
			return n
	return null


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var dir := "user://gamma_ab"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [dir, name])


func _set_gamma(we: WorldEnvironment, on: bool) -> void:
	RenderingServer.global_shader_parameter_set("gamma_out", 1.0 if on else 0.0)
	if we.compositor != null:
		for e in we.compositor.compositor_effects:
			e.enabled = on
	var env := we.environment
	if on:
		env.background_color = env.background_color.linear_to_srgb()
		env.fog_light_color = env.fog_light_color.linear_to_srgb()
	else:
		env.background_color = env.background_color.srgb_to_linear()
		env.fog_light_color = env.fog_light_color.srgb_to_linear()


func _run(t: float) -> void:
	var we := _we()
	match_ref.paused = true
	await get_tree().process_frame
	await _shot("%d_gamma" % int(t))
	_set_gamma(we, false)
	await get_tree().process_frame
	await _shot("%d_linear" % int(t))
	_set_gamma(we, true)
	await get_tree().process_frame
	match_ref.paused = false
	print("GAMMAAB shot ", t)
	_busy = false
	if _times.is_empty():
		get_tree().quit()
