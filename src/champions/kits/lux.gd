extends ChampionKit
## Lux, the Lady of Luminosity.

const LIGHT := Color(1.0, 0.93, 0.62)
const WHITE := Color(1.0, 1.0, 0.95)
const PRISM := Color(1.0, 0.5, 0.9)
const SKY := Color(0.55, 0.85, 1.0)


func build_kit() -> void:
	c.attack_missile_speed = 1600.0
	c.attack_color = Color(1.0, 0.75, 0.95)
	c.role = "mage"
	c.level_order = "EQWEERQEQEREQQWWRW"
	var pd: Dictionary = spell("LuxIlluminationPassive").get("data_values", {})
	c.passive = Illumination.new(pd)
	c.add_effect(c.passive)
	var q = init_ability(LightBinding.new(), "Q")
	if q.cooldowns.size() <= 1 and float(q.cooldowns[0]) == 10.0:
		q.cooldowns = [11.0, 10.5, 10.0, 9.5, 9.0]   # not present in the extracted data (live values)
	c.abilities[0] = q
	c.abilities[1] = init_ability(PrismaticBarrier.new(), "W")
	c.abilities[2] = init_ability(LucentSingularity.new(), "E")
	var r = init_ability(FinalSpark.new(), "R")
	r.cast_range = 3340.0
	r.ind_length = 3340.0
	# ARAM (CommunityDragon lux.bin.json LuxR cooldown override ARAM; wiki ARAM page): 80 / 70 / 60 s
	K.aram_cooldowns(r, [80.0, 80.0, 70.0, 60.0, 60.0, 60.0, 60.0], true)
	c.abilities[3] = r
	c.add_effect(BotLeveler.new())


func ai_tuning() -> Dictionary:
	return {"aggression": 0.45}


## League VFX: the Q prison is attached by the kit (it lasts the root), E hits use E_tar_hit.
func vfx_map() -> Dictionary:
	return {"Q_tar": "", "E_tar": "Lux_Base_E_tar_hit", "BA_crit_tar": "Lux_Base_BA_tar_crit"}


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

	func illum():
		return owner.passive

	func enemy_champs() -> Array:
		var o = owner
		return o.match_ref.champions.filter(func(e): return e.team != o.team and not e.dead and e.is_targetable_by(o.team))


class LuxFx extends RefCounted:
	static func at_unit(u, name: String, src = null) -> LolVfx:
		if u == null or not is_instance_valid(u) or u.match_ref == null:
			return null
		var d := Vector3.ZERO
		if src != null and is_instance_valid(src):
			d = G.flat_dir(src.global_position, u.global_position)
		return LolVfx.spawn(u.match_ref, name, u.global_position + Vector3(0, u.height * 0.5, 0), {"dir": d})

	## Missile visual made of a League system plus its child system.
	static func pair(main: String, child: String) -> LolVfx:
		var v := LolVfx.make(main, {"loop": true})
		if v != null:
			var ch := LolVfx.make(child, {"loop": true})
			if ch != null:
				v.add_child(ch)
		return v

	## Enemy (red) / allied (green) colored variant, relative to the local player.
	static func team_variant(o, red: String, green: String) -> String:
		return red if G.player != null and o.team != G.player.team else green


# ===================================================================== passive
class Illumination extends Effect:
	var dur := 6.0
	var ap_ratio := 0.35

	func _init(pd: Dictionary) -> void:
		id = "lux_passive"
		display_name = "Illumination"
		dur = float(pd.get("DebuffDuration", 6.0))
		ap_ratio = float(pd.get("APRatio", 0.35))

	## League: 30 - 200 by level (+35% AP).
	func damage() -> float:
		return 20.0 + 10.0 * owner.level + ap_ratio * owner.stats.ap

	func mark(u) -> void:
		if u == null or not is_instance_valid(u) or u.dead:
			return
		var b = u.find_buff("lux_illum", owner)
		if b != null:
			b.remaining = dur
			_mark_fx(u, b)
			return
		var nb: Buff = K.buff(u, "lux_illum", dur, {}, owner, {"name": "Illumination", "debuff": true})
		if nb != null:
			_mark_fx(u, nb)

	## League Illumination debuff (restarted when the mark is refreshed; freed with the buff).
	func _mark_fx(u, b) -> void:
		if b.vfx != null and is_instance_valid(b.vfx):
			b.vfx.queue_free()
		b.vfx = LolVfx.attach(u, "Lux_Base_P_debuff", {"height": (u.height if u.kind == G.Kind.CHAMPION else 1.6) * 0.55})

	## Consume the mark on `u` for bonus magic damage. Returns true if one was consumed.
	func detonate(u) -> bool:
		if u == null or not is_instance_valid(u) or u.dead:
			return false
		var b = u.find_buff("lux_illum", owner)
		if b == null:
			return false
		u.remove_buff(b)
		Combat.deal(owner, u, damage(), G.DmgType.MAGIC, {"is_proc": true, "tag": "lux_passive"})
		LuxFx.at_unit(u, "Lux_Base_P_tar", owner)
		return true

	func on_attack_hit(target, _info) -> void:
		detonate(target)

	func on_takedown(victim) -> void:
		var r = owner.abilities[3]
		if r != null and r.has_method("note_takedown"):
			r.note_takedown(victim)


