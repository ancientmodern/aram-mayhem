class_name UIScreen
extends Control
## Base for full-screen menu screens (main menu, champion select, loading, end of game, pause).
## Screens draw themselves in draw_screen() and register clickable rects with button()/hit_area();
## input is resolved against the rects registered on the previous frame (immediate-mode GUI).

signal action(id: String)

const C_BG := Color(0.004, 0.035, 0.06)
const C_PANEL := Color(0.01, 0.06, 0.09, 0.92)
const C_GOLD := Color(0.78, 0.67, 0.43)
const C_GOLD_BRIGHT := Color(0.96, 0.88, 0.66)
const C_GOLD_DARK := Color(0.47, 0.35, 0.16)
const C_TEXT := Color(0.94, 0.9, 0.82)
const C_DIM := Color(0.58, 0.6, 0.62)
const C_TEAL := Color(0.04, 0.78, 0.73)
const C_RED := Color(0.86, 0.22, 0.2)

var f_title: Font
var f_heavy: Font
var f_bold: Font
var f_body: Font
var f_semi: Font
var t := 0.0
var fade := 0.0               ## 0..1 fade-in
var hover_id := ""
var press_id := ""
var _areas: Array = []        ## [[id, rect]] registered this frame (later = on top)
var _prev_areas: Array = []
var tip := {}                 ## {title, body} shown near the mouse when hovering
var _tip_next := {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	f_title = Assets.font("beaufort", "Bold")
	f_heavy = Assets.font("beaufort", "Heavy")
	f_bold = Assets.font("beaufort", "Bold")
	f_body = Assets.font("spiegel", "Regular")
	f_semi = Assets.font("spiegel", "SemiBold")


func _process(delta: float) -> void:
	# UI animates in real time even while the match runs in slow motion
	var rd := delta / maxf(Engine.time_scale, 0.001)
	t += rd
	fade = minf(1.0, fade + rd * 3.0)
	queue_redraw()


func _draw() -> void:
	_areas.clear()
	_tip_next = {}
	draw_screen(size)
	tip = _tip_next
	if not tip.is_empty():
		_draw_tip()
	_prev_areas = _areas.duplicate()
	if fade < 1.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 1.0 - fade))


## Override.
func draw_screen(_vs: Vector2) -> void:
	pass


## Override: called with a clicked id. Default re-emits `action`.
func on_action(id: String) -> void:
	action.emit(id)


func _hit(p: Vector2) -> String:
	for i in range(_prev_areas.size() - 1, -1, -1):
		var a: Array = _prev_areas[i]
		if (a[1] as Rect2).has_point(p):
			return a[0]
	return ""


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var h := _hit(event.position)
		if h != hover_id:
			hover_id = h
			if h != "" and not h.begins_with("~"):
				Sfx.ui("hover")
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press_id = _hit(event.position)
		else:
			var h := _hit(event.position)
			if h != "" and h == press_id and not h.begins_with("~"):
				Sfx.ui("click")
				on_action(h)
			press_id = ""
		accept_event()


# ===================================================================== widgets
func hit_area(id: String, r: Rect2) -> void:
	_areas.append([id, r])


func is_hover(id: String) -> bool:
	return hover_id == id


func set_tip(id: String, title: String, body: String) -> void:
	if hover_id == id:
		_tip_next = {"title": title, "body": body}


## LoL client style button. style: "primary" (gold/teal call to action), "normal", "danger".
func button(id: String, r: Rect2, label: String, style: String = "normal", enabled: bool = true, sz: int = 20) -> void:
	if enabled:
		hit_area(id, r)
	var hov := enabled and hover_id == id
	var down := hov and press_id == id
	var fill := Color(0.03, 0.09, 0.12, 0.95)
	var border := C_GOLD if enabled else Color(0.3, 0.3, 0.3)
	var txt := C_GOLD_BRIGHT if enabled else Color(0.45, 0.45, 0.45)
	match style:
		"primary":
			fill = Color(0.02, 0.2, 0.24) if enabled else Color(0.08, 0.1, 0.11)
			border = C_TEAL if enabled else Color(0.3, 0.3, 0.3)
			txt = Color(0.85, 1.0, 0.98) if enabled else Color(0.45, 0.45, 0.45)
		"danger":
			fill = Color(0.18, 0.03, 0.03)
			border = Color(0.75, 0.3, 0.25)
			txt = Color(1.0, 0.85, 0.8)
	if hov:
		fill = fill.lightened(0.12)
		border = border.lightened(0.3)
	if down:
		fill = fill.darkened(0.3)
	draw_rect(r, fill)
	# inner gradient sheen
	var sheen := Color(1, 1, 1, 0.06 if not hov else 0.11)
	_vgrad(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.5)), sheen, Color(1, 1, 1, 0.0))
	draw_rect(r, border, false, 2.0)
	if style == "primary" and enabled:
		var glow := 0.25 + 0.15 * sin(t * 3.0) + (0.25 if hov else 0.0)
		draw_rect(r.grow(3), Color(border.r, border.g, border.b, glow * 0.5), false, 2.0)
	text_center(label.to_upper(), r.get_center(), sz, txt, f_bold)


