extends Node
## [numbers] Exact number checks for the Manaflow upgrades (src/items/item_fx_x_upgrades.gd): Archangel's -> Seraph's Embrace,
## Manamune -> Muramana, Winter's Approach -> Fimbulwinter, Whispering Circlet -> Diadem of Songs.
##   godot --headless --path . --fixed-fps 60 --quit-after 9000 -- --champ=Lux --harness=res://src/items/tests/upgrade_test.gd
## (also --champ=Malphite for the melee numbers; manaless champions get no benefit from mana items). Output: "UPTEST PASS|FAIL <name> <detail>" and "UPTEST DONE passes=N fails=N".

var main = null
var match_ref = null

var m = null
var c: Champion = null
var dummies: Array = []
var spot := Vector3.ZERO
var passes := 0
var fails := 0
var spy: Spy = null
var base_shield := 1.0     ## ARAM / Mayhem shield modifiers already on every shield (measured without items)


class Spy extends Effect:
	var raw := {}
	var cnt := {}
	var shield_last := 0.0
	var shields := 0
	var heal_last := 0.0
	var heals := 0

	func on_heal_dealt(_t, amount: float) -> void:
		heal_last = amount
		heals += 1

	func _init() -> void:
		id = "harness_spy"
		hidden = true

	func on_damage_dealt(info) -> void:
		var k: String = info.tag if info.tag != "" else "none"
		raw[k] = raw.get(k, 0.0) + info.amount
		cnt[k] = cnt.get(k, 0) + 1

	func on_shield_dealt(_t, amount: float) -> void:
		shield_last = amount
		shields += 1

	func clear() -> void:
		raw.clear()
		cnt.clear()
		shield_last = 0.0
		shields = 0
		heal_last = 0.0
		heals = 0


func _ready() -> void:
	_run()


func _frame() -> void:
	await get_tree().process_frame


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
	print("UPTEST %s %s %s" % ["PASS" if ok else "FAIL", name, detail])
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
	await _sim(0.3)
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


func _ids() -> Array:
	return c.items.map(func(i): return i.item_id)


func _run() -> void:
	for i in 60:
		await _frame()
	_setup()
	for i in 30:
		await _frame()
	print("UPTEST player=%s level=%d melee=%s" % [c.alias, c.level, str(float(c.stats.base.get("attack_range", 550.0)) < 300.0)])
	await _equip([])
	var sh0 := Combat.shield(c, c, 100.0, 2.0)
	base_shield = float(sh0.amount) / 100.0
	print("UPTEST baseline shield=%.3f" % base_shield)
	_registered()
	await _t_transform()
	await _t_seraph()
	await _t_muramana()
	await _t_fimbulwinter()
	await _t_diadem()
	print("UPTEST DONE passes=%d fails=%d" % [passes, fails])
	get_tree().quit()


func _registered() -> void:
	var bad := []
	for id in [3040, 3042, 3121, 2530]:
		var it := ItemDB.create(id)
		if it == null or not ItemFxExtra.has(id):
			bad.append(id)
	_check("registered", bad.is_empty(), str(bad))
	_check("not sold", not ItemDB.visible_in_shop(3040) and not ItemDB.visible_in_shop(3042) and not ItemDB.visible_in_shop(3121) and not ItemDB.visible_in_shop(2530))
	_check("costs", ItemDB.cost_of(3040) == 2900 and ItemDB.cost_of(3042) == 2900 and ItemDB.cost_of(3121) == 2400 and ItemDB.cost_of(2530) == 2250)


## The Manaflow items transform at 360 bonus mana, in the same inventory slot.
func _t_transform() -> void:
	var items: Array = await _equip([1001, 3003, 1036])
	var arch: Item = items[1]
	arch.gained = 350.0
	arch.charges = 3
	arch._land(true)          # +15 -> capped at 360
	await _sim(0.3)
	_check("archangel -> seraph", _ids() == [1001, 3040, 1036], str(_ids()))
	items = await _equip([3004, 1001])
	var mana: Item = items[0]
	mana.gained = 357.0
	mana.charges = 3
	mana._land(true)
	await _sim(0.3)
	_check("manamune -> muramana", _ids() == [3042, 1001], str(_ids()))
	items = await _equip([3119])
	var wint: Item = items[0]
	wint.gained = 357.0
	wint.charges = 3
	wint._consume(dummies[0])
	await _sim(0.3)
	_check("winter's approach -> fimbulwinter", _ids() == [3121], str(_ids()))
	items = await _equip([2526])
	var circ: Item = items[0]
	circ.gained = 358.0
	circ.ammo = 5.0
	circ._grant(true)
	await _sim(0.3)
	_check("whispering circlet -> diadem", _ids() == [2530], str(_ids()))
	# the Circlet's cap is 360 BONUS mana (it used to stop at 60)
	items = await _equip([2526])
	circ = items[0]
	circ.ammo = 5.0
	for i in 5:
		circ._grant(false)
	_check("circlet manaflow 5 x 4 = 20 bonus mana", _near(circ.gained, 20.0, 0.01) and _ids() == [2526], "gained=%.1f" % circ.gained)


