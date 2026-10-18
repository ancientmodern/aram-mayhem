class_name UIScreen
extends Control
## Base for full-screen menu screens (main menu, champion select, loading, end of game, pause).
## Screens draw themselves in draw_screen() and register clickable rects with button()/hit_area();
## input is resolved against the rects registered on the previous frame (immediate-mode GUI).
##
## Visual language = League client (rcp-fe-lol-uikit): colours, type styles, flat-button states/animations and
## sounds are read from the client's own CSS / JS (see docs and tools/lol/extract_client_ui.py). The client UI is
## authored for 1280x720 and scales 1.5x at 1080p, so CSS px are multiplied by K (viewport is 1920x1080 here).

signal action(id: String)

const K := 1.5                ## client CSS px -> viewport px

# ---- League client palette (typekit / uikit CSS)
const C_BG := Color("010a13")
const C_BG2 := Color("091428")
const C_PANEL := Color(0.004, 0.039, 0.075, 0.94)
const C_GOLD := Color("c8aa6e")
const C_GOLD_BRIGHT := Color("f0e6d2")
const C_GOLD_DARK := Color("785a28")
const C_GOLD_MID := Color("c89b3c")
const C_BTN := Color("cdbe91")
const C_TEXT := Color("f0e6d2")
const C_DIM := Color("a09b8c")
const C_GREY := Color("1e2328")
const C_DISABLED := Color("5c5b57")
const C_TEAL := Color("0ac8b9")
const C_RED := Color("e84057")
const C_BLUE := Color("0397ab")

## Type styles: [family, weight, css px, tracking (em), uppercase, default colour]
## Headings are LoL Display (Beaufort) Bold, body is LoL Body (Spiegel) - sizes/letter-spacing from the client's
## `lol-uikit-content-block` h1..h6 / p rules (typekit styles.css); buttons from `.lol-uikit-flat-button`.
const TYPE := {
	"h1": ["beaufort", "Bold", 40, 0.05, true, C_TEXT],
	"h2": ["beaufort", "Bold", 30, 0.05, true, C_TEXT],
	"h3": ["beaufort", "Bold", 24, 0.05, true, C_TEXT],
	"h4": ["beaufort", "Bold", 18, 0.05, true, C_TEXT],
	"h5": ["beaufort", "Bold", 14, 0.075, true, C_TEXT],
	"h6": ["beaufort", "Bold", 12, 0.075, true, C_TEXT],
	"sub": ["beaufort", "Bold", 14, 0.075, true, C_DIM],
	"btn": ["beaufort", "Bold", 14, 0.0714, true, C_BTN],
	"display": ["beaufort", "Heavy", 40, 0.05, true, C_TEXT],
	"body": ["spiegel", "Regular", 12, 0.025, false, C_DIM],
	"body_l": ["spiegel", "Regular", 14, 0.025, false, C_DIM],
	"label": ["spiegel", "SemiBold", 14, 0.025, false, C_TEXT],
	"strong": ["spiegel", "Bold", 14, 0.025, false, C_TEXT],
	"num": ["beaufort", "Bold", 14, 0.0, false, C_TEXT],
}

const KIND_SND := {
	"flat": ["flat_hover", "flat_click"],
	"primary": ["magic_hover", "magic_click"],
	"play": ["play_hover", "play_click"],
	"quit": ["quit_hover", "quit_click"],
	"find": ["find_hover", "find_click"],
	"confirm": ["confirm_hover", "confirm_click"],
	"lockin": ["lockin_hover", "lockin"],
	"reroll": ["reroll_hover", "reroll"],
	"grid": ["grid_hover", "grid_click"],
	"tab": ["hover", "tab"],
	"toggle": ["hover", "toggle"],
	"check": ["hover", "checkbox"],
	"close": ["close_hover", "close_click"],
	"back": ["flat_hover", "back_click"],
	"arrow": ["arrow_hover", "arrow_click"],
	"silent": ["", ""],
}

static var _fv_cache := {}
static var _glow_cache := {}

var t := 0.0
var fade := 0.0               ## 0..1 fade-in
var hover_id := ""
var press_id := ""
var _dt := 0.016
var _areas: Array = []        ## [[id, rect, kind]] registered this frame (later = on top)
var _prev_areas: Array = []
var _st := {}                 ## per-widget animation state {hov, down, hov_t, click_t}
var tip := {}                 ## {title, body} shown near the mouse when hovering
var _tip_next := {}
var _grad := {}               ## id -> {node: Label, key: String, used: bool} gradient-text labels
var _mouse := Vector2(-1000, -1000)   ## last mouse position seen by _gui_input (tooltips follow it)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true


func _process(delta: float) -> void:
	# UI animates in real time even while the match runs in slow motion
	var rd := delta / maxf(Engine.time_scale, 0.001)
	_dt = minf(rd, 0.05)
	t += rd
	fade = minf(1.0, fade + rd * 3.0)
	for s in _st.values():
		if s.click_t >= 0.0:
			s.click_t += rd
			if s.click_t > 1.0:
				s.click_t = -1.0
		if s.hov_t >= 0.0:
			s.hov_t += rd
	queue_redraw()


func _draw() -> void:
	_areas.clear()
	_tip_next = {}
	for g in _grad.values():
		g.used = false
	draw_screen(size)
	tip = _tip_next
	if not tip.is_empty():
		_draw_tip()
	_prev_areas = _areas.duplicate()
	for g in _grad.values():
		if not g.used and g.node.visible:
			g.node.visible = false
	if fade < 1.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 1.0 - fade))


## Override.
func draw_screen(_vs: Vector2) -> void:
	pass


## Override: called with a clicked id. Default re-emits `action`.
func on_action(id: String) -> void:
	action.emit(id)


# ===================================================================== input / hit areas
func _hit(p: Vector2) -> String:
	for i in range(_prev_areas.size() - 1, -1, -1):
		var a: Array = _prev_areas[i]
		if (a[1] as Rect2).has_point(p):
			return a[0]
	return ""


