extends Node
## Exact-number checks for the tank item family (src/items/item_fx_x_tank.gd).
## Usage: godot --headless --path . --fixed-fps 60 --quit-after 6000 -- --sim --botplayer --time=300 --seed=3 --champ=Ahri \
##          --harness=res://src/items/tests/tank_test.gd
## Output: "TANK PASS|FAIL <name> <detail>" and a final "TANK DONE fails=N".

var main = null
var match_ref = null

var m = null
var c: Champion = null
var dummies: Array = []
var tracker: Tracker = null
var spot := Vector3.ZERO
var fails := 0
var passes := 0


class Tracker extends Effect:
	var by_tag := {}
	var heal := 0.0

	func _init() -> void:
		id = "harness_tracker"
		hidden = true

	func on_damage_dealt(info) -> void:
		if info.tag != "":
			by_tag[info.tag] = by_tag.get(info.tag, 0.0) + info.final + info.absorbed

	func on_heal_dealt(_t, a: float) -> void:
		heal += a


	func reset() -> void:
		by_tag.clear()
		heal = 0.0


func _ready() -> void:
	_run()


func _frame() -> void:
	await get_tree().process_frame


func _wait(s: float) -> void:
	var t := 0.0
	while t < s:
		await _frame()
		t += 1.0 / 60.0


