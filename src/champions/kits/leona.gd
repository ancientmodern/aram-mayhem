extends ChampionKit
## Leona, the Radiant Dawn.

const SUN := Color(1.0, 0.8, 0.3)
const SUN_HOT := Color(1.0, 0.95, 0.72)
const DAWN := Color(1.0, 0.55, 0.15)
const HOLD := {"hold": true}


func build_kit() -> void:
	c.attack_missile_speed = 0.0
	c.attack_color = SUN
	c.role = "tank"
	c.level_order = "EQWWWRWEWEREEQQRQQ"
	var pd: Dictionary = spell(str(c.data.get("passive", "LeonaSunlightPassive"))).get("data_values", {})
	c.passive = Sunlight.new(pd)
	c.add_effect(c.passive)
	c.abilities[0] = init_ability(ShieldOfDawn.new(), "Q")
	c.abilities[1] = init_ability(Eclipse.new(), "W")
	c.abilities[2] = init_ability(ZenithBlade.new(), "E")
	c.abilities[3] = init_ability(SolarFlare.new(), "R")
	# Q is an instant self-buff (attack reset) in live
	c.abilities[0].cast_time = 0.0
	c.abilities[0].anim = ""
	c.abilities[2].cast_range = 875.0
	c.abilities[3].cast_time = 0.25
	c.add_effect(QAttackHook.new(c.abilities[0]))


func ai_tuning() -> Dictionary:
	return {"aggression": 0.8}


## Bot AI returns HOLD to deliberately skip a cast ({} would fall back to BotBrain.default_consider).
class KAbility extends Ability:
	func try_cast(t: Dictionary) -> bool:
		if t.get("hold", false):
			return false
		return super.try_cast(t)


# ===================================================================== helpers
class LUtil:
	static func mark(leona, target) -> void:
		var p = leona.passive
		if p != null and p.has_method("apply_mark"):
			p.apply_mark(target)

	static func shake(o, pos: Vector3, amount: float) -> void:
		var m = o.match_ref
		if m != null and m.camera_rig != null and G.player != null and G.flat_dist(G.player.global_position, pos) < 14.0:
			m.camera_rig.shake(amount)

	static func sun_burst(m, pos: Vector3, radius: float) -> void:
		Vfx.burst(m, pos, SUN, radius, {"sparks": 24, "ring": false})
		var n := VfxNode.new()
		n.lifetime = 0.6
		m.add_fx(n, pos)
		# radiating rays
		for i in 6:
			var s := Vfx.sprite(SUN_HOT, 1.0, 2.6, Vfx.spark_texture())
			s.rotation.z = i * PI / 6.0
			s.scale = Vector3.ONE * radius * 0.9
			n.add_child(s)
		var tw := n.create_tween()
		tw.tween_property(n, "scale", Vector3.ONE * 1.6, 0.3).set_ease(Tween.EASE_OUT)

	static func immobile(u) -> bool:
		return (u.cc & Buff.IMMOBILIZE) != 0

	## Exported clip name for a logical clip like "spell2_run" ("" if missing).
	static func find_clip(o, logical: String) -> String:
		if o.anim_player == null:
			return ""
		for an in o.anim_player.get_animation_list():
			if Assets._strip_prefix(String(an).to_lower()) == logical:
				return String(an)
		return ""


# ===================================================================== passive
class Sunlight extends Effect:
	var data := {}

	func _init(pd: Dictionary = {}) -> void:
		data = pd
		id = "leona_passive"
		display_name = "Sunlight"

	func damage() -> float:
		return 24.0 + 8.0 * owner.level

	func apply_mark(target) -> void:
		if target == null or not is_instance_valid(target) or target.dead or target.team == owner.team:
			return
		if target.kind in [G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS]:
			return
		var dur: float = float(data.get("MarkDuration", 1.5))
		var ex = target.find_buff("leona_sunlight")
		if ex != null:
			ex.remaining = dur
			ex.duration = dur
			ex.leona = owner
			return
		var b := SunlightMark.new()
		b.duration = dur
		b.remaining = dur
		b.leona = owner
		b.icon = icon
		var n := VfxNode.new()
		target.add_child(n)
		n.position = Vector3(0, target.height + 0.35, 0)
		n.add_child(Vfx.sprite(SUN, 0.75, 2.4))
		var rays := Vfx.sprite(SUN_HOT, 0.9, 2.2, Vfx.spark_texture())
		n.add_child(rays)
		var tw := n.create_tween().set_loops()
		tw.tween_property(rays, "rotation:z", TAU, 1.6).from(0.0)
		var ring := Vfx.aura(target, SUN, maxf(0.8, target.radius * 1.3), dur + 0.2, 0.08)
		ring.reparent(n)
		ring.position = Vector3(0, -(target.height + 0.27), 0)
		b.vfx = n
		target.add_buff(b, owner)

	func on_tick(u, _dt: float) -> void:
		if u.is_bot and u.ability_points > 0:
			u.auto_level_abilities()


