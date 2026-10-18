class_name MainMenu
extends UIScreen
## Title screen: cycling splash art, PLAY / SETTINGS / QUIT in League client styling.

var _arts: Array = []
var _art_i := 0
var _art_t := 0.0
var _show_settings := false
var _settings_k := 0.0        ## 0..1 settings window open animation
const ART_TIME := 9.0


func _ready() -> void:
	super._ready()
	var roster: Array = ChampionDB.ROSTER.duplicate()
	roster.shuffle()
	for a in roster:
		var tx := Assets.champion_art(a, 0, "splash")
		if tx != null:
			_arts.append(tx)
	Sfx.music("music-cs-draft-pickintent-01", 2.0)


func _process(delta: float) -> void:
	super._process(delta)
	_art_t += delta
	if _art_t > ART_TIME:
		_art_t = 0.0
		_art_i = (_art_i + 1) % maxi(_arts.size(), 1)
	_settings_k = move_toward(_settings_k, 1.0 if _show_settings else 0.0, delta * 5.0)


func draw_screen(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), C_BG)
	_draw_art(vs)
	smoke(vs, 0.10, 7.0)
	# readability gradient on the left
	_hgrad(Rect2(0, 0, vs.x * 0.6, vs.y), Color(0.0, 0.02, 0.05, 0.94), Color(0.0, 0.02, 0.05, 0.0))
	vignette(vs, 0.65)
	# top bar
	_vgrad(Rect2(0, 0, vs.x, 86), Color(0.004, 0.039, 0.075, 0.9), Color(0.004, 0.039, 0.075, 0.0))
	var x := 130.0
	var y := vs.y * 0.17
	var k0 := appear(0.05)
	var k1 := appear(0.2)
	# title: gold gradient ARAM with an occasional shine sweep, violet MAYHEM
	var sweep := fmod(t, 7.0) / 1.6
	var shine := sweep if sweep <= 1.0 else -1.0
	var modal := _settings_k
	var ta := 1.0 - clampf(modal * 4.0, 0.0, 1.0)
	grad_text("title_aram", "ARAM", Rect2(x - 12, y + 6 - (1.0 - k0) * 20, 640, 210), 178, "Heavy", 0.03, 0, k0 * ta, shine, [], 5)
	grad_text("title_mayhem", "MAYHEM", Rect2(x + 6, y + 206 - (1.0 - k1) * 14, 640, 84), 64, "Bold", 0.34, 0, k1 * ta,
			shine - 0.25 if shine >= 0.0 else -1.0, [Color("ffe6f7"), Color("e58cff"), Color("a35bff")], 3)
	var dc := appear(0.35)
	divider(x + 270, y + 306, 540.0 * dc, dc * ta)
	label("Howling Abyss  ·  5v5  ·  Single player", Vector2(x, y + 346), "sub", 0, Color(C_DIM.r, C_DIM.g, C_DIM.b, appear(0.45) * ta), 21.0)
	# buttons
	var by := y + 410.0
	var bw := 440.0
	var ka := appear(0.5)
	var off := (1.0 - ka) * -40.0
	find_button("play", Rect2(x + off, by, bw, 110), "Play", true, "play", 36.0)
	button("settings", Rect2(x + off * 1.4, by + 134, bw, 62), "Settings", "normal", true, 24)
	button("quit", Rect2(x + off * 1.8, by + 212, bw, 62), "Quit", "normal", true, 24, "quit")
	# controls cheat sheet
	var hy := vs.y - 168.0
	label("Controls", Vector2(x, hy), "h5", 0, C_GOLD, 20.0)
	var rows := [
		[["Right-click"], "Move / attack", ["A"], "Attack-move", ["S"], "Stop"],
		[["Q"], ["W"], ["E"], ["R"], "Abilities  (Ctrl + key to level up)", ["D"], ["F"], "Summoner spells", ["1"], "-", ["6"], "Item actives"],
		[["P"], "Shop", ["Tab"], "Scoreboard", ["Space"], "Center camera", ["Y"], "Lock camera", ["Esc"], "Menu"],
	]
	for i in rows.size():
		var cx := x
		var cy := hy + 38 + i * 36
		for part in rows[i]:
			if part is Array:
				cx += _keycap(part[0], Vector2(cx, cy)) + 6
			else:
				cx += label(str(part), Vector2(cx, cy), "body_l", 0, Color("b8b2a2"), 19.0) + 22
	label("Fan-made tribute · not affiliated with Riot Games", Vector2(vs.x - 28, vs.y - 22), "body", 2, Color(1, 1, 1, 0.3), 16.0)
	if _settings_k > 0.001:
		var ez := 1.0 - pow(1.0 - _settings_k, 3.0)
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0.01, 0.03, 0.72 * ez))
		hit_area("~block", Rect2(Vector2.ZERO, vs), "silent")
		var r := Rect2(vs * 0.5 - Vector2(560, 380) + Vector2(0, (1.0 - ez) * 26.0), Vector2(1120, 760))
		draw_settings(r)
		button("settings_back", Rect2(r.get_center().x - 150, r.end.y - 96, 300, 62), "Done", "primary", true, 24)


## Small keyboard key glyph; returns its width.
func _keycap(s: String, p: Vector2) -> float:
	var w := label_w(s, "strong", 18.0) + 22.0
	var r := Rect2(p.x, p.y - 15, maxf(w, 30.0), 30)
	draw_rect(r, Color(0.07, 0.09, 0.12, 0.9))
	grad_border(r, 1.5, [[0.0, Color("463714")], [1.0, Color("785a28")]])
	label(s, r.get_center(), "strong", 1, C_BTN, 18.0)
	return r.size.x


func _draw_art(vs: Vector2) -> void:
	if _arts.is_empty():
		return
	var k := _art_t / ART_TIME
	var zoom := 1.06 + 0.06 * k
	var r := Rect2(vs * 0.5 - vs * zoom * 0.5 + Vector2(-30.0 * k, 0), vs * zoom)
	var cur: Texture2D = _arts[_art_i]
	var intro := clampf(t / 1.4, 0.0, 1.0)
	tex_cover(cur, r, Color(1, 1, 1, 0.92 * intro))
	# crossfade from the previous art in the first second
	if _art_t < 1.2 and _arts.size() > 1:
		var prev: Texture2D = _arts[(_art_i - 1 + _arts.size()) % _arts.size()]
		tex_cover(prev, Rect2(vs * 0.5 - vs * 1.12 * 0.5 + Vector2(-30, 0), vs * 1.12), Color(1, 1, 1, 0.92 * (1.0 - _art_t / 1.2)))


func on_action(id: String) -> void:
	if handle_settings_action(id):
		return
	match id:
		"settings":
			_show_settings = true
			Sfx.ui("flyout_open")
		"settings_back":
			_show_settings = false
			Sfx.ui("flyout_close")
		_:
			super.on_action(id)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and event is InputEventKey and event.keycode == KEY_ESCAPE and _show_settings:
		_show_settings = false
		Sfx.ui("flyout_close")
