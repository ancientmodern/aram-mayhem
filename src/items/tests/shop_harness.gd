extends Node
## Shop QA: drives the real HUD shop with injected mouse / keyboard events, prints assertions ("SHOPTEST ...") and screenshots
## every shop state to user://<shotdir>.
##   tools/preview.sh 200 -- --sim --champ=Ahri --botplayer --seed=5 --harness=res://src/items/tests/shop_harness.gd --shotdir=shoptest --res=1920x1080

var main = null
var match_ref = null
var shot_dir := "user://shoptest"
var c: Champion = null
var shop = null
var hud = null
var fails := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = "user://" + a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var p := "%s/%s.png" % [shot_dir, name]
	img.save_png(p)
	print("SHOPTEST SHOT ", ProjectSettings.globalize_path(p))


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print("SHOPTEST %s %s" % ["ok  " if ok else "FAIL", what])


func _win(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _win(p)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await get_tree().process_frame
	await get_tree().process_frame


func _click(p: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	await _move(p)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = _win(p)
	ev.global_position = ev.position
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _key(code: Key, unicode := 0, ctrl := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.unicode = unicode
	ev.ctrl_pressed = ctrl
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await get_tree().process_frame


func _type(s: String) -> void:
	for ch in s:
		await _key(OS.find_keycode_from_string(ch.to_upper()), ch.unicode_at(0))


func _hit(kind: String, value = null) -> Rect2:
	for h in shop._hits:
		if h[1] == kind and (value == null or h[2] == value):
			return h[0]
	return Rect2()


func _process(_dt: float) -> void:
	if c != null and c.controller != null:
		c.controller = null           # the sim keeps re-attaching an AI brain; the shop QA drives the player by hand
	if c != null and not c.dead and _pin:
		c.global_position = c.spawn_point
		c.in_fountain = true


var _pin := true


func _click_hit(kind: String, value = null, button := MOUSE_BUTTON_LEFT) -> bool:
	var r := _hit(kind, value)
	if r.size.x <= 0.0:
		print("SHOPTEST no hit region ", kind, " ", value)
		return false
	await _click(r.get_center(), button)
	return true


func _owned_ids() -> Array:
	return c.items.map(func(it): return it.item_id)


func _open_tab(t: String) -> void:
	await _click_hit("tab", t)
	await _wait(0.3)


func _run() -> void:
	await _wait(2.5)
	c = G.player
	hud = match_ref.hud
	shop = hud.shop_panel
	c.controller = null          # no AI: the player stands on the spawn platform
	c.global_position = c.spawn_point
	while c.level < 9:
		c.gain_xp(500.0)
	await _wait(1.5)
	for it0 in c.items.duplicate():
		c.remove_item(it0)
	c.gold = 4200.0
	c.in_fountain = true
	await _wait(0.5)
	print("SHOPTEST start gold=%d items=%s level=%d pos_ok=%s ctrl=%s" % [c.gold, str(_owned_ids()), c.level, str(c.can_shop()), str(c.controller)])
	await _move(Vector2(40, 40))
	# ---- open with P
	await _key(KEY_P, 0)
	await _wait(0.6)
	_check(shop.visible, "P opens the shop")
	await _shot("01_recommended")
	# ---- tooltip hover on a suggested card
	var r := _hit("rec_item")
	if r.size.x > 0.0:
		await _move(r.get_center())
		await _wait(0.6)
		await _shot("02_rec_hover_tooltip")
	# ---- all items tab
	await _open_tab("all")
	await _move(Vector2(40, 40))
	await _wait(0.2)
	await _shot("03_all_items")
	var cell := _hit("item", 3031)
	if cell.size.x > 0.0:
		await _move(cell.get_center())
		await _wait(0.6)
		await _shot("04_hover_ie")
	# stat filter: Ability Power, class filter: Mage
	await _click_hit("stat", 5)
	await _wait(0.3)
	await _shot("05_filter_ap")
	await _click_hit("stat", 5)
	await _click_hit("type", 2)
	await _wait(0.3)
	await _shot("06_class_marksman")
	await _click_hit("type", 0)
	await _click_hit("popular")
	await _wait(0.3)
	await _shot("07_popular")
	await _click_hit("popular")
	await _click_hit("invert")
	await _wait(0.3)
	await _shot("08_inverted")
	await _click_hit("invert")
	# ---- scripted purchase sequence: components -> combine -> undo -> sell
	_check(not shop.session.can_undo(), "undo empty at start")
	var g0 := c.gold
	await _click_hit("item", 1036)          # select Long Sword
	_check(shop.selected == 1036, "left-click selects")
	await _click_hit("item", 1036, MOUSE_BUTTON_RIGHT)
	_check(_owned_ids().count(1036) == 1, "right-click buys Long Sword")
	await _click_hit("item", 1036, MOUSE_BUTTON_RIGHT)
	_check(_owned_ids().count(1036) == 2, "second Long Sword (duplicate component)")
	_check(is_equal_approx(g0 - c.gold, 700.0), "gold spent 700 (350 x 2)")
	shop.selected = 3133
	await _wait(0.3)
	await _shot("09_build_tree_owned_components")
	var price: int = ItemDB.price_for(c, 3133)[0]
	_check(price == ItemDB.combine_cost(3133) + ItemDB.cost_of(2022), "Caulfield's discounted price = combine + Glowing Mote (%d)" % price)
	var g1 := c.gold
	await _click_hit("buy")
	_check(_owned_ids().has(3133) and not _owned_ids().has(1036), "combine consumed both Long Swords")
	_check(is_equal_approx(g1 - c.gold, float(price)), "combine charged the discounted price")
	await _wait(0.3)
	await _shot("10_after_combine")
	await _click_hit("undo")
	_check(_owned_ids().count(1036) == 2 and not _owned_ids().has(3133), "undo restores the components")
	_check(is_equal_approx(c.gold, g1), "undo restores gold")
	await _wait(0.2)
	await _shot("11_after_undo")
	await _click_hit("undo")
	_check(_owned_ids().count(1036) == 1, "second undo removes the 2nd Long Sword")
	await _click_hit("undo")
	_check(c.items.is_empty() and is_equal_approx(c.gold, g0), "third undo back to start")
	# buy again and sell
	await _click_hit("item", 1052, MOUSE_BUTTON_RIGHT)
	await _click_hit("item", 3086, MOUSE_BUTTON_RIGHT)
	_check(_owned_ids().has(3086) or _owned_ids().has(1052), "bought Amplifying Tome / Zeal")
	var gs := c.gold
	var it = c.items[0]
	var sv := ItemDB.sell_price(it)
	var slot_r: Rect2 = hud.L.r("Inventory:InventoryItem0_Backdrop")
	await _click(slot_r.get_center())      # select owned item via the HUD inventory
	await _wait(0.2)
	await _shot("12_sell_selected")
	await _click_hit("sell")
	_check(not (it in c.items) and is_equal_approx(c.gold, gs + sv), "sell gives %d gold" % sv)
	# partial combine: Zhonya's needs NLR + Seeker's -> with 200 gold the shop buys components
	c.gold = 1500.0
	shop.selected = 3157
	await _wait(0.3)
	await _shot("13_purchase_components_state")
	var before := c.items.size()
	await _click_hit("buy")
	_check(c.items.size() > before, "PURCHASE COMPONENTS bought %d parts" % (c.items.size() - before))
	await _wait(0.3)
	await _shot("14_components_bought")
	# ---- search
	c.gold = 5000.0
	await _click_hit("search")
	await _type("ie")
	await _wait(0.3)
	_check(shop.selected == 3031, "search 'ie' selects Infinity Edge (nickname)")
	await _shot("15_search_ie")
	await _key(KEY_ESCAPE)
	await _click_hit("search")
	await _type("bc")
	await _wait(0.3)
	_check(shop.selected == 3071, "search 'bc' -> Black Cleaver")
	await _key(KEY_ESCAPE)
	await _click_hit("search")
	await _type("armor")
	await _wait(0.3)
	await _shot("16_search_stat_armor")
	await _key(KEY_ESCAPE)
	# ---- item sets tab
	await _open_tab("sets")
	await _shot("17_item_sets")
	# ---- quick panels
	await _open_tab("all")
	await _click_hit("panel_tab", "cons")
	await _wait(0.3)
	await _click_hit("panel_tab", "boots")
	await _wait(0.3)
	await _click_hit("panel_tab", "inv")
	await _wait(0.4)
	await _shot("18_quick_panels")
	var bootr := _hit("item", 3006)
	if bootr.size.x > 0.0:
		await _move(bootr.get_center())
		await _wait(0.6)
		await _shot("19_boots_tooltip")
	await _click_hit("item", 1001, MOUSE_BUTTON_RIGHT)
	_check(_owned_ids().has(1001), "quick-buy Boots from the boots panel")
	await _click_hit("item", 3006, MOUSE_BUTTON_RIGHT)
	_check(_owned_ids().has(3006) and not _owned_ids().has(1001), "Boots upgraded to Berserker's by right-click")
	_check(ItemDB.buy_block_reason(c, 3020) == "unique", "second boots blocked (item group limit)")
	await _click_hit("item", 2003, MOUSE_BUTTON_RIGHT)
	await _click_hit("item", 2003, MOUSE_BUTTON_RIGHT)
	var pot = null
	for it2 in c.items:
		if it2.item_id == 2003:
			pot = it2
	_check(pot != null and int(pot.get("stacks")) == 2, "two Health Potions stack in one slot")
	await _wait(0.3)
	await _shot("20_consumables_stack")
	await _click_hit("panel_pin", "inv")
	await _key(KEY_ESCAPE)
	_check(not shop.visible, "Esc closes the shop")
	# ---- locked state outside the base
	_pin = false
	c.global_position = c.spawn_point + Vector3(60, 0, -60)
	c.in_fountain = false
	await _key(KEY_P, 0)
	await _wait(0.4)
	shop.selected = 3031
	await _wait(0.3)
	await _shot("21_locked_away_from_base")
	var gold_before := c.gold
	await _click_hit("buy")
	_check(is_equal_approx(c.gold, gold_before), "cannot buy away from the fountain")
	# ---- dead players can shop
	c.dead = true
	await _wait(0.3)
	var st: Dictionary = shop.session.button_state(c, 3031)
	_check(st.enabled or st.reason == "gold" or st.reason == "full", "dead champion may shop (%s)" % st.label)
	c.dead = false
	await _key(KEY_ESCAPE)
	await _wait(0.3)
	# ---- drag-to-sell overlay
	_pin = true
	c.in_fountain = true
	await _key(KEY_P, 0)
	await _wait(0.4)
	hud._drag = {"slot": 0, "start": Vector2(500, 900), "active": true}
	hud._mouse = shop.panel.get_center()
	shop._mouse = shop.panel.get_center()
	await _wait(0.3)
	await _shot("22_sell_overlay")
	hud._drag = {}
	await _key(KEY_ESCAPE)
	print("SHOPTEST DONE fails=%d" % fails)
	get_tree().quit()
