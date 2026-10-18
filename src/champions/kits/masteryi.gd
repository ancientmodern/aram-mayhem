extends ChampionKit
## Master Yi, the Wuju Bladesman.

const GOLD := Color(1.0, 0.82, 0.3)
const WUJU := Color(0.5, 1.0, 0.3)
const JADE := Color(0.35, 1.0, 0.6)
const VIOLET := Color(0.72, 0.42, 1.0)
const BLADE := Color(0.85, 1.0, 0.6)


func build_kit() -> void:
	c.attack_missile_speed = 0.0
	c.attack_color = WUJU
	c.role = "assassin"
	c.level_order = "QEWQQRQEQEREEWWRWW"
	var p := DoubleStrike.new()
	p.dvals = spell("MasterYiPassive").get("data_values", {})
	c.passive = p
	c.add_effect(p)
	c.abilities[0] = init_ability(AlphaStrike.new(), "Q")
	c.abilities[1] = init_ability(Meditate.new(), "W")
	c.abilities[2] = init_ability(WujuStyle.new(), "E")
	c.abilities[3] = init_ability(Highlander.new(), "R")
	c.abilities[1].anim = ""
	c.abilities[1].cast_time = 0.0
	c.add_effect(WujuHook.new(c.abilities[2]))
	c.add_effect(MeditateGuard.new(c.abilities[1]))
	c.add_effect(HighlanderPassive.new(c.abilities[3]))
	c.add_effect(BotLeveler.new())



func ai_tuning() -> Dictionary:
	return {"aggression": 0.8}


# ===================================================================== shared visuals
class Fx:
	static var _shaders := {}

	const ARC_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled%DEPTH%;
uniform vec4 color : source_color = vec4(0.5, 1.0, 0.3, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 1.0, 0.8, 1.0);
uniform float energy = 2.5;
uniform float inner = 0.45;
uniform float head = 0.0;
uniform float tail = 3.0;
uniform float fade = 1.0;
uniform float flat_tail = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float band = smoothstep(inner - 0.04, inner + 0.02, r) * (1.0 - smoothstep(0.95, 1.0, r));
	float ang = atan(p.y, p.x);
	float d = mod(head - ang + 12.566370, 6.283185);
	float g = clamp(1.0 - d / max(tail, 0.001), 0.0, 1.0);
	g = mix(g * g, step(d, tail) * 0.75, flat_tail);
	float rim = smoothstep(0.78, 0.96, r);
	vec3 col = mix(color.rgb, edge_color.rgb, rim * g);
	float a = band * g * (0.35 + 0.65 * rim) * fade;
	ALBEDO = col * energy;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

	## Ground mandala: concentric dashed rings and petals that slowly rotate (Meditate).
	const MANDALA_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, depth_test_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.82, 0.3, 1.0);
