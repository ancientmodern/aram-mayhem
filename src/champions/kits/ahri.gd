extends ChampionKit
## Ahri, the Nine-Tailed Fox.

const COL := Color(0.45, 0.65, 1.0)
const COL_PINK := Color(1.0, 0.45, 0.8)


func build_kit() -> void:
	c.attack_missile_speed = 1750.0
	c.attack_color = Color(0.55, 0.6, 1.0)
	c.role = "mage"
	c.level_order = "QEWQQRQEQEREEWWRWW"
	c.passive = EssenceTheft.new()
	c.add_effect(c.passive)
	c.abilities[0] = init_ability(OrbOfDeception.new(), "Q")
	c.abilities[1] = init_ability(FoxFire.new(), "W")
	c.abilities[2] = init_ability(Charm.new(), "E")
	c.abilities[3] = init_ability(SpiritRush.new(), "R")


# ===================================================================== passive
class EssenceTheft extends Effect:
	var stacks := 0
	var takedown_window := 3.0

	func _init() -> void:
		id = "ahri_passive"
		display_name = "Essence Theft"

	func hud_counter() -> String:
		return str(stacks) if stacks > 0 else ""

	func on_kill(victim) -> void:
		if victim.kind == G.Kind.MINION:
			stacks += 1
			if stacks >= 9:
				stacks = 0
				var heal: float = lerpf(35.0, 95.0, (owner.level - 1) / 17.0) + 0.2 * owner.stats.ap
				Combat.heal(owner, owner, heal)
				Vfx.rising(owner, Color(0.5, 0.8, 1.0), 0.6, 30)

	func on_takedown(victim) -> void:
		if victim.kind != G.Kind.CHAMPION:
			return
		var heal: float = lerpf(75.0, 165.0, (owner.level - 1) / 17.0) + 0.3 * owner.stats.ap
		Combat.heal(owner, owner, heal)
		Vfx.rising(owner, Color(1.0, 0.55, 0.85), 0.8, 40)
		var r: Ability = owner.abilities[3]
		if r != null and r.recast_window > 0.0:
			r.recast_window += 10.0
			r.casts_left = mini(3, r.casts_left + 1)


# ===================================================================== Q
class OrbOfDeception extends Ability:
	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 200.0
		cast_time = 0.25
		anim = "spell1"

	func damage() -> float:
		return dv("BaseDamage") + 0.5 * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var from: Vector3 = K.cast_pos(o, 1.1)
		var dir: Vector3 = t.dir
		var dmg := damage()
		var out_hits := {}
		var self_ref := self
		var mi := K.line_missile(self, from, dir, 2500.0, 970.0, {
			"width": 100.0, "pierce": true, "color": Color(0.55, 0.75, 1.0), "size": 0.75, "light": true,
			"accel": -3200.0, "max_speed": 2500.0,
			"on_hit": func(_m, u): self_ref.hit(u, dmg, G.DmgType.MAGIC, {"tag": "q"}); Vfx.hit_spark(o.match_ref, u.global_position + Vector3(0, 1, 0), COL),
		})
		mi.min_speed = 400.0 * G.U
		mi.on_end = func(_m, pos): _return_orb(pos, dmg)
		notify_cast(t)

	func _return_orb(pos: Vector3, dmg: float) -> void:
		var o = owner
		if not is_instance_valid(o) or o.dead:
			return
		var mi := Missile.new()
		mi.ability = self
		mi.setup_homing(o, pos, o, 60.0 * G.U)
		mi.mode = Missile.Mode.FOLLOW
		mi.accel = 1900.0 * G.U
		mi.max_speed = 2600.0 * G.U
		mi.collides = true
		mi.pierce = true
		mi.width = 100.0 * G.U
		mi.height = 1.1
		mi.visual = Vfx.orb(Color(0.7, 0.85, 1.0), 0.75, true)
		var self_ref := self
		mi.on_hit = func(_m, u):
			if u == o:
				mi.finish(o.global_position)
				return
			self_ref.hit(u, dmg, G.DmgType.TRUE, {"tag": "q"})
			Vfx.hit_spark(o.match_ref, u.global_position + Vector3(0, 1, 0), Color(1, 1, 1))
		mi.on_move = func(m2, _dt):
			if G.flat_dist(m2.global_position, o.global_position) < 0.6:
				m2.finish(o.global_position)
		o.match_ref.add_missile(mi, pos)

	func ai_consider(ctx) -> Dictionary:
		var t: Unit = ctx.best_enemy_in_range(9.2)
		if t != null:
			return ctx.aim_at(ctx.predict(t, cast_time + G.flat_dist(owner.global_position, t.global_position) / 17.0), self)
		if owner.mana > owner.stats.max_mana * 0.6 and ctx.enemy_minions.size() >= 4 and ctx.enemies.is_empty():
			var mn = ctx.enemy_minions[0]
			if G.flat_dist(owner.global_position, mn.global_position) < 8.0:
				return make_target(mn.global_position, null)
		return {}