## Selectable pill (segmented control item / toggle).
func pill(id: String, r: Rect2, label: String, selected: bool, sz: int = 16) -> void:
	hit_area(id, r)
	var hov := hover_id == id
	draw_rect(r, Color(0.06, 0.16, 0.2, 0.95) if selected else Color(0.02, 0.06, 0.09, 0.9))
	draw_rect(r, C_GOLD if selected else (C_GOLD_DARK.lightened(0.3) if hov else C_GOLD_DARK), false, 1.5 if not selected else 2.0)
	text_center(label, r.get_center(), sz, C_GOLD_BRIGHT if selected else (C_TEXT if hov else C_DIM), f_bold)


## Horizontal slider 0..1; returns nothing — drag handled via ids "slider:<key>".
func slider(key: String, r: Rect2, v: float) -> void:
	hit_area("~slider:" + key, r.grow_individual(8, 10, 8, 10))
	var y := r.get_center().y
	draw_rect(Rect2(r.position.x, y - 2, r.size.x, 4), Color(0.12, 0.14, 0.16))
	draw_rect(Rect2(r.position.x, y - 2, r.size.x * v, 4), C_GOLD)
	var kx := r.position.x + r.size.x * v
	var pts := PackedVector2Array([Vector2(kx, y - 9), Vector2(kx + 7, y), Vector2(kx, y + 9), Vector2(kx - 7, y)])
	draw_colored_polygon(pts, C_GOLD_BRIGHT if hover_id == "~slider:" + key else C_GOLD)


func frame(r: Rect2, fill: Color = C_PANEL, border: Color = C_GOLD_DARK, w: float = 1.5) -> void:
	draw_rect(r, fill)
	draw_rect(r, border, false, w)


## Ornate gold frame with corner accents.
func ornate_frame(r: Rect2, col: Color = C_GOLD, w: float = 2.0) -> void:
	draw_rect(r, col, false, w)
	var c := 14.0
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if corner.x <= r.get_center().x else -1.0
		var sy := 1.0 if corner.y <= r.get_center().y else -1.0
		draw_line(corner + Vector2(-3 * sx, -3 * sy), corner + Vector2(c * sx, -3 * sy), col, w + 1.0)
		draw_line(corner + Vector2(-3 * sx, -3 * sy), corner + Vector2(-3 * sx, c * sy), col, w + 1.0)


