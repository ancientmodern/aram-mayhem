extends ChampionKit
## Ezreal, the Prodigal Explorer.

const GOLD := Color(1.0, 0.82, 0.3)


func build_kit() -> void:
	c.attack_missile_speed = 2000.0
	c.attack_color = Color(1.0, 0.85, 0.45)
	c.role = "marksman"
	c.level_order = "QWEQQRQWQWRWWEEREE"
	var pd: Dictionary = spell("EzrealPassive").get("data_values", {})
	c.passive = RisingSpellForce.new(pd)
	c.add_effect(c.passive)
	c.abilities[0] = init_ability(MysticShot.new(), "Q")
	var w = init_ability(EssenceFlux.new(), "W")
	c.abilities[1] = w
	c.abilities[2] = init_ability(ArcaneShift.new(), "E")
	var r = init_ability(TrueshotBarrage.new(), "R")
	r.cast_range = 25000.0
	r.ind_length = 3000.0
	c.abilities[3] = r
	c.add_effect(FluxHook.new(w))
	c.add_effect(AttackFx.new())
	c.add_effect(BotLeveler.new())


func ai_tuning() -> Dictionary:
	return {"aggression": 0.5}


## League VFX mapping. Cast flashes are attached by the abilities at hand height (the generic hook
## attaches them at the feet); the W detonation and the Arcane Shift blink are spawned by the kit.
func vfx_map() -> Dictionary:
	return {
		"Q_cas": "", "Q_mis": "Ezreal_Base_Q_mis", "Q_tar": "Ezreal_Base_Q_tar",
		"W_cas": "", "W_mis": "Ezreal_Base_W_mis", "W_tar": "",
		"E_cas": "", "E_mis": "Ezreal_Base_E_mis", "E_tar": "Ezreal_Base_E_tar",
		"R_cas": "", "R_mis": "Ezreal_Base_R_mis", "R_tar": "Ezreal_Base_R_tar",
	}


# ===================================================================== shared
## Workaround: the core only levels bot abilities at spawn; spend new points as bots level up.
class BotLeveler extends Effect:
	func _init() -> void:
		id = "kit_bot_leveler"
		hidden = true

	func on_tick(u, _dt: float) -> void:
		if u.is_bot and u.ability_points > 0:
			u.auto_level_abilities()


## Abilities return {"skip": true} from ai_consider to hold (prevents the generic bot fallback).
class KitAbility extends Ability:
	func try_cast(t: Dictionary) -> bool:
		if t.get("skip", false):
			return false
		return super(t)

	func skip() -> Dictionary:
		return {"skip": true}

	func ground(p: Vector3) -> Vector3:
		var m = owner.match_ref
		return Vector3(p.x, m.nav.height_at(p) if m.nav != null else 0.0, p.z)

	## Enemy minions standing on the segment owner->to (before `to`).
	func minions_blocking(ctx, to: Vector3, hw_m: float) -> int:
		var a: Vector3 = owner.global_position
		var dmax := G.flat_dist(a, to)
		var n := 0
		for mn in ctx.enemy_minions:
			if G.flat_dist(a, mn.global_position) > dmax:
				continue
			if NavGrid._dist_to_segment(mn.global_position, a, to) <= hw_m + mn.radius:
				n += 1
		return n

	func enemy_champs() -> Array:
		var o = owner
		return o.match_ref.champions.filter(func(e): return e.team != o.team and not e.dead and e.is_targetable_by(o.team))


class FX extends RefCounted:
	## League flash attached at the hand (League effects are bone-relative; we use a hand height + forward offset).
	static func hand_fx(u: Unit, name: String, dir: Vector3, h: float = 1.15, fwd: float = 0.5) -> LolVfx:
		var d := Vector3(dir.x, 0.0, dir.z)
		if d.length_squared() < 0.001:
			d = u.facing
		d = d.normalized()
		var fx := LolVfx.attach(u, name, {"dir": d, "height": h})
		if fx != null:
			fx.position += d * fwd
		return fx

	static func is_structure(u) -> bool:
		return u.kind == G.Kind.TURRET or u.kind == G.Kind.INHIBITOR or u.kind == G.Kind.NEXUS


## League basic attack muzzle flash (Ezreal_Base_BA_cas) at the gauntlet.
class AttackFx extends Effect:
	func _init() -> void:
		id = "ezreal_attack_fx"
		hidden = true

	func on_attack_launch(target) -> void:
		var dir: Vector3 = owner.facing
		if target != null and is_instance_valid(target):
			dir = G.flat_dir(owner.global_position, target.global_position)
		FX.hand_fx(owner, "Ezreal_Base_BA_cas", dir, owner.height * 0.55, owner.radius)


