class_name HudChat
extends RefCounted
## League's in-game chat box (Chat/UIBase in UI.wad: chatframe_atlas, HUD_Chat / HUD_InputBox font styles).
## System messages: kills ("X has slain Y!"), objectives / announcements, welcome text; player messages typed after
## Enter (shown as "[All] Name (Champion): text"). Timestamps like League's ShowTimestamps option. Lines fade out
## 10 s after they arrive while the box is closed; Enter opens the input with the full scrollable history.

const C_SYS := Color(1.0, 0.86, 0.47)          ## League system message (yellow-gold)
const C_ALLY := Color(0.35, 0.65, 1.0)
const C_ENEMY := Color(1.0, 0.33, 0.3)
const C_WHITE := Color(0.95, 0.95, 0.95)
const C_TIME := Color(0.75, 0.75, 0.72)
const MAX_LINES := 120
const SHOW_TIME := 10.0
const FADE_TIME := 1.5

var hud = null
var messages: Array = []        ## {segs: [[text, Color]], t}
var typing := false
var scroll := 0                 ## lines scrolled up while open
var input: LineEdit = null
var origin := Vector2.ZERO
var k := 1.0
var _text_rc := Rect2()
var _box_rc := Rect2()
var _sig_t := 0.0


func setup(h) -> void:
	hud = h
	input = LineEdit.new()
	input.visible = false
	input.flat = true
	input.max_length = 160
	input.context_menu_enabled = false
	input.caret_blink = true
	var sb := StyleBoxEmpty.new()
	for nm in ["normal", "focus", "read_only"]:
		input.add_theme_stylebox_override(nm, sb)
	input.text_submitted.connect(_on_submit)
	input.gui_input.connect(_on_input_key)
	h.add_child(input)


func layout() -> void:
	var L: HudLayout = hud.L
	# League scales chat with ChatScale only (elements ignore the global HUD scale); source space is 1920x1440
	k = L.vs.y / 1440.0
	var h := 312.0 * k
	var stats_top: float = L.r("Stats:StatsBg").position.y
	origin = Vector2(roundf(10.0 * k), roundf(stats_top - h - 14.0 * k))
	_text_rc = L.lr("Chat:ChatFrame_Text", origin, k)
	_box_rc = L.lr("Chat:ChatFrame_Bounds", origin, k)
	var er := L.lr("Chat:ChatFrame_TextEdit", origin, k)
	var st := L.style("HUD_InputBox")
	input.position = er.position
	input.size = er.size
	input.add_theme_font_override("font", st.font)
	input.add_theme_font_size_override("font_size", st.px)
	input.add_theme_color_override("font_color", Color.WHITE)
	input.add_theme_color_override("caret_color", Color.WHITE)


func _stamp() -> String:
	var t: float = hud.match_ref.time if hud.match_ref != null else 0.0
	return "[%02d:%02d] " % [int(t / 60.0), int(t) % 60]


func add(segs: Array) -> void:
	messages.append({"segs": [[_stamp(), C_TIME]] + segs, "t": hud._now})
	if messages.size() > MAX_LINES:
		messages.pop_front()


func system(text: String, col := C_SYS) -> void:
	add([[text, col]])


func _name_col(u) -> Color:
	return C_ALLY if u != null and is_instance_valid(u) and u.team == hud.champ.team else C_ENEMY


func _unit_name(u) -> String:
	if u == null or not is_instance_valid(u):
		return "Minion"
	if u.kind == G.Kind.CHAMPION:
		return "%s (%s)" % [u.display_name, ChampionDB.client_data(u.alias).get("name", u.alias)] \
			if u.display_name != ChampionDB.client_data(u.alias).get("name", u.alias) else u.display_name
	if u.kind == G.Kind.TURRET:
		return "Turret"
	return u.display_name


func kill(victim, killer) -> void:
	if victim == null or not is_instance_valid(victim):
		return
	if killer == null or not is_instance_valid(killer) or killer.kind != G.Kind.CHAMPION:
		add([[_unit_name(victim), _name_col(victim)], [" has been slain!", C_SYS]])
		return
	add([[_unit_name(killer), _name_col(killer)], [" has slain ", C_SYS], [_unit_name(victim), _name_col(victim)], ["!", C_SYS]])


func announcement(text: String, _col: Color) -> void:
	var t := text.strip_edges()
	if t == "":
		return
	if not (t.ends_with("!") or t.ends_with(".")):
		t += "!"
	system(t)


