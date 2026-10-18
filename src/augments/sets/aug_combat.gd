extends RefCounted
## Basic attacks / on-hit / crit / spell damage / burns.


static func register(reg: Dictionary) -> void:
	reg["ARAM_HeavyHitter"] = func(): return HeavyHitter.new()
	reg["ARAM_Juiced"] = func(): return Juiced.new()
	reg["ARAM_LightemUp"] = func(): return LightEmUp.new()
	reg["Twinfire"] = func(): return TwinFire.new()
	reg["ARAM_Typhoon"] = func(): return Typhoon.new()
	reg["CriticalMissile"] = func(): return CriticalMissile.new()
	reg["CriticalRhythm"] = func(): return CriticalRhythm.new()
	reg["ARAM_EtherealWeapon"] = func(): return EtherealWeapon.new()
	reg["ARAM_Marksmage"] = func(): return Marksmage.new()
	reg["ARAM_SoulSiphon"] = func(): return SoulSiphon.new()
	reg["ARAM_DoubleTap"] = func(): return DoubleTap.new()
	reg["ARAM_DrawYourSword"] = func(): return DrawYourSword.new()
	reg["ARAM_DualWield"] = func(): return DualWield.new()
	reg["ARAM_Firebrand"] = func(): return Firebrand.new()
	reg["ARAM_MagicMissile"] = func(): return MagicMissile.new()
	reg["ARAM_Overflow"] = func(): return Overflow.new()
	reg["PressureCooker"] = func(): return PressureCooker.new()
	reg["ARAM_SpiritualPurification"] = func(): return SpiritualPurification.new()
	reg["ARAM_Vulnerability"] = func(): return Vulnerability.new()
	reg["ARAM_Cruelty"] = func(): return Cruelty.new()
	reg["GlassCannon"] = func(): return GlassCannon.new()
	reg["ARAM_InfernalConduit"] = func(): return InfernalConduit.new()
	reg["ARAM_JeweledGauntlet"] = func(): return JeweledGauntlet.new()
	reg["OminousPact"] = func(): return OminousPact.new()
	reg["ARAM_IceCold"] = func(): return IceCold.new()
	reg["Goldrend"] = func(): return Goldrend.new()


static func burn_color() -> Color:
	return Color(1.0, 0.5, 0.15)


class HeavyHitter extends Augment:
	func _init() -> void:
		power = 3.5
		description = "Basic attacks deal bonus physical damage equal to 3.5% of your maximum health."

	func on_attack_hit(t, info) -> void:
		var mult: float = info.on_hit_mult if info != null else 1.0
		proc(t, owner.stats.max_hp * 0.035 * mult, G.DmgType.PHYSICAL, "heavy_hitter")

	func synergy(c) -> float:
		return 1.5 if has_tag(c, "tank") or has_tag(c, "fighter") else (0.5 if has_tag(c, "attack") else -1.0)


class Juiced extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Basic attacks against champions deal bonus magic damage equal to 7% (melee) / 5.6% (ranged) of your maximum mana. This damage can critically strike."

	func fits(c) -> bool:
		return c.stats.uses_mana

	func on_attack_hit(t, info) -> void:
		if t.kind != G.Kind.CHAMPION:
			return
		var pct := 0.07 if is_melee() else 0.056
		var mult: float = info.on_hit_mult if info != null else 1.0
		var d := Combat.deal(owner, t, owner.stats.max_mana * pct * mult, G.DmgType.MAGIC,
				{"is_proc": true, "tag": "juiced", "can_crit": true, "crit_mult": owner.stats.crit_damage + 0.3})
		Vfx.hit_spark(owner.match_ref, t.global_position + Vector3(0, 1.1, 0), Color(0.35, 0.6, 1.0), 0.5)


class LightEmUp extends Augment:
	var count := 0

	func _init() -> void:
		power = 2.0
		description = "Every 4th basic attack fires 4 missiles at the target, each dealing 11-80 (+35% bonus AD) (+19% AP) magic damage."

	func fits(c) -> bool:
		return has_tag(c, "attack")

	func on_attack_hit(t, info) -> void:
		if info != null and info.on_hit_mult < 1.0:
			return
		count += 1
		counter_text = str(count)
		if count < 4:
			return
		count = 0
		counter_text = ""
		var dmg: float = lvl_lerp(11.0, 80.0) + 0.35 * owner.stats.bonus_ad + 0.19 * owner.stats.ap
		var mm = owner.match_ref
		for i in 4:
			var from: Vector3 = owner.global_position + Vector3(cos(i * 1.6) * 0.6, 1.6, sin(i * 1.6) * 0.6)
			var mi := Missile.new()
			mi.setup_homing(owner, from, t, 14.0 + i)
			mi.height = 1.2
			mi.visual = Vfx.orb(Color(1.0, 0.85, 0.3), 0.3, false)
			var self_ref := self
			mi.on_hit = func(_m, u): self_ref.proc(u, dmg, G.DmgType.MAGIC, "light_em_up")
			mm.add_missile(mi, from)