func _kind_of(id: String) -> String:
	for i in range(_prev_areas.size() - 1, -1, -1):
		if _prev_areas[i][0] == id:
			return _prev_areas[i][2]
	return "flat"


## Resolve a kind to [hover sound, click sound]. "hov|clk" gives explicit sound names ("" = silent).
func _kind_sounds(kind: String) -> Array:
	if kind.contains("|"):
		var p := kind.split("|")
		return [p[0], p[1]]
	return KIND_SND.get(kind, KIND_SND.flat)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position
		var h := _hit(event.position)
		if h != hover_id:
			hover_id = h
			if h != "":
				_bs(h).hov_t = 0.0
			if h != "" and not h.begins_with("~"):
				var snd: String = _kind_sounds(_kind_of(h))[0]
				if snd != "":
					Sfx.ui(snd)
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if (h != "" and not h.begins_with("~")) else Control.CURSOR_ARROW
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			press_id = _hit(event.position)
		else:
			var h := _hit(event.position)
			if h != "" and h == press_id and not h.begins_with("~"):
				_bs(h).click_t = 0.0
				var snd: String = _kind_sounds(_kind_of(h))[1]
				if snd != "":
					Sfx.ui(snd)
				on_action(h)
			press_id = ""
		accept_event()


func hit_area(id: String, r: Rect2, kind: String = "flat") -> void:
	_areas.append([id, r, kind])


func is_hover(id: String) -> bool:
	return hover_id == id


func set_tip(id: String, title: String, body: String) -> void:
	if hover_id == id:
		_tip_next = {"title": title, "body": body}


func _bs(id: String) -> Dictionary:
	if not _st.has(id):
		_st[id] = {"hov": 0.0, "down": 0.0, "hov_t": -1.0, "click_t": -1.0}
	return _st[id]


## Smoothly follow a 0/1 target for widget `id` (used by hover/selection fades).
func ease_to(id: String, key: String, target: float, rate: float = 8.0) -> float:
	var s := _bs(id)
	if not s.has(key):
		s[key] = target
	s[key] = move_toward(s[key], target, _dt * rate)
	return s[key]


## 0..1 entrance progress for an element appearing `delay` seconds after the screen opened (eased).
func appear(delay: float, dur: float = 0.45) -> float:
	var k := clampf((t - delay) / dur, 0.0, 1.0)
	return 1.0 - pow(1.0 - k, 3.0)


# ===================================================================== typography
static func font_v(family: String, weight: String, spacing_px: int) -> Font:
	var base := Assets.font(family, weight)
	if spacing_px == 0:
		return base
	var key := "%s|%s|%d" % [family, weight, spacing_px]
	if _fv_cache.has(key):
		return _fv_cache[key]
	var fv := FontVariation.new()
	fv.base_font = base
	fv.spacing_glyph = spacing_px
	_fv_cache[key] = fv
	return fv


## Font for a TYPE style at design-px size `px` (0 = the style's own size).
func style_font(style: String, px: float = 0.0) -> Array:
	var st: Array = TYPE[style]
	var sz := int(round(px if px > 0.0 else float(st[2]) * K))
	var track := int(round(float(st[3]) * sz))
	return [font_v(st[0], st[1], track), sz, track, st[4], st[5]]