# ===================================================================== Q
class LightBinding extends KitAbility:
	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 140.0
		cast_time = 0.25
		anim = "spell1"
		anim_lock = 0.4

	func damage() -> float:
		return dv("BaseDamage") + dv("APRatio", 0.75) * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var dmg := damage()
		var root_t := dv("RootDuration", 2.0)
		var self_ref := self
		K.line_missile(self, K.cast_pos(o, 1.2), t.dir, 1200.0, 1240.0, {
			"width": 70.0, "max_hits": 2, "lol": "Lux_Base_Q_mis", "height": 1.2,
			"on_hit": func(_mi, u): self_ref._bind(u, dmg, root_t),
		})
		notify_cast(t)

	func _bind(u: Unit, dmg: float, root_t: float) -> void:
		var o = owner
		if not is_instance_valid(o) or not is_instance_valid(u):
			return
		var p = illum()
		hit(u, dmg, G.DmgType.MAGIC, {"tag": "q"})
		var b := K.root(u, root_t, o, LIGHT)
		# League light prison on the target (replaces the generic root ring; freed with the root)
		var fx := LolVfx.attach(u, "Lux_Base_Q_tar", {"height": 0.05, "dir": G.flat_dir(o.global_position, u.global_position)})
		if b != null and fx != null:
			if b.vfx != null and is_instance_valid(b.vfx):
				b.vfx.queue_free()
			b.vfx = fx
		elif fx != null:
			fx.queue_free()   # root resisted (unstoppable): no prison
		if p != null:
			p.mark(u)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var rng := 11.8
		var best: Unit = null
		var best_s := -INF
		var best_aim := Vector3.ZERO
		for e in ctx.enemies:
			if e.has_cc_immunity():
				continue
			var d := G.flat_dist(o.global_position, e.global_position)
			if d > rng:
				continue
			var aim: Vector3 = ctx.predict(e, cast_time + d / 12.0)
			if G.flat_dist(o.global_position, aim) > rng:
				continue
			# the binding passes through one unit, so a single minion in front is fine
			var block := 0
			for mn in ctx.enemy_minions:
				if G.flat_dist(o.global_position, mn.global_position) < d and NavGrid._dist_to_segment(mn.global_position, o.global_position, aim) <= 0.7 + mn.radius:
					block += 1
			if block > 1:
				continue
			var s: float = (1.0 - e.hp_ratio()) * 2.0 - d * 0.1
			if e.stats.attack_range < 300.0 and o.edge_dist(e) < 4.0:
				s += 4.0   # peel divers
			if e == ctx.focus:
				s += 1.0
			if s > best_s:
				best_s = s
				best = e
				best_aim = aim
		if best == null:
			return skip()
		return ctx.aim_at(best_aim, self)


