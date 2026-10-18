extends Node
## [bugfix] Lux E double-cast probe. Part 1: ONE real E key press by the player (injected key event) must produce exactly one
## cast and no detonation until recast/5 s. Part 2: a bot-controlled Lux next to an enemy must cast E once, then detonate only
## after the orb landed. Prints LUXE lines.
## Usage: tools/preview.sh 120 -- --champ=Lux --harness=res://src/debug/lux_e_probe.gd
var match_ref = null
var main = null
var m = null
var c: Champion = null
var dets := []     ## [time, tag]
var casts := []    ## [time]


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _ready() -> void:
	_run()


func _key(code: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	ev.keycode = code
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _run() -> void:
	await _wait(1.0)
	m = G.match
	c = G.player
	if c.augments_pending > 0:
		m.get_offer(c)
		m.choose_augment(c, 0)
	var e = c.abilities[2]
	e.level = 1
	c.mana = 9999
	# park the bots away, make an enemy dummy target
	for ch in m.champions:
		if ch != c:
			ch.controller = null
			ch.teleport(ch.spawn_point)
	var dummy: Champion = null
	for ch in m.champions:
		if ch.team != c.team:
			dummy = ch
			break
	var spot: Vector3 = m.nav.nearest_walkable(c.global_position + Vector3(4, 0, 4))
	dummy.teleport(m.nav.nearest_walkable(c.global_position + G.flat_dir(c.global_position, m.nexus_units[1].global_position) * 7.0))
	var t0: float = m.time
	var cc0: int = e.cast_count
	var hp0: float = dummy.hp
	# one real key press (press, hold 0.15 s, release)
	_key(KEY_E, true)
	await _wait(0.15)
	_key(KEY_E, false)
	for i in 14:
		await _wait(0.1)
		print("LUXE player t=%.2f casts=%d recast_window=%.2f cd=%.2f zone_landed=%s hp_lost=%.0f" % [m.time - t0, e.cast_count - cc0, e.recast_window, e.cd, e.zone.get("landed", false) if not e.zone.is_empty() else "none", hp0 - dummy.hp])
	print("LUXE player RESULT casts_after_1_press=%d (want 1)  zone_still_out=%s" % [e.cast_count - cc0, not e.zone.is_empty()])
	# wait for auto-detonate
	await _wait(5.0)
	print("LUXE player auto: casts=%d zone_out=%s hp_lost=%.0f" % [e.cast_count - cc0, not e.zone.is_empty(), hp0 - dummy.hp])
	# part 2: the same Lux driven by a bot brain, enemy standing still in range
	e.cd = 0.0
	e.recast_window = 0.0
	e.zone = {}
	c.mana = 9999
	dummy.hp = dummy.stats.max_hp
	hp0 = dummy.hp
	cc0 = e.cast_count
	var bb := BotBrain.new()
	bb.setup(c, m)
	c.controller = bb
	var t1: float = m.time
	var prev_cc := cc0
	for i in 70:
		await _wait(0.1)
		if e.cast_count != prev_cc:
			print("LUXE bot cast #%d at t=%.2f (recast_window=%.2f landed=%s)" % [e.cast_count - cc0, m.time - t1, e.recast_window, e.zone.get("landed", "n/a") if not e.zone.is_empty() else "none"])
			prev_cc = e.cast_count
	print("LUXE bot RESULT casts_in_7s=%d hp_lost=%.0f" % [e.cast_count - cc0, hp0 - dummy.hp])
	# part 3: the race behind the "E casts forever" report: the singularity detonates by itself (5 s timer) inside the
	# recast's 0.25 s windup. The recast must then do nothing (it used to throw a FREE new orb, which the bot recast again...)
	c.controller = m.player_controller
	await _wait(1.0)
	e.cd = 0.0
	e.recast_window = 0.0
	e.zone = {}
	e.try_cast(e.make_target(dummy.global_position))
	await _wait(1.3)   # landed
	var cd_before: float = e.cd
	var c1: int = e.cast_count
	var ok: bool = e.try_cast(e.make_target(dummy.global_position))   # recast press ...
	e._detonate()                                              # ... and the timer fires inside its windup
	await _wait(0.6)
	print("LUXE race RESULT recast_started=%s new_zone_after_race=%s recast_window=%.2f cd_before=%.2f cd_after=%.2f (want: no new zone, cd unchanged)" % [ok, not e.zone.is_empty(), e.recast_window, cd_before, e.cd])
	get_tree().quit()
