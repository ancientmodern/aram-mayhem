extends Node
## [numbers] Headless harness asserting the key League formulas / ARAM numbers (see docs/NUMBERS_AUDIT.md).
## Usage: godot --headless --path . --fixed-fps 60 -- --champ=Lux --harness=res://src/debug/numbers_test.gd
## Output: "NUM PASS|FAIL <name> <detail>", final "NUM DONE passes=N fails=N".

var main = null
var match_ref = null

var passes := 0
var fails := 0
var m = null
var c: Champion = null


class StatMod extends Effect:
	func _init(p_id: String, p_mods: Dictionary) -> void:
		id = p_id
		stats = p_mods
		hidden = true


func _ready() -> void:
	_run()


func _check(name: String, ok: bool, detail: String = "") -> void:
	print("NUM %s %s %s" % ["PASS" if ok else "FAIL", name, detail])
	if ok:
		passes += 1
	else:
		fails += 1


func _near(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps


func _eq(name: String, got: float, want: float, eps: float = 0.01) -> void:
	_check(name, _near(got, want, eps), "got %.4f want %.4f" % [got, want])


func _run() -> void:
	await get_tree().create_timer(1.0, true, false, true).timeout
	m = G.match
	c = G.player
	_pure_formulas()
	_stats_model()
	_rules_and_economy()
	_structures()
	_structure_attacks()
	_combat_ratios()
	_summoners()
	_minions()
	print("NUM DONE passes=%d fails=%d" % [passes, fails])
	get_tree().quit()


# ===================================================================== damage / resist formulas (no scene needed)
func _pure_formulas() -> void:
	_eq("armor 100 -> 50% damage", Combat.resist_multiplier(100.0, null, true), 0.5)
	_eq("armor 0 -> 100% damage", Combat.resist_multiplier(0.0, null, true), 1.0)
	_eq("armor -100 -> 150% damage", Combat.resist_multiplier(-100.0, null, true), 1.5)
	_eq("MR 50 -> 66.67%", Combat.resist_multiplier(50.0, null, false), 100.0 / 150.0)
	# penetration order: percent first, then lethality; both ignored at armor <= 0
	var src: Champion = c
	var mod := StatMod.new("num_pen", {"armor_pen%": 0.3, "lethality": 10.0, "magic_pen%": 0.4, "magic_pen": 20.0})
	src.add_effect(mod)
	src.recompute_stats()
	_eq("100 armor, 30% pen + 10 lethality -> 60 effective", Combat.resist_multiplier(100.0, src, true), 100.0 / 160.0)
	_eq("armor -20: pen ignored", Combat.resist_multiplier(-20.0, src, true), 2.0 - 100.0 / 120.0)
	_eq("100 MR, 40% pen + 20 flat -> 40 effective", Combat.resist_multiplier(100.0, src, false), 100.0 / 140.0)
	_eq("lethality is flat at level 3 (no level scaling)", src.lethality_flat(), 10.0)
	src.remove_effect(mod)
	src.recompute_stats()
	# critical strikes: base 200%
	_eq("base crit damage 200%", Rules.CRIT_DAMAGE, 2.0)
	# cooldown from ability haste
	var st := Stats.new()
	st.ability_haste = 50.0
	_eq("cooldown 10 s at 50 AH = 6.667", st.cooldown(10.0), 100.0 / 15.0)
	st.ability_haste = 900.0
	_eq("ability haste capped at 500 (1/6)", st.cooldown(12.0), 2.0)
	st.ability_haste = 0.0
	st.summoner_haste = 70.0
	_eq("Flash 300 s with the 70 HA haste = 176.47", 300.0 * 100.0 / (100.0 + st.summoner_haste), 176.47, 0.01)
	# tenacity groups: A multiplies, groups add
	var ten := Stats.new()
	ten.recompute([StatMod.new("a1", {"tenacity": 0.3}), StatMod.new("a2", {"tenacity": 0.2})])
	_eq("tenacity 30% + 20% (same group) = 44%", ten.tenacity, 0.44)
	ten.recompute([StatMod.new("a1", {"tenacity": 0.3}), StatMod.new("b1", {"tenacity_b": 0.75})])
	_eq("tenacity item 30% + Cleanse 75% (groups add) = 100% (capped)", ten.tenacity, 1.0)
	# ARAM global constants
	_eq("attack speed cap 3.003 (gcd_AttackMinDelay 0.333)", Rules.AS_CAP, 1.0 / 0.333, 0.001)
	_eq("passive gold 6 per second (30 / 5 s)", Rules.PASSIVE_GOLD_PER_SEC, 6.0)
	_eq("start gold 1400", Rules.START_GOLD, 1400.0)
	_eq("start level 3", float(Rules.START_LEVEL), 3.0)
	_eq("area damage to minions 75%", Rules.AOE_VS_MINION, 0.75)
	_eq("long range reduction at 1500 u = 77.5%", Rules.long_range_mult(1500.0), 0.775)


# ===================================================================== stat growth, attack speed, move speed
func _stats_model() -> void:
	# League level-scaling curve: g * (n-1) * (0.7025 + 0.0175 * (n-1))
	_eq("growth(99, level 18) = 1683", Stats.growth(99.0, 18), 1683.0)
	_eq("growth(99, level 3) = 99*2*0.7375", Stats.growth(99.0, 3), 99.0 * 2.0 * 0.7375)
	var s := Stats.new()
	s.set_base({"base_hp": 580.0, "hp_per_level": 99.0, "base_ad": 54.0, "ad_per_level": 3.3, "base_armor": 21.0, "armor_per_level": 5.2,
			"base_mr": 30.0, "mr_per_level": 1.3, "base_ms": 330.0, "attack_speed": 0.669, "attack_speed_ratio": 0.625,
			"attack_speed_per_level": 3.0, "mana_base": 440.0, "mana_per_level": 23.5, "mana_regen": 1.8, "mana_regen_per_level": 0.16,
			"base_hp_regen": 1.1, "hp_regen_per_level": 0.11, "attack_range": 550.0})
	s.level = 18
	s.recompute([])
	_eq("Lux level 18 HP = 2263", s.max_hp, 580.0 + 1683.0)
	_eq("Lux level 18 AD = 54 + 3.3*17", s.ad, 54.0 + 3.3 * 17.0)
	_eq("Lux level 18 armor = 21 + 5.2*17", s.armor, 21.0 + 5.2 * 17.0)
	_eq("Lux level 18 mana = 440 + 23.5*17", s.max_mana, 440.0 + 23.5 * 17.0)
	# attack speed: base + ratio * (growth + item bonus)
	_eq("level-18 bonus AS from growth = 51%", s.bonus_as, 0.51)
	s.recompute([StatMod.new("as", {"as": 0.4})])
	_eq("Lux AS = 0.669 + 0.625 * (0.51 + 0.4)", s.attack_speed, 0.669 + 0.625 * 0.91)
	s.recompute([StatMod.new("as", {"as": 5.0})])
	_eq("AS clamped at the 3.003 cap", s.attack_speed, 3.003, 0.001)
	# movement speed soft caps
	s.level = 3
	s.recompute([StatMod.new("ms", {"ms": 100.0})])
	_eq("430 raw MS -> 415 + 15*0.8 = 427", s.move_speed, 427.0)
	s.recompute([StatMod.new("ms", {"ms": 200.0})])
	_eq("530 raw MS -> 415 + 75*0.8 + (530-490)*0.5 = 530*0.5+230 = 495", s.move_speed, 495.0)
	s.recompute([StatMod.new("ms", {"ms": -150.0})])
	_eq("180 raw MS -> below 220: 110 + 90 = 200", s.move_speed, 200.0)
	s.recompute([])
	s.slow = 0.4
	s.recompute([])
	_eq("330 MS with a 40% slow = 198 -> soft-capped 110 + 99 = 209", s.move_speed, 209.0)
	# adaptive force: 0.6 AD per adaptive when bonus AD leads, else full AP
	s.slow = 0.0
	s.recompute([StatMod.new("ad", {"ad": 50.0}), StatMod.new("ad2", {"adaptive": 10.0})])
	_eq("adaptive 10 with more AD -> +6 AD", s.bonus_ad, 56.0)
	s.recompute([StatMod.new("ap", {"ap": 80.0}), StatMod.new("ad2", {"adaptive": 10.0})])
	_eq("adaptive 10 with more AP -> +10 AP", s.ap, 90.0)
	# crit chance above 100% is wasted in classic ARAM
	s.recompute([StatMod.new("crit", {"crit": 1.5})])
	_eq("crit chance capped at 100%", s.crit_chance, 1.0)
	_eq("no crit-to-AD conversion in classic ARAM", s.bonus_ad, 0.0)


# ===================================================================== rules / economy
func _rules_and_economy() -> void:
	_eq("XP 3->4 = 478", Rules.xp_to_next(3), 478.0)
	_eq("XP 17->18 = 1880", Rules.xp_to_next(17), 1880.0)
	_eq("respawn level 10 early = 24 s", Rules.respawn_time(10, 600.0), 24.0)
	_eq("respawn level 18 = 40 s", Rules.respawn_time(18, 600.0), 40.0)
	_eq("respawn +2.5% in the first minute after 24:00", Rules.respawn_time(10, 1441.0), 24.0 * 1.025)
	_eq("respawn +25% cap", Rules.respawn_time(10, 4000.0), 24.0 * 1.25)
	_eq("kill XP of a level-10 victim = 590", Rules.kill_xp(10), 590.0)
	_eq("solo kill XP, same level", Rules.champion_kill_xp(10, 10, 1), 590.0)
	_eq("solo kill XP, victim 2 levels higher: +32%", Rules.champion_kill_xp(10, 8, 1), 590.0 * 1.32)
	_eq("shared kill XP (level 10 victim, 2 participants) = 590*0.9/2", Rules.champion_kill_xp(10, 10, 2), 590.0 * 0.9 / 2.0)
	_eq("minion XP, 1 champion = 92%", Rules.minion_xp_share(64.0, 1), 64.0 * 0.92)
	_eq("minion XP, 5 champions = 24% each", Rules.minion_xp_share(64.0, 5), 64.0 * 0.24)
	_eq("early bounty scale 0:30 = 50%", Rules.early_bounty_scale(30.0), 0.5)
	_eq("early bounty scale 3:30 = 100%", Rules.early_bounty_scale(210.0), 1.0)
	_eq("kill base gold 200", Rules.KILL_GOLD, 200.0)
	_eq("structure bonus at 18:00 = 0", Rules.structure_bonus(1080.0), 0.0)
	_eq("structure bonus at 24:00 = 12.5%", Rules.structure_bonus(1440.0), 0.125)
	_eq("structure bonus at 30:00 = 25%", Rules.structure_bonus(1800.0), 0.25)


# ===================================================================== structure stats
func _structures() -> void:
	var outer: Turret = m.outer_turrets[0]
	var inhib_t: Turret = m.inhib_turrets[0]
	var nx: Structure = m.nexus_units[0]
	var ih: Structure = m.inhibitor_units[0]
	_eq("outer turret HP 1300 + 250*5", outer.stats.max_hp, 2550.0)
	_eq("inhibitor turret HP 3900 + 250*5", inhib_t.stats.max_hp, 5150.0)
	var nt: Turret = nx.guards[0]
	_eq("nexus turret HP 1800 + 250*5", nt.stats.max_hp, 3050.0)
	_eq("nexus HP 5500", nx.stats.max_hp, 5500.0)
	_eq("nexus regen 20/s", nx.stats.hp_regen, 20.0)
	_eq("nexus MR 0", nx.stats.mr, 0.0)
	_eq("inhibitor HP 4000", ih.stats.max_hp, 4000.0)
	_eq("inhibitor regen 15/s", ih.stats.hp_regen, 15.0)
	_eq("turret range 750", outer.stats.attack_range, 750.0)
	_eq("turret attack speed 0.833", outer.stats.attack_speed, 0.833, 0.001)
	_eq("turret missile speed 1200", outer.attack_missile_speed, 1200.0)
	var saved: float = m.time
	m.time = 0.0
	outer.think(0.0)
	outer.stats.recompute(outer.effects)
	_eq("outer turret AD at 0:00 = 185", outer.stats.ad, 185.0)
	_eq("outer turret armor at 0:00 = 60", outer.stats.armor, 60.0)
	m.time = 600.0
	outer.think(0.0)
	outer.stats.recompute(outer.effects)
	_eq("outer turret AD at 10:00 = 185 + 9*10 (Tower Power-Up)", outer.stats.ad, 275.0)
	_eq("outer turret armor at 10:00 = 81 (60 + 21)", outer.stats.armor, 81.0)
	m.time = 721.0
	outer.think(0.0)
	outer.stats.recompute(outer.effects)
	_eq("outer turret AD ends at 185 + 9*12 = 293", outer.stats.ad, 293.0)
	_eq("outer turret armor drops to 40 at 12:00", outer.stats.armor, 40.0)
	_eq("outer turret MR drops to 40 at 12:00", outer.stats.mr, 40.0)
	inhib_t.think(0.0)
	inhib_t.stats.recompute(inhib_t.effects)
	_eq("inhibitor turret AD at 12:01 = 205 + 12 * 12.017", inhib_t.stats.ad, 349.2)
	m.time = 1000.0
	inhib_t.think(0.0)
	inhib_t.stats.recompute(inhib_t.effects)
	_eq("inhibitor turret AD ends at 385 (15 min)", inhib_t.stats.ad, 385.0)
	_eq("inhibitor turret armor end value 84", inhib_t.stats.armor, 84.0)
	nt.think(0.0)
	nt.stats.recompute(nt.effects)
	_eq("nexus turret AD ends at 375", nt.stats.ad, 375.0)
	_eq("nexus turret armor end value 81", nt.stats.armor, 81.0)
	m.time = saved
	# fortification (inhibitor turret) 35% for 60 s after the outer turret falls
	inhib_t.backdoor_until = saved + 30.0
	_eq("fortification blocks 35%", inhib_t.damage_taken_multiplier(null), 0.65)
	inhib_t.backdoor_until = -1.0
	_eq("no fortification otherwise", inhib_t.damage_taken_multiplier(null), 1.0)
	_eq("no 'no minions' damage reduction and no melee weakness on Howling Abyss turrets", outer.damage_taken_multiplier(c), 1.0)
	# turret armor penetration 30%
	_eq("turret 30% armor pen vs 100 armor", Combat.resist_multiplier(100.0, outer, true, c), 100.0 / 170.0)
	var pen := StatMod.new("num_pen2", {"armor_pen%": 0.5})
	c.add_effect(pen)
	c.recompute_stats()
	_eq("inhibitor ignores penetration", Combat.resist_multiplier(100.0, c, true, ih), 0.5)
	_eq("other targets don't (50% pen: 100 armor -> 50)", Combat.resist_multiplier(100.0, c, true, nx.guards[0]), 100.0 / 150.0)
	c.remove_effect(pen)
	c.recompute_stats()


# ===================================================================== champion attacks vs structures / turret attacks
func _structure_attacks() -> void:
	var outer: Turret = m.outer_turrets[1] if c.team == G.Team.ORDER else m.outer_turrets[0]
	outer.invulnerable_count = 0
	outer.hp = outer.stats.max_hp
	# isolate the formula from the champion's own random modifiers
	for e in c.effects.duplicate():
		if e.id.begins_with("num_"):
			c.remove_effect(e)
	var ad: float = c.stats.ad
	var info: DamageInfo = c.attack_hit(outer, false)
	_check("AD champion vs turret: physical, amount = AD", info != null and info.type == G.DmgType.PHYSICAL and _near(info.amount, ad, 0.5),
			"amount %.1f type %d" % [info.amount if info != null else -1.0, info.type if info != null else -1])
	outer.hp = outer.stats.max_hp
	var ap_mod := StatMod.new("num_ap", {"ap": 300.0})
	c.add_effect(ap_mod)
	c.recompute_stats()
	var ad2: float = c.stats.ad
	info = c.attack_hit(outer, false)
	_check("AP champion vs turret: magic, amount = AD + 60% AP", info != null and info.type == G.DmgType.MAGIC and _near(info.amount, ad2 + 180.0, 0.5),
			"amount %.1f type %d (want %.1f magic)" % [info.amount if info != null else -1.0, info.type if info != null else -1, ad2 + 180.0])
	outer.hp = outer.stats.max_hp
	info = c.attack_hit(outer, true)
	_check("basic attacks cannot crit structures", info != null and not info.is_crit and _near(info.amount, ad2 + 180.0, 0.5))
	c.remove_effect(ap_mod)
	var mix := StatMod.new("num_mix", {"ap": 60.0, "ad": 50.0})
	c.add_effect(mix)
	c.recompute_stats()
	var ad3: float = c.stats.ad
	outer.hp = outer.stats.max_hp
	info = c.attack_hit(outer, false)
	_check("bonus AD 50 > 60% of 60 AP: still physical, amount = AD + 36", info != null and info.type == G.DmgType.PHYSICAL and _near(info.amount, ad3 + 36.0, 0.5),
			"amount %.1f type %d" % [info.amount if info != null else -1.0, info.type if info != null else -1])
	c.remove_effect(mix)
	c.recompute_stats()
	# warming up on champions: +50% per hit, max +150% after 3 hits
	var dummy: Champion = null
	for ch in m.champions:
		if ch.team != outer.team:
			dummy = ch
			break
	if dummy == null:
		return
	outer.ramp = 0
	dummy.add_effect(StatMod.new("num_tank", {"hp": 1.0e6}))
	dummy.recompute_stats()
	dummy.hp = dummy.stats.max_hp
	var base_ad: float = outer.stats.ad
	var amounts := []
	for i in 5:
		var ti: DamageInfo = outer.attack_hit(dummy, false)
		amounts.append(ti.amount / base_ad if ti != null else -1.0)
		dummy.hp = dummy.stats.max_hp
	_check("turret warming up: 1.0, 1.5, 2.0, 2.5, 2.5", _near(amounts[0], 1.0, 0.01) and _near(amounts[1], 1.5, 0.01) and _near(amounts[2], 2.0, 0.01)
			and _near(amounts[3], 2.5, 0.01) and _near(amounts[4], 2.5, 0.01), str(amounts))
	outer.ramp = 0


# ===================================================================== minion ratios, vamp rules
func _combat_ratios() -> void:
	var enemy_team := G.enemy_team(c.team)
	var mn := Minion.new()
	mn.setup(enemy_team, Minion.Type.MELEE, 0, [], 325.0)
	m.add_unit(mn, c.global_position + Vector3(3, 0, 0))
	var armor_mult := Combat.resist_multiplier(c.stats.armor, null, true)
	c.hp = c.stats.max_hp
	var info := Combat.deal(mn, c, 100.0, G.DmgType.PHYSICAL, {"is_attack": true, "no_hooks": true})
	_eq("lane minion damage to champions is x0.5", info.mitigated, 100.0 * 0.5 * armor_mult, 0.5)
	# omnivamp / life steal / spell vamp effectiveness (data: AoE/pet/DoT and minions = x0.333 omni + spell vamp)
	var vm := StatMod.new("num_vamp", {"omnivamp": 0.1, "lifesteal": 0.1, "spell_vamp": 0.1})
	c.add_effect(vm)
	c.recompute_stats()
	var enemy: Champion = null
	for ch in m.champions:
		if ch.team == enemy_team:
			enemy = ch
			break
	var ai := DamageInfo.new(c, enemy, 100.0, G.DmgType.PHYSICAL)
	ai.is_attack = true
	_eq("auto attack vs champion: omni 10% + life steal 10%", Combat.vamp_fraction(c, enemy, ai), 0.2)
	_eq("auto attack vs minion: omni x0.333 + life steal x0.6", Combat.vamp_fraction(c, mn, ai), 0.1 * 0.333 + 0.1 * 0.6)
	var si := DamageInfo.new(c, enemy, 100.0, G.DmgType.MAGIC)
	si.is_spell = true
	_eq("single-target spell vs champion: omni + spell vamp", Combat.vamp_fraction(c, enemy, si), 0.2)
	si.is_aoe = true
	_eq("area spell vs champion: both x0.333", Combat.vamp_fraction(c, enemy, si), 0.2 * 0.333)
	c.remove_effect(vm)
	c.recompute_stats()
	# area damage vs minions = 75% (champion source only)
	mn.hp = mn.stats.max_hp
	var ar := Combat.deal(c, mn, 100.0, G.DmgType.TRUE, {"is_aoe": true, "is_spell": true, "no_hooks": true})
	_eq("area damage vs minion = 75%", ar.mitigated, 75.0, 0.5)
	m.remove_unit(mn)
	# Howling Abyss aura: +70 summoner haste for everyone, +15 bonus MR and the AP structure rule for melee champions
	for ch in m.champions:
		var aura = ch.find_effect("mayhem_aura")
		if aura == null:
			continue
		var mods: Dictionary = aura.get_stat_mods()
		_eq("aura: %s summoner haste 70" % ch.alias, float(mods.get("summoner_haste", 0.0)), 70.0)
		if ch.stats.attack_range < 300.0:
			_eq("aura: melee %s +15 bonus MR" % ch.alias, float(mods.get("mr", 0.0)), 15.0)
		else:
			_eq("aura: ranged %s no bonus MR" % ch.alias, float(mods.get("mr", 0.0)), 0.0)


# ===================================================================== summoner spells
func _summoners() -> void:
	c.gain_xp(1.0e7)
	_check("player reached level 18", c.level == 18, "level %d" % c.level)
	var sh := Summoners.make("Barrier", c)
	c.shields.clear()
	sh.execute({})
	_eq("Barrier level 18 = 460", c.total_shield(), 460.0, 1.0)
	c.shields.clear()
	var heal := Summoners.make("Heal", c)
	c.hp = 1.0
	heal.execute({})
	_eq("Heal level 18 = 318 (self)", c.hp - 1.0, 318.0, 1.5)
	var ig := Summoners.make("Ignite", c)
	_eq("Ignite cooldown 180", ig.cooldowns[0], 180.0)
	_eq("Exhaust cooldown 290 on the Howling Abyss", Summoners.make("Exhaust", c).cooldowns[0], 290.0)
	var tgt: Champion = null
	for ch in m.champions:
		if ch.team != c.team:
			tgt = ch
			break
	if tgt != null:
		c.hp = c.stats.max_hp
		var d1 := Combat.deal(tgt, c, 100.0, G.DmgType.PHYSICAL, {"no_vamp": true})
		c.hp = c.stats.max_hp
		var ex := Summoners.make("Exhaust", c)
		ex.execute({"unit": tgt})
		tgt.recompute_stats()
		var d2 := Combat.deal(tgt, c, 100.0, G.DmgType.PHYSICAL, {"no_vamp": true})
		_eq("Exhaust: target deals 35% less damage", d2.mitigated / maxf(d1.mitigated, 0.001), 0.65, 0.005)
		_check("Exhaust: 40% slow", _near(tgt.stats.move_speed, maxf(tgt.stats.base.base_ms * 0.6, 0.0), 40.0), "ms %.1f" % tgt.stats.move_speed)
		var d3 := Combat.deal(tgt, c, 100.0, G.DmgType.TRUE, {"no_vamp": true})
		_eq("Exhaust does not reduce true damage", d3.mitigated, 100.0 * (d1.mitigated / maxf(100.0 * Combat.resist_multiplier(c.stats.armor, null, true), 0.001)), 0.5)
		tgt.remove_buffs_by_id("exhaust")
		c.hp = c.stats.max_hp
	_eq("Flash cooldown 300", Summoners.make("Flash", c).cooldowns[0], 300.0)
	_eq("Mark damage level 18 = 100 true", Summoners.make("Mark", c).damage(), 100.0)


# ===================================================================== minion stats and scaling
func _minions() -> void:
	var mn := Minion.new()
	mn.setup(G.enemy_team(c.team), Minion.Type.MELEE, 10, [], 325.0)
	_eq("melee minion HP after 10 upgrades = 455 + 6*19.8 + 4*6.75", mn.stats.max_hp, 455.0 + 6.0 * 19.8 + 4.0 * 6.75)
	_eq("melee minion AD after 10 upgrades = 12 + 10", mn.stats.ad, 22.0)
	_eq("melee minion XP 64", mn.xp_value, 64.0)
	_eq("melee minion gold 20 + 10*0.125", mn.gold_value, 21.25)
	mn.free()
	var sp := Minion.new()
	sp.setup(G.enemy_team(c.team), Minion.Type.SUPER, 0, [], 325.0)
	_eq("super minion 1500 HP / 306 AD / 60 armor / 10 MR", sp.stats.max_hp + sp.stats.ad + sp.stats.armor + sp.stats.mr, 1500.0 + 306.0 + 60.0 + 10.0)
	sp.free()
