extends Node
## Exact-number checks for the support item family (src/items/item_fx_x_support.gd).
##   godot --headless --path . --fixed-fps 60 --quit-after 3000 -- --sim --botplayer --time=60 --seed=3 --champ=Sona \
##        --harness=res://src/items/tests/support_test.gd
## Output lines: SUPPORTTEST PASS/FAIL ...

var match_ref = null
var main = null
var c: Champion
var a1: Champion
var a2: Champion
var e1: Champion
var fails := 0
var spy: Spy


class Spy extends Effect:
	var dealt := {}

	func _init() -> void:
		id = "support_spy"
		hidden = true

	func on_damage_dealt(info) -> void:
		dealt[info.tag] = float(dealt.get(info.tag, 0.0)) + info.final + info.absorbed


func ck(name: String, got: float, want: float, tol: float = 0.6) -> void:
	var ok := absf(got - want) <= tol
	if not ok:
		fails += 1
	print("SUPPORTTEST %s %s got=%.2f want=%.2f" % ["PASS" if ok else "FAIL", name, got, want])


func ckb(name: String, ok: bool) -> void:
	if not ok:
		fails += 1
	print("SUPPORTTEST %s %s" % ["PASS" if ok else "FAIL", name])


func _ready() -> void:
	await get_tree().create_timer(0.5, true, false, true).timeout
	await _run()
	print("SUPPORTTEST done fails=%d" % fails)
	get_tree().quit()


func _strip() -> void:
	for it in c.items.duplicate():
		c.remove_item(it)
	for u in [c, a1, a2, e1]:
		for b in u.buffs.duplicate():
			u.remove_buff(b)
		u.shields.clear()
	c.recompute_stats()


func _equip(ids: Array) -> void:
	_strip()
	for id in ids:
		c.add_item(ItemDB.create(id))
	c.recompute_stats()


func _reset() -> void:
	var p: Vector3 = c.global_position
	for u in match_ref.champions:
		if u != c and u != a1 and u != a2 and u != e1:
			u.global_position = p + Vector3(300, 0, 0)
	a1.global_position = p + Vector3(2, 0, 0)
	a2.global_position = p + Vector3(0, 0, 3)
	e1.global_position = p + Vector3(-3, 0, 0)
	for u in [c, a1, a2, e1]:
		u.hp = u.stats.max_hp
		u.shields.clear()
		u.cleanse()
		for b in u.buffs.duplicate():
			if b.id.begins_with("ardent") or b.id.begins_with("imperial") or b.id.begins_with("flowing") or b.id.begins_with("zeke"):
				u.remove_buff(b)


