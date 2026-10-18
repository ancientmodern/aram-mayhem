extends Node
## QA harness for the HUD + shop (use with --harness=res://src/ui/hud/hud_test.gd).
## Drives the real HUD with injected mouse / keyboard events and writes screenshots to user://hudtest.

var main = null
var match_ref = null
var shot_dir := "user://hudtest"
var c: Champion = null


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
	print("HUDTEST SHOT ", ProjectSettings.globalize_path(p))


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


func _run() -> void:
	await _wait(2.5)
	c = G.player
	var hud = match_ref.hud
	c.gold = 4200.0
	for i in 5:
		c.gain_xp(400.0)
	await _wait(0.3)
	if c.can_level_ability(0):
		c.level_ability(0)
	await _wait(0.5)
	await _shot("01_hud")
	# ability tooltip
	var qr: Rect2 = hud.L.r("PlayerFrame:Ability0_BorderAvailable")
	await _move(qr.get_center())
	await _wait(0.3)
	await _shot("02_ability_tip")
	# open the shop with P (keyboard path)
	await _move(Vector2(40, 40))
	await _key(KEY_P, 0)
	await _wait(0.6)
	await _shot("03_shop_recommended")
	var shop = hud.shop_panel
	# All Items tab by mouse
	var tab_r: Rect2 = shop.L.r("Shop:ItemShop_TabButton_Default", Vector2(215, 0))
	await _click(tab_r.get_center())
	await _wait(0.4)
	# hover an item for the tooltip
	for h in shop._hits:
		if h[1] == "item":
			await _move((h[0] as Rect2).get_center())
			break
	await _wait(0.3)
	await _shot("04_shop_all_items")
	# stat filter: Ability Power
	for h in shop._hits:
		if h[1] == "stat" and h[2] == 5:
			await _click((h[0] as Rect2).get_center())
			break
	await _wait(0.3)
	await _shot("05_shop_filter_ap")
	for h in shop._hits:
		if h[1] == "stat" and h[2] == 5:
			await _click((h[0] as Rect2).get_center())
			break
	# typing goes straight into the search box
	await _type("lud")
	await _wait(0.3)
	await _shot("06_shop_search")
	await _key(KEY_ESCAPE)
	# select a component and buy it with right-click, then the full item via the purchase button
	shop.selected = 1052
	await _wait(0.2)
	for h in shop._hits:
		if h[1] == "item" and h[2] == 1052:
			await _click((h[0] as Rect2).get_center(), MOUSE_BUTTON_RIGHT)
			break
	shop.selected = 6655
	await _wait(0.3)
	await _shot("07_shop_tree_owned_component")
	for h in shop._hits:
		if h[1] == "buy":
			await _click((h[0] as Rect2).get_center())
			break
	await _wait(0.3)
	await _shot("08_shop_bought")
	await _key(KEY_Z, 0, true)
	await _wait(0.3)
	await _shot("09_shop_undo")
	for h in shop._hits:
		if h[1] == "buy":
			await _click((h[0] as Rect2).get_center())
			break
	await _key(KEY_ESCAPE)
	await _wait(0.4)
	# inventory tooltip
	var ir: Rect2 = hud.L.r("Inventory:InventoryItem0_Backdrop")
	await _move(ir.get_center())
	await _wait(0.3)
	await _shot("10_item_tip")
	await _move(Vector2(640, 300))
	# kill feed + announcement (same signal order as Match._on_champion_killed)
	var enemy = null
	var ally = null
	for ch in match_ref.champions:
		if ch.team != c.team and enemy == null:
			enemy = ch
		elif ch.team == c.team and ch != c and ally == null:
			ally = ch
	G.champion_killed.emit(enemy, c, [ally])
	G.announce("First Blood!", "", G.COLOR_ALLY)
	await _wait(0.6)
	await _shot("11_kill_banner")
	# scoreboard while Tab is held
	Input.action_press("scoreboard")
	await _wait(0.4)
	await _shot("12_scoreboard")
	Input.action_release("scoreboard")
	await _wait(3.5)
	G.announce("Turret destroyed", "", G.COLOR_ALLY)
	await _wait(0.6)
	await _shot("13_banner_plain")
	# outside the fountain: open the shop with the HUD gold button (mouse path), try to buy -> ARAM lock
	c.global_position = c.spawn_point + (Vector3(64, 0, -64) - c.spawn_point).normalized() * 30.0
	c.issue_move(c.global_position)
	await _wait(0.5)
	var sb: Rect2 = hud.L.r("Inventory:Shop_HitArea")
	await _click(sb.get_center())
	await _wait(0.4)
	shop.selected = 1036
	for h in shop._hits:
		if h[1] == "buy":
			await _click((h[0] as Rect2).get_center())
			break
	await _wait(0.3)
	await _shot("15_shop_locked")
	await _key(KEY_ESCAPE)
	await _wait(0.3)
	# death: gray screen + respawn timer on the portrait
	c.die(enemy)
	await _wait(1.0)
	await _shot("14_dead")
	print("HUDTEST DONE")
	get_tree().quit()
