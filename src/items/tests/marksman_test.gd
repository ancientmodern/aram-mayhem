extends Node
## Exact-number checks for the marksman item family (src/items/item_fx_x_marksman.gd).
## godot --headless --path . --fixed-fps 60 --quit-after 6000 -- --champ=Jinx --harness=res://src/items/tests/marksman_test.gd
## (also run with --champ=Garen for the melee numbers). Output: "MKTEST PASS|FAIL <name> <detail>", final "MKTEST DONE fails=N".

var main = null
var match_ref = null

var m = null
var c: Champion = null
var d: Champion = null          ## enemy dummy 1
var d2: Champion = null         ## enemy dummy 2 (chain / bolts)
var tr: Tracker = null
var fails := 0
var passes := 0
var spot := Vector3.ZERO


class Tracker extends Effect:
	var last := {}          ## tag -> {amount, count}
	var seen_mult := 1.0
	var pre_hp := {}        ## tag -> target hp just before that damage

	func _init() -> void:
		id = "mk_tracker"
		hidden = true

	func on_damage_dealt(info) -> void:
		var k: String = info.tag if info.tag != "" else ("attack" if info.is_attack else "spell")
		var e: Dictionary = last.get(k, {"amount": 0.0, "count": 0, "final": 0.0})
		e.amount = info.amount
		e.final = info.mitigated
		seen_mult = info.mult
		e.count += 1
		last[k] = e

	func on_pre_damage_dealt(info) -> void:
		if info.target != null:
			pre_hp[info.tag if info.tag != "" else ("attack" if info.is_attack else "spell")] = info.target.hp

	func reset() -> void:
		last.clear()

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
	print("MKTEST %s %s %s" % ["PASS" if ok else "FAIL", name, detail])
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
	# the bot AI must not drive the player
	c.controller = null
	c.is_bot = false


func _reset() -> void:
	for it in c.items.duplicate():
		c.remove_item(it)
	c.remove_buffs_by_id("guinsoo")
	for id in ["terminus_light", "terminus_dark", "yuntal_flurry", "stormrazor_ms", "voltaic_lethality", "mercurial_ms"]:
		c.remove_buffs_by_id(id)
	for x in [d, d2]:
		if x.dead:
			x.respawn()
		for b in x.buffs.duplicate():
			if b.id != "harness_disarm":
				x.remove_buff(b)
		x.shields.clear()
		x.hp = x.stats.max_hp
	c.shields.clear()
	c.hp = c.stats.max_hp
	if c.dead:
		c.respawn()
	if c.has_meta("mk_energy"):
		c.remove_meta("mk_energy")
	var fwd := G.flat_dir(spot, m.nexus_units[1 if c.team == G.Team.ORDER else 0].global_position)
	c.teleport(spot)
	c.issue_move(spot)
	d.teleport(m.nav.nearest_walkable(spot + fwd * 3.0))
	d2.teleport(m.nav.nearest_walkable(spot + fwd * 3.0 + Vector3(-fwd.z, 0, fwd.x) * 1.5))
	d.issue_move(d.global_position)
	d2.issue_move(d2.global_position)
	tr.reset()


func _equip(ids: Array) -> void:
	_reset()
	for id in ids:
		c.add_item(ItemDB.create(id))
	c.recompute_stats()
	c.hp = c.stats.max_hp


## One basic attack the way Unit._launch_attack does it (launch hooks, then the hit).
func _atk(target, crit := false, keep_hp := false) -> void:
	if not keep_hp:
		target.hp = target.stats.max_hp
	c._pending_crit = crit
	for e in c.effects.duplicate():
		e.on_attack_launch(target)
	c.attack_hit(target, crit)


func _it(id: int) -> Item:
	for it in c.items:
		if it.item_id == id:
			return it
	return null


