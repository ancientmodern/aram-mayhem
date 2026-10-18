extends ChampionKit
## Annie, the Dark Child.

const FIRE := Color(1.0, 0.42, 0.08)
const FIRE_HOT := Color(1.0, 0.78, 0.35)
const EMBER := Color(1.0, 0.22, 0.04)
const STUN_WHITE := Color(1.0, 0.93, 0.78)
const HOLD := {"hold": true}


func build_kit() -> void:
	c.attack_missile_speed = 1200.0
	c.attack_color = Color(1.0, 0.55, 0.2)
	c.role = "mage"
	c.level_order = "QWEQQRQWQWRWWEEREE"
	c.passive = Pyromania.new()
	c.add_effect(c.passive)
	c.abilities[0] = init_ability(Disintegrate.new(), "Q")
	c.abilities[1] = init_ability(Incinerate.new(), "W")
	c.abilities[2] = init_ability(MoltenShield.new(), "E")
	c.abilities[3] = init_ability(SummonTibbers.new(), "R")
	# AnnieE has no cooldown in the extracted data (live: 14/13/12/11/10)
	c.abilities[2].cooldowns = [14.0, 13.0, 12.0, 11.0, 10.0]
	c.add_effect(TibbersPen.new(c.abilities[3]))


func ai_tuning() -> Dictionary:
	return {"aggression": 0.6}


## League VFX: Q/W/R visuals are spawned by the kit at the right place and moment.
func vfx_map() -> Dictionary:
	return {"Q_tar": "", "W_cas": "", "W_tar": "Annie_Base_W_Hit", "R_cas": ""}


## Bot AI returns HOLD to deliberately skip a cast ({} would fall back to BotBrain.default_consider).
class KAbility extends Ability:
	func try_cast(t: Dictionary) -> bool:
		if t.get("hold", false):
			return false
		return super.try_cast(t)


# ===================================================================== shared helpers
class AnnieUtil:
	static func pyro(o):
		var p = o.passive
		if p != null and p.has_method("consume"):
			return p
		return null

	static func stun_ready(o) -> bool:
		var p = pyro(o)
		return p != null and p.stacks >= 4

	static func stacks(o) -> int:
		var p = pyro(o)
		return p.stacks if p != null else 0

	## Tibbers can be summoned right now.
	static func r_up(o) -> bool:
		var r = o.abilities[3]
		return r != null and r.level > 0 and r.recast_window <= 0.0 and r.cast_block_reason() == ""

	static func allies_near(ctx, pos: Vector3, r: float) -> int:
		var n := 0
		for a in ctx.allies:
			if G.flat_dist(a.global_position, pos) < r:
				n += 1
		return n

	## Worth holding the stun for Tibbers: R is up and several champions are close enough to be caught.
	static func hold_for_r(o, ctx) -> bool:
		return r_up(o) and ctx.count_enemies_near(o.global_position, 9.5) >= 2

	static func consume_stun(o) -> float:
		var p = pyro(o)
		if p == null:
			return 0.0
		return p.consume()

	## Post-mitigation estimate of magic damage from `o` to `target`.
	static func est(o, target, dmg: float) -> float:
		var mr: float = target.stats.mr
		if mr > 0.0:
			mr = maxf(0.0, mr * (1.0 - o.stats.magic_pen_pct) - o.stats.magic_pen)
		return dmg * 100.0 / (100.0 + mr)

	static func flash_of(o):
		for sm in o.summoners:
			if sm != null and sm.id == "Flash" and sm.cast_block_reason() == "":
				return sm
		return null

	static func shake(o, amount: float) -> void:
		var m = o.match_ref
		if m != null and m.camera_rig != null and G.player != null and G.flat_dist(G.player.global_position, o.global_position) < 14.0:
			m.camera_rig.shake(amount)

	static func ground_at(m, pos: Vector3) -> Vector3:
		if m != null and m.nav != null:
			return Vector3(pos.x, m.nav.height_at(pos) + 0.05, pos.z)
		return pos

	## Disintegrate impact: League flash on the target, plus the ground shockwave when it stuns.
	static func q_impact(o, tgt, empowered: bool) -> void:
		if tgt == null or not is_instance_valid(tgt) or tgt.match_ref == null:
			return
		var m = tgt.match_ref
		var d: Vector3 = G.flat_dir(o.global_position, tgt.global_position) if is_instance_valid(o) else Vector3.ZERO
		LolVfx.spawn(m, "Annie_Base_Q_tar_02", tgt.global_position + Vector3(0, tgt.height * 0.5, 0), {"dir": d})
		if empowered:
			LolVfx.spawn(m, "Annie_Base_Q_tar", ground_at(m, tgt.global_position), {"dir": d})


