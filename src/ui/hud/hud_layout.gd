class_name HudLayout
extends RefCounted
## League's in-game HUD layout (positions, sizes, anchors and atlas UVs), read from
## assets/ui/hud/layout.json, plus League's font styles (assets/ui/hud/fonts.json). Both are extracted from
## UI.wad.client by tools/lol/extract_hud.py.
##
## League lays every element out in a source resolution (mostly 1600x1200) around an anchor point:
##   screen_pos = anchor * screen + (pos - anchor * src) * scale,  scale = screen_h / src_h * hud_scale
## Elements flagged "g" (minimap, top header) ignore the global HUD scale (the minimap has its own scale).
##
## HUD scale: League's game.cfg [HUD] GlobalScale (0..1, the in-game "HUD Scale" slider / 100) and MinimapScale.
## The engine's slider -> scale curve is code-side (HudScaleSettingsData min/max are not in the shipped bins), so
## GlobalScale is mapped linearly onto [MIN_GLOBAL_SCALE, 1]; at 1 every atlas texel maps 1:1 on a 1200p screen.

const LAYOUT_PATH := "res://assets/ui/hud/layout.json"
const FONTS_PATH := "res://assets/ui/hud/fonts.json"
const TEX_DIR := "res://assets/ui/hud/tex/"
const MIN_GLOBAL_SCALE := 0.65
const FONT_DEFAULT_SCREEN_H := 1080.0   ## FontResolution.screenHeight default

## League settings (game.cfg [HUD]); defaults match the player's own League config (GlobalScale=0.6).
static var global_scale_setting := 0.6
static var minimap_scale_setting := 1.0

static var _data := {}
static var _fonts := {}
static var _tex := {}
static var _style_cache := {}
static var _font_files := {}

var vs := Vector2(1280, 720)
var hud_scale := 1.0
var mm_scale := 1.0
var _rc := {}           ## key -> Rect2 (offset-free rects, rebuilt when the viewport / scale changes)
var _fx := {}           ## key -> {t, uv Rect2, n, per_row, fps, rc}


