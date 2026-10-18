extends ChampionKit
## Malphite, Shard of the Monolith.

const AMBER := Color(1.0, 0.62, 0.22)
const MAGMA := Color(1.0, 0.42, 0.1)
const DUST := Color(0.78, 0.66, 0.5)
const STONE := Color(0.52, 0.45, 0.4)
const GLOW := Color(1.0, 0.82, 0.45)


func build_kit() -> void:
	c.attack_missile_speed = 0.0
	c.attack_color = AMBER
	c.role = "tank"
	c.level_order = "QEWQQRQEQEREEWWRWW"
	var p := GraniteShield.new()
	c.passive = p
	c.add_effect(p)
	c.abilities[0] = init_ability(SeismicShard.new(), "Q")
	c.abilities[1] = init_ability(Thunderclap.new(), "W")
	c.abilities[2] = init_ability(GroundSlam.new(), "E")
	c.abilities[3] = init_ability(UnstoppableForce.new(), "R")
	c.abilities[3].anim = ""
	c.abilities[3].cast_time = 0.0
	c.add_effect(ThunderclapHook.new(c.abilities[1]))
	c.add_effect(BotLeveler.new())



func ai_tuning() -> Dictionary:
	return {"aggression": 0.75}


# ===================================================================== shared visuals
class Fx:
	static var _shaders := {}
	static var _rock_mat: StandardMaterial3D = null

	const ARC_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled%DEPTH%;
uniform vec4 color : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
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

	const CRACK_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, depth_test_disabled;
