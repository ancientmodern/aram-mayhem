extends RefCounted
## Dragon souls and summoner-spell replacers.


static func register(reg: Dictionary) -> void:
	reg["ARAM_InfernalSoul"] = func(): return InfernalSoul.new()
	reg["ARAM_MountainSoul"] = func(): return MountainSoul.new()
	reg["ARAM_OceanSoul"] = func(): return OceanSoul.new()
	reg["HextechSoul"] = func(): return HextechSoul.new()
	reg["ARAM_OmniSoul"] = func(): return OmniSoul.new()
	reg["Flash2"] = func(): return Flash2.new()
	reg["ARAM_Flashbang"] = func(): return Flashbang.new()
	reg["ARAM_Flashy"] = func(): return Flashy.new()
	reg["Poltergeist"] = func(): return PoltergeistAug.new()
	reg["GrowthSpurt"] = func(): return GrowthSpurtAug.new()
	reg["ARAM_BladeWaltz"] = func(): return BladeWaltzAug.new()
	reg["EmpyreanPromise"] = func(): return EmpyreanAug.new()
	reg["ARAM_Minionmancer"] = func(): return Minionmancer.new()


class InfernalSoul extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 2.0
		description = "Infernal Dragon Soul: every 3 seconds, your next attack or ability on a champion explodes, dealing 80 (+22.5% bonus AD) (+13.5% AP) (+2.75% bonus health) adaptive damage around them."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_damage_dealt(info) -> void:
		if cd > 0.0 or info.tag == "infernal" or info.target == null or info.target.kind != G.Kind.CHAMPION or info.is_dot:
			return
		cd = 3.0
		var o = owner
		var bhp: float = o.stats.max_hp - (o.stats.base.base_hp + Stats.growth(o.stats.base.hp_per_level, o.level))
		var dmg: float = 80.0 + 0.225 * o.stats.bonus_ad + 0.135 * o.stats.ap + 0.0275 * bhp
		var pos: Vector3 = info.target.global_position
		Vfx.burst(o.match_ref, pos + Vector3(0, 0.8, 0), Color(1.0, 0.4, 0.1), 2.0, {"sparks": 24})
		for e in o.match_ref.enemies_in_radius(o.team, pos, 2.0):
			proc(e, dmg, adaptive_type(), "infernal")


class MountainSoul extends Augment:
	var out_of_combat := 0.0
	var ready := true

	func _init() -> void:
		power = 2.0
		description = "Mountain Dragon Soul: after 5 seconds without taking damage, gain a shield absorbing 180 (+18% bonus AD) (+13.5% AP) (+15% bonus health) damage."

	func on_damage_taken(_info) -> void:
		out_of_combat = 0.0

	func on_tick(u, dt: float) -> void:
		out_of_combat += dt
		if out_of_combat >= 5.0 and u.total_shield() < 1.0:
			out_of_combat = 0.0
			var bhp: float = u.stats.max_hp - (u.stats.base.base_hp + Stats.growth(u.stats.base.hp_per_level, u.level))
			var amt: float = 180.0 + 0.18 * u.stats.bonus_ad + 0.135 * u.stats.ap + 0.15 * bhp
			u.add_shield(amt, 9999.0, u, -1, false, "mountain_soul")


class OceanSoul extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 1.5
		description = "Ocean Dragon Soul: damaging champions restores 100 (+20% bonus AD) (+12% AP) (+2% bonus health) health over 3 seconds (2s cooldown)."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_damage_dealt(info) -> void:
		if cd > 0.0 or info.target == null or info.target.kind != G.Kind.CHAMPION:
			return
		cd = 2.0
		var o = owner
		var bhp: float = o.stats.max_hp - (o.stats.base.base_hp + Stats.growth(o.stats.base.hp_per_level, o.level))
		var amt: float = 100.0 + 0.2 * o.stats.bonus_ad + 0.12 * o.stats.ap + 0.02 * bhp
		var hb := Buff.new("ocean_soul", 3.0)
		hb.display_name = "Ocean Soul"
		hb.tick_interval = 0.5
		hb.on_interval = func(_x):
			Combat.heal(o, o, amt / 6.0, {"show": false})
			o.mana = minf(o.stats.max_mana, o.mana + amt / 18.0)
		o.add_buff(hb, o)