## Draw a line of text. p.y is the vertical centre of the line; align 0 left / 1 centre / 2 right (about p.x).
## `col` alpha < 0 keeps the style colour. Returns the drawn width.
func label(s: String, p: Vector2, style: String, align: int = 0, col: Color = Color(0, 0, 0, -1), px: float = 0.0,
		shadow: bool = false, outline: float = 0.0, max_w: float = -1.0) -> float:
	var sf := style_font(style, px)
	var f: Font = sf[0]
	var sz: int = sf[1]
	var track: int = sf[2]
	var c: Color = sf[4] if col.a < 0.0 else col
	var txt := s.to_upper() if sf[3] else s
	var w := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x - track
	if max_w > 0.0 and w > max_w:
		while txt.length() > 1 and f.get_string_size(txt + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x - track > max_w:
			txt = txt.substr(0, txt.length() - 1)
		txt += "…"
		w = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x - track
	var x := p.x - (w * 0.5 if align == 1 else (w if align == 2 else 0.0))
	var y := p.y + (f.get_ascent(sz) - f.get_descent(sz)) * 0.5
	var pos := Vector2(x, y)
	if outline > 0.0:
		draw_string_outline(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, int(outline), Color(0, 0, 0, c.a * 0.85))
	if shadow:
		draw_string(f, pos + Vector2(0, maxf(1.0, sz * 0.06)), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(0, 0, 0, c.a * 0.7))
	draw_string(f, pos, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, c)
	return w


func label_w(s: String, style: String, px: float = 0.0) -> float:
	var sf := style_font(style, px)
	var f: Font = sf[0]
	return f.get_string_size(s.to_upper() if sf[3] else s, HORIZONTAL_ALIGNMENT_LEFT, -1, sf[1]).x - float(sf[2])


## Word-wrapped paragraph; returns the y after the last line. `max_lines` truncates.
func paragraph(s: String, p: Vector2, width: float, style: String, col: Color = Color(0, 0, 0, -1), px: float = 0.0,
		line_h: float = 1.4, max_lines: int = 99) -> float:
	var sf := style_font(style, px)
	var lines := wrap_text(s, width, sf[1], sf[0])
	var y := p.y
	for i in mini(lines.size(), max_lines):
		label(lines[i], Vector2(p.x, y + sf[1] * 0.5), style, 0, col, px)
		y += sf[1] * line_h
	return y


## Gradient (League gold) display text as a real Label with grad_text.gdshader, so glyphs keep full font quality.
## rect = text box (centre-aligned when align == 1). `tint` colours: [top, mid, bottom].
func grad_text(id: String, s: String, rect: Rect2, px: int, weight: String = "Heavy", track_em: float = 0.05, align: int = 1,
		alpha: float = 1.0, shine: float = -1.0, tint: Array = [], outline: int = 0, family: String = "beaufort") -> void:
	var g: Dictionary
	if _grad.has(id):
		g = _grad[id]
	else:
		var lb := Label.new()
		lb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lb.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lb.clip_text = false
		var mat := ShaderMaterial.new()
		mat.shader = load("res://src/ui/menu/grad_text.gdshader")
		lb.material = mat
		add_child(lb)
		g = {"node": lb, "key": "", "used": false}
		_grad[id] = g
	g.used = true
	var lb: Label = g.node
	lb.visible = alpha > 0.01
	lb.modulate = Color(1, 1, 1, alpha * fade)
	var key := "%s|%d|%s|%.3f|%d|%s|%s" % [s, px, weight, track_em, align, str(rect), str(tint)]
	if g.key != key:
		g.key = key
		var ls := LabelSettings.new()
		ls.font = font_v(family, weight, int(round(track_em * px)))
		ls.font_size = px
		ls.font_color = Color.WHITE
		if outline > 0:
			ls.outline_size = outline
			ls.outline_color = Color(0, 0, 0, 0.85)
		lb.label_settings = ls
		lb.text = s.to_upper()
		lb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if align == 1 else (HORIZONTAL_ALIGNMENT_RIGHT if align == 2 else HORIZONTAL_ALIGNMENT_LEFT)
		lb.position = rect.position
		lb.size = rect.size
		var m: ShaderMaterial = lb.material
		var ext := rect.size.y
		m.set_shader_parameter("y0", ext * 0.18)
		m.set_shader_parameter("y1", ext * 0.86)
		m.set_shader_parameter("x0", 0.0)
		m.set_shader_parameter("x1", rect.size.x)
		var tc: Array = tint if not tint.is_empty() else [Color("fdf7e5"), Color("f0e6d2"), Color("c8aa6e")]
		m.set_shader_parameter("top", tc[0])
		m.set_shader_parameter("mid", tc[1])
		m.set_shader_parameter("bottom", tc[2])
	(lb.material as ShaderMaterial).set_shader_parameter("shine", shine)


func wrap_text(s: String, width: float, sz: int, f: Font) -> Array:
	var lines := []
	for para in s.split("\n"):
		var cur := ""
		for w in para.split(" "):
			var test := w if cur == "" else cur + " " + w
			if f.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > width and cur != "":
				lines.append(cur)
				cur = w
			else:
				cur = test
		lines.append(cur)
	return lines


# ---- legacy helpers (kept for call sites that still pass explicit fonts)
func text(s: String, p: Vector2, sz: int, col: Color, f: Font = null, outline: bool = false) -> void:
	var font := f if f else Assets.font("spiegel", "Regular")
	if outline:
		draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, col.a * 0.8))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


# ===================================================================== drawing primitives
func tex(path: String) -> Texture2D:
	return Assets.tex(path)


func ctex(rel: String) -> Texture2D:
	return Assets.tex("res://assets/ui/client/" + rel)


## Vertical multi-stop gradient. stops = [[t 0(top)..1(bottom), Color], ...] sorted by t.
func vgrad_stops(r: Rect2, stops: Array) -> void:
	for i in stops.size() - 1:
		var a: Array = stops[i]
		var b: Array = stops[i + 1]
		var y0: float = r.position.y + r.size.y * a[0]
		var y1: float = r.position.y + r.size.y * b[0]
		if y1 <= y0:
			continue
		var pts := PackedVector2Array([Vector2(r.position.x, y0), Vector2(r.end.x, y0), Vector2(r.end.x, y1), Vector2(r.position.x, y1)])
		draw_polygon(pts, PackedColorArray([a[1], a[1], b[1], b[1]]))


func _vgrad(r: Rect2, top: Color, bottom: Color) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_polygon(pts, PackedColorArray([top, top, bottom, bottom]))


func _hgrad(r: Rect2, left: Color, right: Color) -> void:
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
	draw_polygon(pts, PackedColorArray([left, right, right, left]))


## Gradient border (CSS border-image). stops are bottom->top like `linear-gradient(to top, ...)`: [[0..1, Color]].
func grad_border(r: Rect2, w: float, stops: Array, alpha: float = 1.0) -> void:
	var top_stops := []
	for i in range(stops.size() - 1, -1, -1):
		var c: Color = stops[i][1]
		top_stops.append([1.0 - float(stops[i][0]), Color(c.r, c.g, c.b, c.a * alpha)])
	var c_top: Color = top_stops[0][1]
	var c_bot: Color = top_stops[top_stops.size() - 1][1]
	draw_rect(Rect2(r.position, Vector2(r.size.x, w)), c_top)
	draw_rect(Rect2(Vector2(r.position.x, r.end.y - w), Vector2(r.size.x, w)), c_bot)
	var inner_h := r.size.y - w * 2.0
	if inner_h <= 0.0:
		return
	# side strips span the full height so the gradient lines up with the top/bottom strips
	vgrad_stops(Rect2(r.position, Vector2(w, r.size.y)), top_stops)
	vgrad_stops(Rect2(Vector2(r.end.x - w, r.position.y), Vector2(w, r.size.y)), top_stops)


## Soft outer glow (CSS box-shadow blur), drawn as a 9-slice around r.
func glow(r: Rect2, col: Color, spread: int = 10, fill: bool = false) -> void:
	if col.a <= 0.004:
		return
	var sb := _glow_style(spread, fill)
	sb.modulate_color = col
	draw_style_box(sb, r.grow(spread))


