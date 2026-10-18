class_name MainMenu
extends UIScreen
## Title screen: cycling splash art, PLAY / SETTINGS / QUIT.

var _arts: Array = []
var _art_i := 0
var _art_t := 0.0
var _show_settings := false
const ART_TIME := 9.0


func _ready() -> void:
	super._ready()
	var roster: Array = ChampionDB.ROSTER.duplicate()
	roster.shuffle()
	for a in roster:
		var tex := Assets.champion_art(a, 0, "splash")
		if tex != null:
			_arts.append(tex)
	Sfx.music("music-cs-draft-pickintent-01", 2.0)


func _process(delta: float) -> void:
	super._process(delta)
	_art_t += delta
	if _art_t > ART_TIME:
		_art_t = 0.0
		_art_i = (_art_i + 1) % maxi(_arts.size(), 1)


func draw_screen(vs: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vs), C_BG)
	_draw_art(vs)
	# readability gradient on the left
	_hgrad(Rect2(0, 0, vs.x * 0.55, vs.y), Color(0.0, 0.02, 0.04, 0.92), Color(0.0, 0.02, 0.04, 0.0))
	vignette(vs, 0.6)
	var x := 110.0
	var y := vs.y * 0.2
	# title
	var pulse := 0.5 + 0.5 * sin(t * 1.6)
	text("ARAM", Vector2(x - 6, y + 120), 150, C_GOLD_BRIGHT, f_heavy, true)
	var mayhem_col := Color(0.75, 0.45, 1.0).lerp(Color(1.0, 0.55, 0.85), pulse)
	_text_spaced("MAYHEM", Vector2(x + 205, y + 168), 54, mayhem_col, f_heavy, 16.0, true)
	draw_line(Vector2(x, y + 205), Vector2(x + 430, y + 205), C_GOLD_DARK, 2.0)
	text("HOWLING ABYSS  ·  5V5  ·  SINGLE PLAYER", Vector2(x, y + 236), 17, C_DIM, f_semi)
	# buttons
	var by := y + 300.0
	var bw := 330.0
	button("play", Rect2(x, by, bw, 64), "Play", "primary", true, 26)
	button("settings", Rect2(x, by + 84, bw, 50), "Settings")
	button("quit", Rect2(x, by + 152, bw, 50), "Quit")
	# controls cheat sheet
	var hy := vs.y - 150.0
	text("CONTROLS", Vector2(x, hy), 16, C_GOLD, f_bold)
	var lines := [
		"Right-click  move / attack      A + click  attack-move      S  stop",
		"Q W E R  abilities (Ctrl+key to level)      D F  summoner spells      1-6  item actives",
		"P  shop      Tab  scoreboard      Space  center camera      Y  lock camera      Esc  menu",
	]
	for i in lines.size():
		text(lines[i], Vector2(x, hy + 26 + i * 22), 15, C_TEXT.darkened(0.15), f_body)
	text_right("Fan-made tribute · not affiliated with Riot Games", Vector2(vs.x - 24, vs.y - 18), 13, Color(1, 1, 1, 0.35), f_body)
	if _show_settings:
		draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.6))
		hit_area("~block", Rect2(Vector2.ZERO, vs))
		var r := Rect2(vs * 0.5 - Vector2(400, 345), Vector2(800, 690))
		draw_settings(r)
		button("settings_back", Rect2(r.get_center().x - 110, r.end.y - 70, 220, 46), "Done")


func _draw_art(vs: Vector2) -> void:
	if _arts.is_empty():
		return
	var k := _art_t / ART_TIME
	var zoom := 1.06 + 0.06 * k
	var r := Rect2(vs * 0.5 - vs * zoom * 0.5 + Vector2(-30.0 * k, 0), vs * zoom)
	var cur: Texture2D = _arts[_art_i]
	tex_cover(cur, r, Color(1, 1, 1, 0.9))
	# crossfade from the previous art in the first second
	if _art_t < 1.2 and _arts.size() > 1:
		var prev: Texture2D = _arts[(_art_i - 1 + _arts.size()) % _arts.size()]
		tex_cover(prev, Rect2(vs * 0.5 - vs * 1.12 * 0.5 + Vector2(-30, 0), vs * 1.12), Color(1, 1, 1, 0.9 * (1.0 - _art_t / 1.2)))


func on_action(id: String) -> void:
	if handle_settings_action(id):
		return
	match id:
		"settings":
			_show_settings = true
		"settings_back":
			_show_settings = false
		_:
			super.on_action(id)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and event is InputEventKey and event.keycode == KEY_ESCAPE and _show_settings:
		_show_settings = false