uniform float energy = 1.8;
uniform float fade = 1.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float ring1 = 1.0 - smoothstep(0.0, 0.025, abs(r - 0.92));
	float ring2 = (1.0 - smoothstep(0.0, 0.018, abs(r - 0.62))) * step(0.3, fract((ang + TIME * 0.6) / 6.283185 * 16.0));
	float petals = abs(sin(ang * 4.0 - TIME * 0.4)) ;
	float petal = (1.0 - smoothstep(0.0, 0.03, abs(r - (0.3 + 0.28 * petals)))) * step(r, 0.62);
	float glow = (1.0 - smoothstep(0.0, 0.95, r)) * 0.18;
	float a = clamp(ring1 + ring2 * 0.8 + petal * 0.7 + glow, 0.0, 1.0) * fade * (1.0 - smoothstep(0.95, 1.0, r));
	ALBEDO = color.rgb * energy;
	ALPHA = a;
}
"""

	static func shader(key: String, code: String) -> Shader:
		if not _shaders.has(key):
			var s := Shader.new()
			s.code = code
			_shaders[key] = s
		return _shaders[key]

	static func arc_mat(col: Color, edge: Color, inner: float, ground: bool) -> ShaderMaterial:
		var mat := ShaderMaterial.new()
		mat.shader = shader("arc_g" if ground else "arc", ARC_CODE.replace("%DEPTH%", ", depth_test_disabled" if ground else ""))
		mat.set_shader_parameter("color", col)
		mat.set_shader_parameter("edge_color", edge)
		mat.set_shader_parameter("inner", inner)
		return mat

	static func plane(size: float, mat: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(size, size)
		mi.mesh = pm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi

	## Crossed blade cuts on a target ("X" slash).
	static func cross(m, pos: Vector3, col: Color, size: float, dur: float) -> void:
		var a := G.rng.randf() * PI
		for i in 2:
			var ang := a + i * PI * 0.5 + G.rng.randf_range(-0.2, 0.2)
			var off := Vector3(cos(ang), 0.35 * (1 if i == 0 else -1), sin(ang)) * size
			Vfx.beam(m, pos - off, pos + off, col, 0.14, dur)

	static func afterimage(m, pos: Vector3, col: Color, dur: float) -> void:
		var n := VfxNode.new()
		n.lifetime = dur + 0.1
		m.add_fx(n, pos + Vector3(0, 1.1, 0))
		var s := Vfx.sprite(col, 2.2, 1.6)
		s.scale = Vector3(1.1, 2.4, 1.1)
		n.add_child(s)
		var tw := n.create_tween()
		tw.tween_property(s, "scale", Vector3(0.2, 3.0, 0.2), dur).set_ease(Tween.EASE_IN)

	static func sweep(m, pos: Vector3, radius: float, inner: float, col: Color, edge: Color, start_ang: float, turns: float, dur: float, height: float = 0.9, ground: bool = false) -> VfxNode:
		var n := VfxNode.new()
		n.lifetime = dur + 0.4
		m.add_fx(n, pos + Vector3(0, height, 0))
		var mat := arc_mat(col, edge, inner, ground)
		mat.set_shader_parameter("head", start_ang)
		mat.set_shader_parameter("tail", 0.4)
		n.add_child(plane(radius * 2.0, mat))
		var tw := n.create_tween()
		tw.tween_method(func(v): mat.set_shader_parameter("head", v), start_ang, start_ang + TAU * turns, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.parallel().tween_method(func(v): mat.set_shader_parameter("tail", v), 0.4, minf(4.5, TAU * absf(turns) + 0.2), dur)
		tw.tween_method(func(v): mat.set_shader_parameter("fade", v), 1.0, 0.0, 0.3)
		return n


# ===================================================================== helpers
## Bots never spend points after spawning (core gap): level abilities on their behalf.
class BotLeveler extends Effect:
	func _init() -> void:
		id = "kit_bot_leveler"
		hidden = true

	func on_tick(u, _dt: float) -> void:
		if u.is_bot and u.ability_points > 0:
			u.auto_level_abilities()


class YiAbility extends Ability:
	func try_cast(t: Dictionary) -> bool:
		if t.get("skip", false):
			return false
		return super.try_cast(t)

	func skip() -> Dictionary:
		return {"skip": true}

	func now() -> float:
		return owner.match_ref.time if owner.match_ref != null else 0.0

	func self_target() -> Dictionary:
		return {"pos": owner.global_position, "dir": owner.facing, "unit": null}

	func in_alpha() -> bool:
		var q = owner.abilities[0]
		return q != null and q.active


# ===================================================================== passive
class DoubleStrike extends Effect:
	var dvals := {}
	var count := 0
	var last_attack := -100.0
	var striking := false

	func _init() -> void:
		id = "yi_passive"
		display_name = "Double Strike"

	func val(n: String, d: float) -> float:
		return float(dvals.get(n, d))

	func now() -> float:
		return owner.match_ref.time if owner.match_ref != null else 0.0

	func hud_counter() -> String:
		return str(count) if count > 0 else ""

	func on_tick(_u, _dt: float) -> void:
		if count > 0 and now() - last_attack > val("StackDuration", 4.0):
			count = 0

	func on_attack_hit(target, info) -> void:
		if info == null or info.cancelled:
			return
		var o = owner
		var q = o.abilities[0]
		if q != null and q.level > 0:
			q.reduce_cooldown(q.dv("BasicAttackCDR", 1.0))
		if striking:
			return
		last_attack = now()
		count += 1
		if count >= int(val("AttackCount", 4.0)):
			count = 0
			var self_ref := self
			o.match_ref.after(0.14, func(): self_ref._second(target))

	func _second(target) -> void:
		var o = owner
		if o.dead or not o.attack_valid(target) or not o.can_attack():
			return
		striking = true
		var crit: bool = G.rng.randf() < o.stats.crit_chance
		o.attack_hit(target, crit, 0.5)
		striking = false
		var m = o.match_ref
		var tp: Vector3 = target.global_position + Vector3(0, 1.1, 0)
		Fx.cross(m, tp, BLADE, 1.0, 0.16)
		Vfx.hit_spark(m, tp, GOLD, 0.8)
		o.play_anim("crit", 1.6, 0.03)
		o.anim_lock = 0.3


# ===================================================================== Q
class AlphaStrike extends YiAbility:
	var active := false

	func _init() -> void:
		target_type = Target.UNIT
		target_side = Side.ENEMY
		indicator = Ind.NONE
		cast_range = 600.0
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0
		uninterruptible = true

	func damage_vs(first: bool) -> float:
		var d := dv("BaseDamage") + dv("AttackDamageRatio", 0.7) * ad()
		if not first:
			d *= dv("SubsequentHitMultiplier", 0.25)
		return d * (1.0 + owner.stats.crit_chance * dv("BonusCritDamageRatio", 1.0))

	func extra_block_reason() -> String:
		return "casting" if active else ""

	func execute(t: Dictionary) -> void:
		var o = owner
		var u = t.unit
		if u == null or not is_instance_valid(u) or u.dead:
			return
		var m = o.match_ref
		active = true
		o.cancel_windup()
		o.stop_moving()
		o.untargetable_count += 1
		o.invulnerable_count += 1
		if o.model != null:
			o.model.visible = false
		var strikes := int(dv("AlphaStrikeBounces", 4.0))
		var interval := 0.19
		var total := strikes * interval + 0.08
		start_channel(total, {})
		o.channel_disarm = true
		Fx.afterimage(m, o.global_position, BLADE, 0.3)
		Vfx.burst(m, o.global_position + Vector3(0, 1.0, 0), WUJU, 0.9, {"ring": false, "sparks": 18, "light": false})
		var st := {"last": null, "pos": o.global_position, "hit": {}}
		var self_ref := self
		for i in strikes:
			m.after(0.04 + i * interval, func(): self_ref._strike(i, u, st))
		m.after(total, func(): self_ref._finish(u, st))
		notify_cast(t)

	func _pick(i: int, primary, st: Dictionary):
		var o = owner
		var hset: Dictionary = st.hit
		if i == 0 and is_instance_valid(primary) and not primary.dead:
			return primary
		var center: Vector3 = primary.global_position if is_instance_valid(primary) and not primary.dead else st.pos
		var best = null
		var best_s := INF
		for e in o.match_ref.enemies_in_radius(o.team, center, cast_range * G.U):
			if hset.has(e):
				continue
			var s := G.flat_dist(center, e.global_position) + (0.0 if e.kind == G.Kind.CHAMPION else 6.0)
			if s < best_s:
				best_s = s
				best = e
		if best != null:
			return best
		if is_instance_valid(primary) and not primary.dead:
			return primary
		for e in hset:
			if is_instance_valid(e) and not e.dead:
				return e
		return null

	func _strike(i: int, primary, st: Dictionary) -> void:
		var o = owner
		if o.dead:
			return
		var m = o.match_ref
		var tgt = _pick(i, primary, st)
		if tgt == null:
			return
		var first: bool = not st.hit.has(tgt)
		st.hit[tgt] = true
		hit(tgt, damage_vs(first), G.DmgType.PHYSICAL, {"tag": "yi_q"})
		var e_ab = o.abilities[2]
		if e_ab != null and e_ab.is_active() and is_instance_valid(tgt) and not tgt.dead:
			hit(tgt, e_ab.on_hit_damage() * dv("BaseOnHitMultiplier", 0.75), G.DmgType.TRUE, {"tag": "yi_wuju"})
		var from: Vector3 = st.pos
		var tp: Vector3 = tgt.global_position
		var a := G.rng.randf() * TAU
		var land: Vector3 = tp + Vector3(cos(a), 0, sin(a)) * (tgt.radius + 0.7)
		if m.nav != null and not m.nav.is_walkable(land):
			land = tp
		o.teleport(land)
		o.face_toward(tp, 100.0)
		st.pos = land
		st.last = tgt
		var h := Vector3(0, 1.1, 0)
		Vfx.beam(m, from + h, land + h, Color(0.7, 1.0, 0.4), 0.22, 0.22)
		Vfx.beam(m, from + h, land + h, GOLD, 0.07, 0.18)
		Fx.cross(m, tp + h, BLADE, 1.2, 0.2)
		Fx.afterimage(m, land, WUJU, 0.22)
		Vfx.hit_spark(m, tp + h, GOLD, 0.9)

	func _finish(primary, st: Dictionary) -> void:
		var o = owner
		if not active:
			return
		active = false
		o.untargetable_count = maxi(0, o.untargetable_count - 1)
		o.invulnerable_count = maxi(0, o.invulnerable_count - 1)
		if o.model != null:
			o.model.visible = true
		if not o.channel.is_empty() and o.channel.ability == self:
			o.channel = {}
		o.channel_disarm = false
		var m = o.match_ref
		var tgt = primary if is_instance_valid(primary) and not primary.dead else st.last
		if tgt != null and is_instance_valid(tgt) and not tgt.dead:
			var tp: Vector3 = tgt.global_position
			var back: Vector3 = tp + G.flat_dir(tp, st.pos) * (tgt.radius + o.radius + 0.3)
			if m.nav != null and m.nav.is_walkable(back):
				o.teleport(back)
			o.face_toward(tp, 100.0)
		o.reset_attack()
		if o.is_bot and tgt != null and is_instance_valid(tgt) and not tgt.dead and tgt.kind == G.Kind.CHAMPION:
			o.issue_attack(tgt)
		Vfx.burst(m, o.global_position + Vector3(0, 1.0, 0), WUJU, 1.1, {"sparks": 22})
		Fx.sweep(m, o.global_position, 1.6, 0.5, WUJU, Color(1, 1, 0.8), atan2(o.facing.z, o.facing.x), 0.9, 0.16, 1.0)

	func channel_end(_ch: Dictionary, _interrupted: bool) -> void:
		owner.channel_disarm = false

	## True when a dangerous targeted projectile / ability is about to hit Yi.
	func threatened() -> bool:
		var o = owner
		for mi in o.match_ref.missiles:
			if not is_instance_valid(mi) or not mi.alive or mi.team == o.team:
				continue
			if mi.is_attack:
				continue
			var d := G.flat_dist(mi.global_position, o.global_position)
			if d > 5.0:
				continue
			if (mi.mode == Missile.Mode.HOMING or mi.mode == Missile.Mode.FOLLOW) and mi.target == o:
				return true
			if mi.mode == Missile.Mode.LINEAR and mi.dir.dot(G.flat_dir(mi.global_position, o.global_position)) > 0.9 and d < 3.5:
				return true
		return false

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var f = ctx.focus
		var in_rng := func(u) -> bool:
			return valid_unit_target(u) and G.flat_dist(p, u.global_position) <= range_m() + o.radius + u.radius
		if threatened() or (ctx.in_danger() and o.hp_ratio() < 0.25):
			var any = null
			for e in ctx.enemies:
				if in_rng.call(e):
					any = e
					break
			if any == null:
				for mn in ctx.enemy_minions:
					if in_rng.call(mn):
						any = mn
						break
			if any != null:
				return {"unit": any, "pos": any.global_position}
		if ctx.mode == "fight" and f != null and is_instance_valid(f) and in_rng.call(f):
			var d := G.flat_dist(p, f.global_position)
			var melee: float = o.attack_range_m() + o.radius + f.radius
			if d > melee + 1.0 or f.hp_ratio() < 0.35 or ctx.count_enemies_near(f.global_position, 4.0) >= 2:
				return {"unit": f, "pos": f.global_position}
		if ctx.enemies.is_empty() and o.mana > o.stats.max_mana * 0.6:
			for mn in ctx.enemy_minions:
				if in_rng.call(mn) and ctx.count_enemies_near(mn.global_position, 4.0, false) >= 4:
					return {"unit": mn, "pos": mn.global_position}
		return skip()


# ===================================================================== W
class Meditate extends YiAbility:
	var channeling := false
	var dr_until := -1.0
	var extra_until := -1.0
	var fx: VfxNode = null

	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return self_target()

	func extra_block_reason() -> String:
		return "casting" if in_alpha() or channeling else ""

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var dur := dv("HealDuration", 4.0)
		channeling = true
		extra_until = now() + dv("InitialExtraDRDuration", 0.5)
		dr_until = now() + dur + dv("DRLinger", 0.5)
		o.cancel_windup()
		o.stop_moving()
		o.play_anim("spell2", 1.0, 0.1)
		o.anim_lock = 0.7
		start_channel(dur, {"acc": 0.0, "elapsed": 0.0})
		o.channel_disarm = true
		fx = VfxNode.new()
		fx.lifetime = dur + 0.2
		o.add_child(fx)
		var mat := ShaderMaterial.new()
		mat.shader = Fx.shader("mandala", Fx.MANDALA_CODE)
		mat.set_shader_parameter("color", GOLD)
		var mandala := Fx.plane(3.4, mat)
		mandala.position.y = 0.1
		fx.add_child(mandala)
		var dome := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.25
		sm.height = 2.5
		dome.mesh = sm
		var dm := Vfx.add_material(Color(1.0, 0.85, 0.4, 0.45), 1.0, false)
		dm.set_shader_parameter("use_mask", false)
		dome.material_override = dm
		dome.position.y = 1.0
		dome.scale = Vector3(1.0, 0.9, 1.0)
		fx.add_child(dome)
		var e := Vfx.emitter(GOLD, 30, 1.2, 0.2, {"vmin": 0.4, "vmax": 1.0, "dir": Vector3.UP, "spread": 10.0, "radius": 0.9, "local": true})
		fx.add_child(e)
		var l := Vfx.light(GOLD, 1.8, 4.0)
		l.position.y = 1.4
		fx.add_child(l)
		var tw := fx.create_tween().set_loops()
		tw.tween_property(dome, "scale", Vector3(1.06, 0.95, 1.06), 0.6).set_trans(Tween.TRANS_SINE)
		tw.tween_property(dome, "scale", Vector3(1.0, 0.9, 1.0), 0.6).set_trans(Tween.TRANS_SINE)
		Vfx.ring(m, o.global_position, GOLD, 2.2, 0.4, 0.08, 0.1)
		notify_cast(t)

	func channel_tick(dt: float, ch: Dictionary) -> void:
		var o = owner
		ch.elapsed += dt
		ch.acc += dt
		# Meditate pauses Wuju Style and Highlander
		for bid in ["yi_wuju", "yi_highlander"]:
			var b = o.find_buff(bid)
			if b != null:
				b.remaining += dt
		var interval := dv("TickFrequency", 0.5)
		var ticks := dv("HealDuration", 4.0) / interval
		while ch.acc >= interval:
			ch.acc -= interval
			var total := dv("BaseHeal") + ap()
			var amt: float = total / ticks * (1.0 + (1.0 - o.hp_ratio()) * dv("MaxMissingHealthPercent", 1.0))
			Combat.heal(o, o, amt)
		if o.is_bot and ch.elapsed > 1.0 and o.hp_ratio() > 0.9:
			ch.t = 0.0

	func channel_end(_ch: Dictionary, _interrupted: bool) -> void:
		var o = owner
		channeling = false
		o.channel_disarm = false
		o.anim_lock = 0.0
		dr_until = minf(dr_until, now() + dv("DRLinger", 0.5))
		if fx != null and is_instance_valid(fx):
			fx.detach_and_fade()
		fx = null

	func current_dr(src) -> float:
		if now() > dr_until:
			return 0.0
		var dr := dv("DamageReduction", 0.45)
		if now() < extra_until:
			dr += dv("InitialExtraDR", 0.25)
		if src != null and is_instance_valid(src) and src.kind == G.Kind.TURRET:
			dr *= dv("DamageReductionTowerMod", 0.5)
		return dr

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var f = ctx.focus
		var hp: float = o.hp_ratio()
		if ctx.mode == "fight" and f != null and is_instance_valid(f) and f.hp_ratio() < 0.15 and o.in_attack_range(f, 0.5) and hp > 0.15:
			return skip()
		# never meditate in turret range (the damage reduction is halved against turrets)
		if ctx._under_enemy_turret(o.global_position):
			return skip()
		if not ctx.enemies.is_empty() and hp < 0.3:
			return self_target()
		elif hp < 0.55 and ctx.enemy_minions.size() < 3:
			return self_target()
		return skip()


## Meditate's damage reduction (halved against turrets).
class MeditateGuard extends Effect:
	var w

	func _init(p_w) -> void:
		w = p_w
		id = "yi_w_dr"
		hidden = true

	func on_pre_damage_taken(info) -> void:
		var dr: float = w.current_dr(info.source)
		if dr > 0.0:
			info.mult *= 1.0 - dr


# ===================================================================== E
class WujuStyle extends YiAbility:
	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0
		anim = "spell3"
		anim_lock = 0.25

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return self_target()

	func is_active() -> bool:
		return owner.has_buff("yi_wuju")

	func on_hit_damage() -> float:
		return dv("BaseDamage") + dv("ADRatio", 0.35) * bonus_ad()

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var dur := dv("Duration", 5.0)
		var b := K.buff(o, "yi_wuju", dur, {}, o, {"name": "Wuju Style", "icon": icon})
		if b != null and (b.vfx == null or not is_instance_valid(b.vfx)):
			var n := VfxNode.new()
			o.add_child(n)
			b.vfx = n
			var e := Vfx.emitter(WUJU, 30, 0.7, 0.2, {"vmin": 0.6, "vmax": 1.6, "dir": Vector3.UP, "spread": 25.0, "radius": 0.55, "local": false})
			e.position.y = 0.5
			n.add_child(e)
			var glow := Vfx.sprite(WUJU, 1.8, 0.8)
			glow.position.y = 1.2
			n.add_child(glow)
			var l := Vfx.light(WUJU, 1.5, 3.5)
			l.position.y = 1.3
			n.add_child(l)
			var ring := Vfx.aura(o, WUJU, 1.0, dur, 0.06)
			ring.reparent(n)
		Vfx.burst(m, o.global_position + Vector3(0, 1.2, 0), WUJU, 1.0, {"sparks": 20, "ring": false})
		Fx.sweep(m, o.global_position, 1.5, 0.55, WUJU, Color(1, 1, 0.8), atan2(o.facing.z, o.facing.x), 1.0, 0.25, 1.2)
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if is_active():
			return skip()
		var f = ctx.focus
		if ctx.mode == "fight" and f != null and is_instance_valid(f) and o.in_attack_range(f, 1.2):
			return self_target()
		var at = o.attack_target
		if ctx.enemies.is_empty() and at != null and is_instance_valid(at) and at.kind == G.Kind.TURRET and o.in_attack_range(at, 0.3):
			return self_target()
		return skip()


class WujuHook extends Effect:
	var e_ab

	func _init(p_e) -> void:
		e_ab = p_e
		id = "yi_wuju_hook"
		hidden = true

	func on_attack_hit(target, info) -> void:
		if info == null or info.cancelled or not e_ab.is_active():
			return
		if target == null or not is_instance_valid(target) or target.dead:
			return
		Combat.deal(owner, target, e_ab.on_hit_damage(), G.DmgType.TRUE, {"is_proc": true, "tag": "yi_wuju", "ability": e_ab})
		Vfx.hit_spark(owner.match_ref, target.global_position + Vector3(0, 1.1, 0), WUJU, 0.7)


# ===================================================================== R
class Highlander extends YiAbility:
	var saved_run: Array = []

	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return self_target()

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var dur := dv("RDuration", 7.0)
		for b0 in o.buffs.duplicate():
			if b0.slow_amount > 0.0:
				o.remove_buff(b0)
		var b := K.buff(o, "yi_highlander", dur, {"as": dv("RASBonus") / 100.0, "ms%": dv("RMSBonus") / 100.0, "slow_resist": 1.0}, o,
				{"name": "Highlander", "icon": icon})
		if b != null and (b.vfx == null or not is_instance_valid(b.vfx)):
			var n := VfxNode.new()
			o.add_child(n)
			b.vfx = n
			var trail := Vfx.emitter(VIOLET, 50, 0.45, 0.4, {"vmin": 0.0, "vmax": 0.3, "radius": 0.45})
			trail.position.y = 1.0
			n.add_child(trail)
			var sparks := Vfx.emitter(GOLD, 24, 0.5, 0.16, {"vmin": 1.0, "vmax": 2.2, "dir": Vector3.UP, "spread": 35.0, "radius": 0.5, "tex": Vfx.spark_texture()})
			sparks.position.y = 0.6
			n.add_child(sparks)
			var glow := Vfx.sprite(VIOLET, 2.4, 0.9)
			glow.position.y = 1.2
			n.add_child(glow)
			var l := Vfx.light(VIOLET, 2.2, 4.0)
			l.position.y = 1.4
			n.add_child(l)
			var clip: String = o._raw_clip("run_haste")
			if clip != "":
				saved_run = o.anim_map.get("run", []).duplicate()
				o.anim_map["run"] = [clip]
				o.cur_anim = ""
			var self_ref := self
			b.on_expire = func(_bb): self_ref._restore_run()
		Vfx.burst(m, o.global_position + Vector3(0, 1.2, 0), VIOLET, 1.6, {"sparks": 34})
		Vfx.ring(m, o.global_position, GOLD, 3.0, 0.45, 0.08, 0.1)
		Vfx.rising(o, GOLD, 0.5, 30, 0.5)
		notify_cast(t)

	func _restore_run() -> void:
		var o = owner
		if not saved_run.is_empty():
			o.anim_map["run"] = saved_run
			saved_run = []
			o.cur_anim = ""

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if o.has_buff("yi_highlander"):
			return skip()
		var f = ctx.focus
		if ctx.mode == "fight" and f != null and is_instance_valid(f):
			var d := G.flat_dist(o.global_position, f.global_position)
			if d < 9.0 and (f.hp_ratio() < 0.6 or ctx.enemies.size() >= 2 or o.stats.slow > 0.1):
				return self_target()
		if ctx.mode == "retreat" and ctx.in_danger() and o.stats.slow > 0.2:
			return self_target()
		return skip()


## Highlander passive: takedowns slash basic cooldowns by 70% and extend an active Highlander.
class HighlanderPassive extends Effect:
	var r

	func _init(p_r) -> void:
		r = p_r
		id = "yi_r_passive"
		hidden = true

	func on_takedown(victim) -> void:
		if victim == null or victim.kind != G.Kind.CHAMPION or r.level <= 0:
			return
		var o = owner
		for i in 3:
			var a = o.abilities[i]
			if a != null and a.cd > 0.0:
				a.reduce_cooldown_pct(r.dv("RCooldownRefund", 0.7))
		var b = o.find_buff("yi_highlander")
		if b != null:
			b.remaining += r.dv("RKillAssistExtension", 7.0)
			b.duration = maxf(b.duration, b.remaining)
		Vfx.rising(o, GOLD, 0.4, 24, 0.5)
		Vfx.ring(o.match_ref, o.global_position, VIOLET, 2.0, 0.35, 0.08, 0.0)
