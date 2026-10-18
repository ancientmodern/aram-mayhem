extends Node
## [ui-fix] Shop double-click / right-click QA (use with --harness=res://src/ui/hud/shop_dbl_test.gd).
## Real injected mouse events; checks that double-click buys on every item icon (grid, recipe tree incl. root, builds-into,
## search results, recommended cards + their component icons) and that single clicks only select. Prints SHOPDBL PASS/FAIL.
var main = null
var match_ref = null
var c: Champion = null
var shop = null
var fails := 0
var shot_dir := "user://shopdbl"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [shot_dir, name])
	print("SHOPDBL SHOT ", ProjectSettings.globalize_path(shot_dir + "/" + name + ".png"))


func _win(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _btn(p: Vector2, button: int, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = _win(p)
	ev.global_position = ev.position
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _win(p)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame


func _click(p: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	await _move(p)
	_btn(p, button, true)
	await get_tree().process_frame
	_btn(p, button, false)
	await get_tree().process_frame


## Two quick clicks at the same spot (the mouse does not move between them; the panel re-lays-out in between).
func _dbl(p: Vector2) -> void:
	await _move(p)
	for i in 2:
		_btn(p, MOUSE_BUTTON_LEFT, true)
		await get_tree().process_frame
		_btn(p, MOUSE_BUTTON_LEFT, false)
		await get_tree().process_frame


func _check(name: String, ok: bool, detail := "") -> void:
	print("SHOPDBL ", "PASS " if ok else "FAIL ", name, " ", detail)
	if not ok:
		fails += 1


func _reset(gold := 9000.0) -> void:
	c.items.clear()
	c.gold = gold


func _has(id: int) -> bool:
	for it in c.items:
		if it.item_id == id:
			return true
	return false


func _hit_rect(kind: String, id: int, right_panel: bool) -> Rect2:
	var split: float = shop.L.r("Shop:ItemShop_BuildsInto_Slot1").position.x - 4.0
	var best := Rect2()
	for h in shop._hits:
		if h[1] == kind and h[2] == id and ((h[0] as Rect2).position.x >= split) == right_panel:
			best = h[0]
	return best


func _run() -> void:
	await _wait(2.5)
	c = G.player
	var hud = match_ref.hud
	shop = hud.shop_panel
	c.gold = 9000.0
	await _move(Vector2(40, 40))
	var ev := InputEventKey.new()
	ev.keycode = KEY_P
	ev.physical_keycode = KEY_P
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	ev = ev.duplicate()
	ev.pressed = false
	Input.parse_input_event(ev)
	await _wait(0.6)
	_check("shop open", shop.visible)

	# --- recommended cards: card body + component icon ---
	_reset()
	var card_id := -1
	var card_r := Rect2()
	for h in shop._hits:
		if h[1] == "rec_item":
			card_id = h[2]
			card_r = h[0]
			break
	_check("rec card found", card_id >= 0)
	await _click(card_r.get_center() + Vector2(0, -40))
	_check("rec single click selects only", shop.selected == card_id and c.items.is_empty())
	await _wait(0.5)
	await _dbl(card_r.get_center() + Vector2(0, -40))
	await _wait(0.2)
	_check("rec double-click buys", _has(card_id) or c.items.size() > 0, "items=%d" % c.items.size())
	await _shot("1_rec_after_buy")
	# component icon inside a recommended card
	_reset()
	await _wait(0.5)
	var comp := -1
	var comp_r := Rect2()
	for h in shop._hits:
		if h[1] == "item" and (h[0] as Rect2).position.x < shop.L.r("Shop:ItemShop_BuildsInto_Slot1").position.x - 4.0:
			comp = h[2]
			comp_r = h[0]
			break
	if comp >= 0:
		await _dbl(comp_r.get_center())
		await _wait(0.2)
		_check("rec card component double-click buys that component", _has(comp), "comp=%d" % comp)

	# --- all items grid ---
	await _click(shop.L.r("Shop:ItemShop_TabButton_Default", Vector2(215, 0)).get_center())
	await _wait(0.4)
	_reset()
	var gid := 1052
	var gr := _hit_rect("item", gid, false)
	_check("grid item visible", gr.size.x > 0.0)
	await _click(gr.get_center())
	_check("grid single click only selects", shop.selected == gid and not _has(gid))
	await _wait(0.5)
	await _dbl(gr.get_center())
	await _wait(0.2)
	_check("grid double-click buys", _has(gid))
	_reset()

	# --- recipe tree: root, component ---
	shop.selected = 6655
	await _wait(0.3)
	await _shot("2_tree")
	var comps: Array = ItemDB.components_of(6655)
	var cr := _hit_rect("item", comps[0], true)
	_check("tree component visible", cr.size.x > 0.0, "comp=%d" % comps[0])
	var ctr := cr.get_center()
	await _click(ctr)
	_check("tree single click selects the component", shop.selected == comps[0] and not _has(comps[0]))
	await _wait(0.5)
	shop.selected = 6655
	await _wait(0.2)
	cr = _hit_rect("item", comps[0], true)
	await _dbl(cr.get_center())
	await _wait(0.2)
	_check("tree component double-click buys it", _has(comps[0]), "sel=%d items=%s gold=%d" % [shop.selected, c.items.map(func(i): return i.item_id), c.gold])
	_reset()
	shop.selected = 6655
	await _wait(0.3)
	# root of the tree (an item hit in the right panel with the selected id)
	var rr := _hit_rect("item", 6655, true)
	_check("tree root is clickable", rr.size.x > 0.0)
	if rr.size.x > 0.0:
		await _dbl(rr.get_center())
		await _wait(0.2)
		_check("tree root double-click buys the item", _has(6655))
	_reset()
	# right-click on a tree node buys it
	shop.selected = 6655
	await _wait(0.3)
	cr = _hit_rect("item", comps[0], true)
	await _click(cr.get_center(), MOUSE_BUTTON_RIGHT)
	await _wait(0.2)
	_check("tree node right-click buys", _has(comps[0]))

	# --- builds into row ---
	_reset()
	shop.selected = 1052
	await _wait(0.3)
	var into: Array = ItemDB.builds_into(1052)
	var br := _hit_rect("item", into[0], true)
	_check("builds-into item visible", br.size.x > 0.0, "id=%d" % into[0])
	await _shot("3_builds_into")
	await _dbl(br.get_center())
	await _wait(0.2)
	_check("builds-into double-click buys", _has(into[0]), "id=%d" % into[0])

	# --- search results ---
	_reset()
	shop.selected = -1
	for h in shop._hits:
		if h[1] == "search":
			await _click((h[0] as Rect2).get_center())
			break
	for ch in "lud":
		var k := InputEventKey.new()
		k.keycode = OS.find_keycode_from_string(ch.to_upper())
		k.physical_keycode = k.keycode
		k.unicode = ch.unicode_at(0)
		k.pressed = true
		Input.parse_input_event(k)
		await get_tree().process_frame
		k = k.duplicate()
		k.pressed = false
		Input.parse_input_event(k)
		await get_tree().process_frame
	await _wait(0.3)
	print("SHOPDBL search state: focus=", shop.search_focus, " search='", shop.search, "' tab=", shop.tab, " hits_search=", shop._hits.filter(func(h): return h[1] == "search").size())
	var sid := -1
	var sr := Rect2()
	var hs: Array = shop._hits.duplicate()
	hs.reverse()   # top-most first (the results dropdown is drawn after the grid)
	for h in hs:
		if h[1] == "item" and (h[0] as Rect2).position.x < shop.L.r("Shop:ItemShop_BuildsInto_Slot1").position.x - 4.0:
			sid = h[2]
			sr = h[0]
			break
	_check("search result visible", sid >= 0, "search='%s'" % shop.search)
	await _shot("4_search")
	if sid >= 0:
		await _dbl(sr.get_center())
		await _wait(0.2)
		_check("search double-click buys", c.items.size() > 0, "id=%d items=%d" % [sid, c.items.size()])
	print("SHOPDBL DONE fails=", fails)
	get_tree().quit()