uniform vec4 color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float energy = 2.2;
uniform float fade = 1.0;
uniform float progress = 1.0;
uniform float seed = 0.0;
uniform float rays = 9.0;
float hash(float n) { return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453); }
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x) / 6.283185 + 0.5;
	float cell = floor(ang * rays);
	float f = fract(ang * rays);
	float center = 0.5 + (hash(cell) - 0.5) * 0.5 + sin(r * 16.0 + hash(cell + 3.0) * 6.28) * 0.07;
	float len = 0.55 + 0.45 * hash(cell + 7.0);
	float w_abs = 0.035 * (1.0 - r / len) + 0.006;
	float w = w_abs * rays / (6.283185 * max(r, 0.04));
	float line = 1.0 - smoothstep(w * 0.5, w, abs(f - center));
	line *= 1.0 - smoothstep(len * progress - 0.08, len * progress, r);
	float core = (1.0 - smoothstep(0.0, 0.22 * progress, r)) * 0.7;
	float a = clamp(line + core, 0.0, 1.0) * fade;
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

	static func rock_material() -> StandardMaterial3D:
		if _rock_mat == null:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = STONE
			mat.roughness = 0.95
			mat.emission_enabled = true
			mat.emission = Color(0.35, 0.18, 0.05)
			mat.emission_energy_multiplier = 0.6
			_rock_mat = mat
		return _rock_mat

	## Chunky lit rock (prism) mesh.
	static func rock(size: float) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var pm := PrismMesh.new()
		pm.size = Vector3(size, size * 1.3, size * 0.9)
		pm.left_to_right = G.rng.randf()
		mi.mesh = pm
		mi.material_override = rock_material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.rotation = Vector3(G.rng.randf() * TAU, G.rng.randf() * TAU, G.rng.randf() * TAU)
		return mi

	static func wedge(m, pos: Vector3, radius: float, inner: float, col: Color, edge: Color, center_ang: float, width_rad: float, dur: float) -> VfxNode:
		var n := VfxNode.new()
		n.lifetime = dur + 0.05
		m.add_fx(n, pos + Vector3(0, 0.1, 0))
		var mat := arc_mat(col, edge, inner, true)
		mat.set_shader_parameter("head", center_ang + width_rad * 0.5)
		mat.set_shader_parameter("tail", width_rad)
		mat.set_shader_parameter("flat_tail", 1.0)
		n.add_child(plane(radius * 2.0, mat))
		var tw := n.create_tween()
		tw.tween_method(func(v): mat.set_shader_parameter("fade", v), 1.0, 0.0, dur).set_ease(Tween.EASE_IN)
		return n

	static func cracks(m, pos: Vector3, radius: float, col: Color, dur: float, rays: float = 9.0) -> VfxNode:
		var n := VfxNode.new()
		n.lifetime = dur + 0.05
		m.add_fx(n, pos + Vector3(0, 0.1, 0))
		var mat := ShaderMaterial.new()
		mat.shader = shader("crack", CRACK_CODE)
		mat.set_shader_parameter("color", col)
		mat.set_shader_parameter("rays", rays)
		mat.set_shader_parameter("seed", G.rng.randf() * 100.0)
		mat.set_shader_parameter("progress", 0.0)
		n.add_child(plane(radius * 2.0, mat))
		var tw := n.create_tween()
		tw.tween_method(func(v): mat.set_shader_parameter("progress", v), 0.0, 1.0, 0.14).set_ease(Tween.EASE_OUT)
		tw.tween_interval(dur * 0.45)
		tw.tween_method(func(v): mat.set_shader_parameter("fade", v), 1.0, 0.0, dur * 0.55 - 0.14)
		return n

	## Ring of stone spikes erupting from the ground, then sinking back.
	static func spikes(m, pos: Vector3, radius: float, count: int, height: float, dur: float) -> void:
		var n := VfxNode.new()
		n.lifetime = dur + 0.1
		m.add_fx(n, pos)
		for i in count:
			var a := TAU * i / float(count) + G.rng.randf_range(-0.2, 0.2)
			var r := radius * G.rng.randf_range(0.75, 1.05)
			var sp := MeshInstance3D.new()
			var pm := PrismMesh.new()
			var h := height * G.rng.randf_range(0.6, 1.1)
			pm.size = Vector3(0.5, h, 0.45)
			sp.mesh = pm
			sp.material_override = rock_material()
			sp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var holder := Node3D.new()
			n.add_child(holder)
			holder.position = Vector3(cos(a) * r, 0.0, sin(a) * r)
			holder.rotation = Vector3(sin(a) * 0.45, 0.0, -cos(a) * 0.45)
			holder.add_child(sp)
			sp.position.y = -h * 0.5
			var tw := holder.create_tween()
			tw.tween_property(sp, "position:y", h * 0.45, 0.1).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
			tw.tween_interval(dur * 0.5)
			tw.tween_property(sp, "position:y", -h * 0.6, dur * 0.4).set_ease(Tween.EASE_IN)

	static func debris(m, pos: Vector3, amount: int, speed: float, size: float, life: float = 0.8) -> void:
		var n := VfxNode.new()
		n.lifetime = life + 0.1
		m.add_fx(n, pos)
		var chunks := []
		for i in amount:
			var rk := rock(size * G.rng.randf_range(0.6, 1.3))
			n.add_child(rk)
			var dir := Vector3(G.rng.randf_range(-1, 1), G.rng.randf_range(0.6, 1.4), G.rng.randf_range(-1, 1)).normalized()
			chunks.append([rk, dir * speed * G.rng.randf_range(0.5, 1.0), Vector3(G.rng.randf(), G.rng.randf(), G.rng.randf()) * 8.0])
		var st := {"t": 0.0}
		m.add_ticker(life, func(dt):
			if not is_instance_valid(n):
				return false
			st.t += dt
			for ch in chunks:
				var rk2: MeshInstance3D = ch[0]
				ch[1].y -= 16.0 * dt
				rk2.position += ch[1] * dt
				if rk2.position.y < 0.0:
					rk2.position.y = 0.0
					ch[1] *= 0.4
				rk2.rotation += ch[2] * dt
				rk2.scale = Vector3.ONE * clampf(1.4 - st.t / life * 1.4, 0.0, 1.0)
			return true)

	static func dust(m, pos: Vector3, amount: int, radius: float, life: float = 1.0) -> void:
		var n := VfxNode.new()
		n.lifetime = life + 0.2
		m.add_fx(n, pos + Vector3(0, 0.3, 0))
		var e := Vfx.emitter(DUST, amount, life, 0.9, {"one_shot": true, "explosive": 0.85, "vmin": radius * 1.2, "vmax": radius * 2.6,
				"spread": 80.0, "dir": Vector3.UP, "radius": radius * 0.3, "damping": radius * 2.2, "energy": 0.9, "end_scale": 1.6})
		var pm: ParticleProcessMaterial = e.process_material
		pm.direction = Vector3(0, 0.35, 0)
		pm.spread = 180.0
		pm.flatness = 0.75
		e.emitting = true
		n.add_child(e)


