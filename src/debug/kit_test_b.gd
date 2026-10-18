extends Node
## QA harness (kits-b): casts every ability of the player's champion onto parked enemy dummies and checks
## damage, buffs (applied and later removed), crowd control, channel/recast cleanup and lingering VFX.
## Usage: godot --headless --path . --fixed-fps 60 -- --champ=<Alias> --harness=res://src/debug/kit_test_b.gd
## Supported: Lux, Malphite, MasterYi, MissFortune, Sona, Veigar, Yasuo (others get the generic pass).

var main = null
var match_ref = null

var m = null
var c: Champion = null
var foes: Array = []          ## [A, B] enemy champion dummies
var spot := Vector3.ZERO      ## arena centre (A stands here)
var axis := Vector3.RIGHT     ## player -> dummies direction
var side := Vector3.FORWARD
var fails := 0
var passes := 0
var rec: Array = []           ## damage records from the player


class Recorder extends Effect:
	var sink: Array

	func _init(s: Array) -> void:
		sink = s
		id = "kitb_recorder"
		hidden = true

	func on_damage_dealt(info) -> void:
		sink.append({"tag": info.tag, "ab": info.ability, "t": info.target, "amt": info.final + info.absorbed,
				"attack": info.is_attack, "time": owner.match_ref.time if owner.match_ref != null else 0.0})


func _ready() -> void:
	# watchdog: a broken match (compile errors elsewhere) or a stuck scenario must not hang the run
	get_tree().create_timer(300.0, true, false, true).timeout.connect(func():
		print("KITB FAIL watchdog timeout (passes=%d fails=%d)" % [passes, fails + 1])
		get_tree().quit(2))
	_run()


func _wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func _check(name: String, ok: bool, detail: String = "") -> void:
	print("KITB %s %s %s %s" % ["PASS" if ok else "FAIL", c.alias if c != null else "?", name, detail])
	if ok:
		passes += 1
	else:
		fails += 1


# ===================================================================== arena
func _setup() -> void:
	m = G.match
	c = G.player
	if c.augments_pending > 0 and m.has_method("get_offer"):
		m.get_offer(c)
		m.choose_augment(c, 0)
	m.spawner = null
	for u in m.units.duplicate():
		if u.kind == G.Kind.MINION:
			m.remove_unit(u)
	for ch in m.champions:
		if ch != c:
			ch.controller = null
			ch.issue_stop()
			ch.teleport(ch.spawn_point)
	spot = m.nav.nearest_walkable((m.outer_turrets[0].global_position + m.outer_turrets[1].global_position) * 0.5)
	axis = G.flat_dir(c.spawn_point, spot)
	side = Vector3(-axis.z, 0, axis.x)
	for ch in m.champions:
		if ch.team != c.team and foes.size() < 2:
			foes.append(ch)
			# tanky dummies so a full combo never kills them by accident
			var hb := Buff.new("kitb_hp", 1.0)
			hb.permanent = true
			hb.hidden = true
			hb.stats = {"hp": 20000.0}
			ch.add_buff(hb, ch)
	while c.level < 18:
		c.level_up()
	c.auto_level_abilities()
	for f in foes:
		while f.level < 18:
			f.level_up()
	c.add_effect(Recorder.new(rec))
	for f in foes:
		_disarm(f)
		_neutralize(f)


## Dummies are real enemy champions: strip their own kit effects (passives such as Miss Fortune's Strut,
## Garen's Perseverance regen glow, Malphite's Granite Shield) and the visuals those already attached, so the
## lingering-VFX checks only see what the tested champion applied.
func _neutralize(d) -> void:
	for e in d.effects.duplicate():
		if e.id != "mayhem_aura" and not e.id.begins_with("harness") and not e.id.begins_with("kitb"):
			d.remove_effect(e)
	var nodes := []
	_collect_fx(d, nodes)
	for n in nodes:
		n.queue_free()