## Sunlight debuff: the next damage from another allied champion detonates it.
class SunlightMark extends Buff:
	var leona = null

	func _init() -> void:
		id = "leona_sunlight"
		display_name = "Sunlight"
		is_debuff = true

	func on_damage_taken(info) -> void:
		if removed or leona == null or not is_instance_valid(leona):
			return
		var src = info.source
		if src == null or not is_instance_valid(src) or src == leona or info.tag == "sunlight":
			return
		if src.kind != G.Kind.CHAMPION or src.team != leona.team:
			return
		removed = true
		var dmg: float = leona.passive.damage() if leona.passive != null and leona.passive.has_method("damage") else 24.0 + 8.0 * leona.level
		Combat.deal(leona, owner, dmg, G.DmgType.MAGIC, {"is_proc": true, "tag": "sunlight"})
		var m = owner.match_ref
		if m != null:
			var gp: Vector3 = owner.global_position
			LUtil.sun_burst(m, gp + Vector3(0, 1.2, 0), 1.0)
			Vfx.beam(m, gp + Vector3(0, 6.0, 0), gp + Vector3(0, 0.2, 0), SUN, 0.5, 0.25)


# ===================================================================== Q
class ShieldOfDawn extends KAbility:
	var empowered_until := -1.0
	var fx: Node3D = null

	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0
		anim = ""
		resets_attack = true

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return {"pos": owner.global_position + owner.facing, "dir": owner.facing, "unit": null}

	func window() -> float:
		return 6.0

	func execute(t: Dictionary) -> void:
		var o = owner
		empowered_until = o.match_ref.time + window()
		_clear_fx()
		var n := VfxNode.new()
		n.lifetime = window()
		o.add_child(n)
		n.position = Vector3(0, 1.1, 0) + Vector3(0, 0, 0)
		n.add_child(Vfx.sprite(SUN, 1.2, 1.4))
		var e := Vfx.emitter(SUN_HOT, 24, 0.5, 0.25, {"local": true, "radius": 0.5, "vmin": 0.2, "vmax": 0.8, "tex": Vfx.spark_texture()})
		n.add_child(e)
		n.trails.append(e)
		n.add_child(Vfx.light(SUN, 1.5, 3.5))
		fx = n
		Vfx.rising(o, SUN, 0.3, 18, 0.5)
		notify_cast(t)

	func is_empowered() -> bool:
		return owner.match_ref != null and owner.match_ref.time < empowered_until

	func _clear_fx() -> void:
		if fx != null and is_instance_valid(fx):
			fx.detach_and_fade()
		fx = null

	func consume(target) -> void:
		var o = owner
		empowered_until = -1.0
		_clear_fx()
		hit(target, dv("BaseDamage") + 0.3 * ap(), G.DmgType.MAGIC, {"tag": "q"})
		K.stun(target, dv("StunDuration", 1.0), o)
		LUtil.mark(o, target)
		var m = o.match_ref
		var gp: Vector3 = target.global_position
		LUtil.sun_burst(m, gp + Vector3(0, 1.1, 0), 1.2)
		Vfx.ring(m, gp, SUN, 1.6, 0.35, 0.12, 0.15)
		LUtil.shake(o, gp, 0.2)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if is_empowered() or not o.dash.is_empty():
			return HOLD
		var t: Unit = ctx.focus
		if t == null or not is_instance_valid(t) or t.dead:
			t = ctx.best_enemy_in_range(o.attack_range_m() + 1.5)
		if t == null or t.has_cc_immunity():
			return HOLD
		if o.edge_dist(t) <= o.attack_range_m() + 1.2:
			return make_target(t.global_position)
		return HOLD