# ===================================================================== helpers
## Bots never spend points after spawning (core gap): level abilities on their behalf.
class BotLeveler extends Effect:
	func _init() -> void:
		id = "kit_bot_leveler"
		hidden = true

	func on_tick(u, _dt: float) -> void:
		if u.is_bot and u.ability_points > 0:
			u.auto_level_abilities()


class MAbility extends Ability:
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


# ===================================================================== passive
class GraniteShield extends Effect:
	const SID := "malphite_granite"
	var last_hit := -100.0
	var shell: VfxNode = null
	var was_active := false

	func _init() -> void:
		id = "malphite_passive"
		display_name = "Granite Shield"

	func now() -> float:
		return owner.match_ref.time if owner.match_ref != null else 0.0

	func recharge_time() -> float:
		var lv: int = owner.level
		return 8.0 if lv < 7 else (7.0 if lv < 13 else 6.0)

	func is_active() -> bool:
		for s in owner.shields:
			if s.id == SID:
				return true
		return false

	func hud_counter() -> String:
		if is_active():
			return ""
		var left := recharge_time() - (now() - last_hit)
		return str(int(ceil(left))) if left > 0.0 else ""

	func on_damage_taken(info) -> void:
		if info.final + info.absorbed > 0.0:
			last_hit = now()

	func on_respawn() -> void:
		last_hit = -100.0

	func on_tick(u, _dt: float) -> void:
		if u.dead:
			return
		var on := is_active()
		if not on and now() - last_hit >= recharge_time():
			Combat.shield(u, u, 0.1 * u.stats.max_hp, 1.0e6, {"id": SID})
			on = true
			var m = u.match_ref
			if m != null and u.model != null:
				Vfx.ring(m, u.global_position, AMBER, 1.8, 0.35, 0.08, 0.15)
				Vfx.rising(u, GLOW, 0.3, 16, 0.6)
		if was_active and not on and u.match_ref != null:
			# shell shatters
			Fx.debris(u.match_ref, u.global_position + Vector3(0, 1.2, 0), 7, 4.0, 0.35, 0.7)
			Vfx.hit_spark(u.match_ref, u.global_position + Vector3(0, 1.3, 0), AMBER, 1.0)
		was_active = on
		_update_shell(u, on)

	## Three granite chunks orbiting Malphite while the shield is up.
	func _update_shell(u, on: bool) -> void:
		if shell == null or not is_instance_valid(shell):
			shell = VfxNode.new()
			u.add_child(shell)
			shell.position.y = 1.3
			for i in 3:
				var a := TAU * i / 3.0
				var rk := Fx.rock(0.32)
				rk.position = Vector3(cos(a), 0.15 * (i - 1), sin(a)) * maxf(1.1, u.radius * 1.5)
				shell.add_child(rk)
			var glow := Vfx.sprite(AMBER, 0.6, 1.2)
			glow.position = Vector3(0, 0, 0)
			glow.visible = false
			shell.add_child(glow)
			var spin := shell.create_tween().set_loops()
			spin.tween_property(shell, "rotation:y", TAU, 3.0).from(0.0)
		if shell.visible != on:
			shell.visible = on