func _run() -> void:
	await _frames(20)
	_setup()
	await _frames(5)
	var melee := float(c.stats.base.attack_range) < 300.0
	print("MKTEST champion %s level %d melee=%s" % [c.display_name, c.level, str(melee)])
	await _t_onhit(melee)
	await _t_kraken_botrk_guinsoo(melee)
	await _t_energized(melee)
	await _t_yuntal(melee)
	await _t_misc(melee)
	await _t_shields(melee)
	await _t_runaans()
	print("MKTEST DONE passes=%d fails=%d" % [passes, fails])
	get_tree().quit()


func _t_onhit(_melee: bool) -> void:
	_equip([1043])
	_atk(d)
	_check("recurve 15 physical on-hit", _near(tr.amt("recurve"), 15.0), str(tr.amt("recurve")))
	_equip([3091])
	_atk(d)
	_check("wits end 45 magic", _near(tr.amt("witsend"), 45.0), str(tr.amt("witsend")))
	_equip([3302])
	var exp := 30.0 + 0.1 * c.stats.bonus_ad + 0.1 * c.stats.ap
	_atk(d)
	_check("terminus on-hit 30+10%bAD+10%AP", _near(tr.amt("terminus"), exp, 0.1), "%s vs %s" % [tr.amt("terminus"), exp])
	var l := c.find_buff("terminus_light")
	var per := 6.0 + (1.0 if c.level >= 11 else 0.0) + (1.0 if c.level >= 14 else 0.0)
	_check("terminus light attack: 1 stack armor/mr", l != null and l.stacks == 1 and c.find_buff("terminus_dark") == null)
	var armor_with: float = c.stats.armor
	_atk(d)
	var dk := c.find_buff("terminus_dark")
	_check("terminus dark attack: pen stack", dk != null and dk.stacks == 1, "armor_pen%%=%.2f" % c.stats.armor_pen_pct)
	c.recompute_stats()
	_check("terminus pen 10%", _near(c.stats.armor_pen_pct, 0.1, 0.001) and _near(c.stats.magic_pen_pct, 0.1, 0.001))
	_atk(d)
	_atk(d)
	_atk(d)
	_atk(d)
	l = c.find_buff("terminus_light")
	dk = c.find_buff("terminus_dark")
	_check("terminus stacks cap at 3", l.stacks == 3 and dk.stacks == 3, "%d/%d" % [l.stacks, dk.stacks])
	_check("terminus armor/mr per level", _near(l.get_stat_mods().get("armor", 0.0), per * 3.0, 0.01), str(l.get_stat_mods()))
	c.recompute_stats()
	_check("terminus max pen 30%", _near(c.stats.armor_pen_pct, 0.3, 0.001))
	armor_with = armor_with + 0.0
	# grievous (Executioner's Calling)
	_equip([3123])
	Combat.deal(c, d, 50.0, G.DmgType.PHYSICAL, {})
	_check("executioner's applies 40% grievous", _near(d.grievous_wounds(), 0.4, 0.001))
	_equip([3033])
	Combat.deal(c, d2, 50.0, G.DmgType.PHYSICAL, {})
	_check("mortal reminder applies 40% grievous", _near(d2.grievous_wounds(), 0.4, 0.001))
	# lord dominik's
	_equip([])
	Combat.deal(c, d, 100.0, G.DmgType.PHYSICAL, {})
	var m0 := tr.seen_mult
	_equip([3036])
	var bonus: float = d.stats.max_hp - (d.stats.base.base_hp + Stats.growth(d.stats.base.hp_per_level, d.level))
	var expm := 1.0 + 0.15 * clampf(bonus / 1500.0, 0.0, 1.0)
	Combat.deal(c, d, 100.0, G.DmgType.PHYSICAL, {})
	_check("lord dominik's giant slayer mult", _near(tr.seen_mult / m0, expm, 0.001), "%.4f vs %.4f" % [tr.seen_mult / m0, expm])
	# serylda's
	_equip([6694])
	d.hp = d.stats.max_hp * 0.4
	Combat.deal(c, d, 10.0, G.DmgType.PHYSICAL, {"is_spell": true})
	_check("serylda's slows below 50% hp", d.find_buff("seryldas_slow") != null and _near(d.find_buff("seryldas_slow").slow_amount, 0.3, 0.001))
	d.hp = d.stats.max_hp
	d.remove_buffs_by_id("seryldas_slow")
	Combat.deal(c, d, 10.0, G.DmgType.PHYSICAL, {"is_spell": true})
	_check("serylda's no slow above 50% hp", d.find_buff("seryldas_slow") == null)
	# scout's slingshot
	_equip([3144])
	Combat.deal(c, d, 10.0, G.DmgType.PHYSICAL, {})
	_check("slingshot bullseye 40 magic", _near(tr.amt("bullseye"), 40.0) and tr.cnt("bullseye") == 1)
	Combat.deal(c, d, 10.0, G.DmgType.PHYSICAL, {})
	_check("slingshot on cooldown", tr.cnt("bullseye") == 1)
	for i in 39:
		_atk(d)
	_check("slingshot attacks reduce cd by 1s each", tr.cnt("bullseye") == 1)
	_atk(d)
	Combat.deal(c, d, 10.0, G.DmgType.PHYSICAL, {})
	_check("slingshot ready again after 40 attacks", tr.cnt("bullseye") == 2, str(tr.cnt("bullseye")))
	# collector
	_equip([6676])
	d.hp = d.stats.max_hp * 0.04
	Combat.deal(c, d, 1.0, G.DmgType.PHYSICAL, {})
	_check("collector executes below 5%", d.dead)
	var gold0: float = c.gold
	_check("collector gold hook present", _it(6676) != null, "gold %s" % gold0)
	_reset()
	# phantom dancer
	_equip([3046])
	_check("phantom dancer ghosted", (c.cc & Buff.CC.GHOSTED) != 0)
	c.die(null)
	c.respawn()
	await _frames(3)
	_check("phantom dancer ghosted after respawn", (c.cc & Buff.CC.GHOSTED) != 0)
	_reset()


