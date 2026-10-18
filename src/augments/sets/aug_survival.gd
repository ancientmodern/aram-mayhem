extends RefCounted
## Tank, size, survival and death payoffs.


static func register(reg: Dictionary) -> void:
	reg["EscapePlan"] = func(): return EscapePlan.new()
	reg["MightyShield"] = func(): return MightyShield.new()
	reg["ARAM_MindtoMatter"] = func(): return MindToMatter.new()
	reg["SwiftAndSafe"] = func(): return SwiftAndSafe.new()
	reg["VeilOfWarding"] = func(): return VeilOfWarding.new()
	reg["ARAM_BigBrain"] = func(): return BigBrain.new()
	reg["ARAM_CelestialBody"] = func(): return CelestialBody.new()
	reg["ARAM_DawnbringersResolve"] = func(): return Dawnbringer.new()
	reg["ARAM_OutlawsGrit"] = func(): return OutlawsGrit.new()
	reg["PinCushion"] = func(): return Porcupine.new()
	reg["ARAM_ShrinkRay"] = func(): return ShrinkRay.new()
	reg["ARAM_CourageoftheColossus"] = func(): return CourageColossus.new()
	reg["ARAM_GiantSlayer"] = func(): return GiantSlayer.new()
	reg["ARAM_Goliath"] = func(): return Goliath.new()
	reg["ARAM_MadScientist"] = func(): return MadScientist.new()
	reg["ARAM_DiveBomber"] = func(): return DiveBomber.new()
	reg["FishBait"] = func(): return SharkBait.new()
	reg["ARAM_DropBear"] = func(): return DropBear.new()
	reg["ARAM_Hellbent"] = func(): return Hellbent.new()
	reg["DontChangeTheChannel"] = func(): return DontChangeChannel.new()


static func bonus_hp(u) -> float:
	return u.stats.max_hp - (u.stats.base.base_hp + Stats.growth(u.stats.base.hp_per_level, u.level))


class EscapePlan extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 2.0
		description = "Dropping below 35% health grants a decaying shield for 65% of your max health, 150% decaying movement speed and a smaller size for 5.5 seconds (75s cooldown)."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_damage_taken(_info) -> void:
		if cd > 0.0 or owner.dead or owner.hp_ratio() > 0.35:
			return
		cd = 75.0
		Combat.shield(owner, owner, owner.stats.max_hp * 0.65, 5.5, {"decay": true, "id": "escape_plan"})
		K.haste(owner, 1.5, 5.5, owner, true, "escape_ms")
		K.buff(owner, "escape_small", 5.5, {"size": -0.35}, owner, {"name": "Escape Plan"})
		Vfx.shield_bubble(owner, Color(0.7, 0.9, 1.0), 2.0, 1.0)


class MightyShield extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 1.5
		description = "Gaining a shield grants 40-100 adaptive force for 3 seconds (5s cooldown)."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_shield_received(_a: float) -> void:
		if cd > 0.0:
			return
		cd = 5.0
		K.buff(owner, "mighty_shield", 3.0, {"adaptive": lvl_lerp(40.0, 100.0)}, owner, {"name": "Mighty Shield"})


class MindToMatter extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Gain bonus health equal to 50% of your maximum mana."

	func fits(c) -> bool:
		return c.stats.uses_mana

	func get_stat_mods() -> Dictionary:
		return {"hp": owner.stats.max_mana * 0.5 if owner != null else 0.0}


class SwiftAndSafe extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 1.5
		description = "After dashing or blinking, gain a 2-second shield absorbing 65-290 (+65% AD) (+26% AP) damage (5s cooldown)."

	func fits(c) -> bool:
		return has_tag(c, "dash")

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_dash(_a: Vector3, _b: Vector3) -> void:
		if cd > 0.0:
			return
		cd = 5.0
		K.shield(owner, owner, lvl_lerp(65.0, 290.0) + 0.65 * owner.stats.ad + 0.26 * owner.stats.ap, 2.0, Color(0.6, 0.9, 1.0))