func _collect_fx(root: Node, out: Array) -> void:
	for ch in root.get_children():
		if ch is LolVfx or ch is VfxNode:
			out.append(ch)
		else:
			_collect_fx(ch, out)


## Hidden, permanent disarm so idle auto-attacks never interfere with a check (removed by _attack()).
func _disarm(u) -> void:
	if u.find_buff("kitb_disarm") != null:
		return
	var b := Buff.new("kitb_disarm", 1.0)
	b.permanent = true
	b.hidden = true
	b.cleansable = false
	b.cc = Buff.CC.DISARM
	u.add_buff(b, u)


func _attack(t) -> void:
	c.remove_buffs_by_id("kitb_disarm")
	c.issue_attack(t)


func _stop_attack() -> void:
	c.issue_hold()
	c.attack_target = null
	_disarm(c)


## Player `dist` meters in front of dummy A (B stands `b_off` meters behind A along the cast axis, offset sideways).
func _place(dist: float, b_back: float = 1.2, b_side: float = 0.6) -> void:
	for f in foes:
		f.cleanse()
		for b in f.buffs.duplicate():
			if not b.id.begins_with("kitb_"):
				f.remove_buff(b)
		f.shields.clear()
		f.recompute_stats()
		f.hp = f.stats.max_hp
		f.issue_hold()
		f.attack_target = null
	foes[0].teleport(spot)
	foes[1].teleport(m.nav.nearest_walkable(spot + axis * b_back + side * b_side))
	c.teleport(m.nav.nearest_walkable(spot - axis * dist))
	_stop_attack()
	c.face_toward(spot, 100.0)
	c.hp = c.stats.max_hp
	c.mana = c.stats.max_mana


func _ab(slot: int) -> Ability:
	return c.abilities[slot]


func _ready_ab(slot: int) -> Ability:
	var a := _ab(slot)
	a.cd = 0.0
	if a.max_charges > 0:
		a.charges = a.max_charges
	c.mana = c.stats.max_mana
	return a


func _cast(slot: int, pos: Vector3, unit = null) -> bool:
	var a := _ready_ab(slot)
	var t := a.make_target(pos, unit)
	return a.try_cast(t)


## Damage dealt since record index `from` matching `tag` ("" = any) on `target` (null = any).
func _dmg(from: int, tag: String = "", target = null) -> float:
	var s := 0.0
	for i in range(from, rec.size()):
		var r: Dictionary = rec[i]
		if (tag == "" or r.tag == tag) and (target == null or r.t == target):
			s += r.amt
	return s


func _dmg_ab(from: int, slot: int, target = null) -> float:
	var s := 0.0
	var a := _ab(slot)
	for i in range(from, rec.size()):
		var r: Dictionary = rec[i]
		if r.ab == a and (target == null or r.t == target):
			s += r.amt
	return s


func _airborne(u) -> bool:
	return (u.cc & Buff.CC.AIRBORNE) != 0


# ===================================================================== lingering VFX
func _fx_name(n: Node) -> String:
	var nm := String(n.name)
	if not nm.begins_with("@") or not (n is LolVfx):
		return nm
	for k in LolVfx._db:
		if is_same(LolVfx._db[k], n.def):
			return String(k)
	return nm


## Live looping League effects (and generic VfxNodes) attached to `u`.
func _attached_fx(u: Node) -> Array:
	var out := []
	for ch in u.get_children():
		if ch is LolVfx:
			if ch.get("_loop") and not ch.get("_stopped"):
				out.append(_fx_name(ch))
		elif ch is VfxNode and ch.is_processing() and ch.lifetime <= 0.0:
			out.append("VfxNode")
	return out


func _world_loops() -> Array:
	var out := []
	for ch in m.fx_root.get_children():
		if ch is LolVfx and ch.get("_loop") and not ch.get("_stopped"):
			out.append(_fx_name(ch))
	return out


## Allowed persistent effects on the player (passive state indicators).
func _allowed(nm: String) -> bool:
	for k in ["MissFortune_Base_W_Max", "MissFortune_Base_P_Buff", "Sona_Base_Q_PCReady", "Sona_Base_W_PCReady",
			"Sona_Base_E_PCReady", "VfxNode"]:
		if nm.begins_with(k):
			return true
	return false