# ===================================================================== passive
class Pyromania extends Effect:
	var stacks := 4             ## starts (and respawns) with the stun ready
	var just_consumed := false
	var ready_fx: Node3D = null
	var ready_fx2: Node3D = null

	func _init() -> void:
		id = "annie_passive"
		display_name = "Pyromania"

	func hud_counter() -> String:
		return str(stacks)

	func stun_duration() -> float:
		var lvl: int = owner.level
		if lvl >= 11:
			return 1.75
		if lvl >= 6:
			return 1.5
		return 1.25

	## Called by damaging abilities on cast. Returns the stun duration (0 if not ready).
	func consume() -> float:
		if stacks < 4:
			return 0.0
		stacks = 0
		just_consumed = true
		_hide_ready()
		return stun_duration()

	func on_ability_cast(ab, _t) -> void:
		if ab == null or ab.is_summoner or ab.slot > 3:
			return
		if just_consumed:
			just_consumed = false
			return
		if stacks < 4:
			stacks += 1
			if stacks >= 4:
				_show_ready(true)

	func on_tick(u, _dt: float) -> void:
		# bots never spend level-up points in core; do it for them (no effect for human players)
		if u.is_bot and u.ability_points > 0:
			u.auto_level_abilities()
		if stacks >= 4 and not u.dead and (ready_fx == null or not is_instance_valid(ready_fx)):
			_show_ready(false)

	func on_cc_applied(target, buff) -> void:
		if (buff.cc & Buff.CC.STUN) != 0 and target.kind == G.Kind.CHAMPION:
			var r = owner.abilities[3]
			if r != null and r.has_method("enrage"):
				r.enrage(r.dv("EnrageDuration", 3.0), false)

	func on_death(_killer) -> void:
		_hide_ready()
		var r = owner.abilities[3]
		if r != null and r.has_method("enrage"):
			r.enrage(r.dv("AvengerEnrageDuration", 10.0), true)

	func on_respawn() -> void:
		stacks = 4

	func _show_ready(_pop: bool) -> void:
		_hide_ready()
		var o = owner
		ready_fx = LolVfx.attach(o, "Annie_Base_StunReady", {"loop": true, "height": 0.05})
		if ready_fx == null:
			ready_fx = Vfx.aura(o, STUN_WHITE, 0.95, 1.0e6, 0.07)

	func _hide_ready() -> void:
		for fx in [ready_fx, ready_fx2]:
			# kill (not detach_and_fade): the stun-ready glow must not keep fading where Annie stood
			K.kill_fx(fx, 0.15)
		ready_fx = null
		ready_fx2 = null


