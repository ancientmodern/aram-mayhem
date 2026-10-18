class_name ControlTest
extends Node
## QA: injects real mouse/keyboard events and checks the player's champion responds like League.
## Usage: godot --path . [--headless] --fixed-fps 60 -- --champ=Ezreal --ctrltest

var m = null
var c: Champion = null
var pc: PlayerController = null
var fails := 0


func _ready() -> void:
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _check(name: String, ok: bool, detail: String = "") -> void:
	print("CTRL %s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if not ok:
		fails += 1


## World point -> window coordinates (input events are in window space; the root viewport is stretched).
func _screen(p: Vector3) -> Vector2:
	return get_viewport().get_final_transform() * pc.rig.cam.unproject_position(p)


func _mouse_to(p: Vector3) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _screen(p)
	ev.global_position = ev.position
	Input.parse_input_event(ev)


func _click(p: Vector3, button: int, pressed_only: bool = false) -> void:
	_mouse_to(p)
	await get_tree().process_frame
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.position = _screen(p)
	ev.global_position = ev.position
	ev.pressed = true
	Input.parse_input_event(ev)
	if pressed_only:
		return
	await get_tree().process_frame
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


func _key(code: Key, pressed: bool = true, release: bool = true) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)
	if pressed and release:
		await get_tree().process_frame
		var up := ev.duplicate()
		up.pressed = false
		Input.parse_input_event(up)


