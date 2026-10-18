extends Node
## [bugfix] Input-repeat audit: for the player's champion and each of Q/W/E/R, in every cast mode (quick / quick with
## indicator / normal), presses the key and HOLDS it for 2 s (with OS-style echo events) and checks the ability cast
## exactly once (one press = one cast; recast abilities may only recast on a NEW press). Prints KEYHOLD lines.
## Usage: godot --headless --path . --fixed-fps 60 -- --champ=Lux --harness=res://src/debug/key_hold_test.gd
var match_ref = null
var main = null
var m = null
var c: Champion = null
var pc = null
var fails := 0


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _ready() -> void:
	_run()


func _screen(p: Vector3) -> Vector2:
	return get_viewport().get_final_transform() * pc.rig.cam.unproject_position(p)


func _mouse_to(p: Vector3) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = _screen(p)
	ev.global_position = ev.position
	Input.parse_input_event(ev)


func _key(code: Key, pressed: bool, echo: bool = false) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	ev.echo = echo
	Input.parse_input_event(ev)


func _click(p: Vector3) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.position = _screen(p)
	ev.global_position = ev.position
	ev.pressed = true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)


func _run() -> void:
	await _wait(1.0)
	m = G.match
	c = G.player
	pc = m.player_controller
	if c.augments_pending > 0:
		m.get_offer(c)
		m.choose_augment(c, 0)
	m.spawner = null
	for u in m.units.duplicate():
		if u.kind == G.Kind.MINION:
			m.remove_unit(u)
	for ch in m.champions:
		if ch != c:
			ch.controller = null
	var foes: Array = m.champions.filter(func(e): return e.team != c.team)
	var axis := G.flat_dir(c.global_position, m.nexus_units[1].global_position)
	var spot: Vector3 = m.nav.nearest_walkable(m.lane_path[m.lane_path.size() / 2])   # mid lane: no turrets / fountains
	pc.rig.locked = true
	var keys := [KEY_Q, KEY_W, KEY_E, KEY_R]
	for mode in [0, 1, 2]:
		G.settings["cast_mode"] = mode
		for slot in 4:
			var ab: Ability = c.abilities[slot]
			if ab == null:
				continue
			# fresh arena
			for f in foes:
				if f.dead:
					f.respawn()
				f.hp = f.stats.max_hp
				f.cleanse()
			if c.dead:
				c.respawn()
			c.cleanse()
			c.level = maxi(c.level, 6)
			ab.level = maxi(ab.level, 1)
			ab.cd = 0.0
			ab.recast_window = 0.0
			ab.sealed = false
			c.mana = c.stats.max_mana
			c.hp = c.stats.max_hp
			c.teleport(m.nav.nearest_walkable(spot - axis * 6.0))
			c.issue_stop()
			for i in foes.size():
				foes[i].teleport(m.nav.nearest_walkable(spot + axis * 2.0 * i + Vector3(0, 0, i * 0.5)))
				foes[i].issue_hold()
			c.face_toward(spot, 100.0)
			await _wait(0.9)   # let the locked camera settle on the champion before aiming the cursor
			var aim_pos: Vector3 = foes[0].global_position
			_mouse_to(aim_pos)
			await get_tree().process_frame
			await get_tree().process_frame
			var n0: int = ab.cast_count
			var cd0 := ab.cd
			_key(keys[slot], true)
			if mode == 2:
				await get_tree().process_frame
				await _click(aim_pos)
			var t_end: float = m.time + 2.0
			while m.time < t_end:
				await _wait(0.033)
				_key(keys[slot], true, true)   # OS key repeat
			_key(keys[slot], false)
			await _wait(0.3)
			var n: int = ab.cast_count - n0
			var ok := n <= 1
			var tag := "OK" if ok else "FAIL"
			if n == 0:
				tag = "WARN(no cast)"
			if not ok:
				fails += 1
			print("KEYHOLD %s %s mode=%d slot=%d casts=%d toggled=%s recast_window=%.1f" % [tag, c.alias, mode, slot, n, ab.get("toggled"), ab.recast_window])
	print("KEYHOLD DONE %s fails=%d" % [c.alias, fails])
	get_tree().quit()
