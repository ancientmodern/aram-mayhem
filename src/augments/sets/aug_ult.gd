extends RefCounted
## Cooldown manipulation, ultimate empowerment and ability augments.


static func register(reg: Dictionary) -> void:
	reg["ARAM_UltimateUnstoppable"] = func(): return UltimateUnstoppable.new()
	reg["ARAM_ItsKillingTime"] = func(): return ItsKillingTime.new()
	reg["ARAM_SkilledSniper"] = func(): return SkilledSniper.new()
	reg["ARAM_Archmage"] = func(): return Archmage.new()
	reg["ARAM_BacktoBasics"] = func(): return BackToBasics.new()
	reg["ARAM_CantTouchThis"] = func(): return CantTouchThis.new()
	reg["ARAM_Dashing"] = func(): return Dashing.new()
	reg["ARAM_FeyMagic"] = func(): return FeyMagic.new()
	reg["FinalForm"] = func(): return FinalForm.new()
	reg["ARAM_MysticPunch"] = func(): return MysticPunch.new()
	reg["ARAM_StuckInHereWithMe"] = func(): return StuckInHere.new()
	reg["SurgeField"] = func(): return SurgeField.new()
	reg["SkipTheBasics"] = func(): return UltBot.new()
	reg["UltimateAwakening"] = func(): return UltimateAwakening.new()
	reg["ARAM_UltimateRevolution"] = func(): return UltimateRevolution.new()
	reg["Overloaded"] = func(): return Overloaded.new()
	reg["ARAM_BreadAndButter"] = func(): return Bread.make(0, "Your Q gains 100 ability haste.")
	reg["ARAM_BreadAndJam"] = func(): return Bread.make(1, "Your W gains 100 ability haste.")
	reg["ARAM_BreadAndCheese"] = func(): return Bread.make(2, "Your E gains 100 ability haste.")
	reg["SpecializedEmpowerment"] = func(): return PursuitOfPower.new()
	reg["ARAM_SpecializedRecursion"] = func(): return PursuitOfHaste.new()
	reg["ARAM_Quickstep"] = func(): return Quickstep.new()
	reg["ARAM_RabbleRousing"] = func(): return Rejuvenation.new()
	reg["ARAM_Terror"] = func(): return Terror.new()
	reg["ARAM_SustainingStrike"] = func(): return Siphon.new()
	reg["ARAM_SpinToWin"] = func(): return SpinToWin.new()
	reg["TrustyWeapon"] = func(): return TrustyWeapon.new()


class UltimateUnstoppable extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 1.5
		description = "Casting your ultimate grants crowd control immunity for 3 seconds (8s cooldown)."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_ability_cast(ab, _t) -> void:
		if cd <= 0.0 and ab.is_ult and not ab.is_summoner:
			cd = 8.0
			owner.cleanse()
			K.buff(owner, "ult_unstoppable", 3.0, {}, owner, {"name": "Unstoppable", "cc": Buff.CC.UNSTOPPABLE})
			Vfx.aura(owner, Color(1.0, 0.85, 0.4), 1.2, 3.0)


class ItsKillingTime extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 2.5
		description = "Casting your ultimate marks all enemy champions for 5 seconds (8s cooldown). The mark stores 40% of your damage to them, then detonates as true damage."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_ability_cast(ab, _t) -> void:
		if cd > 0.0 or not ab.is_ult or ab.is_summoner:
			return
		cd = 8.0
		var m = owner.match_ref
		for e in m.champions_of(G.enemy_team(owner.team)):
			if not e.visible_to[owner.team]:
				continue
			var b := Buff.new("killing_time", 5.0)
			b.display_name = "Death Mark"
			b.is_debuff = true
			b.cleansable = false
			b.set_meta("stored", 0.0)
			var src = owner
			var tgt = e
			b.on_expire = func(bb):
				var st: float = bb.get_meta("stored", 0.0)
				if st > 1.0 and is_instance_valid(tgt) and not tgt.dead and is_instance_valid(src):
					Combat.deal(src, tgt, st, G.DmgType.TRUE, {"is_proc": true, "no_hooks": true, "tag": "killing_time"})
					Vfx.burst(tgt.match_ref, tgt.global_position + Vector3(0, 1, 0), Color(0.9, 0.2, 0.25), 1.6)
			e.add_buff(b, owner)
			b.vfx = Vfx.aura(e, Color(0.9, 0.15, 0.2), 0.9, 5.0, 0.1)

	func on_damage_dealt(info) -> void:
		if info.target == null or info.tag == "killing_time":
			return
		var b: Buff = info.target.find_buff("killing_time", owner)
		if b != null:
			b.set_meta("stored", float(b.get_meta("stored", 0.0)) + info.mitigated * 0.4)