# ===================================================================== W
class FoxFire extends Ability:
	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 725.0
		cast_time = 0.0
		anim = "spell2"
		anim_lock = 0.3

	func fire_damage() -> float:
		return dv("BaseDamage") + dv("APRatio", 0.4) * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		K.haste(o, dv("MovementSpeed", 0.4), dv("MovementSpeedDuration", 2.0), o, true, "ahri_w_ms")
		var holder := VfxNode.new()
		holder.lifetime = 2.6
		o.add_child(holder)
		holder.position.y = 1.0
		var flames := []
		for i in 3:
			var f := Vfx.orb(Color(0.45, 0.6, 1.0), 0.42, false, true)
			holder.add_child(f)
			flames.append(f)
		var spin := holder.create_tween().set_loops()
		spin.tween_property(holder, "rotation:y", TAU, 1.2).from(0.0)
		for i in 3:
			flames[i].position = Vector3(cos(i * TAU / 3.0), 0, sin(i * TAU / 3.0)) * 1.5
		var dmg := fire_damage()
		var hits_on := {}
		var self_ref := self
		var launch := func(idx: int):
			if not is_instance_valid(o) or o.dead:
				return
			var tgt: Unit = self_ref._pick_target()
			if tgt == null:
				return
			var f = flames[idx]
			if not is_instance_valid(f):
				return
			var p: Vector3 = f.global_position
			f.visible = false
			K.homing_missile(self_ref, p, tgt, 1400.0, func(_mm, u):
				var n: int = hits_on.get(u, 0)
				hits_on[u] = n + 1
				var d := dmg * (1.0 if n == 0 else self_ref.dv("RepeatDamageMod", 0.4))
				if u.kind == G.Kind.MINION and u.hp_ratio() < 0.2:
					d *= 2.0
				self_ref.hit(u, d, G.DmgType.MAGIC, {"tag": "w"})
				Vfx.hit_spark(m, u.global_position + Vector3(0, 1, 0), Color(0.5, 0.65, 1.0)),
				{"color": Color(0.45, 0.6, 1.0), "size": 0.42})
		# fire all three after the initial delay if targets exist, otherwise keep checking
		for i in 3:
			var delay := dv("InitialDelay", 0.25) + i * 0.12
			m.after(delay, func(): launch.call(i))
		notify_cast(t)

	func _pick_target() -> Unit:
		var o = owner
		var r := dv("BonusAcquisitionRange", 725.0) * G.U
		var best: Unit = null
		var bd := INF
		var focus = o.attack_target
		for u in o.match_ref.enemies_in_radius(o.team, o.global_position, r):
			var d := G.flat_dist(o.global_position, u.global_position)
			if u == focus or u.has_buff("charm"):
				d -= 50.0
			if u.kind == G.Kind.CHAMPION:
				d -= 4.0
			if d < bd:
				bd = d
				best = u
		return best

	func ai_consider(ctx) -> Dictionary:
		if ctx.count_enemies_near(owner.global_position, 7.0) > 0:
			return {"pos": owner.global_position}
		if ctx.enemies.is_empty() and ctx.enemy_minions.size() >= 3 and owner.mana > owner.stats.max_mana * 0.5:
			for mn in ctx.enemy_minions:
				if G.flat_dist(owner.global_position, mn.global_position) < 6.0:
					return {"pos": owner.global_position}
		return {}