class VeilOfWarding extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 1.5
		description = "Gain a spell shield that blocks the next damaging enemy ability (30s cooldown)."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)
		counter_text = "" if cd > 0.0 else "●"

	func on_pre_damage_taken(info) -> void:
		if cd > 0.0 or not info.is_spell or info.source == null or info.source.kind != G.Kind.CHAMPION or info.is_dot:
			return
		cd = 30.0
		info.cancelled = true
		Vfx.shield_bubble(owner, Color(0.85, 0.5, 1.0), 0.5, 1.1)
		owner.match_ref.fx_text(owner, "Blocked", Color(0.85, 0.6, 1.0))


class BigBrain extends Augment:
	var timer := 0.0

	func _init() -> void:
		power = 2.5
		description = "Gain a shield equal to 300% of your ability power that lasts until destroyed. Refreshed on respawn and every 70 seconds."

	func on_acquire(_c) -> void:
		_refresh()

	func on_respawn() -> void:
		_refresh()

	func on_tick(_u, dt: float) -> void:
		timer += dt
		if timer >= 70.0:
			_refresh()

	func _refresh() -> void:
		timer = 0.0
		var amt: float = owner.stats.ap * 3.0
		if amt > 1.0:
			owner.add_shield(amt, 9999.0, owner, -1, false, "big_brain")
			Vfx.shield_bubble(owner, Color(0.8, 0.6, 1.0), 1.0, 1.1)

	func synergy(c) -> float:
		return 1.5 if has_tag(c, "ap") else -2.0


class CelestialBody extends Augment:
	func _init() -> void:
		power = 2.0
		stats = {"hp": 1500.0, "dmg_amp": -0.1}
		description = "Gain 1500 bonus health, but deal 10% less damage."

	func synergy(c) -> float:
		return 1.5 if has_tag(c, "tank") or has_tag(c, "melee") else -0.5


class Dawnbringer extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 2.0
		description = "Dropping below 50% health heals you for 30% of your max health over 3 seconds (45s cooldown, resets on death)."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_death(_k) -> void:
		cd = 0.0

	func on_damage_taken(_info) -> void:
		if cd > 0.0 or owner.dead or owner.hp_ratio() > 0.5:
			return
		cd = 45.0
		var b := Buff.new("dawnbringer", 3.0)
		b.display_name = "Dawnbringer's Resolve"
		b.tick_interval = 0.25
		var o = owner
		b.on_interval = func(_bb): Combat.heal(o, o, o.stats.max_hp * 0.3 / 12.0, {"show": false})
		owner.add_buff(b, owner)
		b.vfx = Vfx.rising(owner, Color(1.0, 0.9, 0.5), 3.0, 30)


class OutlawsGrit extends Augment:
	func _init() -> void:
		power = 1.5
		description = "Dashing or blinking grants 12 armor and magic resist for 15 seconds, stacking up to 5 times."

	func fits(c) -> bool:
		return has_tag(c, "dash")

	func on_dash(_a: Vector3, _b: Vector3) -> void:
		var b: Buff = owner.find_buff("outlaws_grit")
		if b == null:
			K.buff(owner, "outlaws_grit", 15.0, {}, owner, {"name": "Outlaw's Grit", "max_stacks": 5,
					"stack_mode": Buff.Stack.ADD_STACK, "per_stack": {"armor": 12.0, "mr": 12.0}})
		else:
			b.stacks = mini(5, b.stacks + 1)
			b.remaining = 15.0
			owner.stats.mark_dirty()