## Empowered Shield of Dawn attack (and the shield-bash animation during its windup).
class QAttackHook extends Effect:
	var q = null
	var played := false

	func _init(p_q) -> void:
		q = p_q
		id = "leona_q_hook"
		hidden = true

	func on_tick(u, _dt: float) -> void:
		if u.windup_timer < 0.0:
			played = false
			return
		if not played and q.is_empowered() and u.has_anim("spell1"):
			played = true
			u.play_anim("spell1", 1.0, 0.05, u.windup_timer + 0.35)
			u.anim_lock = u.windup_timer + 0.35

	func on_attack_hit(target, _info) -> void:
		if q == null or not q.is_empowered() or target == null or not is_instance_valid(target) or target.dead:
			return
		if target.kind in [G.Kind.TURRET, G.Kind.INHIBITOR, G.Kind.NEXUS]:
			return
		q.consume(target)


# ===================================================================== W
class Eclipse extends KAbility:
	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.CIRCLE
		ind_radius = 450.0
		cast_range = 0.0
		cast_time = 0.0
		anim = "spell2"
		anim_lock = 0.45

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return {"pos": owner.global_position, "dir": owner.facing, "unit": null}

	func resist_stats() -> Dictionary:
		var o = owner
		var base := dv("ArmorBaseBonus", 20.0)
		return {"armor": base + 0.2 * o.stats.bonus_armor, "mr": dv("MRBaseBonus", 20.0) + 0.2 * o.stats.bonus_mr}

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var dur := dv("ArmorMRDuration", 3.0)
		var b := EclipseBuff.new()
		b.duration = dur
		b.remaining = dur
		b.stats = resist_stats()
		b.flat = dv("FlatDamageReduction", 8.0)
		b.cap = dv("FlatDamageReductionMax", 0.5)
		b.icon = icon
		# radiant sun disc around Leona
		var n := VfxNode.new()
		o.add_child(n)
		n.position = Vector3(0, 0.08, 0)
		var ring := Vfx.aura(o, SUN, 1.25, dur, 0.08)
		ring.reparent(n)
		var disc := Vfx.sprite(SUN, 1.8, 1.0)
		disc.position = Vector3(0, 1.2, 0)
		n.add_child(disc)
		var e := Vfx.emitter(SUN_HOT, 30, 0.8, 0.22, {"local": true, "radius": 1.0, "dir": Vector3.UP, "spread": 15.0,
				"vmin": 0.6, "vmax": 1.4, "tex": Vfx.spark_texture()})
		n.add_child(e)
		n.trails.append(e)
		var l := Vfx.light(SUN, 2.0, 5.0)
		l.position.y = 1.2
		n.add_child(l)
		b.vfx = n
		o.remove_buffs_by_id("leona_w")
		o.add_buff(b, o)
		# area preview of the detonation
		var tel := Vfx.aura(o, Color(SUN.r, SUN.g, SUN.b, 0.35), ind_radius * G.U, dur, 0.05)
		var tmat: ShaderMaterial = (tel.get_child(0) as MeshInstance3D).material_override
		tmat.set_shader_parameter("thickness", 0.025)
		tmat.set_shader_parameter("fill", 0.03)
		tmat.set_shader_parameter("segments", 0.0)
		_set_stance(true)
		var self_ref := self
		m.after(dur, func():
			if is_instance_valid(o):
				self_ref._detonate())
		notify_cast(t)

	func _set_stance(on: bool) -> void:
		var o = owner
		if not o.has_meta("leona_anim_backup"):
			o.set_meta("leona_anim_backup", {"idle": o.anim_map.get("idle", []), "run": o.anim_map.get("run", [])})
		var bk: Dictionary = o.get_meta("leona_anim_backup")
		if on:
			var idle_clip: String = LUtil.find_clip(o, "spell2_idle")
			var run_clip: String = LUtil.find_clip(o, "spell2_run")
			if idle_clip != "":
				o.anim_map["idle"] = [idle_clip]
			if run_clip != "":
				o.anim_map["run"] = [run_clip]
		else:
			o.anim_map["idle"] = bk.idle
			o.anim_map["run"] = bk.run
		o.cur_anim = ""

	func _detonate() -> void:
		var o = owner
		_set_stance(false)
		if o.dead:
			return
		var m = o.match_ref
		var dmg := dv("ExplosionBaseDamage") + dv("APRatio", 0.4) * ap()
		var hits := K.enemies_circle(self, o.global_position, ind_radius)
		for u in hits:
			hit(u, dmg, G.DmgType.MAGIC, {"is_aoe": true, "tag": "w"})
			LUtil.mark(o, u)
		var gp: Vector3 = o.global_position
		Vfx.burst(m, gp + Vector3(0, 1.0, 0), SUN, 1.3, {"sparks": 40, "ring": false})
		Vfx.ring(m, gp, SUN_HOT, ind_radius * G.U, 0.45, 0.12, 0.3)
		Vfx.ring(m, gp, DAWN, ind_radius * G.U * 0.7, 0.35, 0.08, 0.0)
		LUtil.shake(o, gp, 0.15)
		if not hits.is_empty():
			var dur := dv("ArmorMRDuration", 3.0)
			K.buff(o, "leona_w_keep", dur, resist_stats(), o, {"name": "Eclipse", "icon": icon})
			Vfx.aura(o, SUN, 1.0, dur, 0.06)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var r := ind_radius * G.U
		if ctx.count_enemies_near(o.global_position, r * 0.9) >= 1 and (ctx.mode == "fight" or ctx.in_danger()):
			return make_target(o.global_position)
		# soak while diving in with E / walking into a fight
		if ctx.mode == "fight" and ctx.focus != null and G.flat_dist(o.global_position, ctx.focus.global_position) < 8.0 and o.hp_ratio() < 0.9:
			return make_target(o.global_position)
		if ctx.in_danger():
			return make_target(o.global_position)
		return HOLD