static func _glow_style(spread: int, fill: bool = false) -> StyleBoxTexture:
	var ck := spread + (100000 if fill else 0)
	if _glow_cache.has(ck):
		return _glow_cache[ck]
	var m := spread
	var n := m * 2 + 4
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var dx := maxf(maxf(float(m - x), float(x - (n - m - 1))), 0.0)
			var dy := maxf(maxf(float(m - y), float(y - (n - m - 1))), 0.0)
			var d := Vector2(dx, dy).length() / float(m)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (3.0 - 2.0 * a)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var sb := StyleBoxTexture.new()
	sb.texture = ImageTexture.create_from_image(img)
	sb.texture_margin_left = m
	sb.texture_margin_right = m
	sb.texture_margin_top = m
	sb.texture_margin_bottom = m
	sb.draw_center = fill
	_glow_cache[ck] = sb
	return sb


func frame(r: Rect2, fill: Color = C_PANEL, border: Color = C_GOLD_DARK, w: float = 1.5) -> void:
	draw_rect(r, fill)
	draw_rect(r, border, false, w)


## League dialog / panel: deep-blue gradient fill, gold gradient border, thin inner highlight and soft drop glow.
func panel(r: Rect2, alpha: float = 0.96, border_w: float = 3.0, glow_dark: bool = true) -> void:
	if glow_dark:
		glow(r, Color(0, 0, 0, 0.55 * alpha), 22)
	vgrad_stops(r, [[0.0, Color(0.035, 0.078, 0.157, alpha)], [0.35, Color(0.004, 0.039, 0.075, alpha)], [1.0, Color(0.004, 0.039, 0.075, alpha)]])
	grad_border(r, border_w, [[0.0, Color("463714")], [0.5, Color("785a28")], [1.0, Color("c8aa6e")]])
	draw_rect(r.grow(-border_w - 3.0), Color(0.78, 0.67, 0.43, 0.10), false, 1.0)


## Gold ornate frame with corner accents (champion cards / portraits).
func ornate_frame(r: Rect2, col: Color = C_GOLD, w: float = 2.0) -> void:
	draw_rect(r, col, false, w)
	var c := 14.0
	for corner in [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]:
		var sx := 1.0 if corner.x <= r.get_center().x else -1.0
		var sy := 1.0 if corner.y <= r.get_center().y else -1.0
		draw_line(corner + Vector2(-3 * sx, -3 * sy), corner + Vector2(c * sx, -3 * sy), col, w + 1.0)
		draw_line(corner + Vector2(-3 * sx, -3 * sy), corner + Vector2(-3 * sx, c * sy), col, w + 1.0)


## Gold divider with a centre diamond (League title divider).
func divider(cx: float, y: float, w: float, alpha: float = 1.0) -> void:
	var a := Color(0.78, 0.67, 0.43, 0.0)
	var b := Color(0.78, 0.67, 0.43, 0.85 * alpha)
	_hgrad(Rect2(cx - w * 0.5, y - 0.5, w * 0.5 - 8, 1.5), a, b)
	_hgrad(Rect2(cx + 8, y - 0.5, w * 0.5 - 8, 1.5), b, a)
	draw_colored_polygon(PackedVector2Array([Vector2(cx - 5, y), Vector2(cx, y - 5), Vector2(cx + 5, y), Vector2(cx, y + 5)]), Color(0.78, 0.67, 0.43, alpha))
	draw_colored_polygon(PackedVector2Array([Vector2(cx - 2.5, y), Vector2(cx, y - 2.5), Vector2(cx + 2.5, y), Vector2(cx, y + 2.5)]), Color(0.004, 0.039, 0.075, alpha))


## Draw a texture scaled to cover `r` (center-cropped), with optional focus point (0..1 uv).
func tex_cover(tx: Texture2D, r: Rect2, mod: Color = Color.WHITE, focus: Vector2 = Vector2(0.5, 0.5)) -> void:
	if tx == null:
		draw_rect(r, Color(0.05, 0.07, 0.09))
		return
	var ts := tx.get_size()
	var s := maxf(r.size.x / ts.x, r.size.y / ts.y)
	var src_size := r.size / s
	var src_pos := (ts - src_size) * focus
	src_pos = src_pos.clamp(Vector2.ZERO, ts - src_size)
	draw_texture_rect_region(tx, r, Rect2(src_pos, src_size), mod)


func vignette(vs: Vector2, strength: float = 0.75) -> void:
	_vgrad(Rect2(0, 0, vs.x, vs.y * 0.3), Color(0, 0, 0, strength), Color(0, 0, 0, 0))
	_vgrad(Rect2(0, vs.y * 0.6, vs.x, vs.y * 0.4), Color(0, 0, 0, 0), Color(0, 0, 0, strength))
	_hgrad(Rect2(0, 0, vs.x * 0.25, vs.y), Color(0, 0, 0, strength * 0.8), Color(0, 0, 0, 0))
	_hgrad(Rect2(vs.x * 0.75, 0, vs.x * 0.25, vs.y), Color(0, 0, 0, 0), Color(0, 0, 0, strength * 0.8))


## Slowly drifting client smoke layer (League's parallax-smoke art) over a backdrop.
func smoke(vs: Vector2, alpha: float = 0.16, speed: float = 9.0) -> void:
	var tx := ctex("lol-uikit/images/parallax-smoke-background.png")
	if tx == null:
		return
	var h := vs.y * 1.1
	var w := h * 16.0 / 9.0
	var off := fmod(t * speed, w)
	var m := Color(0.55, 0.75, 0.9, alpha)
	for i in 3:
		draw_texture_rect(tx, Rect2(-off + (i - 0) * w - w * 0.1, -vs.y * 0.05, w, h), false, m)


func circle_tex(tx: Texture2D, center: Vector2, r: float, mod: Color = Color.WHITE) -> void:
	if tx == null:
		draw_circle(center, r, Color(0.05, 0.07, 0.09))
		return
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 48:
		var a := TAU * i / 48.0
		var d := Vector2(cos(a), sin(a))
		pts.append(center + d * r)
		uvs.append(Vector2(0.5, 0.5) + d * 0.5)
	draw_colored_polygon(pts, mod, uvs, tx)