class TwinFire extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 2.0
		stats = {"crit": 0.25}
		description = "Damaging abilities against champions launch 1 (+1 per 33% crit chance) missiles dealing 10-30 (+7% bonus AD) (+7% AP) magic damage (5s cooldown). Gain 25% crit chance."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_damage_dealt(info) -> void:
		if cd > 0.0 or not info.is_spell or info.target == null or info.target.kind != G.Kind.CHAMPION:
			return
		cd = 5.0
		var n := 1 + int(owner.stats.crit_chance / 0.3333)
		var dmg: float = lvl_lerp(10.0, 30.0) + 0.07 * owner.stats.bonus_ad + 0.07 * owner.stats.ap
		var t = info.target
		for i in n:
			var from: Vector3 = owner.global_position + Vector3(0, 1.4, 0)
			var mi := Missile.new()
			mi.setup_homing(owner, from, t, 13.0 + i * 1.5)
			mi.visual = Vfx.orb(Color(1.0, 0.45, 0.25), 0.28, false)
			var self_ref := self
			mi.on_hit = func(_m, u): self_ref.proc(u, dmg, G.DmgType.MAGIC, "twin_fire")
			owner.match_ref.add_missile(mi, from)


class Typhoon extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Basic attacks launch a bolt at a nearby enemy, prioritizing champions, dealing 30% AD physical damage and applying on-hit effects."

	func fits(c) -> bool:
		return has_tag(c, "attack")

	func on_attack_hit(t, info) -> void:
		if info == null or info.on_hit_mult < 1.0 or info.tag == "typhoon":
			return
		var best = null
		var bd := INF
		for u in owner.match_ref.enemies_in_radius(owner.team, t.global_position, 6.0):
			if u == t:
				continue
			var d: float = G.flat_dist(u.global_position, t.global_position) - (5.0 if u.kind == G.Kind.CHAMPION else 0.0)
			if d < bd:
				bd = d
				best = u
		if best == null:
			return
		var from: Vector3 = owner.global_position + Vector3(0, 1.2, 0)
		var mi := Missile.new()
		mi.setup_homing(owner, from, best, 16.0)
		mi.visual = Vfx.orb(Color(0.6, 0.9, 1.0), 0.28, false)
		var self_ref := self
		mi.on_hit = func(_m, u):
			var inf := Combat.deal(self_ref.owner, u, self_ref.owner.stats.ad * 0.3, G.DmgType.PHYSICAL, {"is_proc": true, "tag": "typhoon"})
			self_ref.owner.trigger_on_hit(u, inf, 1.0, self_ref)
		owner.match_ref.add_missile(mi, from)


class CriticalMissile extends Augment:
	func _init() -> void:
		power = 3.5
		stats = {"crit": 0.25}
		description = "Critical strikes against champions launch 1 (+1 per 50% crit chance) missiles dealing 15-65 magic damage each. Gain 25% crit chance."

	func on_damage_dealt(info) -> void:
		if not info.is_crit or info.target == null or info.target.kind != G.Kind.CHAMPION or info.tag == "crit_missile":
			return
		var n := 1 + int(owner.stats.crit_chance / 0.5)
		var t = info.target
		for i in n:
			var from: Vector3 = owner.global_position + Vector3(0, 1.6, 0)
			var mi := Missile.new()
			mi.setup_homing(owner, from, t, 12.0 + i * 2.0)
			mi.visual = Vfx.orb(Color(1.0, 0.75, 0.3), 0.3, false)
			var self_ref := self
			var dmg: float = lvl_lerp(15.0, 65.0)
			mi.on_hit = func(_m, u): self_ref.proc(u, dmg, G.DmgType.MAGIC, "crit_missile")
			owner.match_ref.add_missile(mi, from)


