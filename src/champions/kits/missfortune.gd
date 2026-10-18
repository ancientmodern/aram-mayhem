extends ChampionKit
## Miss Fortune, the Bounty Hunter.

const RED := Color(1.0, 0.22, 0.3)
const GOLD := Color(1.0, 0.78, 0.3)
const PINK := Color(1.0, 0.42, 0.62)
const HOT := Color(1.0, 0.92, 0.7)


func build_kit() -> void:
	c.attack_missile_speed = 2000.0
	c.attack_color = Color(1.0, 0.75, 0.4)
	c.role = "marksman"
	c.level_order = "QEWQQRQEQEREEWWRWW"
	c.passive = LoveTap.new()
	c.add_effect(c.passive)
	c.abilities[0] = init_ability(DoubleUp.new(), "Q")
	var w = init_ability(Strut.new(), "W")
	c.abilities[1] = w
	c.abilities[2] = init_ability(MakeItRain.new(), "E")
	var r = init_ability(BulletTime.new(), "R")
	r.cast_range = float(spell("R").get("castConeDistance", 1400.0))
	r.ind_length = r.cast_range
	c.abilities[3] = r
	c.add_effect(StrutPassive.new(w))
	c.add_effect(BotLeveler.new())


func ai_tuning() -> Dictionary:
	return {"aggression": 0.6}


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
		# a player casting something else cancels Bullet Time
		if not owner.is_bot and not owner.channel.is_empty() and owner.channel.ability != self:
			owner.interrupt_channel(true)
		return super(t)

	## Bots never break their own Bullet Time channel with another cast.
	func extra_block_reason() -> String:
		if owner.is_bot and not owner.channel.is_empty() and owner.channel.ability != self:
			return "channeling"
		return ""

	func skip() -> Dictionary:
		return {"skip": true}

	func ground(p: Vector3) -> Vector3:
		var m = owner.match_ref
		return Vector3(p.x, m.nav.height_at(p) if m.nav != null else 0.0, p.z)


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

	static func bullet(color: Color, length: float = 0.8, thick: float = 0.08, trail: bool = true) -> VfxNode:
		var n := VfxNode.new()
		n.add_child(tracer(HOT, length, thick, 3.5))
		n.add_child(Vfx.sprite(color, thick * 6.0, 2.0))
		if trail:
			var tr := Vfx.emitter(color, 24, 0.18, thick * 3.5, {"vmin": 0.0, "vmax": 0.2, "radius": 0.03})
			n.add_child(tr)
			n.trails.append(tr)
		return n

	## Flat circular emission area (instead of a sphere).
	static func disc(e: GPUParticles3D, radius: float) -> void:
		var pm: ParticleProcessMaterial = e.process_material
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = radius
		pm.emission_ring_inner_radius = 0.0
		pm.emission_ring_height = 0.05

	## Lipstick-pink heart pop for Love Tap.
	static func heart(m, pos: Vector3) -> void:
		var n := VfxNode.new()
		n.lifetime = 0.6
		m.add_fx(n, pos)
		var l := Vfx.sprite(PINK, 0.45, 2.6)
		l.position = Vector3(-0.13, 0.08, 0)
		var r := Vfx.sprite(PINK, 0.45, 2.6)
		r.position = Vector3(0.13, 0.08, 0)
		var b := Vfx.sprite(PINK, 0.38, 2.6)
		b.position = Vector3(0, -0.12, 0)
		for s in [l, r, b]:
			n.add_child(s)
		var tw := n.create_tween()
		tw.tween_property(n, "position:y", pos.y + 0.8, 0.6)
		tw.parallel().tween_property(n, "scale", Vector3.ONE * 1.6, 0.6)
		Vfx.hit_spark(m, pos, PINK, 0.8)