func _t_kraken_botrk_guinsoo(melee: bool) -> void:
	_equip([6672])
	var base := 150.0 + 5.0 * maxf(0.0, float(c.level) - 8.0)
	if not melee:
		base *= float(ItemDB.data(6672, "RangedDamageMultiplier", 1.0))
	_atk(d)
	_atk(d)
	_check("kraken no proc before 3rd", tr.cnt("kraken") == 0)
	d.hp = d.stats.max_hp * 0.5
	_atk(d, false, true)
	var hpk: float = tr.pre_hp.get("kraken", 1.0)
	var ex := base * (1.0 + 0.75 * (1.0 - hpk / d.stats.max_hp))
	_check("kraken 3rd attack dmg (missing hp amp)", tr.cnt("kraken") == 1 and _near(tr.amt("kraken"), ex, 0.5), "%s vs %s (hp %.0f%%)" % [tr.amt("kraken"), ex, hpk / d.stats.max_hp * 100.0])
	# botrk
	_equip([3153])
	d.hp = d.stats.max_hp * 0.8
	_atk(d, false, true)
	var hp0: float = tr.pre_hp.get("botrk", 1.0)
	var pct := float(ItemDB.data(3153, "MeleeValue" if melee else "RangedValue", 0.09))
	_check("botrk %.0f%% current hp" % (pct * 100.0), _near(tr.amt("botrk"), hp0 * pct, 0.5), "%s vs %s" % [tr.amt("botrk"), hp0 * pct])
	_atk(d)
	_check("botrk no slow on 2nd", d.find_buff("botrk_slow") == null)
	_atk(d)
	var sb := d.find_buff("botrk_slow")
	var sl := 0.3 if melee else 0.15
	_check("botrk slow on 3rd (%.2f)" % sl, sb != null and _near(sb.slow_amount, sl, 0.001), "" if sb == null else str(sb.slow_amount))
	d.remove_buffs_by_id("botrk_slow")
	_atk(d)
	_atk(d)
	_atk(d)
	_check("botrk slow on cooldown (15s)", d.find_buff("botrk_slow") == null)
	# guinsoo
	_equip([3124])
	for i in 4:
		_atk(d)
	c.recompute_stats()
	var gb := c.find_buff("guinsoo")
	_check("guinsoo 4 stacks of 8% as", gb != null and gb.stacks == 4 and _near(c.stats.m("as"), 0.25 + 4.0 * 0.08, 0.001), "stacks=%s" % (str(gb.stacks) if gb != null else "none"))
	_check("guinsoo wrath 30 magic", _near(tr.amt("guinsoo"), 30.0) and tr.cnt("guinsoo") == 4)
	_atk(d)
	_atk(d)
	var before: int = tr.cnt("guinsoo")
	_atk(d)
	_check("guinsoo third full attack applies on-hit twice", tr.cnt("guinsoo") == before + 2, "%d -> %d" % [before, tr.cnt("guinsoo")])
	_equip([6675])
	var ab = c.abilities[0]
	ab.cd = 10.0
	_atk(d)
	_check("navori -15%% remaining cd", _near(ab.cd, 8.5, 0.01), str(ab.cd))
	ab.cd = 0.0