class SkilledSniper extends Augment:
	var done := {}

	func _init() -> void:
		power = 2.0
		description = "Hitting an enemy champion with a basic ability from at least 600 units away reduces its current cooldown by 80%."

	func fits(c) -> bool:
		return has_tag(c, "ranged") and has_tag(c, "ability") or has_tag(c, "poke")

	func on_damage_dealt(info) -> void:
		var ab = info.ability
		if ab == null or ab.is_ult or info.target == null or info.target.kind != G.Kind.CHAMPION:
			return
		if G.flat_dist(owner.global_position, info.target.global_position) < 6.0:
			return
		var key := "%s_%d" % [ab.get_instance_id(), ab.cast_count]
		if done.has(key):
			return
		done[key] = true
		ab.reduce_cooldown_pct(0.65 if info.is_dot else 0.8)


class Archmage extends Augment:
	func _init() -> void:
		power = 2.5
		description = "Whenever you cast an ability, refund 30% of its cooldown to another random ability."

	func on_ability_cast(ab, _t) -> void:
		if ab.is_summoner:
			return
		var others := []
		for i in 4:
			var o = owner.abilities[i]
			if o != null and o != ab and o.cd > 0.0:
				others.append(o)
		if others.is_empty():
			return
		var pick = others[G.rng.randi() % others.size()]
		pick.reduce_cooldown(ab.cd_total * 0.3)


class BackToBasics extends Augment:
	func _init() -> void:
		power = 3.5
		stats = {"ah": 70.0, "heal_power": 0.35}
		description = "Your abilities deal 35% increased damage, you gain 70 ability haste and 35% increased healing and shielding, but your ultimate is sealed."

	func on_attach(u) -> void:
		var r = u.abilities[3]
		if r != null:
			r.sealed = true

	func on_detach(u) -> void:
		var r = u.abilities[3]
		if r != null:
			r.sealed = false

	func on_pre_damage_dealt(info) -> void:
		if info.is_spell:
			info.mult *= 1.35

	func modify_heal_received(amount: float, _h) -> float:
		return amount * 1.35

	func synergy(c) -> float:
		return 1.0 if has_tag(c, "ability") else 0.0


class CantTouchThis extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 3.0
		description = "Casting your ultimate grants invulnerability for 2 seconds (8s cooldown)."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_ability_cast(ab, _t) -> void:
		if cd <= 0.0 and ab.is_ult and not ab.is_summoner:
			cd = 8.0
			K.buff(owner, "cant_touch", 2.0, {}, owner, {"name": "Can't Touch This", "cc": Buff.CC.INVULNERABLE})
			Vfx.shield_bubble(owner, Color(1.0, 0.9, 0.4), 2.0, 1.3)


class Dashing extends Augment:
	func _init() -> void:
		power = 3.0
		description = "Abilities with dashes or blinks gain 175 ability haste."

	func fits(c) -> bool:
		return has_tag(c, "dash")

	func modify_cooldown(ab, cd: float) -> float:
		if ab.is_summoner or not ab.is_dash():
			return cd
		var ah: float = owner.stats.ability_haste + (owner.stats.ult_haste if ab.is_ult else owner.stats.basic_haste)
		return ab.base_cooldown() * 100.0 / (100.0 + ah + 175.0)


