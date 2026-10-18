extends Node
## Exact number checks for the mage item family (src/items/item_fx_x_mage.gd).
##   godot --headless --path . --fixed-fps 60 --quit-after 20000 -- --champ=Lux --harness=res://src/items/tests/mage_test.gd
## Output: "MAGE PASS|FAIL <name> <detail>" and a final "MAGE DONE passes=N fails=N".

var main = null
var match_ref = null

var m = null
var c: Champion = null
var dummies: Array = []
var spot := Vector3.ZERO
var passes := 0
var fails := 0
var spy: Spy = null


class Spy extends Effect:
	var raw := {}        ## tag -> total raw amount
	var cnt := {}
	var mult := {}       ## tag -> last accumulated mult
	var shield_last := 0.0
	var shields := 0

	func _init() -> void:
		id = "harness_spy"
		hidden = true

	func on_damage_dealt(info) -> void:
		var k: String = info.tag if info.tag != "" else "none"
		raw[k] = raw.get(k, 0.0) + info.amount
		cnt[k] = cnt.get(k, 0) + 1
		mult[k] = info.mult

	func on_shield_dealt(_t, amount: float) -> void:
		shield_last = amount
		shields += 1

	func clear() -> void:
		raw.clear()
		cnt.clear()
		mult.clear()
		shield_last = 0.0
		shields = 0


func _ready() -> void:
	_run()


func _frame() -> void:
	await get_tree().process_frame


## Simulate `s` seconds of match time.
func _sim(s: float) -> void:
	var t0: float = m.time
	var guard := 0
	while m.time - t0 < s and guard < 100000:
		guard += 1
		_quiet()
		await _frame()


func _quiet() -> void:
	for u in [c] + dummies:
		if u.dead:
			continue
		u.attack_target = null
		if u.windup_timer >= 0.0:
			u.cancel_windup()