# ===================================================================== passive
class LoveTap extends Effect:
	var last_target = null

	func _init() -> void:
		id = "mf_passive"
		display_name = "Love Tap"

	## 50% -> 100% AD by level (levels 1/4/7/9/11/13).
	func ratio() -> float:
		var lv: int = owner.level
		if lv >= 13:
			return 1.0
		if lv >= 11:
			return 0.9
		if lv >= 9:
			return 0.8
		if lv >= 7:
			return 0.7
		if lv >= 4:
			return 0.6
		return 0.5

	func bonus_vs(u) -> float:
		var b: float = ratio() * owner.stats.ad
		if u.kind != G.Kind.CHAMPION:
			b *= 0.5
		return b

	## Returns the Love Tap bonus if `u` is a new target (and consumes it), else 0.
	func try_tap(u) -> float:
		if u == null or not is_instance_valid(u) or u == last_target:
			return 0.0
		last_target = u
		if u.kind == G.Kind.TURRET or u.kind == G.Kind.INHIBITOR or u.kind == G.Kind.NEXUS:
			return 0.0
		FX.heart(owner.match_ref, u.global_position + Vector3(0, u.height * 0.75 if u.kind == G.Kind.CHAMPION else 1.2, 0))
		if u.kind == G.Kind.CHAMPION:
			var w = owner.abilities[1]
			if w != null and w.level > 0:
				w.reduce_cooldown(w.dv("LoveTapBaseRefund", 2.0))
		return bonus_vs(u)

	func on_pre_damage_dealt(info) -> void:
		if info.is_attack and info.target != null:
			var b := try_tap(info.target)
			if b > 0.0:
				if info.is_crit:
					b *= owner.stats.crit_damage
				info.flat_bonus += b