## Square icon with a gold gradient frame.
func icon(tx: Texture2D, r: Rect2, border: Color = C_GOLD_DARK, mod: Color = Color.WHITE) -> void:
	if tx != null:
		draw_texture_rect(tx, r, false, mod)
	else:
		draw_rect(r, Color(0.04, 0.06, 0.08))
	if border.is_equal_approx(C_GOLD_DARK):
		grad_border(r, 1.5, [[0.0, Color("463714")], [1.0, Color("785a28")]])
	elif border.is_equal_approx(C_GOLD):
		grad_border(r, 2.0, [[0.0, Color("785a28")], [0.55, Color("c89b3c")], [1.0, Color("f0e6d2")]])
	else:
		draw_rect(r, border, false, 1.5)


# ===================================================================== widgets
## League flat button (`lol-uikit-flat-button`): 2px gradient border, #1e2328 body, warm hover gradient + glow
## pulse, 94%->100% click scale, sheen sweep and corner flare, disabled grey. style: "normal" / "primary" (brown
## gold) / "danger". `sz` overrides the text px (viewport px).
func button(id: String, r: Rect2, label_text: String, style: String = "normal", enabled: bool = true, sz: int = 0, kind: String = "flat") -> void:
	if enabled:
		hit_area(id, r, kind if kind != "flat" or style != "primary" else "primary")
	var s := _bs(id)
	var hov := enabled and hover_id == id
	var down := hov and press_id == id
	s.hov = move_toward(s.hov, 1.0 if hov else 0.0, _dt * 6.0)
	var ct: float = s.click_t
	# click: scale .94 -> 1 over 130 ms
	var rr := r
	if ct >= 0.0 and ct < 0.13:
		var k := lerpf(0.94, 1.0, ct / 0.13)
		rr = Rect2(r.get_center() - r.size * k * 0.5, r.size * k)
	if down:
		rr = Rect2(r.get_center() - r.size * 0.985 * 0.5, r.size * 0.985)
	var bw := 2.0 * K
	# outer 1px shadow ring
	draw_rect(rr.grow(1.5), Color(0.004, 0.039, 0.075, 0.95))
	var danger := style == "danger"
	# hover glow pulse (600 ms): rgba(240,230,216,.5) -> .3 -> 0
	var pulse := 0.0
	if s.hov_t >= 0.0 and s.hov_t < 0.6 and hov:
		var k2: float = s.hov_t / 0.6
		pulse = lerpf(0.5, 0.3, k2 * 2.0) if k2 < 0.5 else lerpf(0.3, 0.0, (k2 - 0.5) * 2.0)
	if ct >= 0.0 and ct < 0.6:
		var k3 := ct / 0.6
		pulse = maxf(pulse, lerpf(0.5, 0.3, k3 * 2.0) if k3 < 0.5 else lerpf(0.3, 0.0, (k3 - 0.5) * 2.0))
	if pulse > 0.0 and enabled:
		glow(rr, Color(0.94, 0.9, 0.85, pulse), 12)
	# body
	if not enabled:
		draw_rect(rr, C_GREY)
		draw_rect(rr, C_DISABLED, false, bw)
	else:
		if style == "primary":
			vgrad_stops(rr, [[0.0, Color("5a401f")], [1.0, Color("332717")]])
			if s.hov > 0.0:
				vgrad_stops(rr, [[0.0, Color(0.376, 0.271, 0.133, s.hov)], [1.0, Color(0.518, 0.404, 0.271, s.hov)]])
		elif danger:
			vgrad_stops(rr, [[0.0, Color("2a1316")], [1.0, Color("1a0c0e")]])
			if s.hov > 0.0:
				vgrad_stops(rr, [[0.0, Color(0.42, 0.12, 0.14, s.hov * 0.8)], [1.0, Color(0.55, 0.16, 0.18, s.hov * 0.8)]])
		else:
			draw_rect(rr, C_GREY)
			if s.hov > 0.0:
				vgrad_stops(rr, [[0.0, Color(0.118, 0.137, 0.165, s.hov)], [0.4, Color(0.118, 0.137, 0.165, s.hov)], [1.0, Color(0.463, 0.38, 0.2, 0.55 * s.hov)]])
		if down:
			draw_rect(rr, Color(0, 0, 0, 0.45))
		# border: idle gold gradient, hover brighter gradient cross-faded, down dark
		var idle := [[0.0, Color("785b28")], [0.55, Color("c89c3c")], [0.71, Color("c8a355")], [1.0, Color("c8aa6e")]]
		if danger:
			idle = [[0.0, Color("6b2a2c")], [0.55, Color("a8403f")], [1.0, Color("d9645e")]]
		if down:
			grad_border(rr, bw, [[0.0, Color("694f27")], [1.0, Color("463817")]])
		else:
			grad_border(rr, bw, idle)
			if s.hov > 0.0:
				var hb := [[0.0, Color("c89c3c")], [0.5, Color("dcc188")], [0.71, Color("e1c998")], [1.0, Color("f0e6d8")]]
				if danger:
					hb = [[0.0, Color("a8403f")], [0.5, Color("e07a70")], [1.0, Color("ffb4a8")]]
				grad_border(rr, bw, hb, s.hov)
		# click sheen sweep (330 ms) + corner flares (400 ms)
		if ct >= 0.0 and ct < 0.33:
			var k4 := ct / 0.33
			var band_h := rr.size.y * 1.5
			var top := rr.position.y - rr.size.y + (rr.size.y * 2.0) * k4
			var a0 := clampf(top, rr.position.y, rr.end.y)
			var a1 := clampf(top + band_h, rr.position.y, rr.end.y)
			if a1 > a0:
				var peak := top + band_h * 0.92
				var segs := [[a0, 0.0], [clampf(peak, a0, a1), 0.15], [a1, 0.0]]
				for i in 2:
					var ya: float = segs[i][0]
					var yb: float = segs[i + 1][0]
					if yb > ya:
						var ca := Color(1, 1, 1, _interp_sheen(ya, top, band_h))
						var cb := Color(1, 1, 1, _interp_sheen(yb, top, band_h))
						draw_polygon(PackedVector2Array([Vector2(rr.position.x, ya), Vector2(rr.end.x, ya), Vector2(rr.end.x, yb), Vector2(rr.position.x, yb)]), PackedColorArray([ca, ca, cb, cb]))
		if ct >= 0.0 and ct < 0.4:
			var fa := 0.6 * sin(clampf(ct / 0.4, 0.0, 1.0) * PI)
			var sh := ctex("lol-uikit/images/sheen.png")
			if sh != null and fa > 0.0:
				var sz2 := Vector2(48, 48) * K
				draw_texture_rect(sh, Rect2(rr.position - sz2 * 0.5, sz2), false, Color(1, 1, 1, fa))
				draw_texture_rect(sh, Rect2(rr.end - sz2 * 0.5, sz2), false, Color(1, 1, 1, fa * 0.8))
	# label
	var tc := C_BTN
	if not enabled:
		tc = C_DISABLED
	else:
		tc = C_BTN.lerp(C_TEXT, s.hov)
		if danger:
			tc = Color("ffd9d2").lerp(Color.WHITE, s.hov)
		if down:
			tc = C_DISABLED
		elif ct >= 0.0 and ct < 0.2:
			tc = Color("e4e1d8")
	var px := float(sz) if sz > 0 else 0.0
	if pulse > 0.0 and enabled:
		label(label_text, rr.get_center(), "btn", 1, Color(0.94, 0.9, 0.85, pulse * 0.5), px + 1.0 if px > 0.0 else 0.0)
	label(label_text, rr.get_center(), "btn", 1, tc, px)


