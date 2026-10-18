extends RefCounted
## Stat sticks, stat conversions and infinite stackers.


static func register(reg: Dictionary) -> void:
	reg["ARAM_BluntForce"] = func(): return Simple.make({"ad%": 0.2}, 3.5, ["ad"], ["ap"], "Gain 20% increased attack damage.")
	reg["ARAM_Deft"] = func(): return Simple.make({"as": 0.6}, 2.5, ["attack", "onhit", "crit"], ["mage"], "Gain 60% bonus attack speed.")
	reg["ARAM_FirstAidKit"] = func(): return Simple.make({"heal_power": 0.2}, 1.5, ["heal", "shield", "support"], [], "Gain 20% heal and shield power.")
	reg["ARAM_Goredrink"] = func(): return Simple.make({"omnivamp": 0.15}, 2.5, [], [], "Gain 15% omnivamp.")
	reg["ARAM_ItsCritical"] = func(): return Simple.make({"crit": 0.5}, 2.5, ["crit", "attack"], ["mage", "tank"], "Gain 50% critical strike chance.")
	reg["ARAM_Recursion"] = func(): return Simple.make({"ah": 60.0}, 4.0, ["ability"], [], "Gain 60 ability haste.")
	reg["ARAM_ThreadtheNeedle"] = func(): return Simple.make({"armor_pen%": 0.18, "magic_pen%": 0.18}, 2.0, [], ["tank", "support"], "Gain 18% armor penetration and magic penetration.")
	reg["ARAM_ScopedWeapons"] = func(): return RangeAug.make(75.0, 50.0, 1.5, "Gain 75 (melee) / 50 (ranged) bonus attack range.")
	reg["ARAM_ScopierWeapons"] = func(): return RangeAug.make(200.0, 100.0, 2.0, "Gain 200 (melee) / 100 (ranged) bonus attack range.")
	reg["ARAM_ScopiestWeapons"] = func(): return RangeAug.make(250.0, 150.0, 2.2, "Gain 250 (melee) / 150 (ranged) bonus attack range.")
	reg["ARAM_WitchfulThinking"] = func(): return Witchful.new()
	reg["ARAM_Zealot"] = func(): return Zealot.new()
	reg["WarlockJuicebox"] = func(): return Juicebox.new()
	reg["ARAM_Eureka"] = func(): return Eureka.new()
	reg["ARAM_ProteinShake"] = func(): return ProteinShake.new()
	reg["ARAM_ADAPt"] = func(): return Adapt.new()
	reg["ARAM_escAPADe"] = func(): return Escapade.new()
	reg["ARAM_Purist_Caster"] = func(): return PuristCaster.new()
	reg["ARAM_DontBlink"] = func(): return DontBlink.new()
	reg["ARAM_Erosion"] = func(): return Erosion.new()
	reg["ForgedByTheMaster"] = func(): return Forged.new()
	reg["BrushPower"] = func(): return HideOnBush.new()
	reg["ARAM_SlapAround"] = func(): return SlapAround.new()
	reg["ARAM_StackosaurusRex"] = func(): return Stackosaurus.new()
	reg["ARAM_PhenomenalEvil"] = func(): return PhenomenalEvil.new()
	reg["ShrinkEngine"] = func(): return ShrinkEngine.new()
	reg["ARAM_TankEngine"] = func(): return TankEngine.new()
	reg["SoulEater"] = func(): return SoulEater.new()
	reg["InfiniteRecursion"] = func(): return InfiniteRecursion.new()
	reg["ARAM_MasterofDuality"] = func(): return MasterOfDuality.new()
	reg["ARAM_TapDancer"] = func(): return TapDancer.new()
	reg["ARAM_ImTheJuggernaut"] = func(): return TitansResolve.new()


