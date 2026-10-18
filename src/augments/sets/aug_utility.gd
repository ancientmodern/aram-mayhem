extends RefCounted
## Healing, shielding, team support and mobility.


static func register(reg: Dictionary) -> void:
	reg["ARAM_SonicBoom"] = func(): return SonicBoom.new()
	reg["ARAM_AllForYou"] = func(): return AllForYou.new()
	reg["ARAM_CriticalHealing"] = func(): return CriticalHealing.new()
	reg["NatureIsHealing"] = func(): return NatureIsHealing.new()
	reg["PatOnTheBack"] = func(): return PatOnTheBack.new()
	reg["ARAM_SearingDawn"] = func(): return SearingDawn.new()
	reg["ARAM_CircleofDeath"] = func(): return CircleOfDeath.new()
	reg["ARAM_SpiritBomb"] = func(): return SpiritBomb.new()
	reg["ARAM_WindspeakersBlessing"] = func(): return Windspeaker.new()
	reg["ARAM_Homeguard"] = func(): return Homeguard.new()
	reg["KillSecured"] = func(): return KillSecured.new()
	reg["ARAM_LegDay"] = func(): return LegDay.new()
	reg["ARAM_ShadowRunner"] = func(): return ShadowRunner.new()
	reg["ARAM_GetExcited"] = func(): return GetExcited.new()
	reg["Nightstalking"] = func(): return Nightstalking.new()
	reg["ARAM_WithHaste"] = func(): return WithHaste.new()
	reg["ARAM_Earthwake"] = func(): return Earthwake.new()
	reg["SupportMain"] = func(): return SupportMain.new()


class SonicBoom extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 1.5
		description = "Healing, shielding or buffing an ally deals 30-150 true damage to enemies within 450 units of them and slows them by 30% for 2 seconds (2s cooldown)."

	func fits(c) -> bool:
		return Augment.is_support(c)

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func _boom(t) -> void:
		if cd > 0.0 or t == owner:
			return
		cd = 2.0
		var m = owner.match_ref
		Vfx.ring(m, t.global_position, Color(0.7, 0.9, 1.0), 4.5, 0.4)
		for e in m.enemies_in_radius(owner.team, t.global_position, 4.5):
			proc(e, lvl_lerp(30.0, 150.0), G.DmgType.TRUE, "sonic_boom")
			K.slow(e, 0.3, 2.0, owner)

	func on_heal_dealt(t, _a: float) -> void:
		_boom(t)

	func on_shield_dealt(t, _a: float) -> void:
		_boom(t)


class AllForYou extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Your heals and shields on allied champions are 30% stronger."

	func fits(c) -> bool:
		return Augment.is_support(c)

	func modify_heal_shield_dealt(amount: float, t, _s: bool) -> float:
		return amount * 1.3 if t != owner else amount


class CriticalHealing extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 2.0
		stats = {"crit": 0.25}
		description = "Your heals and shields have a chance equal to your crit chance to be 40% stronger. Gain 25% crit chance."

	func fits(c) -> bool:
		return Augment.is_support(c)

	func modify_heal_shield_dealt(amount: float, _t, _s: bool) -> float:
		if G.rng.randf() < owner.stats.crit_chance:
			return amount * 1.4
		return amount


class NatureIsHealing extends Augment:
	var cds := {}
	var last := 0

	func _init() -> void:
		power = 1.0
		description = "Entering brush heals you for 40-300 (+15% missing health) over 1.5 seconds (20s cooldown per brush)."

	func on_tick(u, _dt: float) -> void:
		var b: int = u.in_brush
		if b > 0 and b != last:
			var now_t: float = u.match_ref.time
			if now_t - cds.get(b, -100.0) >= 20.0:
				cds[b] = now_t
				var amt: float = lvl_lerp(40.0, 300.0) + 0.15 * (u.stats.max_hp - u.hp)
				var hb := Buff.new("nature_heal", 1.5)
				hb.display_name = "Nature is Healing"
				hb.tick_interval = 0.25
				hb.on_interval = func(_x): Combat.heal(u, u, amt / 6.0, {"show": false})
				u.add_buff(hb, u)
				Vfx.rising(u, Color(0.4, 1.0, 0.5), 1.5, 25)
		last = b