class Porcupine extends Augment:
	var stored := 0.0

	func _init() -> void:
		power = 2.0
		description = "Store damage taken from champions. When full (400-3900), burst needles around you dealing 75-200 (+125% bonus armor) (+125% bonus MR) physical damage and slowing by 30%."

	func cap() -> float:
		return lvl_lerp(400.0, 3900.0)

	func on_damage_taken(info) -> void:
		if info.source == null or info.source.kind != G.Kind.CHAMPION:
			return
		stored += info.amount
		counter_text = "%d%%" % int(clampf(stored / cap(), 0.0, 1.0) * 100.0)
		if stored >= cap():
			stored = 0.0
			counter_text = ""
			var m = owner.match_ref
			var dmg: float = lvl_lerp(75.0, 200.0) + 1.25 * owner.stats.bonus_armor + 1.25 * owner.stats.bonus_mr
			Vfx.burst(m, owner.global_position + Vector3(0, 1, 0), Color(0.85, 0.8, 0.6), 4.0, {"sparks": 60})
			for e in m.enemies_in_radius(owner.team, owner.global_position, 4.0):
				proc(e, dmg, G.DmgType.PHYSICAL, "porcupine")
				K.slow(e, 0.3, 2.0, owner)

	func synergy(c) -> float:
		return 1.5 if has_tag(c, "tank") else -0.5


class ShrinkRay extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Basic attacks reduce the target's damage dealt by 15% for 3 seconds and shrink them."

	func on_attack_hit(t, _info) -> void:
		if t.kind == G.Kind.CHAMPION or t.kind == G.Kind.MINION:
			K.buff(t, "shrink_ray", 3.0, {"dmg_amp": -0.15, "size": -0.3}, owner, {"name": "Shrink Ray", "debuff": true})


class CourageColossus extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 2.5
		description = "Immobilizing an enemy champion grants a 3-second shield absorbing 150-450 (+4% max health) damage (5s cooldown)."

	func fits(c) -> bool:
		return has_tag(c, "cc")

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_cc_applied(target, buff) -> void:
		if cd > 0.0 or target.kind != G.Kind.CHAMPION or (buff.cc & (Buff.IMMOBILIZE | Buff.CC.GROUNDED)) == 0:
			return
		cd = 5.0
		K.shield(owner, owner, lvl_lerp(150.0, 450.0) + 0.04 * owner.stats.max_hp, 3.0, Color(1.0, 0.8, 0.4))


class GiantSlayer extends Augment:
	func _init() -> void:
		power = 2.5
		stats = {"size": -0.6, "ms%": 0.2}
		description = "Become tiny (-60% size) and gain 20% movement speed. Deal 10-30% bonus damage to champions bigger than you."

	func on_pre_damage_dealt(info) -> void:
		var t = info.target
		if t == null or t.kind != G.Kind.CHAMPION:
			return
		var diff: float = t.stats.size - owner.stats.size
		if diff > 0.0:
			info.mult *= 1.0 + clampf(diff * 0.4, 0.1, 0.3)


class Goliath extends Augment:
	func _init() -> void:
		power = 3.0
		stats = {"hp%": 0.35, "ad%": 0.15, "ap%": 0.15, "size": 0.5}
		description = "Gain 35% bonus health, 15% increased attack damage and ability power, and 50% increased size."


class MadScientist extends Augment:
	var big := true

	func _init() -> void:
		power = 3.0
		description = "On acquisition and each respawn, become either huge (+30% damage stats, +20% health, +40% size) or tiny (70 ability haste, 40% movement speed, -40% size)."

	func on_acquire(_c) -> void:
		_roll()

	func on_respawn() -> void:
		_roll()

	func _roll() -> void:
		big = G.rng.randf() < 0.5
		if big:
			stats = {"ad%": 0.3, "ap%": 0.3, "hp%": 0.2, "size": 0.4}
			display_name = "Mad Scientist (Huge)"
		else:
			stats = {"ah": 70.0, "ms%": 0.4, "size": -0.4}
			display_name = "Mad Scientist (Tiny)"
		refresh_stats()