# ===================================================================== passive
class RisingSpellForce extends Effect:
	var per := 0.1
	var dur := 6.0
	var max_st := 5
	var _glow: Node3D = null

	func _init(pd: Dictionary) -> void:
		id = "ezreal_passive"
		display_name = "Rising Spell Force"
		per = float(pd.get("AttackSpeedPerStack", 0.1))
		dur = float(pd.get("StackDuration", 6.0))
		max_st = int(pd.get("MaxStacks", 5.0))

	func hud_counter() -> String:
		if owner == null:
			return ""
		var b: Buff = owner.find_buff("ezreal_rsf")
		return str(b.stacks) if b != null else ""

	func on_damage_dealt(info) -> void:
		var ab = info.ability
		if ab == null or not info.is_spell or ab.is_summoner or ab.owner != owner or info.target == null:
			return
		add_stack()

	func add_stack() -> void:
		var o = owner
		var b: Buff = o.find_buff("ezreal_rsf")
		var before: int = b.stacks if b != null else 0
		K.buff(o, "ezreal_rsf", dur, {}, o, {"name": "Rising Spell Force", "icon": icon,
			"per_stack": {"as": per}, "max_stacks": max_st, "stack_mode": Buff.Stack.ADD_STACK})
		o.stats.mark_dirty()
		b = o.find_buff("ezreal_rsf")
		if b != null and b.stacks >= max_st and before < max_st:
			# fully charged: golden glow while maxed
			# lives as long as the maxed buff (refreshes keep it); freed with the buff
			var n := Vfx.aura(o, GOLD, 1.0, 0.0, 0.1)
			b.vfx = n
			Vfx.rising(o, GOLD, 0.6, 24, 0.5)


# ===================================================================== Q
class MysticShot extends KitAbility:
	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 120.0
		cast_time = 0.25
		anim = "spell1"
		anim_lock = 0.35

	func damage() -> float:
		return dv("BaseDamage") + dv("BaseDamageADRatio", 1.3) * ad() + dv("BaseDamageAPRatio", 0.15) * ap()

	func begin_cast(t: Dictionary) -> void:
		super(t)
		FX.hand_fx(owner, "Ezreal_Base_Q_bow", t.get("dir", owner.facing))

	func execute(t: Dictionary) -> void:
		var o = owner
		var from: Vector3 = K.cast_pos(o, 1.15)
		var dmg := damage()
		var self_ref := self
		K.line_missile(self, from, t.dir, 2000.0, 1200.0, {
			"width": 60.0, "lol": "Ezreal_Base_Q_mis", "height": 1.15,
			"on_hit": func(_mi, u): self_ref._on_hit(u, dmg),
		})
		notify_cast(t)

	func _on_hit(u: Unit, dmg: float) -> void:
		var o = owner
		if not is_instance_valid(o):
			return
		var info := hit(u, dmg, G.DmgType.PHYSICAL, {"tag": "q"})
		# Mystic Shot applies on-hit effects
		if info != null and not info.cancelled and is_instance_valid(u):
			for e in o.effects.duplicate():
				e.on_attack_hit(u, info)
		for a in o.abilities:
			if a != null:
				a.reduce_cooldown(dv("CDRefund", 1.5))

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var rng := 11.5
		var best: Unit = null
		var best_s := -INF
		var best_aim := Vector3.ZERO
		for e in ctx.enemies:
			var d := G.flat_dist(o.global_position, e.global_position)
			if d > rng + 0.5:
				continue
			var aim: Vector3 = ctx.predict(e, cast_time + d / 20.0)
			if G.flat_dist(o.global_position, aim) > rng:
				continue
			if minions_blocking(ctx, aim, 0.6) > 0:
				continue
			var s: float = (1.0 - e.hp_ratio()) * 3.0 - d * 0.1 + (2.0 if (e.cc & Buff.IMMOBILIZE) != 0 else 0.0)
			if e.find_buff("ezreal_w_mark", o) != null:
				s += 3.0
			if s > best_s:
				best_s = s
				best = e
				best_aim = aim
		var mana_r: float = o.mana / maxf(o.stats.max_mana, 1.0)
		if best != null and (ctx.mode != "lane" or mana_r > 0.25):
			return ctx.aim_at(best_aim, self)
		# farm: last-hit minions out of reach (also refunds cooldowns)
		if ctx.enemies.is_empty() and mana_r > 0.45:
			var dmg := damage()
			for mn in ctx.enemy_minions:
				var d2 := G.flat_dist(o.global_position, mn.global_position)
				if d2 > rng or mn.kind != G.Kind.MINION:
					continue
				var eff: float = dmg * Combat.resist_multiplier(mn.stats.armor, o, true)
				if mn.hp <= eff and (d2 > o.attack_range_m() + 0.5 or o.attack_timer > 0.3):
					var aim2: Vector3 = mn.global_position
					var blockers := minions_blocking(ctx, aim2, 0.6)
					if blockers <= 1:
						return make_target(aim2, null)
		return skip()