class PatOnTheBack extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 2.0
		description = "Being near an allied champion grants you a 50-150 (+25% bonus movement speed) shield and 30% movement speed for 3 seconds (9s cooldown)."

	func on_tick(u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)
		if cd > 0.0 or u.dead:
			return
		for a in u.match_ref.allies_in_radius(u.team, u.global_position, 2.0):
			if a != u:
				cd = 9.0
				K.shield(u, u, lvl_lerp(50.0, 150.0) + 0.25 * u.stats.move_speed * 0.3, 3.0, Color(0.9, 0.9, 0.6))
				K.haste(u, 0.3, 3.0, u, false, "pat_ms")
				return


class SearingDawn extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Your damaging abilities mark enemies with Sunlight. Your allies' next hit on them deals 40-200 bonus magic damage."

	func on_damage_dealt(info) -> void:
		if info.is_spell and info.target != null and info.target.kind == G.Kind.CHAMPION and not info.target.dead:
			var b := Buff.new("searing_sun", 3.0)
			b.display_name = "Sunlight"
			b.is_debuff = true
			b.set_meta("src", owner)
			b.set_meta("dmg", lvl_lerp(40.0, 200.0))
			info.target.add_buff(b, owner)
			if info.target.find_effect("searing_detonator") == null:
				var det := Detonator.new()
				info.target.add_effect(det)


## Lives on marked enemies: an ally's damage detonates the mark.
class Detonator extends Effect:
	func _init() -> void:
		id = "searing_detonator"
		hidden = true

	func on_damage_taken(info) -> void:
		var b: Buff = owner.find_buff("searing_sun")
		if b == null or info.source == null or info.tag == "searing":
			return
		var src = b.get_meta("src")
		if src == null or not is_instance_valid(src) or info.source == src or info.source.team != src.team:
			return
		owner.remove_buff(b)
		Combat.deal(src, owner, float(b.get_meta("dmg")), G.DmgType.MAGIC, {"is_proc": true, "tag": "searing"})
		Vfx.burst(owner.match_ref, owner.global_position + Vector3(0, 1, 0), Color(1.0, 0.85, 0.35), 1.2, {"ring": false})


class CircleOfDeath extends Augment:
	var bank := 0.0

	func _init() -> void:
		power = 2.5
		description = "Healing and health regeneration you do deals 70% of that amount as magic damage to the nearest enemy champion within 1000 units."

	func on_tick(u, dt: float) -> void:
		if u.hp < u.stats.max_hp:
			bank += u.stats.hp_regen * dt
		if bank >= 15.0:
			_fire(bank)
			bank = 0.0

	func on_heal_dealt(_t, amount: float) -> void:
		bank += amount

	func _fire(amount: float) -> void:
		var best = null
		var bd := 10.5
		for e in owner.match_ref.enemies_in_radius(owner.team, owner.global_position, 10.0, true):
			var d: float = G.flat_dist(e.global_position, owner.global_position)
			if d < bd:
				bd = d
				best = e
		if best == null:
			return
		var from: Vector3 = owner.global_position + Vector3(0, 1.2, 0)
		var mi := Missile.new()
		mi.setup_homing(owner, from, best, 16.0)
		mi.visual = Vfx.orb(Color(0.3, 1.0, 0.5), 0.35, false)
		var self_ref := self
		var dmg := amount * 0.7
		mi.on_hit = func(_m, u): self_ref.proc(u, dmg, G.DmgType.MAGIC, "circle_of_death")
		owner.match_ref.add_missile(mi, from)