# ===================================================================== Q
class DoubleUp extends KitAbility:
	const BOUNCE_R := 500.0

	func _init() -> void:
		target_type = Target.UNIT
		target_side = Side.ENEMY
		indicator = Ind.NONE
		cast_time = 0.25
		anim = "spell1"
		anim_lock = 0.35
		resets_attack = true

	func damage() -> float:
		return dv("BaseDamage") + dv("ADRatio", 1.0) * ad() + dv("APRatio", 0.35) * ap()

	func crit_mult() -> float:
		return 1.0 + dv("BounceCriticalMod", 0.5) * (owner.stats.crit_damage - 1.0)

	func execute(t: Dictionary) -> void:
		var o = owner
		var u: Unit = t.get("unit")
		if u == null or not is_instance_valid(u) or u.dead:
			return
		var m = o.match_ref
		var from: Vector3 = K.cast_pos(o, 1.2)
		var dir := G.flat_dir(o.global_position, u.global_position)
		var self_ref := self
		Vfx.hit_spark(m, from, GOLD, 0.8)
		K.homing_missile(self, from, u, 1400.0, func(_mi, tu): self_ref._first_hit(tu, dir), {"visual": FX.bullet(GOLD, 0.9, 0.1), "height": 1.2})
		notify_cast(t)

	func _apply(u: Unit, amount: float, crit: bool, tag: String) -> DamageInfo:
		var o = owner
		var bonus: float = o.passive.try_tap(u) if o.passive != null else 0.0
		if crit:
			bonus *= o.stats.crit_damage
		var info := hit(u, amount + bonus, G.DmgType.PHYSICAL, {"tag": tag, "is_crit": crit})
		if info != null and not info.cancelled and is_instance_valid(u):
			for e in o.effects.duplicate():
				e.on_attack_hit(u, info)
		return info

	func _first_hit(u: Unit, dir: Vector3) -> void:
		var o = owner
		if not is_instance_valid(o) or not is_instance_valid(u):
			return
		var m = o.match_ref
		var pos: Vector3 = u.global_position
		var info := _apply(u, damage(), false, "q")
		var killed: bool = info != null and info.killed
		Vfx.burst(m, pos + Vector3(0, 1.0, 0), GOLD, 0.7, {"sparks": 16, "ring": false, "light": false})
		var nxt := bounce_target(u, pos, dir)
		var self_ref := self
		if nxt == null:
			# dud ricochet
			var mi := K.line_missile(self, pos + Vector3(0, 1.2, 0), dir, 400.0, 176.0, {"width": 10.0, "visual": FX.bullet(GOLD, 0.5, 0.06, false)})
			mi.collides = false
			return
		var crit: bool = killed or G.rng.randf() < o.stats.crit_chance
		var col := RED if crit else GOLD
		Vfx.hit_spark(m, pos + Vector3(0, 1.2, 0), col, 0.9)
		K.homing_missile(self, pos + Vector3(0, 1.2, 0), nxt, 1400.0, func(_mi, tu): self_ref._second_hit(tu, crit),
			{"visual": FX.bullet(col, 1.1 if crit else 0.9, 0.12 if crit else 0.1), "height": 1.2})

	func _second_hit(tu: Unit, crit: bool) -> void:
		if not is_instance_valid(owner) or not is_instance_valid(tu):
			return
		var m = owner.match_ref
		var dmg: float = damage() * (crit_mult() if crit else 1.0)
		_apply(tu, dmg, crit, "q2")
		var p2: Vector3 = tu.global_position + Vector3(0, 1.0, 0)
		if crit:
			Vfx.burst(m, p2, RED, 1.3, {"sparks": 34})
			Vfx.hit_spark(m, p2, HOT, 1.4)
		else:
			Vfx.burst(m, p2, GOLD, 0.8, {"sparks": 16, "ring": false, "light": false})

	## Unit behind `first` (relative to the shot direction): champions in a narrow cone first,
	## then anything in the narrow cone, then champions / anything in a wide cone.
	func bounce_target(first, pos: Vector3, dir: Vector3) -> Unit:
		var o = owner
		var best: Unit = null
		var best_s := INF
		for u in o.match_ref.enemies_in_radius(o.team, pos, BOUNCE_R * G.U):
			if u == first:
				continue
			var to := G.flat(u.global_position - pos)
			var d := to.length()
			if d < 0.05:
				continue
			var ang := rad_to_deg(dir.angle_to(to / d))
			var tier := -1
			if ang <= 20.0:
				tier = 0 if u.kind == G.Kind.CHAMPION else 1
			elif ang <= 55.0:
				tier = 2 if u.kind == G.Kind.CHAMPION else 3
			if tier < 0:
				continue
			var s := tier * 100.0 + d
			if s < best_s:
				best_s = s
				best = u
		return best

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var rng := range_m()
		var dmg := damage()
		var mana_r: float = o.mana / maxf(o.stats.max_mana, 1.0)
		# bounce setups: a target in front with an enemy champion behind it
		var best: Unit = null
		var best_s := -INF
		for u in ctx.enemy_minions + ctx.enemies:
			if G.flat_dist(p, u.global_position) > rng + u.radius + o.radius:
				continue
			var nxt := bounce_target(u, u.global_position, G.flat_dir(p, u.global_position))
			if nxt == null or nxt.kind != G.Kind.CHAMPION:
				continue
			var kills: bool = u.hp <= dmg * Combat.resist_multiplier(u.stats.armor, o, true)
			var s := 5.0 + (8.0 if kills else 0.0) + (1.0 - nxt.hp_ratio()) * 3.0 + (2.0 if u.kind == G.Kind.CHAMPION else 0.0)
			if s > best_s:
				best_s = s
				best = u
		if best != null and (ctx.mode != "lane" or mana_r > 0.3 or best_s > 12.0):
			return {"unit": best, "pos": best.global_position, "dir": G.flat_dir(p, best.global_position)}
		var t: Unit = ctx.best_enemy_in_range(rng)
		if t != null and (ctx.mode == "fight" or mana_r > 0.45 or t.hp_ratio() < 0.35):
			return {"unit": t, "pos": t.global_position, "dir": G.flat_dir(p, t.global_position)}
		# farm: last hit with Q when it won't be wasted
		if ctx.enemies.is_empty() and mana_r > 0.6:
			for mn in ctx.enemy_minions:
				if G.flat_dist(p, mn.global_position) <= rng and mn.hp <= dmg * Combat.resist_multiplier(mn.stats.armor, o, true):
					return {"unit": mn, "pos": mn.global_position, "dir": G.flat_dir(p, mn.global_position)}
		return skip()