# ===================================================================== E
class Charm extends Ability:
	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 120.0
		cast_time = 0.25
		anim = "spell3_north"

	func execute(t: Dictionary) -> void:
		var o = owner
		var dmg := dv("BaseDamage") + dv("APRatio", 0.85) * ap()
		var dur := dv("CharmDuration", 1.2)
		var self_ref := self
		var heart := VfxNode.new()
		heart.add_child(Vfx.sprite(Color(1.0, 0.4, 0.75), 0.9, 2.5))
		heart.add_child(Vfx.sprite(Color(1.0, 0.75, 0.9), 0.4, 3.0))
		var e := Vfx.emitter(Color(1.0, 0.45, 0.8), 40, 0.4, 0.35, {"vmin": 0.0, "vmax": 0.4})
		heart.add_child(e)
		heart.trails.append(e)
		K.line_missile(self, K.cast_pos(o, 1.1), t.dir, 1550.0, 975.0, {
			"width": 120.0, "visual": heart,
			"on_hit": func(_m, u):
				self_ref.hit(u, dmg, G.DmgType.MAGIC, {"tag": "e"})
				K.charm(u, dur, o, 0.65)
				Vfx.burst(o.match_ref, u.global_position + Vector3(0, 1.0, 0), COL_PINK, 1.0, {"ring": false, "sparks": 20}),
		})
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var t: Unit = ctx.best_enemy_in_range(9.0)
		if t != null and not t.has_cc_immunity():
			return ctx.aim_at(ctx.predict(t, cast_time + G.flat_dist(owner.global_position, t.global_position) / 15.5), self)
		return {}


# ===================================================================== R
class SpiritRush extends Ability:
	var casts_left := 0
	var dash_lock := 0.0

	func _init() -> void:
		target_type = Target.POINT
		indicator = Ind.NONE
		cast_range = 500.0
		cast_time = 0.0
		anim = "spell4"
		anim_lock = 0.35

	func is_dash() -> bool:
		return true

	func auto_cooldown() -> bool:
		return false

	func extra_block_reason() -> String:
		return "cooldown" if dash_lock > 0.0 else ""

	func on_tick(dt: float) -> void:
		dash_lock = maxf(0.0, dash_lock - dt)

	func execute(t: Dictionary) -> void:
		var o = owner
		if recast_window <= 0.0:
			casts_left = 3
			recast_window = dv("RRecastWindow", 15.0)
		casts_left -= 1
		dash_lock = dv("RDashCooldown", 1.0)
		var dest: Vector3 = o.global_position + G.flat_dir(o.global_position, t.pos) * minf(G.flat_dist(o.global_position, t.pos), dv("RDashDistance", 500.0) * G.U)
		var self_ref := self
		var trail := Vfx.rising(o, Color(0.6, 0.7, 1.0), 0.35, 30, 0.4)
		o.start_dash(dest, {"speed": 15.0, "on_arrive": func(_u): self_ref._bolts()})
		if casts_left <= 0:
			recast_window = 0.0
			start_cooldown()
		notify_cast(t)

	func on_recast_expired() -> void:
		casts_left = 0
		start_cooldown()

	func _bolts() -> void:
		var o = owner
		var m = o.match_ref
		var dmg := dv("RBaseDamage") + dv("RAPCoefficient", 0.35) * ap()
		var cands: Array = m.enemies_in_radius(o.team, o.global_position, dv("RAcquisitionRange", 600.0) * G.U)
		cands.sort_custom(func(a, b):
			var sa: float = (0.0 if a.kind == G.Kind.CHAMPION else 100.0) + G.flat_dist(o.global_position, a.global_position)
			var sb: float = (0.0 if b.kind == G.Kind.CHAMPION else 100.0) + G.flat_dist(o.global_position, b.global_position)
			return sa < sb)
		var self_ref := self
		for i in mini(3, cands.size()):
			var tgt: Unit = cands[i]
			K.homing_missile(self, o.global_position + Vector3(0, 1.2, 0), tgt, 1400.0, func(_mm, u):
				self_ref.hit(u, dmg, G.DmgType.MAGIC, {"tag": "r"})
				Vfx.hit_spark(m, u.global_position + Vector3(0, 1, 0), Color(0.7, 0.75, 1.0), 0.8),
				{"color": Color(0.65, 0.7, 1.0), "size": 0.45})

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if ctx.mode == "retreat" and ctx.in_danger():
			var away: Vector3 = G.flat_dir(ctx.enemies[0].global_position, o.global_position)
			return {"pos": o.global_position + away * 5.0}
		var t: Unit = ctx.best_enemy_in_range(10.0)
		if t != null and (t.hp_ratio() < 0.5 or recast_window > 0.0) and o.hp_ratio() > 0.3:
			var d := G.flat_dist(o.global_position, t.global_position)
			var toward := G.flat_dir(o.global_position, t.global_position)
			# dash to a spot within bolt range but not on top of them
			var goal: Vector3 = o.global_position + toward * clampf(d - 3.0, 0.5, 5.0)
			return {"pos": goal}
		return {}
