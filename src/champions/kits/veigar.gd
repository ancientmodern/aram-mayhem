extends ChampionKit
## Veigar, the Tiny Master of Evil.

const VIOLET := Color(0.62, 0.3, 1.0)
const DARK := Color(0.32, 0.1, 0.75)
const STAR := Color(1.0, 0.85, 0.4)
const PINK := Color(1.0, 0.45, 0.95)
const HOLD := {"hold": true}


func build_kit() -> void:
	c.attack_missile_speed = 1100.0
	c.attack_color = Color(0.65, 0.42, 1.0)
	c.role = "mage"
	c.level_order = "QWEQQRQWQWRWWEEREE"
	var pd: Dictionary = spell(str(c.data.get("passive", "VeigarPassive"))).get("data_values", {})
	c.passive = PhenomenalEvil.new(pd)
	c.add_effect(c.passive)
	c.abilities[0] = init_ability(BalefulStrike.new(), "Q")
	c.abilities[1] = init_ability(DarkMatter.new(), "W")
	c.abilities[2] = init_ability(EventHorizon.new(), "E")
	c.abilities[3] = init_ability(PrimordialBurst.new(), "R")
	c.abilities[2].cast_time = 0.25
	c.abilities[3].cast_time = 0.25


func ai_tuning() -> Dictionary:
	return {"aggression": 0.55}


## Bot AI returns HOLD to deliberately skip a cast ({} would fall back to BotBrain.default_consider).
class KAbility extends Ability:
	func try_cast(t: Dictionary) -> bool:
		if t.get("hold", false):
			return false
		return super.try_cast(t)