## Generic static-stat augment with tag-based bot synergy.
class Simple extends Augment:
	var good_tags: Array = []
	var bad_tags: Array = []

	static func make(st: Dictionary, pw: float, good: Array, bad: Array, desc: String) -> Simple:
		var a := Simple.new()
		a.stats = st
		a.power = pw
		a.good_tags = good
		a.bad_tags = bad
		a.description = desc
		return a

	func synergy(c) -> float:
		var s := 0.0
		var tags := AugmentDB.champion_tags(c)
		for t in good_tags:
			if t in tags:
				s += 1.0
		for t in bad_tags:
			if t in tags:
				s -= 1.5
		return s


class RangeAug extends Augment:
	var melee_r := 75.0
	var ranged_r := 50.0

	static func make(m: float, r: float, pw: float, desc: String) -> RangeAug:
		var a := RangeAug.new()
		a.melee_r = m
		a.ranged_r = r
		a.power = pw
		a.description = desc
		return a

	func get_stat_mods() -> Dictionary:
		return {"range": melee_r if is_melee() else ranged_r}

	func synergy(c) -> float:
		return 1.0 if has_tag(c, "attack") else -1.0


class Witchful extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Gain 20-80 ability power (based on level)."

	func get_stat_mods() -> Dictionary:
		return {"ap": lvl_lerp(20.0, 80.0)}

	func synergy(c) -> float:
		return 1.5 if has_tag(c, "ap") else -1.5


class Zealot extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Gain 35% (+5% per 100 AP) bonus attack speed and 25% (+5% per 100 AP) critical strike chance."

	func get_stat_mods() -> Dictionary:
		var ap: float = owner.stats.ap if owner != null else 0.0
		return {"as": 0.35 + 0.05 * ap / 100.0, "crit": 0.25 + 0.05 * ap / 100.0}

	func synergy(c) -> float:
		return 1.0 if has_tag(c, "attack") else 0.0


class Juicebox extends Augment:
	func _init() -> void:
		power = 3.5
		description = "Gain 10% (+3% per 100 AP) omnivamp."

	func get_stat_mods() -> Dictionary:
		var ap: float = owner.stats.ap if owner != null else 0.0
		return {"omnivamp": 0.1 + 0.03 * ap / 100.0}

	func synergy(c) -> float:
		return 1.0 if has_tag(c, "ap") else 0.0


class Eureka extends Augment:
	func _init() -> void:
		power = 3.5
		description = "Gain ability haste equal to 30% of your ability power."

	func get_stat_mods() -> Dictionary:
		return {"ah": 0.3 * (owner.stats.ap if owner != null else 0.0)}

	func synergy(c) -> float:
		return 1.5 if has_tag(c, "ap") else -2.0


class ProteinShake extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Gain 25% (+35% per 100 bonus armor) (+35% per 100 bonus magic resist) heal and shield power."

	func get_stat_mods() -> Dictionary:
		if owner == null:
			return {"heal_power": 0.25}
		return {"heal_power": 0.25 + 0.35 * owner.stats.bonus_armor / 100.0 + 0.35 * owner.stats.bonus_mr / 100.0}

	func synergy(c) -> float:
		return 1.5 if has_tag(c, "heal") or has_tag(c, "shield") or has_tag(c, "tank") else -1.0


class Adapt extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Convert all bonus attack damage into ability power (1 AP per 0.6 bonus AD) and increase ability power by 15%."

	func get_stat_mods() -> Dictionary:
		if owner == null:
			return {"ap%": 0.15}
		var bad := Augment.sum_other(owner, "ad", self)
		return {"ad": -bad, "ap": bad / 0.6, "ap%": 0.15}

	func synergy(c) -> float:
		return 1.0 if has_tag(c, "ap") else -2.0


class Escapade extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Convert all ability power into bonus attack damage (1 AD per 1.66 AP) and increase total attack damage by 15%."

	func get_stat_mods() -> Dictionary:
		if owner == null:
			return {"ad%": 0.15}
		var ap := Augment.sum_other(owner, "ap", self)
		return {"ap": -ap, "ad": ap / 1.66, "ad%": 0.15}

	func synergy(c) -> float:
		return 1.0 if has_tag(c, "ad") else -2.0