class SpiritBomb extends Augment:
	var charge := 0.0

	func _init() -> void:
		power = 2.5
		description = "Your healing and shielding charges a Spirit Bomb. When charged (200-2000), it is thrown at the most wounded ally, healing 5-15% (+3% per 100 AP) missing health and shielding allies in a large area."

	func fits(c) -> bool:
		return Augment.is_support(c)

	func _need() -> float:
		return lvl_lerp(200.0, 2000.0)

	func on_heal_dealt(_t, a: float) -> void:
		_add(a)

	func on_shield_dealt(_t, a: float) -> void:
		_add(a)

	func _add(a: float) -> void:
		charge += a
		counter_text = "%d%%" % int(clampf(charge / _need(), 0.0, 1.0) * 100.0)
		if charge >= _need():
			charge = 0.0
			counter_text = ""
			var m = owner.match_ref
			var best = owner
			for al in m.allies_in_radius(owner.team, owner.global_position, 12.0):
				if al.hp_ratio() < best.hp_ratio():
					best = al
			var pos: Vector3 = best.global_position
			Vfx.burst(m, pos + Vector3(0, 1, 0), Color(0.5, 0.9, 1.0), 4.75, {"sparks": 50})
			for al in m.allies_in_radius(owner.team, pos, 4.75):
				var pct: float = lvl_lerp(0.05, 0.15) + 0.03 * owner.stats.ap / 100.0
				Combat.heal(owner, al, (al.stats.max_hp - al.hp) * pct)
				Combat.shield(owner, al, al.hp * lvl_lerp(0.1, 0.25), 2.0)


class Windspeaker extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Heals and shields you give (or receive) grant the target 30-60 armor and magic resist for 3 seconds."

	func fits(c) -> bool:
		return Augment.is_support(c)

	func on_heal_dealt(t, _a: float) -> void:
		_bless(t)

	func on_shield_dealt(t, _a: float) -> void:
		_bless(t)

	func _bless(t) -> void:
		var v: float = lvl_lerp(30.0, 60.0)
		K.buff(t, "windspeaker", 3.0, {"armor": v, "mr": v}, owner, {"name": "Windspeaker's Blessing"})


class Homeguard extends Augment:
	var lock := 0.0

	func _init() -> void:
		power = 1.0
		description = "Gain 100% bonus movement speed. This bonus is lost for 6 seconds after taking damage."

	func on_damage_taken(info) -> void:
		if info.final + info.absorbed > 0.0:
			lock = 6.0
			refresh_stats()

	func on_tick(u, dt: float) -> void:
		if lock > 0.0:
			lock -= dt
			if lock <= 0.0:
				u.stats.mark_dirty()

	func get_stat_mods() -> Dictionary:
		return {"ms%": 1.0} if lock <= 0.0 else {}


class KillSecured extends Augment:
	func _init() -> void:
		power = 1.0
		description = "Gain 60% bonus movement speed towards enemy champions below 40% health."

	func on_tick(u, _dt: float) -> void:
		u.stats.mark_dirty()

	func get_stat_mods() -> Dictionary:
		if owner == null or not owner.moving:
			return {}
		var t = owner.attack_target
		if t != null and is_instance_valid(t) and t.kind == G.Kind.CHAMPION and t.hp_ratio() < 0.4:
			return {"ms%": 0.6}
		return {}


class LegDay extends Augment:
	func _init() -> void:
		power = 1.5
		stats = {"ms": 50.0, "slow_resist": 0.5}
		description = "Gain 50 bonus movement speed and 50% slow resist."


class ShadowRunner extends Augment:
	func _init() -> void:
		power = 1.5
		description = "After dashing or blinking, gain 300 bonus movement speed for 2 seconds."

	func fits(c) -> bool:
		return has_tag(c, "dash")

	func on_dash(_a: Vector3, _b: Vector3) -> void:
		K.buff(owner, "shadow_runner", 2.0, {"ms": 300.0}, owner, {"name": "Shadow Runner"})


class GetExcited extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Champion takedowns grant 100% movement speed and 15% attack speed for 4 seconds."

	func on_takedown(_v) -> void:
		K.haste(owner, 1.0, 4.0, owner, true, "excited_ms")
		K.buff(owner, "excited_as", 4.0, {"as": 0.15}, owner, {"name": "Get Excited!"})
		Vfx.rising(owner, Color(1.0, 0.4, 0.7), 1.0, 30)