func text(s: String, p: Vector2, sz: int, col: Color, f: Font = null, outline: bool = false) -> void:
	var font := f if f else f_body
	if outline:
		draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, col.a * 0.8))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func text_right(s: String, p: Vector2, sz: int, col: Color, f: Font = null) -> void:
	var font := f if f else f_body
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
	draw_string(font, p - Vector2(w, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func text_center(s: String, p: Vector2, sz: int, col: Color, f: Font = null, outline: bool = false, spacing: float = 0.0) -> void:
	var font := f if f else f_body
	if spacing > 0.0:
		_text_spaced(s, p, sz, col, font, spacing, outline)
		return
	var ts := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
	var pos := p - Vector2(ts.x * 0.5, -sz * 0.35)
	if outline:
		draw_string_outline(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, maxi(4, sz / 8), Color(0, 0, 0, col.a * 0.8))
	draw_string(font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _text_spaced(s: String, p: Vector2, sz: int, col: Color, font: Font, spacing: float, outline: bool) -> void:
	var widths := []
	var total := 0.0
	for ch in s:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x
		widths.append(w)
		total += w + spacing
	total -= spacing
	var x := p.x - total * 0.5
	for i in s.length():
		var pos := Vector2(x, p.y + sz * 0.35)
		if outline:
			draw_string_outline(font, pos, s[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, maxi(4, sz / 8), Color(0, 0, 0, col.a * 0.8))
		draw_string(font, pos, s[i], HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)
		x += widths[i] + spacing


func wrap_text(s: String, width: float, sz: int, f: Font = null) -> Array:
	var font := f if f else f_body
	var lines := []
	for para in s.split("\n"):
		var cur := ""
		for w in para.split(" "):
			var test := w if cur == "" else cur + " " + w
			if font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > width and cur != "":
				lines.append(cur)
				cur = w
			else:
				cur = test
		lines.append(cur)
	return lines


func text_block(s: String, p: Vector2, width: float, sz: int, col: Color, f: Font = null, line_h: float = 1.35, max_lines: int = 99) -> float:
	var lines := wrap_text(s, width, sz, f)
	var y := p.y
	for i in mini(lines.size(), max_lines):
		text(lines[i], Vector2(p.x, y + sz), sz, col, f)
		y += sz * line_h
	return y


## Draw a texture scaled to cover `r` (center-cropped), with optional focus point (0..1 uv).
func tex_cover(tex: Texture2D, r: Rect2, mod: Color = Color.WHITE, focus: Vector2 = Vector2(0.5, 0.5)) -> void:
	if tex == null:
		draw_rect(r, Color(0.05, 0.07, 0.09))
		return
	var ts := tex.get_size()
	var s := maxf(r.size.x / ts.x, r.size.y / ts.y)
	var src_size := r.size / s
	var src_pos := (ts - src_size) * focus
	src_pos = src_pos.clamp(Vector2.ZERO, ts - src_size)
	draw_texture_rect_region(tex, r, Rect2(src_pos, src_size), mod)


func _vgrad(r: Rect2, top: Color, bottom: Color) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]))


func _hgrad(r: Rect2, left: Color, right: Color) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_polygon(pts, PackedColorArray([left, right, right, left]))


func vignette(vs: Vector2, strength: float = 0.75) -> void:
	_vgrad(Rect2(0, 0, vs.x, vs.y * 0.3), Color(0, 0, 0, strength), Color(0, 0, 0, 0))
	_vgrad(Rect2(0, vs.y * 0.6, vs.x, vs.y * 0.4), Color(0, 0, 0, 0), Color(0, 0, 0, strength))
	_hgrad(Rect2(0, 0, vs.x * 0.25, vs.y), Color(0, 0, 0, strength * 0.8), Color(0, 0, 0, 0))
	_hgrad(Rect2(vs.x * 0.75, 0, vs.x * 0.25, vs.y), Color(0, 0, 0, 0), Color(0, 0, 0, strength * 0.8))


func circle_tex(tex: Texture2D, center: Vector2, r: float, mod: Color = Color.WHITE) -> void:
	if tex == null:
		draw_circle(center, r, Color(0.05, 0.07, 0.09))
		return
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		var d := Vector2(cos(a), sin(a))
		pts.append(center + d * r)
		uvs.append(Vector2(0.5, 0.5) + d * 0.5)
	draw_colored_polygon(pts, mod, uvs, tex)


func icon(tex: Texture2D, r: Rect2, border: Color = C_GOLD_DARK, mod: Color = Color.WHITE) -> void:
	if tex != null:
		draw_texture_rect(tex, r, false, mod)
	else:
		draw_rect(r, Color(0.04, 0.06, 0.08))
	draw_rect(r, border, false, 1.5)


func _draw_tip() -> void:
	var mp := get_local_mouse_position()
	var w := 340.0
	var lines := wrap_text(str(tip.get("body", "")), w - 24, 15)
	var h := 44.0 + lines.size() * 20.0
	var p := mp + Vector2(18, 18)
	if p.x + w > size.x - 8:
		p.x = mp.x - w - 18
	if p.y + h > size.y - 8:
		p.y = size.y - h - 8
	var r := Rect2(p, Vector2(w, h))
	frame(r, Color(0.01, 0.04, 0.06, 0.97), C_GOLD_DARK)
	text(str(tip.get("title", "")), p + Vector2(12, 26), 18, C_GOLD_BRIGHT, f_bold)
	var y := p.y + 50
	for ln in lines:
		text(ln, Vector2(p.x + 12, y), 15, C_TEXT, f_body)
		y += 20.0


# ===================================================================== settings (shared)
const DIFFS := ["Easy", "Normal", "Hard", "Insane"]
var _drag_slider := ""


## Draws the settings block inside r. Ids: "set:diff:N", "set:quick", "set:edge", "set:lock", "set:fs".
func draw_settings(r: Rect2) -> void:
	frame(r, Color(0.01, 0.05, 0.08, 0.95), C_GOLD_DARK)
	text_center("SETTINGS", Vector2(r.get_center().x, r.position.y + 34), 26, C_GOLD_BRIGHT, f_bold, false, 3.0)
	var x := r.position.x + 36
	var y := r.position.y + 80
	var w := r.size.x - 72
	text("Bot difficulty", Vector2(x, y + 18), 17, C_TEXT, f_semi)
	var pw := (w - 220) / 4.0
	for i in 4:
		pill("set:diff:%d" % i, Rect2(x + 220 + i * pw, y, pw - 6, 30), DIFFS[i], int(G.settings.difficulty) == i)
	y += 52
	text("Ability casting", Vector2(x, y + 18), 17, C_TEXT, f_semi)
	var modes := ["Quick", "Indicator", "Normal"]
	var mw := (w - 220) / 3.0
	for i in 3:
		pill("set:cast:%d" % i, Rect2(x + 220 + i * mw, y, mw - 6, 30), modes[i], int(G.settings.get("cast_mode", 0)) == i)
	set_tip("set:cast:0", "Quick cast", "Abilities cast instantly at the cursor when the key is pressed.")
	set_tip("set:cast:1", "Quick cast with indicator", "Hold the key to see the indicator, release to cast.")
	set_tip("set:cast:2", "Normal cast", "Press the key to show the indicator, left-click to cast, right-click to cancel.")
	y += 52
	var toggles := [["set:edge", "Screen edge camera pan", "edge_pan"],
			["set:lock", "Camera locked to champion", "camera_locked"], ["set:fs", "Fullscreen", "fullscreen"],
			["set:dmg", "Show all damage numbers", "show_all_damage_numbers"]]
	for tg in toggles:
		text(tg[1], Vector2(x, y + 18), 17, C_TEXT, f_semi)
		var on: bool = G.settings.get(tg[2], false)
		pill(tg[0] + ":0", Rect2(x + w - 150, y, 72, 28), "On", on, 14)
		pill(tg[0] + ":1", Rect2(x + w - 72, y, 72, 28), "Off", not on, 14)
		y += 42
	for s in [["Master volume", "master_volume"], ["Sound effects", "sfx_volume"], ["Music", "music_volume"]]:
		text(s[0], Vector2(x, y + 18), 17, C_TEXT, f_semi)
		slider(s[1], Rect2(x + 220, y + 6, w - 290, 16), float(G.settings.get(s[1], 0.5)))
		text_right("%d%%" % int(round(float(G.settings.get(s[1], 0.5)) * 100)), Vector2(x + w, y + 20), 16, C_DIM, f_semi)
		y += 42


## Returns true if the action was a settings action (handled).
func handle_settings_action(id: String) -> bool:
	if not id.begins_with("set:"):
		return false
	var parts := id.split(":")
	match parts[1]:
		"diff":
			G.settings.difficulty = int(parts[2])
		"cast":
			G.settings.cast_mode = int(parts[2])
		"edge":
			G.settings.edge_pan = parts[2] == "0"
		"lock":
			G.settings.camera_locked = parts[2] == "0"
		"dmg":
			G.settings.show_all_damage_numbers = parts[2] == "0"
		"fs":
			G.settings.fullscreen = parts[2] == "0"
			G.apply_window_mode()
	G.save_settings()
	return true


func _input(event: InputEvent) -> void:
	# slider dragging (works even when the cursor leaves the rect)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and is_visible_in_tree():
			var h := _hit(get_local_mouse_position())
			if h.begins_with("~slider:"):
				_drag_slider = h.substr(8)
				_apply_slider(get_local_mouse_position())
		elif not event.pressed and _drag_slider != "":
			_drag_slider = ""
			G.save_settings()
			Sfx.ui("click")
	elif event is InputEventMouseMotion and _drag_slider != "":
		_apply_slider(get_local_mouse_position())


func _apply_slider(mp: Vector2) -> void:
	for a in _prev_areas:
		if a[0] == "~slider:" + _drag_slider:
			var r: Rect2 = (a[1] as Rect2).grow_individual(-8, -10, -8, -10)
			G.settings[_drag_slider] = clampf((mp.x - r.position.x) / r.size.x, 0.0, 1.0)
			Sfx.apply_volumes()
			return