# ===================================================================== Q
class SeismicShard extends MAbility:
	func _init() -> void:
		target_type = Target.UNIT
		target_side = Side.ENEMY
		indicator = Ind.NONE
		cast_range = 625.0
		cast_time = 0.25
		anim = "spell2"
		anim_lock = 0.5

	func damage() -> float:
		return dv("BaseDamage") + 0.6 * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var u = t.unit
		if u == null or not is_instance_valid(u) or u.dead:
			notify_cast(t)
			return
		var m = o.match_ref
		var self_ref := self
		var vis := VfxNode.new()
		var spinner := Node3D.new()
		vis.add_child(spinner)
		var rk := Fx.rock(0.55)
		spinner.add_child(rk)
		var rk2 := Fx.rock(0.35)
		rk2.position = Vector3(0.2, 0.15, 0.1)
		spinner.add_child(rk2)
		vis.add_child(Vfx.sprite(AMBER, 0.9, 1.4))
		var trail := Vfx.emitter(DUST, 40, 0.5, 0.4, {"vmin": 0.0, "vmax": 0.5, "radius": 0.2, "energy": 1.2})
		vis.add_child(trail)
		vis.trails.append(trail)
		var embers := Vfx.emitter(AMBER, 20, 0.3, 0.14, {"vmin": 0.3, "vmax": 1.0, "radius": 0.15, "tex": Vfx.spark_texture()})
		vis.add_child(embers)
		vis.trails.append(embers)
		vis.add_child(Vfx.light(AMBER, 1.5, 3.0))
		var tw := vis.create_tween().set_loops()
		tw.tween_property(spinner, "rotation", Vector3(TAU, TAU * 0.5, 0), 0.4).from(Vector3.ZERO)
		var dmg := damage()
		var mi := K.homing_missile(self, K.cast_pos(o, 1.2), u, 1200.0, func(_mm, tgt):
			self_ref._land(tgt, dmg), {"visual": vis, "height": 0.6})
		mi.on_move = func(mm, _dt):
			mm.height = 0.45 + absf(sin(mm.traveled * 1.15)) * 1.1
		notify_cast(t)

	func _land(tgt, dmg: float) -> void:
		var o = owner
		var m = o.match_ref
		if tgt == null or not is_instance_valid(tgt) or tgt.dead:
			return
		hit(tgt, dmg, G.DmgType.MAGIC, {"tag": "malph_q"})
		var pct := dv("SpeedSteal", 20.0) / 100.0
		var dur := dv("SlowDuration", 3.0)
		K.slow(tgt, pct, dur, o, false, "malph_q_slow")
		if not o.dead:
			K.haste(o, pct, dur, o, false, "malph_q_ms")
			var hv := VfxNode.new()
			hv.lifetime = dur
			o.add_child(hv)
			var e := Vfx.emitter(DUST, 24, 0.6, 0.35, {"vmin": 0.2, "vmax": 0.6, "radius": 0.5, "energy": 1.0})
			e.position.y = 0.2
			hv.add_child(e)
			hv.trails.append(e)
		var tp: Vector3 = tgt.global_position + Vector3(0, 1.0, 0)
		Fx.debris(m, tp, 6, 4.5, 0.25, 0.6)
		Vfx.burst(m, tp, AMBER, 1.0, {"sparks": 18, "ring": false})
		Vfx.ring(m, tgt.global_position, DUST, 1.4, 0.35, 0.1, 0.1)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var in_rng := func(u) -> bool:
			return valid_unit_target(u) and G.flat_dist(p, u.global_position) <= range_m() + o.radius + u.radius - 0.1
		if ctx.mode == "retreat":
			var chaser = null
			var cd := INF
			for e in ctx.enemies:
				var d := G.flat_dist(p, e.global_position)
				if in_rng.call(e) and d < cd:
					cd = d
					chaser = e
			if chaser != null:
				return {"unit": chaser, "pos": chaser.global_position}
			return skip()
		var t: Unit = ctx.best_enemy_in_range(range_m() + o.radius)
		if t != null and in_rng.call(t):
			if ctx.mode == "fight" or not o.stats.uses_mana or o.mana > o.stats.max_mana * 0.35:
				return {"unit": t, "pos": t.global_position}
		if ctx.enemies.is_empty() and o.mana > o.stats.max_mana * 0.75:
			var est: float = damage()
			for mn in ctx.enemy_minions:
				if in_rng.call(mn) and mn.hp < est * Combat.resist_multiplier(mn.stats.mr, o, false) and G.flat_dist(p, mn.global_position) > 2.5:
					return {"unit": mn, "pos": mn.global_position}
		return skip()


