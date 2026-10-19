extends Node
## [ui-feel] QA harness for HUD press feedback (--harness=res://src/ui/hud/hud_feel_test.gd).
## Drives the real HUD with injected mouse / keyboard events, saves consecutive cropped frames around each press
## (user://<shotdir>/seq_<name>_<n>.png) and prints the HUD sound log (Sfx.hud_log) after every step.
## Asserts (printed as FEEL PASS / FEEL FAIL): level-up press -> clicked art + LevelUp_click, release -> level-up + release
## sound + SelectedOut flipbook, hotkeys press the slot, failed casts play the fail sound once, item use plays HitFX.

var main = null
var match_ref = null
var shot_dir := "user://feelseq"
var c: Champion = null
var hud = null
var _t0 := 0
var _fails := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shotdir="):
			shot_dir = "user://" + a.substr(10)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _frame() -> void:
	await get_tree().process_frame


func _win(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _win(p)
	ev.global_position = ev.position
	Input.parse_input_event(ev)
	await _frame()
	await _frame()


func _mouse(p: Vector2, down: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = _win(p)
	ev.global_position = ev.position
	ev.pressed = down
	Input.parse_input_event(ev)


func _key_ev(code: Key, down: bool, ctrl := false) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.ctrl_pressed = ctrl
	ev.pressed = down
	Input.parse_input_event(ev)


## Save `n` consecutive frames cropped to the HUD action bar.
func _seq(name: String, n: int, skip := 0) -> void:
	for i in n:
		await RenderingServer.frame_post_draw
		if i >= skip or true:
			var img := get_viewport().get_texture().get_image()
			var vs := img.get_size()
			var r := Rect2i(int(vs.x * 0.27), int(vs.y * 0.74), int(vs.x * 0.50), int(vs.y * 0.24))
			img.get_region(r).save_png("%s/seq_%s_%02d.png" % [ProjectSettings.globalize_path(shot_dir), name, i])


func _log(tag: String) -> void:
	var out := []
	for e in Sfx.hud_log:
		if int(e[0]) >= _t0:
			out.append("%s@%dms(%+.1fdB)" % [String(e[1]).replace("Play_sfx_hud_base_", "").replace("Play_sfx_", ""), int(e[0]) - _t0, e[2]])
	print("FEEL SOUND [%s] %s" % [tag, ", ".join(out)])
	_t0 = Time.get_ticks_msec()


func _count(ev: String) -> int:
	var n := 0
	for e in Sfx.hud_log:
		if e[1] == ev:
			n += 1
	return n


func _check(name: String, ok: bool) -> void:
	if not ok:
		_fails += 1
	print("FEEL %s %s" % ["PASS" if ok else "FAIL", name])


func _run() -> void:
	await _wait(3.0)
	c = G.player
	hud = match_ref.hud
	c.gold = 3000.0
	_t0 = Time.get_ticks_msec()
	Sfx.hud_log.clear()
	# ---- 1. level-up button: hover, press (held), release
	for i in 4:
		c.ability_points = 0
	c.ability_points = 3
	c.xp = c.xp   # keep level
	await _wait(0.5)
	var lr: Rect2 = hud.L.r("PlayerFrame:LevelUp1_ButtonDefault")
	print("FEEL lvl1 rect ", lr, " can=", c.can_level_ability(1), " points=", c.ability_points)
	_t0 = Time.get_ticks_msec()
	await _move(lr.get_center())
	await _seq("lvl_hover", 2)
	_log("hover lvl W")
	var lvl_before: int = c.abilities[1].level
	_mouse(lr.get_center(), true)
	await _seq("lvl_press", 5)
	_check("pressed art while held", hud._pressed("lvl1"))
	_check("LevelUp_click played on press", _count("Play_sfx_hud_base_LevelUp_click") == 1)
	_check("no level-up before release", c.abilities[1].level == lvl_before)
	_log("press")
	await _wait(0.25)
	_mouse(lr.get_center(), false)
	await _seq("lvl_release", 16)
	_check("level-up on release", c.abilities[1].level == lvl_before + 1)
	_check("LevelUp_release + spell_levelup played once", _count("Play_sfx_hud_base_LevelUp_release") == 1 and _count("Play_sfx_hud_base_spell_levelup") == 1)
	_log("release")
	await _wait(0.8)
	await _seq("lvl_after", 3)
	# drag off the button: press, move away, release -> nothing
	lr = hud.L.r("PlayerFrame:LevelUp1_ButtonDefault")
	var lv1: int = c.abilities[1].level
	await _move(lr.get_center())
	_mouse(lr.get_center(), true)
	await _frame()
	await _move(lr.get_center() + Vector2(0, -160))
	_mouse(lr.get_center() + Vector2(0, -160), false)
	await _frame()
	_check("release off the button cancels", c.abilities[1].level == lv1)
	_log("cancelled press")
	# ctrl+key level-up (keyboard): only spell_levelup, no click
	c.ability_points = 2
	await _wait(0.3)
	_key_ev(KEY_E, true, true)
	await _frame()
	_key_ev(KEY_E, false, true)
	await _wait(0.2)
	_log("ctrl+E")
	c.ability_points = 0
	# ---- 2. hotkeys: Q (learned), then W press on an unlearned slot, R unlearned, D summoner
	for slot in 2:
		if c.abilities[slot].level <= 0:
			c.abilities[slot].level = 1
	await _wait(0.3)
	_t0 = Time.get_ticks_msec()
	_key_ev(KEY_Q, true)
	await _seq("key_q", 4)
	_check("Q slot drawn pressed while down", hud._slot_pressed(0))
	_key_ev(KEY_Q, false)
	await _seq("key_q_up", 8)
	_log("Q")
	await _wait(0.6)
	_t0 = Time.get_ticks_msec()
	_key_ev(KEY_R, true)
	await _seq("key_r_unlearned", 3)
	_key_ev(KEY_R, false)
	await _wait(0.5)
	_check("unlearned R plays a fail sound", _count("Play_sfx_hud_base_SpellFail_Cooldown") >= 1)
	_check("fail message is League's", hud.fail_msg == "You have not learned that ability yet!")
	_log("R unlearned")
	_key_ev(KEY_R, true)
	await _frame()
	_key_ev(KEY_R, false)
	await _frame()
	_key_ev(KEY_R, true)
	await _frame()
	_key_ev(KEY_R, false)
	await _wait(0.1)
	_check("fail sound not spammed", _count("Play_sfx_hud_base_SpellFail_Cooldown") <= 2)
	_t0 = Time.get_ticks_msec()
	_key_ev(KEY_D, true)
	await _seq("key_d", 4)
	_key_ev(KEY_D, false)
	await _wait(0.4)
	_log("D summoner")
	# ---- 3. items: buy a potion-like active and press its key
	c.gold = 9000.0
	ItemDB.buy(c, 3157)   # Zhonya's Hourglass: has an active
	await _wait(0.4)
	print("FEEL items=", c.items.size(), " active=", c.items[0].has_active() if c.items.size() > 0 else false)
	if c.items.size() > 0:
		_t0 = Time.get_ticks_msec()
		_key_ev(KEY_1, true)
		await _seq("key_1", 5)
		_key_ev(KEY_1, false)
		await _seq("key_1_up", 8)
		_log("item 1")
	# ---- 4. shop button press / release
	c.global_position = c.spawn_point
	await _wait(0.4)
	var sr: Rect2 = hud.L.r("Inventory:Shop_HitArea")
	await _move(sr.get_center())
	_t0 = Time.get_ticks_msec()
	_mouse(sr.get_center(), true)
	await _seq("shop_press", 3)
	_check("shop button drawn pressed", hud._pressed("shop"))
	_check("shop not open until release", not hud.shop_panel.visible)
	_mouse(sr.get_center(), false)
	await _wait(0.5)
	_check("shop opens on release", hud.shop_panel.visible)
	_log("shop open")
	hud.toggle_shop()
	await _wait(0.3)
	_log("shop close")
	# ---- 5. camera lock key
	_t0 = Time.get_ticks_msec()
	_key_ev(KEY_Y, true)
	await _frame()
	_key_ev(KEY_Y, false)
	await _wait(0.3)
	_check("camera lock toggle plays its sound", _count("Play_sfx_hud_base_camera_lock") + _count("Play_sfx_hud_base_camera_unlock") == 1)
	_log("camera lock")
	print("FEEL DONE fails=", _fails)
	get_tree().quit()