func _t_energized(melee: bool) -> void:
	_equip([3095])
	_atk(d)
	var st = c.get_meta("mk_energy")
	_check("energized: +6 per attack", _near(st.energy, 6.0, 0.01), str(st.energy))
	st.energy = 100.0
	await _frames(2)
	_atk(d)
	_check("stormrazor bolt 100 magic", _near(tr.amt("stormrazor"), 100.0) and tr.cnt("stormrazor") == 1, str(tr.amt("stormrazor")))
	var ms := c.find_buff("stormrazor_ms")
	_check("stormrazor +45% ms 1.5s", ms != null and _near(ms.get_stat_mods().get("ms%", 0.0), 0.45, 0.001) and _near(ms.duration, 1.5, 0.001))
	_check("energy reset after proc", _near(st.energy, 0.0, 6.5), str(st.energy))
	_atk(d)
	_check("no second bolt", tr.cnt("stormrazor") == 1)
	# movement stacks: 1 per 24 units
	st.energy = 0.0
	await _frames(2)
	var p0: Vector3 = c.global_position
	c.global_position = p0 + Vector3(2.4, 0, 0)
	await _frames(2)
	_check("energized: 1 stack / 24 units moved (240u -> 10)", _near(st.energy, 10.0, 0.6), str(st.energy))
	# stormrazor + statikk + rfc share one charge
	_equip([3095, 3087, 3094])
	_atk(d)
	st = c.get_meta("mk_energy")
	_check("statikk electroshock: 6+9 stacks", _near(st.energy, 15.0, 0.01), str(st.energy))
	st.energy = 100.0
	await _frames(2)
	_check("rapid firecannon: range up while charged", c.stats.attack_range > c.stats.base.attack_range + 1.0, "%s vs base %s" % [c.stats.attack_range, c.stats.base.attack_range])
	var rng_bonus: float = c.stats.attack_range - c.stats.base.attack_range
	var exp_bonus := minf(0.35 * c.stats.base.attack_range, 150.0)
	_check("rapid firecannon bonus = min(35%, 150)", _near(rng_bonus, exp_bonus, 0.5), "%s vs %s" % [rng_bonus, exp_bonus])
	_atk(d)
	_check("firecannon 40 magic", _near(tr.amt("firecannon"), 40.0) and tr.cnt("firecannon") == 1)
	_check("shared charge: stormrazor also fired", tr.cnt("stormrazor") == 1)
	var targets := 2
	var cnt: int = tr.cnt("statikk")
	_check("statikk chain hit >= 2 targets, 70 vs champions", cnt >= targets and _near(tr.amt("statikk"), 70.0), "n=%d amt=%s" % [cnt, tr.amt("statikk")])
	await _frames(2)
	_check("range back to normal after proc", _near(c.stats.attack_range, c.stats.base.attack_range, 0.5), str(c.stats.attack_range))
	# voltaic
	_equip([6699])
	st = null
	_atk(d)
	st = c.get_meta("mk_energy")
	st.energy = 100.0
	await _frames(2)
	d.hp = d.stats.max_hp * 0.7
	Combat.deal(c, d, 10.0, G.DmgType.MAGIC, {"is_spell": true})
	var hpv: float = tr.pre_hp.get("voltaic", 1.0)
	var pctv := (9.0 if melee else 7.0) / 100.0
	_check("voltaic galvanize + firmament (%.0f%% current hp)" % (pctv * 100.0), tr.cnt("voltaic") == 1 and _near(tr.amt("voltaic"), hpv * pctv, 0.01), "%s vs %s" % [tr.amt("voltaic"), hpv * pctv])
	var vb := c.find_buff("voltaic_lethality")
	_check("voltaic lethality buff", vb != null and _near(vb.get_stat_mods().get("lethality", 0.0), 15.0 if melee else 12.0, 0.01))


