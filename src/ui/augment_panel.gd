class_name AugmentPanel
extends Control
## Augment selection screen: 3 tier-coloured cards with one reroll each.

var hud = null
var open := false
var hidden_by_user := false
var _anim := 0.0
var _hover := -1
var _hover_reroll := -1
var _card_rects: Array = []
var _reroll_rects: Array = []
var _hide_rect := Rect2()
var _picked := -1
var _pick_t := 0.0
var _card_anim := [0.0, 0.0, 0.0]
var f_title: Font
var f_name: Font
var f_body: Font
const CARD := Vector2(300, 470)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	f_title = Assets.font("beaufort", "Bold")
	f_name = Assets.font("beaufort", "Bold")
	f_body = Assets.font("spiegel", "Regular")


func champ():
	return G.player


func in_combat(c) -> bool:
	return c.match_ref != null and not c.dead and c.match_ref.time - c.last_combat_time < 4.0


func can_pick(c) -> bool:
	return c.augments_pending > 0 and (c.dead or c.in_fountain) and not in_combat(c)


func toggle() -> void:
	var c = champ()
	if c == null or c.augments_pending <= 0:
		return
	hidden_by_user = not hidden_by_user if open else false
	if not can_pick(c):
		hud._on_cast_failed(null, "")
		hud.fail_msg = "Augments can be chosen in base or while dead"
		hud.fail_t = 1.8


func _process(delta: float) -> void:
	var c = champ()
	if c == null or hud == null:
		return
	var want: bool = c.augments_pending > 0 and can_pick(c) and not hidden_by_user
	if _picked >= 0:
		_pick_t += delta
		if _pick_t > 0.55:
			_finish_pick()
		queue_redraw()
		return
	if want and not open:
		open = true
		_anim = 0.0
		_card_anim = [0.0, 0.0, 0.0]
		c.match_ref.get_offer(c)
		Sfx.ui("card_appear")
	elif not want and open:
		open = false
	if open:
		_anim = minf(1.0, _anim + delta * 2.5)
		for i in 3:
			var target := 1.0 if i == _hover else 0.0
			_card_anim[i] = lerpf(_card_anim[i], target, clampf(delta * 12.0, 0.0, 1.0))
	if c.augments_pending <= 0:
		hidden_by_user = false
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not open or _picked >= 0:
		return
	if event is InputEventMouseMotion:
		var mp: Vector2 = get_local_mouse_position()
		var prev_hover := _hover
		_hover = -1
		_hover_reroll = -1
		for i in _card_rects.size():
			if _card_rects[i].has_point(mp):
				_hover = i
		if _hover >= 0 and _hover != prev_hover:
			Sfx.ui("card_hover")
		for i in _reroll_rects.size():
			if _reroll_rects[i].has_point(mp):
				_hover_reroll = i
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var mp2: Vector2 = get_local_mouse_position()
		var c = champ()
		for i in _reroll_rects.size():
			if _reroll_rects[i].has_point(mp2):
				c.match_ref.reroll_offer(c, i)
				Sfx.ui("reroll")
				Vfx.ring(c.match_ref, c.global_position, Color(0.8, 0.7, 1.0), 1.5, 0.4)
				get_viewport().set_input_as_handled()
				return
		for i in _card_rects.size():
			if _card_rects[i].has_point(mp2):
				_picked = i
				_pick_t = 0.0
				Sfx.ui("card_select")
				get_viewport().set_input_as_handled()
				return
		if _hide_rect.has_point(mp2):
			hidden_by_user = true
			get_viewport().set_input_as_handled()


func _finish_pick() -> void:
	var c = champ()
	var idx := _picked
	_picked = -1
	open = false
	if c != null and c.augments_pending > 0:
		c.match_ref.choose_augment(c, idx)