func _check_no_linger(label: String) -> void:
	var bad := []
	for f in foes:
		for n in _attached_fx(f):
			bad.append("%s@%s" % [n, f.display_name])
		for b in f.buffs:
			if not b.id.begins_with("kitb_"):
				bad.append("buff:%s@%s" % [b.id, f.display_name])
	for n in _attached_fx(c):
		if not _allowed(n):
			bad.append("%s@self" % n)
	for n in _world_loops():
		bad.append("%s@world" % n)
	_check("no_linger_" + label, bad.is_empty(), str(bad))


# ===================================================================== run
func _run() -> void:
	await _wait(1.0)
	if G.match == null or G.player == null:
		print("KITB FAIL no match / player (passes=0 fails=1)")
		get_tree().quit(2)
		return
	_setup()
	await _wait(0.3)
	var alias: String = c.alias
	print("KITB START %s level=%d ranks=%s" % [alias, c.level, [_ab(0).level, _ab(1).level, _ab(2).level, _ab(3).level]])
	match alias:
		"Lux": await _lux()
		"Malphite": await _malphite()
		"MasterYi": await _yi()
		"MissFortune": await _mf()
		"Sona": await _sona()
		"Veigar": await _veigar()
		"Yasuo": await _yasuo()
		_: await _generic()
	await _melee_combo()
	# everything must be gone once effects have run out
	_place(6.0)
	await _wait(7.5)
	_check_no_linger("final")
	await _death_cleanup()
	print("KITB DONE %s passes=%d fails=%d timers=%d tickers=%d missiles=%d" % [alias, passes, fails, m._timers.size(), m.tickers.size(), m.missiles.size()])
	get_tree().quit()


## Free fight: basic attacks on A while every ability is cast (on-hit / proc interactions), then settle.
func _melee_combo() -> void:
	var a = foes[0]
	_place(c.attack_range_m() * 0.8 + 0.5)
	await _wait(0.2)
	_attack(a)
	for round in 2:
		for s in 4:
			var ab := _ab(s)
			if ab.target_type == Ability.Target.UNIT and ab.target_side != Ability.Side.ENEMY:
				_cast(s, c.global_position, c)
			else:
				_cast(s, a.global_position, a)
			await _wait(0.7)
			if c.attack_target == null and c.channel.is_empty():
				_attack(a)
	await _wait(1.5)
	_stop_attack()
	c.interrupt_channel(true)


## Kill dummy A while it carries debuffs; its attached effects must go with them.
func _death_cleanup() -> void:
	var a = foes[0]
	_place(5.0)
	await _wait(0.2)
	for s in 4:
		var ab := _ab(s)
		if ab.target_type == Ability.Target.UNIT and ab.target_side == Ability.Side.ENEMY:
			_cast(s, a.global_position, a)
		elif ab.target_type != Ability.Target.UNIT:
			_cast(s, a.global_position, a)
		await _wait(0.5)
	await _wait(0.4)
	a.die(c)
	await _wait(0.2)
	var bad := _attached_fx(a)
	_check("death_clears_fx", bad.is_empty() and a.buffs.filter(func(b): return not b.id.begins_with("kitb_")).is_empty(), str(bad))
	a.respawn()
	await _wait(0.2)


func _generic() -> void:
	for s in 4:
		_place(4.5)
		await _wait(0.2)
		var i0 := rec.size()
		_cast(s, foes[0].global_position, foes[0])
		await _wait(2.0)
		_check("cast_%s" % "QWER"[s], true, "dmg=%.0f" % _dmg_ab(i0, s))