# ===================================================================== W
class Thunderclap extends MAbility:
	var empowered := false
	var window_until := -1.0
	var fx: VfxNode = null

	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_range = 0.0
		cast_time = 0.0
		anim = "spell1"
		anim_lock = 0.3
		resets_attack = true

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return self_target()

	func armor_bonus_pct() -> float:
		if level <= 0:
			return 0.0
		var pct := dv("BonusArmorPassive", 0.1)
		if owner.passive != null and owner.passive.is_active():
			pct *= dv("BonusArmorPassiveMultiplier", 3.0)
		return pct

	func bonus_damage() -> float:
		return dv("ThunderclapBaseDamage") + dv("ThunderclapBaseDamageAPRatio", 0.2) * ap() + dv("ThunderclapBaseDamageArmorRatio", 0.15) * owner.stats.armor

	func splash_damage() -> float:
		return dv("ThunderclapSplashDamage") + dv("ThunderclapSplashAP", 0.3) * ap() + dv("ThunderclapSplashArmor", 0.15) * owner.stats.armor

	func in_window() -> bool:
		return now() < window_until

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		empowered = true
		window_until = now() + dv("ThunderclapBuffDuration", 5.0)
		if fx != null and is_instance_valid(fx):
			fx.queue_free()
		fx = VfxNode.new()
		fx.lifetime = dv("ThunderclapBuffDuration", 5.0)
		o.add_child(fx)
		for side in [-1.0, 1.0]:
			var fist := Vfx.sprite(AMBER, 0.9, 2.2)
			fist.position = Vector3(side * 0.9, 1.5, 0.0)
			fx.add_child(fist)
			var e := Vfx.emitter(GLOW, 14, 0.4, 0.14, {"vmin": 0.3, "vmax": 0.9, "radius": 0.2, "tex": Vfx.spark_texture()})
			e.position = fist.position
			fx.add_child(e)
		var l := Vfx.light(AMBER, 1.6, 3.0)
		l.position.y = 1.5
		fx.add_child(l)
		Vfx.ring(m, o.global_position, GLOW, 2.0, 0.3, 0.1, 0.1)
		Vfx.burst(m, o.global_position + Vector3(0, 1.5, 0), GLOW, 0.8, {"sparks": 12, "ring": false, "light": false})
		notify_cast(t)

	func end_fx() -> void:
		if fx != null and is_instance_valid(fx):
			fx.detach_and_fade()
		fx = null

	func on_tick(_dt: float) -> void:
		if fx != null and not in_window():
			end_fx()
			empowered = false

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if in_window():
			return skip()
		var f = ctx.focus
		if ctx.mode == "fight" and f != null and is_instance_valid(f) and o.in_attack_range(f, 0.4):
			if o.windup_timer < 0.0 and o.attack_timer > 0.12:
				return self_target()
		var at = o.attack_target
		if ctx.enemies.is_empty() and at != null and is_instance_valid(at) and at.kind == G.Kind.MINION and o.in_attack_range(at, 0.2) \
				and o.mana > o.stats.max_mana * 0.6 and ctx.count_enemies_near(at.global_position, 3.5, false) >= 3:
			return self_target()
		return skip()


class ThunderclapHook extends Effect:
	var w

	func _init(p_w) -> void:
		w = p_w
		id = "malph_w_hook"
		hidden = true

	func get_stat_mods() -> Dictionary:
		var pct: float = w.armor_bonus_pct()
		return {"armor%": pct} if pct > 0.0 else {}

	func on_pre_damage_dealt(info) -> void:
		if info.is_attack and w.empowered and info.target != null and info.tag == "":
			info.flat_bonus += w.bonus_damage()
			info.tag = "malph_w"
			w.empowered = false

	func on_attack_hit(target, info) -> void:
		if info == null or target == null or not is_instance_valid(target):
			return
		var big: bool = info.tag == "malph_w"
		if not big and not w.in_window():
			return
		var o = owner
		var m = o.match_ref
		var origin: Vector3 = o.global_position
		var dir := G.flat_dir(origin, target.global_position)
		var reach: float = w.dv("ThunderClapSplashRange", 400.0)
		var len: float = G.flat_dist(origin, target.global_position) / G.U + reach
		var dmg: float = w.splash_damage()
		for u in K.enemies_cone(w, origin, dir, len, 70.0):
			if u == target:
				continue
			Combat.deal(o, u, dmg, G.DmgType.PHYSICAL, {"is_aoe": true, "is_proc": true, "tag": "malph_w_splash", "ability": w})
			Vfx.hit_spark(m, u.global_position + Vector3(0, 1.0, 0), AMBER, 0.5)
		var ang := atan2(dir.z, dir.x)
		Fx.wedge(m, origin, len * G.U, 0.15, Color(0.95, 0.55, 0.2), GLOW, ang, deg_to_rad(70.0), 0.35)
		var tp: Vector3 = target.global_position + Vector3(0, 1.0, 0)
		if big:
			Vfx.burst(m, tp, GLOW, 1.4, {"sparks": 26})
			Vfx.ring(m, target.global_position, Color(1, 0.95, 0.8), 2.2, 0.3, 0.12, 0.0)
			Fx.debris(m, tp, 5, 4.0, 0.25, 0.55)
			if m.camera_rig != null and (o == G.player or target == G.player):
				m.camera_rig.shake(0.12)
		else:
			Vfx.hit_spark(m, tp, AMBER, 0.8)


