extends Node
## Exact-number checks for the bruiser item family (src/items/item_fx_x_bruiser.gd).
## godot --headless --path . --fixed-fps 60 --quit-after 9000 -- --sim --botplayer --time=300 --seed=3 --champ=Garen \
##        --harness=res://src/items/tests/bruiser_test.gd      (also --champ=Ezreal for the ranged numbers)
## Output: "BXTEST PASS|FAIL <name> <detail>", final "BXTEST DONE passes=N fails=N".

var main = null
var match_ref = null

var m = null
var c: Champion = null
var d: Champion = null
var d2: Champion = null
var tr: Tracker = null
var fails := 0
var passes := 0
var spot := Vector3.ZERO
var fwd := Vector3.FORWARD
var melee := true


## sim_monitor re-installs a BotBrain on the player every frame when it is not one: an idle BotBrain keeps it passive.
class IdleBrain extends BotBrain:
	func think(_dt: float) -> void:
		pass

	func think_dead(_dt: float) -> void:
		pass


class Tracker extends Effect:
	var last := {}          ## tag -> {amount, count, final}
	var atk_amount := -1.0
	var atk_crit := false

	func _init() -> void:
		id = "bx_tracker"
		hidden = true

	func on_damage_dealt(info) -> void:
		var k: String = info.tag if info.tag != "" else ("attack" if info.is_attack else ("spell" if info.is_spell else "other"))
		if info.is_attack:
			atk_amount = info.amount
			atk_crit = info.is_crit
		var e: Dictionary = last.get(k, {"amount": 0.0, "count": 0, "final": 0.0, "crit": false})
		e.amount = info.amount
		e.final = info.mitigated
		e.crit = info.is_crit
		e.count += 1
		last[k] = e

	func reset() -> void:
		last.clear()
		atk_amount = -1.0
		atk_crit = false

	func amt(tag: String) -> float:
		return last.get(tag, {}).get("amount", -1.0)

	func cnt(tag: String) -> int:
		return last.get(tag, {}).get("count", 0)