func _t_yuntal(melee: bool) -> void:
	_equip([3032])
	var base_crit: float = c.stats.crit_chance
	for i in 10:
		_atk(d)
	var per := 0.01 * (1.0 if melee else 0.5)
	c.recompute_stats()
	_check("yun tal: +%.1f%% crit per attack" % (per * 100.0), _near(c.stats.crit_chance - base_crit, per * 10.0, 0.0005), "%s" % (c.stats.crit_chance - base_crit))
	var fb := c.find_buff("yuntal_flurry")
	_check("yun tal flurry +30% as, 6s", fb != null and _near(fb.get_stat_mods().get("as", 0.0), 0.3, 0.001) and _near(fb.duration, 6.0, 0.001))
	var it = _it(3032)
	var cd0: float = it._cd
	_atk(d, true)
	_check("yun tal crit reduces cd by 2", _near(cd0 - it._cd, 2.0, 0.01), "%s -> %s" % [cd0, it._cd])
	for i in 100:
		_atk(d)
	c.recompute_stats()
	_check("yun tal crit capped at 25%", _near(c.stats.crit_chance - base_crit, 0.25, 0.001), str(c.stats.crit_chance - base_crit))


func _t_misc(_melee: bool) -> void:
	# quicksilver / mercurial
	_equip([3139])
	var it = _it(3139)
	K.stun(c, 2.0, d)
	K.slow(c, 0.4, 3.0, d)
	_check("cc applied", (c.cc & Buff.CC.STUN) != 0)
	it.activate(c.global_position, null)
	_check("mercurial removes stun and slow", (c.cc & Buff.CC.STUN) == 0 and c.find_buff("slow_" + str(d.get_instance_id())) == null)
	var mb := c.find_buff("mercurial_ms")
	_check("mercurial +50% ms 2s", mb != null and _near(mb.get_stat_mods().get("ms%", 0.0), 0.5, 0.001) and _near(mb.duration, 2.0, 0.001))
	_check("mercurial 90s cd", _near(it.active_left, 90.0, 0.5) and _near(it.active_cd, 90.0, 0.01), "%s/%s" % [it.active_left, it.active_cd])
	_equip([3140])
	it = _it(3140)
	K.knockup(c, 1.0, d)
	K.root(c, 2.0, d)
	it.activate(c.global_position, null)
	_check("quicksilver keeps airborne, removes root", (c.cc & Buff.CC.AIRBORNE) != 0 and (c.cc & Buff.CC.ROOT) == 0)
	_check("quicksilver gives no ms", c.find_buff("mercurial_ms") == null)
	c.remove_buffs_by_id("knockup")
	for b in c.buffs.duplicate():
		if b.is_debuff:
			c.remove_buff(b)


