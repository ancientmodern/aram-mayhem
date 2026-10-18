class_name PauseMenu
extends UIScreen
## In-match Esc menu: resume, settings, surrender, leave to main menu, quit.

var match_ref = null
var _settings := false
var _confirm := ""            ## "surrender" / "leave" / "quit" awaiting confirmation


func _ready() -> void:
	super._ready()
	fade = 1.0
	visible = false


func open() -> void:
	visible = true
	_settings = false
	_confirm = ""
	if match_ref != null and not match_ref.over:
		match_ref.paused = true
	Sfx.ui("gold_click")


func close() -> void:
	visible = false
	if match_ref != null and not match_ref.over:
		match_ref.paused = false


func draw_screen(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.01, 0.02, 0.7))
	hit_area("~block", Rect2(Vector2.ZERO, vs))
	if _settings:
		var r := Rect2(vs * 0.5 - Vector2(400, 345), Vector2(800, 690))
		draw_settings(r)
		button("settings_back", Rect2(r.get_center().x - 110, r.end.y - 70, 220, 46), "Done")
		return
	var w := 380.0
	var h := 470.0
	var r := Rect2(vs * 0.5 - Vector2(w, h) * 0.5, Vector2(w, h))
	frame(r, Color(0.01, 0.05, 0.08, 0.97), C_GOLD_DARK)
	ornate_frame(r, C_GOLD, 1.5)
	text_center("PAUSED", Vector2(r.get_center().x, r.position.y + 44), 30, C_GOLD_BRIGHT, f_bold, false, 5.0)
	if _confirm != "":
		var q := {"surrender": "Surrender this game?", "leave": "Leave to the main menu?", "quit": "Quit to desktop?"}
		text_center(q[_confirm], Vector2(r.get_center().x, r.position.y + 170), 20, C_TEXT, f_semi)
		button("yes", Rect2(r.position.x + 40, r.position.y + 230, w - 80, 52), "Yes", "danger", true, 20)
		button("no", Rect2(r.position.x + 40, r.position.y + 296, w - 80, 52), "Cancel", "normal", true, 20)
		return
	var bx := r.position.x + 40
	var bw := w - 80
	var y := r.position.y + 90
	button("resume", Rect2(bx, y, bw, 56), "Resume", "primary", true, 22)
	button("settings", Rect2(bx, y + 76, bw, 48), "Settings")
	button("surrender", Rect2(bx, y + 136, bw, 48), "Surrender", "normal", match_ref != null and not match_ref.over)
	button("leave", Rect2(bx, y + 196, bw, 48), "Main Menu")
	button("quit", Rect2(bx, y + 256, bw, 48), "Quit Game", "danger")
	text_center("Esc to resume", Vector2(r.get_center().x, r.end.y - 22), 13, C_DIM, f_body)


func on_action(id: String) -> void:
	if handle_settings_action(id):
		return
	match id:
		"resume":
			close()
		"settings":
			_settings = true
		"settings_back":
			_settings = false
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
		elif _confirm != "":
			_confirm = ""
		else:
			close()
		get_viewport().set_input_as_handled()