class HextechSoul extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 1.5
		description = "Hextech Dragon Soul: every 2.5 seconds, damaging a champion triggers a chain lightning that deals 25-50 (+15% bonus AD) (+10% AP) magic damage and slows by 99% for 0.25s, bouncing to 3 enemies."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_damage_dealt(info) -> void:
		if cd > 0.0 or info.tag == "hextech" or info.target == null or info.target.kind != G.Kind.CHAMPION:
			return
		cd = 2.5
		var o = owner
		var m = o.match_ref
		var dmg: float = lvl_lerp(25.0, 50.0) + 0.15 * o.stats.bonus_ad + 0.1 * o.stats.ap
		var cur = info.target
		var hit := {}
		var prev_pos: Vector3 = o.global_position + Vector3(0, 1.2, 0)
		for i in 4:
			if cur == null:
				break
			hit[cur] = true
			Vfx.beam(m, prev_pos, cur.global_position + Vector3(0, 1.0, 0), Color(0.5, 0.85, 1.0), 0.08, 0.2)
			proc(cur, dmg, G.DmgType.MAGIC, "hextech")
			K.slow(cur, 0.99, 0.25, o)
			prev_pos = cur.global_position + Vector3(0, 1.0, 0)
			var nxt = null
			var bd := 5.0
			for e in m.enemies_in_radius(o.team, cur.global_position, 5.0):
				if not hit.has(e):
					var d: float = G.flat_dist(e.global_position, cur.global_position)
					if d < bd:
						bd = d
						nxt = e
			cur = nxt


class OmniSoul extends Augment:
	var souls: Array = []

	func _init() -> void:
		power = 3.0
		description = "Gain 3 random Dragon Souls."

	func on_acquire(c) -> void:
		var all := ["ARAM_InfernalSoul", "ARAM_MountainSoul", "ARAM_OceanSoul", "HextechSoul"]
		all.shuffle()
		var names := []
		for i in 3:
			var a := AugmentDB.create(all[i])
			if a != null:
				a.hidden = true
				c.add_effect(a)
				names.append(a.display_name)
		description = "Dragon Souls: " + ", ".join(names)


class Flash2 extends Augment:
	func _init() -> void:
		power = 0.5
		stats = {"summoner_haste": 70.0}
		description = "Replace a summoner spell with Flash and gain 70 summoner spell haste."

	func on_acquire(c) -> void:
		var has := false
		for s in c.summoners:
			if s != null and s.id == "Flash":
				has = true
		if not has:
			Summoners.set_spell(c, 0, "Flash")
		elif c.summoners[1] == null or c.summoners[1].id != "Flash":
			Summoners.set_spell(c, 1 if c.summoners[0].id == "Flash" else 0, "Flash")


class Flashbang extends Augment:
	func _init() -> void:
		power = 1.5
		description = "Your Flash causes an explosion at the destination dealing 70-240 (+70% AD) (+60% AP) magic damage and slowing by 35%. Flash's cooldown resets when you die. (Grants Flash.)"

	func on_acquire(c) -> void:
		var has := false
		for s in c.summoners:
			if s != null and s.id == "Flash":
				has = true
		if not has:
			Summoners.set_spell(c, 0, "Flash")

	func on_summoner_cast(spell) -> void:
		if spell.id != "Flash":
			return
		var o = owner
		var m = o.match_ref
		var pos: Vector3 = o.global_position
		var self_ref := self
		m.after(0.05, func():
			Vfx.burst(m, o.global_position + Vector3(0, 0.6, 0), Color(1.0, 0.85, 0.4), 2.75, {"sparks": 30})
			for e in m.enemies_in_radius(o.team, o.global_position, 2.75):
				self_ref.proc(e, self_ref.lvl_lerp(70.0, 240.0) + 0.7 * o.stats.ad + 0.6 * o.stats.ap, G.DmgType.MAGIC, "flashbang")
				K.slow(e, 0.35, 1.25, o))

	func on_death(_k) -> void:
		for s in owner.summoners:
			if s != null and s.id == "Flash":
				s.cd = 0.0