class EclipseBuff extends Buff:
	var flat := 8.0
	var cap := 0.5

	func _init() -> void:
		id = "leona_w"
		display_name = "Eclipse"

	func on_pre_damage_taken(info) -> void:
		if info.amount <= 0.0 or info.type == G.DmgType.TRUE:
			return
		var resist: float = owner.stats.armor if info.type == G.DmgType.PHYSICAL else owner.stats.mr
		var k := Combat.resist_multiplier(resist, info.source, info.type == G.DmgType.PHYSICAL)
		# flat reduction applies after mitigation: convert to a pre-mitigation amount
		info.amount -= minf(flat / maxf(k, 0.05), info.amount * cap)


# ===================================================================== E
class ZenithBlade extends KAbility:
	const TRAVEL := 900.0

	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 140.0
		cast_range = 875.0
		cast_time = 0.25
		anim = "spell3"
		anim_lock = 0.45

	func is_dash() -> bool:
		return true

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var dir: Vector3 = t.dir
		var dmg := dv("BaseDamage") + 0.4 * ap()
		var root := dv("RootDuration", 0.5)
		var state := {"last": null}
		var self_ref := self
		var on_hit := func(_mm, u):
			self_ref.hit(u, dmg, G.DmgType.MAGIC, {"tag": "e"})
			LUtil.mark(o, u)
			Vfx.hit_spark(m, u.global_position + Vector3(0, 1.0, 0), SUN_HOT, 0.9)
			if u.kind == G.Kind.CHAMPION:
				state.last = u
		var on_end := func(_mm, _pos):
			var tgt = state.last
			if tgt == null or not is_instance_valid(tgt) or tgt.dead or not is_instance_valid(o) or o.dead:
				return
			self_ref._dash_to(tgt, root)
		K.line_missile(self, K.cast_pos(o, 1.0), dir, 2000.0, TRAVEL, {
			"width": 70.0, "pierce": true, "visual": _blade_visual(), "on_hit": on_hit, "on_end": on_end,
		})
		notify_cast(t)

	func _dash_to(tgt, root: float) -> void:
		var o = owner
		var m = o.match_ref
		var d := G.flat_dist(o.global_position, tgt.global_position)
		var spd := maxf(22.0, d / 0.3)
		var travel := maxf(0.0, d - o.radius - tgt.radius) / spd
		K.root(tgt, root + travel, o, SUN)
		Vfx.beam(m, o.global_position + Vector3(0, 1.0, 0), tgt.global_position + Vector3(0, 1.0, 0), SUN, 0.35, travel + 0.15)
		if (o.cc & (Buff.BLOCK_MOVE | Buff.CC.GROUNDED)) != 0:
			return
		var dest: Vector3 = tgt.global_position - G.flat_dir(o.global_position, tgt.global_position) * (o.radius + tgt.radius * 0.8)
		var trail := Vfx.rising(o, SUN, travel + 0.1, 30, 0.4)
		trail.position.y = 0.6
		o.start_dash(dest, {"speed": spd, "anim": "spell3", "on_arrive": func(_u):
			Vfx.burst(m, o.global_position + Vector3(0, 0.8, 0), SUN, 1.0, {"sparks": 16, "ring": true})})

	func _blade_visual() -> VfxNode:
		var n := VfxNode.new()
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.18, 0.08, 1.9)
		blade.mesh = bm
		var mat := Vfx.add_material(SUN_HOT, 3.0, false)
		mat.set_shader_parameter("use_mask", false)
		blade.material_override = mat
		blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		n.add_child(blade)
		var glow := Vfx.sprite(SUN, 1.6, 1.8)
		n.add_child(glow)
		var e := Vfx.emitter(SUN, 70, 0.4, 0.6, {"vmin": 0.0, "vmax": 0.3, "radius": 0.3})
		n.add_child(e)
		n.trails.append(e)
		var e2 := Vfx.emitter(SUN_HOT, 24, 0.5, 0.25, {"vmin": 0.5, "vmax": 1.5, "tex": Vfx.spark_texture()})
		n.add_child(e2)
		n.trails.append(e2)
		n.add_child(Vfx.light(SUN, 2.0, 4.0))
		return n

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if ctx.mode == "retreat" or not o.dash.is_empty():
			return HOLD
		var rng := TRAVEL * G.U * 0.93
		var t: Unit = null
		var best_s := -INF
		for e in ctx.enemies:
			var d := G.flat_dist(o.global_position, e.global_position)
			if d > rng or d < o.attack_range_m() + 1.0 or e.has_cc_immunity():
				continue
			if ctx._under_enemy_turret(e.global_position) and e.hp_ratio() > 0.25:
				continue
			var s: float = (1.0 - e.hp_ratio()) * 2.0 - d * 0.1 + (1.0 if e == ctx.focus else 0.0) + (0.8 if e.stats.attack_range > 300.0 else 0.0)
			if s > best_s:
				best_s = s
				t = e
		if t == null:
			return HOLD
		var support := 0
		for a in ctx.allies:
			if G.flat_dist(a.global_position, t.global_position) < 11.0:
				support += 1
		var enemies_there: int = ctx.count_enemies_near(t.global_position, 7.0)
		if not (ctx.mode == "fight" or support >= 1):
			return HOLD
		if o.hp_ratio() < 0.35 and t.hp_ratio() > 0.2:
			return HOLD
		if enemies_there > support + 2 and t.hp_ratio() > 0.3:
			return HOLD
		var aim: Vector3 = ctx.predict(t, cast_time + G.flat_dist(o.global_position, t.global_position) / 20.0)
		return ctx.aim_at(aim, self)