class FeyMagic extends Augment:
	var cds := {}

	func _init() -> void:
		power = 2.5
		description = "Damaging enemies with your ultimate polymorphs them into harmless critters for 2 seconds (disarmed, silenced, slowed) (15s cooldown per target)."

	func on_damage_dealt(info) -> void:
		var t = info.target
		if info.ability == null or not info.ability.is_ult or t == null or t.kind != G.Kind.CHAMPION or t.dead:
			return
		var now_t: float = owner.match_ref.time
		if now_t - cds.get(t, -100.0) < 15.0:
			return
		cds[t] = now_t
		var b := Buff.new("polymorph", 2.0)
		b.display_name = "Polymorph"
		b.cc = Buff.CC.POLYMORPH | Buff.CC.DISARM | Buff.CC.SILENCE
		b.is_debuff = true
		b.stats = {"ms": -60.0, "size": -0.6}
		t.add_buff(b, owner)
		Vfx.burst(owner.match_ref, t.global_position + Vector3(0, 1, 0), Color(1.0, 0.5, 0.9), 1.4, {"sparks": 30})


class FinalForm extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 3.0
		description = "Casting your ultimate empowers you for 10 seconds: a shield for 50% max health, 20% omnivamp and 30% movement speed (20s cooldown)."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_ability_cast(ab, _t) -> void:
		if cd > 0.0 or not ab.is_ult or ab.is_summoner:
			return
		cd = 20.0
		Combat.shield(owner, owner, owner.stats.max_hp * 0.5, 10.0, {"id": "final_form", "decay": false})
		K.buff(owner, "final_form", 10.0, {"omnivamp": 0.2, "ms%": 0.3}, owner, {"name": "Final Form"})
		Vfx.aura(owner, Color(1.0, 0.75, 0.25), 1.4, 10.0)
		Vfx.burst(owner.match_ref, owner.global_position + Vector3(0, 1, 0), Color(1.0, 0.8, 0.3), 2.0)


class MysticPunch extends Augment:
	func _init() -> void:
		power = 3.0
		description = "Basic attacks reduce the remaining cooldowns of your abilities by 1.25 seconds."

	func on_attack_hit(_t, info) -> void:
		var mult: float = info.on_hit_mult if info != null else 1.0
		for i in 4:
			var ab = owner.abilities[i]
			if ab != null:
				ab.reduce_cooldown(1.25 * mult)

	func synergy(c) -> float:
		return 1.5 if has_tag(c, "attack") or c.has_augment("ARAM_EtherealWeapon") else -0.5


class StuckInHere extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 2.5
		stats = {"ult_ah": 30.0}
		description = "Casting your ultimate creates an aura that grows to 500 units over 2 seconds, then taunts all enemies inside for 2 seconds while you take 50% less damage (30s cooldown). Gain 30 ultimate haste."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_ability_cast(ab, _t) -> void:
		if cd > 0.0 or not ab.is_ult or ab.is_summoner:
			return
		cd = 30.0
		var o = owner
		var m = o.match_ref
		K.buff(o, "stuck_dr", 4.0, {"dmg_reduction": 0.5}, o, {"name": "Stuck In Here"})
		var aura := Vfx.aura(o, Color(1.0, 0.3, 0.2), 5.0, 2.1)
		aura.scale = Vector3.ONE * 0.2
		var tw := aura.create_tween()
		tw.tween_property(aura, "scale", Vector3.ONE, 2.0)
		m.after(2.0, func():
			if not is_instance_valid(o) or o.dead:
				return
			Vfx.ring(m, o.global_position, Color(1.0, 0.25, 0.2), 5.0, 0.5)
			for e in m.enemies_in_radius(o.team, o.global_position, 5.0, true):
				K.taunt(e, 2.0, o))