func _run() -> void:
	c = G.player
	while c.level < 13:
		c.gain_xp(1000.0)
	for u in match_ref.champions:
		if u == c:
			continue
		if u.team == c.team:
			if a1 == null:
				a1 = u
			elif a2 == null:
				a2 = u
		elif e1 == null:
			e1 = u
	var tank := Effect.new()
	tank.stats = {"hp": 100000.0}
	e1.add_effect(tank)
	spy = Spy.new()
	c.add_effect(spy)
	_reset()

	# ---- Guardian's Horn: 15 from attacks / spells, 25% vs damage over time
	_equip([])
	_reset()
	var before := c.hp
	Combat.deal(e1, c, 100.0, G.DmgType.PHYSICAL, {"is_attack": true, "show_number": false})
	var l0 := before - c.hp
	c.hp = c.stats.max_hp
	_equip([2051])
	_reset()
	before = c.hp
	Combat.deal(e1, c, 100.0, G.DmgType.PHYSICAL, {"is_attack": true, "show_number": false})
	ck("horn physical attack blocks 15", before - c.hp, l0 - 15.0)
	c.hp = c.stats.max_hp
	_equip([])
	_reset()
	before = c.hp
	Combat.deal(e1, c, 100.0, G.DmgType.MAGIC, {"is_spell": true, "is_dot": true, "show_number": false})
	l0 = before - c.hp
	_equip([2051])
	_reset()
	before = c.hp
	Combat.deal(e1, c, 100.0, G.DmgType.MAGIC, {"is_spell": true, "is_dot": true, "show_number": false})
	ck("horn magic DoT blocks 3.75", before - c.hp, l0 - 3.75)

	# ---- Guardian's Orb: mana regen / health regen without mana
	_equip([3112])
	ckb("orb uses_mana=%s mana_regen=%.2f" % [str(c.stats.uses_mana), c.stats.mana_regen], true)

	# ---- Locket: 290 + 7/level from level 9, x(1+heal power), diminished 25% when repeated within 20 s
	_equip([3190])
	_reset()
	var loc: Item = c.items[0]
	loc.activate(c.global_position, null)
	var want := (290.0 + 7.0 * 5.0) * (1.0 + c.stats.heal_power)
	ck("locket shield on ally", a1.total_shield(), want, 1.0)
	ck("locket shield on self", c.total_shield(), want, 1.0)
	var t0: float = match_ref.time
	loc.active_left = 0.0
	loc.activate(c.global_position, null)
	ckb("locket diminished second cast (a1 shield %.0f)" % a1.total_shield(), a1.total_shield() <= want + 0.25 * want + 1.0)

	# ---- Ardent Censer: on heal ally -> both get Sanctify, on-hit 20 magic
	_equip([3504])
	_reset()
	a1.hp = 100.0
	Combat.heal(c, a1, 50.0)
	var b1: Buff = a1.find_buff("ardent_sanctify")
	var b2: Buff = c.find_buff("ardent_sanctify")
	ckb("ardent buff on ally and self", b1 != null and b2 != null)
	if b1 != null:
		ck("ardent attack speed", b1.stats.get("as", 0.0), 0.25, 0.001)
	_reset()
	Combat.heal(c, c, 50.0)
	ckb("ardent not triggered by self heal", c.find_buff("ardent_sanctify") == null)

	# ---- Moonstone chain
	_equip([6617])
	_reset()
	a1.hp = 100.0
	a2.hp = 100.0
	var hpw := 1.0 + c.stats.heal_power
	Combat.heal(c, a1, 100.0)
	ck("moonstone first heal (ARAM -50% on others)", a1.hp - 100.0, 50.0 * hpw)
	ck("moonstone chain heal 30%", a2.hp - 100.0, 15.0 * hpw, 0.8)
	_reset()
	Combat.shield(c, a1, 200.0, 3.0)
	ck("moonstone chain shield 35%", a2.total_shield(), 70.0 * hpw, 0.8)

	# ---- Echoes of Helia: 30% of pre-mitigation damage to champions stored, released on heal
	_equip([6620])
	_reset()
	Combat.deal(c, e1, 200.0, G.DmgType.MAGIC, {"is_proc": true, "show_number": false})
	a1.hp = 100.0
	Combat.heal(c, a1, 50.0)
	hpw = 1.0 + c.stats.heal_power
	ck("echoes heal + 60 soul charges", a1.hp - 100.0, 25.0 * hpw + 60.0, 1.0)
	a1.hp = 100.0
	Combat.heal(c, a1, 50.0)
	ck("echoes charges consumed", a1.hp - 100.0, 25.0 * hpw, 1.0)

	# ---- Staff of Flowing Water: Rapids
	_equip([6616])
	_reset()
	a1.hp = 100.0
	Combat.heal(c, a1, 50.0)
	var r1: Buff = a1.find_buff("flowing_rapids")
	ckb("rapids on ally and self", r1 != null and c.find_buff("flowing_rapids") != null)
	if r1 != null:
		ck("rapids AP", r1.stats.get("ap", 0.0), 40.0, 0.01)
		ck("rapids AH", r1.stats.get("ah", 0.0), 15.0, 0.01)

	# ---- Sword of Blossoming Dawn: AS = 1.2 x heal power
	_equip([124011])
	await get_tree().process_frame
	await get_tree().process_frame
	c.recompute_stats()
	ck("blossom bonus AS stat (heal power %.2f)" % c.stats.heal_power, c.stats.m("as"), 1.2 * c.stats.heal_power, 0.002)
	_reset()
	a1.hp = 100.0
	c.hp = c.stats.max_hp
	var it: Item = c.items[0]
	var info := DamageInfo.new(c, e1, 10.0, G.DmgType.PHYSICAL)
	info.is_attack = true
	it.on_attack_hit(e1, info)
	var exp_heal := 0.5 * (15.0 + 30.0 * 12.0 / 17.0 + 0.10 * c.stats.bonus_ad + 0.07 * c.stats.ap) * (1.0 + c.stats.heal_power)
	ck("blossom peppermint heal (lowest ally)", a1.hp - 100.0, exp_heal, 1.0)

	# ---- Mikael's: cleanse + heal 100-250
	_equip([3222])
	_reset()
	K.stun(a1, 2.0, e1)
	a1.hp = 100.0
	var mk: Item = c.items[0]
	mk.activate(a1.global_position, a1)
	ckb("mikael cleansed stun", (a1.cc & Buff.CC.STUN) == 0)
	ck("mikael heal", a1.hp - 100.0, 0.5 * (100.0 + 150.0 * 12.0 / 17.0) * (1.0 + c.stats.heal_power), 1.0)

	# ---- Knight's Vow: redirect 14% of Worthy damage, heal 12% of damage Worthy deals
	_equip([3109])
	_reset()
	var kv: Item = c.items[0]
	kv.activate(a1.global_position, a1)
	var c_hp0 := c.hp
	var a_hp0 := a1.hp
	Combat.deal(e1, a1, 100.0, G.DmgType.MAGIC, {"is_spell": true, "show_number": false})
	var ally_lost := a_hp0 - a1.hp
	var holder_lost := c_hp0 - c.hp
	ckb("vow redirects damage (ally %.1f, holder %.1f)" % [ally_lost, holder_lost], holder_lost > 0.5 and absf(holder_lost / (ally_lost + holder_lost) - 0.14) < 0.01)
	c.hp = c.stats.max_hp - 200.0
	c_hp0 = c.hp
	var eh0: float = e1.hp
	Combat.deal(a1, e1, 100.0, G.DmgType.TRUE, {"is_spell": true, "show_number": false})
	ck("vow heals 12% of damage dealt by Worthy", c.hp - c_hp0, 0.12 * (eh0 - e1.hp), 0.3)

	# ---- Shurelya's: nearby allies get 30% move speed
	_equip([2065])
	_reset()
	var sh: Item = c.items[0]
	sh.activate(c.global_position, null)
	var hb: Buff = a1.find_buff("shurelya_ms")
	ckb("shurelya haste on ally", hb != null)
	if hb != null:
		ck("shurelya ms%", hb.get_stat_mods().get("ms%", 0.0), 0.30, 0.001)

	# ---- Imperial Mandate: immobilize -> 7% Vulnerable for allies' damage
	_equip([4005])
	_reset()
	K.stun(e1, 1.0, c)
	var vb: Buff = e1.find_buff("imperial_vulnerable_%d" % c.team)
	ckb("imperial vulnerable mark", vb != null)
	_reset()
	e1.cleanse()
	e1.remove_buffs_by_id("imperial_vulnerable_%d" % c.team)
	var base_hp := e1.hp
	Combat.deal(a1, e1, 100.0, G.DmgType.TRUE, {"is_spell": true, "show_number": false})
	var d0 := base_hp - e1.hp
	K.stun(e1, 1.0, c)
	base_hp = e1.hp
	Combat.deal(a1, e1, 100.0, G.DmgType.TRUE, {"is_spell": true, "show_number": false})
	ck("imperial +7% damage from allies", base_hp - e1.hp, d0 * 1.07, 0.5)

	# ---- Verdant Barrier: blocks the first enemy spell
	_equip([4632])
	_reset()
	before = c.hp
	Combat.deal(e1, c, 100.0, G.DmgType.MAGIC, {"is_spell": true, "show_number": false})
	ck("verdant blocks first spell", before - c.hp, 0.0, 0.01)
	Combat.deal(e1, c, 100.0, G.DmgType.MAGIC, {"is_spell": true, "show_number": false})
	ckb("verdant second spell hits", before - c.hp > 10.0)

	# ---- Zeke's: ultimate readies a storm, near an enemy champion it burns 30/s
	_equip([3050])
	_reset()
	ck("zeke ult haste", c.stats.ult_haste, 15.0, 0.01)
	var zk: Item = c.items[0]
	var ult := Ability.new(c)
	ult.is_ult = true
	zk.on_ability_cast(ult, {})
	e1.global_position = c.global_position + Vector3(2.0, 0, 0)
	e1.hp = e1.stats.max_hp
	var ez := e1.hp
	var slowed := false
	for i in 110:
		e1.global_position = c.global_position + Vector3(2.0, 0, 0)
		await get_tree().process_frame
		if e1.find_buff("zeke_slow") != null:
			slowed = true
	var zdmg: float = spy.dealt.get("zeke", 0.0)
	ckb("zeke storm burning (%.1f dmg in ~1.5 s, 30/s x mr factor)" % zdmg, zdmg > 25.0 and zdmg < 60.0)
	ckb("zeke storm slows", slowed)
	_strip()

	# ---- Whispering Circlet: Harmony 0.5% heal/shield power per 100 bonus mana, Manaflow +8 max mana per charge vs champions
	_equip([2526])
	await get_tree().process_frame
	await get_tree().process_frame
	c.recompute_stats()
	var wc: Item = c.items[0]
	var bm: float = c.stats.max_mana - (c.stats.base.mana_base + Stats.growth(c.stats.base.mana_per_level, c.level))
	ck("circlet heal power = 8% + 0.5%/100 bonus mana (bonus mana %d)" % int(bm), c.stats.heal_power, 0.08 + 0.00005 * bm, 0.002)
	var mana0: float = c.stats.max_mana
	var ai := DamageInfo.new(c, e1, 10.0, G.DmgType.PHYSICAL)
	ai.is_attack = true
	wc.on_attack_hit(e1, ai)
	c.recompute_stats()
	ck("circlet manaflow on-hit vs champion +8 max mana", c.stats.max_mana - mana0, 8.0, 0.01)
	ck("circlet charges left", wc.ammo, 4.0, 0.1)

	# ---- Bandlepipes: slowing an enemy champion -> 20 move speed, allies attack speed
	_equip([2524])
	_reset()
	var bp: Item = c.items[0]
	var ms0: float = c.stats.move_speed
	K.slow(e1, 0.3, 1.0, c)
	for i in 40:
		await get_tree().process_frame
	var fb: Buff = a1.find_buff("bandle_fanfare")
	ckb("bandlepipes fanfare aura on ally", fb != null)
	if fb != null:
		var is_melee_a: bool = float(a1.stats.base.get("attack_range", 550.0)) < 300.0
		ck("bandlepipes ally attack speed", fb.stats.get("as", 0.0), 0.3 if is_melee_a else 0.3 * 0.667, 0.001)
	ck("bandlepipes self +20 ms", c.stats.m("ms"), 20.0, 0.01)

	# ---- Guardian's Orb without mana: health regen instead
	_strip()
	var had: bool = c.stats.uses_mana
	c.stats.uses_mana = false
	c.add_item(ItemDB.create(3112))
	c.recompute_stats()
	ck("orb (manaless) hp regen mod", c.stats.m("hp_regen"), 3.0, 0.01)
	c.stats.uses_mana = had
	_strip()

	# ---- bot decisions: put the active items on a bot ally in a hurt, enemy-adjacent situation
	_strip()
	_reset()
	var bot: Champion = a1
	var brain = bot.controller
	if brain != null:
		bot.global_position = c.global_position + Vector3(2, 0, 0)
		e1.global_position = bot.global_position + Vector3(3, 0, 0)
		c.hp = c.stats.max_hp * 0.3
		bot.hp = bot.stats.max_hp * 0.3
		for id in [3190, 2065, 3109, 3222, 3107]:
			var bi := ItemDB.create(id)
			bot.add_item(bi)
			brain.mode = "fight"
			brain._gather()
			var want_fire: bool = bi.ai_should_activate(brain)
			ckb("bot decision %s -> %s (enemies %d, allies %d)" % [bi.display_name, str(want_fire), brain.enemies.size(), brain.allies.size()], true)
			if want_fire and id != 3107:
				bi.activate(Vector3.ZERO, null)
			bot.remove_item(bi)
	_reset()

	# ---- Redemption: 150-350 to allies, 10% max hp true damage to enemy champions, after 2.5 s
	_equip([3107])
	_reset()
	a1.hp = 100.0
	var e_hp: float = e1.hp
	spy.dealt.clear()
	var rd: Item = c.items[0]
	rd.activate(c.global_position, null)
	ck("redemption not instant", a1.hp, 100.0, 0.01)
	for i in 165:
		e1.global_position = a1.global_position + Vector3(0.0, 0, 1.0)
		await get_tree().process_frame
	var rexp := 0.5 * (150.0 + 200.0 * 12.0 / 17.0) * (1.0 + c.stats.heal_power)
	ck("redemption heal", a1.hp - 100.0, rexp, 9.0)
	ck("redemption true damage 10% max health", spy.dealt.get("redemption", 0.0), 0.1 * e1.stats.max_hp, 5.0)