class DiveBomber extends Augment:
	func _init() -> void:
		power = 1.5
		description = "When you die, you explode, dealing true damage equal to 20% of each nearby enemy's maximum health."

	func on_death(_k) -> void:
		var m = owner.match_ref
		var pos: Vector3 = owner.global_position
		Vfx.burst(m, pos + Vector3(0, 0.8, 0), Color(1.0, 0.45, 0.2), 5.0, {"sparks": 80})
		if m.camera_rig != null and owner == G.player:
			m.camera_rig.shake(0.5)
		for e in m.enemies_in_radius(owner.team, pos, 5.0):
			Combat.deal(owner, e, e.stats.max_hp * 0.2, G.DmgType.TRUE, {"is_proc": true, "tag": "dive_bomber"})


class SharkBait extends Augment:
	var active := false
	var cd := 0.0

	func _init() -> void:
		power = 2.0
		description = "On fatal damage, become Shark Bait for 3.5 seconds (invulnerable, unstoppable, slowing nearby enemies). Then a giant shark erupts, dealing 120-350 (+30% of their missing health) magic damage and knocking up."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func prevent_death(_info) -> bool:
		if active or cd > 0.0:
			return false
		active = true
		cd = 60.0
		var o = owner
		var m = o.match_ref
		o.hp = 1.0
		var b := Buff.new("shark_bait", 3.5)
		b.display_name = "Shark Bait"
		b.cc = Buff.CC.INVULNERABLE | Buff.CC.UNSTOPPABLE | Buff.CC.GHOSTED | Buff.CC.DISARM | Buff.CC.SILENCE
		b.stats = {"ms": 400.0}
		b.cleansable = false
		o.add_buff(b, o)
		b.vfx = Vfx.aura(o, Color(0.3, 0.6, 1.0), 4.0, 3.5)
		var self_ref := self
		m.add_ticker(3.5, func(_dt):
			for e in m.enemies_in_radius(o.team, o.global_position, 4.0):
				K.slow(e, 0.4, 0.3, o, false, "shark_slow")
			return true)
		m.after(3.5, func():
			var pos: Vector3 = o.global_position
			Vfx.burst(m, pos + Vector3(0, 0.3, 0), Color(0.3, 0.55, 1.0), 4.0, {"sparks": 70})
			Vfx.ring(m, pos, Color(0.6, 0.8, 1.0), 4.0, 0.6)
			for e in m.enemies_in_radius(o.team, pos, 4.0):
				Combat.deal(o, e, self_ref.lvl_lerp(120.0, 350.0) + 0.3 * (e.stats.max_hp - e.hp), G.DmgType.MAGIC, {"is_proc": true, "tag": "shark"})
				K.knockup(e, 1.0, o)
			self_ref.active = false
			if not o.dead:
				o.hp = 0.0
				o.die(null, null))
		return true


class DropBear extends Augment:
	func _init() -> void:
		power = 2.5
		description = "When you die, Tibbers drops onto your corpse, dealing 250-750 (+100% AP) magic damage and stunning for 1.5s, then hunts your killer for 8-20 seconds with a burning aura."

	func on_death(killer) -> void:
		var o = owner
		var m = o.match_ref
		var pos: Vector3 = o.global_position
		var self_ref := self
		Vfx.ground_circle(m, pos, 3.0, Color(1.0, 0.4, 0.1, 0.8), 0.6, 0.3)
		m.after(0.5, func():
			Vfx.burst(m, pos + Vector3(0, 0.5, 0), Color(1.0, 0.45, 0.15), 3.5, {"sparks": 70})
			if m.camera_rig != null:
				m.camera_rig.shake(0.4 if o == G.player else 0.1)
			for e in m.enemies_in_radius(o.team, pos, 3.0):
				Combat.deal(o, e, self_ref.lvl_lerp(250.0, 750.0) + o.stats.ap, G.DmgType.MAGIC, {"is_proc": true, "tag": "dropbear"})
				K.stun(e, 1.5, o)
			var t := Summon.new()
			t.setup(o, "Tibbers", {"hp": 1500.0 + 100.0 * o.level, "ad": 60.0 + 4.0 * o.level, "armor": 50.0, "mr": 50.0,
				"as": 0.8, "range": 175.0, "ms": 380.0, "radius": 0.9, "height": 2.8, "model": "AnnieTibbers",
				"lifetime": self_ref.lvl_lerp(8.0, 20.0), "scale": 1.2})
			m.add_unit(t, pos)
			if killer != null and is_instance_valid(killer) and killer.kind == G.Kind.CHAMPION:
				t.controlled_target = killer
			t.leash = 30.0
			var acc := {"t": 0.0}
			m.add_ticker(t.lifetime, func(dt):
				if not is_instance_valid(t) or t.dead:
					return false
				acc.t += dt
				if acc.t >= 1.0:
					acc.t = 0.0
					for e in m.enemies_in_radius(t.team, t.global_position, 3.0):
						Combat.deal(t, e, self_ref.lvl_lerp(25.0, 150.0) + 0.5 * o.stats.ap, G.DmgType.MAGIC, {"is_proc": true, "is_dot": true, "tag": "burn"})
				return true))


