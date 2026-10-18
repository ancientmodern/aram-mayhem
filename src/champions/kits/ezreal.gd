extends ChampionKit
## Ezreal, the Prodigal Explorer.

const GOLD := Color(1.0, 0.82, 0.3)
const SUN := Color(1.0, 0.92, 0.6)
const ARCANE := Color(0.45, 0.75, 1.0)
const FLUX := Color(1.0, 0.55, 0.15)


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
	c.add_effect(BotLeveler.new())


func ai_tuning() -> Dictionary:
	return {"aggression": 0.5}


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
	static func tracer(color: Color, length: float, thick: float, energy: float = 3.0) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(thick, thick, length)
		mi.mesh = bm
		var mat := Vfx.add_material(color, energy, false)
		mat.set_shader_parameter("use_mask", false)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi

	static func solid(mesh: Mesh, color: Color, energy: float = 2.0) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var mat := Vfx.add_material(color, energy, false)
		mat.set_shader_parameter("use_mask", false)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi

	static func torus(color: Color, r: float, thick: float, energy: float = 2.0) -> MeshInstance3D:
		var tm := TorusMesh.new()
		tm.inner_radius = r - thick
		tm.outer_radius = r
		tm.rings = 24
		return solid(tm, color, energy)


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
			var n := Vfx.aura(o, GOLD, 1.0, dur, 0.1)
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

	static func bolt_visual() -> VfxNode:
		var n := VfxNode.new()
		n.add_child(FX.tracer(SUN, 1.1, 0.16, 4.0))
		n.add_child(Vfx.sprite(Color(1, 1, 0.9), 0.45, 3.5))
		n.add_child(Vfx.sprite(GOLD, 1.2, 1.5))
		var tr := Vfx.emitter(GOLD, 50, 0.3, 0.35, {"vmin": 0.0, "vmax": 0.5, "radius": 0.08})
		n.add_child(tr)
		n.trails.append(tr)
		var sp := Vfx.emitter(ARCANE, 16, 0.35, 0.18, {"vmin": 0.6, "vmax": 1.6, "radius": 0.1, "tex": Vfx.spark_texture()})
		n.add_child(sp)
		n.trails.append(sp)
		n.add_child(Vfx.light(GOLD, 1.5, 3.0))
		return n

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var from: Vector3 = K.cast_pos(o, 1.15)
		var dmg := damage()
		var self_ref := self
		Vfx.hit_spark(m, from, GOLD, 0.7)
		K.line_missile(self, from, t.dir, 2000.0, 1200.0, {
			"width": 60.0, "visual": bolt_visual(), "height": 1.15,
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
		var p: Vector3 = u.global_position + Vector3(0, 1.0, 0)
		Vfx.burst(o.match_ref, p, GOLD, 0.7, {"sparks": 18, "ring": false})
		Vfx.hit_spark(o.match_ref, p, ARCANE, 0.8)

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

	static func orb_visual() -> VfxNode:
		var n := VfxNode.new()
		n.add_child(Vfx.sprite(Color(1.0, 0.95, 0.75), 0.5, 3.0))
		n.add_child(Vfx.sprite(FLUX, 1.4, 1.6))
		var ring := FX.torus(GOLD, 0.45, 0.06, 2.5)
		ring.rotation.x = PI * 0.5
		n.add_child(ring)
		var tw := ring.create_tween().set_loops()
		tw.tween_property(ring, "rotation:z", TAU, 0.5).from(0.0)
		var tr := Vfx.emitter(FLUX, 50, 0.4, 0.45, {"vmin": 0.0, "vmax": 0.6, "radius": 0.15})
		n.add_child(tr)
		n.trails.append(tr)
		n.add_child(Vfx.light(FLUX, 1.8, 3.5))
		return n

	func execute(t: Dictionary) -> void:
		var o = owner
		var from: Vector3 = K.cast_pos(o, 1.15)
		var self_ref := self
		var mi := K.line_missile(self, from, t.dir, 1700.0, 1200.0, {
			"width": 60.0, "minions": false, "visual": orb_visual(), "height": 1.15,
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
		var b: Buff = K.buff(u, "ezreal_w_mark", dv("DetonationTimeout", 4.0), {}, o, {"name": "Essence Flux", "debuff": true})
		if b != null:
			b.vfx = _mark_visual(u, b.duration)
		Vfx.hit_spark(o.match_ref, u.global_position + Vector3(0, 1.2, 0), FLUX, 0.9)

	func _mark_visual(u: Unit, dur: float) -> VfxNode:
		var n := VfxNode.new()
		n.lifetime = dur + 0.1
		u.add_child(n)
		var h: float = u.height if u.kind == G.Kind.CHAMPION else 3.0
		n.position.y = h * 0.6
		n.add_child(Vfx.sprite(FLUX, 0.9, 1.4))
		n.add_child(Vfx.sprite(SUN, 0.35, 3.0))
		var ring := FX.torus(GOLD, 0.6, 0.05, 2.0)
		n.add_child(ring)
		var ring2 := FX.torus(FLUX, 0.45, 0.04, 2.0)
		ring2.rotation.x = PI * 0.5
		n.add_child(ring2)
		var tw := n.create_tween().set_loops()
		tw.tween_property(n, "rotation:y", TAU, 1.2).from(0.0)
		var tw2 := ring2.create_tween().set_loops()
		tw2.tween_property(ring2, "rotation:z", TAU, 0.8).from(0.0)
		return n

	## Detonate the mark on `u` (by_ability = the ability that triggered it, null for attacks).
	func detonate(u, by_ability) -> void:
		var o = owner
		if u == null or not is_instance_valid(u) or u.dead:
			return
		var b = u.find_buff("ezreal_w_mark", o)
		if b == null:
			return
		u.remove_buff(b)
		hit(u, damage(), G.DmgType.MAGIC, {"tag": "w_det"})
		if by_ability != null and o.stats.uses_mana:
			o.mana = minf(o.stats.max_mana, o.mana + by_ability.cost() + dv("ManaReturn", 60.0))
			Vfx.rising(o, ARCANE, 0.4, 14, 0.4)
		var p: Vector3 = u.global_position + Vector3(0, 1.1, 0)
		Vfx.burst(o.match_ref, p, FLUX, 1.3, {"sparks": 30})
		Vfx.burst(o.match_ref, p, SUN, 0.6, {"sparks": 6, "ring": false, "light": false})

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
		Vfx.burst(m, from + Vector3(0, 1.0, 0), GOLD, 0.9, {"sparks": 24, "ring": false})
		Vfx.ring(m, from, GOLD, 1.2, 0.3, 0.12, 0.1)
		o.cancel_windup()
		o.teleport(dest)
		for e in o.effects.duplicate():
			e.on_dash(from, dest)
		Vfx.beam(m, from + Vector3(0, 1.0, 0), dest + Vector3(0, 1.0, 0), SUN, 0.25, 0.25)
		Vfx.burst(m, dest + Vector3(0, 1.0, 0), SUN, 1.0, {"sparks": 30})
		Vfx.rising(o, GOLD, 0.3, 20, 0.5)
		var tgt := _pick_target(dest)
		if tgt != null:
			var dmg := damage()
			var self_ref := self
			var vis := VfxNode.new()
			vis.add_child(Vfx.sprite(Color(1, 1, 0.85), 0.4, 3.5))
			vis.add_child(Vfx.sprite(GOLD, 1.0, 1.6))
			var tr := Vfx.emitter(GOLD, 40, 0.3, 0.3, {"vmin": 0.0, "vmax": 0.4, "radius": 0.06})
			vis.add_child(tr)
			vis.trails.append(tr)
			K.homing_missile(self, dest + Vector3(0, 1.2, 0), tgt, 2000.0, func(_mi, u):
				self_ref.hit(u, dmg, G.DmgType.MAGIC, {"tag": "e"})
				Vfx.burst(m, u.global_position + Vector3(0, 1.0, 0), GOLD, 0.8, {"sparks": 16, "ring": false}),
				{"visual": vis, "height": 1.2})
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
		var o = owner
		var dir: Vector3 = t.get("dir", o.facing)
		var n := VfxNode.new()
		n.lifetime = cast_time + 0.05
		o.add_child(n)
		n.position = Vector3(0, 1.2, 0) + dir * 0.9
		var core := Vfx.sprite(Color(1, 1, 0.9), 0.3, 3.5)
		n.add_child(core)
		var halo := Vfx.sprite(GOLD, 0.8, 1.6)
		n.add_child(halo)
		var inward := Vfx.emitter(GOLD, 60, 0.45, 0.25, {"vmin": -3.5, "vmax": -2.0, "radius": 1.6, "local": true, "tex": Vfx.spark_texture()})
		n.add_child(inward)
		n.add_child(Vfx.light(GOLD, 2.0, 5.0))
		var tw := n.create_tween()
		tw.tween_property(core, "scale", Vector3.ONE * 1.1, cast_time)
		tw.parallel().tween_property(halo, "scale", Vector3.ONE * 2.0, cast_time)
		Vfx.aura(o, GOLD, 1.6, cast_time, 0.08)

	static func wave_visual() -> VfxNode:
		var n := VfxNode.new()
		for i in 11:
			var x := (float(i) - 5.0) * 0.32
			var bulge := (1.0 - pow(x / 1.75, 2.0)) * 0.7
			var s := Vfx.sprite(GOLD if i % 2 == 0 else SUN, 0.95, 1.4)
			s.position = Vector3(x, 0, -bulge)
			n.add_child(s)
		var core := FX.tracer(SUN, 0.4, 0.18, 2.5)
		core.scale = Vector3(13.0, 1.0, 1.0)
		core.position.z = -0.65
		n.add_child(core)
		for x2 in [-1.2, 0.0, 1.2]:
			var tr := Vfx.emitter(GOLD, 40, 0.35, 0.6, {"vmin": 0.0, "vmax": 0.6, "radius": 0.4, "energy": 1.3})
			tr.position = Vector3(x2, 0, 0)
			n.add_child(tr)
			n.trails.append(tr)
		var sp := Vfx.emitter(SUN, 30, 0.5, 0.22, {"vmin": 1.0, "vmax": 3.0, "radius": 1.2, "tex": Vfx.spark_texture(), "energy": 2.0})
		n.add_child(sp)
		n.trails.append(sp)
		n.add_child(Vfx.light(GOLD, 3.0, 8.0))
		return n

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var from: Vector3 = K.cast_pos(o, 1.2)
		var dmg_c := damage()
		var dmg_m := minion_damage()
		var self_ref := self
		Vfx.burst(m, from, GOLD, 0.9, {"sparks": 30, "ring": false})
		Vfx.ring(m, o.global_position, GOLD, 2.5, 0.4, 0.1, 0.05)
		var mi := K.line_missile(self, from, t.dir, 2000.0, 25000.0, {
			"width": 160.0, "pierce": true, "visual": wave_visual(), "height": 1.2,
			"on_hit": func(_mi, u):
				var d: float = dmg_c if u.kind == G.Kind.CHAMPION else dmg_m
				self_ref.hit(u, d, G.DmgType.MAGIC, {"tag": "r", "is_aoe": true})
				Vfx.burst(m, u.global_position + Vector3(0, 1.0, 0), GOLD, 1.0 if u.kind == G.Kind.CHAMPION else 0.5, {"sparks": 16, "ring": false, "light": false}),
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
