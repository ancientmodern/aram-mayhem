extends Node
## [ui-polish] Interaction-state screenshots for the menu screens (hover / press / click animation / slider drag / tooltips)
## by injecting real mouse events. Needs a 1920x1080 window so event coordinates equal viewport coordinates.
## Usage: tools/preview.sh 120 -- --menu --res=1920x1080 --harness=res://src/debug/ui_states.gd --sfxlog
## Screenshots land in user://ui_states/.

var main = null
var shot_dir := "user://ui_states"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := "%s/%s.png" % [shot_dir, name]
	img.save_png(p)
	print("UISTATES SHOT ", ProjectSettings.globalize_path(p))


func _center(id: String) -> Vector2:
	for a in main.screen._prev_areas:
		if a[0] == id:
			return (a[1] as Rect2).get_center()
	push_warning("ui_states: no area " + id)
	return Vector2(10, 10)


func _move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	ev.global_position = p
	Input.parse_input_event(ev)


func _btn(p: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.position = p
	ev.global_position = p
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _click(p: Vector2) -> void:
	_move(p)
	await _wait(0.05)
	_btn(p, true)
	await _wait(0.06)
	_btn(p, false)


func _run() -> void:
	await _wait(2.2)
	var s = main.screen
	await _shot("a01_menu_idle")
	_move(_center("play"))
	await _wait(0.2)
	await _shot("a02_play_hover")
	_move(_center("settings"))
	await _wait(0.2)
	await _shot("a03_settings_hover")
	_btn(_center("settings"), true)
	await _wait(0.1)
	await _shot("a04_settings_down")
	_btn(_center("settings"), false)
	await _wait(0.9)
	await _shot("a05_settings_open")
	_move(_center("set:cast:1"))
	await _wait(0.2)
	await _shot("a06_settings_radio_hover")
	await _click(_center("set:tab:1"))
	await _wait(0.4)
	_move(_center("set:fs:0") if _has("set:fs:0") else _center("set:fs:1"))
	await _wait(0.2)
	await _shot("a07_settings_video_checkbox")
	await _click(_center("set:tab:2"))
	await _wait(0.5)
	var sc := _center("~slider:master_volume")
	_move(sc)
	await _wait(0.1)
	_btn(sc, true)
	await _wait(0.1)
	_move(sc + Vector2(-120, 0))
	await _wait(0.2)
	await _shot("a08_settings_slider_drag")
	_btn(sc + Vector2(-120, 0), false)
	await _wait(0.2)
	await _click(_center("settings_back"))
	await _wait(0.6)
	# champion select
	main.show_champ_select()
	await _wait(2.0)
	s = main.screen
	await _shot("b01_cs_idle")
	var bench_id := ""
	for a in s._prev_areas:
		if str(a[0]).begins_with("bench:"):
			bench_id = a[0]
			break
	_move(_center(bench_id))
	await _wait(0.35)
	print("UISTATES hover=", s.hover_id, " tip=", s.tip, " mouse=", s.get_local_mouse_position())
	await _shot("b02_cs_bench_hover_tip")
	_move(_center("trade:2"))
	await _wait(0.35)
	await _shot("b03_cs_trade_hover")
	_move(_center("ab:2"))
	await _wait(0.35)
	await _shot("b04_cs_ability_tip")
	_move(_center("lock"))
	await _wait(0.4)
	await _shot("b05_cs_lock_hover")
	_move(_center("reroll"))
	await _wait(0.3)
	await _shot("b06_cs_reroll_hover")
	await _click(_center("bench:" + bench_id.substr(6)) if false else _center(bench_id))
	await _wait(0.15)
	await _shot("b07_cs_after_swap")
	print("UISTATES DONE sounds=", Sfx.stats)
	get_tree().quit()


func _has(id: String) -> bool:
	for a in main.screen._prev_areas:
		if a[0] == id:
			return true
	return false