# ===================================================================== Lux
func _lux() -> void:
	var a = foes[0]
	var b = foes[1]
	# Q: damage, root on two units, Illumination mark
	_place(6.0, 1.0, 0.0)
	await _wait(0.2)
	var i0 := rec.size()
	_cast(0, a.global_position)
	await _wait(0.9)
	_check("q_damage", _dmg(i0, "q", a) > 0.0, "%.0f" % _dmg(i0, "q", a))
	_check("q_root_first", a.has_buff("root"))
	_check("q_root_second", b.has_buff("root"), "second target behind")
	_check("q_mark", a.has_buff("lux_illum"))
	await _wait(2.0)
	_check("q_root_expires", not a.has_buff("root") and _attached_fx(a).is_empty(), str(_attached_fx(a)))
	# passive detonation by a basic attack
	c.teleport(m.nav.nearest_walkable(spot - axis * 4.0))
	i0 = rec.size()
	_attack(a)
	await _wait(1.6)
	_stop_attack()
	_check("p_detonate", _dmg(i0, "lux_passive", a) > 0.0 and not a.has_buff("lux_illum"), "%.0f" % _dmg(i0, "lux_passive", a))
	# W: self shield, then it ends
	_place(6.0)
	await _wait(0.2)
	_cast(1, spot)
	await _wait(0.4)
	_check("w_shield", c.total_shield() > 0.0, "%.0f" % c.total_shield())
	await _wait(3.5)
	_check("w_shield_ends", c.total_shield() <= 0.0 and _attached_fx(c).filter(func(n): return n.contains("W_tar")).is_empty())
	# E: slow zone then recast detonation
	_place(7.0)
	await _wait(0.2)
	i0 = rec.size()
	_cast(2, a.global_position)
	await _wait(1.0)
	_check("e_zone_slow", a.has_buff("lux_e_slow"))
	_check("e_recast_window_cd_on_cast", _ab(2).recast_window > 0.0 and _ab(2).cd > 0.0)
	_ab(2).try_cast(_ab(2).make_target(a.global_position))
	await _wait(0.5)
	_check("e_detonate", _dmg(i0, "e", a) > 0.0 and _ab(2).cd > 0.0 and _ab(2).recast_window <= 0.0, "%.0f" % _dmg(i0, "e", a))
	# E without recast detonates on its own
	_place(7.0)
	await _wait(0.2)
	i0 = rec.size()
	_cast(2, a.global_position)
	await _wait(6.3)
	_check("e_auto_detonate", _dmg(i0, "e", a) > 0.0, "%.0f" % _dmg(i0, "e", a))
	# R: beam through both dummies after the 1 s charge
	_place(10.0)
	await _wait(0.2)
	i0 = rec.size()
	_cast(3, a.global_position)
	await _wait(0.6)
	_check("r_not_yet", _dmg(i0, "r") == 0.0)
	await _wait(0.9)
	_check("r_damage_both", _dmg(i0, "r", a) > 0.0 and _dmg(i0, "r", b) > 0.0)
	_check("r_marks", a.has_buff("lux_illum"))
	# R interrupted during the charge: no damage, beam effect removed
	_place(10.0)
	await _wait(0.2)
	i0 = rec.size()
	_cast(3, a.global_position)
	await _wait(0.3)
	K.stun(c, 1.0, a)
	await _wait(1.5)
	_check("r_interrupt", _dmg(i0, "r") == 0.0 and _ab(3).get("_beam_fx") == null)