func _interp_sheen(y: float, top: float, band_h: float) -> float:
	var k := (y - top) / band_h
	var peak := 0.92
	if k <= peak:
		return 0.15 * clampf(k / peak, 0.0, 1.0)
	return 0.15 * clampf((1.0 - k) / (1.0 - peak), 0.0, 1.0)


## League's blue "find match" trapezoid button (lol-parties art) used for the main call to action.
func find_button(id: String, r: Rect2, label_text: String, enabled: bool = true, kind: String = "play", px: float = 0.0) -> void:
	if enabled:
		hit_area(id, r, kind)
	var s := _bs(id)
	var hov := enabled and hover_id == id
	var down := hov and press_id == id
	s.hov = move_toward(s.hov, 1.0 if hov else 0.0, _dt * 6.0)
	var base := ctex("lol-parties/button-find-match.png")
	var over := ctex("lol-parties/button-find-match-over.png")
	var dn := ctex("lol-parties/button-find-match-down.png")
	var dis := ctex("lol-parties/button-find-match-disabled.png")
	var rr := r
	var ct: float = s.click_t
	if ct >= 0.0 and ct < 0.13:
		var k := lerpf(0.95, 1.0, ct / 0.13)
		rr = Rect2(r.get_center() - r.size * k * 0.5, r.size * k)
	if not enabled:
		draw_texture_rect(dis, rr, false)
	elif down:
		draw_texture_rect(dn, rr, false)
	else:
		draw_texture_rect(base, rr, false)
		if s.hov > 0.0:
			draw_texture_rect(over, rr, false, Color(1, 1, 1, s.hov))
	var tc := Color("cdfafa").lerp(Color.WHITE, s.hov) if enabled else Color("5c5b57")
	if down:
		tc = Color("7fb3b8")
	label(label_text, rr.get_center() + Vector2(0, -rr.size.y * 0.04), "btn", 1, tc, px if px > 0.0 else rr.size.y * 0.3, true)


## Settings-style radio option (gold ring + dot). Returns nothing; register id with hit_area.
func radio(id: String, r: Rect2, label_text: String, selected: bool, kind: String = "toggle", px: float = 19.0) -> void:
	hit_area(id, r, kind)
	var hov := hover_id == id
	var a := ease_to(id, "sel", 1.0 if selected else 0.0, 10.0)
	var h := ease_to(id, "h", 1.0 if hov else 0.0, 10.0)
	var cy := r.get_center().y
	var rad := 8.0 * K * 0.8
	var c := Vector2(r.position.x + rad + 2, cy)
	var ring := C_GOLD_DARK.lerp(C_GOLD, maxf(a, h))
	draw_circle(c, rad, Color(0.004, 0.039, 0.075, 0.9))
	draw_arc(c, rad, 0, TAU, 40, ring, 2.0, true)
	if a > 0.0:
		draw_circle(c, (rad - 4.5) * a, Color(C_GOLD_BRIGHT.r, C_GOLD_BRIGHT.g, C_GOLD_BRIGHT.b, a))
		glow(Rect2(c - Vector2(2, 2), Vector2(4, 4)), Color(0.94, 0.9, 0.7, 0.18 * a), 8)
	label(label_text, Vector2(c.x + rad + 10, cy), "label", 0, C_TEXT.lerp(C_DIM, 1.0 - maxf(a, h)) if not selected else C_GOLD_BRIGHT, px)


## A row of radio options spread across r, each cell sized to its label; ids are prefix + index.
func radio_row(prefix: String, r: Rect2, labels: Array, sel: int, px: float = 19.0) -> void:
	var widths := []
	var total := 0.0
	for l in labels:
		var wd := label_w(str(l), "label", px) + 8.0 * K * 0.8 * 2.0 + 14.0
		widths.append(wd)
		total += wd
	var gap := maxf((r.size.x - total) / maxf(labels.size() - 1, 1), 8.0)
	var x := r.position.x
	for i in labels.size():
		radio("%s%d" % [prefix, i], Rect2(x, r.position.y, widths[i], r.size.y), str(labels[i]), sel == i, "toggle", px)
		x += widths[i] + gap