# ===================================================================== W
class Strut extends KitAbility:
	var since_hit := 99.0

	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0

	func cancels_windup() -> bool:
		return true

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return {"pos": owner.global_position, "dir": owner.facing, "unit": null}

	func passive_ms() -> float:
		if level <= 0:
			return 0.0
		var ooc := dv("PassiveBaseMSOOC", 4.0)
		if owner.has_buff("mf_w_active") or since_hit >= ooc + dv("PassiveMaxMSExtraOOC", 3.0):
			return dv("PassiveMaxMS", 60.0)
		if since_hit >= ooc:
			return dv("PassiveBaseMS", 25.0)
		return 0.0

	func execute(t: Dictionary) -> void:
		var o = owner
		var dur := dv("ActiveDuration", 4.0)
		var b: Buff = K.buff(o, "mf_w_active", dur, {"as": dv("ActiveAS", 0.4)}, o, {"name": "Strut", "icon": icon})
		if b != null:
			var n := VfxNode.new()
			n.lifetime = dur
			o.add_child(n)
			var e := Vfx.emitter(GOLD, 40, 0.5, 0.22, {"vmin": 0.3, "vmax": 1.0, "dir": Vector3.UP, "spread": 30.0, "radius": 0.5, "tex": Vfx.spark_texture()})
			e.position.y = 0.9
			n.add_child(e)
			n.trails.append(e)
			b.vfx = n
		Vfx.aura(o, RED, 1.1, dur, 0.06)
		Vfx.ring(o.match_ref, o.global_position, GOLD, 1.8, 0.35, 0.12, 0.1)
		Vfx.rising(o, PINK, 0.5, 24, 0.5)
		o.stats.mark_dirty()
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var f: Unit = ctx.focus
		if ctx.mode == "fight" and f != null and is_instance_valid(f) and o.edge_dist(f) < o.attack_range_m() + 1.5:
			return make_target(o.global_position)
		if ctx.mode == "retreat" and ctx.in_danger():
			return make_target(o.global_position)
		if ctx.wants_speed():
			return make_target(o.global_position)
		return skip()


## Strut's passive move speed (and its out-of-combat timer).
class StrutPassive extends Effect:
	var w

	func _init(p_w) -> void:
		w = p_w
		id = "mf_strut"
		hidden = true

	func on_tick(_u, dt: float) -> void:
		w.since_hit += dt

	func on_damage_taken(info) -> void:
		var s = info.source
		if s != null and (s.kind == G.Kind.CHAMPION or s.kind == G.Kind.TURRET or info.is_spell):
			w.since_hit = 0.0

	func get_stat_mods() -> Dictionary:
		var ms: float = w.passive_ms()
		return {"ms": ms} if ms > 0.0 else {}