# ===================================================================== Malphite
func _malphite() -> void:
	var a = foes[0]
	var b = foes[1]
	_place(6.0)
	c.passive.last_hit = -100.0
	await _wait(0.3)
	_check("p_shield_up", c.passive.is_active())
	# Q
	var i0 := rec.size()
	_cast(0, a.global_position, a)
	await _wait(1.0)
	_check("q_damage", _dmg(i0, "malph_q", a) > 0.0)
	_check("q_slow_steal", a.has_buff("malph_q_slow") and c.has_buff("malph_q_ms"))
	await _wait(3.0)
	_check("q_buffs_end", not a.has_buff("malph_q_slow") and not c.has_buff("malph_q_ms"))
	# W: empowered attack + aftershock on the unit behind
	_place(1.6, 1.4, 0.0)
	await _wait(0.2)
	i0 = rec.size()
	_cast(1, c.global_position)
	await _wait(0.05)
	_attack(a)
	await _wait(1.2)
	_stop_attack()
	_check("w_empowered", _dmg(i0, "malph_w", a) > 0.0)
	_check("w_aftershock", _dmg(i0, "malph_w_splash", b) > 0.0)
	await _wait(5.0)
	_check("w_fx_ends", _ab(1).get("fx") == null)
	# E
	_place(1.6)
	await _wait(0.2)
	i0 = rec.size()
	_cast(2, c.global_position)
	await _wait(0.6)
	_check("e_damage", _dmg(i0, "malph_e", a) > 0.0 and _dmg(i0, "malph_e", b) > 0.0)
	_check("e_as_debuff", a.has_buff("malph_e_as"))
	await _wait(3.2)
	_check("e_debuff_ends", not a.has_buff("malph_e_as") and _attached_fx(a).is_empty(), str(_attached_fx(a)))
	# R
	_place(7.0)
	await _wait(0.2)
	i0 = rec.size()
	_cast(3, a.global_position)
	var up := false
	for k in 30:
		await _wait(0.05)
		up = up or _airborne(a)
	_check("r_damage", _dmg(i0, "malph_r", a) > 0.0)
	_check("r_knockup", up)
	_check("r_lands_on_target", G.flat_dist(c.global_position, a.global_position) < 3.0, "%.2f" % G.flat_dist(c.global_position, a.global_position))
	await _wait(2.0)
	_check("r_cleanup", not _airborne(a) and not c.has_buff("malph_r_unstoppable"))
	# the shell must not stay on a dead Malphite
	_place(6.0)
	c.passive.last_hit = -100.0
	await _wait(0.2)
	c.die(a)
	await _wait(0.2)
	var shell = c.passive.get("shell")
	_check("p_shell_hidden_dead", shell == null or not is_instance_valid(shell) or not shell.visible)
	c.respawn()
	await _wait(0.2)


# ===================================================================== Master Yi
## Records on-hit hook calls (with their effectiveness) so Alpha Strike's on-hit application can be checked.
class OnHitProbe extends Effect:
	var calls: Array = []

	func _init() -> void:
		id = "kitb_onhit_probe"
		hidden = true

	func on_attack_hit(target, info) -> void:
		calls.append([target, info.on_hit_mult if info != null else -1.0])