class CriticalRhythm extends Augment:
	func _init() -> void:
		power = 2.5
		stats = {"crit": 0.25}
		description = "Critical strikes grant 6% attack speed for 6 seconds, stacking up to 10 times (60%). Gain 25% crit chance."

	func on_damage_dealt(info) -> void:
		if info.is_crit:
			var b: Buff = owner.find_buff("crit_rhythm")
			if b == null:
				b = Buff.new("crit_rhythm", 6.0)
				b.display_name = "Critical Rhythm"
				b.max_stacks = 10
				b.stack_mode = Buff.Stack.ADD_STACK
				b.stats_per_stack = {"as": 0.06}
				owner.add_buff(b, owner)
			else:
				b.stacks = mini(10, b.stacks + 1)
				b.remaining = 6.0
				owner.stats.mark_dirty()

	func synergy(c) -> float:
		return 1.5 if has_tag(c, "crit") or has_tag(c, "attack") else -1.0


class EtherealWeapon extends Augment:
	var cds := {}

	func _init() -> void:
		power = 3.5
		description = "Your abilities apply on-hit effects (1 second cooldown per target)."

	func on_damage_dealt(info) -> void:
		if not info.is_spell or info.target == null or info.no_hooks:
			return
		var t = info.target
		var now_t: float = owner.match_ref.time
		if now_t - cds.get(t, -10.0) < 1.0:
			return
		cds[t] = now_t
		owner.trigger_on_hit(t, info, 1.0, self)

	func synergy(c) -> float:
		return 1.5 if has_tag(c, "onhit") or c.has_augment("ARAM_MysticPunch") else 0.5


class Marksmage extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Basic attacks deal bonus physical damage equal to 75% of your ability power."

	func on_attack_hit(t, info) -> void:
		var mult: float = info.on_hit_mult if info != null else 1.0
		if owner.stats.ap > 0.0:
			proc(t, owner.stats.ap * 0.75 * mult, G.DmgType.PHYSICAL, "marksmage")

	func synergy(c) -> float:
		return 1.0 if has_tag(c, "ap") else -1.0


class SoulSiphon extends Augment:
	func _init() -> void:
		power = 3.5
		stats = {"crit": 0.25}
		description = "Heal for 12% of the damage dealt by your critical strikes. Gain 25% crit chance."

	func on_damage_dealt(info) -> void:
		if info.is_crit and info.mitigated > 0.0:
			Combat.heal(owner, owner, info.mitigated * 0.12, {"is_vamp": true, "show": false})

	func synergy(c) -> float:
		return 1.0 if has_tag(c, "crit") or has_tag(c, "attack") else -0.5


class DoubleTap extends Augment:
	func _init() -> void:
		power = 2.5
		stats = {"crit": 0.25}
		description = "Basic attacks that critically strike apply on-hit effects an additional time. Gain 25% crit chance."

	func on_attack_hit(t, info) -> void:
		if info != null and info.is_crit and info.is_attack and info.on_hit_mult >= 1.0:
			owner.trigger_on_hit(t, info, 0.999, self)


class DrawYourSword extends Augment:
	var k := 0.0

	func _init() -> void:
		power = 4.0
		description = "Become melee: your attack range becomes 200 and you gain bonus attack damage, attack speed, health and move speed (more for longer-ranged champions) and 20% life steal."

	func fits(c) -> bool:
		return not is_melee(c)

	func on_attach(u) -> void:
		k = clampf((float(u.stats.base.attack_range) - 500.0) / 150.0, 0.0, 1.0)
		u.set_meta("orig_missile", u.attack_missile_speed)
		u.attack_missile_speed = 0.0
		u.stats.mark_dirty()

	func get_stat_mods() -> Dictionary:
		if owner == null:
			return {}
		return {"range": 200.0 - float(owner.stats.base.attack_range), "ad%": lerpf(0.24, 0.5, k), "as": lerpf(0.2, 0.6, k),
			"hp%": lerpf(0.24, 0.45, k), "ms%": lerpf(0.1, 0.2, k), "lifesteal": 0.2, "armor": 20.0, "mr": 20.0}

	func synergy(c) -> float:
		return 1.0 if has_tag(c, "attack") else -0.5