class Hellbent extends Augment:
	var stacks := 0
	var timer := 0.0
	var cd := 0.0
	var reviving := false

	func _init() -> void:
		power = 3.0
		description = "Hitting champions builds stacks (6s, max 10). At max, lethal damage instead makes you invulnerable for 4 seconds and revives you with 35-75% health and 15 seconds of bonus damage, speed and omnivamp (90s cooldown)."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)
		if stacks > 0:
			timer -= dt
			if timer <= 0.0:
				stacks = 0
		counter_text = ("%d" % stacks) if cd <= 0.0 else ""

	func on_damage_dealt(info) -> void:
		if info.target != null and info.target.kind == G.Kind.CHAMPION and not info.is_dot:
			stacks = mini(10, stacks + 1)
			timer = 6.0

	func prevent_death(_info) -> bool:
		if stacks < 10 or cd > 0.0 or reviving:
			return false
		reviving = true
		cd = 90.0
		stacks = 0
		var o = owner
		var b := Buff.new("hellbent_revive", 4.0)
		b.display_name = "Hellbent"
		b.cc = Buff.CC.INVULNERABLE | Buff.CC.STASIS
		b.cleansable = false
		o.add_buff(b, o)
		o.hp = 1.0
		b.vfx = Vfx.aura(o, Color(1.0, 0.2, 0.15), 2.0, 4.0)
		var self_ref := self
		o.match_ref.after(4.0, func():
			self_ref.reviving = false
			if o.dead:
				return
			o.hp = o.stats.max_hp * self_ref.lvl_lerp(0.35, 0.75)
			var st := {"omnivamp": self_ref.lvl_lerp(0.15, 0.3), "ms": 40.0}
			if o.stats.bonus_ad >= o.stats.ap:
				st["ad"] = self_ref.lvl_lerp(15.0, 120.0)
			else:
				st["ap"] = self_ref.lvl_lerp(25.0, 200.0)
			K.buff(o, "hellbent", 15.0, st, o, {"name": "Hellbent"})
			Vfx.burst(o.match_ref, o.global_position + Vector3(0, 1, 0), Color(1.0, 0.25, 0.15), 3.0, {"sparks": 60}))
		return true


class DontChangeChannel extends Augment:
	var acc := 0.0

	func _init() -> void:
		power = 1.5
		description = "For every second you channel an ability, gain a 50-200 (+50% AD) (+25% AP) (+10% bonus health) shield that decays once you stop channeling."

	func fits(c) -> bool:
		return has_tag(c, "channel")

	func on_tick(u, dt: float) -> void:
		if u.channel.is_empty():
			return
		acc += dt
		if acc >= 1.0:
			acc = 0.0
			var amt: float = lvl_lerp(50.0, 200.0) + 0.5 * u.stats.ad + 0.25 * u.stats.ap + 0.1 * bonus_hp_of(u)
			Combat.shield(u, u, amt, 3.0, {"decay": true})

	func bonus_hp_of(u) -> float:
		return u.stats.max_hp - (u.stats.base.base_hp + Stats.growth(u.stats.base.hp_per_level, u.level))