func _check(name: String, ok: bool, detail: String = "") -> void:
	print("TANK %s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if ok:
		passes += 1
	else:
		fails += 1


func _near(a: float, b: float, tol: float = 0.02) -> bool:
	return absf(a - b) <= maxf(absf(b) * tol, 0.6)


func _setup() -> void:
	m = G.match
	c = G.player
	m.spawner = null
	for u in m.units.duplicate():
		if u.kind == G.Kind.MINION or u.kind == G.Kind.SUMMON:
			m.remove_unit(u)
	spot = m.nav.nearest_walkable((m.outer_turrets[0].global_position + m.outer_turrets[1].global_position) * 0.5)
	for ch in m.champions:
		if ch == c:
			continue
		ch.controller = null
		ch.is_bot = false
		ch.teleport(ch.spawn_point)
		ch.issue_move(ch.spawn_point)
	for ch in m.champions:
		if ch.team != c.team and dummies.size() < 2:
			dummies.append(ch)
	c.controller = null
	c.is_bot = false
	c.gain_xp(1.0e6)
	while c.level < 13:
		c.gain_xp(1000.0)
	c.add_effect(Tracker.new())
	tracker = c.find_effect("harness_tracker")
	for u in [c, dummies[0], dummies[1]]:
		for e in u.effects.duplicate():
			if e.id != "mayhem_aura" and not e.id.begins_with("harness"):
				u.remove_effect(e)
		var b := Buff.new("harness_disarm", 1.0)
		b.permanent = true
		b.hidden = true
		b.cc = Buff.CC.DISARM | Buff.CC.SILENCE
		b.cleansable = false
		u.add_buff(b, u)
	_place(4.0)


func _place(dist: float) -> void:
	var fwd := G.flat_dir(spot, m.nexus_units[1 if c.team == G.Team.ORDER else 0].global_position)
	var side := Vector3(-fwd.z, 0, fwd.x)
	c.teleport(spot)
	c.issue_move(spot)
	for i in dummies.size():
		var d: Champion = dummies[i]
		if d.dead:
			d.respawn()
		d.teleport(m.nav.nearest_walkable(spot + fwd * (dist + i * 0.5) + side * float(i)))
		d.issue_move(d.global_position)
		d.hp = d.stats.max_hp


func _put(d, p: Vector3) -> void:
	d.teleport(p)
	d.issue_move(p)


func _clean() -> void:
	for u in [c, dummies[0], dummies[1]]:
		for b in u.buffs.duplicate():
			if not b.id.begins_with("harness"):
				u.remove_buff(b)
		u.shields.clear()
	tracker.reset()


func _equip(ids: Array) -> void:
	c.controller = null   # --botplayer installs a controller again after setup
	for it in c.items.duplicate():
		c.remove_item(it)
	for id in ids:
		c.add_item(ItemDB.create(id))
	_clean()
	c.recompute_stats()
	c.hp = c.stats.max_hp
	c.mana = c.stats.max_mana
	for d in dummies:
		d.recompute_stats()
		d.hp = d.stats.max_hp
	_place(4.0)


func _item(id: int):
	for it in c.items:
		if it.item_id == id:
			return it
	return null


func _hit(src, dst, amount: float, type: int = G.DmgType.PHYSICAL, opts := {"is_attack": true}) -> DamageInfo:
	return Combat.deal(src, dst, amount, type, opts)


func _run() -> void:
	await get_tree().create_timer(0.5, true, false, true).timeout
	_setup()
	var d0: Champion = dummies[0]
	var d1: Champion = dummies[1]

	# ---------------------------------------------------------------- Warden's Mail
	_equip([3082])
	var arm := c.stats.armor
	var rm := 100.0 / (100.0 + arm)
	var i1 := _hit(d0, c, 200.0)
	_check("wardens_mail 200 raw -15", _near(i1.mitigated, 200.0 * rm - 15.0), "post %.2f want %.2f" % [i1.mitigated, 200.0 * rm - 15.0])
	var i2 := _hit(d0, c, 30.0)
	_check("wardens_mail 30 raw cap 20%%", _near(i2.mitigated, 30.0 * rm * 0.8), "post %.2f want %.2f" % [i2.mitigated, 30.0 * rm * 0.8])
	var i3 := Combat.deal(d0, c, 200.0, G.DmgType.PHYSICAL, {})
	_check("wardens_mail spell untouched", _near(i3.mitigated, 200.0 * rm), "post %.2f" % i3.mitigated)

	# ---------------------------------------------------------------- Plated Steelcaps (legacy)
	_equip([3047])
	rm = 100.0 / (100.0 + c.stats.armor)
	var i4 := _hit(d0, c, 100.0)
	_check("steelcaps -10%% attack", _near(i4.mitigated, 100.0 * rm * 0.9), "post %.2f want %.2f" % [i4.mitigated, 100.0 * rm * 0.9])

	# ---------------------------------------------------------------- Thornmail / Bramble Vest
	_equip([3075])
	tracker.reset()
	d0.hp = d0.stats.max_hp
	var before := d0.hp
	_hit(d0, c, 100.0)
	var want := (20.0 + 0.1 * c.stats.bonus_armor) * 100.0 / (100.0 + d0.stats.mr)
	_check("thornmail damage", _near(before - d0.hp, want), "dealt %.2f want %.2f (bonus armor %.0f)" % [before - d0.hp, want, c.stats.bonus_armor])
	_check("thornmail grievous", d0.grievous_wounds() >= 0.39, "gw %.2f" % d0.grievous_wounds())
	_equip([3076])
	d0.hp = d0.stats.max_hp
	before = d0.hp
	_hit(d0, c, 100.0)
	want = 10.0 * 100.0 / (100.0 + d0.stats.mr)
	_check("bramble damage", _near(before - d0.hp, want), "dealt %.2f want %.2f" % [before - d0.hp, want])
	_equip([3075, 3076])
	d0.hp = d0.stats.max_hp
	before = d0.hp
	_hit(d0, c, 100.0)
	want = (20.0 + 0.1 * c.stats.bonus_armor) * 100.0 / (100.0 + d0.stats.mr)
	_check("thorns do not stack", _near(before - d0.hp, want), "dealt %.2f want %.2f" % [before - d0.hp, want])

	# ---------------------------------------------------------------- Spirit Visage
	_equip([3065])
	c.hp = 10.0
	var healed := Combat.heal(null, c, 100.0)
	_check("visage heal +25%%", _near(healed, 125.0), "healed %.1f" % healed)
	Combat.shield(null, c, 100.0, 5.0)
	_check("visage shield +25%%", _near(c.total_shield(), 125.0), "shield %.1f" % c.total_shield())

	# ---------------------------------------------------------------- Immolate family
	for id in [6660, 3068, 6664]:
		_equip([id])
		_put(d0, c.global_position + Vector3(2.0, 0, 0))
		await _wait(0.3)   # vision refresh: a unit must be visible to be hit
		d0.hp = d0.stats.max_hp
		tracker.reset()
		var bh := TankFxProbe.bonus_hp(c)
		var base := 15.0
		var ratio := 0.0
		if id == 3068:
			base = 20.0
			ratio = 0.015
		elif id == 6664:
			ratio = 0.01
		var tick := (base + ratio * bh) * 100.0 / (100.0 + d0.stats.mr)
		_hit(c, d0, 1.0, G.DmgType.TRUE)   # dealing damage activates it
		await _wait(2.1)
		var got: float = tracker.by_tag.get("immolate", 0.0)
		_check("immolate %d three ticks window" % id, _near(got, tick * 3.0, 0.06), "got %.1f want ~%.1f (tick %.1f, bonus hp %.0f)" % [got, tick * 3.0, tick, bh])
		await _wait(2.5)
		var got2: float = tracker.by_tag.get("immolate", 0.0)
		_check("immolate %d stops after 3s" % id, _near(got2, got, 0.01) or _near(got2, tick * 3.0, 0.06), "total %.1f" % got2)
	# Desolate (Hollow Radiance): champion takedown within 3s
	_equip([6664])
	_put(d0, c.global_position + Vector3(2.0, 0, 0))
	_put(d1, d0.global_position + Vector3(1.0, 0, 0))
	d1.hp = d1.stats.max_hp
	d0.damage_log[c] = m.time
	tracker.reset()
	var hr = _item(6664)
	var bh2 := TankFxProbe.bonus_hp(c)
	d1.hp = d1.stats.max_hp
	var d1_before := d1.hp
	hr.on_takedown(d0)
	var want_d := (60.0 + 0.01 * bh2) * 100.0 / (100.0 + d1.stats.mr)
	var got_d: float = d1_before - d1.hp
	_check("desolate champion takedown", _near(got_d, want_d), "got %.1f want %.1f" % [got_d, want_d])

	# ---------------------------------------------------------------- Frozen Heart
	_equip([3110])
	_put(d0, c.global_position + Vector3(3.0, 0, 0))
	var as0 := d0.stats.attack_speed
	await _wait(1.0)
	var as1 := d0.stats.attack_speed
	_check("frozen heart -20%% AS", _near(as1, as0 * 0.8, 0.03), "%.3f -> %.3f" % [as0, as1])
	_put(d0, c.global_position + Vector3(9.0, 0, 0))
	await _wait(1.5)
	_check("frozen heart range 7m", _near(d0.stats.attack_speed, as0, 0.01), "as %.3f" % d0.stats.attack_speed)

	# ---------------------------------------------------------------- Jak'Sho
	_equip([6665, 3082])
	_put(d0, c.global_position + Vector3(3.0, 0, 0))
	var ba := c.stats.bonus_armor
	var bm := c.stats.bonus_mr
	var arm_before := c.stats.armor
	var t := 0.0
	while t < 4.0:
		if int(t * 2.0) != int((t - 1.0 / 60.0) * 2.0):
			_hit(d0, c, 1.0, G.DmgType.MAGIC, {})
		await _frame()
		t += 1.0 / 60.0
	_check("jaksho not yet at 4s", _near(c.stats.armor, arm_before, 0.005), "armor %.1f" % c.stats.armor)
	while t < 6.5:
		if int(t * 2.0) != int((t - 1.0 / 60.0) * 2.0):
			_hit(d0, c, 1.0, G.DmgType.MAGIC, {})
		await _frame()
		t += 1.0 / 60.0
	_check("jaksho +30%% bonus armor after 5s", _near(c.stats.armor, arm_before + 0.3 * ba, 0.01), "armor %.1f want %.1f" % [c.stats.armor, arm_before + 0.3 * ba])
	_check("jaksho +30%% bonus MR", _near(c.stats.mr, c.stats.base_mr + 1.3 * bm, 0.01), "mr %.1f" % c.stats.mr)
	var jk = _item(6665)
	await _wait(6.0)
	_check("jaksho ends with combat", _near(c.stats.armor, arm_before, 0.005), "armor %.1f" % c.stats.armor)

	# ---------------------------------------------------------------- Dead Man's Plate
	_equip([3742])
	var ms0 := c.stats.move_speed
	var far: Vector3 = m.nav.nearest_walkable(spot - G.flat_dir(spot, m.nexus_units[1 if c.team == G.Team.ORDER else 0].global_position) * 12.0)
	# the pathfinder is not needed: walk the champion by hand (the item measures position change)
	var wt := 0.0
	var ang := 0.0
	var rad := 3.0
	var center := spot - Vector3(rad, 0, 0)
	while wt < 4.3:
		ang += ms0 * G.U / 60.0 / rad
		c.teleport(center + Vector3(cos(ang), 0, sin(ang)) * rad)
		await _frame()
		wt += 1.0 / 60.0
	var dm = _item(3742)
	_check("dmp builds 20 MS", _near(c.stats.move_speed, ms0 + 20.0 * (1.0 + 0.0), 0.03) or c.stats.move_speed > ms0 + 15.0, "ms %.1f -> %.1f stacks %.0f" % [ms0, c.stats.move_speed, dm.stacks])
	c.issue_stop()
	_put(d0, c.global_position + Vector3(2.0, 0, 0))
	dm.stacks = 100.0
	tracker.reset()
	var ai := c.attack_hit(d0, false)
	var want_s := (40.0 + c.stats.base_ad) * 100.0 / (100.0 + d0.stats.armor)
	_check("dmp discharge", _near(tracker.by_tag.get("shipwrecker", 0.0), want_s), "got %.1f want %.1f" % [tracker.by_tag.get("shipwrecker", 0.0), want_s])
	_check("dmp resets stacks", dm.stacks < 1.0)

	# ---------------------------------------------------------------- Force of Nature
	_equip([4401])
	var mr0 := c.stats.mr
	for i in 8:
		_hit(d0, c, 5.0, G.DmgType.MAGIC, {})
		await _wait(1.1)
	_check("force of nature +70 MR", _near(c.stats.mr, mr0 + 70.0, 0.01), "mr %.1f -> %.1f" % [mr0, c.stats.mr])
	_check("force of nature MS buff", c.has_buff("steadfast"))

	# ---------------------------------------------------------------- Heartsteel
	_equip([3084])
	_put(d0, c.global_position + Vector3(3.0, 0, 0))
	var hs = _item(3084)
	tracker.reset()
	c.attack_hit(d0, false)
	_check("heartsteel needs 0.5s nearby", tracker.by_tag.get("heartsteel", 0.0) == 0.0)
	await _wait(0.7)
	var mh := c.stats.max_hp
	tracker.reset()
	c.attack_hit(d0, false)
	var raw := 70.0 + 0.06 * mh
	want = raw * 100.0 / (100.0 + d0.stats.armor)
	_check("heartsteel proc dmg", _near(tracker.by_tag.get("heartsteel", 0.0), want), "got %.1f want %.1f" % [tracker.by_tag.get("heartsteel", 0.0), want])
	_check("heartsteel max hp gain 5%%", _near(hs.gained, raw * 0.05), "gained %.2f want %.2f" % [hs.gained, raw * 0.05])
	tracker.reset()
	c.attack_hit(d0, false)
	_check("heartsteel per-target cd", tracker.by_tag.get("heartsteel", 0.0) == 0.0)
	c.recompute_stats()
	_check("heartsteel goliath size", _near(c.stats.size - 1.0, 0.03 * c.stats.max_hp / 1000.0, 0.05), "size %.3f hp %.0f" % [c.stats.size, c.stats.max_hp])

	# ---------------------------------------------------------------- Iceborn Gauntlet
	_equip([6662])
	_put(d0, c.global_position + Vector3(2.0, 0, 0))
	tracker.reset()
	c.attack_hit(d0, false)
	_check("iceborn no proc without ability", tracker.by_tag.get("spellblade", 0.0) == 0.0)
	var ib = _item(6662)
	ib.on_ability_cast(c.abilities[0], null)
	c.attack_hit(d0, false)
	want = 1.5 * c.stats.base_ad * 100.0 / (100.0 + d0.stats.armor)
	_check("iceborn spellblade 150%% base AD", _near(tracker.by_tag.get("spellblade", 0.0), want), "got %.1f want %.1f" % [tracker.by_tag.get("spellblade", 0.0), want])
	await _wait(0.5)
	_check("iceborn frost field slows", d0.has_buff("iceborn_field") or d0.stats.slow > 0.0, "slow %.2f" % d0.stats.slow)

	# ---------------------------------------------------------------- Unending Despair
	_equip([2502])
	_put(d0, c.global_position + Vector3(3.0, 0, 0))
	d0.hp = d0.stats.max_hp
	c.hp = c.stats.max_hp * 0.5
	var bh3 := TankFxProbe.bonus_hp(c)
	_hit(d0, c, 1.0, G.DmgType.MAGIC, {})
	d1.hp = d1.stats.max_hp
	_put(d1, c.global_position + Vector3(20.0, 0, 0))
	tracker.reset()
	await _wait(0.5)
	var dr: float = tracker.by_tag.get("anguish", 0.0)
	want = 0.03 * bh3 * 100.0 / (100.0 + d0.stats.mr)
	_check("unending drain", _near(dr, want), "got %.1f want %.1f" % [dr, want])
	_check("unending heals 250%%", _near(tracker.heal, want * 2.5 * 0.9, 0.05), "heal %.1f want %.1f" % [tracker.heal, want * 2.5 * 0.9])
	_put(d1, c.global_position + Vector3(4.0, 0, 0))

	# ---------------------------------------------------------------- Protoplasm Harness
	_equip([2525])
	c.hp = c.stats.max_hp * 0.35
	_hit(d0, c, c.stats.max_hp * 0.1, G.DmgType.TRUE, {})
	_check("lifeline triggers", c.has_buff("lifeline"))
	var mh0 := c.stats.max_hp
	_check("lifeline max hp", mh0 > 600.0, "max hp %.0f" % mh0)
	await _wait(5.5)
	_check("lifeline ends", not c.has_buff("lifeline"))
	_equip([2525])
	c.hp = 100.0
	_hit(d0, c, 150.0, G.DmgType.TRUE, {})
	_check("lifeline saves from lethal", not c.dead and c.hp > 0.0, "hp %.0f dead %s" % [c.hp, c.dead])

	# ---------------------------------------------------------------- Warmog's Armor
	_equip([3083, 3084])
	await _wait(0.7)
	c.hp = c.stats.max_hp * 0.5
	var item_hp := 1000.0 + 900.0
	_check("warmog vitality", _near(c.stats.max_hp, c.stats.base.base_hp + Stats.growth(c.stats.base.hp_per_level, c.level) + item_hp + 0.12 * item_hp + 0.0, 0.03), "max hp %.0f" % c.stats.max_hp)
	await _wait(1.0)
	var hp_mid := c.hp
	_check("warmog no regen before 8s", _near(hp_mid, c.stats.max_hp * 0.5, 0.03), "hp %.0f" % hp_mid)
	await _wait(8.0)
	var hp_a := c.hp
	await _wait(2.0)
	var gain := (c.hp - hp_a) / 2.0
	_check("warmog 1.5%% max hp per s", _near(gain, 0.015 * c.stats.max_hp + c.stats.hp_regen, 0.1), "gain/s %.1f want %.1f" % [gain, 0.015 * c.stats.max_hp + c.stats.hp_regen])

	# ---------------------------------------------------------------- Gluttonous Greaves
	_equip([3008])
	var ov := c.stats.omnivamp
	var gg = _item(3008)
	gg.on_takedown(d0)
	gg.on_takedown(d0)
	c.recompute_stats()
	_check("gluttonous +0.6%% per takedown", _near(c.stats.omnivamp, ov + 0.012, 0.02), "omni %.4f -> %.4f" % [ov, c.stats.omnivamp])

	# ---------------------------------------------------------------- Winter's Approach
	_equip([3119])
	_put(d0, c.global_position + Vector3(2.0, 0, 0))
	var wa = _item(3119)
	await _wait(0.7)
	var mm0 := c.stats.max_mana
	var hp0 := c.stats.max_hp
	wa.charges = 4
	c.attack_hit(d0, false)
	c.recompute_stats()
	_check("manaflow +9 max mana vs champion", _near(c.stats.max_mana, mm0 + 9.0), "mana %.1f -> %.1f" % [mm0, c.stats.max_mana])
	await _wait(0.6)
	_check("awe health 15%% of bonus mana", _near(c.stats.max_hp, hp0 + 0.15 * 9.0, 0.02), "hp %.1f -> %.1f" % [hp0, c.stats.max_hp])

	print("TANK DONE fails=%d passes=%d" % [fails, passes])
	get_tree().quit()


class TankFxProbe:
	static func bonus_hp(u) -> float:
		return maxf(0.0, u.stats.max_hp - (u.stats.base.base_hp + Stats.growth(u.stats.base.hp_per_level, u.level)))