# ===================================================================== E
class GroundSlam extends MAbility:
	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.CIRCLE
		ind_radius = 400.0
		cast_range = 0.0
		cast_time = 0.24
		anim = "spell3"
		anim_lock = 0.45

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return self_target()

	func damage() -> float:
		return dv("BaseDamage") + 0.4 * owner.stats.armor + 0.6 * ap()

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var p: Vector3 = o.global_position
		var pct := dv("ASReduction", 30.0) / 100.0
		var dur := dv("Duration", 3.0)
		var dmg := damage()
		for u in K.enemies_circle(self, p, ind_radius):
			hit(u, dmg, G.DmgType.MAGIC, {"is_aoe": true, "tag": "malph_e"})
			if not u.dead:
				var ratio: float = maxf(0.1, float(u.stats.base.get("attack_speed_ratio", 0.625)))
				var delta: float = u.stats.attack_speed * pct / ratio
				K.buff(u, "malph_e_as", dur, {"as": -delta}, o, {"name": "Ground Slam", "debuff": true})
				Vfx.hit_spark(m, u.global_position + Vector3(0, 1.0, 0), AMBER, 0.7)
		var r := ind_radius * G.U
		Vfx.ring(m, p, GLOW, r, 0.35, 0.12, 0.2)
		Vfx.ring(m, p, DUST, r * 1.15, 0.55, 0.08, 0.0)
		Fx.cracks(m, p, r, MAGMA, 1.0, 10.0)
		Fx.spikes(m, p, r * 0.8, 10, 1.4, 0.7)
		Fx.dust(m, p, 40, r * 0.6, 0.9)
		Vfx.burst(m, p + Vector3(0, 0.4, 0), AMBER, 1.2, {"sparks": 24, "ring": false})
		if m.camera_rig != null and o == G.player:
			m.camera_rig.shake(0.15)
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var r := ind_radius * G.U
		var champs := 0
		for e in ctx.enemies:
			if G.flat_dist(p, ctx.predict(e, cast_time)) <= r + e.radius * 0.5:
				champs += 1
		if champs >= 1:
			return self_target()
		if ctx.enemies.is_empty() and o.mana > o.stats.max_mana * 0.55 and ctx.count_enemies_near(p, r, false) >= 4:
			return self_target()
		return skip()