## League checkbox (uikit checkbox sprite sheet). r = whole row; label drawn to the right of the box.
func checkbox(id: String, r: Rect2, label_text: String, on: bool) -> void:
	hit_area(id, r, "check")
	var hov := hover_id == id
	var h := ease_to(id, "h", 1.0 if hov else 0.0, 10.0)
	var sheet := ctex("lol-uikit/images/checkbox-spritesheet.png")
	var bs := 14.0 * K * 1.1
	var br := Rect2(r.position.x, r.get_center().y - bs * 0.5, bs, bs)
	if sheet != null:
		# frames (14px each): 0 off, 1 off-hover, 2 on, 3 on-hover
		var fr := (2 if on else 0) + (1 if hov else 0)
		draw_texture_rect_region(sheet, br, Rect2(0, fr * 14, 14, 14))
	else:
		draw_rect(br, C_GREY)
		draw_rect(br, C_GOLD, false, 2.0)
	if hov:
		glow(br, Color(0.94, 0.9, 0.7, 0.14), 8)
	label(label_text, Vector2(br.end.x + 14, r.get_center().y), "label", 0, C_TEXT.lerp(C_GOLD_BRIGHT, h), 20.0)


## Horizontal slider 0..1 with the client's diamond handle; drag handled by _input via ids "~slider:<key>".
func slider(key: String, r: Rect2, v: float) -> void:
	var sid := "~slider:" + key
	hit_area(sid, r.grow_individual(14, 14, 14, 14), "silent")
	var y := r.get_center().y
	var hov := hover_id == sid or _drag_slider == key
	var h := ease_to(sid, "h", 1.0 if hov else 0.0, 10.0)
	var gr := Rect2(r.position.x, y - 3.0, r.size.x, 6.0)
	draw_rect(gr.grow(1.5), Color(0.004, 0.039, 0.075, 0.95))
	draw_rect(gr, Color("1e2328"))
	draw_rect(gr, Color("463714"), false, 1.0)
	var fr := Rect2(gr.position, Vector2(gr.size.x * v, gr.size.y))
	if fr.size.x > 1.0:
		_hgrad(fr, C_GOLD_DARK, C_GOLD.lerp(C_GOLD_BRIGHT, h * 0.5))
	var kx := r.position.x + r.size.x * v
	var sprite := ctex("lol-uikit/images/slider-btn.png")
	var ks := 17.0 * K
	if sprite != null:
		var fi := 2 if (_drag_slider == key) else (1 if hov else 0)
		var kr := Rect2(kx - ks * 0.5, y - ks * 0.5, ks, ks)
		if hov:
			glow(kr.grow(-6), Color(0.94, 0.85, 0.55, 0.22), 10)
		draw_texture_rect_region(sprite, kr, Rect2(0, fi * 120, 120, 120))
	else:
		draw_circle(Vector2(kx, y), 8, C_GOLD)


## Left-nav tab row (settings categories).
func nav_tab(id: String, r: Rect2, label_text: String, selected: bool) -> void:
	hit_area(id, r, "tab")
	var hov := hover_id == id
	var a := ease_to(id, "sel", 1.0 if selected else 0.0, 9.0)
	var h := ease_to(id, "h", 1.0 if hov else 0.0, 10.0)
	if a > 0.0 or h > 0.0:
		_hgrad(r, Color(0.78, 0.67, 0.43, 0.20 * a + 0.07 * h), Color(0.78, 0.67, 0.43, 0.0))
	if a > 0.0:
		draw_rect(Rect2(r.position.x, r.position.y + 6, 3, r.size.y - 12), Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, a))
	label(label_text, Vector2(r.position.x + 22, r.get_center().y), "h5", 0, C_DIM.lerp(C_TEXT, maxf(a, h * 0.8)), 20.0)


## Round close / icon button using the client's circular frame art. Returns nothing.
func close_button(id: String, r: Rect2) -> void:
	hit_area(id, r, "close")
	var hov := hover_id == id
	var down := hov and press_id == id
	var tx := ctex("lol-parties/button-x-down.png") if down else (ctex("lol-parties/button-x-over.png") if hov else ctex("lol-parties/button-x.png"))
	if tx != null:
		draw_texture_rect(tx, r, false)


func _draw_tip() -> void:
	var mp := _mouse
	var w := 400.0
	var sfb := style_font("body_l", 19.0)
	var lines := wrap_text(str(tip.get("body", "")), w - 36, sfb[1], sfb[0])
	var h := 70.0 + lines.size() * 27.0 if str(tip.get("body", "")) != "" else 56.0
	var p := mp + Vector2(22, 22)
	if p.x + w > size.x - 8:
		p.x = mp.x - w - 22
	if p.y + h > size.y - 8:
		p.y = size.y - h - 8
	var r := Rect2(p, Vector2(w, h))
	glow(r, Color(0, 0, 0, 0.5), 14)
	draw_rect(r, Color(0.004, 0.039, 0.075, 0.97))
	grad_border(r, 2.0, [[0.0, Color("463714")], [1.0, Color("c8aa6e")]])
	label(str(tip.get("title", "")), p + Vector2(18, 30), "h5", 0, C_GOLD_BRIGHT, 21.0)
	var y := p.y + 56
	for ln in lines:
		label(ln, Vector2(p.x + 18, y + 11), "body_l", 0, Color("cdbe91"), 19.0)
		y += 27.0


# ===================================================================== settings (shared)
const DIFFS := ["Easy", "Normal", "Hard", "Insane"]
const SET_TABS := ["Gameplay", "Video", "Sound"]
var _drag_slider := ""
var _slider_last := -1.0
var settings_tab := 0