func _t_shields(melee: bool) -> void:
	# immortal shieldbow
	_equip([6673])
	var amt := 400.0 + 30.0 * maxf(0.0, float(c.level) - 8.0)
	if not melee:
		amt *= 0.8
	c.hp = c.stats.max_hp * 0.4
	var dmg := c.stats.max_hp * 0.2
	# true damage: exactly dmg before shield
	Combat.deal(d, c, dmg, G.DmgType.TRUE, {})
	_check("shieldbow lifeline absorbs the triggering hit", _near(c.hp, c.stats.max_hp * 0.4, 0.5) and c.shields.size() > 0 and _near(c.shields[0].max, amt, 0.5), "hp=%.0f shield=%.0f max=%.0f exp=%.0f" % [c.hp, c.total_shield(), c.shields[0].max if c.shields.size() > 0 else -1.0, amt])
	var it = _it(6673)
	_check("shieldbow cd 75", _near(it._cd, 75.0, 0.5), str(it._cd))   # [numbers] classic ARAM 75 s (Mayhem 60 s)
	_check("shieldbow 3s shield", c.shields.size() > 0 and _near(c.shields[0].duration, 3.0, 0.01))
	c.shields.clear()
	Combat.deal(d, c, dmg, G.DmgType.TRUE, {})
	_check("shieldbow on cooldown: no second shield", c.total_shield() == 0.0)
	# bloodthirster
	_equip([3072])
	c.hp = c.stats.max_hp
	var cap := 165.0 + 15.0 * maxf(0.0, float(c.level) - 8.0)
	for i in 40:
		_atk(d)
	var sh := 0.0
	for s in c.shields:
		if s.id == "ichor":
			sh = s.amount
	_check("bloodthirster ichorshield capped at %.0f" % cap, sh > 1.0 and sh <= cap + 0.5, "%.1f" % sh)
	c.hp = c.stats.max_hp * 0.5
	c.shields.clear()
	_atk(d)
	_check("bloodthirster no shield while healing is not excess", c.total_shield() < 1.0, "%.1f" % c.total_shield())
	# serpent's fang
	_equip([6695])
	d.shields.clear()
	var k_sh: float = float(Combat.shield(d, d, 100.0, 0.5).amount) / 100.0   # [numbers] the dummy's own shield modifiers (Mayhem aura ...)
	d.shields.clear()
	d.add_shield(200.0, 5.0, d)
	var fi := Combat.deal(c, d, 10.0, G.DmgType.PHYSICAL, {})
	var w := float(ItemDB.data(6695, "ShieldShred" if melee else "ShieldShredRange", 50.0)) / 100.0
	_check("serpent's fang shreds existing shield by %.0f%%" % (w * 100.0), _near(d.total_shield(), (200.0 - fi.absorbed) * (1.0 - w), 0.5), str(d.total_shield()))
	var tot0: float = d.total_shield()
	Combat.shield(d, d, 100.0, 3.0)
	var ww := float(ItemDB.data(6695, "ShieldWounds" if melee else "ShieldWoundsRange", 50.0)) / 100.0
	_check("serpent's fang reduces new shields by %.0f%%" % (ww * 100.0), _near(d.total_shield() - tot0, 100.0 * k_sh * (1.0 - ww), 0.5), "%s" % (d.total_shield() - tot0))


func _t_runaans() -> void:
	_equip([3085])
	var n_bolts := 0
	for i in 6:
		_atk(d)
	await _frames(90)
	n_bolts = tr.cnt("runaans")
	var expect := 1 if float(c.stats.base.attack_range) < 300.0 else 2
	_check("runaan's bolts (%d per attack, 60%% AD)" % expect, n_bolts >= expect * 4, "bolts=%d" % n_bolts)
	if n_bolts > 0:
		_check("runaan's bolt 60% ad", _near(tr.amt("runaans") / c.stats.ad, 0.6, 0.01) or _near(tr.amt("runaans") / (c.stats.ad * c.stats.crit_damage), 0.6, 0.01), "%.3f" % (tr.amt("runaans") / c.stats.ad))