# ===================================================================== R
class UnstoppableForce extends MAbility:
	func _init() -> void:
		target_type = Target.POINT
		indicator = Ind.CIRCLE
		ind_radius = 270.0
		cast_range = 1000.0
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0

	func is_dash() -> bool:
		return true

	func damage() -> float:
		return dv("BaseDamage") + 0.9 * ap()

	func radius_m() -> float:
		return ind_radius * G.U

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var from: Vector3 = o.global_position
		var dest: Vector3 = t.pos
		if G.flat_dist(from, dest) > range_m():
			dest = from + G.flat_dir(from, dest) * range_m()
		var speed_u: float = 1835.0 + o.stats.move_speed
		var dur: float = maxf(0.12, G.flat_dist(from, dest) / (speed_u * G.U))
		K.buff(o, "malph_r_unstoppable", dur + 0.15, {}, o, {"name": "Unstoppable Force", "cc": Buff.CC.UNSTOPPABLE, "hidden": true})
		var self_ref := self
		o.start_dash(dest, {"speed": speed_u * G.U, "height": 0.7, "on_arrive": func(_u): self_ref._impact()})
		o.play_anim("spell4", 1.0, 0.03, dur + 0.3)
		o.anim_lock = dur + 0.3
		# meteor shell + molten trail
		var n := VfxNode.new()
		n.lifetime = dur + 0.05
		o.add_child(n)
		n.position.y = 1.2
		var shell := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.3
		sm.height = 2.6
		shell.mesh = sm
		var sh_mat := Vfx.add_material(MAGMA, 1.6, false)
		sh_mat.set_shader_parameter("use_mask", false)
		shell.material_override = sh_mat
		n.add_child(shell)
		n.add_child(Vfx.sprite(AMBER, 3.2, 1.2))
		var fire := Vfx.emitter(MAGMA, 90, 0.5, 0.7, {"vmin": 0.0, "vmax": 0.8, "radius": 0.8})
		n.add_child(fire)
		n.trails.append(fire)
		var dust := Vfx.emitter(DUST, 60, 0.8, 0.9, {"vmin": 0.2, "vmax": 1.2, "radius": 0.9, "energy": 0.8, "end_scale": 1.5})
		dust.position.y = -0.9
		n.add_child(dust)
		n.trails.append(dust)
		n.add_child(Vfx.light(MAGMA, 4.0, 6.0))
		var ang := atan2(dest.z - from.z, dest.x - from.x)
		var tele := Vfx.ground_circle(m, dest, radius_m(), Color(1.0, 0.5, 0.15, 0.8), dur + 0.1, 0.3)
		tele.get_child(0).material_override.set_shader_parameter("energy", 2.0)
		Vfx.beam(m, from + Vector3(0, 0.15, 0), dest + Vector3(0, 0.15, 0), Color(1.0, 0.45, 0.12), 0.9, dur + 0.35)
		notify_cast(t)

	func _impact() -> void:
		var o = owner
		var m = o.match_ref
		var p: Vector3 = o.global_position
		var dmg := damage()
		var hits := K.enemies_circle(self, p, ind_radius)
		for u in hits:
			hit(u, dmg, G.DmgType.MAGIC, {"is_aoe": true, "tag": "malph_r"})
			if not u.dead:
				K.knockup(u, dv("KnockupDuration", 1.5), o)
			Vfx.hit_spark(m, u.global_position + Vector3(0, 1.0, 0), GLOW, 1.0)
		var r := radius_m()
		Vfx.burst(m, p + Vector3(0, 0.8, 0), MAGMA, 2.6, {"sparks": 70})
		Vfx.ring(m, p, Color(1.0, 0.95, 0.85), r * 1.25, 0.3, 0.14, 0.25)
		Vfx.ring(m, p, AMBER, r * 2.0, 0.55, 0.08, 0.0)
		Vfx.ring(m, p, DUST, r * 2.8, 0.85, 0.05, 0.0)
		Fx.cracks(m, p, r * 1.8, MAGMA, 1.8, 13.0)
		Fx.spikes(m, p, r * 1.05, 14, 2.4, 1.1)
		Fx.spikes(m, p, r * 0.55, 7, 1.6, 0.9)
		Fx.debris(m, p + Vector3(0, 0.6, 0), 12, 8.0, 0.4, 1.0)
		Fx.dust(m, p, 70, r, 1.3)
		var flash := VfxNode.new()
		flash.lifetime = 0.5
		m.add_fx(flash, p + Vector3(0, 1.5, 0))
		var l := Vfx.light(AMBER, 9.0, r * 4.0)
		flash.add_child(l)
		var tw := flash.create_tween()
		tw.tween_property(l, "light_energy", 0.0, 0.45)
		if m.camera_rig != null:
			var involved: bool = o == G.player or hits.has(G.player)
			m.camera_rig.shake(0.6 if involved else 0.25)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		if ctx.enemies.is_empty():
			return skip()
		var r := radius_m()
		var preds := []
		for e in ctx.enemies:
			if G.flat_dist(p, e.global_position) <= range_m() + r + 2.0 and not e.has_cc_immunity():
				preds.append([e, ctx.predict(e, 0.35)])
		if preds.is_empty():
			return skip()
		var centers := []
		for i in preds.size():
			centers.append(preds[i][1])
			for j in range(i + 1, preds.size()):
				var a: Vector3 = preds[i][1]
				var b: Vector3 = preds[j][1]
				if a.distance_to(b) <= r * 2.0 + 1.0:
					centers.append((a + b) * 0.5)
		var best := Vector3.INF
		var best_s := -INF
		var dmg := damage()
		for cpos in centers:
			if G.flat_dist(p, cpos) > range_m():
				continue
			var n := 0
			var kill := false
			var hp_sum := 0.0
			for pr in preds:
				var e = pr[0]
				if G.flat_dist(cpos, pr[1]) <= r + e.radius * 0.8:
					n += 1
					hp_sum += e.hp_ratio()
					if dmg * Combat.resist_multiplier(e.stats.mr, o, false) >= e.hp + e.total_shield():
						kill = true
			if n == 0:
				continue
			if ctx._under_enemy_turret(cpos) and n < 3 and not kill:
				continue
			var ok: bool = n >= 2 or (kill and ctx.mode != "retreat")
			if not ok:
				continue
			var s := n * 10.0 + (5.0 if kill else 0.0) - hp_sum
			if s > best_s:
				best_s = s
				best = cpos
		if best == Vector3.INF:
			return skip()
		return make_target(best, null)