# ===================================================================== W
class EssenceFlux extends KitAbility:
	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 120.0
		cast_time = 0.25
		anim = "spell2"
		anim_lock = 0.35

	func damage() -> float:
		return dv("BaseDamage") + 1.0 * bonus_ad() + dv("APRatio", 0.9) * ap()

	func begin_cast(t: Dictionary) -> void:
		super(t)
		FX.hand_fx(owner, "Ezreal_Base_W_Cas", t.get("dir", owner.facing))

	func execute(t: Dictionary) -> void:
		var o = owner
		var from: Vector3 = K.cast_pos(o, 1.15)
		var self_ref := self
		var mi := K.line_missile(self, from, t.dir, 1700.0, 1200.0, {
			"width": 60.0, "minions": false, "lol": "Ezreal_Base_W_mis", "height": 1.15,
			"on_hit": func(_mi, u): self_ref._stick(u),
		})
		mi.hit_structures = true
		mi.hits_summons = false
		notify_cast(t)

	func _stick(u: Unit) -> void:
		var o = owner
		if not is_instance_valid(o) or not is_instance_valid(u) or u.dead:
			return
		var old = u.find_buff("ezreal_w_mark", o)
		if old != null:
			u.remove_buff(old)
		# INDEPENDENT + source lookup: another Ezreal's mark is a separate debuff (REFRESH would merge them and
		# orphan the second orb VFX). kill_fx: the orb (a 4 s particle) vanishes the moment the mark ends -
		# detonation, expiry, death or removal - instead of fading for seconds after it.
		var b: Buff = K.buff(u, "ezreal_w_mark", dv("DetonationTimeout", 4.0), {}, o, {"name": "Essence Flux", "debuff": true,
			"stack_mode": Buff.Stack.INDEPENDENT, "kill_fx": true})
		if b != null:
			# League mark (orb + ring) on the target until it is detonated or expires
			var h: float = u.height if u.kind == G.Kind.CHAMPION else 3.0
			b.vfx = LolVfx.attach(u, "Ezreal_Base_W_tar_objects" if FX.is_structure(u) else "Ezreal_Base_W_tar", {"loop": true, "height": h * 0.5})
			b.kill_fade = 0.0

	## Detonate the mark on `u` (by_ability = the ability that triggered it, null for attacks).
	func detonate(u, by_ability) -> void:
		var o = owner
		if u == null or not is_instance_valid(u) or u.dead:
			return
		var b = u.find_buff("ezreal_w_mark", o)
		if b == null:
			return
		u.remove_buff(b)
		var h: float = u.height if u.kind == G.Kind.CHAMPION else 3.0
		LolVfx.spawn(o.match_ref, "Ezreal_Base_W_hit_Objects" if FX.is_structure(u) else "Ezreal_Base_W_hit",
			u.global_position + Vector3(0, h * 0.5, 0), {"dir": G.flat_dir(o.global_position, u.global_position)})
		hit(u, damage(), G.DmgType.MAGIC, {"tag": "w_det"})
		if by_ability != null and o.stats.uses_mana:
			o.mana = minf(o.stats.max_mana, o.mana + by_ability.cost() + dv("ManaReturn", 60.0))

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var rng := 11.5
		var mana_r: float = o.mana / maxf(o.stats.max_mana, 1.0)
		var q = o.abilities[0]
		var follow_up: bool = q != null and q.level > 0 and q.cd < 1.0
		var best: Unit = null
		var best_aim := Vector3.ZERO
		var best_s := -INF
		for e in ctx.enemies:
			var d := G.flat_dist(o.global_position, e.global_position)
			if d > rng:
				continue
			if e.find_buff("ezreal_w_mark", o) != null:
				continue
			var aim: Vector3 = ctx.predict(e, cast_time + d / 17.0)
			if G.flat_dist(o.global_position, aim) > rng:
				continue
			var s: float = (1.0 - e.hp_ratio()) * 3.0 - d * 0.1
			if d <= o.attack_range_m() + e.radius:
				s += 2.0
			if s > best_s:
				best_s = s
				best = e
				best_aim = aim
		if best != null and (ctx.mode == "fight" or follow_up or mana_r > 0.5):
			return ctx.aim_at(best_aim, self)
		# sieging: mark the turret we are hitting
		var tgt = o.attack_target
		if tgt != null and is_instance_valid(tgt) and tgt.kind == G.Kind.TURRET and ctx.enemies.is_empty() and mana_r > 0.5:
			if G.flat_dist(o.global_position, tgt.global_position) < rng and tgt.find_buff("ezreal_w_mark", o) == null:
				return make_target(tgt.global_position, null)
		return skip()


