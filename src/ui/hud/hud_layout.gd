class_name HudLayout
extends RefCounted
## League's in-game HUD layout (positions, sizes, anchors and atlas UVs), read from
## assets/ui/hud/layout.json which tools/lol/extract_hud.py extracts from UI.wad.client.
##
## League lays every element out in a source resolution (mostly 1600x1200) around an anchor point:
##   screen_pos = anchor * screen + (pos - anchor * src) * scale,  scale = screen_h / src_h * hud_scale
## Elements flagged "g" (minimap, top header) ignore the global HUD scale.

const LAYOUT_PATH := "res://assets/ui/hud/layout.json"
const TEX_DIR := "res://assets/ui/hud/tex/"

static var _data := {}
static var _tex := {}
static var _font_cache := {}

var vs := Vector2(1280, 720)
var hud_scale := 1.0
var mm_scale := 1.0


static func data() -> Dictionary:
	if _data.is_empty() and FileAccess.file_exists(LAYOUT_PATH):
		var d = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
		if d is Dictionary:
			_data = d
	return _data


static func tex(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name]
	var t: Texture2D = null
	var p := TEX_DIR + name + ".png"
	if ResourceLoader.exists(p):
		t = load(p)
	_tex[name] = t
	return t


func begin(p_vs: Vector2) -> void:
	vs = p_vs


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
	var el := e(key)
	if el.is_empty() or not el.has("p"):
		return Rect2()
	return rect_of(el, off, grow)


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
	var el := e(key)
	if el.is_empty() or not el.has("p"):
		return Rect2()
	var rc := rect_of(el, off)
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
	var steps := maxi(3, int(ceil(40.0 * frac)))
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
	var rc := rect_of(el)
	var uv: Array = el.uv
	var u := Rect2(uv[0], uv[1], uv[2] - uv[0], uv[3] - uv[1])
	frac = clampf(frac, 0.0, 1.0)
	var dst := Rect2(rc.position.x, rc.end.y - rc.size.y * frac, rc.size.x, rc.size.y * frac)
	var src := Rect2(u.position.x, u.end.y - u.size.y * frac, u.size.x, u.size.y * frac)
	region(ci, el.t, src, dst, mod)


## Horizontal fill: draws the left `frac` of the element's texture (resource bars).
func fill_h(ci: CanvasItem, key: String, frac: float, mod := Color.WHITE, from := 0.0) -> Rect2:
	var el := e(key)
	if el.is_empty() or not el.has("t"):
		return Rect2()
	var rc := rect_of(el)
	var uv: Array = el.uv
	var u := Rect2(uv[0], uv[1], uv[2] - uv[0], uv[3] - uv[1])
	frac = clampf(frac, 0.0, 1.0)
	from = clampf(from, 0.0, frac)
	var dst := Rect2(rc.position.x + rc.size.x * from, rc.position.y, rc.size.x * (frac - from), rc.size.y)
	var src := Rect2(u.position.x + u.size.x * from, u.position.y, u.size.x * (frac - from), u.size.y)
	if dst.size.x > 0.5:
		region(ci, el.t, src, dst, mod)
	return dst


## Draw text inside an element's rect. size = font size in source px; halign 0 left, 1 center, 2 right.
func text(ci: CanvasItem, key: String, s_txt: String, font: Font, size: float, col: Color, halign := -1,
		off := Vector2.ZERO, outline := 3.0) -> Rect2:
	var el := e(key)
	if el.is_empty() or not el.has("p"):
		return Rect2()
	var rc := rect_of(el, off)
	var ha: int = halign if halign >= 0 else int(el.get("ha", 0))
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


## Circular textured image (portraits).
static func circle_tex(ci: CanvasItem, t: Texture2D, center: Vector2, radius: float, mod := Color.WHITE, zoom := 1.0) -> void:
	if t == null:
		return
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		var d := Vector2(cos(a), sin(a))
		pts.append(center + d * radius)
		uvs.append(Vector2(0.5, 0.5) + d * 0.5 / zoom)
	ci.draw_colored_polygon(pts, mod, uvs, t)


## Champion square icon with League's slight zoom crop (square icons have a dark border baked in).
static func square_icon(ci: CanvasItem, t: Texture2D, rc: Rect2, mod := Color.WHITE, crop := 0.06) -> void:
	if t == null:
		return
	var ts := t.get_size()
	ci.draw_texture_rect_region(t, rc, Rect2(ts * crop, ts * (1.0 - crop * 2.0)), mod)