class Nightstalking extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Champion takedowns make you invisible for 1.5 seconds and grant 40% movement speed. Attacking or casting ends the stealth."

	func on_takedown(_v) -> void:
		var b := K.buff(owner, "nightstalk", 1.5, {"ms%": 0.4}, owner, {"name": "Nightstalking", "cc": Buff.CC.CAMOUFLAGE})
		_set_stealth(0.6)
		var self_ref := self
		owner.match_ref.after(1.5, func(): self_ref._set_stealth(0.0))

	func _set_stealth(v: float) -> void:
		if owner.model != null:
			_rec(owner.model, v)

	func _rec(n: Node, v: float) -> void:
		if n is GeometryInstance3D:
			(n as GeometryInstance3D).set_instance_shader_parameter("stealth", v)
		for c in n.get_children():
			_rec(c, v)

	func _break() -> void:
		var b: Buff = owner.find_buff("nightstalk")
		if b != null:
			owner.remove_buff(b)
			_set_stealth(0.0)

	func on_attack_launch(_t) -> void:
		_break()

	func on_ability_cast(_ab, _t) -> void:
		_break()


class WithHaste extends Augment:
	func _init() -> void:
		power = 1.5
		description = "Gain bonus movement speed equal to 70% of your ability haste."

	func get_stat_mods() -> Dictionary:
		return {"ms": 0.7 * (owner.stats.ability_haste if owner != null else 0.0)}


class Earthwake extends Augment:
	var hit_cd := {}

	func _init() -> void:
		power = 3.0
		description = "Dashes and blinks leave a trail that erupts after 0.75 seconds, dealing 90-250 (+125% bonus AD) (+60% AP) physical damage to enemies along it."

	func fits(c) -> bool:
		return has_tag(c, "dash")

	func on_dash(a: Vector3, b: Vector3) -> void:
		var m = owner.match_ref
		var dmg: float = lvl_lerp(90.0, 250.0) + 1.25 * owner.stats.bonus_ad + 0.6 * owner.stats.ap
		var n := maxi(2, int(G.flat_dist(a, b) / 1.5))
		for i in n + 1:
			var p: Vector3 = a.lerp(b, float(i) / n)
			Vfx.ground_circle(m, p, 1.5, Color(0.9, 0.55, 0.2, 0.7), 0.8, 0.25)
		var self_ref := self
		m.after(0.75, func():
			var hit := {}
			for i in n + 1:
				var p: Vector3 = a.lerp(b, float(i) / n)
				Vfx.burst(m, p, Color(0.95, 0.6, 0.25), 1.5, {"sparks": 10, "light": false})
				for e in m.enemies_in_radius(self_ref.owner.team, p, 3.0):
					if not hit.has(e):
						hit[e] = true
						self_ref.proc(e, dmg * (0.7 if e.kind == G.Kind.MINION else 1.0), G.DmgType.PHYSICAL, "earthwake"))


class SupportMain extends Augment:
	var healed := 0.0

	func _init() -> void:
		power = 1.5
		description = "QUEST: heal allied champions for 3000. REWARD: every heal you give also grants a heal-over-time worth 25% of it over 3 seconds."

	func fits(c) -> bool:
		return has_tag(c, "heal")

	func on_heal_dealt(t, amount: float) -> void:
		if t == owner:
			return
		if healed < 3000.0:
			healed += amount
			counter_text = "%d%%" % int(minf(100.0, healed / 30.0))
			if healed >= 3000.0:
				counter_text = "✔"
			return
		var hb := Buff.new("support_main_hot", 3.0)
		hb.display_name = "Support Main"
		hb.tick_interval = 0.5
		var o = owner
		hb.on_interval = func(_x): Combat.heal(null, t, amount * 0.25 / 6.0, {"show": false})
		t.add_buff(hb, o)