class PuristCaster extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Convert all bonus attack speed into ability haste (0.65 per 1%), and your abilities' cooldowns are reduced by 10%."

	func get_stat_mods() -> Dictionary:
		if owner == null:
			return {}
		var bas := Augment.sum_other(owner, "as", self) + Stats.growth(owner.stats.base.attack_speed_per_level, owner.level) / 100.0
		return {"as": -bas, "ah": bas * 100.0 * 0.65}

	func modify_cooldown(_ab, cd: float) -> float:
		return cd * 0.9 if not _ab.is_summoner else cd

	func synergy(c) -> float:
		return 1.5 if has_tag(c, "ability") else -1.0


class DontBlink extends Augment:
	func _init() -> void:
		power = 1.5
		description = "Deal 1% increased damage per 10 movement speed you have more than the target."

	func on_pre_damage_dealt(info) -> void:
		var diff: float = owner.stats.move_speed - info.target.stats.move_speed
		if diff > 0.0 and info.target.kind != G.Kind.TURRET:
			info.mult *= 1.0 + diff / 10.0 * 0.01


class Erosion extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Each instance of damage reduces the target's armor and magic resist by 1.5% for 4 seconds, stacking up to 20 times (30%)."

	func on_damage_dealt(info) -> void:
		var t = info.target
		if t == null or t.dead or info.final + info.absorbed <= 0.0 or t.kind == G.Kind.TURRET:
			return
		var b: Buff = t.find_buff("erosion", owner)
		if b == null:
			b = Buff.new("erosion", 4.0)
			b.display_name = "Erosion"
			b.is_debuff = true
			b.max_stacks = 20
			b.stack_mode = Buff.Stack.ADD_STACK
			b.stats_per_stack = {"armor%": -0.015, "mr%": -0.015}
			b.stacks = 1
			t.add_buff(b, owner)
		else:
			b.stacks = mini(b.max_stacks, b.stacks + 1)
			b.remaining = 4.0
			t.stats.mark_dirty()


class Forged extends Augment:
	func _init() -> void:
		power = 1.5
		description = "Increase the damage dealt by your item effects and augments by 45%."

	func on_pre_damage_dealt(info) -> void:
		if info.is_proc and not info.is_attack:
			info.mult *= 1.45


class HideOnBush extends Augment:
	var linger := 0.0

	func _init() -> void:
		power = 1.5
		description = "While in brush, deal 20% increased damage. Lingers for 2 seconds after leaving brush."

	func on_tick(u, dt: float) -> void:
		if u.in_brush > 0:
			linger = 2.0
		else:
			linger = maxf(0.0, linger - dt)

	func on_pre_damage_dealt(info) -> void:
		if linger > 0.0:
			info.mult *= 1.2


class SlapAround extends Augment:
	var stacks := 0
	var cd := 0.0

	func _init() -> void:
		power = 2.0
		description = "Immobilizing or grounding an enemy champion grants 10 adaptive force, stacking infinitely. Lose 50% of stacks on death."

	func fits(c) -> bool:
		return has_tag(c, "cc")

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_cc_applied(target, buff) -> void:
		if target.kind == G.Kind.CHAMPION and (buff.cc & (Buff.IMMOBILIZE | Buff.CC.GROUNDED)) != 0 and cd <= 0.0:
			cd = 0.5
			stacks += 1
			counter_text = str(stacks)
			refresh_stats()

	func on_death(_k) -> void:
		stacks = stacks / 2
		counter_text = str(stacks)
		refresh_stats()

	func get_stat_mods() -> Dictionary:
		return {"adaptive": stacks * 10.0}