class DualWield extends Augment:
	func _init() -> void:
		power = 3.0
		stats = {"as": 0.1}
		description = "Basic attacks launch a bolt after 0.225s dealing 40% of the attack's damage and applying on-hit effects at 40% effectiveness. Gain 10% attack speed."

	func fits(c) -> bool:
		return has_tag(c, "attack")

	func on_attack_hit(t, info) -> void:
		if info == null or not info.is_attack or info.on_hit_mult < 1.0:
			return
		var amt: float = info.amount
		var self_ref := self
		owner.match_ref.after(0.225, func():
			if is_instance_valid(t) and not t.dead and is_instance_valid(self_ref.owner):
				var d := Combat.deal(self_ref.owner, t, amt * 0.4, G.DmgType.PHYSICAL, {"is_proc": true, "tag": "dual_wield"})
				self_ref.owner.trigger_on_hit(t, d, 0.4, self_ref)
				Vfx.hit_spark(self_ref.owner.match_ref, t.global_position + Vector3(0, 1.1, 0), Color(0.9, 0.9, 1.0), 0.45))


class Firebrand extends Augment:
	func _init() -> void:
		power = 2.5
		description = "Basic attacks apply a stacking Burn for 5 seconds dealing 0.4% of the target's maximum health as magic damage per second per stack."

	func on_attack_hit(t, info) -> void:
		if t.kind == G.Kind.TURRET or t.kind == G.Kind.INHIBITOR or t.kind == G.Kind.NEXUS:
			return
		var b: Buff = t.find_buff("firebrand", owner)
		if b == null:
			b = Buff.new("firebrand", 5.0)
			b.display_name = "Burn"
			b.is_debuff = true
			b.tick_interval = 0.5
			b.max_stacks = 999
			b.stack_mode = Buff.Stack.INDEPENDENT
			var src = owner
			var bb := b
			b.on_interval = func(_x):
				if is_instance_valid(src) and not t.dead:
					Combat.deal(src, t, t.stats.max_hp * 0.004 * bb.stacks * 0.5, G.DmgType.MAGIC, {"is_dot": true, "is_proc": true, "tag": "burn"})
			t.add_buff(b, owner)
		else:
			b.stacks += 1
			b.remaining = 5.0


class MagicMissile extends Augment:
	var last_cast := {}

	func _init() -> void:
		power = 2.5
		description = "Damaging a champion with an ability fires 3 missiles that each deal 0.33-1% of the target's max health as true damage (more over longer distance). Once every 6 seconds per ability."

	func on_damage_dealt(info) -> void:
		if not info.is_spell or info.target == null or info.target.kind != G.Kind.CHAMPION or info.ability == null:
			return
		var now_t: float = owner.match_ref.time
		if now_t - last_cast.get(info.ability, -10.0) < 6.0:
			return
		last_cast[info.ability] = now_t
		var t = info.target
		for i in 3:
			var from: Vector3 = owner.global_position + Vector3(cos(i * 2.1), 1.8, sin(i * 2.1)) * 0.8
			var mi := Missile.new()
			mi.setup_homing(owner, from, t, 9.0 + i)
			mi.visual = Vfx.orb(Color(0.75, 0.55, 1.0), 0.3, false)
			var self_ref := self
			mi.on_hit = func(m2, u):
				var dist: float = m2.traveled / G.U
				var pct := lerpf(0.0033, 0.01, clampf(dist / 1000.0, 0.0, 1.0))
				self_ref.proc(u, u.stats.max_hp * pct, G.DmgType.TRUE, "magic_missile")
			owner.match_ref.add_missile(mi, from)


class Overflow extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Your abilities cost double mana, but you deal 10% (+0.5% per 100 max mana) increased damage and healing/shielding."

	func fits(c) -> bool:
		return c.stats.uses_mana

	func _amp() -> float:
		return 0.1 + 0.005 * owner.stats.max_mana / 100.0

	func on_ability_cast(ab, _t) -> void:
		if not ab.is_summoner and owner.stats.uses_mana:
			owner.mana = maxf(0.0, owner.mana - ab.cost())

	func on_pre_damage_dealt(info) -> void:
		info.mult *= 1.0 + _amp()

	func modify_heal_shield_dealt(amount: float, _t, _s: bool) -> float:
		return amount * (1.0 + _amp())


class PressureCooker extends Augment:
	var acc := 0.0

	func _init() -> void:
		power = 2.0
		description = "Burn aura: every second, enemy champions within 350 units gain a stacking 3 second Burn dealing 0.5% of YOUR maximum health per second."

	func on_tick(u, dt: float) -> void:
		acc += dt
		if acc < 1.0 or u.dead:
			return
		acc = 0.0
		for e in u.match_ref.enemies_in_radius(u.team, u.global_position, 3.5, true):
			var src = u
			var b := Buff.new("pressure_cooker", 3.0)
			b.display_name = "Burn"
			b.is_debuff = true
			b.tick_interval = 0.5
			b.max_stacks = 99
			b.stack_mode = Buff.Stack.ADD_STACK
			var tgt = e
			b.on_interval = func(bb):
				if is_instance_valid(src):
					Combat.deal(src, tgt, src.stats.max_hp * 0.005 * 0.5 * bb.stacks, G.DmgType.MAGIC, {"is_dot": true, "is_proc": true, "tag": "burn"})
			e.add_buff(b, u)
		Vfx.ring(u.match_ref, u.global_position, Color(1.0, 0.45, 0.15), 3.5, 0.5, 0.06, 0.08)

	func synergy(c) -> float:
		return 1.5 if has_tag(c, "tank") or has_tag(c, "melee") else -1.0