func _draw() -> void:
	_card_rects.clear()
	_reroll_rects.clear()
	if not open and _picked < 0:
		return
	var c = champ()
	var off: Dictionary = c.match_ref.offers.get(c, {})
	if off.is_empty():
		return
	var vs := size
	var tier: String = off.tier
	var tcol: Color = G.RARITY_COLORS.get(tier, Color.WHITE)
	var a := _ease(_anim)
	# dim band
	draw_rect(Rect2(0, vs.y * 0.5 - 330, vs.x, 660), Color(0.01, 0.015, 0.03, 0.72 * a))
	var title := "CHOOSE AN AUGMENT"
	_center_text(title, Vector2(vs.x * 0.5, vs.y * 0.5 - 292), 30, Color(0.95, 0.9, 0.78, a), f_title)
	_center_text(tier.to_upper(), Vector2(vs.x * 0.5, vs.y * 0.5 - 258), 18, Color(tcol.r, tcol.g, tcol.b, a), f_title)
	var gap := 44.0
	var total_w := CARD.x * 3 + gap * 2
	var x0 := vs.x * 0.5 - total_w * 0.5
	var t := Time.get_ticks_msec() / 1000.0
	for i in off.ids.size():
		var aid: String = off.ids[i]
		var stagger := clampf((_anim - i * 0.12) * 1.6, 0.0, 1.0)
		var e := _ease(stagger)
		var lift: float = _card_anim[i] * 14.0
		var r := Rect2(x0 + i * (CARD.x + gap), vs.y * 0.5 - 225 + (1.0 - e) * 60.0 - lift, CARD.x, CARD.y)
		var alpha := e
		if _picked >= 0:
			if i == _picked:
				var k := _pick_t / 0.55
				r = r.grow(k * 20.0)
				alpha = 1.0 - k * k
			else:
				alpha = maxf(0.0, 1.0 - _pick_t * 4.0)
		_card_rects.append(r)
		_draw_card(r, aid, tier, tcol, alpha, i == _hover, t)
		var rr := Rect2(r.position.x + CARD.x * 0.5 - 70, r.end.y + 18, 140, 36)
		_reroll_rects.append(rr)
		var used: bool = off.rerolled[i]
		var rcol := Color(0.5, 0.5, 0.55, 0.6 * alpha) if used else Color(0.85, 0.75, 1.0, alpha)
		draw_rect(rr, Color(0.05, 0.05, 0.09, 0.9 * alpha))
		draw_rect(rr, rcol if (i == _hover_reroll and not used) else Color(rcol.r, rcol.g, rcol.b, rcol.a * 0.6), false, 2.0)
		_center_text("REROLLED" if used else "⟳  REROLL", rr.get_center(), 15, rcol, f_title)
	_hide_rect = Rect2(vs.x * 0.5 - 50, vs.y * 0.5 + 318, 100, 26)
	_center_text("Hide [G]", _hide_rect.get_center(), 13, Color(0.75, 0.75, 0.8, 0.7 * a), f_body)


func _draw_card(r: Rect2, aid: String, tier: String, tcol: Color, alpha: float, hover: bool, t: float) -> void:
	var a := AugmentDB.create(aid)
	if a == null:
		return
	var border := tcol
	if tier == "Prismatic":
		border = Color.from_hsv(fmod(t * 0.15, 1.0), 0.45, 1.0)
	# background
	draw_rect(r, Color(0.03, 0.04, 0.07, 0.96 * alpha))
	var grad_top := Color(tcol.r * 0.25, tcol.g * 0.25, tcol.b * 0.3, 0.9 * alpha)
	draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y * 0.45)), grad_top)
	if tier == "Prismatic":
		for s in 6:
			var hx := r.position.x + fmod(t * 60.0 + s * 70.0, r.size.x + 120.0) - 60.0
			var hc := Color.from_hsv(fmod(t * 0.1 + s * 0.16, 1.0), 0.6, 1.0, 0.07 * alpha)
			draw_line(Vector2(hx, r.position.y), Vector2(hx - 60, r.position.y + r.size.y * 0.45), hc, 18.0)
	# glow behind icon
	var ic := Vector2(r.get_center().x, r.position.y + 118)
	for k in 6:
		draw_circle(ic, 90.0 - k * 12.0, Color(tcol.r, tcol.g, tcol.b, (0.04 + k * 0.02) * alpha * (1.4 if hover else 1.0)))
	if a.icon != null:
		var isz := 160.0
		draw_texture_rect(a.icon, Rect2(ic - Vector2(isz, isz) * 0.5, Vector2(isz, isz)), false, Color(1, 1, 1, alpha))
	# frame
	var bw := 3.0 if hover else 2.0
	draw_rect(r, Color(border.r, border.g, border.b, alpha), false, bw)
	draw_rect(r.grow(-6), Color(border.r, border.g, border.b, 0.25 * alpha), false, 1.0)
	# name
	_center_text(a.display_name, Vector2(r.get_center().x, r.position.y + 232), 25, Color(1.0, 0.95, 0.85, alpha), f_name)
	draw_line(Vector2(r.position.x + 40, r.position.y + 254), Vector2(r.end.x - 40, r.position.y + 254), Color(border.r, border.g, border.b, 0.6 * alpha), 1.0)
	# description
	var lines := _wrap(Hud._clean(a.description), r.size.x - 36, 15)
	var y := r.position.y + 282
	for ln in lines:
		if y > r.end.y - 30:
			break
		_center_text(ln, Vector2(r.get_center().x, y), 15, Color(0.86, 0.86, 0.9, alpha), f_body, false)
		y += 21
	_center_text(tier.to_upper(), Vector2(r.get_center().x, r.end.y - 18), 12, Color(tcol.r, tcol.g, tcol.b, 0.8 * alpha), f_title)


func _ease(x: float) -> float:
	return 1.0 - pow(1.0 - clampf(x, 0.0, 1.0), 3.0)


func _center_text(s: String, p: Vector2, sz: int, col: Color, f: Font, outline: bool = true) -> void:
	var ts := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz)
	var pos := p - Vector2(ts.x * 0.5, -sz * 0.35)
	if outline:
		draw_string_outline(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, col.a * 0.8))
	draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _wrap(text: String, width: float, sz: int) -> Array:
	var out := []
	for para in text.split("\n"):
		var line := ""
		for word in para.split(" "):
			var test := word if line == "" else line + " " + word
			if f_body.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > width and line != "":
				out.append(line)
				line = word
			else:
				line = test
		if line != "":
			out.append(line)
	return out