class Stackosaurus extends Augment:
	func _init() -> void:
		power = 1.0
		description = "Increase the number of permanent stacks you gain from abilities by 100%."

	func fits(c) -> bool:
		return has_tag(c, "stacks") or c.has_augment("ARAM_PhenomenalEvil")

	func permanent_stack_mult() -> float:
		return 2.0

	func synergy(c) -> float:
		return 3.0 if has_tag(c, "stacks") or c.has_augment("ARAM_PhenomenalEvil") else -3.0


class PhenomenalEvil extends Augment:
	var stacks := 0.0
	var gcd := 0.0
	var per_cast := {}

	func _init() -> void:
		power = 3.5
		description = "Each ability hit on an enemy champion grants a permanent stack of 1 ability power (max once per second). If this is not your first augment, start with 40 stacks."

	func on_acquire(c) -> void:
		if c.augments.size() > 1:
			stacks = 40.0
		counter_text = str(int(stacks))
		refresh_stats()

	func on_tick(_u, dt: float) -> void:
		gcd = maxf(0.0, gcd - dt)

	func on_damage_dealt(info) -> void:
		if info.is_spell and info.target != null and info.target.kind == G.Kind.CHAMPION and gcd <= 0.0 and not info.is_dot:
			gcd = 1.0
			stacks += 1.0 * owner.permanent_stack_mult()
			counter_text = str(int(stacks))
			refresh_stats()
			Vfx.hit_spark(owner.match_ref, owner.global_position + Vector3(0, owner.height, 0), Color(0.7, 0.4, 1.0), 0.5)

	func get_stat_mods() -> Dictionary:
		return {"ap": stacks}

	func synergy(c) -> float:
		return 1.5 if has_tag(c, "ap") else -2.0


class ShrinkEngine extends Augment:
	var stacks := 0

	func _init() -> void:
		power = 4.0
		description = "Champion takedowns grant a stack (infinite): +8 ability haste, +1% movement speed and -4% size each (size capped at 20 stacks). Lose 65% of stacks on death."

	func on_takedown(_v) -> void:
		stacks += 1
		counter_text = str(stacks)
		refresh_stats()

	func on_death(_k) -> void:
		stacks = int(stacks * 0.35)
		counter_text = str(stacks)
		refresh_stats()

	func get_stat_mods() -> Dictionary:
		return {"ah": stacks * 8.0, "ms%": stacks * 0.01, "size": -0.04 * mini(stacks, 20)}


class TankEngine extends Augment:
	var stacks := 0

	func _init() -> void:
		power = 4.0
		description = "Champion takedowns grant a stack (infinite): increase your maximum health and size by 5% each. Lose 65% of stacks on death."

	func on_takedown(_v) -> void:
		stacks += 1
		counter_text = str(stacks)
		refresh_stats()
		Vfx.rising(owner, Color(1.0, 0.75, 0.35), 0.6, 30)

	func on_death(_k) -> void:
		stacks = int(stacks * 0.35)
		counter_text = str(stacks)
		refresh_stats()

	func get_stat_mods() -> Dictionary:
		return {"hp%": stacks * 0.05, "size": stacks * 0.05}

	func synergy(c) -> float:
		return 1.0 if has_tag(c, "melee") else 0.0


class SoulEater extends Augment:
	var bonus := 0.0
	var cd := 0.0

	func _init() -> void:
		power = 2.0
		description = "Immobilizing or grounding an enemy champion grants 20 bonus health, stacking infinitely. If this is not your first augment, gain 300 bonus health."

	func fits(c) -> bool:
		return has_tag(c, "cc")

	func on_acquire(c) -> void:
		if c.augments.size() > 1:
			bonus += 300.0
		refresh_stats()

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_cc_applied(target, buff) -> void:
		if target.kind == G.Kind.CHAMPION and (buff.cc & (Buff.IMMOBILIZE | Buff.CC.GROUNDED)) != 0 and cd <= 0.0:
			cd = 0.5
			bonus += 20.0
			counter_text = str(int(bonus))
			refresh_stats()

	func get_stat_mods() -> Dictionary:
		return {"hp": bonus}