func _yi() -> void:
	var a = foes[0]
	var b = foes[1]
	_place(5.0)
	await _wait(0.2)
	var i0 := rec.size()
	var probe := OnHitProbe.new()
	c.add_effect(probe)
	_cast(0, a.global_position, a)
	await _wait(0.25)
	_check("q_untargetable", c.untargetable_count > 0 and not c.is_targetable_by(a.team))
	await _wait(1.0)
	_check("q_damage_main", _dmg(i0, "yi_q", a) > 0.0)
	_check("q_damage_bounce", _dmg(i0, "yi_q", b) > 0.0)
	# League: each mark applies on-hit effects, 75% for a target's first mark, 18.75% for later marks
	var primary_ok := false
	var mults := []
	for call in probe.calls:
		mults.append(snappedf(call[1], 0.0001))
		if call[0] == a and is_equal_approx(call[1], 0.75):
			primary_ok = true
	_check("q_applies_on_hit", primary_ok, str(mults))
	c.remove_effect(probe)
	_check("q_restored", c.untargetable_count == 0 and c.invulnerable_count == 0 and c.channel.is_empty() and not c.channel_disarm \
			and (c.model == null or c.model.visible))
	_check("q_reappears_near", G.flat_dist(c.global_position, a.global_position) < 3.0)
	# W: channel heals; a move order breaks it and cleans up
	_place(5.0)
	await _wait(0.2)
	c.hp = c.stats.max_hp * 0.4
	var hp0: float = c.hp
	_cast(1, c.global_position)
	await _wait(1.2)
	_check("w_heals", c.hp > hp0, "%.0f -> %.0f" % [hp0, c.hp])
	_check("w_channel", not c.channel.is_empty())
	c.issue_move(c.global_position - axis * 2.0)
	await _wait(0.2)
	_check("w_move_breaks", c.channel.is_empty() and not _ab(1).channeling and not c.channel_disarm and _ab(1).get("fx") == null)
	# Q during W must end W cleanly
	_place(5.0)
	await _wait(0.2)
	c.hp = c.stats.max_hp * 0.4
	_cast(1, c.global_position)
	await _wait(0.5)
	_cast(0, a.global_position, a)
	await _wait(1.3)
	_check("q_cancels_w", not _ab(1).channeling and _ab(1).get("fx") == null and _ab(1).cast_block_reason() != "casting",
			"channeling=%s" % _ab(1).channeling)
	# E: true damage on attacks
	_place(1.8)
	await _wait(0.2)
	i0 = rec.size()
	_cast(2, c.global_position)
	_attack(a)
	await _wait(1.5)
	_stop_attack()
	_check("e_true_damage", _dmg(i0, "yi_wuju", a) > 0.0)
	await _wait(4.0)
	_check("e_ends", not c.has_buff("yi_wuju"))
	# R
	var ms0: float = c.stats.move_speed
	_cast(3, c.global_position)
	await _wait(0.2)
	_check("r_buff", c.has_buff("yi_highlander") and c.stats.move_speed > ms0)
	await _wait(7.2)
	_check("r_ends", not c.has_buff("yi_highlander"))


# ===================================================================== Miss Fortune
func _mf() -> void:
	var a = foes[0]
	var b = foes[1]
	_place(5.0, 1.5, 0.0)
	await _wait(0.2)
	var i0 := rec.size()
	_cast(0, a.global_position, a)
	await _wait(1.2)
	_check("q_damage", _dmg(i0, "q", a) > 0.0)
	_check("q_bounce", _dmg(i0, "q2", b) > 0.0)
	# W
	_cast(1, c.global_position)
	await _wait(0.2)
	_check("w_buff", c.has_buff("mf_w_active"))
	await _wait(4.2)
	_check("w_ends", not c.has_buff("mf_w_active"))
	# E
	_place(6.0)
	await _wait(0.2)
	i0 = rec.size()
	_cast(2, a.global_position)
	await _wait(1.0)
	_check("e_damage", _dmg(i0, "e", a) > 0.0)
	_check("e_slow", a.has_buff("mf_e_slow"))
	await _wait(2.0)
	# R full channel
	_place(7.0)
	await _wait(0.2)
	i0 = rec.size()
	_cast(3, a.global_position)
	await _wait(0.3)
	_check("r_channel", not c.channel.is_empty() and c.channel_disarm)
	await _wait(3.4)
	var hits := 0
	for k in range(i0, rec.size()):
		if rec[k].tag == "r" and rec[k].t == a:
			hits += 1
	_check("r_waves", hits >= 12, "hits=%d" % hits)
	_check("r_cleanup", c.channel.is_empty() and not c.channel_disarm and _ab(3).get("_cone") == null)
	# R interrupted by a stun
	_place(7.0)
	await _wait(0.2)
	_cast(3, a.global_position)
	await _wait(0.6)
	K.stun(c, 0.4, a)
	await _wait(0.1)
	_check("r_stun_stops", c.channel.is_empty() and not c.channel_disarm and _ab(3).get("_cone") == null)
	await _wait(0.5)
	# R while MF dies
	_place(7.0)
	await _wait(0.2)
	_cast(3, a.global_position)
	await _wait(0.6)
	c.die(a)
	await _wait(0.3)
	_check("r_death_stops", c.channel.is_empty() and not c.channel_disarm and _ab(3).get("_cone") == null)
	c.respawn()
	await _wait(0.2)
	# R kills its target mid-channel (Collector-style execute), then keeps firing safely
	_place(7.0)
	await _wait(0.2)
	_cast(3, a.global_position)
	await _wait(0.5)
	a.hp = 1.0
	await _wait(0.5)
	_check("r_target_dies", a.dead)
	await _wait(2.5)
	_check("r_after_kill_cleanup", c.channel.is_empty() and not c.channel_disarm)
	a.respawn()
	await _wait(0.2)
	# long-match stress: many casts cut at random points (stun, move order, other spell, death); timers stay bounded
	var t0: int = m._timers.size()
	for n in 24:
		_place(7.0)
		await _wait(0.05)
		_cast(3, a.global_position)
		await _wait(G.rng.randf_range(0.05, 0.9))
		match n % 4:
			0: K.stun(c, 0.2, a)
			1: c.interrupt_channel(true)
			2: _cast(0, a.global_position, a)
			3:
				a.hp = 1.0
		await _wait(0.1)
		if a.dead:
			a.respawn()
	await _wait(3.5)
	_check("r_stress_clean", c.channel.is_empty() and not c.channel_disarm and _ab(3).get("_cone") == null and m._timers.size() <= t0 + 40,
			"timers %d -> %d" % [t0, m._timers.size()])