class SurgeField extends Augment:
	var zone_until := -1.0
	var zone_pos := Vector3.ZERO

	func _init() -> void:
		power = 2.5
		description = "Casting your ultimate spawns a surge zone for 8 seconds: inside it you gain 50 ability haste and 40% movement speed, and damage to champions fires a missile for 20% bonus magic damage."

	func on_ability_cast(ab, _t) -> void:
		if not ab.is_ult or ab.is_summoner:
			return
		zone_until = owner.match_ref.time + 8.0
		zone_pos = owner.global_position
		Vfx.ground_circle(owner.match_ref, zone_pos, 3.0, Color(0.4, 0.8, 1.0, 0.8), 8.0, 0.2)

	func _inside() -> bool:
		return owner.match_ref != null and owner.match_ref.time < zone_until and G.flat_dist(owner.global_position, zone_pos) < 3.3

	func on_tick(u, _dt: float) -> void:
		if owner.match_ref.time < zone_until + 0.1:
			u.stats.mark_dirty()

	func get_stat_mods() -> Dictionary:
		return {"ah": 50.0, "ms%": 0.4} if owner != null and _inside() else {}

	func on_damage_dealt(info) -> void:
		if _inside() and info.target != null and info.target.kind == G.Kind.CHAMPION and info.tag != "surge" and not info.is_dot:
			Combat.deal(owner, info.target, info.amount * 0.2, G.DmgType.MAGIC, {"is_proc": true, "tag": "surge", "no_hooks": true})
			Vfx.hit_spark(owner.match_ref, info.target.global_position + Vector3(0, 1.2, 0), Color(0.45, 0.85, 1.0), 0.5)


class UltBot extends Augment:
	func _init() -> void:
		power = 2.0
		stats = {"ah": 100.0}
		description = "Ability haste only affects your ultimate, but you gain 100 ability haste and your haste is 50% more effective on it."

	func modify_cooldown(ab, cd: float) -> float:
		if ab.is_summoner:
			return cd
		if ab.is_ult:
			var ah: float = (owner.stats.ability_haste + owner.stats.ult_haste) * 1.5
			return ab.base_cooldown() * 100.0 / (100.0 + ah)
		return ab.base_cooldown()


class UltimateAwakening extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 3.0
		stats = {"ult_ah": 30.0}
		description = "Casting your ultimate resets your basic ability cooldowns and grants 300 basic ability haste for 15 seconds (20s cooldown). Gain 30 ultimate haste."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_ability_cast(ab, _t) -> void:
		if cd > 0.0 or not ab.is_ult or ab.is_summoner:
			return
		cd = 20.0
		for i in 3:
			var b = owner.abilities[i]
			if b != null:
				b.cd = 0.0
		K.buff(owner, "awakening", 15.0, {"basic_ah": 300.0}, owner, {"name": "Ultimate Awakening"})
		Vfx.rising(owner, Color(0.5, 0.8, 1.0), 1.0, 40)


class UltimateRevolution extends Augment:
	var cd := 0.0

	func _init() -> void:
		power = 3.0
		description = "Casting your ultimate resets its cooldown once its effect starts (75s cooldown, resets on death)."

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_death(_k) -> void:
		cd = 0.0

	func on_ability_cast(ab, _t) -> void:
		if cd > 0.0 or not ab.is_ult or ab.is_summoner:
			return
		cd = 75.0
		var self_ref := self
		owner.match_ref.after(0.6, func():
			if is_instance_valid(ab.owner) and ab.recast_window <= 0.0:
				ab.cd = 0.0
				Vfx.ring(self_ref.owner.match_ref, self_ref.owner.global_position, Color(1.0, 0.8, 0.3), 2.0, 0.5))


class Overloaded extends Augment:
	var slot := 0

	func _init() -> void:
		power = 3.0
		description = "Your chosen ability has its cooldown reset whenever you cast a different ability."

	func on_attach(u) -> void:
		slot = Augment.pick_slot(u, "short")
		display_name = "Overloaded (%s)" % "QWE"[slot]

	func on_ability_cast(ab, _t) -> void:
		if ab.is_summoner or ab.slot == slot:
			return
		var target = owner.abilities[slot]
		if target != null:
			target.cd = 0.0


class Bread extends Augment:
	var slot := 0

	static func make(s: int, desc: String) -> Bread:
		var b := Bread.new()
		b.slot = s
		b.power = 2.5
		b.description = desc + " Owning all three Bread augments makes a Bread Sandwich: +250 ultimate haste and +50 haste on each basic ability."
		return b

	func _sandwich() -> bool:
		return owner.has_augment("ARAM_BreadAndButter") and owner.has_augment("ARAM_BreadAndJam") and owner.has_augment("ARAM_BreadAndCheese")

	func modify_cooldown(ab, cd: float) -> float:
		if ab.is_summoner:
			return cd
		var bonus := 0.0
		if ab.slot == slot:
			bonus += 100.0 + (50.0 if _sandwich() else 0.0)
		if bonus <= 0.0:
			return cd
		var ah: float = owner.stats.ability_haste + owner.stats.basic_haste
		return ab.base_cooldown() * 100.0 / (100.0 + ah + bonus)

	func get_stat_mods() -> Dictionary:
		if owner != null and slot == 0 and _sandwich():
			return {"ult_ah": 250.0}
		return {}


