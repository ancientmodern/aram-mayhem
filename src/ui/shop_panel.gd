class_name ShopPanel
extends Control
## Item shop (P / click gold). Buying is only possible while dead or on the spawn platform.

var hud = null
var category := "Recommended"
var selected := -1
var selected_owned = null
var _cells := []           ## [{rect, id}]
var _cat_rects := {}
var _btn_buy := Rect2()
var _btn_sell := Rect2()
var _btn_close := Rect2()
var _inv_rects := []
var _tree_cells := []
var _last_click_t := 0
var _last_click_id := -1
var f_title: Font
var f_body: Font
var f_bold: Font
var msg := ""
var msg_t := 0.0
var panel := Rect2()

const CATS := ["Recommended", "Starter", "Boots", "Fighter", "Marksman", "Mage", "Tank", "Support", "Basic", "All"]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	f_title = Assets.font("beaufort", "Bold")
	f_body = Assets.font("spiegel", "Regular")
	f_bold = Assets.font("spiegel", "Bold")


func refresh() -> void:
	queue_redraw()


func champ():
	return G.player


func _process(delta: float) -> void:
	msg_t = maxf(0.0, msg_t - delta)
	if visible:
		queue_redraw()


func _items_for(cat: String) -> Array:
	var c = champ()
	var out := []
	if cat == "Recommended":
		return ItemDB.BUILDS.get(c.alias, []).duplicate() + [9999]
	for id in ItemDB.CAT:
		var tags: Array = ItemDB.tags_of(id)
		match cat:
			"Starter":
				if "starter" in tags:
					out.append(id)
			"Boots":
				if "boots" in tags:
					out.append(id)
			"Basic":
				if "basic" in tags:
					out.append(id)
			"All":
				if not ("basic" in tags) and not ("starter" in tags) and not ("boots" in tags):
					out.append(id)
			_:
				if cat.to_lower() in tags and not ("basic" in tags) and not ("boots" in tags) and not ("starter" in tags):
					out.append(id)
	out.sort_custom(func(a, b): return ItemDB.cost_of(a) < ItemDB.cost_of(b))
	return out


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		visible = false
		get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton and event.pressed):
		return
	var mp: Vector2 = get_local_mouse_position()
	if not panel.has_point(mp):
		return
	get_viewport().set_input_as_handled()
	var right: bool = event.button_index == MOUSE_BUTTON_RIGHT
	if _btn_close.has_point(mp):
		visible = false
		return
	for k in _cat_rects:
		if _cat_rects[k].has_point(mp):
			category = k
			return
	for cell in _cells + _tree_cells:
		if cell.rect.has_point(mp):
			selected = cell.id
			selected_owned = null
			var now := Time.get_ticks_msec()
			if right or (now - _last_click_t < 350 and _last_click_id == cell.id):
				_buy(cell.id)
			_last_click_t = now
			_last_click_id = cell.id
			return
	for i in _inv_rects.size():
		if _inv_rects[i].has_point(mp) and i < champ().items.size():
			selected_owned = champ().items[i]
			selected = selected_owned.item_id
			return
	if _btn_buy.has_point(mp) and selected >= 0:
		_buy(selected)
	elif _btn_sell.has_point(mp) and selected_owned != null:
		if champ().can_shop():
			ItemDB.sell(champ(), selected_owned)
			Sfx.ui("gold_click")
			selected_owned = null
		else:
			_msg("You can only sell while dead or in base")


func _buy(id: int) -> void:
	var c = champ()
	var r := ItemDB.buy_block_reason(c, id)
	if r != "":
		_msg(r)
		Sfx.ui("locked")
		return
	ItemDB.buy(c, id)
	Sfx.ui("buy")
	Vfx.rising(c, G.COLOR_GOLD, 0.4, 20)


func _msg(s: String) -> void:
	msg = s
	msg_t = 2.0