func _check(name: String, ok: bool, detail: String = "") -> void:
	print("MAGE %s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if ok:
		passes += 1
	else:
		fails += 1


func _near(a: float, b: float, tol: float = 0.01) -> bool:
	return absf(a - b) <= maxf(tol, absf(b) * 0.001)


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
		if ch.team != c.team and dummies.size() < 2:
			dummies.append(ch)
	c.gain_xp(1.0e6)
	for i in 30:
		if not c.level_ability(3):
			for s in [0, 1, 2]:
				if c.level_ability(s):
					break
	spy = Spy.new()
	c.add_effect(spy)
	for u in [c] + dummies:
		var b := Buff.new("harness_disarm", 1.0)
		b.permanent = true
		b.hidden = true
		b.cc = Buff.CC.DISARM
		b.cleansable = false
		u.add_buff(b, u)
	for d in dummies:
		for e in d.effects.duplicate():
			if e.id != "mayhem_aura" and not e.id.begins_with("harness") and not e.id.begins_with("kitb"):
				d.remove_effect(e)


func _reset_positions(dist: float) -> void:
	var fwd := G.flat_dir(spot, m.nexus_units[1 if c.team == G.Team.ORDER else 0].global_position)
	var side := Vector3(-fwd.z, 0, fwd.x)
	c.teleport(spot)
	c.issue_move(spot)
	c.face_toward(spot + fwd, 1000.0)
	for i in dummies.size():
		var d: Champion = dummies[i]
		if d.dead:
			d.respawn()
		var p: Vector3 = spot + fwd * (dist + i * 1.2) + side * (0.0 if i == 0 else 1.0)
		d.teleport(m.nav.nearest_walkable(p))
		d.issue_move(d.global_position)
		d.hp = d.stats.max_hp
	c.hp = c.stats.max_hp
	c.mana = c.stats.max_mana


func _park(d: Champion, dist: float) -> void:
	var fwd := G.flat_dir(spot, m.nexus_units[1 if c.team == G.Team.ORDER else 0].global_position)
	d.teleport(m.nav.nearest_walkable(spot + fwd * dist))
	d.issue_move(d.global_position)


## Fresh equipment + clean arena. Returns the created items.
func _equip(ids: Array, dist: float = 5.0) -> Array:
	for it in c.items.duplicate():
		c.remove_item(it)
	var out := []
	for id in ids:
		var it := ItemDB.create(id)
		c.add_item(it)
		out.append(it)
	for u in [c] + dummies:
		for b in u.buffs.duplicate():
			if not b.id.begins_with("harness"):
				u.remove_buff(b)
		u.shields.clear()
	for ab in c.abilities:
		if ab != null:
			ab.cd = 0.0
	c.recompute_stats()
	_reset_positions(dist)
	c.recompute_stats()
	await _sim(0.3)     # let the vision system see the freshly teleported dummies
	c.hp = c.stats.max_hp
	c.mana = c.stats.max_mana
	spy.clear()
	return out


func _hit(d, amount: float = 10.0, type: int = G.DmgType.MAGIC, slot: int = 0, tag: String = "") -> DamageInfo:
	var ab: Ability = c.abilities[slot]
	ab.cast_count += 1
	var opts := {}
	if tag != "":
		opts["tag"] = tag
	return ab.hit(d, amount, type, opts)


func _x(d, amount: float = 10.0, type: int = G.DmgType.MAGIC, extra: Dictionary = {}) -> DamageInfo:
	var o := {"tag": "x"}
	o.merge(extra, true)
	return Combat.deal(c, d, amount, type, o)


func _run() -> void:
	for i in 60:
		await _frame()
	_setup()
	for i in 30:
		await _frame()
	print("MAGE player=%s level=%d ap_ult=%s" % [c.alias, c.level, str(c.abilities[3].is_ult)])
	await _baseline()
	_registered()
	await _t_manaflow()
	await _t_luden()
	await _t_burns()
	await _t_amps()
	await _t_misc_procs()
	await _t_eternity()
	await _t_actives()
	await _t_conditional()
	await _t_debuffs()
	await _t_cryptbloom()
	print("MAGE DONE passes=%d fails=%d" % [passes, fails])
	get_tree().quit()


## ARAM / Mayhem modifiers (damage dealt, shield power) already sit on every hit: measure them without items.
var base_magic := 1.0
var base_phys := 1.0
var base_attack := 1.0
var base_true := 1.0
var base_shield := 1.0


func _baseline() -> void:
	await _equip([])
	_x(dummies[0], 10.0, G.DmgType.MAGIC)
	base_magic = spy.mult.get("x", 1.0)
	_x(dummies[0], 10.0, G.DmgType.PHYSICAL)
	base_phys = spy.mult.get("x", 1.0)
	_x(dummies[0], 10.0, G.DmgType.PHYSICAL, {"is_attack": true})
	base_attack = spy.mult.get("x", 1.0)
	_x(dummies[0], 10.0, G.DmgType.TRUE)
	base_true = spy.mult.get("x", 1.0)
	var sh := Combat.shield(c, c, 100.0, 2.0)
	base_shield = float(sh.amount) / 100.0
	print("MAGE baseline magic=%.3f phys=%.3f attack=%.3f true=%.3f shield=%.3f" % [base_magic, base_phys, base_attack, base_true, base_shield])


func _registered() -> void:
	var ids := [3070, 3003, 3004, 3916, 3165, 2508, 2503, 3145, 3802, 3803, 6657, 3147, 4633, 6653, 6655, 3152, 2420, 4645, 4628,
			4646, 3118, 2522, 8020, 2504, 8010, 3137, 4629, 123430, 6621, 2523]
	var bad := []
	for id in ids:
		var it := ItemDB.create(id)
		if it == null or not ItemFxExtra.has(id):
			bad.append(id)
	_check("registered", bad.is_empty(), str(bad))


# --------------------------------------------------------------------- Tear family
func _t_manaflow() -> void:
	var it: Item = (await _equip([3003]))[0]
	var m0: float = c.stats.max_mana
	_hit(dummies[0])
	c.abilities[0].cast_count -= 1
	_hit(dummies[0])    # same cast: only one charge
	await _sim(0.3)
	_check("archangel manaflow champion", _near(c.stats.max_mana - m0, 15.0, 0.1), "d=%.2f" % (c.stats.max_mana - m0))
	_check("archangel charges", it.charges == 4, "charges=%d" % it.charges)
	var want_ap: float = 70.0 + 0.01 * (600.0 + 15.0)
	_check("archangel awe ap", _near(c.stats.m("ap"), want_ap, 0.2), "ap=%.2f want=%.2f" % [c.stats.m("ap"), want_ap])
	for i in 6:
		_hit(dummies[0])
	await _sim(0.3)
	_check("archangel cap/charges", it.charges == 0 and _near(c.stats.max_mana - m0, 75.0, 0.1), "charges=%d d=%.1f" % [it.charges, c.stats.max_mana - m0])
	it.charge_t = 0.01
	await _sim(0.1)
	_check("archangel recharge", it.charges == 1, "charges=%d" % it.charges)
	# mana cap 360
	it.gained = 355.0
	it.charges = 5
	_hit(dummies[0])
	await _sim(0.1)
	_check("archangel max 360", _near(it.gained, 360.0), "gained=%.1f" % it.gained)

	it = (await _equip([3004]))[0]
	var ad0: float = c.stats.m("ad")
	m0 = c.stats.max_mana
	c.attack_hit(dummies[0], false)
	await _sim(0.3)
	_check("manamune attack charge", _near(c.stats.max_mana - m0, 9.0, 0.1), "d=%.2f" % (c.stats.max_mana - m0))
	_check("manamune awe ad", _near(c.stats.m("ad"), 35.0 + 0.025 * (500.0 + 9.0), 0.05), "ad=%.2f" % c.stats.m("ad"))
	_hit(dummies[0])
	await _sim(0.2)
	_check("manamune ability charge", _near(c.stats.max_mana - m0, 18.0, 0.1), "d=%.2f" % (c.stats.max_mana - m0))
	it = (await _equip([3070]))[0]
	m0 = c.stats.max_mana
	_hit(dummies[0])
	await _sim(0.2)
	_check("tear manaflow", _near(c.stats.max_mana - m0, 9.0, 0.1), "d=%.2f" % (c.stats.max_mana - m0))


# --------------------------------------------------------------------- Luden's
func _t_luden() -> void:
	await _equip([6655])
	_park(dummies[1], 40.0)
	var base: float = 75.0 + 0.05 * c.stats.ap
	_hit(dummies[0])
	await _sim(1.5)
	_check("luden single target", _near(spy.raw.get("luden", 0.0), base * 2.0, 0.1) and spy.cnt.get("luden", 0) == 6,
			"raw=%.1f want=%.1f n=%d" % [spy.raw.get("luden", 0.0), base * 2.0, spy.cnt.get("luden", 0)])
	spy.clear()
	_hit(dummies[0])
	await _sim(1.0)
	_check("luden cooldown", spy.cnt.get("luden", 0) == 0)
	await _equip([6655])
	_hit(dummies[0])
	await _sim(1.5)
	var want: float = base * (2.0 + 4.0 * 0.2)
	_check("luden two targets", _near(spy.raw.get("luden", 0.0), want, 0.1) and spy.cnt.get("luden", 0) == 6,
			"raw=%.1f want=%.1f n=%d" % [spy.raw.get("luden", 0.0), want, spy.cnt.get("luden", 0)])


# --------------------------------------------------------------------- burns
func _t_burns() -> void:
	await _equip([2508])
	_park(dummies[1], 40.0)
	_hit(dummies[0])
	await _sim(3.6)
	_check("fated ashes burn", _near(spy.raw.get("burn", 0.0), 15.0, 0.05) and spy.cnt.get("burn", 0) == 6,
			"raw=%.2f n=%d" % [spy.raw.get("burn", 0.0), spy.cnt.get("burn", 0)])
	await _equip([2503])
	var ap: float = c.stats.ap
	_hit(dummies[0])
	await _sim(0.5)
	_check("blackfire ap per champion", _near(c.stats.m("ap%"), 0.04, 0.0001), "ap%%=%.3f" % c.stats.m("ap%"))
	await _sim(3.1)
	var want: float = 3.0 * (20.0 + 0.02 * ap)
	_check("blackfire burn", _near(spy.raw.get("burn", 0.0), want * 1.04, 0.1) or _near(spy.raw.get("burn", 0.0), want, 0.4) and spy.cnt.get("burn", 0) == 6,
			"raw=%.2f want=%.2f n=%d" % [spy.raw.get("burn", 0.0), want, spy.cnt.get("burn", 0)])
	await _sim(0.3)
	_check("blackfire ap ends", _near(c.stats.m("ap%"), 0.0, 0.0001))
	await _equip([6653])
	_hit(dummies[0])
	await _sim(3.6)
	var d0: Champion = dummies[0]
	var want_l: float = 0.054 * d0.stats.max_hp
	_check("liandry torment", _near(spy.raw.get("burn", 0.0), want_l, 0.1) and spy.cnt.get("burn", 0) == 6,
			"raw=%.2f want=%.2f n=%d" % [spy.raw.get("burn", 0.0), want_l, spy.cnt.get("burn", 0)])


# --------------------------------------------------------------------- combat amplification
func _t_amps() -> void:
	await _equip([3147])
	_x(dummies[0], 1.0)
	var m_first: float = spy.mult.get("x", 0.0) / base_magic
	for i in 8:
		await _sim(0.5)
		_x(dummies[0], 1.0)
	_check("haunting guise amp", _near(m_first, 1.0, 0.0001) and _near(spy.mult.get("x", 0.0) / base_magic, 1.06, 0.0001),
			"first=%.3f last=%.3f" % [m_first, spy.mult.get("x", 0.0) / base_magic])
	await _sim(3.4)
	_x(dummies[0], 1.0)
	_check("haunting guise resets", _near(spy.mult.get("x", 0.0) / base_magic, 1.0, 0.0001), "mult=%.3f" % (spy.mult.get("x", 0.0) / base_magic))
	var rm: Item = (await _equip([4633]))[0]
	var bonus_hp: float = ItemFx.bonus_hp(c)
	for i in 10:
		_x(dummies[0], 1.0)
		await _sim(0.5)
	_check("riftmaker amp 8%", _near(spy.mult.get("x", 0.0) / base_magic, 1.08, 0.0001), "mult=%.3f" % (spy.mult.get("x", 0.0) / base_magic))
	_check("riftmaker omnivamp", _near(c.stats.omnivamp, 0.06, 0.0001), "vamp=%.3f" % c.stats.omnivamp)
	_check("riftmaker void infusion", _near(c.stats.m("ap"), 70.0 + 0.02 * bonus_hp, 0.6), "ap=%.2f want=%.2f" % [c.stats.m("ap"), 70.0 + 0.02 * bonus_hp])


# --------------------------------------------------------------------- misc damage procs
func _t_misc_procs() -> void:
	await _equip([3145])
	_hit(dummies[0])
	_hit(dummies[0], 10.0, G.DmgType.MAGIC, 0)
	await _sim(0.2)
	_check("alternator", _near(spy.raw.get("alternator", 0.0), 65.0) and spy.cnt.get("alternator", 0) == 1,
			"raw=%.1f n=%d" % [spy.raw.get("alternator", 0.0), spy.cnt.get("alternator", 0)])
	await _equip([3916])
	_hit(dummies[0])
	_check("oblivion orb grievous", _near(dummies[0].grievous_wounds(), 0.4, 0.001))
	await _equip([3165])
	_hit(dummies[0])
	_check("morellonomicon grievous", _near(dummies[0].grievous_wounds(), 0.4, 0.001))

	await _equip([4645])
	var d0: Champion = dummies[0]
	d0.hp = d0.stats.max_hp * 0.3
	_x(d0, 10.0)
	var a: float = spy.mult.get("x", 0.0) / base_magic
	_x(d0, 10.0, G.DmgType.PHYSICAL)
	var b: float = spy.mult.get("x", 0.0) / base_phys
	_x(d0, 10.0, G.DmgType.TRUE)
	var tr: float = spy.mult.get("x", 0.0) / base_true
	d0.hp = d0.stats.max_hp * 0.6
	_x(d0, 10.0)
	var hi: float = spy.mult.get("x", 0.0) / base_magic
	_check("shadowflame", _near(a, 1.2, 0.0001) and _near(b, 1.0, 0.0001) and _near(tr, 1.2, 0.0001) and _near(hi, 1.0, 0.0001),
			"magic=%.2f phys=%.2f true=%.2f healthy=%.2f" % [a, b, tr, hi])

	await _equip([2523])
	_x(d0, 100.0, G.DmgType.PHYSICAL, {"is_attack": true})
	var near_m: float = spy.mult.get("x", 0.0) / base_attack
	_park(d0, 3.0)
	_x(d0, 100.0, G.DmgType.PHYSICAL, {"is_attack": true})
	var near_m2: float = spy.mult.get("x", 0.0) / base_attack
	_park(d0, 9.0)
	_x(d0, 100.0, G.DmgType.PHYSICAL, {"is_attack": true})
	var far_m: float = spy.mult.get("x", 0.0) / base_attack
	_x(d0, 100.0, G.DmgType.MAGIC)
	var spell_m: float = spy.mult.get("x", 0.0) / base_magic
	var dd: float = G.flat_dist(c.global_position, d0.global_position) / G.U
	_check("hexoptics magnification", _near(far_m, 1.1, 0.0001) and _near(spell_m, 1.0, 0.0001) and near_m > 1.0 and near_m2 > 1.0 and near_m2 < 1.1,
			"5m=%.3f 3m=%.3f 9m=%.3f spell=%.3f dist=%.0f" % [near_m, near_m2, far_m, spell_m, dd])
	d0.hp = 1.0
	_park(d0, 5.0)
	_x(d0, 5.0)
	var hit_it: Item = c.items[0]
	hit_it.on_takedown(d0)
	await _sim(0.3)
	var rng_bonus: float = c.stats.attack_range - float(c.stats.base.attack_range)
	_check("hexoptics arcane aim", _near(rng_bonus, 100.0, 0.01), "range bonus=%.1f" % rng_bonus)

	await _equip([4646])
	d0 = dummies[0]
	_park(dummies[1], 40.0)
	var ap: float = c.stats.ap
	_x(d0, d0.stats.max_hp * 0.32, G.DmgType.TRUE)
	await _sim(2.3)
	var want: float = 125.0 + 0.1 * ap
	_check("stormsurge squall", _near(spy.raw.get("stormsurge", 0.0), want, 0.05) and spy.cnt.get("stormsurge", 0) == 1,
			"raw=%.2f want=%.2f n=%d" % [spy.raw.get("stormsurge", 0.0), want, spy.cnt.get("stormsurge", 0)])
	spy.clear()
	_x(d0, d0.stats.max_hp * 0.3, G.DmgType.TRUE)
	await _sim(2.3)
	_check("stormsurge cooldown", spy.cnt.get("stormsurge", 0) == 0)

	await _equip([3118])
	d0 = dummies[0]
	_park(dummies[1], 40.0)
	ap = c.stats.ap
	_check("malignance ult haste", _near(c.stats.ult_haste, 20.0, 0.01), "ult_ah=%.1f" % c.stats.ult_haste)
	_hit(d0, 10.0, G.DmgType.MAGIC, 3)
	var mr0: float = d0.stats.mr
	await _sim(1.0)
	var mr1: float = d0.stats.mr
	await _sim(2.4)
	var per: float = (40.0 + 0.028 * ap) * 0.25
	var n: int = spy.cnt.get("malignance", 0)
	_check("malignance hatefog", n >= 11 and n <= 12 and _near(spy.raw.get("malignance", 0.0), per * n, 0.1),
			"n=%d raw=%.2f per=%.3f" % [n, spy.raw.get("malignance", 0.0), per])
	_check("malignance mr shred", _near(mr0 - mr1, 10.0, 0.05) or mr1 < mr0, "mr %.1f -> %.1f" % [mr0, mr1])
	spy.clear()
	_hit(d0, 10.0, G.DmgType.MAGIC, 0)
	await _sim(0.5)
	_check("malignance only ult", spy.cnt.get("malignance", 0) == 0)


# --------------------------------------------------------------------- Eternity family / Lost Chapter / Rod of Ages
func _t_eternity() -> void:
	var it: Item = (await _equip([3803]))[0]
	c.mana = 0.0
	var hurt := Combat.deal(dummies[0], c, 200.0, G.DmgType.TRUE, {"tag": "dmy"})
	_check("eternity mana from champion damage", _near(c.mana, 0.1 * hurt.mitigated, 0.3), "mana=%.1f mitigated=%.1f" % [c.mana, hurt.mitigated])
	var ab: Ability = c.abilities[0]
	var cost := ab.cost()
	c.hp = 500.0
	it.on_ability_cast(ab, {})
	var healed: float = c.hp - 500.0
	_check("eternity heal on cast", _near(healed, minf(20.0, 0.25 * cost) * (1.0 + c.stats.heal_power), 0.05), "healed=%.2f cost=%.0f" % [healed, cost])
	it.on_ability_cast(ab, {})
	_check("eternity heal cooldown", _near(c.hp - 500.0, healed, 0.05))

	var roa: Item = (await _equip([6657]))[0]
	var hp0: float = c.stats.max_hp
	var ap0: float = c.stats.ap
	roa.timer = 39.99
	await _sim(0.3)
	_check("rod of ages stack", roa.stacks == 1 and _near(c.stats.max_hp - hp0, 10.0, 0.01) and _near(c.stats.ap - ap0, 3.0, 0.01),
			"stacks=%d hp+%.1f ap+%.1f" % [roa.stacks, c.stats.max_hp - hp0, c.stats.ap - ap0])
	# level reward: use a lower level champion
	roa.stacks = 9
	roa.timer = 39.99
	var lvl0: int = c.level
	c.level = 12
	await _sim(0.3)
	_check("rod of ages level", c.level == 13 and roa.stacks == 10, "level=%d stacks=%d" % [c.level, roa.stacks])
	c.level = lvl0
	c.recompute_stats()

	var lc: Item = (await _equip([3802]))[0]
	c.mana = 0.0
	lc.on_level_up(c.level)
	await _sim(3.3)
	var want: float = 0.2 * c.stats.max_mana
	_check("lost chapter restore", absf(c.mana - want) < 0.05 * want + 20.0 and c.mana > want * 0.8, "mana=%.1f want=%.1f" % [c.mana, want])


# --------------------------------------------------------------------- actives
func _t_actives() -> void:
	var it: Item = (await _equip([2420]))[0]
	_check("seekers active cd", it.active_cd > 0.0, "cd=%.1f" % it.active_cd)
	it.activate(c.global_position, null)
	await _sim(0.2)
	_check("seekers stasis", (c.cc & Buff.CC.STASIS) != 0 and c.is_invulnerable())
	_check("seekers breaks", c.items.size() == 1 and c.items[0].item_id == 2421, str(c.items.map(func(x): return x.item_id)))
	await _sim(2.6)
	_check("seekers stasis ends", (c.cc & Buff.CC.STASIS) == 0)

	it = (await _equip([3152]))[0]
	_park(dummies[1], 40.0)
	var ap: float = c.stats.ap
	var d0: Champion = dummies[0]
	c.face_toward(d0.global_position, 1000.0)
	var p0: Vector3 = c.global_position
	it.activate(d0.global_position, null)
	await _sim(2.5)
	var want: float = 135.0 + 0.15 * ap
	_check("rocketbelt damage", _near(spy.raw.get("rocketbelt", 0.0), want, 0.05) and spy.cnt.get("rocketbelt", 0) == 1,
			"raw=%.2f want=%.2f n=%d" % [spy.raw.get("rocketbelt", 0.0), want, spy.cnt.get("rocketbelt", 0)])
	_check("rocketbelt dash", G.flat_dist(c.global_position, p0) > 2.0, "moved=%.2f" % G.flat_dist(c.global_position, p0))
	_check("rocketbelt cooldown", _near(it.active_cd, 50.0, 0.01) and it.active_left > 40.0, "cd=%.1f left=%.1f" % [it.active_cd, it.active_left])

	it = (await _equip([2522]))[0]
	ap = c.stats.ap
	var ab: Ability = c.abilities[0]
	var mana_before := c.mana
	it.on_ability_cast(ab, {})
	_check("actualizer inactive", _near(c.mana, mana_before, 0.001))
	it.activate(c.global_position, null)
	var amp: float = 0.01 * (15.0 + 0.005 * c.stats.max_mana)
	c.mana = c.stats.max_mana
	mana_before = c.mana
	it.on_ability_cast(ab, {})
	_check("actualizer cost", _near(mana_before - c.mana, ab.cost(), 0.01), "paid=%.1f cost=%.1f" % [mana_before - c.mana, ab.cost()])
	_hit(dummies[0], 10.0, G.DmgType.MAGIC, 0, "sp")
	_check("actualizer damage amp", _near(spy.mult.get("sp", 0.0) / base_magic, 1.0 + amp, 0.0001), "mult=%.4f amp=%.4f" % [spy.mult.get("sp", 0.0) / base_magic, amp])
	ab.cd = 10.0
	await _sim(1.0)
	_check("actualizer cooldown tick", _near(ab.cd, 10.0 - 1.3, 0.12), "cd=%.2f" % ab.cd)
	var sh := Combat.shield(c, c, 100.0, 2.0)
	_check("actualizer shield amp", _near(float(sh.amount), 100.0 * (1.0 + c.stats.heal_power) * (1.0 + amp) * base_shield, 0.05), "shield=%.2f" % float(sh.amount))


# --------------------------------------------------------------------- conditional / passive stat items
func _t_conditional() -> void:
	var it: Item = (await _equip([8020]))[0]
	var d0: Champion = dummies[0]
	await _sim(0.6)
	_x(d0, 10.0)
	_check("abyssal mask amp", _near(spy.mult.get("x", 0.0) / base_magic, 1.12, 0.0001), "mult=%.3f" % (spy.mult.get("x", 0.0) / base_magic))
	_x(d0, 10.0, G.DmgType.PHYSICAL)
	_check("abyssal mask physical", _near(spy.mult.get("x", 0.0) / base_phys, 1.0, 0.0001))
	_park(d0, 9.0)
	await _sim(1.0)
	_x(d0, 10.0)
	_check("abyssal mask range", _near(spy.mult.get("x", 0.0) / base_magic, 1.0, 0.0001), "mult=%.3f" % (spy.mult.get("x", 0.0) / base_magic))

	it = (await _equip([2504]))[0]
	it.quiet = 15.0
	await _sim(0.2)
	var shield: float = c.total_shield(G.DmgType.MAGIC)
	_check("kaenic shield", _near(shield, 0.15 * c.stats.max_hp, 0.5), "shield=%.1f hp=%.0f" % [shield, c.stats.max_hp])
	Combat.deal(dummies[0], c, 30.0, G.DmgType.MAGIC, {"tag": "dmy"})
	_check("kaenic resets", it.quiet < 0.5 and c.total_shield(G.DmgType.MAGIC) < shield)
	c.hp = c.stats.max_hp

	await _equip([6621])
	await _sim(0.3)
	_check("dawncore", _near(c.stats.m("ap"), 45.0 + 10.0, 0.05) and _near(c.stats.m("heal_power"), 0.16 + 0.02, 0.0001),
			"ap=%.1f hsp=%.3f" % [c.stats.m("ap"), c.stats.m("heal_power")])

	await _equip([4629])
	d0 = dummies[0]
	for i in 4:
		_hit(d0, 10.0, G.DmgType.MAGIC, 0)
	await _sim(0.3)
	_check("cosmic drive stacks", _near(c.stats.m("ms"), 60.0, 0.01), "ms=%.1f" % c.stats.m("ms"))
	await _sim(4.3)
	_check("cosmic drive ends", _near(c.stats.m("ms"), 0.0, 0.01))

	var rr: Item = (await _equip([123430]))[0]
	var crit0: float = c.stats.m("crit")
	rr.on_ability_cast(c.abilities[0], {})
	rr.on_ability_cast(c.abilities[0], {})
	rr.on_ability_cast(c.abilities[1], {})
	await _sim(0.3)
	_check("rite of ruin crit", _near(c.stats.m("crit") - crit0, 0.05, 0.0001), "crit +%.3f" % (c.stats.m("crit") - crit0))
	var got := 0
	var last := 0.0
	for i in 60:
		rr.last_cast.clear()
		spy.clear()
		rr.on_ability_cast(c.abilities[0], {})
		if spy.shields > 0:
			got += 1
			last = spy.shield_last
	var want: float = (70.0 + (210.0 - 70.0) * clampf((c.level - 1) / 17.0, 0.0, 1.0) + 0.15 * c.stats.ap + 0.25 * c.stats.bonus_ad) * (1.0 + c.stats.heal_power) * base_shield
	_check("rite of ruin shield", got > 5 and _near(last, want, 0.1), "procs=%d/60 last=%.1f want=%.1f" % [got, last, want])


# --------------------------------------------------------------------- debuffs
func _t_debuffs() -> void:
	await _equip([8010])
	var d0: Champion = dummies[0]
	_hit(d0, 10.0, G.DmgType.MAGIC, 0)
	await _sim(0.4)
	_hit(d0, 10.0, G.DmgType.MAGIC, 0)
	await _sim(0.4)
	var base_mr: float = d0.stats.base_mr
	_check("bloodletter stacks", _near(d0.stats.mr, base_mr * (1.0 - 0.15), 0.05), "mr=%.2f base=%.2f" % [d0.stats.mr, base_mr])
	await _sim(6.5)
	_check("bloodletter expires", _near(d0.stats.mr, base_mr, 0.05))

	await _equip([4628])
	d0 = dummies[0]
	_park(d0, 4.0)
	_hit(d0, 10.0, G.DmgType.MAGIC, 0, "hs")
	_check("hypershot short range", _near(spy.mult.get("hs", 0.0) / base_magic, 1.0, 0.0001) and d0.buffs.filter(func(b): return b.id.begins_with("hypershot")).is_empty())
	_park(d0, 8.0)
	_park(dummies[1], 9.0)
	_hit(d0, 10.0, G.DmgType.MAGIC, 0, "hs")
	var marked: bool = not d0.buffs.filter(func(b): return b.id.begins_with("hypershot")).is_empty()
	var marked2: bool = not dummies[1].buffs.filter(func(b): return b.id.begins_with("hypershot")).is_empty()
	_hit(d0, 10.0, G.DmgType.MAGIC, 0, "hs")
	_check("hypershot mark + focus", marked and marked2 and _near(spy.mult.get("hs", 0.0) / base_magic, 1.1, 0.0001), "marked=%s focus=%s mult=%.3f" % [marked, marked2, spy.mult.get("hs", 0.0) / base_magic])


# --------------------------------------------------------------------- Cryptbloom (kills the dummy: last)
func _t_cryptbloom() -> void:
	await _equip([3137])
	var d0: Champion = dummies[0]
	_park(dummies[1], 40.0)
	var ap: float = c.stats.ap
	_x(d0, 10.0)
	d0.hp = 1.0
	c.hp = 100.0
	_x(d0, 500.0, G.DmgType.TRUE)
	await _sim(0.1)
	var want: float = (100.0 + 0.2 * ap) * (1.0 + c.stats.heal_power)
	_check("cryptbloom heal", d0.dead and _near(c.hp - 100.0, want, 1.0), "dead=%s healed=%.1f want=%.1f" % [d0.dead, c.hp - 100.0, want])