func _run() -> void:
	await _wait(1.0)
	m = G.match
	c = G.player
	pc = m.player_controller
	# skip the opening augment screen
	if c.augments_pending > 0:
		m.get_offer(c)
		m.choose_augment(c, 0)
	await _wait(0.3)
	# --- 1. right-click move
	var start := c.global_position
	var goal: Vector3 = m.nav.nearest_walkable(start + G.flat_dir(start, m.nexus_units[1].global_position) * 6.0)
	await _click(goal, MOUSE_BUTTON_RIGHT)
	await _wait(0.12)
	print("CTRL dbg goal=%s screen=%s vp_mouse=%s mouse_ground=%s vp=%s cmd=%d path_end=%s" % [goal, _screen(goal), get_viewport().get_mouse_position(),
			pc.mouse_ground, get_viewport().get_visible_rect().size, c.cmd, c.path[c.path.size() - 1] if c.path.size() > 0 else "none"])
	_check("move_starts_immediately", c.moving or G.flat_dist(c.global_position, start) > 0.2)
	await _wait(2.5)
	_check("move_arrives", G.flat_dist(c.global_position, goal) < 0.8, "dist=%.2f" % G.flat_dist(c.global_position, goal))
	# --- 2. S stops
	await _click(m.nexus_units[1].global_position, MOUSE_BUTTON_RIGHT)
	await _wait(0.3)
	await _key(KEY_S)
	await _wait(0.1)
	var p_stop := c.global_position
	await _wait(0.4)
	_check("stop_key", G.flat_dist(c.global_position, p_stop) < 0.05 and not c.moving)
	# --- 3. hold right mouse to follow the cursor
	var hold_goal: Vector3 = m.nav.nearest_walkable(c.global_position + Vector3(4, 0, 0))
	pc.rig.locked = false   # with a locked camera the cursor's ground point moves with the champion
	await _click(c.global_position + Vector3(-3, 0, 0), MOUSE_BUTTON_RIGHT, true)
	await _wait(0.3)
	# the camera follows the champion, so release right after the cursor reaches the goal
	_mouse_to(hold_goal)
	await _wait(0.15)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_RIGHT
	up.position = _screen(hold_goal)
	up.pressed = false
	Input.parse_input_event(up)
	await _wait(2.5)
	_check("hold_rmb_follows_cursor", G.flat_dist(c.global_position, hold_goal) < 0.6, "dist=%.2f" % G.flat_dist(c.global_position, hold_goal))
	pc.rig.locked = true
	# --- 4. deterministic arena: clear the lane, park the bots, pin one stunned enemy minion mid-lane
	m.game_speed = 3.0
	while m.time < 62.0:
		await _wait(0.2)
	m.game_speed = 1.0
	m.spawner = null
	var target: Unit = null
	for u in m.units.duplicate():
		if u.kind == G.Kind.MINION and not u.dead:
			if target == null and u.team != c.team:
				target = u
			else:
				m.remove_unit(u)
	for ch in m.champions:
		if ch != c:
			ch.controller = null
			ch.teleport(ch.spawn_point)
	if target == null:
		_check("found_enemy_minion", false)
		_finish()
		return
	var mid: Vector3 = (m.outer_turrets[0].global_position + m.outer_turrets[1].global_position) * 0.5
	mid = m.nav.nearest_walkable(mid)
	target.teleport(mid)
	target.hp = target.stats.max_hp
	K.stun(target, 30.0, null)
	c.teleport(m.nav.nearest_walkable(mid + G.flat_dir(mid, c.spawn_point) * 4.0))
	c.issue_stop()
	await _wait(0.3)
	# --- 5. right-click an enemy to attack it
	var hp0: float = target.hp
	_mouse_to(target.global_position)
	await get_tree().process_frame
	await get_tree().process_frame
	_check("hover_picks_enemy", pc.hovered == target, "hovered=%s" % (pc.hovered.display_name if pc.hovered else "none"))
	await _click(target.global_position, MOUSE_BUTTON_RIGHT)
	await _wait(0.1)
	_check("rclick_enemy_sets_target", c.attack_target == target)
	await _wait(2.0)
	_check("attack_deals_damage", target.dead or target.hp < hp0, "hp %.0f -> %.0f" % [hp0, target.hp])
	# --- 6. a move order replaces the attack order
	await _click(c.global_position + G.flat_dir(target.global_position, c.global_position) * 2.0, MOUSE_BUTTON_RIGHT)
	await _wait(0.05)
	_check("move_cancels_attack_cmd", c.cmd == Unit.Cmd.MOVE and c.attack_target == null)
	await _wait(0.8)
	# --- 7. quick cast Q at the enemy
	G.settings.cast_mode = 0
	c.mana = c.stats.max_mana
	var q: Ability = c.abilities[0]
	if q.level == 0:
		c.ability_points += 1
		c.level_ability(0)
	if not target.dead:
		_mouse_to(target.global_position)
		await get_tree().process_frame
		await _key(KEY_Q)
		await _wait(0.8)
		_check("quick_cast_q", q.cd > 0.0 or q.charges < q.max_charges, "cd=%.2f" % q.cd)
	# --- 8. A + left click near (not on) the enemy attacks it if in range, otherwise attack-moves
	c.issue_stop()
	if not target.dead:
		c.teleport(m.nav.nearest_walkable(target.global_position + G.flat_dir(target.global_position, c.spawn_point) * minf(c.attack_range_m(), 3.0)))
		await _wait(0.1)
		await _key(KEY_A, true, false)
		await get_tree().process_frame
		await get_tree().process_frame
		_check("a_shows_range_ring", pc._ind_range.visible)
		await _key(KEY_A, false)
		print("CTRL dbg dist=%.2f in_range=%s targetable=%s armed=%s" % [G.flat_dist(c.global_position, target.global_position), c.in_attack_range(target), target.is_targetable_by(c.team), pc.attack_move_armed])
		await _click(target.global_position + Vector3(1.5, 0, 1.5), MOUSE_BUTTON_LEFT)
		await _wait(0.15)
		_check("a_click_attacks", c.attack_target == target, "cmd=%d target=%s" % [c.cmd, c.attack_target.display_name if c.attack_target else "none"])
	# --- 9. Esc opens / closes the pause menu
	await _key(KEY_ESCAPE)
	await _wait(0.1)
	_check("esc_pauses", m.paused and m.pause_menu.visible)
	var t0: float = m.time
	await _wait(0.3)
	_check("pause_freezes_time", absf(m.time - t0) < 0.001)
	await _key(KEY_ESCAPE)
	await _wait(0.1)
	_check("esc_resumes", not m.paused and not m.pause_menu.visible)
	_finish()


func _finish() -> void:
	print("CTRL DONE fails=%d" % fails)
	get_tree().quit()