## Detonates Essence Flux marks when Ezreal's attacks or abilities hit.
class FluxHook extends Effect:
	var w

	func _init(p_w) -> void:
		w = p_w
		id = "ezreal_w_hook"
		hidden = true

	func on_attack_hit(target, _info) -> void:
		w.detonate(target, null)

	func on_damage_dealt(info) -> void:
		var ab = info.ability
		if ab == null or ab == w or not info.is_spell or ab.is_summoner or ab.owner != owner:
			return
		w.detonate(info.target, ab)


# ===================================================================== E
class ArcaneShift extends KitAbility:
	func _init() -> void:
		target_type = Target.POINT
		indicator = Ind.CIRCLE
		ind_radius = 70.0
		cast_range = 475.0
		cast_time = 0.25
		anim = "spell3"
		anim_lock = 0.3

	func is_dash() -> bool:
		return true

	func damage() -> float:
		return dv("BaseDamage") + 0.6 * bonus_ad() + dv("EAPRatio", 0.75) * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var from: Vector3 = o.global_position
		var want: Vector3 = from + G.flat_dir(from, t.pos) * minf(G.flat_dist(from, t.pos), range_m())
		var dest := want
		if m.nav != null and not m.nav.is_walkable(want):
			dest = m.nav.nearest_walkable(want)
		# League blink: E_cas stays at the departure point, E_end plays on Ezreal at the arrival
		var bdir := G.flat_dir(from, dest)
		LolVfx.spawn(m, "Ezreal_Base_E_cas", from, {"dir": bdir, "height": 1.0})
		o.cancel_windup()
		o.teleport(dest)
		for e in o.effects.duplicate():
			e.on_dash(from, dest)
		LolVfx.attach(o, "Ezreal_Base_E_end", {"dir": bdir, "height": 1.0})
		var tgt := _pick_target(dest)
		if tgt != null:
			var dmg := damage()
			var self_ref := self
			K.homing_missile(self, dest + Vector3(0, 1.2, 0), tgt, 2000.0, func(_mi, u):
				self_ref.hit(u, dmg, G.DmgType.MAGIC, {"tag": "e"}),
				{"lol": "Ezreal_Base_E_mis", "height": 1.2})
		notify_cast(t)

	func _pick_target(pos: Vector3) -> Unit:
		var o = owner
		var best: Unit = null
		var best_s := INF
		for u in o.match_ref.enemies_in_radius(o.team, pos, dv("MissileRange", 750.0) * G.U):
			var s := G.flat_dist(pos, u.global_position)
			if u.find_buff("ezreal_w_mark", o) != null:
				s -= 100.0
			if s < best_s:
				best_s = s
				best = u
		return best

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var blink := range_m()
		if ctx.enemies.is_empty():
			return skip()
		var nearest: Unit = null
		var nd := INF
		for e in ctx.enemies:
			var d := G.flat_dist(p, e.global_position)
			if d < nd:
				nd = d
				nearest = e
		var home := G.flat_dir(p, o.spawn_point)
		# escape / peel
		var melee_on_me: bool = nearest != null and nd < 2.6 and nearest.stats.attack_range < 300.0
		if (ctx.mode == "retreat" and ctx.in_danger() and nd < 7.0) or (melee_on_me and o.hp_ratio() < 0.65):
			var away := G.flat_dir(nearest.global_position, p)
			var dir := (away * 0.6 + home * 0.4).normalized()
			return {"pos": p + dir * blink, "dir": dir, "unit": null}
		# finish: the bolt (or a blink into attack range) kills a fleeing champion
		if ctx.mode == "fight" and o.hp_ratio() > 0.4:
			var dmg := damage()
			for e in ctx.enemies:
				var eff: float = dmg * Combat.resist_multiplier(e.stats.mr, o, false)
				var d2 := G.flat_dist(p, e.global_position)
				if e.hp + e.total_shield() > eff * 1.05 or d2 > dv("MissileRange", 750.0) * G.U + blink - 0.5:
					continue
				# blink sideways/back when possible so the bolt still reaches
				var back := G.flat_dir(e.global_position, p)
				var spot := p + back * blink
				if G.flat_dist(spot, e.global_position) > dv("MissileRange", 750.0) * G.U - 0.5:
					spot = p + G.flat_dir(p, e.global_position) * blink
				if ctx.count_enemies_near(spot, 4.0) > 1 and o.hp_ratio() < 0.7:
					continue
				var closer := 0
				for u in o.match_ref.enemies_in_radius(o.team, spot, dv("MissileRange", 750.0) * G.U):
					if u != e and G.flat_dist(spot, u.global_position) < G.flat_dist(spot, e.global_position) and e.find_buff("ezreal_w_mark", o) == null:
						closer += 1
				if closer == 0:
					return {"pos": spot, "dir": G.flat_dir(p, spot), "unit": null}
		return skip()