# ===================================================================== Q
class Disintegrate extends KAbility:
	func _init() -> void:
		target_type = Target.UNIT
		target_side = Side.ENEMY
		indicator = Ind.RANGE
		cast_time = 0.25
		anim = "spell1"
		anim_lock = 0.45

	func damage() -> float:
		return dv("BaseDamage") + dv("APRatio", 0.8) * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var u = t.get("unit")
		if u == null or not is_instance_valid(u) or u.dead:
			return
		var stun := AnnieUtil.consume_stun(o)
		var dmg := damage()
		var paid := cost()
		var m = o.match_ref
		var self_ref := self
		var on_hit := func(_mm, tgt):
			var info = self_ref.hit(tgt, dmg, G.DmgType.MAGIC, {"tag": "q"})
			if stun > 0.0:
				K.stun(tgt, stun, o)
			AnnieUtil.q_impact(o, tgt, stun > 0.0)
			if info != null and info.killed and is_instance_valid(o) and not o.dead:
				o.mana = minf(o.stats.max_mana, o.mana + paid)
				self_ref.cd = maxf(0.0, self_ref.cd - self_ref.cd_total * 0.5)
				Vfx.rising(o, Color(0.5, 0.7, 1.0), 0.35, 14, 0.4)
		K.homing_missile(self, K.cast_pos(o, 1.2), u, 1400.0, on_hit, {"lol": "Annie_Base_Q_mis"})
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var rng := range_m() + 0.3
		var dmg := damage()
		var ready := AnnieUtil.stun_ready(o)
		# 1) secure kills
		for e in ctx.enemies:
			if G.flat_dist(o.global_position, e.global_position) <= rng + e.radius:
				if AnnieUtil.est(o, e, dmg) >= e.hp + e.total_shield():
					return {"unit": e, "pos": e.global_position}
		if ready:
			# hold the stun for a multi-target R/W unless we must peel or it's a duel
			var close: Unit = null
			for e in ctx.enemies:
				if G.flat_dist(o.global_position, e.global_position) < 3.5 + e.radius and not e.has_cc_immunity():
					close = e
					break
			if close != null and (ctx.in_danger() or o.hp_ratio() < 0.6):
				return {"unit": close, "pos": close.global_position}
			var f: Unit = ctx.focus
			if f == null or not is_instance_valid(f) or f.dead:
				f = ctx.best_enemy_in_range(rng)
			if f != null and G.flat_dist(o.global_position, f.global_position) <= rng + f.radius and not f.has_cc_immunity():
				if f.hp_ratio() < 0.35:
					return {"unit": f, "pos": f.global_position}
				# save it for a multi-target Tibbers / Incinerate when those are available
				if AnnieUtil.hold_for_r(o, ctx):
					return HOLD
				var w_ab = o.abilities[1]
				if w_ab != null and w_ab.cast_block_reason() == "" and w_ab.best_cone(ctx)[0] >= 2:
					return HOLD
				# single-target stun: in a committed fight, or when allies are there to follow up
				if ctx.mode == "fight" or AnnieUtil.allies_near(ctx, f.global_position, 7.0) >= 1:
					return {"unit": f, "pos": f.global_position}
			return HOLD
		# 2) poke champions (also builds Pyromania)
		var t: Unit = ctx.best_enemy_in_range(rng)
		if t != null:
			return {"unit": t, "pos": t.global_position}
		# 3) last-hit minions with Q (refund) to stack the passive
		if o.mana > o.stats.max_mana * 0.3:
			var best: Unit = null
			var best_hp := INF
			for mn in ctx.enemy_minions:
				if mn.kind != G.Kind.MINION:
					continue
				if G.flat_dist(o.global_position, mn.global_position) > rng + mn.radius:
					continue
				if AnnieUtil.est(o, mn, dmg) * 0.95 >= mn.hp and mn.hp > o.stats.ad * 1.1 and mn.hp < best_hp:
					best_hp = mn.hp
					best = mn
			if best != null:
				return {"unit": best, "pos": best.global_position}
		return HOLD