# ===================================================================== W
class PrismaticBarrier extends KitAbility:
	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 220.0
		cast_time = 0.25
		anim = "spell2"
		anim_lock = 0.35

	func shield_amount() -> float:
		return dv("BaseShieldAmount") + dv("APRatio", 0.4) * ap()

	func _shield(u) -> void:
		if u == null or not is_instance_valid(u) or u.dead or u.kind != G.Kind.CHAMPION:
			return
		# same as K.shield without the generic bubble: League's W_tar_shield draws it
		var dur := dv("ShieldDuration", 2.5)
		var sh: Dictionary = Combat.shield(owner, u, shield_amount(), dur, {"id": ""})
		var fx := LolVfx.attach(u, "Lux_Base_W_tar_shield", {"height": u.height * 0.5})
		if fx != null and u.match_ref != null:
			u.match_ref.add_ticker(dur + 0.1, func(_dt) -> bool:
				var alive := false
				if is_instance_valid(u) and not u.dead:
					for s2 in u.shields:
						if is_same(s2, sh):
							alive = true
				if not alive:
					if is_instance_valid(fx):
						fx.stop()
					return false
				return true)
			u.match_ref.after(dur + 0.05, func():
				if is_instance_valid(fx):
					fx.stop())

	func execute(t: Dictionary) -> void:
		var o = owner
		var self_ref := self
		_shield(o)
		var mi := K.line_missile(self, K.cast_pos(o, 1.2), t.dir, 2200.0, cast_range, {
			"width": 110.0, "pierce": true, "visual": LuxFx.pair("Lux_Base_W_mis", "Lux_Base_W_mis_child"), "keep_visual": true, "height": 1.2,
			"on_hit": func(_m, u): self_ref._shield(u),
			"on_end": func(_m, pos): self_ref._return(pos),
		})
		_allies_only(mi)
		notify_cast(t)

	func _allies_only(mi: Missile) -> void:
		mi.hits_allies = true
		mi.hits_champions = false
		mi.hits_minions = false
		mi.hits_summons = false
		mi.blockable = false

	func _return(pos: Vector3) -> void:
		var o = owner
		if not is_instance_valid(o) or o.dead:
			return
		var mi := Missile.new()
		mi.ability = self
		mi.setup_homing(o, pos, o, 1400.0 * G.U)
		mi.mode = Missile.Mode.FOLLOW
		mi.accel = 1500.0 * G.U
		mi.max_speed = 2400.0 * G.U
		mi.collides = true
		mi.pierce = true
		mi.width = 110.0 * G.U
		mi.height = 1.2
		mi.visual = LuxFx.pair("Lux_Base_W_mis_return", "Lux_Base_W_mis_return_child")
		mi.custom["keep_visual"] = true
		_allies_only(mi)
		var self_ref := self
		mi.on_hit = func(_m, u): self_ref._shield(u)
		mi.on_move = func(m2, _dt):
			if G.flat_dist(m2.global_position, o.global_position) < 0.7:
				self_ref._shield(o)
				m2.finish(o.global_position)
		o.match_ref.add_missile(mi, pos)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var rng := range_m()
		var threatened := func(u) -> bool:
			return ctx.count_enemies_near(u.global_position, 6.0) > 0 and (u.hp_ratio() < 0.75 or u.last_damaged_time > o.match_ref.time - 1.0)
		var best_dir := Vector3.ZERO
		var best_n := 0
		for a in ctx.allies:
			var d := G.flat_dist(p, a.global_position)
			if d > rng or d < 0.5 or not threatened.call(a):
				continue
			var dir := G.flat_dir(p, a.global_position)
			var n := 1
			for b in ctx.allies:
				if b != a and threatened.call(b) and NavGrid._dist_to_segment(b.global_position, p, p + dir * rng) <= 1.1 + b.radius:
					n += 1
			if n > best_n:
				best_n = n
				best_dir = dir
		if best_dir != Vector3.ZERO and (best_n >= 2 or threatened.call(o) or ctx.mode == "fight"):
			return {"pos": p + best_dir * 5.0, "dir": best_dir, "unit": null}
		if threatened.call(o) and o.hp_ratio() < 0.7:
			var away: Vector3 = G.flat_dir(ctx.enemies[0].global_position, p) if not ctx.enemies.is_empty() else o.facing
			return {"pos": p + away * 5.0, "dir": away, "unit": null}
		return skip()