class PursuitOfPower extends Augment:
	var slot := 0
	var hits := 0
	var last_key := ""

	func _init() -> void:
		power = 2.0
		description = "QUEST: hit enemy champions 10 times with your chosen ability. REWARD: that ability deals 30% increased damage."

	func on_attach(u) -> void:
		slot = Augment.pick_slot(u, "short")
		display_name = "Pursuit of Power (%s)" % "QWE"[slot]
		counter_text = "0/10"

	func on_pre_damage_dealt(info) -> void:
		if hits >= 10 and info.ability != null and info.ability.slot == slot and not info.ability.is_summoner:
			info.mult *= 1.3

	func on_damage_dealt(info) -> void:
		if hits >= 10 or info.ability == null or info.ability.slot != slot or info.target == null or info.target.kind != G.Kind.CHAMPION:
			return
		var key := "%d_%d" % [info.ability.cast_count, info.target.get_instance_id()]
		if key == last_key:
			return
		last_key = key
		hits += 1
		counter_text = "%d/10" % hits if hits < 10 else "✔"


class PursuitOfHaste extends Augment:
	var slot := 0
	var hits := 0
	var last_key := ""

	func _init() -> void:
		power = 2.0
		description = "QUEST: hit enemy champions with your chosen ability. 10 hits: +80 ability haste on it. 30 hits: another +80."

	func on_attach(u) -> void:
		slot = Augment.pick_slot(u, "short")
		display_name = "Pursuit of Haste (%s)" % "QWE"[slot]
		counter_text = "0/10"

	func on_damage_dealt(info) -> void:
		if hits >= 30 or info.ability == null or info.ability.slot != slot or info.target == null or info.target.kind != G.Kind.CHAMPION:
			return
		var key := "%d_%d" % [info.ability.cast_count, info.target.get_instance_id()]
		if key == last_key:
			return
		last_key = key
		hits += 1
		counter_text = ("%d/10" % hits) if hits < 10 else (("%d/30" % hits) if hits < 30 else "✔")

	func modify_cooldown(ab, cd: float) -> float:
		if ab.is_summoner or ab.slot != slot or hits < 10:
			return cd
		var bonus := 80.0 if hits < 30 else 160.0
		var ah: float = owner.stats.ability_haste + owner.stats.basic_haste
		return ab.base_cooldown() * 100.0 / (100.0 + ah + bonus)


class Quickstep extends Augment:
	var slot := 0

	func _init() -> void:
		power = 2.0
		description = "Casting your chosen ability also dashes you up to 350 units toward your cursor."

	func on_attach(u) -> void:
		slot = Augment.pick_slot(u, "short")
		display_name = "Quickstep (%s)" % "QWE"[slot]

	func on_ability_cast(ab, t) -> void:
		if ab.is_summoner or ab.slot != slot or not owner.dash.is_empty():
			return
		var dest: Vector3 = t.get("pos", owner.global_position + owner.facing * 3.5)
		var o: Vector3 = owner.global_position
		var d := minf(G.flat_dist(o, dest), 3.5)
		if d < 0.5:
			dest = o + owner.facing * 3.5
			d = 3.5
		owner.start_dash(o + G.flat_dir(o, dest) * d, {"speed": 20.0})


class Rejuvenation extends Augment:
	var slot := 0

	func _init() -> void:
		power = 2.0
		description = "Casting your chosen ability heals you for 30-100 (+25% bonus AD) (+15% AP) (+5% bonus health), up to 50% more for long-cooldown abilities."

	func on_attach(u) -> void:
		slot = Augment.pick_slot(u, "long")
		display_name = "Rejuvenation (%s)" % "QWE"[slot]

	func on_ability_cast(ab, _t) -> void:
		if ab.is_summoner or ab.slot != slot:
			return
		var bonus_hp: float = owner.stats.max_hp - (owner.stats.base.base_hp + Stats.growth(owner.stats.base.hp_per_level, owner.level))
		var heal: float = lvl_lerp(30.0, 100.0) + 0.25 * owner.stats.bonus_ad + 0.15 * owner.stats.ap + 0.05 * bonus_hp
		heal *= 1.0 + clampf((ab.base_cooldown() - 6.0) / 20.0, 0.0, 0.5)
		Combat.heal(owner, owner, heal)