# ===================================================================== W
class Incinerate extends KAbility:
	const ANGLE := 50.0

	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.CONE
		ind_angle = ANGLE
		cast_range = 600.0
		cast_time = 0.25
		anim = "spell2"
		anim_lock = 0.45

	func damage() -> float:
		return dv("BaseDamage") + dv("APRatio", 0.8) * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var stun := AnnieUtil.consume_stun(o)
		var dir: Vector3 = t.dir
		var origin: Vector3 = o.global_position
		var dmg := damage()
		LolVfx.spawn(m, "Annie_Base_W_cas_Right", AnnieUtil.ground_at(m, origin), {"dir": dir})
		var self_ref := self
		for u in K.enemies_cone(self, origin, dir, cast_range + 40.0, ANGLE):
			var delay := G.flat_dist(origin, u.global_position) / 28.0
			var tgt: Unit = u
			m.after(delay, func():
				if not is_instance_valid(tgt) or tgt.dead or not is_instance_valid(o):
					return
				self_ref.hit(tgt, dmg, G.DmgType.MAGIC, {"is_aoe": true, "tag": "w"})
				if stun > 0.0:
					K.stun(tgt, stun, o))
		AnnieUtil.shake(o, 0.08)
		notify_cast(t)

	## Number of enemy champions hit by a cone from `from` toward `aim`.
	func _count(ctx, from: Vector3, aim: Vector3) -> int:
		var dir := G.flat_dir(from, aim)
		var n := 0
		var half := deg_to_rad(ANGLE * 0.5)
		for e in ctx.enemies:
			var p: Vector3 = ctx.predict(e, cast_time)
			var to := G.flat(p - from)
			var d := to.length()
			if d > cast_range * G.U + e.radius:
				continue
			if d < 0.8 or dir.angle_to(to.normalized()) <= half + atan2(e.radius, maxf(d, 0.01)) * 0.6:
				n += 1
		return n

	## [champions hit, aim point] of the best cone from Annie's position.
	func best_cone(ctx) -> Array:
		var p: Vector3 = owner.global_position
		var best_n := 0
		var best_aim := Vector3.INF
		for e in ctx.enemies:
			if G.flat_dist(p, e.global_position) > cast_range * G.U + e.radius:
				continue
			var aim: Vector3 = ctx.predict(e, cast_time)
			var n := _count(ctx, p, aim)
			if n > best_n:
				best_n = n
				best_aim = aim
		return [best_n, best_aim]

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var ready := AnnieUtil.stun_ready(o)
		var bc := best_cone(ctx)
		var best_n: int = bc[0]
		var best_aim: Vector3 = bc[1]
		if best_n > 0:
			if not ready or best_n >= 2:
				return make_target(best_aim, null)
			# single target with the stun up: only if Tibbers isn't available to carry it
			if not AnnieUtil.hold_for_r(o, ctx) and (ctx.mode == "fight" or ctx.in_danger()):
				return make_target(best_aim, null)
		if ready:
			var fl = AnnieUtil.flash_of(o)
			# flash-W engage when R is down
			if fl != null and not AnnieUtil.r_up(o) and ctx.mode == "fight" and o.hp_ratio() > 0.5 and not ctx.allies.is_empty():
				var pt: Vector3 = ctx.best_cluster_point(cast_range * G.U + 3.5, 1.8, 2)
				if pt != Vector3.INF:
					var d := G.flat_dist(p, pt)
					if d > cast_range * G.U * 0.8 and d < cast_range * G.U + 3.5:
						var step := minf(d - 3.0, 4.0)
						if fl.try_cast({"pos": p + G.flat_dir(p, pt) * step, "dir": G.flat_dir(p, pt)}):
							return make_target(pt, null)
			return HOLD
		# wave clear (also charges Pyromania)
		if ctx.enemies.is_empty() and o.mana > o.stats.max_mana * 0.5 and ctx.enemy_minions.size() >= 3:
			for mn in ctx.enemy_minions:
				if G.flat_dist(p, mn.global_position) > cast_range * G.U * 0.9:
					continue
				var cnt := K.enemies_cone(self, p, G.flat_dir(p, mn.global_position), cast_range, ANGLE).size()
				if cnt >= 3:
					return make_target(mn.global_position, null)
		return HOLD


# ===================================================================== E
class MoltenShield extends KAbility:
	func _init() -> void:
		target_type = Target.UNIT
		target_side = Side.ALLY_OR_SELF
		indicator = Ind.RANGE
		cast_range = 800.0
		cast_time = 0.0
		anim = "spell3"
		anim_lock = 0.35

	func in_cast_range(t: Dictionary) -> bool:
		var u = t.get("unit")
		if u == null:
			return true
		return G.flat_dist(owner.global_position, u.global_position) <= (cast_range + dv("CastRangeGenerosity", 225.0)) * G.U + owner.radius + u.radius

	func execute(t: Dictionary) -> void:
		var u = t.get("unit")
		if u == null or not is_instance_valid(u) or u.dead:
			u = owner
		apply_to(u)
		notify_cast(t)

	func apply_to(u) -> void:
		var o = owner
		var dur := dv("ShieldDuration", 3.0)
		u.remove_buffs_by_id("annie_e")
		# same as K.shield, without the generic bubble (League's E_buf draws the shield)
		Combat.shield(o, u, dv("ShieldAmount") + 0.4 * ap(), dur, {"id": "annie_e"})
		var b := MoltenShieldBuff.new()
		b.duration = dur
		b.remaining = dur
		b.annie = o
		b.ab = self
		b.reflect = dv("DamageReflection") + 0.4 * ap()
		# live Molten Shield has no damage reduction (DamageReduction is a leftover of the old E; the
		# tooltip only lists shield, decaying move speed and the damage return)
		b.icon = icon
		# the League buff origin sits ~0.5 m above the ground (its ground parts are offset downward)
		b.vfx = LolVfx.attach(u, "Annie_Base_E_Tibbers_buf" if u is Tibbers else "Annie_Base_E_buf", {"height": 0.5})
		u.add_buff(b, o)
		# MoveSpeedCalc = lerpByLevel(0.2 -> 0.5) (the per-rank MovementSpeed values are unused by the tooltip)
		K.haste(u, lerpf(0.2, 0.5, (o.level - 1) / 17.0), dv("MovementSpeedDuration", 1.5), o, true, "annie_e_ms")

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var rng := (cast_range + 150.0) * G.U
		var now: float = o.match_ref.time
		# 1) protect a champion that is being focused (allies first, then self)
		var best: Unit = null
		var best_s := 0.0
		for a in ctx.allies + [o]:
			if a.dead or G.flat_dist(o.global_position, a.global_position) > rng + a.radius:
				continue
			var threat: int = ctx.count_enemies_near(a.global_position, 5.0)
			var hurt: bool = now - a.last_hit_by_champion_time < 1.0
			if threat <= 0 or not hurt:
				continue
			var s: float = (1.0 - a.hp_ratio()) * 2.0 + threat * 0.4 + (0.3 if a != o else 0.0)
			if a.hp_ratio() < 0.75 and s > best_s:
				best_s = s
				best = a
		if best != null:
			return {"unit": best, "pos": best.global_position}
		# 2) charge the stun right before a fight (classic E-stacking)
		var st := AnnieUtil.stacks(o)
		if st == 3 and ctx.count_enemies_near(o.global_position, 11.0) > 0:
			return {"unit": o, "pos": o.global_position}
		# 3) stack Pyromania while safe
		if st < 4 and ctx.enemies.is_empty() and o.mana > o.stats.max_mana * 0.7:
			return {"unit": o, "pos": o.global_position}
		# 4) speed to escape
		if ctx.mode == "retreat" and ctx.in_danger():
			return {"unit": o, "pos": o.global_position}
		return HOLD