# ===================================================================== R
class TrueshotBarrage extends KitAbility:
	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 320.0
		cast_time = 1.0
		anim = "spell4"
		anim_lock = 1.15

	func damage() -> float:
		return dv("BaseDamage") + 1.0 * bonus_ad() + dv("RAPRatio", 0.9) * ap()

	func minion_damage() -> float:
		return dv("BaseDamageMinionMonster") + 1.0 * bonus_ad() + 1.1 * ap()

	func begin_cast(t: Dictionary) -> void:
		super(t)
		# League channel: arcane bow drawn in front of Ezreal + glowing gauntlet
		var dir: Vector3 = t.get("dir", owner.facing)
		FX.hand_fx(owner, "Ezreal_Base_R_bow", dir, 1.2, 0.6)
		FX.hand_fx(owner, "Ezreal_Base_R_Gauntlet_Glow", dir, 1.2, 0.4)

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var from: Vector3 = K.cast_pos(o, 1.2)
		var dmg_c := damage()
		var dmg_m := minion_damage()
		var self_ref := self
		var mi := K.line_missile(self, from, t.dir, 2000.0, 25000.0, {
			"width": 160.0, "pierce": true, "lol": "Ezreal_Base_R_mis", "height": 1.2,
			"on_hit": func(_mi, u):
				var d: float = dmg_c if u.kind == G.Kind.CHAMPION else dmg_m
				self_ref.hit(u, d, G.DmgType.MAGIC, {"tag": "r", "is_aoe": true}),
		})
		mi.lifetime = 14.0
		if m.camera_rig != null and o == G.player:
			m.camera_rig.shake(0.25)
		notify_cast(t)

	func _count_line(from: Vector3, dir: Vector3, length: float, champs: Array) -> int:
		var to := from + dir * length
		var n := 0
		for e in champs:
			if NavGrid._dist_to_segment(e.global_position, from, to) <= 1.6 + e.radius:
				n += 1
		return n

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var from: Vector3 = o.global_position
		var champs := enemy_champs()
		var best_s := -INF
		var best_aim := Vector3.ZERO
		for e in champs:
			var d := G.flat_dist(from, e.global_position)
			if d > 200.0 or d < 1.5:
				continue
			var tt := cast_time + d / 20.0
			var v: Vector3 = e.velocity if (e.cc & Buff.BLOCK_MOVE) == 0 else Vector3.ZERO
			var aim: Vector3 = e.global_position + v * minf(tt, 2.5) * 0.7
			var dir := G.flat_dir(from, aim)
			var eff: float = damage() * Combat.resist_multiplier(e.stats.mr, o, false)
			var n := _count_line(from, dir, 200.0, champs)
			var s := -INF
			if eff >= e.hp + e.total_shield():
				s = 100.0 - d * 0.2 + n * 5.0
				if d > 40.0 and v.length() > 1.0 and (e.cc & Buff.IMMOBILIZE) == 0:
					s -= 25.0
			elif n >= 3 and d < 60.0:
				s = 40.0 + n * 10.0
			elif n >= 2 and ctx.mode == "fight" and d < 25.0:
				s = 25.0 + n * 5.0
			elif ctx.mode == "fight" and d < 15.0 and e.hp_ratio() < 0.4 and eff > e.hp * 0.6:
				s = 15.0
			if s > best_s:
				best_s = s
				best_aim = aim
		if best_s <= 0.0:
			return skip()
		return ctx.aim_at(best_aim, self)