func open() -> void:
	if typing:
		return
	typing = true
	scroll = 0
	input.text = ""
	input.visible = true
	input.grab_focus()
	if hud.match_ref != null and hud.match_ref.player_controller != null:
		hud.match_ref.player_controller.ui_blocking = true


func close() -> void:
	typing = false
	scroll = 0
	input.release_focus()
	input.visible = false
	if hud.match_ref != null and hud.match_ref.player_controller != null:
		hud.match_ref.player_controller.ui_blocking = hud.shop_panel != null and hud.shop_panel.visible


func _on_submit(txt: String) -> void:
	var t := txt.strip_edges()
	if t != "":
		var c = hud.champ
		add([["[All] ", C_WHITE], [_unit_name(c), C_ALLY], [": " + t, C_WHITE]])
		hud.hud_sfx("Play_sfx_hud_base_Chat_All", -6.0)   # [ui-polish]
	close()


func _on_input_key(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		close()
		input.accept_event()


func has_point(mp: Vector2) -> bool:
	return typing and _box_rc.has_point(mp)


func handle_wheel(mp: Vector2, up: bool) -> bool:
	if not has_point(mp):
		return false
	scroll = clampi(scroll + (2 if up else -2), 0, maxi(0, messages.size() - 3))
	return true


func process(_delta: float) -> void:
	if typing and not input.has_focus():
		close()


func _alpha(m: Dictionary) -> float:
	if typing:
		return 1.0
	var age: float = hud._now - m.t
	return clampf((SHOW_TIME + FADE_TIME - age) / FADE_TIME, 0.0, 1.0)


func sig() -> Array:
	var s := [messages.size(), typing, scroll]
	for i in range(maxi(0, messages.size() - 10), messages.size()):
		s.append(int(_alpha(messages[i]) * 12.0))
	return s


func draw(ci: CanvasItem) -> void:
	var L: HudLayout = hud.L
	if typing:
		L.draw_in(ci, "Chat:ChatFrame_Background", Rect2(_text_rc.position - Vector2(10, 0) * k, Vector2(_box_rc.size.x, _text_rc.size.y)), Color(1, 1, 1, 0.55))
		L.ldraw(ci, "Chat:ChatFrame_Input_Frame_L", origin, k)
		L.ldraw(ci, "Chat:ChatFrame_Input_Frame_C", origin, k)
		L.ldraw(ci, "Chat:ChatFrame_Input_Frame_R", origin, k)
		if input.text == "":
			L.ltext_in(ci, "Chat:ChatFrame_Input_Indicator_Text", L.lr("Chat:ChatFrame_Input_Indicator_Text", origin, k), "[All] Press Enter to send, Esc to close")
	var st := L.style("HUD_Chat")
	var px: int = st.px
	var font: Font = st.font
	var lh := roundf(px * 1.3)
	var width := _text_rc.size.x
	# lay out bottom-up: newest message at the bottom of the text area
	var y := _text_rc.end.y - lh * 0.3
	var skipped := 0
	for mi in range(messages.size() - 1, -1, -1):
		var m: Dictionary = messages[mi]
		var a := _alpha(m)
		if a <= 0.0:
			break
		var rows := _wrap(m.segs, font, px, width)
		for ri in range(rows.size() - 1, -1, -1):
			if skipped < scroll:
				skipped += 1
				continue
			if y - lh < _text_rc.position.y:
				return
			var x := _text_rc.position.x
			for seg in rows[ri]:
				var c: Color = seg[1]
				var col := Color(c.r, c.g, c.b, c.a * a)
				ci.draw_string(font, Vector2(x + 1, y + 1), seg[0], HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(0, 0, 0, 0.85 * a))
				ci.draw_string(font, Vector2(x, y), seg[0], HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
				x += font.get_string_size(seg[0], HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			y -= lh


## Word-wrap coloured segments into rows of segments (cached per message and font size).
func _wrap(segs: Array, font: Font, px: int, width: float) -> Array:
	var rows: Array = [[]]
	var x := 0.0
	for seg in segs:
		var words: PackedStringArray = String(seg[0]).split(" ")
		var cur := ""
		for wi in words.size():
			var w := words[wi] + (" " if wi < words.size() - 1 else "")
			var ww := font.get_string_size(w, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
			if x + ww > width and x > 0.0:
				if cur != "":
					rows[rows.size() - 1].append([cur, seg[1]])
				rows.append([])
				cur = ""
				x = 0.0
			cur += w
			x += ww
		if cur != "":
			rows[rows.size() - 1].append([cur, seg[1]])
	return rows