# ===================================================================== E
class LucentSingularity extends KitAbility:
	var zone := {}          ## {pos, landed, node, detonate_on_land}

	func _init() -> void:
		target_type = Target.POINT
		indicator = Ind.CIRCLE
		ind_radius = 310.0
		cast_time = 0.25
		anim = "spell3"
		anim_lock = 0.35

	## League: Lucent Singularity's cooldown starts on cast; the recast is free.
	func damage() -> float:
		return dv("BaseDamage") + 0.8 * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		if recast_window > 0.0 and not zone.is_empty():
			# recast: detonate now (or as soon as the orb lands)
			if zone.landed:
				_detonate()
			else:
				zone.detonate_on_land = true
			notify_cast(t)
			return
		var pos := ground(t.pos)
		var from: Vector3 = K.cast_pos(o, 1.2)
		var fly := maxf(0.15, G.flat_dist(from, pos) / 13.0)
		zone = {"pos": pos, "landed": false, "node": null, "detonate_on_land": false}
		var st := zone
		recast_window = fly + dv("SlowZoneDuration", 5.0)
		var self_ref := self
		K.arc_missile(self, from, pos, fly, func(_mi, _p): self_ref._land(st), {"lol": "Lux_Base_E_mis", "arc": 1.2})
		notify_cast(t)

	func _land(st: Dictionary) -> void:
		var o = owner
		if not is_instance_valid(o) or not is_same(st, zone):
			return
		var m = o.match_ref
		var pos: Vector3 = st.pos
		var r_m := ind_radius * G.U
		st.landed = true
		# League singularity zone (team colored, includes its radius ring)
		st.node = LolVfx.spawn(m, LuxFx.team_variant(o, "Lux_Base_E_tar_aoe_red", "Lux_Base_E_tar_aoe_green"), pos + Vector3(0, 0.05, 0),
				{"dir": G.flat_dir(o.global_position, pos)})
		var slow := dv("SlowPercent", 25.0) / 100.0
		m.add_ticker(dv("SlowZoneDuration", 5.0) + 0.1, func(_dt: float) -> bool:
			if not is_same(st, zone) or not is_instance_valid(o):
				return false
			for u in m.enemies_in_radius(o.team, pos, r_m):
				K.slow(u, slow, 0.25, o, false, "lux_e_slow")
			return true)
		if st.detonate_on_land:
			_detonate()

	func on_recast_expired() -> void:
		if not zone.is_empty():
			_detonate()

	func _detonate() -> void:
		var o = owner
		if zone.is_empty():
			return
		var st := zone
		zone = {}
		recast_window = 0.0
		if not is_instance_valid(o):
			return
		var m = o.match_ref
		var pos: Vector3 = st.pos
		var r_m := ind_radius * G.U
		var n = st.node
		if n != null and is_instance_valid(n):
			n.queue_free()   # the nova replaces the zone at once (its particles would linger for seconds)
		var p = illum()
		var dmg := damage()
		var slow := dv("SlowPercent", 25.0) / 100.0
		for u in m.enemies_in_radius(o.team, pos, r_m):
			hit(u, dmg, G.DmgType.MAGIC, {"tag": "e", "is_aoe": true})
			K.slow(u, slow, dv("SlowLingerDuration", 1.0), o, false, "lux_e_slow")
			if p != null:
				p.mark(u)
		LolVfx.spawn(m, "Lux_Base_E_tar_nova", pos + Vector3(0, 1.0, 0), {"dir": G.flat_dir(o.global_position, pos)})

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var r_m := ind_radius * G.U
		if recast_window > 0.0:
			if zone.is_empty():
				return skip()
			var zp: Vector3 = zone.pos
			# detonate when a champion is inside (or about to walk out), or for a kill on minions late in the zone
			for e in ctx.enemies:
				var d := G.flat_dist(zp, e.global_position)
				if d <= r_m + e.radius * 0.5:
					return {"pos": zp, "dir": G.flat_dir(o.global_position, zp), "unit": null}
			if not zone.landed:
				return skip()
			var minions := 0
			for mn in ctx.enemy_minions:
				if G.flat_dist(zp, mn.global_position) <= r_m:
					minions += 1
			if ctx.enemies.is_empty() and minions >= 3:
				return {"pos": zp, "dir": G.flat_dir(o.global_position, zp), "unit": null}
			return skip()
		var rng := range_m()
		var cp: Vector3 = ctx.best_cluster_point(rng, r_m * 0.9, 2)
		if cp != Vector3.INF:
			return ctx.aim_at(cp, self)
		var t: Unit = ctx.best_enemy_in_range(rng + r_m * 0.5)
		var mana_r: float = o.mana / maxf(o.stats.max_mana, 1.0)
		if t != null and (ctx.mode != "lane" or mana_r > 0.4 or (t.cc & Buff.IMMOBILIZE) != 0):
			return ctx.aim_at(ctx.predict(t, cast_time + 0.6), self)
		if ctx.enemies.is_empty() and mana_r > 0.7:
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
class FinalSpark extends KitAbility:
	var _beam_fx: LolVfx = null
	var _hit_champs := {}     ## champions hit by the last beam
	var _hit_time := -100.0
	var _refunded := false

	## League: a champion takedown within ResetAssistWindow of being hit refunds ResetPercent of the cooldown.
	func note_takedown(victim) -> void:
		if _refunded or not _hit_champs.has(victim) or owner.match_ref == null:
			return
		if owner.match_ref.time - _hit_time > dv("ResetAssistWindow", 1.75):
			return
		_refunded = true
		_hit_champs.clear()
		cd = maxf(0.0, cd - cd_total * dv("ResetPercent", 0.3))

	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 380.0
		cast_time = 1.0
		anim = "spell4"
		anim_lock = 1.3

	func damage() -> float:
		return dv("Damage") + 1.2 * ap()

	## League (wiki Final Spark notes): starting the cast refreshes Illumination marks with less than 1 s left
	## to 1.25 s on enemies within 5000 units, so the 1 s charge-up can still detonate them. The beam then
	## consumes each mark (bonus damage) and applies a fresh one.
	func _extend_marks() -> void:
		var o = owner
		for u in o.match_ref.enemies_in_radius(o.team, o.global_position, 5000.0 * G.U, false):
			var b = u.find_buff("lux_illum", o)
			if b != null and b.remaining < 1.0:
				b.remaining = 1.25

	func begin_cast(t: Dictionary) -> void:
		super(t)
		var o = owner
		var m = o.match_ref
		var dir: Vector3 = t.get("dir", o.facing)
		_extend_marks()
		# League Final Spark: R_cas (wand charge) comes from the generic cast hook; the beam system holds
		# the charge / warning lines (t=0) and the beam itself (delayed by 1 s = the cast time).
		# Its origin is at Lux's wand height (its ground parts are offset by -1.6 m).
		_beam_fx = LolVfx.spawn(m, "Lux_Base_R_mis_beam", o.global_position, {"dir": dir, "height": 1.6, "length": cast_range * G.U})

	## Drop the League beam if the cast gets interrupted before it fires.
	func on_tick(_dt: float) -> void:
		if _beam_fx != null and (not is_instance_valid(_beam_fx) or owner.casting.get("ability") != self):
			if is_instance_valid(_beam_fx):
				_beam_fx.queue_free()
			_beam_fx = null

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var dir: Vector3 = t.dir
		var from: Vector3 = o.global_position + Vector3(0, 1.1, 0) + dir * 0.6
		var to: Vector3 = from + dir * cast_range * G.U
		_beam_fx = null   # fired: the League beam plays out on its own
		var dmg := damage()
		var p = illum()
		_hit_champs.clear()
		_refunded = false
		_hit_time = o.match_ref.time
		for u in K.enemies_line(self, o.global_position, o.global_position + dir * cast_range * G.U, ind_width):
			if u.kind == G.Kind.CHAMPION:
				_hit_champs[u] = true
			if p != null:
				p.detonate(u)
			hit(u, dmg, G.DmgType.MAGIC, {"tag": "r", "is_aoe": true})
			if p != null and not u.dead:
				p.mark(u)
		if m.camera_rig != null:
			var near_player: bool = G.player != null and NavGrid._dist_to_segment(G.player.global_position, from, to) < 12.0
			m.camera_rig.shake(0.4 if o == G.player or near_player else 0.1)
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var from: Vector3 = o.global_position
		var rng := cast_range * G.U - 1.0
		var hw := ind_width * 0.5 * G.U
		var champs := enemy_champs()
		var p = illum()
		var best_s := -INF
		var best_aim := Vector3.ZERO
		for e in champs:
			var d := G.flat_dist(from, e.global_position)
			if d > rng:
				continue
			var aim: Vector3 = e.global_position if (e.cc & Buff.BLOCK_MOVE) != 0 else e.global_position + e.velocity * cast_time * 0.8
			var dir := G.flat_dir(from, aim)
			var to := from + dir * rng
			var n := 0
			var kill := false
			for e2 in champs:
				var lead: Vector3 = e2.global_position + (e2.velocity * cast_time * 0.8 if (e2.cc & Buff.BLOCK_MOVE) == 0 else Vector3.ZERO)
				if NavGrid._dist_to_segment(lead, from, to) <= hw + e2.radius * 0.5:
					n += 1
					var dmg := damage() * Combat.resist_multiplier(e2.stats.mr, o, false)
					if p != null and e2.find_buff("lux_illum", o) != null:
						dmg += p.damage() * Combat.resist_multiplier(e2.stats.mr, o, false)
					if dmg >= e2.hp + e2.total_shield():
						kill = true
			var s := -INF
			if kill:
				s = 50.0 + n * 10.0
			elif n >= 2:
				s = 30.0 + n * 10.0
			elif (e.cc & Buff.IMMOBILIZE) != 0 and d < 20.0 and e.hp_ratio() < 0.7:
				s = 20.0
			if s > best_s:
				best_s = s
				best_aim = aim
		if best_s <= 0.0:
			return skip()
		return ctx.aim_at(best_aim, self)