# ===================================================================== E
class MakeItRain extends KitAbility:
	func _init() -> void:
		target_type = Target.POINT
		indicator = Ind.CIRCLE
		ind_radius = 350.0
		cast_time = 0.25
		anim = "spell3"
		anim_lock = 0.4

	func dps() -> float:
		return dv("BaseDamagePerSecond") + dv("APRatioPerSecond", 0.6) * ap()

	func slow_amount() -> float:
		return dv("BaseSlowAmount", 0.4) + dv("SlowPer100AP", 0.0006) * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var pos := ground(t.pos)
		var r_m := ind_radius * G.U
		var delay := dv("CastDelay", 0.25)
		var dur := dv("BaseDuration", 2.0)
		var interval := 1.0 / maxf(1.0, dv("TicksPerSecond", 4.0))
		var per_tick := dps() * interval
		var slow := slow_amount()
		_visual(m, pos, r_m, delay, dur)
		var st := {"age": 0.0, "acc": 0.0}
		var self_ref := self
		m.add_ticker(delay + dur, func(dt: float) -> bool:
			st.age += dt
			if not is_instance_valid(o) or st.age < delay:
				return true
			st.acc += dt
			while st.acc >= interval:
				st.acc -= interval
				for u in m.enemies_in_radius(o.team, pos, r_m):
					self_ref.hit(u, per_tick, G.DmgType.MAGIC, {"tag": "e", "is_aoe": true, "is_dot": true})
					K.slow(u, slow, interval + 0.1, o, false, "mf_e_slow")
					if G.rng.randf() < 0.5:
						Vfx.hit_spark(m, u.global_position + Vector3(G.rng.randf_range(-0.3, 0.3), 1.0, G.rng.randf_range(-0.3, 0.3)), GOLD, 0.4)
			return true)
		notify_cast(t)

	func _visual(m, pos: Vector3, r_m: float, delay: float, dur: float) -> void:
		var life := delay + dur
		var zone := Vfx.ground_circle(m, pos, r_m, Color(1.0, 0.35, 0.3, 0.8), life, 0.12)
		var mat: ShaderMaterial = zone.get_meta("mat")
		var tw := zone.create_tween()
		tw.tween_method(func(v): mat.set_shader_parameter("fill", v), 0.02, 0.2, delay)
		var n := VfxNode.new()
		n.lifetime = life
		m.add_fx(n, pos)
		var rain := Vfx.emitter(HOT, 140, 0.32, 0.16, {"dir": Vector3.DOWN, "spread": 4.0, "vmin": 20.0, "vmax": 24.0, "radius": r_m * 0.85, "tex": Vfx.spark_texture(), "energy": 2.0})
		rain.position.y = 7.0
		FX.disc(rain, r_m * 0.9)
		n.add_child(rain)
		n.trails.append(rain)
		var splash := Vfx.emitter(GOLD, 90, 0.25, 0.22, {"dir": Vector3.UP, "spread": 70.0, "vmin": 1.0, "vmax": 3.0, "radius": r_m * 0.85, "tex": Vfx.spark_texture()})
		splash.position.y = 0.1
		FX.disc(splash, r_m * 0.9)
		n.add_child(splash)
		n.trails.append(splash)
		var dust := Vfx.emitter(RED, 30, 0.6, 0.6, {"dir": Vector3.UP, "spread": 30.0, "vmin": 0.2, "vmax": 0.6, "radius": r_m * 0.8, "energy": 1.0})
		FX.disc(dust, r_m * 0.85)
		n.add_child(dust)
		n.trails.append(dust)
		var l := Vfx.light(GOLD, 2.0, r_m * 2.5)
		l.position.y = 2.0
		n.add_child(l)
		Vfx.ring(m, pos, GOLD, r_m, 0.35, 0.1, 0.05)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var rng := range_m()
		var r_m := ind_radius * G.U
		var mana_r: float = o.mana / maxf(o.stats.max_mana, 1.0)
		var cp: Vector3 = ctx.best_cluster_point(rng, r_m * 0.9, 2)
		if cp != Vector3.INF:
			return ctx.aim_at(cp, self)
		if ctx.mode == "fight" and ctx.focus != null:
			var f: Unit = ctx.focus
			if G.flat_dist(o.global_position, f.global_position) <= rng + r_m * 0.5 and (f.hp_ratio() < 0.6 or mana_r > 0.5):
				return ctx.aim_at(ctx.predict(f, 0.6), self)
		if ctx.mode == "retreat" and not ctx.enemies.is_empty():
			var e0: Unit = ctx.enemies[0]
			if G.flat_dist(o.global_position, e0.global_position) < 7.0:
				return ctx.aim_at(ctx.predict(e0, 0.4), self)
		# wave clear when rich in mana
		if ctx.enemies.is_empty() and mana_r > 0.75:
			for mn in ctx.enemy_minions:
				if G.flat_dist(o.global_position, mn.global_position) > rng:
					continue
				var n := 0
				for mn2 in ctx.enemy_minions:
					if G.flat_dist(mn.global_position, mn2.global_position) <= r_m:
						n += 1
				if n >= 4:
					return make_target(mn.global_position, null)
		return skip()