func _draw() -> void:
	if not visible:
		return
	var c = champ()
	var vs := size
	panel = Rect2(vs.x * 0.5 - 600, vs.y * 0.5 - 380, 1200, 700)
	draw_rect(Rect2(Vector2.ZERO, vs), Color(0, 0, 0, 0.35))
	draw_rect(panel, Color(0.02, 0.04, 0.07, 0.97))
	draw_rect(panel, Color(0.78, 0.67, 0.43), false, 2.0)
	_text("SHOP", panel.position + Vector2(24, 38), 28, Color(0.95, 0.88, 0.65), f_title)
	_text("%d" % int(c.gold), panel.position + Vector2(140, 38), 24, G.COLOR_GOLD, f_title)
	draw_circle(panel.position + Vector2(126, 30), 8, G.COLOR_GOLD)
	if not c.can_shop():
		_text("You can only buy items while dead or in base", panel.position + Vector2(260, 36), 16, Color(1.0, 0.55, 0.45), f_bold)
	_btn_close = Rect2(panel.end.x - 44, panel.position.y + 12, 32, 32)
	draw_rect(_btn_close, Color(0.15, 0.05, 0.05))
	_text("X", _btn_close.position + Vector2(10, 24), 18, Color(1, 0.8, 0.7), f_bold)
	# categories
	_cat_rects.clear()
	var cy := panel.position.y + 70
	for k in CATS:
		var r := Rect2(panel.position.x + 14, cy, 150, 40)
		var on: bool = k == category
		draw_rect(r, Color(0.12, 0.1, 0.06) if on else Color(0.04, 0.06, 0.09))
		draw_rect(r, Color(0.78, 0.67, 0.43) if on else Color(0.3, 0.27, 0.2), false, 1.0)
		_text(k, r.position + Vector2(14, 26), 15, Color(0.95, 0.9, 0.8) if on else Color(0.7, 0.7, 0.72), f_bold)
		_cat_rects[k] = r
		cy += 46
	# grid
	_cells.clear()
	var gx := panel.position.x + 186
	var gy := panel.position.y + 74
	var ids := _items_for(category)
	var col := 0
	for id in ids:
		var r := Rect2(gx + col * 78, gy, 64, 64)
		_draw_item_cell(r, id)
		_cells.append({"rect": r, "id": id})
		col += 1
		if col >= 8:
			col = 0
			gy += 96
	# details
	var dx := panel.position.x + 830
	var dr := Rect2(dx, panel.position.y + 64, 350, 470)
	draw_rect(dr, Color(0.03, 0.05, 0.08))
	draw_rect(dr, Color(0.3, 0.27, 0.2), false, 1.0)
	_tree_cells.clear()
	if selected >= 0 and ItemDB.has(selected):
		var icon := Assets.item_icon(selected) if selected != 9999 else Assets.augment_icon("ARAM_Stats")
		if icon != null:
			draw_texture_rect(icon, Rect2(dr.position + Vector2(14, 14), Vector2(64, 64)), false)
		_text(ItemDB.name_of(selected), dr.position + Vector2(90, 38), 19, Color(0.95, 0.88, 0.65), f_title)
		var pr := ItemDB.price_for(c, selected)
		_text("%d" % pr[0] + ("   (%d)" % ItemDB.cost_of(selected) if pr[0] != ItemDB.cost_of(selected) else ""), dr.position + Vector2(90, 66), 16, G.COLOR_GOLD, f_bold)
		var y := dr.position.y + 104
		var st: Dictionary = ItemDB.CAT[selected][2]
		for k in st:
			_text(ItemDB.stat_line(k, st[k]), Vector2(dr.position.x + 16, y), 15, Color(0.85, 0.9, 1.0), f_bold)
			y += 22
		var desc: String = ItemDB.CAT[selected][7]
		y += 6
		for ln in _wrap(desc, dr.size.x - 32, 14):
			_text(ln, Vector2(dr.position.x + 16, y), 14, Color(0.82, 0.82, 0.85), f_body)
			y += 19
		# build path
		var comps: Array = ItemDB.components_of(selected)
		if not comps.is_empty():
			y = maxf(y + 10, dr.position.y + 330)
			_text("Builds from", Vector2(dr.position.x + 16, y), 13, Color(0.6, 0.6, 0.65), f_bold)
			var tx := dr.position.x + 16
			for comp in comps:
				var cr := Rect2(tx, y + 10, 48, 48)
				_draw_item_cell(cr, comp, true)
				_tree_cells.append({"rect": cr, "id": comp})
				tx += 58
		_btn_buy = Rect2(dr.position.x + 16, dr.end.y - 56, 150, 42)
		var can := ItemDB.buy_block_reason(c, selected) == ""
		draw_rect(_btn_buy, Color(0.12, 0.25, 0.12) if can else Color(0.1, 0.1, 0.1))
		draw_rect(_btn_buy, Color(0.78, 0.67, 0.43) if can else Color(0.3, 0.3, 0.3), false, 2.0)
		_text("BUY", _btn_buy.position + Vector2(52, 28), 18, Color(0.95, 0.95, 0.9) if can else Color(0.5, 0.5, 0.5), f_title)
		_btn_sell = Rect2()
		if selected_owned != null:
			_btn_sell = Rect2(dr.position.x + 184, dr.end.y - 56, 150, 42)
			draw_rect(_btn_sell, Color(0.25, 0.1, 0.08))
			draw_rect(_btn_sell, Color(0.78, 0.5, 0.4), false, 2.0)
			_text("SELL %d" % int(selected_owned.cost * 0.7), _btn_sell.position + Vector2(30, 28), 16, Color(1, 0.85, 0.75), f_title)
	# inventory
	_inv_rects.clear()
	var iy := panel.end.y - 120
	_text("Inventory", Vector2(panel.position.x + 830, iy - 8), 14, Color(0.7, 0.7, 0.72), f_bold)
	for i in 6:
		var r := Rect2(panel.position.x + 830 + i * 58, iy + 4, 52, 52)
		draw_rect(r, Color(0.05, 0.06, 0.09))
		draw_rect(r, Color(0.3, 0.27, 0.2), false, 1.0)
		if i < c.items.size() and c.items[i].icon != null:
			draw_texture_rect(c.items[i].icon, r.grow(-2), false)
			if c.items[i] == selected_owned:
				draw_rect(r, Color(1, 0.85, 0.4), false, 2.0)
		_inv_rects.append(r)
	_text("Right-click or double-click to buy", Vector2(panel.position.x + 186, panel.end.y - 18), 13, Color(0.55, 0.55, 0.6), f_body)
	if msg_t > 0.0:
		var a := minf(1.0, msg_t * 2.0)
		_text(msg, Vector2(panel.position.x + 520, panel.end.y - 18), 15, Color(1, 0.5, 0.4, a), f_bold)