## FxBuff: the E_buf shield visual ends when the shield breaks.
class MoltenShieldBuff extends K.FxBuff:
	var annie = null
	var ab = null
	var reflect := 0.0
	var used := false

	func _init() -> void:
		id = "annie_e"
		display_name = "Molten Shield"

	func on_tick(u, _dt: float) -> void:
		for s in u.shields:
			if s.id == "annie_e":
				return
		removed = true

	func on_damage_taken(info) -> void:
		if used or removed:
			return
		var src = info.source
		if src == null or not is_instance_valid(src) or src.dead or src.team == owner.team:
			return
		if not (info.is_attack or info.is_spell) or info.is_dot or info.is_reflect:
			return
		if src.kind in [G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS]:
			return
		used = true
		var dealer = annie if annie != null and is_instance_valid(annie) else owner
		# League E_tar plays on the attacker through the generic spell-hit hook
		Combat.deal(dealer, src, reflect, G.DmgType.MAGIC, {"is_spell": true, "is_reflect": true, "ability": ab, "tag": "annie_e"})


# ===================================================================== R
class SummonTibbers extends KAbility:
	var tibbers = null
	var base_cast_time := 0.25
	var cmd_lock := 0.0

	func _init() -> void:
		target_type = Target.POINT
		indicator = Ind.CIRCLE
		ind_radius = 250.0
		cast_range = 600.0
		cast_time = 0.25
		anim = "spell4"
		anim_lock = 0.6

	func tibbers_alive() -> bool:
		return tibbers != null and is_instance_valid(tibbers) and not tibbers.dead

	## The cooldown already runs from the summon; recasts only command Tibbers.
	func on_recast_expired() -> void:
		pass

	func clamp_point_to_range() -> bool:
		return not tibbers_alive()

	func in_cast_range(t: Dictionary) -> bool:
		if tibbers_alive():
			return true
		return super.in_cast_range(t)

	func on_tick(dt: float) -> void:
		cmd_lock = maxf(0.0, cmd_lock - dt)
		var cmd := tibbers_alive()
		if not cmd and recast_window > 0.0:
			recast_window = 0.0
		indicator = Ind.NONE if cmd else Ind.CIRCLE
		cast_time = 0.0 if cmd else base_cast_time
		anim = "" if cmd else "spell4"
		face_target = not cmd

	func make_target(world_pos: Vector3, hovered = null) -> Dictionary:
		var t := super.make_target(world_pos, hovered)
		if tibbers_alive() and hovered != null and is_instance_valid(hovered) and not hovered.dead \
				and hovered.team != owner.team and hovered.is_targetable_by(owner.team) \
				and hovered.kind in [G.Kind.CHAMPION, G.Kind.MINION, G.Kind.SUMMON]:
			t.unit = hovered
			t.pos = hovered.global_position
		return t

	func execute(t: Dictionary) -> void:
		if tibbers_alive():
			# recast: order Tibbers around (not a spell cast: no Pyromania stack, no on-cast procs)
			var u = t.get("unit")
			if u != null and is_instance_valid(u) and not u.dead and u.team != owner.team:
				tibbers.command_attack(u)
			else:
				tibbers.command_move(t.pos)
			return
		_summon(t.pos)
		notify_cast(t)

	func _summon(pos: Vector3) -> void:
		var o = owner
		var m = o.match_ref
		var stun := AnnieUtil.consume_stun(o)
		var dmg := dv("InitialDamage") + 0.75 * ap()
		LolVfx.spawn(m, "Annie_Base_R_cas", AnnieUtil.ground_at(m, pos), {"dir": G.flat_dir(o.global_position, pos)})
		for u in K.enemies_circle(self, pos, ind_radius):
			hit(u, dmg, G.DmgType.MAGIC, {"is_aoe": true, "tag": "r"})
			if stun > 0.0:
				K.stun(u, stun, o)
		AnnieUtil.shake(o, 0.4)
		var lvl: int = o.level
		var s = Tibbers.new()
		# League AnnieR calcs (CommunityDragon annie.bin.json): TibbersTotalHP = breakpoints(1150; +50/lvl from 7,
		# +250/lvl from 11, +300/lvl from 16) * TibbersModeSpecificHPMod + 50% AP -> 1150 (L6) .. 3500 (L18);
		# TibbersTotalResists = 30, +5/lvl from 7 -> 90 (L18). Attack range 150 (wiki Summon: Tibbers).
		var res := K.level_breakpoints(lvl, 30.0, 0.0, [[7, 5.0]])
		var hp := K.level_breakpoints(lvl, 1150.0, 0.0, [[7, 50.0], [11, 250.0], [16, 300.0]])
		s.setup(o, "Tibbers", {
			"hp": hp * dv("TibbersModeSpecificHPMod", 1.0) + 0.5 * ap(),
			"ad": dv("TibbersAttackDamage") + dv("TibbersAttackAPRatio", 0.1) * ap(),
			"armor": res, "mr": res, "as": 0.625, "range": 150.0, "ms": 350.0 + dv("TibbersBonusMS"),
			"radius": 0.9, "height": 3.2, "model": "AnnieTibbers", "lifetime": dv("TibbersLifetime", 45.0), "scale": 1.15,
		})
		s.annie = o
		s.r_ab = self
		m.add_unit(s, pos)
		s.face_toward(pos + o.facing, 1000.0)
		tibbers = s
		recast_window = s.lifetime
		s.setup_visuals()
		var self_ref := self
		s.died.connect(func(_u, _k): self_ref._on_tibbers_gone())
		s.on_expire = func(_u): self_ref._on_tibbers_gone()
		enrage(dv("EnrageDuration", 3.0), false)
		var e_ab = o.abilities[2]
		if e_ab != null and e_ab.level > 0:
			e_ab.apply_to(s)

	func _on_tibbers_gone() -> void:
		tibbers = null
		recast_window = 0.0

	func enrage(dur: float, avenger: bool) -> void:
		if not tibbers_alive():
			return
		var tb = tibbers
		tb.remove_buffs_by_id("tibbers_enrage")
		var b := EnrageBuff.new()
		b.duration = dur
		b.remaining = dur
		b.as_bonus = 2.75
		b.ms_bonus = dv("MovespeedBurst", 1.0)
		b.decay_rate = absf(dv("TibbersAttackSpeedDecay", -0.1))
		# League frenzy: speed streaks / scorched ground + burning fists
		var fx := Node3D.new()
		tb.add_child(fx)
		LolVfx.attach(fx, "Annie_Base_R_Tibbers_Frenzy_buf_01", {"loop": true, "height": 0.4})
		LolVfx.attach(fx, "Annie_Base_TibbersFrenzyBuff", {"loop": true, "height": tb.height * 0.45})
		b.vfx = fx
		tb.add_buff(b, owner)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if tibbers_alive():
			return _ai_command(ctx)
		var p: Vector3 = o.global_position
		var rng := range_m()
		var rad := ind_radius * G.U
		var ready := AnnieUtil.stun_ready(o)
		var dmg := dv("InitialDamage") + 0.75 * ap()
		# 1) multi-champion hit (ideal with the stun up)
		var pt: Vector3 = ctx.best_cluster_point(rng, rad * 0.9, 2)
		if pt != Vector3.INF and G.flat_dist(p, pt) <= rng + rad * 0.5:
			if ready or ctx.mode == "fight":
				return make_target(pt, null)
		# 2) flash-R engage onto a group with the stun ready
		if ready and o.hp_ratio() > 0.45 and (ctx.mode == "fight" or ctx.allies.size() >= 1):
			var fl = AnnieUtil.flash_of(o)
			if fl != null:
				var fpt: Vector3 = ctx.best_cluster_point(rng + 3.8, rad * 0.9, 2)
				if fpt != Vector3.INF:
					var d := G.flat_dist(p, fpt)
					if d > rng + rad * 0.5 and d < rng + 3.8 and ctx.count_enemies_near(fpt, 6.0) <= ctx.allies.size() + 2:
						var step := minf(d - rng + 1.0, 4.0)
						if fl.try_cast({"pos": p + G.flat_dir(p, fpt) * step, "dir": G.flat_dir(p, fpt)}):
							return make_target(fpt, null)
		# 3) burst a single champion: kill threat or committed fight
		var t: Unit = ctx.best_enemy_in_range(rng + rad * 0.5)
		if t != null and ready and ctx.mode == "fight" and not t.has_cc_immunity():
			return make_target(ctx.predict(t, cast_time), null)
		if t != null:
			var q_ab = o.abilities[0]
			var combo := AnnieUtil.est(o, t, dmg + (q_ab.damage() if q_ab != null and q_ab.level > 0 else 0.0))
			if combo >= t.hp + t.total_shield() and t.hp_ratio() > 0.08:
				return make_target(ctx.predict(t, cast_time), null)
			if ctx.mode == "fight" and t.hp_ratio() < 0.5 and ctx.count_enemies_near(p, 12.0) <= 2:
				return make_target(ctx.predict(t, cast_time), null)
			# 4) self-peel: drop Tibbers on a diver
			if ctx.in_danger() and G.flat_dist(p, t.global_position) < 4.0:
				return make_target(t.global_position, null)
		return HOLD

	func _ai_command(ctx) -> Dictionary:
		if cmd_lock > 0.0:
			return HOLD
		var tb = tibbers
		var o = owner
		var want: Unit = null
		if ctx.mode == "retreat" and not ctx.enemies.is_empty():
			# keep Tibbers between Annie and her chasers
			var nd := INF
			for e in ctx.enemies:
				var d := G.flat_dist(o.global_position, e.global_position)
				if d < nd and d < 8.0:
					nd = d
					want = e
		elif ctx.focus != null and is_instance_valid(ctx.focus) and not ctx.focus.dead:
			want = ctx.focus
		if want == null or G.flat_dist(tb.global_position, want.global_position) > 10.0:
			return HOLD
		if tb.controlled_target == want:
			return HOLD
		cmd_lock = 1.0
		return {"pos": want.global_position, "unit": want, "dir": G.flat_dir(o.global_position, want.global_position)}