## Draws the League-style settings window inside r. Ids: "set:tab:N", "set:diff:N", "set:cast:N", "set:<key>:0|1"
## (0 = turn on), "~slider:<key>", plus the screen's own "settings_back".
func draw_settings(r: Rect2) -> void:
	panel(r, 0.97)
	label("Settings", Vector2(r.get_center().x, r.position.y + 54), "h2", 1, C_GOLD_BRIGHT, 40.0)
	divider(r.get_center().x, r.position.y + 96, r.size.x * 0.5)
	# left navigation
	var nx := r.position.x + 36
	var ny := r.position.y + 132
	for i in SET_TABS.size():
		nav_tab("set:tab:%d" % i, Rect2(nx, ny + i * 62, 250, 56), SET_TABS[i], settings_tab == i)
	_vgrad(Rect2(r.position.x + 310, ny, 1.5, r.size.y - 270), Color(0.78, 0.67, 0.43, 0.5), Color(0.78, 0.67, 0.43, 0.0))
	var x := r.position.x + 360
	var w := r.size.x - 360 - 50
	var y := ny + 6
	var row := 62.0
	match settings_tab:
		0:
			label("Bot difficulty", Vector2(x, y + 22), "label", 0, C_TEXT, 21.0)
			radio_row("set:diff:", Rect2(x + 230, y, w - 230, 44), DIFFS, int(G.settings.difficulty), 20.0)
			y += row
			label("Ability casting", Vector2(x, y + 22), "label", 0, C_TEXT, 21.0)
			var modes := ["Quick", "Indicator", "Normal"]
			radio_row("set:cast:", Rect2(x + 230, y, w - 230, 44), modes, int(G.settings.get("cast_mode", 0)), 20.0)
			set_tip("set:cast:0", "Quick cast", "Abilities cast instantly at the cursor when the key is pressed.")
			set_tip("set:cast:1", "Quick cast with indicator", "Hold the key to see the indicator, release to cast.")
			set_tip("set:cast:2", "Normal cast", "Press the key to show the indicator, left-click to cast, right-click to cancel.")
			y += row + 8
			for tg in [["set:edge", "Screen edge camera pan", "edge_pan", false], ["set:lock", "Camera locked to champion", "camera_locked", false],
					["set:dmg", "Show all damage numbers", "show_all_damage_numbers", false]]:
				_setting_check(tg, x, y, w)
				y += 54
		1:
			for tg in [["set:fs", "Fullscreen", "fullscreen", false], ["set:vsync", "Vertical sync (cap to monitor refresh)", "vsync", true],
					["set:cb", "Colorblind mode", "colorblind", false]]:
				_setting_check(tg, x, y, w)
				y += 54
		2:
			for s in [["Master volume", "master_volume"], ["Sound effects", "sfx_volume"], ["Music", "music_volume"]]:
				label(s[0], Vector2(x, y + 20), "label", 0, C_TEXT, 21.0)
				var v := float(G.settings.get(s[1], 0.5))
				slider(s[1], Rect2(x + 250, y + 10, w - 360, 20), v)
				label("%d%%" % int(round(v * 100)), Vector2(x + w, y + 20), "label", 2, C_DIM, 20.0)
				y += row


func _setting_check(tg: Array, x: float, y: float, w: float) -> void:
	var on: bool = G.settings.get(tg[2], tg[3])
	# id flips the value on click ("0" = turn on)
	checkbox("%s:%d" % [tg[0], 1 if on else 0], Rect2(x, y, w, 40), tg[1], on)


## Returns true if the action was a settings action (handled).
func handle_settings_action(id: String) -> bool:
	if not id.begins_with("set:"):
		return false
	var parts := id.split(":")
	match parts[1]:
		"tab":
			settings_tab = int(parts[2])
			return true
		"diff":
			G.settings.difficulty = int(parts[2])
		"cast":
			G.settings.cast_mode = int(parts[2])
		"edge":
			G.settings.edge_pan = parts[2] == "0"
		"lock":
			G.settings.camera_locked = parts[2] == "0"
			var rig = G.match.get("camera_rig") if G.match != null else null
			if rig != null:
				rig.locked = G.settings.camera_locked   # applies immediately from the pause menu
		"dmg":
			G.settings.show_all_damage_numbers = parts[2] == "0"
		"fs":
			G.settings.fullscreen = parts[2] == "0"
			G.apply_window_mode()
		"vsync":
			G.settings.vsync = parts[2] == "0"
			G.apply_window_mode()
		"cb":
			G.settings.colorblind = parts[2] == "0"
	G.save_settings()
	return true


func _input(event: InputEvent) -> void:
	# slider dragging (works even when the cursor leaves the rect)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and is_visible_in_tree():
			var h := _hit(event.position)
			if h.begins_with("~slider:"):
				_drag_slider = h.substr(8)
				_slider_last = -1.0
				Sfx.ui("slide")
				_apply_slider(event.position)
		elif not event.pressed and _drag_slider != "":
			_drag_slider = ""
			G.save_settings()
			Sfx.ui("slide_release")
	elif event is InputEventMouseMotion and _drag_slider != "":
		_apply_slider(event.position)


func _apply_slider(mp: Vector2) -> void:
	for a in _prev_areas:
		if a[0] == "~slider:" + _drag_slider:
			var r: Rect2 = (a[1] as Rect2).grow_individual(-14, -14, -14, -14)
			var v := clampf((mp.x - r.position.x) / r.size.x, 0.0, 1.0)
			G.settings[_drag_slider] = v
			Sfx.apply_volumes()
			# a soft tick every 5% so dragging has audible feedback (League's volume bar click)
			var step := floorf(v * 20.0)
			if step != _slider_last:
				if _slider_last >= 0.0:
					Sfx.ui("slide_tick", -3.0)
				_slider_last = step
			return