class SpiritualPurification extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Champion takedowns make the area explode (500 radius), dealing adaptive damage equal to 15% of enemies' current health and slowing them by 60% for 1.5s."

	func on_takedown(victim) -> void:
		var m = owner.match_ref
		var pos: Vector3 = victim.global_position
		Vfx.burst(m, pos + Vector3(0, 0.6, 0), Color(0.9, 0.95, 1.0), 3.0, {"sparks": 40})
		for e in m.enemies_in_radius(owner.team, pos, 5.0):
			proc(e, e.hp * 0.15, adaptive_type(), "purification")
			K.slow(e, 0.6, 1.5, owner)


class Vulnerability extends Augment:
	func _init() -> void:
		power = 3.5
		stats = {"crit": 0.25}
		description = "Damage from items, augments and damage-over-time effects can critically strike (145% + bonus crit damage). Gain 25% crit chance."

	func on_pre_damage_dealt(info) -> void:
		if (info.is_proc or info.is_dot) and not info.is_attack:
			info.can_crit = true


class Cruelty extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 2.5
		description = "Immobilizing an enemy champion calls down a comet that lands after 1 second, dealing 50-150 (+40% AP) (+4% max health) magic damage around them (6s cooldown)."

	func fits(c) -> bool:
		return has_tag(c, "cc")

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_cc_applied(target, buff) -> void:
		if cd > 0.0 or target.kind != G.Kind.CHAMPION or (buff.cc & (Buff.IMMOBILIZE | Buff.CC.GROUNDED)) == 0:
			return
		cd = 6.0
		var m = owner.match_ref
		var pos: Vector3 = target.global_position
		var dmg: float = lvl_lerp(50.0, 150.0) + 0.4 * owner.stats.ap + 0.04 * owner.stats.max_hp
		Vfx.ground_circle(m, pos, 3.0, Color(0.6, 0.5, 1.0, 0.8), 1.05, 0.25)
		var comet := Vfx.orb(Color(0.65, 0.5, 1.0), 0.9, true)
		m.add_fx(comet, pos + Vector3(4, 14, -4))
		var tw := comet.create_tween()
		tw.tween_property(comet, "global_position", pos + Vector3(0, 0.3, 0), 1.0).set_ease(Tween.EASE_IN)
		var self_ref := self
		m.after(1.0, func():
			comet.detach_and_fade()
			Vfx.burst(m, pos + Vector3(0, 0.4, 0), Color(0.65, 0.5, 1.0), 3.0)
			for e in m.enemies_in_radius(self_ref.owner.team, pos, 3.0):
				self_ref.proc(e, dmg, G.DmgType.MAGIC, "cruelty"))


class GlassCannon extends Augment:
	func _init() -> void:
		power = 0.5
		description = "Your health is capped at 70% of your maximum health. You deal bonus true damage equal to 25% (melee) / 15% (ranged) of all damage you deal."

	func on_tick(u, _dt: float) -> void:
		u.hp = minf(u.hp, u.stats.max_hp * 0.7)

	func on_damage_dealt(info) -> void:
		if info.no_hooks or info.target == null or info.target.dead or info.type == G.DmgType.TRUE and info.tag == "glass":
			return
		var pct := 0.25 if is_melee() else 0.15
		Combat.deal(owner, info.target, info.amount * info.mult * pct, G.DmgType.TRUE, {"is_proc": true, "no_hooks": true, "tag": "glass", "show_number": false})