class Flashy extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Your Flash has 3 charges with a 2-second cooldown between casts. (Grants Flash.)"

	func on_acquire(c) -> void:
		var fl = null
		for s in c.summoners:
			if s != null and s.id == "Flash":
				fl = s
		if fl == null:
			Summoners.set_spell(c, 0, "Flash")
			fl = c.summoners[0]
		fl.max_charges = 3
		fl.charges = 3
		fl.charge_cd = 40.0


class PoltergeistAug extends Augment:
	func _init() -> void:
		power = 1.5
		description = "Replace a summoner spell with Poltergeist (68s cooldown): cast Barrier and Ghost at the same time."

	func on_acquire(c) -> void:
		var sp := PoltergeistSpell.new(c)
		_install(c, sp, "Poltergeist", "ghost")

	func _install(c, sp: Ability, sid: String, icon_name: String) -> void:
		sp.is_summoner = true
		sp.level = 1
		sp.max_level = 1
		sp.id = sid
		sp.anim = ""
		sp.icon = icon if icon != null else Assets.summoner_icon(icon_name)
		var slot := 0
		if c.summoners[0] != null and c.summoners[0].id == "Flash":
			slot = 1
		sp.slot = 5 + slot
		sp.key = "D" if slot == 0 else "F"
		c.summoners[slot] = sp


class PoltergeistSpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Poltergeist"
		description = "Cast Barrier and Ghost together."
		cooldowns = [68.0]
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0

	func execute(t: Dictionary) -> void:
		var amt: float = 105.0 + 18.0 * (owner.level - 1)
		Combat.shield(owner, owner, amt, 2.5)
		Vfx.shield_bubble(owner, Color(0.9, 0.85, 1.0), 2.5, 1.1)
		K.buff(owner, "poltergeist", 5.0, {"ms%": 0.3}, owner, {"name": "Poltergeist", "cc": Buff.CC.GHOSTED})
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		return {"pos": owner.global_position} if ctx.in_danger() and owner.hp_ratio() < 0.35 else {}


class GrowthSpurtAug extends PoltergeistAug:
	func _init() -> void:
		power = 2.0
		description = "Replace a summoner spell with Growth Spurt (76.5s cooldown): instantly grow 50% larger, knock up and back nearby enemies and gain 300 bonus health for 7 seconds."

	func on_acquire(c) -> void:
		_install(c, GrowthSpurtSpell.new(c), "GrowthSpurt", "fortify")


class GrowthSpurtSpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Growth Spurt"
		description = "Grow, knock enemies back and gain health."
		cooldowns = [76.5]
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0
		ind_radius = 400.0

	func execute(t: Dictionary) -> void:
		var o = owner
		K.buff(o, "growth_spurt", 7.0, {"size": 0.5, "hp": 300.0 + 20.0 * o.level}, o, {"name": "Growth Spurt"})
		Vfx.ring(o.match_ref, o.global_position, Color(0.6, 1.0, 0.5), 4.0, 0.4, 0.2, 0.2)
		for e in o.match_ref.enemies_in_radius(o.team, o.global_position, 4.0):
			e.knockback(o.global_position, 2.75, 1.0, o)
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		return {"pos": owner.global_position} if ctx.count_enemies_near(owner.global_position, 3.5) >= 2 or (ctx.in_danger() and ctx.count_enemies_near(owner.global_position, 3.0) >= 1) else {}


class BladeWaltzAug extends PoltergeistAug:
	func _init() -> void:
		power = 3.0
		description = "Replace a summoner spell with Blade Waltz (45s cooldown): blink between nearby enemy champions 8 times over 1.75 seconds while untargetable, each strike dealing 30-150 (+10% bonus AD) (+6% AP) physical damage and applying on-hit."

	func on_acquire(c) -> void:
		_install(c, BladeWaltzSpell.new(c), "BladeWaltz", "flash")


class BladeWaltzSpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Blade Waltz"
		description = "Dance between enemy champions, striking each."
		cooldowns = [45.0]
		target_type = Target.UNIT
		target_side = Side.ENEMY
		target_champions_only = true
		indicator = Ind.NONE
		cast_range = 500.0
		cast_time = 0.0

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var primary = t.unit
		o.untargetable_count += 1
		var dmg: float = lerpf(30.0, 150.0, (o.level - 1) / 17.0) + 0.1 * o.stats.bonus_ad + 0.06 * o.stats.ap
		var state := {"n": 0, "acc": 0.0, "cur": primary}
		var self_ref := self
		m.add_ticker(2.0, func(dt):
			state.acc += dt
			if state.acc < 0.22:
				return true
			state.acc = 0.0
			state.n += 1
			var tgt = state.cur
			if tgt == null or not is_instance_valid(tgt) or tgt.dead:
				tgt = null
				for e in m.enemies_in_radius(o.team, o.global_position, 6.0, true):
					tgt = e
					break
			if tgt == null or state.n > 8:
				o.untargetable_count = maxi(0, o.untargetable_count - 1)
				return false
			var from: Vector3 = o.global_position
			o.teleport(tgt.global_position + G.flat_dir(tgt.global_position, from) * 1.0)
			o.face_toward(tgt.global_position, 100.0)
			Vfx.beam(m, from + Vector3(0, 1, 0), o.global_position + Vector3(0, 1, 0), Color(0.9, 0.9, 1.0), 0.1, 0.15)
			var inf := Combat.deal(o, tgt, dmg, G.DmgType.PHYSICAL, {"is_proc": true, "tag": "blade_waltz"})
			o.trigger_on_hit(tgt, inf, 0.5)
			Vfx.hit_spark(m, tgt.global_position + Vector3(0, 1, 0), Color(1, 1, 1), 0.8)
			# next target: a different nearby champion if possible
			var nxt = tgt
			for e in m.enemies_in_radius(o.team, tgt.global_position, 6.0, true):
				if e != tgt:
					nxt = e
					break
			state.cur = primary if state.n >= 7 else nxt
			return true)
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var e: Unit = ctx.best_enemy_in_range(5.0)
		if e != null and ctx.mode == "fight":
			return {"unit": e, "pos": e.global_position}
		return {}


class EmpyreanAug extends PoltergeistAug:
	func _init() -> void:
		power = 2.0
		stats = {"heal_power": 0.15}
		description = "Replace a summoner spell with Vigilance (20s cooldown): dash to an allied champion and shield you both for 100-250 (+100% AP) (+10% bonus health). Gain 15% heal and shield power."

	func fits(c) -> bool:
		return true

	func on_acquire(c) -> void:
		_install(c, VigilanceSpell.new(c), "Vigilance", "barrier")


class VigilanceSpell extends Ability:
	func _init(p_owner) -> void:
		super._init(p_owner)
		display_name = "Vigilance"
		description = "Dash to an ally and shield you both."
		cooldowns = [20.0]
		target_type = Target.UNIT
		target_side = Side.ALLY
		self_cast_ok = false
		indicator = Ind.NONE
		cast_range = 2000.0
		cast_time = 0.25

	func execute(t: Dictionary) -> void:
		var o = owner
		var ally = t.unit
		if ally == null or not is_instance_valid(ally):
			return
		var amt: float = lerpf(100.0, 250.0, (o.level - 1) / 17.0) + o.stats.ap
		o.start_dash(ally.global_position + G.flat_dir(ally.global_position, o.global_position) * 1.0, {"speed": 25.0,
			"on_arrive": func(_u):
				K.shield(o, o, amt, 3.0, Color(1.0, 0.9, 0.6))
				K.shield(o, ally, amt, 3.0, Color(1.0, 0.9, 0.6))})
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		for a in ctx.allies:
			if a.hp_ratio() < 0.4 and ctx.count_enemies_near(a.global_position, 6.0) > 0:
				return {"unit": a, "pos": a.global_position}
		return {}


class Minionmancer extends Augment:
	func _init() -> void:
		power = 1.5
		description = "Your pets deal 40% increased damage and gain 40% bonus health and size."

	func fits(c) -> bool:
		return has_tag(c, "pet")

	func on_tick(u, _dt: float) -> void:
		for s in u.match_ref.units:
			if s.kind == G.Kind.SUMMON and s.get("summoner") == u and not s.has_meta("minionmancer"):
				s.set_meta("minionmancer", true)
				var b := Buff.new("minionmancer", 9999.0)
				b.permanent = true
				b.hidden = true
				b.stats = {"hp%": 0.4, "dmg_amp": 0.4, "size": 0.4}
				s.add_buff(b, u)
				s.hp = s.stats.max_hp