## R passive: magic penetration.
class TibbersPen extends Effect:
	var r: Ability

	func _init(p_r) -> void:
		r = p_r
		id = "annie_r_pen"
		hidden = true

	func get_stat_mods() -> Dictionary:
		if r == null or r.level <= 0:
			return {}
		return {"magic_pen%": r.dv("RPercentPenBuff", 0.1)}


class EnrageBuff extends Buff:
	var as_bonus := 2.75
	var ms_bonus := 1.0
	var decay_rate := 0.1
	var attacks := 0

	func _init() -> void:
		id = "tibbers_enrage"
		display_name = "Enraged"

	func get_stat_mods() -> Dictionary:
		var k := clampf(remaining / maxf(duration, 0.01), 0.0, 1.0)
		return {"as": maxf(0.0, as_bonus * k - decay_rate * attacks), "ms%": ms_bonus * k}

	func on_attack_launch(_t) -> void:
		attacks += 1


## Tibbers' basic attacks deal magic damage scaling with Annie's AP.
class TibbersFists extends Effect:
	var r_ab = null

	func _init(p_r) -> void:
		r_ab = p_r
		id = "tibbers_fists"
		hidden = true

	func on_pre_damage_dealt(info) -> void:
		if info.is_attack and r_ab != null and is_instance_valid(r_ab.owner):
			info.type = G.DmgType.MAGIC
			info.amount = r_ab.dv("TibbersAttackDamage") + r_ab.dv("TibbersAttackAPRatio", 0.1) * r_ab.owner.stats.ap
			info.is_pet = true

	func on_attack_hit(target, _info) -> void:
		if owner.match_ref != null and is_instance_valid(target):
			Vfx.hit_spark(owner.match_ref, target.global_position + Vector3(0, 1.0, 0), FIRE, 1.0)