class InfernalConduit extends Augment:
	var cds := {}

	func _init() -> void:
		power = 3.0
		description = "Ability hits on champions apply a stacking 3s Burn (2-20 (+4.6% bonus AD) (+2% AP) magic damage per second). Every Burn tick you deal reduces your basic ability cooldowns by 0.08s."

	func on_damage_dealt(info) -> void:
		if info.tag == "burn" and info.is_dot:
			for i in 3:
				var ab = owner.abilities[i]
				if ab != null:
					ab.reduce_cooldown(0.08)
		if not info.is_spell or info.is_dot or info.target == null or info.target.kind != G.Kind.CHAMPION:
			return
		var now_t: float = owner.match_ref.time
		if now_t - cds.get(info.target, -10.0) < 1.0:
			return
		cds[info.target] = now_t
		var t = info.target
		var per: float = lvl_lerp(2.0, 20.0) + 0.046 * owner.stats.bonus_ad + 0.02 * owner.stats.ap
		var b: Buff = t.find_buff("conduit_burn", owner)
		if b == null:
			b = Buff.new("conduit_burn", 3.0)
			b.display_name = "Burn"
			b.is_debuff = true
			b.tick_interval = 0.5
			b.max_stacks = 99
			b.stack_mode = Buff.Stack.INDEPENDENT
			var src = owner
			var bb := b
			b.on_interval = func(_x):
				if is_instance_valid(src) and not t.dead:
					Combat.deal(src, t, per * 0.5 * bb.stacks, G.DmgType.MAGIC, {"is_dot": true, "is_proc": true, "tag": "burn"})
			t.add_buff(b, owner)
			b.vfx = Vfx.rising(t, Color(1.0, 0.45, 0.15), 30.0, 16, 0.4)
		else:
			b.stacks += 1
			b.remaining = 3.0

	func synergy(c) -> float:
		return 1.5 if has_tag(c, "ability") else -1.0


class JeweledGauntlet extends Augment:
	func _init() -> void:
		power = 3.0
		description = "Your abilities can critically strike for 145% (+bonus crit damage). Gain 25% (+4.5% per 100 AP) critical strike chance."

	func get_stat_mods() -> Dictionary:
		return {"crit": 0.25 + 0.045 * (owner.stats.ap if owner != null else 0.0) / 100.0}

	func on_pre_damage_dealt(info) -> void:
		if info.is_spell:
			info.can_crit = true

	func synergy(c) -> float:
		return 1.5 if has_tag(c, "ability") else -1.0


class OminousPact extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Abilities cost 5% of your current health. Gain ability power (up to 75-150), movement speed (up to 50%) and omnivamp (up to 20%) based on missing health."

	func on_ability_cast(ab, _t) -> void:
		if not ab.is_summoner:
			owner.hp = maxf(1.0, owner.hp - owner.hp * 0.05)

	func on_tick(u, _dt: float) -> void:
		u.stats.mark_dirty()

	func get_stat_mods() -> Dictionary:
		if owner == null:
			return {}
		var missing := clampf((1.0 - owner.hp_ratio()) / 0.7, 0.0, 1.0)
		return {"ap": lvl_lerp(75.0, 150.0) * missing, "ms%": 0.5 * missing, "omnivamp": 0.2 * missing}

	func synergy(c) -> float:
		return 1.0 if has_tag(c, "ap") else -0.5


class IceCold extends Augment:
	func _init() -> void:
		power = 1.0
		description = "Your slowing effects reduce the target's movement speed by an additional 75."

	func on_cc_applied(target, buff) -> void:
		if buff.slow_amount > 0.0 and buff.id != "ice_cold":
			var b := Buff.new("ice_cold", buff.duration)
			b.display_name = "Ice Cold"
			b.is_debuff = true
			b.stats = {"ms": -75.0}
			target.add_buff(b, owner)


class Goldrend extends Augment:
	var cds := {}

	func _init() -> void:
		power = 2.5
		description = "Damaging an enemy champion deals 50-150 (+40% bonus AD) (+20% AP) bonus magic damage and grants 30 gold and 25% movement speed for 1.5s (30s cooldown per champion)."

	func on_damage_dealt(info) -> void:
		var t = info.target
		if t == null or t.kind != G.Kind.CHAMPION or info.tag == "goldrend" or info.is_dot:
			return
		var now_t: float = owner.match_ref.time
		if now_t - cds.get(t, -100.0) < 30.0:
			return
		cds[t] = now_t
		proc(t, lvl_lerp(50.0, 150.0) + 0.4 * owner.stats.bonus_ad + 0.2 * owner.stats.ap, G.DmgType.MAGIC, "goldrend")
		owner.add_gold(30.0, t)
		K.haste(owner, 0.25, 1.5, owner, false, "goldrend_ms")
		Vfx.burst(owner.match_ref, t.global_position + Vector3(0, 1.2, 0), G.COLOR_GOLD, 1.0, {"ring": false, "sparks": 24})