func _draw_item_cell(r: Rect2, id: int, small: bool = false) -> void:
	var c = champ()
	var owned := false
	for it in c.items:
		if it.item_id == id:
			owned = true
	var icon := Assets.item_icon(id) if id != 9999 else Assets.augment_icon("ARAM_Stats")
	draw_rect(r, Color(0.05, 0.06, 0.09))
	if icon != null:
		var p := ItemDB.price_for(c, id)
		var mod := Color.WHITE if c.gold >= p[0] else Color(0.55, 0.55, 0.6)
		draw_texture_rect(icon, r.grow(-2), false, mod)
	var border := Color(0.78, 0.67, 0.43) if id == selected else (Color(0.35, 0.8, 0.4) if owned else Color(0.3, 0.27, 0.2))
	draw_rect(r, border, false, 2.0 if id == selected else 1.0)
	if not small:
		var pr2 := ItemDB.price_for(c, id)
		var t := str(pr2[0])
		var ts := f_bold.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
		_text(t, Vector2(r.get_center().x - ts.x * 0.5, r.end.y + 16), 13, G.COLOR_GOLD if c.gold >= pr2[0] else Color(0.6, 0.55, 0.4), f_bold)


func _text(s: String, p: Vector2, sz: int, col: Color, f: Font) -> void:
	draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, col)


func _wrap(text: String, width: float, sz: int) -> Array:
	var out := []
	var line := ""
	for word in text.split(" "):
		var test := word if line == "" else line + " " + word
		if f_body.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > width and line != "":
			out.append(line)
			line = word
		else:
			line = test
	if line != "":
		out.append(line)
	return out