class Tibbers extends Summon:
	var annie = null
	var r_ab = null
	var move_cmd_until := 0.0
	var move_goal_cmd := Vector3.ZERO
	var burn_acc := 0.0
	var fx: Array = []

	func setup_visuals() -> void:
		add_effect(TibbersFists.new(r_ab))
		fx.append(Vfx.aura(self, FIRE, 3.0, lifetime + 3.0, 0.06))
		var flames := VfxNode.new()
		add_child(flames)
		flames.position.y = 0.4
		var e := Vfx.emitter(FIRE, 50, 0.9, 0.7, {"radius": 1.0, "dir": Vector3.UP, "spread": 20.0, "vmin": 0.8, "vmax": 2.4, "energy": 1.5,
				"gravity": Vector3(0, 1.0, 0)})
		flames.add_child(e)
		flames.trails.append(e)
		var e2 := Vfx.emitter(EMBER, 24, 1.2, 0.18, {"radius": 2.6, "dir": Vector3.UP, "spread": 10.0, "vmin": 0.6, "vmax": 1.6,
				"tex": Vfx.spark_texture()})
		flames.add_child(e2)
		flames.trails.append(e2)
		var l := Vfx.light(FIRE, 2.5, 7.0)
		l.position.y = 1.2
		flames.add_child(l)
		fx.append(flames)
		# drop from the sky
		airborne_height = 6.0
		var tw := create_tween()
		tw.tween_property(self, "airborne_height", 0.0, 0.22).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		play_anim("idle1_in", 1.0, 0.0)
		anim_lock = 0.7

	func command_attack(u: Unit) -> void:
		move_cmd_until = 0.0
		controlled_target = u
		issue_attack(u)
		if match_ref != null:
			Vfx.ring(match_ref, u.global_position, FIRE, 1.2, 0.35, 0.15, 0.1)

	func command_move(pos: Vector3) -> void:
		controlled_target = null
		move_goal_cmd = pos
		issue_move(pos)
		move_cmd_until = match_ref.time + G.flat_dist(global_position, pos) / maxf(stats.move_speed * G.U, 1.0) + 0.4
		Vfx.ring(match_ref, pos, FIRE_HOT, 0.9, 0.35, 0.15, 0.1)

	func think(dt: float) -> void:
		_burn(dt)
		if move_cmd_until > match_ref.time:
			lifetime -= dt
			if lifetime <= 0.0:
				_expire()
				return
			if G.flat_dist(global_position, move_goal_cmd) < 0.8 or not moving:
				move_cmd_until = 0.0
			return
		super.think(dt)

	## League (wiki Summon: Tibbers): the flame aura burns enemies within 350 units every 0.25 s for a quarter of
	## AuraDamage (+4% AP) per second.
	const AURA_RADIUS := 350.0
	const AURA_TICK := 0.25
	var burn_n := 0

	func _burn(dt: float) -> void:
		burn_acc += dt
		if burn_acc < AURA_TICK:
			return
		burn_acc -= AURA_TICK
		burn_n += 1
		if r_ab == null or annie == null or not is_instance_valid(annie):
			return
		var dps: float = r_ab.dv("AuraDamage") + 0.04 * annie.stats.ap
		var sparks: bool = burn_n % 2 == 0   # embers at 2 Hz is plenty
		for u in match_ref.enemies_in_radius(team, global_position, AURA_RADIUS * G.U):
			Combat.deal(annie, u, dps * AURA_TICK, G.DmgType.MAGIC, {"is_spell": true, "is_aoe": true, "is_dot": true,
					"ability": r_ab, "tag": "tibbers_aura"})
			if sparks and u.kind == G.Kind.CHAMPION:
				Vfx.hit_spark(match_ref, u.global_position + Vector3(0, 0.9, 0), EMBER, 0.45)

	func _fade_fx() -> void:
		for f in fx:
			if f != null and is_instance_valid(f):
				f.detach_and_fade()
		fx.clear()

	func on_died(killer) -> void:
		_fade_fx()
		super.on_died(killer)

	func _expire() -> void:
		_fade_fx()
		if match_ref != null:
			Vfx.burst(match_ref, global_position + Vector3(0, 1.2, 0), EMBER, 1.5, {"sparks": 30})
		super._expire()