class Terror extends Augment:
	var slot := 0
	var cd := 0.0

	func _init() -> void:
		power = 2.0
		description = "Casting your chosen ability fears all enemies within 450 units for 1.75 seconds (30s cooldown)."

	func on_attach(u) -> void:
		slot = Augment.pick_slot(u, "long")
		display_name = "Terror (%s)" % "QWE"[slot]

	func on_tick(_u, dt: float) -> void:
		cd = maxf(0.0, cd - dt)

	func on_ability_cast(ab, _t) -> void:
		if cd > 0.0 or ab.is_summoner or ab.slot != slot:
			return
		var es: Array = owner.match_ref.enemies_in_radius(owner.team, owner.global_position, 4.5)
		if es.is_empty():
			return
		cd = 30.0
		Vfx.ring(owner.match_ref, owner.global_position, Color(0.6, 0.2, 0.8), 4.5, 0.6, 0.15, 0.25)
		for e in es:
			K.fear(e, 1.75, owner)


class Siphon extends Augment:
	var slot := 0

	func _init() -> void:
		power = 2.0
		description = "Your chosen ability heals you for 30% of the damage it deals to enemy champions."

	func on_attach(u) -> void:
		slot = Augment.pick_slot(u, "long")
		display_name = "Siphon (%s)" % "QWE"[slot]

	func on_damage_dealt(info) -> void:
		if info.ability != null and not info.ability.is_summoner and info.ability.slot == slot and info.target != null and info.target.kind == G.Kind.CHAMPION:
			Combat.heal(owner, owner, info.mitigated * 0.3, {"is_vamp": true})


class SpinToWin extends Augment:
	func _init() -> void:
		power = 2.0
		description = "Your spinning abilities deal 30% increased damage (50% for ultimates) and gain 30 ability haste."

	func fits(c) -> bool:
		return has_tag(c, "spin")

	func on_pre_damage_dealt(info) -> void:
		if info.is_spell and info.ability != null and info.ability.get("spinning") != null:
			info.mult *= 1.5 if info.ability.is_ult else 1.3

	func modify_cooldown(ab, cd: float) -> float:
		if ab.get("spinning") == null:
			return cd
		var ah: float = owner.stats.ability_haste + owner.stats.basic_haste
		return ab.base_cooldown() * 100.0 / (100.0 + ah + 30.0)

	func synergy(c) -> float:
		return 2.0 if has_tag(c, "spin") else -3.0


class TrustyWeapon extends Augment:
	var slot := 0

	func _init() -> void:
		power = 1.5
		description = "Your chosen ability grants a Friendship stack for 6 seconds when it hits a champion (max 6). Each stack increases its damage by 5%."

	func on_attach(u) -> void:
		slot = Augment.pick_slot(u, "short")
		display_name = "Trusty Weapon (%s)" % "QWE"[slot]

	func on_pre_damage_dealt(info) -> void:
		if info.ability != null and not info.ability.is_summoner and info.ability.slot == slot:
			var b: Buff = owner.find_buff("friendship")
			if b != null:
				info.mult *= 1.0 + 0.05 * b.stacks

	func on_damage_dealt(info) -> void:
		if info.ability == null or info.ability.is_summoner or info.ability.slot != slot or info.target == null or info.target.kind != G.Kind.CHAMPION:
			return
		var b: Buff = owner.find_buff("friendship")
		if b == null:
			b = Buff.new("friendship", 6.0)
			b.display_name = "Friendship"
			b.max_stacks = 6
			b.stack_mode = Buff.Stack.ADD_STACK
			owner.add_buff(b, owner)
		else:
			b.stacks = mini(6, b.stacks + 1)
			b.remaining = 6.0