# ===================================================================== Sona
func _sona() -> void:
	var a = foes[0]
	var b = foes[1]
	_place(5.0)
	await _wait(0.2)
	var i0 := rec.size()
	_cast(0, c.global_position)
	await _wait(1.0)
	_check("q_damage_two", _dmg(i0, "q", a) > 0.0 and _dmg(i0, "q", b) > 0.0)
	_check("q_self_hymn", c.has_buff("sona_q_onhit"))
	await _wait(0.6)
	c.hp = c.stats.max_hp * 0.5
	var hp0: float = c.hp
	_cast(1, c.global_position)
	await _wait(0.3)
	_check("w_heal", c.hp > hp0)
	_check("w_shield", c.total_shield() > 0.0)
	await _wait(0.4)
	_cast(2, c.global_position)
	await _wait(0.2)
	_check("e_haste", c.has_buff("sona_e_self"))
	_check("p_ready", c.passive.ready)
	c.teleport(m.nav.nearest_walkable(spot - axis * 4.0))
	i0 = rec.size()
	_attack(a)
	await _wait(1.5)
	_stop_attack()
	_check("p_power_chord", _dmg(i0, "power_chord", a) > 0.0 and not c.passive.ready)
	_check("q_hymn_onhit", _dmg(i0, "sona_q", a) > 0.0)
	# R
	_place(6.0)
	await _wait(0.2)
	i0 = rec.size()
	_cast(3, a.global_position)
	await _wait(0.8)
	_check("r_damage_stun", _dmg(i0, "r", a) > 0.0 and a.has_buff("stun") and b.has_buff("stun"))
	await _wait(1.8)
	_check("r_stun_ends", not a.has_buff("stun") and _attached_fx(a).is_empty(), str(_attached_fx(a)))


# ===================================================================== Veigar
func _veigar() -> void:
	var a = foes[0]
	var b = foes[1]
	_place(6.0)
	await _wait(0.2)
	var st0: float = c.passive.stacks
	var i0 := rec.size()
	_cast(0, a.global_position)
	await _wait(0.8)
	_check("q_damage", _dmg(i0, "q", a) > 0.0)
	_check("p_stack", c.passive.stacks > st0)
	# W
	i0 = rec.size()
	_cast(1, a.global_position)
	await _wait(0.9)
	_check("w_delay", _dmg(i0, "w") == 0.0)
	await _wait(0.8)
	_check("w_damage", _dmg(i0, "w", a) > 0.0)
	# E: cage edge on A; B stands in the middle and then blinks out (must be stunned)
	_place(2.0, 0.0, 0.0)
	var R: float = _ab(2).ind_radius * G.U
	var center: Vector3 = m.nav.nearest_walkable(spot + axis * R)
	b.teleport(center)
	await _wait(0.2)
	_cast(2, center)
	await _wait(0.9)
	_check("e_edge_stun", a.has_buff("stun"))
	_check("e_inside_free", not b.has_buff("stun"))
	b.teleport(m.nav.nearest_walkable(center + side * (R + 4.0)))
	await _wait(0.2)
	_check("e_blink_out_stun", b.has_buff("stun"))
	await _wait(3.0)
	_check("e_stun_ends", not a.has_buff("stun") and not b.has_buff("stun"))
	# R
	_place(5.0)
	await _wait(0.2)
	i0 = rec.size()
	_cast(3, a.global_position, a)
	await _wait(1.0)
	_check("r_damage", _dmg(i0, "r", a) > 0.0)