# ===================================================================== R
class BulletTime extends KitAbility:
	const ANGLE := 40.0
	var _cone: Node3D = null

	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.CONE
		ind_angle = ANGLE
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0

	func wave_damage() -> float:
		return dv("BaseDamage") + dv("tADRatio", 0.6) * ad() + dv("APRatio", 0.25) * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var dir: Vector3 = t.dir
		var waves := int(dv("BaseWaves", 14.0))
		var dur := dv("BaseChannelDuration", 3.0)
		var interval := dur / float(maxi(waves, 1))
		o.stop_moving()
		o.cancel_windup()
		o.face_toward(o.global_position + dir, 1000.0)
		start_channel(dur, {"dir": dir, "interval": interval, "acc": interval, "left": waves, "n": 0})
		o.channel_disarm = true
		o.play_anim("spell4", 1.0, 0.1)
		o.anim_lock = dur
		_cone = _cone_visual(m, o.global_position, dir, dur)
		Vfx.ring(m, o.global_position, RED, 2.0, 0.4, 0.12, 0.1)
		notify_cast(t)

	func _cone_visual(m, pos: Vector3, dir: Vector3, dur: float) -> Node3D:
		var len := cast_range * G.U
		var n := VfxNode.new()
		n.lifetime = dur + 0.1
		m.add_fx(n, pos)
		var mi := Vfx.indicator_mesh(2, Color(1.0, 0.25, 0.3, 0.32))
		mi.material_override.set_shader_parameter("cone_half", deg_to_rad(ANGLE * 0.5))
		n.add_child(mi)
		mi.global_position = Vector3(pos.x, pos.y + 0.1, pos.z) + dir * len * 0.5
		mi.global_basis = Basis(Vector3.UP, atan2(dir.x, dir.z)).scaled(Vector3(len * 2.0, 1, len))
		return n

	func channel_tick(dt: float, ch: Dictionary) -> void:
		var o = owner
		# a player's move order cancels the channel (League behaviour)
		if not o.is_bot and o.moving and o.cmd == Unit.Cmd.MOVE:
			o.interrupt_channel(true)
			return
		o.face_toward(o.global_position + ch.dir, dt)
		ch.acc += dt
		while ch.acc >= ch.interval and ch.left > 0:
			ch.acc -= ch.interval
			ch.left -= 1
			ch.n += 1
			_wave(ch)

	func _wave(ch: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var dir: Vector3 = ch.dir
		var origin: Vector3 = o.global_position
		var len_u := cast_range
		var dmg := wave_damage()
		var crit: bool = G.rng.randf() < o.stats.crit_chance
		if crit:
			dmg *= 1.0 + dv("CritDamageMultiplier", 0.3) * (o.stats.crit_damage - 1.0)
		var self_ref := self
		for u in K.enemies_cone(self, origin, dir, len_u, ANGLE):
			var delay := G.flat_dist(origin, u.global_position) / 20.0
			m.after(delay, func():
				if is_instance_valid(u) and not u.dead and is_instance_valid(o):
					self_ref.hit(u, dmg, G.DmgType.PHYSICAL, {"tag": "r", "is_aoe": true, "is_crit": crit})
					Vfx.hit_spark(m, u.global_position + Vector3(G.rng.randf_range(-0.3, 0.3), 1.0 + G.rng.randf_range(-0.3, 0.3), 0), RED if crit else GOLD, 0.7 if crit else 0.5))
		# visuals: alternate guns, a fan of tracer rounds
		var side := Vector3(-dir.z, 0, dir.x)
		var gun := side * (0.35 if ch.n % 2 == 0 else -0.35)
		var muzzle: Vector3 = origin + Vector3(0, 1.15, 0) + dir * 0.7 + gun
		Vfx.hit_spark(m, muzzle, HOT, 0.9)
		var half := deg_to_rad(ANGLE * 0.5)
		var count := 6
		for j in count:
			var a := lerpf(-half, half, (float(j) + G.rng.randf()) / float(count))
			var bd := dir.rotated(Vector3.UP, a)
			var mi := K.line_missile(self, muzzle, bd, 2000.0 + G.rng.randf_range(-150.0, 150.0), len_u, {
				"width": 10.0, "visual": FX.bullet(RED if crit else GOLD, 0.9, 0.09, j % 2 == 0), "height": 1.15})
			mi.collides = false
		if m.camera_rig != null and o == G.player:
			m.camera_rig.shake(0.06)

	func channel_end(_ch: Dictionary, _interrupted: bool) -> void:
		var o = owner
		o.channel_disarm = false
		o.anim_lock = 0.0
		if _cone != null and is_instance_valid(_cone):
			_cone.queue_free()
		_cone = null

	## Enemy champions inside the cone toward `dir`.
	func count_in_cone(ctx, dir: Vector3, lead: float) -> Array:
		var o = owner
		var out := []
		var half := deg_to_rad(ANGLE * 0.5)
		var rng := cast_range * G.U - 1.0
		for e in ctx.enemies:
			var p: Vector3 = ctx.predict(e, lead)
			var to := G.flat(p - o.global_position)
			var d := to.length()
			if d > rng or d < 0.1:
				continue
			if dir.angle_to(to / d) <= half + atan2(e.radius, d) * 0.5:
				out.append(e)
		return out

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if ctx.enemies.is_empty():
			return skip()
		var best_dir := Vector3.ZERO
		var best: Array = []
		var best_s := -INF
		var dirs: Array = []
		for e in ctx.enemies:
			if G.flat_dist(o.global_position, e.global_position) < cast_range * G.U:
				dirs.append(G.flat_dir(o.global_position, ctx.predict(e, 0.6)))
		for i in dirs.size():
			for j in range(i + 1, dirs.size()):
				var avg: Vector3 = (dirs[i] + dirs[j])
				if avg.length() > 0.5:
					dirs.append(avg.normalized())
		for d in dirs:
			var inside := count_in_cone(ctx, d, 0.6)
			var s := inside.size() * 10.0
			for e in inside:
				s += (1.0 - e.hp_ratio()) * 3.0
			if s > best_s:
				best_s = s
				best = inside
				best_dir = d
		if best.is_empty():
			return skip()
		var total := 0.0
		var waves := dv("BaseWaves", 14.0)
		var lone: Unit = best[0]
		total = wave_damage() * waves * 0.6 * Combat.resist_multiplier(lone.stats.armor, o, true)
		# divers on top of us: don't plant ourselves unless it's a big hit
		var divers := 0
		for e in ctx.enemies:
			if o.edge_dist(e) < 2.0 and e.stats.attack_range < 300.0:
				divers += 1
		if best.size() >= 3 or (best.size() >= 2 and divers == 0) or (best.size() >= 2 and o.hp_ratio() > 0.5):
			return {"pos": o.global_position + best_dir * 5.0, "dir": best_dir, "unit": null}
		if best.size() == 1 and ctx.mode == "fight" and divers == 0 and total >= lone.hp + lone.total_shield() \
				and ((lone.cc & Buff.IMMOBILIZE) != 0 or lone.stats.slow > 0.2 or G.flat_dist(o.global_position, lone.global_position) < 8.0):
			return {"pos": o.global_position + best_dir * 5.0, "dir": best_dir, "unit": null}
		return skip()