# ===================================================================== R
class SolarFlare extends KAbility:
	const INNER := 150.0

	func _init() -> void:
		target_type = Target.POINT
		indicator = Ind.CIRCLE
		ind_radius = 325.0
		cast_range = 1200.0
		cast_time = 0.25
		anim = "spell4"
		anim_lock = 0.7

	func delay() -> float:
		return 0.625

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var pos: Vector3 = t.pos
		var R := ind_radius * G.U
		var dl := delay()
		var dmg := dv("ExplosionBaseDamage") + dv("ExplosionAPRatio", 0.8) * ap()
		var cc := dv("CCDuration", 1.75)
		var slow := dv("SlowPercent", 80.0) / 100.0
		var self_ref := self
		# telegraph: outer ring, inner stun ring, a sun gathering high above
		var outer := Vfx.ground_circle(m, pos, R, SUN, dl + 0.05, 0.12)
		var omat: ShaderMaterial = outer.get_meta("mat")
		var tw := outer.create_tween()
		tw.tween_method(func(v): omat.set_shader_parameter("fill", v), 0.05, 0.4, dl)
		var inner := Vfx.ground_circle(m, pos, INNER * G.U, SUN_HOT, dl + 0.05, 0.2)
		inner.get_meta("mat").set_shader_parameter("thickness", 0.12)
		var sun := VfxNode.new()
		sun.lifetime = dl + 0.1
		m.add_fx(sun, pos + Vector3(0, 13.0, 0))
		var core := Vfx.sprite(SUN_HOT, 1.0, 3.0)
		sun.add_child(core)
		var halo := Vfx.sprite(SUN, 3.0, 1.6)
		sun.add_child(halo)
		sun.add_child(Vfx.light(SUN, 3.0, 16.0))
		var stw := sun.create_tween()
		stw.tween_property(core, "scale", Vector3.ONE * 3.0, dl).set_ease(Tween.EASE_IN)
		stw.parallel().tween_property(halo, "scale", Vector3.ONE * 6.0, dl).set_ease(Tween.EASE_IN)
		Vfx.beam(m, pos + Vector3(0, 13.0, 0), pos, SUN, 0.25, dl)
		m.after(dl, func():
			if not is_instance_valid(o):
				return
			self_ref._strike(pos, R, dmg, cc, slow))
		notify_cast(t)

	func _strike(pos: Vector3, R: float, dmg: float, cc: float, slow: float) -> void:
		var o = owner
		var m = o.match_ref
		for u in K.enemies_circle(self, pos, ind_radius):
			hit(u, dmg, G.DmgType.MAGIC, {"is_aoe": true, "tag": "r"})
			LUtil.mark(o, u)
			if G.flat_dist(pos, u.global_position) <= INNER * G.U + u.radius:
				K.stun(u, cc, o)
			else:
				K.slow(u, slow, cc, o, false, "leona_r_slow")
		Vfx.beam(m, pos + Vector3(0, 18.0, 0), pos + Vector3(0, 0.1, 0), SUN_HOT, 1.6, 0.4)
		Vfx.beam(m, pos + Vector3(0, 18.0, 0), pos + Vector3(0, 0.1, 0), SUN, 3.2, 0.3)
		Vfx.burst(m, pos + Vector3(0, 0.8, 0), SUN, R * 0.45, {"sparks": 60, "ring": false})
		Vfx.ring(m, pos, SUN_HOT, R * 1.35, 0.6, 0.15, 0.4)
		Vfx.ring(m, pos, DAWN, R * 0.9, 0.45, 0.1, 0.0)
		Vfx.ground_circle(m, pos, R, DAWN, 1.6, 0.45)
		Vfx.ground_circle(m, pos, INNER * G.U, SUN_HOT, 1.2, 0.6)
		var n := VfxNode.new()
		n.lifetime = 2.0
		m.add_fx(n, pos + Vector3(0, 0.2, 0))
		var e := Vfx.emitter(SUN_HOT, 70, 1.2, 0.3, {"one_shot": true, "explosive": 0.9, "dir": Vector3.UP, "spread": 50.0,
				"vmin": 3.0, "vmax": 9.0, "damping": 2.0, "gravity": Vector3(0, -5.0, 0), "radius": R * 0.6, "tex": Vfx.spark_texture()})
		e.emitting = true
		n.add_child(e)
		LUtil.shake(o, pos, 0.45)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var rng := range_m()
		var R := ind_radius * G.U
		var lead := cast_time + delay()
		# 1) multi-champion flare (center on the group)
		var best_n := 0
		var best := Vector3.INF
		for e in ctx.enemies:
			if G.flat_dist(p, e.global_position) > rng + R * 0.5:
				continue
			var c: Vector3 = ctx.predict(e, lead)
			var n := 0
			for e2 in ctx.enemies:
				if G.flat_dist(c, ctx.predict(e2, lead)) <= R * 0.85 + e2.radius:
					n += 1
			if n > best_n:
				best_n = n
				best = c
		if best_n >= 2 and G.flat_dist(p, best) <= rng + R * 0.3:
			return make_target(best, null)
		if ctx.mode != "fight" or ctx.focus == null:
			return HOLD
		var f: Unit = ctx.focus
		if f.has_cc_immunity() or G.flat_dist(p, f.global_position) > rng:
			return HOLD
		# 2) chain CC after E/Q, or open on a target the team can follow up on
		var e_ab = o.abilities[2]
		var q_ab = o.abilities[0]
		var e_down: bool = e_ab == null or e_ab.cast_block_reason() != ""
		var chain: bool = LUtil.immobile(f) and f.hp_ratio() > 0.2 and (o.abilities[0].is_empowered() == false)
		var allies_near := 0
		for a in ctx.allies:
			if G.flat_dist(a.global_position, f.global_position) < 9.0:
				allies_near += 1
		if chain and allies_near >= 1:
			return make_target(f.global_position, null)
		if e_down and not LUtil.immobile(f) and allies_near >= 1 and f.hp_ratio() > 0.25 and q_ab != null and not q_ab.is_empowered():
			return make_target(ctx.predict(f, lead), null)
		# 3) peel for a diven ally
		for a in ctx.allies:
			if a.hp_ratio() < 0.4:
				var threat: int = ctx.count_enemies_near(a.global_position, 3.5)
				if threat >= 1 and G.flat_dist(p, a.global_position) < rng:
					return make_target(a.global_position, null)
		return HOLD