static func data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(LAYOUT_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
		if d is Dictionary:
			_data = d
	return _data


static func fonts() -> Dictionary:
	if _fonts.is_empty() and FileAccess.file_exists(FONTS_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(FONTS_PATH))
		if d is Dictionary:
			_fonts = d
	return _fonts


static func tex(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name]
	var t: Texture2D = null
	var p := TEX_DIR + name + ".png"
	if ResourceLoader.exists(p):
		t = load(p)
	_tex[name] = t
	return t


static func scale_for_setting(gs: float) -> float:
	return lerpf(MIN_GLOBAL_SCALE, 1.0, clampf(gs, 0.0, 1.0))


## Call at the start of every draw pass; cheap when nothing changed.
func begin(p_vs: Vector2) -> void:
	var hs := scale_for_setting(global_scale_setting)
	var ms := minimap_scale_setting
	if p_vs != vs or hs != hud_scale or ms != mm_scale:
		vs = p_vs
		hud_scale = hs
		mm_scale = ms
		_rc.clear()
		_fx.clear()


func has(key: String) -> bool:
	return data().has(key)


func e(key: String) -> Dictionary:
	return data().get(key, {})


## Scale factor (screen px per source px) of an element.
func scale_of(el: Dictionary) -> float:
	var src: Array = el.get("src", [1600, 1200])
	return vs.y / float(src[1]) * (1.0 if el.has("g") else hud_scale)


## Global scale for the 1600x1200 HUD space.
func s() -> float:
	return vs.y / 1200.0 * hud_scale


## Screen rect of an element; `off` is an offset in source pixels, `grow` extra size in source px.
func r(key: String, off := Vector2.ZERO, grow := Vector2.ZERO) -> Rect2:
	if off == Vector2.ZERO and grow == Vector2.ZERO:
		var c = _rc.get(key)
		if c != null:
			return c
		var el := e(key)
		var rc := Rect2() if el.is_empty() or not el.has("p") else rect_of(el)
		_rc[key] = rc
		return rc
	var el2 := e(key)
	if el2.is_empty() or not el2.has("p"):
		return Rect2()
	return rect_of(el2, off, grow)


func rect_of(el: Dictionary, off := Vector2.ZERO, grow := Vector2.ZERO) -> Rect2:
	var src: Array = el.get("src", [1600, 1200])
	var a: Array = el.get("a", [0.5, 0.5])
	var sc := scale_of(el)
	var anc := Vector2(float(a[0]), float(a[1]))
	var srcv := Vector2(float(src[0]), float(src[1]))
	var p := Vector2(float(el.p[0]), float(el.p[1])) + off
	var sz := Vector2(float(el.s[0]), float(el.s[1])) + grow
	return Rect2(anc * vs + (p - anc * srcv) * sc, sz * sc)


## Map a point given in an element's source space to the screen.
func pt(key: String, src_point: Vector2) -> Vector2:
	var el := e(key)
	var src: Array = el.get("src", [1600, 1200])
	var a: Array = el.get("a", [0.5, 0.5])
	var anc := Vector2(float(a[0]), float(a[1]))
	return anc * vs + (src_point - anc * Vector2(float(src[0]), float(src[1]))) * scale_of(el)


## Draw an element's own texture region at its layout rect (plus offset). Returns the rect.
func draw(ci: CanvasItem, key: String, mod := Color.WHITE, off := Vector2.ZERO) -> Rect2:
	var rc := r(key, off)
	if rc.size.x <= 0.0:
		return rc
	draw_in(ci, key, rc, mod)
	return rc


## Draw an element's texture region into an arbitrary rect.
func draw_in(ci: CanvasItem, key: String, rc: Rect2, mod := Color.WHITE) -> void:
	var el := e(key)
	if not el.has("t"):
		return
	var t := tex(el.t)
	if t == null:
		return
	if el.has("uv"):
		var uv: Array = el.uv
		ci.draw_texture_rect_region(t, rc, Rect2(uv[0], uv[1], uv[2] - uv[0], uv[3] - uv[1]), mod)
	else:
		ci.draw_texture_rect(t, rc, false, mod)


## Texture region of an element (Rect2 in texture pixels), or an empty rect.
func uv_of(key: String) -> Rect2:
	var el := e(key)
	if not el.has("uv"):
		return Rect2()
	var uv: Array = el.uv
	return Rect2(uv[0], uv[1], uv[2] - uv[0], uv[3] - uv[1])


# ------------------------------------------------------------------ flipbooks (UiElementEffectAnimationData)
## Frame count and duration (s) of an EffectAnimation element.
func fx_info(key: String) -> Vector2:
	var el := e(key)
	if not el.has("fr"):
		return Vector2.ZERO
	var fr: Array = el.fr
	return Vector2(float(fr[0]), float(fr[0]) / maxf(1.0, float(fr[2])))


## Draw frame `frame` of an EffectAnimation flipbook. Frames are packed row-major from the element's UV,
## with a 1 px gutter (League atlases: stride = frame size + 1). `rc` overrides the layout rect.
func draw_fx(ci: CanvasItem, key: String, frame: int, mod := Color.WHITE, off := Vector2.ZERO, rc := Rect2()) -> void:
	var el := e(key)
	if not el.has("fr") or not el.has("t"):
		return
	var t := tex(el.t)
	if t == null:
		return
	var fr: Array = el.fr
	var n := int(fr[0])
	var per_row := maxi(1, int(fr[1]))
	frame = clampi(frame, 0, n - 1)
	var uv := uv_of(key)
	var stride := uv.size + Vector2.ONE
	var src := Rect2(uv.position + Vector2(frame % per_row, frame / per_row) * stride, uv.size)
	if rc.size.x <= 0.0:
		rc = r(key, off)
	ci.draw_texture_rect_region(t, rc, src, mod)


## Frame index of a flipbook started `age` seconds ago; -1 once a non-looping one has finished.
func fx_frame(key: String, age: float, loop := false) -> int:
	var el := e(key)
	if not el.has("fr"):
		return -1
	var fr: Array = el.fr
	var i := int(age * float(fr[2]))
	if loop:
		return i % maxi(1, int(fr[0]))
	return i if i < int(fr[0]) else -1


static func region(ci: CanvasItem, tex_name: String, uv: Rect2, rc: Rect2, mod := Color.WHITE) -> void:
	var t := tex(tex_name)
	if t != null:
		ci.draw_texture_rect_region(t, rc, uv, mod)


## Horizontal 3-slice: keeps `cap` source px of the texture at both ends unstretched.
static func hslice(ci: CanvasItem, tex_name: String, uv: Rect2, rc: Rect2, cap: float, mod := Color.WHITE) -> void:
	var t := tex(tex_name)
	if t == null:
		return
	var k := rc.size.y / uv.size.y
	var cw := minf(cap * k, rc.size.x * 0.5)
	ci.draw_texture_rect_region(t, Rect2(rc.position, Vector2(cw, rc.size.y)), Rect2(uv.position, Vector2(cap, uv.size.y)), mod)
	ci.draw_texture_rect_region(t, Rect2(rc.position + Vector2(cw, 0), Vector2(rc.size.x - cw * 2.0, rc.size.y)),
		Rect2(uv.position + Vector2(cap, 0), Vector2(uv.size.x - cap * 2.0, uv.size.y)), mod)
	ci.draw_texture_rect_region(t, Rect2(Vector2(rc.end.x - cw, rc.position.y), Vector2(cw, rc.size.y)),
		Rect2(Vector2(uv.end.x - cap, uv.position.y), Vector2(cap, uv.size.y)), mod)


## 9-slice with a uniform margin `m` (source px).
static func nine(ci: CanvasItem, tex_name: String, uv: Rect2, rc: Rect2, m: float, mod := Color.WHITE, k := 1.0) -> void:
	var t := tex(tex_name)
	if t == null:
		return
	var d := minf(m * k, minf(rc.size.x, rc.size.y) * 0.5)
	var xs := [rc.position.x, rc.position.x + d, rc.end.x - d, rc.end.x]
	var ys := [rc.position.y, rc.position.y + d, rc.end.y - d, rc.end.y]
	var us := [uv.position.x, uv.position.x + m, uv.end.x - m, uv.end.x]
	var vv := [uv.position.y, uv.position.y + m, uv.end.y - m, uv.end.y]
	for j in 3:
		for i in 3:
			var dst := Rect2(xs[i], ys[j], xs[i + 1] - xs[i], ys[j + 1] - ys[j])
			if dst.size.x <= 0.0 or dst.size.y <= 0.0:
				continue
			ci.draw_texture_rect_region(t, dst, Rect2(us[i], vv[j], us[i + 1] - us[i], vv[j + 1] - vv[j]), mod)


## League radial cooldown (EffectCooldownRadial): covers `frac` (0..1) of the rect, sweeping clockwise
## from 12 o'clock; the uncovered part grows clockwise as the cooldown runs out.
## With a texture region the cover is textured (League's dark cooldown overlay), otherwise flat colour.
static func radial(ci: CanvasItem, rc: Rect2, frac: float, col: Color, tex_name := "", uv := Rect2()) -> void:
	if frac <= 0.001:
		return
	frac = minf(frac, 1.0)
	var c := rc.get_center()
	var pts := PackedVector2Array([c])
	var steps := maxi(3, int(ceil(32.0 * frac)))
	# remaining cooldown occupies the arc from (1-frac) to 1 of a clockwise sweep starting at the top
	var a0 := -PI * 0.5 + TAU * (1.0 - frac)
	var a1 := -PI * 0.5 + TAU
	var hx := rc.size.x * 0.5
	var hy := rc.size.y * 0.5
	for i in steps + 1:
		var a := lerpf(a0, a1, float(i) / steps)
		var d := Vector2(cos(a), sin(a))
		var m := maxf(absf(d.x) / hx, absf(d.y) / hy)
		pts.append(c + d / m)
	var t: Texture2D = tex(tex_name) if tex_name != "" else null
	if t == null:
		ci.draw_colored_polygon(pts, col)
		return
	var ts := t.get_size()
	var uvs := PackedVector2Array()
	for p in pts:
		var k := (p - rc.position) / rc.size
		uvs.append((uv.position + k * uv.size) / ts)
	ci.draw_colored_polygon(pts, col, uvs, t)


## Vertical fill (EffectFillPercentage): draws the bottom `frac` of the element's texture.
func fill_v(ci: CanvasItem, key: String, frac: float, mod := Color.WHITE) -> void:
	var el := e(key)
	if el.is_empty() or not el.has("t"):
		return
	var rc := r(key)
	var u := uv_of(key)
	frac = clampf(frac, 0.0, 1.0)
	var dst := Rect2(rc.position.x, rc.end.y - rc.size.y * frac, rc.size.x, rc.size.y * frac)
	var src := Rect2(u.position.x, u.end.y - u.size.y * frac, u.size.x, u.size.y * frac)
	region(ci, el.t, src, dst, mod)


## Horizontal fill: draws the left `frac` of the element's texture (resource bars).
func fill_h(ci: CanvasItem, key: String, frac: float, mod := Color.WHITE, from := 0.0, off := Vector2.ZERO) -> Rect2:
	var el := e(key)
	if el.is_empty() or not el.has("t"):
		return Rect2()
	var rc := r(key, off)
	var u := uv_of(key)
	frac = clampf(frac, 0.0, 1.0)
	from = clampf(from, 0.0, frac)
	var dst := Rect2(rc.position.x + rc.size.x * from, rc.position.y, rc.size.x * (frac - from), rc.size.y)
	var src := Rect2(u.position.x + u.size.x * from, u.position.y, u.size.x * (frac - from), u.size.y)
	if dst.size.x > 0.5:
		region(ci, el.t, src, dst, mod)
	return dst


# ------------------------------------------------------------------ League font styles
static func _font_file(name: String) -> Font:
	if _font_files.has(name):
		return _font_files[name]
	var f: Font = null
	match name.to_lower():
		"beaufortforlol-bold": f = Assets.font("beaufort", "Bold")
		"beaufortforlol-regular": f = Assets.font("beaufort", "Regular")
		"beaufortforlol-heavy": f = Assets.font("beaufort", "Heavy")
		"beaufortforlol-medium": f = Assets.font("beaufort", "Medium")
		"spiegel-bold": f = Assets.font("spiegel", "Bold")
		"spiegel-semibold": f = Assets.font("spiegel", "SemiBold")
		"spiegel-regular": f = Assets.font("spiegel", "Regular")
		"gillsansmtpro-medium":
			if ResourceLoader.exists("res://assets/ui/hud/fonts/gillsansmtpro-medium.otf"):
				f = load("res://assets/ui/hud/fonts/gillsansmtpro-medium.otf")
	if f == null:
		f = Assets.font("spiegel", "Regular")
	_font_files[name] = f
	return f


static func _c8(a, fallback: Color) -> Color:
	if a == null:
		return fallback
	return Color8(int(a[0]), int(a[1]), int(a[2]), int(a[3]))


## Resolved League text style (GameFontDescription) for the current screen height:
## {font, color, shadow (Color, a=0 none), sh (Vector2 shadow offset, px), outline (Color), ol (int px), px (int)}
## `size_px` is the style's font size in League's reference resolution, already converted to screen px.
func style(fd: String, scale := 1.0) -> Dictionary:
	var ck := "%s|%d|%d" % [fd, int(vs.y), int(scale * 1000.0)]
	var c = _style_cache.get(ck)
	if c != null:
		return c
	var d: Dictionary = fonts().get(fd, {})
	var sizes: Array = d.get("sizes", [])
	var ref_h := FONT_DEFAULT_SCREEN_H
	var fs := 0.0
	var ol := 0.0
	var sh := Vector2.ZERO
	if not sizes.is_empty():
		var pick: Array = sizes[0]
		if d.get("auto", true):
			for z in sizes:
				if float(z[0]) == 0.0 or float(z[0]) == FONT_DEFAULT_SCREEN_H:
					pick = z
		else:
			# fixed sizes per screen height: largest entry not above the screen
			var best := -1.0
			for z in sizes:
				var zh := float(z[0]) if float(z[0]) > 0.0 else FONT_DEFAULT_SCREEN_H
				if zh <= vs.y and zh > best and float(z[1]) > 0.0:
					best = zh
					pick = z
		ref_h = float(pick[0]) if float(pick[0]) > 0.0 else FONT_DEFAULT_SCREEN_H
		fs = float(pick[1])
		ol = float(pick[2])
		sh = Vector2(float(pick[3]), float(pick[4]))
		if not d.get("auto", true):
			ref_h = vs.y
	var k := vs.y / ref_h * scale
	var st := {
		"font": _font_file(String(d.get("font", "BeaufortforLOL-Bold"))),
		"color": _c8(d.get("color"), Color.WHITE),
		"shadow": _c8(d.get("shadow"), Color(0, 0, 0, 0.85)) if sh != Vector2.ZERO else Color(0, 0, 0, 0),
		"sh": (sh * maxf(1.0, k)).round(),
		"outline": _c8(d.get("outline"), Color(0, 0, 0, 0.9)),
		"ol": int(round(ol * 2.0 * maxf(1.0, k))) if ol > 0.0 else 0,
		"px": maxi(8, int(round(fs * k))) if fs > 0.0 else 0,
		"k": k,
	}
	_style_cache[ck] = st
	return st


## Draw text in an element's rect with the element's own League font style (fd). `col` overrides the style colour
## (alpha multiplies), `px_src` overrides the font size (source px) when the style has none.
func ltext(ci: CanvasItem, key: String, s_txt: String, col := Color(0, 0, 0, 0), halign := -1, off := Vector2.ZERO,
		px_src := 0.0) -> Rect2:
	var el := e(key)
	if el.is_empty() or not el.has("p"):
		return Rect2()
	var rc := r(key, off)
	var sc := (1.0 if el.has("g") else hud_scale)
	var st := style(String(el.get("fd", "HUD_Default")), sc)
	var px: int = st.px
	if px <= 0 or px_src > 0.0:
		px = maxi(8, int(round((px_src if px_src > 0.0 else 13.0) * scale_of(el))))
	var c: Color = st.color if col.a <= 0.0 else col
	var ha: int = halign if halign >= 0 else int(el.get("ha", 0))
	styled_in(ci, rc, s_txt, st, px, c, ha)
	return rc


## Text with the element's League style into an explicit rect (locally laid out scenes); `sc` = style scale.
func ltext_in(ci: CanvasItem, key: String, rc: Rect2, s_txt: String, col := Color(0, 0, 0, 0), halign := -1, sc := 1.0) -> void:
	var el := e(key)
	var st := style(String(el.get("fd", "HUD_Default")), sc)
	var px: int = st.px
	if px <= 0:
		px = maxi(8, int(rc.size.y * 0.7))
	var c: Color = st.color if col.a <= 0.0 else col
	styled_in(ci, rc, s_txt, st, px, c, halign if halign >= 0 else int(el.get("ha", 0)))


# ------------------------------------------------------------------ locally laid out scenes
## Target frame, chat and ping wheel elements are positioned by code in League; their layout positions are local
## to the scene: rect = origin + (p + off) * k.
func lr(key: String, origin: Vector2, k: float, off := Vector2.ZERO) -> Rect2:
	var el := e(key)
	if el.is_empty() or not el.has("p"):
		return Rect2()
	return Rect2(origin + (Vector2(float(el.p[0]), float(el.p[1])) + off) * k, Vector2(float(el.s[0]), float(el.s[1])) * k)


func ldraw(ci: CanvasItem, key: String, origin: Vector2, k: float, mod := Color.WHITE, off := Vector2.ZERO) -> Rect2:
	var rc := lr(key, origin, k, off)
	if rc.size.x > 0.0:
		draw_in(ci, key, rc, mod)
	return rc


## Draw a string with a resolved style (shadow / outline) into a rect, vertically centred.
static func styled_in(ci: CanvasItem, rc: Rect2, s_txt: String, st: Dictionary, px: int, col: Color, ha := 1) -> void:
	var font: Font = st.font
	var w := font.get_string_size(s_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var x := rc.position.x
	if ha == 1:
		x = rc.get_center().x - w * 0.5
	elif ha == 2:
		x = rc.end.x - w
	var y := rc.get_center().y + (font.get_ascent(px) - font.get_descent(px)) * 0.5
	var p := Vector2(roundf(x), roundf(y))
	var ol: int = st.ol
	if ol > 0:
		var oc: Color = st.outline
		ci.draw_string_outline(font, p, s_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, ol, Color(oc.r, oc.g, oc.b, oc.a * col.a))
	var shc: Color = st.shadow
	if shc.a > 0.0:
		ci.draw_string(font, p + st.sh, s_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, Color(shc.r, shc.g, shc.b, shc.a * col.a))
	ci.draw_string(font, p, s_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


## Text helper with an explicit font / size (source px). Elements that carry a League font style (fd) use it.
func text(ci: CanvasItem, key: String, s_txt: String, font: Font, size: float, col: Color, halign := -1,
		off := Vector2.ZERO, outline := 3.0) -> Rect2:
	var el := e(key)
	if el.is_empty() or not el.has("p"):
		return Rect2()
	var rc := r(key, off)
	var ha: int = halign if halign >= 0 else int(el.get("ha", 0))
	if el.has("fd"):
		# the element has a League font style: its typeface, size and shadow win; the caller's colour is kept
		var st := style(String(el.fd), 1.0 if el.has("g") else hud_scale)
		var spx: int = st.px if int(st.px) > 0 else maxi(9, int(round(size * scale_of(el))))
		styled_in(ci, rc, s_txt, st, spx, col, ha)
		return rc
	text_in(ci, rc, s_txt, font, maxi(9, int(round(size * scale_of(el)))), col, ha, outline)
	return rc


static func text_in(ci: CanvasItem, rc: Rect2, s_txt: String, font: Font, px: int, col: Color, ha := 1, outline := 3.0) -> void:
	var w := font.get_string_size(s_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x
	var x := rc.position.x
	if ha == 1:
		x = rc.get_center().x - w * 0.5
	elif ha == 2:
		x = rc.end.x - w
	var asc := font.get_ascent(px)
	var desc := font.get_descent(px)
	var y := rc.get_center().y + (asc - desc) * 0.5
	if outline > 0.0:
		ci.draw_string_outline(font, Vector2(x, y), s_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, int(outline), Color(0, 0, 0, col.a * 0.9))
	ci.draw_string(font, Vector2(x, y), s_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)


static var _unit_circle := {}    ## segment count -> PackedVector2Array of unit directions


## Circular textured image (portraits). Unit-circle directions are cached per segment count.
static func circle_tex(ci: CanvasItem, t: Texture2D, center: Vector2, radius: float, mod := Color.WHITE, zoom := 1.0) -> void:
	if t == null:
		return
	var n := 32 if radius > 14.0 else 20
	var dirs: PackedVector2Array = _unit_circle.get(n, PackedVector2Array())
	if dirs.is_empty():
		for i in n:
			var a := TAU * i / float(n)
			dirs.append(Vector2(cos(a), sin(a)))
		_unit_circle[n] = dirs
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	pts.resize(n)
	uvs.resize(n)
	var uk := 0.5 / zoom
	for i in n:
		var d := dirs[i]
		pts[i] = center + d * radius
		uvs[i] = Vector2(0.5, 0.5) + d * uk
	ci.draw_colored_polygon(pts, mod, uvs, t)


## Champion square icon with League's slight zoom crop (square icons have a dark border baked in).
static func square_icon(ci: CanvasItem, t: Texture2D, rc: Rect2, mod := Color.WHITE, crop := 0.06) -> void:
	if t == null:
		return
	var ts := t.get_size()
	ci.draw_texture_rect_region(t, rc, Rect2(ts * crop, ts * (1.0 - crop * 2.0)), mod)