# ===================================================================== Yasuo
func _yasuo() -> void:
	var a = foes[0]
	var b = foes[1]
	var q = _ab(0)
	_place(3.0)
	await _wait(0.2)
	var i0 := rec.size()
	_cast(0, a.global_position)
	await _wait(0.6)
	_check("q1_damage", _dmg(i0, "yasuo_q", a) > 0.0 and q.stacks == 1, "stacks=%d" % q.stacks)
	_cast(0, a.global_position)
	await _wait(0.6)
	_check("q2_stack", q.stacks == 2 and q.is_q3())
	_check("q3_ready_fx", q.get("ready_fx") != null)
	_place(6.0)
	await _wait(0.1)
	i0 = rec.size()
	_cast(0, a.global_position)
	var up := false
	for k in 20:
		await _wait(0.05)
		up = up or _airborne(a)
	_check("q3_tornado", _dmg(i0, "yasuo_q", a) > 0.0 and up and q.stacks == 0)
	_check("q3_fx_cleared", q.get("ready_fx") == null)
	# R on the airborne target
	_place(6.0)
	await _wait(0.1)
	_cast(0, a.global_position)   # rebuild stacks quickly for the knock-up
	await _wait(0.5)
	q.set_stacks(2)
	_ready_ab(0)
	_cast(0, a.global_position)
	for k in 30:
		await _wait(0.05)
		if _airborne(a):
			break
	i0 = rec.size()
	var r_ok := _cast(3, a.global_position, a)
	await _wait(1.2)
	_check("r_cast", r_ok and _dmg(i0, "yasuo_r", a) > 0.0 and c.has_buff("yasuo_r"))
	await _wait(1.0)
	_check("r_lands", not _airborne(a))
	# W blocks an enemy missile
	_place(6.0)
	await _wait(0.2)
	_cast(1, a.global_position)
	await _wait(0.5)
	var hit := {"n": 0}
	var mab: Ability = a.abilities[0]
	K.line_missile(mab, a.global_position + Vector3(0, 1, 0), G.flat_dir(a.global_position, c.global_position), 1500.0, 1200.0,
			{"width": 60.0, "on_hit": func(_mm, _u): hit.n += 1})
	var hm := K.homing_missile(mab, a.global_position + Vector3(0, 1, 0), c, 1500.0, func(_mm, _u): hit.n += 1)
	await _wait(1.2)
	_check("w_blocks", hit.n == 0, "hits=%d" % hit.n)
	await _wait(3.0)
	# E: dash through, per-target lockout
	_place(3.0)
	await _wait(0.2)
	i0 = rec.size()
	var p0 := c.global_position
	_cast(2, a.global_position, a)
	await _wait(0.6)
	_check("e_damage_dash", _dmg(i0, "yasuo_e", a) > 0.0 and G.flat_dist(p0, c.global_position) > 3.0)
	_ready_ab(2)
	_check("e_target_lockout", not _ab(2).valid_unit_target(a))
	# E -> Q circle
	_place(3.0)
	await _wait(0.2)
	i0 = rec.size()
	_ready_ab(0)
	_cast(2, b.global_position, b)
	await _wait(0.05)
	_cast(0, c.global_position)
	await _wait(0.8)
	_check("eq_damage", _dmg(i0, "yasuo_q") > 0.0)