func _t_seraph() -> void:
	var it: Item = (await _equip([3040]))[0]
	var mx: float = c.stats.max_mana
	var bonus: float = c.stats.m("mana")
	_check("seraph stats", _near(it.stats.get("ap", 0.0), 70.0) and _near(it.stats.get("ah", 0.0), 25.0) and _near(it.stats.get("mana", 0.0), 1000.0))
	_check("seraph awe 2% bonus mana", _near(c.stats.m("ap"), 70.0 + 0.02 * bonus, 0.1), "ap=%.2f want=%.2f" % [c.stats.m("ap"), 70.0 + 0.02 * bonus])
	c.shields.clear()
	c.hp = c.stats.max_hp * 0.35
	spy.clear()
	var hp0 := c.hp
	Combat.deal(dummies[0], c, c.stats.max_hp * 0.2, G.DmgType.TRUE, {"tag": "x"})
	var sh: float = spy.shield_last
	var want_sh: float = 0.18 * mx * (1.0 + c.stats.heal_power) * base_shield
	_check("seraph lifeline shield 18% max mana", sh > 0.0 and _near(sh, want_sh, 1.0), "shield=%.1f want=%.1f hp %.0f -> %.0f" % [sh, want_sh, hp0, c.hp])
	_check("seraph lifeline cooldown 75", _near(it.icd, 75.0, 0.5), "icd=%.1f" % it.icd)
	c.shields.clear()
	c.hp = c.stats.max_hp * 0.35
	Combat.deal(dummies[0], c, c.stats.max_hp * 0.2, G.DmgType.TRUE, {"tag": "x"})
	_check("seraph lifeline on cooldown", c.shields.is_empty())


func _t_muramana() -> void:
	var it: Item = (await _equip([3042]))[0]
	var mx: float = c.stats.max_mana
	_check("muramana awe 2% max mana", _near(c.stats.m("ad"), 35.0 + 0.02 * mx, 0.1), "ad=%.2f want=%.2f" % [c.stats.m("ad"), 35.0 + 0.02 * mx])
	var melee: bool = float(c.stats.base.get("attack_range", 550.0)) < 300.0
	spy.clear()
	c.attack_hit(dummies[0], false)
	await _sim(0.1)
	_check("muramana shock on-hit 1.2% max mana", _near(spy.raw.get("shock", 0.0), 0.012 * mx, 0.2) and spy.cnt.get("shock", 0) == 1, "raw=%.2f want=%.2f" % [spy.raw.get("shock", 0.0), 0.012 * mx])
	spy.clear()
	_hit(dummies[0])
	c.abilities[0].cast_count -= 1
	_hit(dummies[0])          # same cast: one proc per cast instance and target
	await _sim(0.1)
	var r := 0.04 if melee else 0.03
	_check("muramana shock ability %d%% max mana, once per cast" % int(r * 100.0), _near(spy.raw.get("shock", 0.0), r * mx, 0.2) and spy.cnt.get("shock", 0) == 1, "raw=%.2f want=%.2f n=%d" % [spy.raw.get("shock", 0.0), r * mx, spy.cnt.get("shock", 0)])


func _t_fimbulwinter() -> void:
	var it: Item = (await _equip([3121]))[0]
	var bonus: float = c.stats.m("mana")
	var hp_item: float = 550.0 + 0.15 * bonus
	_check("fimbulwinter awe 15% bonus mana as health", _near(c.stats.m("hp"), hp_item, 1.0), "hp=%.1f want=%.1f" % [c.stats.m("hp"), hp_item])
	var melee: bool = float(c.stats.base.get("attack_range", 550.0)) < 300.0
	c.shields.clear()
	spy.clear()
	var cur := c.mana
	var b := K.root(dummies[0], 1.0, c)
	await _sim(0.1)
	var sh: float = spy.shield_last
	var want: float = (100.0 + 0.045 * cur) * 1.8 * (1.0 + c.stats.heal_power) * base_shield     # two enemy champions inside 1200 units
	_check("fimbulwinter shield (100 + 4.5% mana) x1.8 with 2 enemies near", _near(sh, want, 3.0), "shield=%.1f want=%.1f melee=%s" % [sh, want, str(melee)])
	_check("fimbulwinter cooldown 8", _near(it.icd, 8.0, 0.5) or sh <= 0.0, "icd=%.1f" % it.icd)


func _t_diadem() -> void:
	var it: Item = (await _equip([2530]))[0]
	var bonus: float = c.stats.m("mana")
	_check("diadem harmony 0.5% per 100 bonus mana + 8%", _near(c.stats.heal_power, 0.08 + 0.00005 * bonus, 0.001), "hsp=%.4f want=%.4f" % [c.stats.heal_power, 0.08 + 0.00005 * bonus])
	# consonance: an allied champion nearby, you in combat -> 0.8% max mana heal every second (ARAM halves heals on others)
	var ally: Champion = null
	for ch in m.champions:
		if ch != c and ch.team == c.team and not ch.dead:
			ally = ch
			break
	if ally == null:
		_check("diadem consonance (no ally to test)", true)
		return
	ally.teleport(m.nav.nearest_walkable(spot + Vector3(1.5, 0, 0)))
	ally.issue_move(ally.global_position)
	ally.hp = ally.stats.max_hp * 0.5
	c.last_combat_time = m.time
	spy.clear()
	it._tick = 0.0
	await _sim(0.5)
	var got: float = spy.heal_last
	var want: float = 0.008 * c.stats.max_mana * (1.0 + c.stats.heal_power) * Rules.ARAM_OUTGOING_HEAL
	_check("diadem consonance heals the ally once", spy.heals == 1 and _near(got, want, 0.3), "got=%.2f want=%.2f n=%d" % [got, want, spy.heals])