func _ready() -> void:
	_run()


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _check(name: String, ok: bool, detail: String = "") -> void:
	print("BXTEST %s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if ok:
		passes += 1
	else:
		fails += 1


func _near(a: float, b: float, eps: float = 0.05) -> bool:
	return absf(a - b) <= eps


func _setup() -> void:
	m = G.match
	c = G.player
	if c.augments_pending > 0 and m.has_method("get_offer"):
		m.get_offer(c)
		m.choose_augment(c, 0)
	m.spawner = null
	for u in m.units.duplicate():
		if u.kind == G.Kind.MINION or u.kind == G.Kind.SUMMON:
			m.remove_unit(u)
	spot = m.nav.nearest_walkable((m.outer_turrets[0].global_position + m.outer_turrets[1].global_position) * 0.5)
	var dums := []
	for ch in m.champions:
		if ch == c:
			continue
		ch.controller = null
		ch.is_bot = false
		ch.teleport(ch.spawn_point)
		ch.issue_move(ch.spawn_point)
		if ch.team != c.team and dums.size() < 2:
			dums.append(ch)
	d = dums[0]
	d2 = dums[1]
	c.gain_xp(1.0e6)
	tr = Tracker.new()
	c.add_effect(tr)
	for x in [d, d2]:
		for e in x.effects.duplicate():
			if e.id != "mayhem_aura" and not e.id.begins_with("harness"):
				x.remove_effect(e)
		var b := Buff.new("harness_disarm", 1.0)
		b.permanent = true
		b.hidden = true
		b.cc = Buff.CC.DISARM
		b.cleansable = false
		x.add_buff(b, x)
	var cb := Buff.new("harness_disarm", 1.0)   # no auto attacks: the test drives every attack by hand
	cb.permanent = true
	cb.hidden = true
	cb.cc = Buff.CC.DISARM
	cb.cleansable = false
	c.add_buff(cb, c)


func _reset() -> void:
	if not (c.controller is IdleBrain):
		c.controller = IdleBrain.new()
	c.is_bot = false
	for ch in m.champions:
		if ch != c:
			ch.controller = null
			ch.is_bot = false
	for it in c.items.duplicate():
		c.remove_item(it)
	for b in c.buffs.duplicate():
		if not b.permanent:
			c.remove_buff(b)
	for x in [d, d2]:
		if x.dead:
			x.respawn()
		for b in x.buffs.duplicate():
			if b.id != "harness_disarm":
				x.remove_buff(b)
		x.shields.clear()
		x.damage_log.clear()
		x.hp = x.stats.max_hp
	c.shields.clear()
	c.hp = c.stats.max_hp
	c.mana = c.stats.max_mana
	if c.dead:
		c.respawn()
	fwd = G.flat_dir(spot, m.nexus_units[1 if c.team == G.Team.ORDER else 0].global_position)
	c.teleport(spot)
	c.issue_move(spot)
	c.facing = fwd
	c.last_combat_time = -100.0
	d.teleport(m.nav.nearest_walkable(spot + fwd * 3.0))
	d2.teleport(m.nav.nearest_walkable(spot + fwd * 3.0 - Vector3(-fwd.z, 0, fwd.x) * 1.5))
	d.issue_move(d.global_position)
	d2.issue_move(d2.global_position)
	d.visible_to = [true, true, true]
	tr.reset()


func _equip(ids: Array) -> void:
	_reset()
	await _frames(2)   # the unit grid is rebuilt per frame (teleported dummies must be re-indexed)
	d.visible_to = [true, true, true]
	d2.visible_to = [true, true, true]
	for id in ids:
		c.add_item(ItemDB.create(id))
	c.recompute_stats()
	c.hp = c.stats.max_hp


func _atk(target, crit := false, keep_hp := false) -> void:
	if not keep_hp:
		target.hp = target.stats.max_hp
	c._pending_crit = crit
	for e in c.effects.duplicate():
		e.on_attack_launch(target)
	c.attack_hit(target, crit)


## Cast the first (or the ultimate) ability: fires the on_ability_cast hooks only.
func _cast(slot: int = 0) -> void:
	var ab = c.abilities[slot]
	var saved: bool = ab.is_ult
	if slot == 3:
		ab.is_ult = true
	for e in c.effects.duplicate():
		e.on_ability_cast(ab, {})
	ab.is_ult = saved


func _it(id: int) -> Item:
	for it in c.items:
		if it.item_id == id:
			return it
	return null


func _data(id: int, key: String, def: float = 0.0) -> float:
	return float(ItemDB.data(id, key, def))


func _run() -> void:
	await _frames(20)
	_setup()
	await _frames(5)
	melee = float(c.stats.base.attack_range) < 300.0
	print("BXTEST champion %s level %d melee=%s" % [c.display_name, c.level, str(melee)])
	await _t_hydras()
	await _t_spellblade()
	await _t_fighters()
	await _t_shields()
	await _t_takedowns()
	await _t_misc()
	print("BXTEST DONE passes=%d fails=%d" % [passes, fails])
	get_tree().quit()


func _t_hydras() -> void:
	var cl := 0.4 if melee else 0.2
	await _equip([3077])
	_atk(d)
	_check("tiamat cleave %.0f%% AD to d2" % (cl * 100.0), _near(tr.amt("cleave"), c.stats.ad * cl, 0.1) and tr.cnt("cleave") == 1, "%s vs %s n=%d" % [tr.amt("cleave"), c.stats.ad * cl, tr.cnt("cleave")])
	_check("tiamat active_cd 10", _near(_it(3077).active_cd, 10.0))
	_it(3077).activate(c.global_position, null)
	_check("tiamat crescent 75%% AD (hits both)", _near(tr.amt("hydra"), c.stats.ad * 0.75, 0.1) and tr.cnt("hydra") == 2, "%s n=%d" % [tr.amt("hydra"), tr.cnt("hydra")])
	await _equip([3074])
	c.hp = 100.0
	_it(3074).activate(c.global_position, null)
	var gain: float = c.hp - 100.0
	var exp_h := 0.0
	exp_h = c.stats.ad * 1.0 * (100.0 / (100.0 + d.stats.armor)) * c.stats.lifesteal * 2.0
	_check("ravenous crescent 100%% AD + life steal", _near(tr.amt("hydra"), c.stats.ad, 0.1) and gain > 0.0, "dmg=%s heal=%.1f (approx %.1f)" % [tr.amt("hydra"), gain, exp_h])
	await _equip([6698])
	_it(6698).activate(c.global_position, null)
	_check("profane heretical cleave 80%% AD", _near(tr.amt("hydra"), c.stats.ad * 0.8, 0.1), str(tr.amt("hydra")))
	await _equip([6631])
	_it(6631).activate(c.global_position, null)
	var sb := d.find_buff("slow_%d" % c.get_instance_id())
	_check("stridebreaker shockwave 100%% AD", _near(tr.amt("hydra"), c.stats.ad, 0.1))
	_check("stridebreaker slow 35%", sb != null and _near(sb.slow_amount, 0.35, 0.001), "" if sb == null else str(sb.slow_amount))
	var hb := c.find_buff("stridebreaker_ms")
	_check("stridebreaker decaying ms 45%% x 2 champions", hb != null, "" if hb == null else str(hb.get("amount")))
	_atk(d)
	_check("stridebreaker passive cleave", _near(tr.amt("cleave"), c.stats.ad * cl, 0.1), str(tr.amt("cleave")))
	# titanic
	var rm := 1.0 if melee else 0.5
	await _equip([3748])
	_atk(d)
	_check("titanic on-hit 1%% max hp", _near(tr.amt("titanic"), c.stats.max_hp * 0.01 * rm, 0.1), "%s vs %s" % [tr.amt("titanic"), c.stats.max_hp * 0.01 * rm])
	_it(3748).activate(c.global_position, null)
	tr.reset()
	_atk(d)
	_check("titanic crescent empowers: 4%% max hp", _near(tr.amt("titanic"), c.stats.max_hp * 0.04 * rm, 0.1), str(tr.amt("titanic")))
	tr.reset()
	_atk(d)
	_check("titanic empower consumed", _near(tr.amt("titanic"), c.stats.max_hp * 0.01 * rm, 0.1))
	# phage / rage
	await _equip([3044])
	_atk(d)
	var rb := c.find_buff("rage")
	var rms := 20.0 * rm
	_check("phage rage %.0f flat ms" % rms, rb != null and _near(float(rb.stats.get("ms", 0.0)), rms, 0.01), "" if rb == null else str(rb.stats))
	# black cleaver
	await _equip([3071])
	Combat.deal(c, d, 100.0, G.DmgType.PHYSICAL, {})
	await _frames(2)
	Combat.deal(c, d, 100.0, G.DmgType.PHYSICAL, {})
	var carve := d.find_buff("carve", c)
	_check("cleaver carve 2 stacks", carve != null and carve.stacks == 2, "" if carve == null else str(carve.stacks))
	_check("cleaver carve armor -6%% per stack", carve != null and _near(carve.get_stat_mods().get("armor%", 0.0), -0.12, 0.001))
	var fv := c.find_buff("fervor")
	_check("cleaver fervor %.0f ms" % rms, fv != null and _near(float(fv.stats.get("ms", 0.0)), rms, 0.01))
	for i in 6:
		await _frames(2)
		Combat.deal(c, d, 10.0, G.DmgType.PHYSICAL, {})
	_check("cleaver carve caps at 5", d.find_buff("carve", c).stacks == 5)
	# hullbreaker skipper
	await _equip([3181])
	for i in 4:
		_atk(d)
	_check("hullbreaker no proc on first 4 attacks", tr.cnt("skipper") == 0)
	_atk(d)
	# [numbers] bin calc MaxStackDamage: (120% base AD + 5% MAX Health) x 0.7 for ranged (wiki: 84% base AD + 3.5% max Health)
	var ad_r: float = _data(3181, "SkipperADRatio", 1.2)
	var exp_s: float = (ad_r * c.stats.base_ad + 0.05 * c.stats.max_hp) * (1.0 if melee else 0.7)
	_check("hullbreaker 5th attack skipper dmg", tr.cnt("skipper") == 1 and _near(tr.amt("skipper"), exp_s, 0.2), "%s vs %s" % [tr.amt("skipper"), exp_s])


func _t_spellblade() -> void:
	var base: float = c.stats.base_ad
	await _equip([3057])
	_atk(d)
	_check("sheen: no proc without ability", tr.cnt("spellblade") == 0)
	_cast()
	_atk(d)
	_check("sheen 100%% base AD", _near(tr.amt("spellblade"), base, 0.1), str(tr.amt("spellblade")))
	_atk(d)
	_check("sheen: only once", tr.cnt("spellblade") == 1)
	_cast()
	_atk(d)
	_check("sheen on 1.5s cooldown", tr.cnt("spellblade") == 1)
	await _frames(100)
	_cast()
	_atk(d)
	_check("sheen ready after 1.5s", tr.cnt("spellblade") == 2, "n=%d primed=%s cd=%.2f" % [tr.cnt("spellblade"), str(_it(3057).primed), _it(3057).cd])
	await _equip([3078])
	_cast()
	_atk(d)
	_check("trinity 200%% base AD", _near(tr.amt("spellblade"), base * 2.0, 0.1), str(tr.amt("spellblade")))
	var rb := c.find_buff("rage")
	_check("trinity quicken 20 ms", rb != null and _near(float(rb.stats.get("ms", 0.0)), 20.0, 0.01))
	await _equip([3057, 3078])
	_cast()
	_atk(d)
	_check("sheen+trinity: only strongest procs", tr.cnt("spellblade") == 1 and _near(tr.amt("spellblade"), base * 2.0, 0.1), "%s n=%d" % [tr.amt("spellblade"), tr.cnt("spellblade")])
	await _equip([3508])
	_cast()
	var mana0: float = c.mana
	c.mana = c.stats.max_mana * 0.5
	mana0 = c.mana
	_atk(d)
	var er: float = base * 1.25 + 50.0 * c.stats.crit_chance
	_check("essence reaver dmg 125%% base AD + 50*crit%%", _near(tr.amt("spellblade"), er, 0.1), "%s vs %s" % [tr.amt("spellblade"), er])
	_check("essence reaver mana refund = dmg", _near(c.mana - mana0, minf(er, c.stats.max_mana - mana0), 0.5), "%.1f" % (c.mana - mana0))
	await _equip([3100])
	_cast()
	c.recompute_stats()
	_check("lich bane primed: +50%% attack speed", _near(c.stats.m("as"), 0.5 + float(ItemDB.meta(3100).stats.get("as", 0.0)), 0.001), str(c.stats.m("as")))
	_atk(d)
	var lb: float = 0.75 * base + 0.45 * c.stats.ap
	_check("lich bane 75%% base AD + 45%% AP magic", _near(tr.amt("spellblade"), lb, 0.1), "%s vs %s" % [tr.amt("spellblade"), lb])
	c.recompute_stats()
	_check("lich bane attack speed gone after proc", _near(c.stats.m("as"), 0.0, 0.001))
	await _equip([2510, 3091])
	c.hp = c.stats.max_hp * 0.5
	var hp0: float = c.hp
	_cast()
	_atk(d)
	var dd: float = 0.75 * base + 0.10 * c.stats.ap
	_check("dusk and dawn 75%% base AD + 10%% AP", _near(tr.amt("spellblade"), dd, 0.1), "%s vs %s" % [tr.amt("spellblade"), dd])
	_check("dusk and dawn heals", c.hp > hp0, "%.1f" % (c.hp - hp0))
	var w0: int = tr.cnt("witsend")
	await _frames(25)
	_check("dusk and dawn applies on-hit again (wit's end x2)", tr.cnt("witsend") == w0 + 1 and w0 == 1, "%d -> %d" % [w0, tr.cnt("witsend")])


func _t_fighters() -> void:
	await _equip([3053])
	c.recompute_stats()
	var bonus_ad_exp: float = 0.5 * c.stats.base_ad
	_check("sterak's +50%% base AD bonus AD", _near(c.stats.bonus_ad, bonus_ad_exp, 0.5), "%s vs %s" % [c.stats.bonus_ad, bonus_ad_exp])
	c.hp = c.stats.max_hp * 0.5
	Combat.deal(d, c, 30.0, G.DmgType.PHYSICAL, {})
	_check("sterak's: no shield above 30%", c.total_shield() <= 0.0)
	c.hp = c.stats.max_hp * 0.31
	var si := Combat.deal(d, c, c.stats.max_hp * 0.05 * 1.0, G.DmgType.TRUE, {})
	var exp_sh: float = ItemFx.bonus_hp(c) * 0.7
	_check("sterak's shield 70%% bonus hp (absorbed the hit that triggered it)", si.absorbed > 0.0 and _near(c.total_shield() + si.absorbed, exp_sh, 0.5), "%.1f + %.1f vs %.1f" % [c.total_shield(), si.absorbed, exp_sh])
	var it: Item = _it(3053)
	_check("sterak's cooldown running", it.cd > 59.0, str(it.cd))
	# eclipse
	var pc := 0.08 if melee else 0.05
	await _equip([6692])
	Combat.deal(c, d, 10.0, G.DmgType.PHYSICAL, {"is_spell": true})
	_check("eclipse: 1 hit no proc", tr.cnt("eclipse") == 0)
	await _frames(15)
	Combat.deal(c, d, 10.0, G.DmgType.PHYSICAL, {"is_spell": true})
	_check("eclipse: 2 hits -> %.0f%% max hp" % (pc * 100.0), tr.cnt("eclipse") == 1 and _near(tr.amt("eclipse"), d.stats.max_hp * pc, 0.2), "%s vs %s" % [tr.amt("eclipse"), d.stats.max_hp * pc])
	var base_sh: float = 150.0 if melee else 75.0
	var ratio: float = 0.5 if melee else 0.25
	_check("eclipse shield %.0f + %.0f%% bonus AD" % [base_sh, ratio * 100.0], _near(c.total_shield(), base_sh + ratio * c.stats.bonus_ad, 0.5), "%.1f" % c.total_shield())
	# death's dance
	await _equip([6333])
	var frac := 0.3 if melee else 0.1
	c.hp = c.stats.max_hp
	var hp_before: float = c.hp
	var di := Combat.deal(d, c, 400.0, G.DmgType.PHYSICAL, {})
	var mit: float = di.mitigated
	_check("death's dance delays %.0f%% post-mitigation" % (frac * 100.0), _near(hp_before - c.hp, mit * (1.0 - frac), 0.5), "lost %.1f vs %.1f" % [hp_before - c.hp, mit * (1.0 - frac)])
	await _frames(200)
	_check("death's dance bleed finishes (total = full damage)", _near(hp_before - c.hp, mit, 2.0 + c.stats.hp_regen * 5.0), "lost %.1f vs %.1f" % [hp_before - c.hp, mit])
	# shojin
	await _equip([3161])
	c.recompute_stats()
	_check("shojin 25 basic ability haste", _near(c.stats.basic_haste, 25.0, 0.01))
	var ab = c.abilities[0]
	var dmg_base := 100.0
	var i0 := Combat.deal(c, d, dmg_base, G.DmgType.MAGIC, {"is_spell": true, "ability": ab})
	var b := c.find_buff("shojin")
	_check("shojin stack on spell damage", b != null and b.stacks == 1)
	Combat.deal(c, d, dmg_base, G.DmgType.MAGIC, {"is_spell": true, "ability": ab})
	_check("shojin 1s lockout per cast", c.find_buff("shojin").stacks == 1)
	var amp: float = 1.0 + (0.03 if melee else 0.015)
	var i1 := Combat.deal(c, d, dmg_base, G.DmgType.MAGIC, {"is_spell": true, "ability": c.abilities[1]})
	_check("shojin amp %.1f%% per stack" % ((amp - 1.0) * 100.0), _near(i1.mitigated / maxf(0.001, i0.mitigated), amp, 0.002), "%.4f" % (i1.mitigated / i0.mitigated))
	# maw
	await _equip([3156])
	c.hp = c.stats.max_hp * 0.4
	var mhp0: float = c.hp
	var mi := Combat.deal(d, c, c.stats.max_hp * 0.3, G.DmgType.MAGIC, {})
	var maw_sh: float = (200.0 if melee else 150.0) + 1.5 * c.stats.bonus_ad
	_check("maw shield 200 (+150%% bonus AD)", _near(c.total_shield() + mi.absorbed, maw_sh, 0.5), "%.1f + %.1f vs %.1f hp %.0f/%.0f" % [c.total_shield(), mi.absorbed, maw_sh, c.hp, mhp0])
	_check("maw omnivamp 10%%", c.find_buff("maw_vamp") != null and _near(float(c.find_buff("maw_vamp").stats.get("omnivamp", 0.0)), 0.1, 0.001))
	_check("maw cd 75", _near(_it(3156).cd, 75.0, 1.0), str(_it(3156).cd))   # [numbers] classic ARAM 75 s (Mayhem 60 s)
	c.shields.clear()
	await _equip([3155])
	c.hp = c.stats.max_hp * 0.4
	Combat.deal(d, c, 1.0, G.DmgType.PHYSICAL, {})
	_check("hexdrinker: physical hit no shield", c.total_shield() <= 0.0)
	var hi := Combat.deal(d, c, c.stats.max_hp * 0.3, G.DmgType.MAGIC, {})
	var hx: float = lerpf(110.0, 280.0, clampf((c.level - 1) / 17.0, 0.0, 1.0))
	_check("hexdrinker shield 110-280 by level", _near(c.total_shield() + hi.absorbed, hx, 0.5), "%.1f + %.1f vs %.1f (level %d)" % [c.total_shield(), hi.absorbed, hx, c.level])


func _t_shields() -> void:
	# edge of night spell shield
	await _equip([3814])
	var hp0: float = c.hp
	var dinfo := Combat.deal(d, c, 200.0, G.DmgType.MAGIC, {"is_spell": true})
	_check("edge of night blocks first enemy ability", dinfo.cancelled and c.hp >= hp0 - 0.1)
	dinfo = Combat.deal(d, c, 200.0, G.DmgType.MAGIC, {"is_spell": true})
	_check("edge of night then on cooldown (30s)", not dinfo.cancelled and c.hp < hp0)
	# bloodmail
	await _equip([2501])
	c.recompute_stats()
	var tyr: float = 0.025 * ItemFx.bonus_hp(c)
	var ad_full: float = c.stats.ad
	_check("bloodmail tyranny 2.5%% bonus hp as AD", ad_full > 0.0 and _near(c.stats.bonus_ad - 30.0, tyr, 1.0), "bonus_ad %.1f tyr %.1f" % [c.stats.bonus_ad, tyr])
	c.hp = c.stats.max_hp * 0.3
	await _frames(40)
	c.recompute_stats()
	_check("bloodmail retribution up to +12%%", c.stats.ad > ad_full * 1.10 and c.stats.ad < ad_full * 1.14, "%.1f vs %.1f" % [c.stats.ad, ad_full])


func _t_takedowns() -> void:
	await _equip([126697])
	Combat.deal(c, d, 10.0, G.DmgType.PHYSICAL, {})
	_it(126697).on_takedown(d)
	var ad_exp: float = (15.0 + 2.0) if melee else (10.0 + 1.0)
	var hb := c.find_buff("hubris")
	_check("hubris +%.0f AD after 1 takedown" % ad_exp, hb != null and _near(float(hb.stats.get("ad", 0.0)), ad_exp, 0.01), "" if hb == null else str(hb.stats))
	Combat.deal(c, d2, 10.0, G.DmgType.PHYSICAL, {})
	_it(126697).on_takedown(d2)
	_check("hubris 2nd stack", _near(float(c.find_buff("hubris").stats.get("ad", 0.0)), ad_exp + (2.0 if melee else 1.0), 0.01))
	_it(126697).on_takedown(d)   # d was last damaged > 3s ago? still within -> test via cleared log below
	d.damage_log.clear()
	var before: int = _it(126697).kills
	_it(126697).on_takedown(d)
	_check("hubris needs damage within 3s", _it(126697).kills == before)
	# axiom arc
	await _equip([6696])
	var ult = c.abilities[3]
	ult.cd = 60.0
	ult.cd_total = 100.0
	Combat.deal(c, d, 10.0, G.DmgType.PHYSICAL, {})
	_it(6696).on_takedown(d)
	var pct: float = 0.10 + 0.0025 * c.stats.lethality
	_check("axiom arc refunds 10%%+0.25%%/lethality of ult cd", _near(ult.cd, 60.0 - 100.0 * pct, 0.01), "%.2f vs %.2f" % [ult.cd, 60.0 - 100.0 * pct])
	ult.cd = 0.0
	# endless hunger
	await _equip([2517])
	c.recompute_stats()
	var ah_exp: float = 5.0 + (0.13 if melee else 0.10) * c.stats.bonus_ad
	_check("endless hunger famine ah", _near(c.stats.ability_haste, ah_exp, 0.5), "%.2f vs %.2f" % [c.stats.ability_haste, ah_exp])
	Combat.deal(c, d, 10.0, G.DmgType.PHYSICAL, {})
	_it(2517).on_takedown(d)
	c.recompute_stats()
	_check("endless hunger feast +15%% omnivamp", _near(c.stats.omnivamp, 0.05 + 0.15, 0.001), "%.3f" % c.stats.omnivamp)
	# death's dance defy
	await _equip([6333])
	c.hp = 100.0
	Combat.deal(c, d, 10.0, G.DmgType.PHYSICAL, {})
	_it(6333).on_takedown(d)
	await _frames(150)
	var healed: float = c.hp - 100.0
	var regen: float = c.stats.hp_regen * 2.5
	_check("death's dance defy heals ~100%% bonus AD over 2s", _near(healed - regen, c.stats.bonus_ad * (1.0 + c.stats.heal_power), 2.0), "%.1f (regen %.1f) vs %.1f" % [healed, regen, c.stats.bonus_ad])


func _t_misc() -> void:
	# youmuu
	await _equip([3142])
	_check("youmuu active_cd 45", _near(_it(3142).active_cd, 45.0))
	_it(3142).activate(c.global_position, null)
	var yb := c.find_buff("youmuu")
	var yp := 0.45 if melee else 0.30
	_check("youmuu wraith step %.0f%% ms + ghosted" % (yp * 100.0), yb != null and _near(float(yb.stats.get("ms%", 0.0)), yp, 0.001) and (c.cc & Buff.CC.GHOSTED) != 0)
	c.last_combat_time = -100.0
	await _frames(20)
	c.recompute_stats()
	var haunt: float = 30.0 if melee else 15.0
	_check("youmuu haunt out of combat ms", _near(c.stats.m("ms") - float(ItemDB.meta(3142).stats.get("ms", 0.0)), haunt, 0.01), str(c.stats.m("ms")))
	# soul anchor
	await _equip([4003])
	var p0 := c.global_position
	_it(4003).activate(c.global_position, null)
	c.teleport(p0 + Vector3(6, 0, 0))
	_it(4003).activate(c.global_position, null)
	_check("soul anchor recall returns to mark", G.flat_dist(c.global_position, p0) < 0.5, "%.2f" % G.flat_dist(c.global_position, p0))
	_it(4003).active_left = 0.0
	_it(4003).activate(c.global_position, null)
	c.teleport(p0 + Vector3(6, 0, 0))
	await _frames(260)
	_check("soul anchor auto return after 4s", G.flat_dist(c.global_position, p0) < 0.5, "%.2f marked=%s left=%.2f mark=%s p0=%s pos=%s" % [G.flat_dist(c.global_position, p0), str(_it(4003).marked), _it(4003).left, str(_it(4003).mark), str(p0), str(c.global_position)])
	# gunblade
	await _equip([3146])
	_it(3146).activate(c.global_position, d)
	var gb: float = lerpf(175.0, 253.0, clampf((c.level - 1) / 17.0, 0.0, 1.0)) + 0.3 * c.stats.ap
	_check("gunblade 175-253 + 30%% AP", _near(tr.amt("gunblade"), gb, 0.1), "%s vs %s" % [tr.amt("gunblade"), gb])
	var gs := d.find_buff("slow_%d" % c.get_instance_id())
	_check("gunblade slow 25%", gs != null and _near(gs.slow_amount, 0.25, 0.001))
	# umbral glaive
	await _equip([3179])
	c.teleport(c.spawn_point)
	await _frames(90)
	c.teleport(spot)
	_atk(d)
	_check("umbral glaive nightstalker 50 + 1.5*lethality true", _near(tr.amt("nightstalker"), 50.0 + 1.5 * c.stats.lethality, 0.1), str(tr.amt("nightstalker")))
	# fiendhunter
	await _equip([2512])
	c.recompute_stats()
	var as0: float = c.stats.m("as")
	_cast(3)
	c.recompute_stats()
	_check("fiendhunter +50%% attack speed after ult", _near(c.stats.m("as") - as0, 0.5, 0.001), "%.3f" % (c.stats.m("as") - as0))
	_atk(d, false)
	var exp_c: float = c.stats.ad * c.stats.crit_damage * 0.8
	_check("fiendhunter non-crit attack crits for 80%%", _near(tr.atk_amount, exp_c, 0.1) and tr.atk_crit, "%s vs %s" % [tr.atk_amount, exp_c])
	_atk(d, true)
	_check("fiendhunter natural crit: 15%% bonus true damage", tr.cnt("fiendhunter") == 1 and _near(tr.amt("fiendhunter"), c.stats.ad * c.stats.crit_damage * 0.15, 0.1), "%s" % tr.amt("fiendhunter"))
	_atk(d, false)
	c.recompute_stats()
	_check("fiendhunter ends after 3 attacks", _near(c.stats.m("as") - as0, 0.0, 0.001))
	# hexplate
	await _equip([3073])
	c.recompute_stats()
	_check("hexplate 30 ultimate haste", _near(c.stats.ult_haste, 30.0, 0.01))
	var as1: float = c.stats.m("as")
	var ms1: float = c.stats.m("ms%")
	_cast(3)
	c.recompute_stats()
	var ea: float = 0.5 if melee else 0.25
	var em: float = 0.2 if melee else 0.1
	_check("hexplate overdrive +%.0f%% AS +%.0f%% MS" % [ea * 100.0, em * 100.0], _near(c.stats.m("as") - as1, ea, 0.001) and _near(c.stats.m("ms%") - ms1, em, 0.001))
	# chempunk
	await _equip([6609])
	Combat.deal(c, d, 50.0, G.DmgType.PHYSICAL, {})
	_check("chempunk chainsword 40%% grievous", _near(d.grievous_wounds(), 0.4, 0.001))
	# sundered sky
	await _equip([6610])
	c.hp = c.stats.max_hp * 0.5
	var hp0: float = c.hp
	_atk(d)
	var exp_ss: float = c.stats.ad * c.stats.crit_damage * 0.8
	var heal_exp: float = 0.9 * c.stats.base_ad * (1.0 if melee else 0.5) + 0.04 * (c.stats.max_hp - hp0)
	_check("sundered sky first attack crits for 80%%", tr.atk_crit and _near(tr.atk_amount, exp_ss, 0.1), "%s vs %s" % [tr.atk_amount, exp_ss])
	_check("sundered sky heals 90%% base AD + 4%% missing hp", _near(c.hp - hp0, heal_exp, 1.0), "%.1f vs %.1f" % [c.hp - hp0, heal_exp])
	tr.reset()
	_atk(d, false)
	_check("sundered sky 10s cooldown per target", not tr.atk_crit)
	_atk(d2, false)
	_check("sundered sky separate target ready", tr.atk_crit)