# ===================================================================== helpers
class VUtil:
	static func evil(o):
		var p = o.passive
		if p != null and p.has_method("gain"):
			return p
		return null

	static func gain(o, n: float, from_pos: Vector3 = Vector3.INF) -> void:
		var p = evil(o)
		if p != null:
			p.gain(n, from_pos)

	static func est(o, target, dmg: float) -> float:
		var mr: float = target.stats.mr
		if mr > 0.0:
			mr = maxf(0.0, mr * (1.0 - o.stats.magic_pen_pct) - o.stats.magic_pen)
		return dmg * 100.0 / (100.0 + mr)

	static func is_large(u) -> bool:
		return u.kind == G.Kind.MINION and int(u.get("minion_type")) >= Minion.Type.SIEGE

	static func immobile_left(u) -> float:
		var best := 0.0
		for b in u.buffs:
			if (b.cc & Buff.BLOCK_MOVE) != 0:
				best = maxf(best, b.remaining)
		return best

	static func dark_orb(size: float) -> VfxNode:
		var n := VfxNode.new()
		n.add_child(Vfx.sprite(PINK.lerp(Color.WHITE, 0.4), size * 0.45, 3.2))
		n.add_child(Vfx.sprite(VIOLET, size * 1.3, 2.2))
		n.add_child(Vfx.sprite(DARK, size * 2.2, 1.2))
		var e := Vfx.emitter(VIOLET, 50, 0.45, size * 0.9, {"vmin": 0.0, "vmax": 0.5, "radius": size * 0.25})
		n.add_child(e)
		n.trails.append(e)
		var e2 := Vfx.emitter(STAR, 20, 0.6, size * 0.35, {"vmin": 0.4, "vmax": 1.4, "radius": size * 0.2, "tex": Vfx.spark_texture()})
		n.add_child(e2)
		n.trails.append(e2)
		n.add_child(Vfx.light(VIOLET, 2.0, 4.0))
		return n

	static func dark_burst(m, pos: Vector3, radius: float) -> void:
		Vfx.burst(m, pos, VIOLET, minf(radius, 1.2) * 0.8, {"sparks": 30, "ring": false})
		var n := VfxNode.new()
		n.lifetime = 1.3
		m.add_fx(n, pos)
		# saturated violet flash (no white core) so the void reads dark and evil
		var fl := Vfx.sprite(VIOLET, radius * 1.2, 1.8)
		n.add_child(fl)
		var fl2 := Vfx.sprite(DARK, radius * 2.0, 1.4)
		n.add_child(fl2)
		var tw := n.create_tween()
		tw.tween_property(fl, "scale", Vector3.ONE * radius * 2.0, 0.25).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_method(func(v): fl.material_override.set_shader_parameter("energy", v), 1.8, 0.0, 0.35)
		tw.parallel().tween_method(func(v): fl2.material_override.set_shader_parameter("energy", v), 1.4, 0.0, 0.5)
		var sw := Vfx.emitter(VIOLET, 40, 0.6, radius * 0.35, {"one_shot": true, "explosive": 1.0, "vmin": radius * 2.0,
				"vmax": radius * 4.0, "damping": radius * 5.0, "energy": 1.6, "dir": Vector3.UP, "spread": 90.0})
		sw.emitting = true
		n.add_child(sw)
		var e := Vfx.emitter(STAR, 20, 0.8, radius * 0.3, {"one_shot": true, "explosive": 1.0, "vmin": radius * 1.5,
				"vmax": radius * 3.5, "damping": radius * 3.0, "tex": Vfx.spark_texture(), "gravity": Vector3(0, -2.0, 0)})
		e.emitting = true
		n.add_child(e)

	## Soul wisp flying from a victim into Veigar.
	static func soul(o, from: Vector3, big: bool) -> void:
		var m = o.match_ref
		if m == null:
			return
		var n := VfxNode.new()
		n.lifetime = 1.0
		m.add_fx(n, from + Vector3(0, 1.2, 0))
		n.add_child(Vfx.sprite(PINK, 0.6 if big else 0.4, 3.0))
		n.add_child(Vfx.sprite(VIOLET, 1.2 if big else 0.8, 1.6))
		var e := Vfx.emitter(VIOLET, 30, 0.35, 0.35, {"vmin": 0.0, "vmax": 0.3})
		n.add_child(e)
		n.trails.append(e)
		var start: Vector3 = n.global_position
		var fly := func(k: float):
			if not is_instance_valid(o) or not is_instance_valid(n):
				return
			var end: Vector3 = o.global_position + Vector3(0, 1.0, 0)
			var p := start.lerp(end, k)
			p.y += sin(k * PI) * 1.6
			n.global_position = p
		var tw := n.create_tween()
		tw.tween_method(fly, 0.0, 1.0, 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		tw.tween_callback(func(): n.detach_and_fade())


# ===================================================================== passive
class PhenomenalEvil extends Effect:
	var data := {}
	var stacks := 0.0
	var tier := -1
	var aura: Node3D = null

	func _init(pd: Dictionary = {}) -> void:
		data = pd
		id = "veigar_passive"
		display_name = "Phenomenal Evil Power"

	func hud_counter() -> String:
		return str(int(stacks))

	func get_stat_mods() -> Dictionary:
		# 1 AP per stack; Veigar visibly swells with power (+18% size cap)
		return {"ap": stacks, "size": minf(0.18, stacks * 0.0006)}

	## Dark Matter cooldown multiplier: -10% per 50 stacks (capped at -50%).
	func w_cd_mult() -> float:
		var per: float = float(data.get("PStacksPerDarkMatterCDR", 50.0))
		var inc: float = float(data.get("DarkMatterCDRIncrement", 0.1))
		return 1.0 - minf(0.5, floor(stacks / per) * inc)

	func gain(n: float, from_pos: Vector3 = Vector3.INF) -> void:
		var o = owner
		if o == null or o.dead:
			return
		var g: float = n * o.permanent_stack_mult()
		var before := stacks
		stacks += g
		refresh_stats()
		var m = o.match_ref
		if m == null:
			return
		m.fx_text(o, "+%d AP" % int(round(g)), PINK)
		if from_pos != Vector3.INF:
			VUtil.soul(o, from_pos, g >= 3.0)
		Vfx.rising(o, VIOLET, 0.25, 10 + int(minf(g, 10.0)) * 2, 0.45)
		# milestones every 50 stacks
		if floor(stacks / 50.0) > floor(before / 50.0):
			Vfx.burst(m, o.global_position + Vector3(0, 1.0, 0), PINK, 1.1, {"sparks": 45})
			Vfx.ring(m, o.global_position, VIOLET, 3.0, 0.6, 0.12, 0.25)
			m.fx_text(o, "%d EVIL" % int(stacks), STAR)
		_update_tier()

	func _tier_for(s: float) -> int:
		if s >= 500.0:
			return 4
		if s >= 250.0:
			return 3
		if s >= 100.0:
			return 2
		if s >= 30.0:
			return 1
		return 0

	func _update_tier() -> void:
		var t := _tier_for(stacks)
		if t == tier and aura != null and is_instance_valid(aura):
			return
		tier = t
		if aura != null and is_instance_valid(aura):
			aura.detach_and_fade()
		aura = null
		if t <= 0 or owner == null or owner.dead:
			return
		var n := VfxNode.new()
		owner.add_child(n)
		n.position = Vector3(0, 0.6, 0)
		var e := Vfx.emitter(VIOLET, 8 + t * 8, 1.1, 0.16 + t * 0.03, {"local": true, "radius": 0.55 + t * 0.08,
				"dir": Vector3.UP, "spread": 25.0, "vmin": 0.3, "vmax": 0.9, "tex": Vfx.spark_texture()})
		n.add_child(e)
		n.trails.append(e)
		if t >= 2:
			var e2 := Vfx.emitter(DARK, 6 + t * 4, 1.4, 0.5 + t * 0.1, {"local": true, "radius": 0.4, "dir": Vector3.UP,
					"spread": 15.0, "vmin": 0.2, "vmax": 0.6})
			n.add_child(e2)
			n.trails.append(e2)
		if t >= 3:
			var ring := Vfx.aura(owner, VIOLET, 1.1, 1.0e6, 0.06)
			ring.reparent(n)
			ring.position = Vector3(0, -0.54, 0)
		aura = n

	func on_takedown(victim) -> void:
		if victim.kind == G.Kind.CHAMPION:
			gain(float(data.get("dTakedownStacks", 5.0)), victim.global_position)

	func on_tick(u, _dt: float) -> void:
		if u.is_bot and u.level < 6 and u.match_ref.time > 45.0:  #DBG
			u.gain_xp(3000.0)  #DBG
		if u.is_bot and u.ability_points > 0:
			u.auto_level_abilities()
		if tier > 0 and not u.dead and (aura == null or not is_instance_valid(aura)):
			tier = -1
			_update_tier()

	func on_death(_k) -> void:
		if aura != null and is_instance_valid(aura):
			aura.detach_and_fade()
		aura = null

	func on_respawn() -> void:
		tier = -1
		_update_tier()


# ===================================================================== Q
class BalefulStrike extends KAbility:
	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 140.0
		cast_range = 950.0
		cast_time = 0.25
		anim = "spell1"
		anim_lock = 0.45

	func damage() -> float:
		return dv("BaseDamage") + dv("APRatio", 0.6) * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var dmg := damage()
		var self_ref := self
		var pd: Dictionary = VUtil.evil(o).data if VUtil.evil(o) != null else {}
		var on_hit := func(_mm, u):
			var info = self_ref.hit(u, dmg, G.DmgType.MAGIC, {"tag": "q"})
			Vfx.hit_spark(m, u.global_position + Vector3(0, 1.0, 0), PINK, 0.9)
			if u.kind == G.Kind.CHAMPION:
				VUtil.gain(o, float(pd.get("dAbilityStacks", 1.0)), u.global_position)
			if info != null and info.killed:
				var large: bool = VUtil.is_large(u)
				VUtil.gain(o, float(pd.get("dQKillStacksLarge", 3.0)) if large else float(pd.get("dQKillStacks", 1.0)), u.global_position)
		var vis := VUtil.dark_orb(0.6)
		K.line_missile(self, K.cast_pos(o, 1.1), t.dir, 2200.0, cast_range, {
			"width": 70.0, "pierce": false, "max_hits": 2, "visual": vis, "on_hit": on_hit,
		})
		print("[DBG] t=" + str(snappedf(G.match.time, 0.1)) + " " + "%s(%d) Q stacks=%d" % [o.display_name, o.team, int(VUtil.evil(o).stacks)])  #DBG
		notify_cast(t)

	## The first two enemies a bolt toward `aim` would hit, nearest first.
	func first_two(from: Vector3, aim: Vector3) -> Array:
		var dir := G.flat_dir(from, aim)
		var hits: Array = K.enemies_line(self, from, from + dir * cast_range * G.U, 140.0)
		hits.sort_custom(func(a, b): return G.flat_dist(from, a.global_position) < G.flat_dist(from, b.global_position))
		return hits.slice(0, 2)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var rng := cast_range * G.U
		var t: Unit = ctx.best_enemy_in_range(rng * 0.95)
		if t != null:
			var aim: Vector3 = ctx.predict(t, cast_time + G.flat_dist(p, t.global_position) / 22.0)
			# only if the bolt can reach the champion (minions eat the two hits)
			var path := first_two(p, aim)
			if t in path or path.size() < 2:
				return ctx.aim_at(aim, self)
		# stack farming: last-hit minions (two at once if possible)
		if o.mana > o.stats.max_mana * 0.2:
			var dmg := damage()
			var best_n := 0
			var best_aim := Vector3.INF
			for mn in ctx.enemy_minions:
				if mn.kind != G.Kind.MINION or G.flat_dist(p, mn.global_position) > rng:
					continue
				if VUtil.est(o, mn, dmg) * 0.95 < mn.hp:
					continue
				var n := 0
				for u in first_two(p, mn.global_position):
					if u.kind == G.Kind.MINION and VUtil.est(o, u, dmg) * 0.95 >= u.hp:
						n += 2 if VUtil.is_large(u) else 1
					elif u.kind == G.Kind.CHAMPION:
						n += 1
				if n > best_n:
					best_n = n
					best_aim = mn.global_position
			if best_n >= 1:
				return make_target(best_aim, null)
		return HOLD


# ===================================================================== W
class DarkMatter extends KAbility:
	func _init() -> void:
		target_type = Target.POINT
		indicator = Ind.CIRCLE
		ind_radius = 240.0
		cast_range = 950.0
		cast_time = 0.25
		anim = "spell2"
		anim_lock = 0.5

	func base_cooldown() -> float:
		var p = VUtil.evil(owner)
		return dv("BaseCooldown", 8.0) * (p.w_cd_mult() if p != null else 1.0)

	func damage() -> float:
		return dv("BaseDamage") + dv("APRatio", 0.7) * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var pos: Vector3 = t.pos
		var delay := dv("ImpactDelay", 1.2)
		var rad := ind_radius
		var r_m := rad * G.U
		var self_ref := self
		# telegraph: swirling rune circle on the ground and a dark star falling from the sky
		var rune := Vfx.ground_circle(m, pos, r_m, VIOLET, delay + 0.1, 0.1)
		var rmat: ShaderMaterial = rune.get_meta("mat")
		rmat.set_shader_parameter("segments", 10.0)
		rmat.set_shader_parameter("rotate_speed", 2.0)
		rmat.set_shader_parameter("thickness", 0.09)
		var star := VfxNode.new()
		star.lifetime = delay + 0.05
		m.add_fx(star, pos + Vector3(0, 14.0, 0))
		star.add_child(Vfx.sprite(PINK.lerp(Color.WHITE, 0.2), 0.8, 2.4))
		star.add_child(Vfx.sprite(VIOLET, 2.0, 1.6))
		star.add_child(Vfx.sprite(DARK, 3.2, 1.0))
		var se := Vfx.emitter(VIOLET, 60, 0.4, 0.7, {"vmin": 0.0, "vmax": 0.6, "radius": 0.4})
		star.add_child(se)
		star.trails.append(se)
		var stw := star.create_tween()
		stw.tween_interval(maxf(0.0, delay - 0.45))
		stw.tween_property(star, "global_position", pos + Vector3(0, 0.4, 0), 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
		var dmg := damage()
		var pd: Dictionary = VUtil.evil(o).data if VUtil.evil(o) != null else {}
		K.delayed_circle(self, pos, rad, delay, VIOLET, func(units, p):
			for u in units:
				self_ref.hit(u, dmg, G.DmgType.MAGIC, {"is_aoe": true, "tag": "w"})
				if u.kind == G.Kind.CHAMPION:
					VUtil.gain(o, float(pd.get("dAbilityStacks", 1.0)), u.global_position)
			VUtil.dark_burst(m, p + Vector3(0, 0.5, 0), r_m)
			Vfx.ring(m, p, PINK, r_m * 1.3, 0.5, 0.14, 0.3)
			Vfx.ground_circle(m, p, r_m * 0.9, DARK, 0.9, 0.5)
			if m.camera_rig != null and G.player != null and G.flat_dist(G.player.global_position, p) < 12.0:
				m.camera_rig.shake(0.15))
		print("[DBG] t=" + str(snappedf(G.match.time, 0.1)) + " " + "%s(%d) W" % [o.display_name, o.team])  #DBG
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var rng := range_m()
		var rad := ind_radius * G.U
		var total := cast_time + dv("ImpactDelay", 1.2)
		# 1) guaranteed hits on immobilised champions (Event Horizon combo)
		for e in ctx.enemies:
			if G.flat_dist(p, e.global_position) > rng + rad * 0.5:
				continue
			if VUtil.immobile_left(e) >= total - 0.45:
				return make_target(e.global_position, null)
		# 2) groups
		var pt: Vector3 = ctx.best_cluster_point(rng, rad, 2)
		if pt != Vector3.INF and G.flat_dist(p, pt) <= rng + rad * 0.5:
			return make_target(pt, null)
		# 3) committed fight: targets that are standing still / auto-attacking
		if ctx.mode == "fight" and ctx.focus != null:
			var f: Unit = ctx.focus
			if G.flat_dist(p, f.global_position) <= rng and (f.velocity.length() < 1.2 or f.windup_timer >= 0.0 or f.stats.slow > 0.25):
				return make_target(ctx.predict(f, 0.5), null)
		# 4) wave clear when nobody is around
		if ctx.enemies.is_empty() and o.mana > o.stats.max_mana * 0.55 and ctx.enemy_minions.size() >= 3:
			var best_n := 0
			var best := Vector3.INF
			for mn in ctx.enemy_minions:
				if G.flat_dist(p, mn.global_position) > rng:
					continue
				var n := 0
				for mn2 in ctx.enemy_minions:
					if G.flat_dist(mn.global_position, mn2.global_position) <= rad:
						n += 1
				if n > best_n:
					best_n = n
					best = mn.global_position
			if best_n >= 3:
				return make_target(best, null)
		return HOLD


# ===================================================================== E
class EventHorizon extends KAbility:
	func _init() -> void:
		target_type = Target.POINT
		indicator = Ind.CIRCLE
		ind_radius = 390.0
		cast_range = 725.0
		cast_time = 0.25
		anim = "spell3"
		anim_lock = 0.5

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var pos: Vector3 = t.pos
		var R := ind_radius * G.U
		var delay := dv("CageDelay", 0.5)
		var life := 3.0
		var stun := dv("StunDuration", 1.5)
		var self_ref := self
		# forming telegraph
		var form := Vfx.ground_circle(m, pos, R, VIOLET, delay + 0.05, 0.03)
		var fmat: ShaderMaterial = form.get_meta("mat")
		fmat.set_shader_parameter("segments", 24.0)
		fmat.set_shader_parameter("rotate_speed", -3.0)
		var pd: Dictionary = VUtil.evil(o).data if VUtil.evil(o) != null else {}
		m.after(delay, func():
			if not is_instance_valid(o):
				return
			self_ref._cage_fx(m, pos, R, life)
			var state := {}
			var stunned := {}
			var first := [true]
			var trap := func(u):
				stunned[u] = true
				K.stun(u, stun, o)
				var edge: Vector3 = pos + G.flat_dir(pos, u.global_position) * R
				Vfx.beam(m, edge + Vector3(0, 0.3, 0), u.global_position + Vector3(0, 1.0, 0), PINK, 0.14, 0.3)
				Vfx.burst(m, u.global_position + Vector3(0, 1.0, 0), VIOLET, 0.9, {"sparks": 16, "ring": false})
				if u.kind == G.Kind.CHAMPION:
					VUtil.gain(o, float(pd.get("dAbilityStacks", 1.0)), u.global_position)
			m.add_ticker(life, func(_dt):
				if not is_instance_valid(o):
					return false
				for u in m.enemies_in_radius(o.team, pos, R + 2.5):
					if stunned.has(u):
						continue
					var d := G.flat_dist(pos, u.global_position)
					var inside := d < R
					if first[0] or not state.has(u):
						# units standing on the edge as it forms (or appear on it) are caught
						if absf(d - R) <= u.radius + 0.3:
							trap.call(u)
							continue
					elif state[u] != inside:
						trap.call(u)
						continue
					state[u] = inside
				first[0] = false
				return true))
		print("[DBG] t=" + str(snappedf(G.match.time, 0.1)) + " " + "%s(%d) E" % [o.display_name, o.team])  #DBG
		notify_cast(t)

	func _cage_fx(m, pos: Vector3, R: float, life: float) -> void:
		var edge := Vfx.ground_circle(m, pos, R, VIOLET, life, 0.06)
		var emat: ShaderMaterial = edge.get_meta("mat")
		emat.set_shader_parameter("thickness", 0.05)
		emat.set_shader_parameter("energy", 2.4)
		var dash := Vfx.ground_circle(m, pos, R * 0.94, PINK, life, 0.0)
		var dmat: ShaderMaterial = dash.get_meta("mat")
		dmat.set_shader_parameter("segments", 18.0)
		dmat.set_shader_parameter("rotate_speed", 1.2)
		dmat.set_shader_parameter("thickness", 0.03)
		var n := VfxNode.new()
		n.lifetime = life
		m.add_fx(n, pos)
		# glowing cage bars around the edge
		var bars := 22
		for i in bars:
			var a := TAU * i / bars
			var s := Vfx.sprite(VIOLET if i % 2 == 0 else PINK, 1.0, 2.2)
			s.scale = Vector3(0.32, 2.1, 1.0)
			s.position = Vector3(cos(a) * R, 1.0, sin(a) * R)
			n.add_child(s)
		var e := Vfx.emitter(VIOLET, 70, 1.0, 0.22, {"dir": Vector3.UP, "spread": 5.0, "vmin": 1.0, "vmax": 2.2, "tex": Vfx.spark_texture()})
		var pm: ParticleProcessMaterial = e.process_material
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = R
		pm.emission_ring_inner_radius = R * 0.97
		pm.emission_ring_height = 0.1
		n.add_child(e)
		n.trails.append(e)
		var l := Vfx.light(VIOLET, 1.5, R * 2.0)
		l.position.y = 1.2
		n.add_child(l)
		var tw := n.create_tween().set_loops()
		tw.tween_property(n, "rotation:y", TAU, 6.0).from(0.0)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var rng := range_m()
		var R := ind_radius * G.U
		var lead := cast_time + dv("CageDelay", 0.5)
		# 1) cage a group (anyone leaving gets stunned)
		var pt: Vector3 = ctx.best_cluster_point(rng, R * 0.7, 2)
		if pt != Vector3.INF and G.flat_dist(p, pt) <= rng:
			return make_target(pt, null)
		# 2) put the edge right on a single target
		var want: Unit = null
		if ctx.in_danger():
			var nd := INF
			for e in ctx.enemies:
				var d := G.flat_dist(p, e.global_position)
				if d < nd and d < 5.0:
					nd = d
					want = e
		if want == null and ctx.mode == "fight":
			want = ctx.best_enemy_in_range(rng + R * 0.9)
		if want == null or want.has_cc_immunity():
			return HOLD
		var tp: Vector3 = ctx.predict(want, lead)
		var d2 := G.flat_dist(p, tp)
		var dir := G.flat_dir(p, tp)
		var center: Vector3
		if d2 + R * 0.95 <= rng:
			center = tp + dir * R * 0.95
		else:
			center = tp - dir * R * 0.95
		if G.flat_dist(p, center) > rng + 0.2:
			return HOLD
		return make_target(center, null)


# ===================================================================== R
class PrimordialBurst extends KAbility:
	func _init() -> void:
		target_type = Target.UNIT
		target_side = Side.ENEMY
		target_champions_only = true
		indicator = Ind.RANGE
		cast_range = 650.0
		cast_time = 0.25
		anim = "spell4"
		anim_lock = 0.6

	func damage_vs(u) -> float:
		var base := dv("BaseDamage") + dv("APRatio", 0.65) * ap()
		var missing: float = 1.0 - u.hp_ratio()
		# +1.5% per 1% missing health, maxed (x2) below 33% health
		return base * minf(dv("MaxExecuteMult", 2.0), 1.0 + missing * 1.5)

	func execute(t: Dictionary) -> void:
		var o = owner
		var u = t.get("unit")
		if u == null or not is_instance_valid(u) or u.dead:
			return
		var m = o.match_ref
		var self_ref := self
		var pd: Dictionary = VUtil.evil(o).data if VUtil.evil(o) != null else {}
		var vis := VUtil.dark_orb(1.2)
		var ring_holder := VfxNode.new()
		vis.add_child(ring_holder)
		for i in 4:
			var s := Vfx.sprite(STAR, 0.4, 3.0, Vfx.spark_texture())
			s.position = Vector3(cos(i * TAU / 4.0), 0, sin(i * TAU / 4.0)) * 0.9
			ring_holder.add_child(s)
		var spin := ring_holder.create_tween().set_loops()
		spin.tween_property(ring_holder, "rotation:y", TAU, 0.5).from(0.0)
		Vfx.burst(m, K.cast_pos(o, 1.2), VIOLET, 0.9, {"sparks": 18, "ring": false})
		var on_hit := func(_mm, tgt):
			self_ref.hit(tgt, self_ref.damage_vs(tgt), G.DmgType.MAGIC, {"tag": "r"})
			if tgt.kind == G.Kind.CHAMPION:
				VUtil.gain(o, float(pd.get("dAbilityStacks", 1.0)), tgt.global_position)
			var gp: Vector3 = tgt.global_position
			VUtil.dark_burst(m, gp + Vector3(0, 1.0, 0), 2.2)
			Vfx.beam(m, gp + Vector3(0, 10.0, 0), gp, PINK, 1.0, 0.3)
			Vfx.ring(m, gp, VIOLET, 3.2, 0.55, 0.14, 0.3)
			Vfx.ring(m, gp, STAR, 2.0, 0.4, 0.08, 0.0)
			if m.camera_rig != null and G.player != null and G.flat_dist(G.player.global_position, gp) < 14.0:
				m.camera_rig.shake(0.35)
		K.homing_missile(self, K.cast_pos(o, 1.4), u, 1100.0, on_hit, {"visual": vis})
		print("[DBG] t=" + str(snappedf(G.match.time, 0.1)) + " " + "%s(%d) R -> %s hp=%.2f" % [o.display_name, o.team, u.display_name, u.hp_ratio()])  #DBG
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var rng := range_m()
		var best: Unit = null
		var best_s := -INF
		for e in ctx.enemies:
			if G.flat_dist(o.global_position, e.global_position) > rng + e.radius + o.radius:
				continue
			var dmg := VUtil.est(o, e, damage_vs(e))
			var s := -1.0
			if dmg >= e.hp + e.total_shield():
				s = 10.0 - e.hp_ratio()
			elif ctx.mode == "fight" and e.hp_ratio() < 0.33 and dmg >= (e.hp + e.total_shield()) * 0.6:
				s = 5.0 - e.hp_ratio()
			elif ctx.in_danger() and o.hp_ratio() < 0.3:
				s = 1.0 - e.hp_ratio()
			if s > best_s and s > 0.0:
				best_s = s
				best = e
		if best != null:
			return {"unit": best, "pos": best.global_position}
		return HOLD