class InfiniteRecursion extends Augment:
	var takedowns := 0

	func _init() -> void:
		power = 3.5
		description = "Gain 60 ability haste, increased by 3 for each champion takedown."

	func on_takedown(_v) -> void:
		takedowns += 1
		counter_text = str(60 + takedowns * 3)
		refresh_stats()

	func get_stat_mods() -> Dictionary:
		return {"ah": 60.0 + takedowns * 3.0}


class MasterOfDuality extends Augment:
	func _init() -> void:
		power = 2.5
		description = "Basic attacks grant 6-18 AP and abilities grant 3-9 bonus AD (once per cast) for 5 seconds. Duration refreshes and stacks infinitely."

	func on_attack_hit(_t, _info) -> void:
		_stack("duality_ap", {"ap": lvl_lerp(6.0, 18.0)})

	func on_ability_cast(_ab, _t) -> void:
		_stack("duality_ad", {"ad": lvl_lerp(3.0, 9.0)})

	func _stack(bid: String, per: Dictionary) -> void:
		var b: Buff = owner.find_buff(bid)
		if b == null:
			b = Buff.new(bid, 5.0)
			b.display_name = "Master of Duality"
			b.max_stacks = 9999
			b.stack_mode = Buff.Stack.ADD_STACK
			b.stats_per_stack = per
			owner.add_buff(b, owner)
		else:
			b.stacks += 1
			b.remaining = 5.0
			owner.stats.mark_dirty()


class TapDancer extends Augment:
	func _init() -> void:
		power = 2.5
		description = "Basic attacks grant 10 movement speed for 5 seconds, stacking infinitely. Gain bonus attack speed equal to 10% of your movement speed."

	func fits(c) -> bool:
		return has_tag(c, "attack")

	func on_attack_hit(t, _info) -> void:
		if t.kind != G.Kind.CHAMPION and t.kind != G.Kind.MINION:
			return
		var b: Buff = owner.find_buff("tap_dancer")
		if b == null:
			b = Buff.new("tap_dancer", 5.0)
			b.display_name = "Tap Dancer"
			b.max_stacks = 9999
			b.stack_mode = Buff.Stack.ADD_STACK
			b.stats_per_stack = {"ms": 10.0}
			owner.add_buff(b, owner)
		else:
			b.stacks += 1
			b.remaining = 5.0
			owner.stats.mark_dirty()

	func get_stat_mods() -> Dictionary:
		return {"as": (owner.stats.move_speed * 0.1 / 100.0) if owner != null else 0.0}


class TitansResolve extends Augment:
	var stacks := 0
	var timer := 0.0

	func _init() -> void:
		power = 3.0
		description = "Dealing or taking damage grants a stack (6s, max 10). At max: 15-45 bonus AD or 25-75 AP, +5-10 armor and MR, +10% size and +8% tenacity."

	func _add() -> void:
		timer = 6.0
		if stacks < 10:
			stacks += 1
			counter_text = str(stacks)
			refresh_stats()

	func on_damage_dealt(info) -> void:
		if not info.is_dot and info.target != null and info.target.kind != G.Kind.MINION:
			_add()

	func on_damage_taken(info) -> void:
		if not info.is_dot and info.source != null and info.source.kind == G.Kind.CHAMPION:
			_add()

	func on_tick(_u, dt: float) -> void:
		if stacks > 0:
			timer -= dt
			if timer <= 0.0:
				stacks = 0
				counter_text = ""
				refresh_stats()

	func get_stat_mods() -> Dictionary:
		if stacks < 10:
			return {}
		var d := {"armor": lvl_lerp(5.0, 10.0), "mr": lvl_lerp(5.0, 10.0), "size": 0.1, "tenacity": 0.08}
		if owner.stats.bonus_ad >= owner.stats.ap:
			d["ad"] = lvl_lerp(15.0, 45.0)
		else:
			d["ap"] = lvl_lerp(25.0, 75.0)
		return d
