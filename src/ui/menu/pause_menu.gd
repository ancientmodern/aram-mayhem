class_name PauseMenu
extends UIScreen
## In-match Esc menu: resume, settings, surrender, leave to main menu, quit. League game-menu look and sounds.

var match_ref = null
var _settings := false
var _confirm := ""            ## "surrender" / "leave" / "quit" awaiting confirmation
var _open_k := 0.0            ## 0..1 open animation


func _ready() -> void:
	super._ready()
	fade = 1.0
	visible = false


## League's in-game menu sounds (Play_sfx_hud_base_menu_open/close) through GameAudio, client sounds otherwise.
func _menu_sfx(ev: String, fallback: String) -> void:
	if match_ref != null and match_ref.audio != null and match_ref.audio.has(ev):
		match_ref.audio.play(ev, null, -3.0, 0.0)
	else:
		Sfx.ui(fallback)


func open() -> void:
	visible = true
	_settings = false
	_confirm = ""
	_open_k = 0.0
	if match_ref != null and not match_ref.over:
		match_ref.paused = true
	_menu_sfx("Play_sfx_hud_base_menu_open", "flyout_open")


func close() -> void:
	visible = false
	if match_ref != null and not match_ref.over:
		match_ref.paused = false
	_menu_sfx("Play_sfx_hud_base_menu_close", "flyout_close")


func _process(delta: float) -> void:
	super._process(delta)
	_open_k = minf(1.0, _open_k + delta * 6.0)


func draw_screen(vs: Vector2) -> void:
	var ez := 1.0 - pow(1.0 - _open_k, 3.0)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.01, 0.03, 0.74 * ez))
	hit_area("~block", Rect2(Vector2.ZERO, vs), "silent")
	var slide := (1.0 - ez) * 22.0
	if _settings:
		var r := Rect2(vs * 0.5 - Vector2(560, 380) + Vector2(0, slide), Vector2(1120, 760))
		draw_settings(r)
		button("settings_back", Rect2(r.get_center().x - 150, r.end.y - 96, 300, 62), "Done", "primary", true, 24)
		return
	var w := 500.0
	var h := 640.0
	var r := Rect2(vs * 0.5 - Vector2(w, h) * 0.5 + Vector2(0, slide), Vector2(w, h))
	panel(r, 0.97)
	label("Paused", Vector2(r.get_center().x, r.position.y + 62), "h2", 1, C_GOLD_BRIGHT, 46.0, true)
	divider(r.get_center().x, r.position.y + 106, w * 0.62)
	if _confirm != "":
		var q := {"surrender": "Surrender this game?", "leave": "Leave to the main menu?", "quit": "Quit to desktop?"}
		label(q[_confirm], Vector2(r.get_center().x, r.position.y + 218), "h4", 1, C_TEXT, 30.0)
		label("This can't be undone.", Vector2(r.get_center().x, r.position.y + 262), "body_l", 1, C_DIM, 20.0)
		button("yes", Rect2(r.position.x + 60, r.position.y + 330, w - 120, 68), "Yes", "danger", true, 26)
		button("no", Rect2(r.position.x + 60, r.position.y + 420, w - 120, 68), "Cancel", "normal", true, 26)
		return
	var bx := r.position.x + 60
	var bw := w - 120
	var y := r.position.y + 140
	button("resume", Rect2(bx, y, bw, 72), "Resume", "primary", true, 28)
	button("settings", Rect2(bx, y + 92, bw, 62), "Settings", "normal", true, 24)
	button("surrender", Rect2(bx, y + 168, bw, 62), "Surrender", "normal", match_ref != null and not match_ref.over, 24)
	button("leave", Rect2(bx, y + 244, bw, 62), "Main menu", "normal", true, 24)
	button("quit", Rect2(bx, y + 320, bw, 62), "Quit game", "danger", true, 24, "quit")
	label("Esc to resume", Vector2(r.get_center().x, r.end.y - 30), "body", 1, Color(C_DIM.r, C_DIM.g, C_DIM.b, 0.8), 17.0)


func on_action(id: String) -> void:
	if handle_settings_action(id):
		return
	match id:
		"resume":
			close()
		"settings":
			_settings = true
			Sfx.ui("flyout_open")
		"settings_back":
			_settings = false
			Sfx.ui("flyout_close")
		"surrender", "leave", "quit":
			_confirm = id
		"no":
			_confirm = ""
		"yes":
			var what := _confirm
			_confirm = ""
			match what:
				"surrender":
					close()
					match_ref.end_game(G.enemy_team(G.player.team))
				"leave":
					close()
					G.flow_request.emit("menu")
				"quit":
					G.flow_request.emit("quit")


func _unhandled_key_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_pressed() and event is InputEventKey and event.keycode == KEY_ESCAPE:
		if _settings:
			_settings = false
			Sfx.ui("flyout_close")
		elif _confirm != "":
			_confirm = ""
		else:
			close()
		get_viewport().set_input_as_handled()
