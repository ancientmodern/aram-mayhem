extends ChampionKit
## Yasuo, the Unforgiven.

const WIND := Color(0.5, 0.82, 1.0)
const WIND_W := Color(0.82, 0.94, 1.0)
const DEEP := Color(0.25, 0.45, 1.0)
const STEEL := Color(0.92, 0.96, 1.0)
const EQ_RADIUS := 220.0      ## units


func build_kit() -> void:
	c.attack_missile_speed = 0.0
	c.attack_color = WIND
	c.role = "fighter"
	# Flow is shown on the resource bar: a 100-point pool filled by moving (see the passive)
	c.resource_name = "Flow"
	c.stats.uses_mana = true
	c.stats.set_base({"mana_base": 100.0, "mana_per_level": 0.0, "mana_regen": 0.0, "mana_regen_per_level": 0.0})
	c.level_order = "QEWQQRQEQEREEWWRWW"
	var p := WayOfTheWanderer.new()
	p.dvals = spell("YasuoPassive").get("data_values", {})
	c.passive = p
	c.add_effect(p)
	c.abilities[0] = init_ability(SteelTempest.new(), "Q")
	c.abilities[1] = init_ability(WindWall.new(), "W")
	c.abilities[2] = init_ability(SweepingBlade.new(), "E")
	c.abilities[3] = init_ability(LastBreath.new(), "R")
	c.abilities[3].anim = ""
	c.abilities[3].cast_time = 0.0
	c.add_effect(RPenHook.new(c.abilities[3]))
	c.add_effect(BotLeveler.new())



func ai_tuning() -> Dictionary:
	return {"aggression": 0.75}


func anim_overrides() -> Dictionary:
	return {"run_fast": ["run_fast"]}


# ===================================================================== shared visuals
class Fx:
	static var _shaders := {}

	const ARC_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled%DEPTH%;
uniform vec4 color : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
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

	## Spiralling wind bands on a cylinder / cone (tornado, whirl columns).
	const SWIRL_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 color : source_color = vec4(0.6, 0.85, 1.0, 1.0);
uniform float energy = 2.0;
uniform float fade = 1.0;
uniform float speed = 2.5;
uniform float twist = 2.0;
uniform float bands = 3.0;
void fragment() {
	float s = sin((UV.x * bands + UV.y * twist - TIME * speed) * 6.283185);
	float b = smoothstep(0.35, 1.0, s);
	float s2 = sin((UV.x * (bands * 2.0 + 1.0) - UV.y * twist * 1.5 - TIME * speed * 1.7) * 6.283185);
	b += smoothstep(0.6, 1.0, s2) * 0.5;
	float vert = smoothstep(0.0, 0.18, UV.y) * smoothstep(1.0, 0.75, UV.y);
	float ndv = abs(dot(NORMAL, VIEW));
	float rim = pow(1.0 - ndv, 1.2);
	float a = (b * 0.75 + rim * 0.35) * vert * fade;
	ALBEDO = mix(color.rgb, vec3(1.0), b * 0.35) * energy;
	ALPHA = clamp(a * color.a, 0.0, 1.0);
}
"""

	## Vertical sheet of flowing wind (Wind Wall).
	const WALL_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
uniform vec4 color : source_color = vec4(0.6, 0.85, 1.0, 1.0);
uniform float energy = 2.0;
uniform float fade = 1.0;
void fragment() {
	vec2 uv = UV;
	float side = smoothstep(0.0, 0.14, uv.x) * smoothstep(1.0, 0.86, uv.x);
	float h = 1.0 - uv.y;
	float vert = smoothstep(0.0, 0.06, h) * (1.0 - smoothstep(0.55, 1.0, h));
	float s1 = 0.5 + 0.5 * sin((uv.x * 3.0 - TIME * 1.6) * 6.283185 + sin(h * 7.0 + TIME * 2.2) * 1.4);
	float s2 = 0.5 + 0.5 * sin((uv.x * 7.0 + TIME * 2.4) * 6.283185 + h * 5.0);
	float s3 = 0.5 + 0.5 * sin((h * 10.0 - uv.x * 2.0 + TIME * 3.0) * 6.283185);
	float base = smoothstep(0.25, 0.0, h) * 0.6;
	float a = side * vert * (0.14 + 0.5 * pow(s1, 3.0) + 0.3 * pow(s2, 5.0) + 0.12 * s3) + side * base;
	ALBEDO = mix(color.rgb, vec3(1.0), pow(s1, 6.0) * 0.6) * energy;
	ALPHA = clamp(a * fade, 0.0, 1.0);
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

	static func swirl_mat(col: Color, energy: float, speed: float, twist: float, bands: float) -> ShaderMaterial:
		var mat := ShaderMaterial.new()
		mat.shader = shader("swirl", SWIRL_CODE)
		mat.set_shader_parameter("color", col)
		mat.set_shader_parameter("energy", energy)
		mat.set_shader_parameter("speed", speed)
		mat.set_shader_parameter("twist", twist)
		mat.set_shader_parameter("bands", bands)
		return mat

	static func plane(size: float, mat: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(size, size)
		mi.mesh = pm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi

	static func cone(top: float, bottom: float, height: float, mat: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = top
		cm.bottom_radius = bottom
		cm.height = height
		cm.radial_segments = 24
		cm.rings = 4
		cm.cap_top = false
		cm.cap_bottom = false
		mi.mesh = cm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi

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

	## Thin glowing slash line that flashes and thins out.
	static func slash(m, a: Vector3, b: Vector3, col: Color, width: float, dur: float) -> void:
		Vfx.beam(m, a, b, col, width, dur)

	## Whirlwind column rising from the ground.
	static func whirl(m, pos: Vector3, radius: float, height: float, col: Color, dur: float) -> VfxNode:
		var n := VfxNode.new()
		n.lifetime = dur + 0.1
		m.add_fx(n, pos)
		var mat := swirl_mat(col, 2.2, 3.5, 2.5, 3.0)
		var c1 := cone(radius, radius * 0.45, height, mat)
		c1.position.y = height * 0.5
		n.add_child(c1)
		var mat2 := swirl_mat(WIND_W, 1.6, -4.5, -1.5, 2.0)
		var c2 := cone(radius * 0.7, radius * 0.3, height * 0.85, mat2)
		c2.position.y = height * 0.45
		n.add_child(c2)
		n.scale = Vector3(1, 0.2, 1)
		var tw := n.create_tween()
		tw.tween_property(n, "scale", Vector3.ONE, dur * 0.3).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(dur * 0.35)
		tw.tween_method(func(v):
			mat.set_shader_parameter("fade", v)
			mat2.set_shader_parameter("fade", v), 1.0, 0.0, dur * 0.35)
		var spin := n.create_tween().set_loops()
		spin.tween_property(n, "rotation:y", TAU, 0.5).from(0.0)
		return n

	static func gust(m, pos: Vector3, col: Color, amount: int, speed: float, size: float, life: float = 0.5) -> void:
		var n := VfxNode.new()
		n.lifetime = life + 0.2
		m.add_fx(n, pos)
		var e := Vfx.emitter(col, amount, life, size, {"one_shot": true, "explosive": 0.9, "vmin": speed * 0.4, "vmax": speed,
				"spread": 180.0, "radius": 0.2, "damping": speed * 1.5})
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


class YAbility extends Ability:
	func try_cast(t: Dictionary) -> bool:
		if t.get("skip", false):
			return false
		return super.try_cast(t)

	func skip() -> Dictionary:
		return {"skip": true}

	func now() -> float:
		return owner.match_ref.time if owner.match_ref != null else 0.0

	static func airborne(u) -> bool:
		return u != null and is_instance_valid(u) and not u.dead and (u.cc & Buff.CC.AIRBORNE) != 0


## Last Breath's suspension: holds the victim at the apex of its knock-up, then lets it fall.
class SuspendBuff extends Buff:
	var hold := 0.7

	func tick(unit, dt: float) -> bool:
		if hold > 0.0:
			hold -= dt
			remaining = duration * 0.5
			return not removed
		return super.tick(unit, dt)


# ===================================================================== passive
class WayOfTheWanderer extends Effect:
	var dvals := {}
	var last_pos := Vector3.INF
	var flow_fx: VfxNode = null
	var flow_emit: GPUParticles3D = null

	func _init() -> void:
		id = "yasuo_passive"
		display_name = "Way of the Wanderer"

	func val(n: String, d: float) -> float:
		return float(dvals.get(n, d))

	func units_per_flow() -> float:
		var lv: int = owner.level
		return 59.0 if lv < 7 else (52.0 if lv < 13 else 46.0)

	func shield_value() -> float:
		var lv: float = owner.level
		return lerpf(125.0, 600.0, (lv - 1.0) / 17.0)

	func full() -> bool:
		return owner.mana >= owner.stats.max_mana - 0.01

	func on_tick(u, _dt: float) -> void:
		var p: Vector3 = u.global_position
		if last_pos != Vector3.INF and not u.dead:
			var d := G.flat_dist(p, last_pos)
			if d > 0.0001 and d < 6.0:
				u.mana = minf(u.stats.max_mana, u.mana + d / G.U / units_per_flow())
		last_pos = p
		_update_flow_fx(u)

	func _update_flow_fx(u) -> void:
		if flow_fx == null or not is_instance_valid(flow_fx):
			flow_fx = VfxNode.new()
			u.add_child(flow_fx)
			flow_fx.position.y = 0.25
			flow_emit = Vfx.emitter(WIND_W, 18, 0.7, 0.2, {"vmin": 0.6, "vmax": 1.4, "radius": 0.5, "dir": Vector3.UP, "spread": 60.0, "local": true})
			flow_fx.add_child(flow_emit)
		var want: bool = full() and not u.dead
		if flow_emit.emitting != want:
			flow_emit.emitting = want

	func on_respawn() -> void:
		last_pos = Vector3.INF

	func on_damage_taken(info) -> void:
		var o = owner
		if o.dead or not full():
			return
		var src = info.source
		if src == null or not is_instance_valid(src):
			return
		if src.kind != G.Kind.CHAMPION and src.kind != G.Kind.SUMMON:
			return
		if info.final + info.absorbed <= 0.0:
			return
		o.mana = 0.0
		K.shield(o, o, shield_value(), 1.0, WIND_W)
		Fx.gust(o.match_ref, o.global_position + Vector3(0, 1.0, 0), WIND_W, 24, 4.0, 0.3)

	## Intent: crit chance doubled, crit damage reduced, overflow crit -> AD.
	func get_stat_mods() -> Dictionary:
		var o = owner
		if o == null:
			return {}
		var other := 0.0
		for e in o.effects:
			if e != self and not e.removed:
				other += float(e.get_stat_mods().get("crit", 0.0))
		var mult := val("CritChanceMultiplier", 1.0)
		var d := {"crit": other * mult, "crit_dmg": -Rules.CRIT_DAMAGE * (1.0 - val("CritDamageMod", 0.9))}
		var total := other * (1.0 + mult)
		if total > 1.0:
			# the Mayhem core already converts 0.45 AD per 1% overflow; Yasuo gets 0.5
			d["ad"] = (total - 1.0) * 100.0 * maxf(0.0, val("YasuoCritToAD", 50.0) / 100.0 - 0.45)
		return d


# ===================================================================== Q
class SteelTempest extends YAbility:
	var stacks := 0
	var stack_until := -1.0
	var eq_pending := false
	var alt := false
	var ready_fx: VfxNode = null

	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 100.0
		cast_range = 450.0
		cast_time = 0.35
		anim = "spell1a"
		anim_lock = 0.35

	func is_q3() -> bool:
		return stacks >= 2

	func set_stacks(n: int) -> void:
		stacks = n
		stack_until = now() + dv("GatheringStormDuration", 6.0)
		var o = owner
		if is_q3():
			if ready_fx == null or not is_instance_valid(ready_fx):
				ready_fx = VfxNode.new()
				o.add_child(ready_fx)
				var mat := Fx.swirl_mat(Color(0.55, 0.85, 1.0, 0.55), 1.3, 3.0, 1.5, 2.0)
				var col := Fx.cone(0.95, 0.75, 2.1, mat)
				col.position.y = 1.05
				ready_fx.add_child(col)
				var e := Vfx.emitter(WIND_W, 22, 0.6, 0.18, {"vmin": 0.5, "vmax": 1.5, "radius": 0.7, "dir": Vector3.UP, "spread": 30.0, "local": true})
				e.position.y = 0.4
				ready_fx.add_child(e)
				var spin := ready_fx.create_tween().set_loops()
				spin.tween_property(ready_fx, "rotation:y", TAU, 0.8).from(0.0)
		elif ready_fx != null and is_instance_valid(ready_fx):
			ready_fx.detach_and_fade()
			ready_fx = null

	func add_stack() -> void:
		set_stacks(mini(2, stacks + 1))

	func on_tick(_dt: float) -> void:
		if stacks > 0 and now() >= stack_until:
			set_stacks(0)
		var bas: float = owner.stats.bonus_as
		cast_time = maxf(0.175, 0.35 / (1.0 + maxf(0.0, bas)))
		if is_q3():
			cast_range = dv("TornadoRange", 1100.0)
			ind_width = 180.0
			anim = "spell1c"
		else:
			cast_range = dv("StabRange", 450.0)
			ind_width = 100.0
			anim = "spell1b" if alt else "spell1a"
		if eq_pending:
			var e_ab = owner.abilities[2]
			if e_ab == null or not e_ab.dashing:
				do_eq()

	## Cooldown scales with bonus attack speed only (min 1.33 s).
	func start_cooldown(_override: float = -1.0) -> void:
		var bas: float = owner.stats.bonus_as
		var c := maxf(1.33, dv("Cooldown", 4.0) * (1.0 - minf(maxf(0.0, bas) / 1.67, 0.6675)))
		for e in owner.effects:
			c = e.modify_cooldown(self, c)
		cd = c
		cd_total = c

	func q_damage() -> Array:
		var dmg := dv("BaseDamage") + dv("ADRatio", 1.05) * ad()
		var crit: bool = G.rng.randf() < owner.stats.crit_chance
		if crit:
			dmg *= owner.stats.crit_damage
		return [dmg, crit]

	func try_cast(t: Dictionary) -> bool:
		if t.get("skip", false):
			return false
		var e_ab = owner.abilities[2]
		if e_ab != null and e_ab.dashing and not eq_pending and cast_block_reason() == "":
			_begin_eq()
			return true
		return super.try_cast(t)

	func _begin_eq() -> void:
		var o = owner
		cast_count += 1
		start_cooldown()
		eq_pending = true
		o.play_anim("spell1_dash", 1.0, 0.03, 0.5)
		o.anim_lock = 0.5

	## Steel Tempest cast during Sweeping Blade: a circular slash at the end of the dash.
	func do_eq() -> void:
		eq_pending = false
		var o = owner
		if o.dead:
			return
		var m = o.match_ref
		var p: Vector3 = o.global_position
		var q3 := is_q3()
		var dc := q_damage()
		var champs := 0
		var hits := K.enemies_circle(self, p, EQ_RADIUS)
		for u in hits:
			hit(u, dc[0], G.DmgType.PHYSICAL, {"is_aoe": true, "tag": "yasuo_q", "is_crit": dc[1]})
			if q3:
				K.knockup(u, dv("KnockUpDurationTOOLTIPONLY", 1.0), o)
			if u.kind == G.Kind.CHAMPION:
				champs += 1
			Vfx.hit_spark(m, u.global_position + Vector3(0, 1.0, 0), WIND_W, 0.7)
		if q3:
			set_stacks(0)
		elif not hits.is_empty():
			add_stack()
		var start := atan2(o.facing.z, o.facing.x)
		Fx.sweep(m, p, EQ_RADIUS * G.U + 0.3, 0.45, WIND, STEEL, start, 1.0, 0.18, 0.9)
		Vfx.ring(m, p, WIND_W, EQ_RADIUS * G.U + 0.4, 0.3, 0.08, 0.1)
		if q3:
			Fx.whirl(m, p, 2.4, 3.6, WIND, 0.7)
			Vfx.ring(m, p, DEEP, 3.0, 0.45, 0.1, 0.15)
			if m.camera_rig != null and o == G.player:
				m.camera_rig.shake(0.15)
		notify_cast({"pos": p, "dir": o.facing, "unit": null})
		if q3 and champs > 0:
			o.abilities[3].bot_follow_up()

	func execute(t: Dictionary) -> void:
		var dir: Vector3 = t.dir
		if is_q3():
			_tornado(dir)
		else:
			_stab(dir)
			alt = not alt
		notify_cast(t)

	func _stab(dir: Vector3) -> void:
		var o = owner
		var m = o.match_ref
		var p: Vector3 = o.global_position
		var reach := dv("StabRange", 450.0) * G.U
		var a: Vector3 = p + dir * 0.3
		var b: Vector3 = p + dir * reach
		var dc := q_damage()
		var hits := K.enemies_line(self, a, b, dv("StabWidth", 80.0) * 1.25)
		for u in hits:
			hit(u, dc[0], G.DmgType.PHYSICAL, {"tag": "yasuo_q", "is_crit": dc[1]})
			Vfx.hit_spark(m, u.global_position + Vector3(0, 1.0, 0), STEEL if not dc[1] else Color(1.0, 0.85, 0.4), 0.8 if dc[1] else 0.55)
		if not hits.is_empty():
			add_stack()
		var h := Vector3(0, 1.1, 0)
		Fx.slash(m, a + h, b + h, WIND, 0.32, 0.16)
		Fx.slash(m, a + h, b + h, Color(1, 1, 1), 0.1, 0.12)
		var tip := VfxNode.new()
		tip.lifetime = 0.25
		m.add_fx(tip, b + h)
		var s := Vfx.sprite(WIND_W, 1.0, 3.0, Vfx.spark_texture())
		tip.add_child(s)
		var tw := tip.create_tween()
		tw.tween_property(s, "scale", Vector3.ONE * 0.1, 0.2)
		Fx.gust(m, b + h, WIND, 10, 2.5, 0.18, 0.35)

	func _tornado(dir: Vector3) -> void:
		var o = owner
		var m = o.match_ref
		set_stacks(0)
		var dc := q_damage()
		var self_ref := self
		var vis := VfxNode.new()
		var spin := Node3D.new()
		vis.add_child(spin)
		var mat := Fx.swirl_mat(WIND, 2.3, 3.2, 2.2, 3.0)
		var funnel := Fx.cone(1.15, 0.35, 2.8, mat)
		funnel.position.y = 1.4
		spin.add_child(funnel)
		var mat2 := Fx.swirl_mat(WIND_W, 1.8, -4.0, -1.4, 2.0)
		var core := Fx.cone(0.7, 0.2, 2.4, mat2)
		core.position.y = 1.2
		spin.add_child(core)
		var dust := Vfx.emitter(WIND, 50, 0.5, 0.35, {"vmin": 0.3, "vmax": 1.2, "radius": 0.6, "dir": Vector3.UP, "spread": 60.0})
		dust.position.y = 0.3
		vis.add_child(dust)
		vis.trails.append(dust)
		var l := Vfx.light(WIND, 2.5, 6.0)
		l.position.y = 1.4
		vis.add_child(l)
		var tw := vis.create_tween().set_loops()
		tw.tween_property(spin, "rotation:y", TAU, 0.35).from(0.0)
		var champs := {"n": 0}
		K.line_missile(self, o.global_position + dir * 0.4, dir, 1200.0, dv("TornadoRange", 1100.0), {
			"width": 90.0, "pierce": true, "height": 0.0, "visual": vis,
			"on_hit": func(_m, u):
				self_ref.hit(u, dc[0], G.DmgType.PHYSICAL, {"tag": "yasuo_q", "is_crit": dc[1]})
				K.knockup(u, self_ref.dv("KnockUpDurationTOOLTIPONLY", 1.0), o)
				Vfx.burst(m, u.global_position + Vector3(0, 1.0, 0), WIND_W, 0.9, {"sparks": 16, "ring": false, "light": false})
				if u.kind == G.Kind.CHAMPION:
					champs.n += 1
					if champs.n == 1:
						o.abilities[3].bot_follow_up(),
		})

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var e_ab = o.abilities[2]
		if e_ab != null and e_ab.dashing:
			var end: Vector3 = o.dash.get("to", p) if not o.dash.is_empty() else p
			var rr: float = EQ_RADIUS * G.U
			var nc := 0
			for e in ctx.enemies:
				if G.flat_dist(end, ctx.predict(e, 0.25)) <= rr + e.radius:
					nc += 1
			if nc > 0:
				return {"pos": end, "dir": o.facing, "unit": null}
			if not is_q3() and ctx.enemies.is_empty():
				for mn in ctx.enemy_minions:
					if G.flat_dist(end, mn.global_position) <= rr + mn.radius:
						return {"pos": end, "dir": o.facing, "unit": null}
			return skip()
		if is_q3():
			# hold the whirlwind for a Sweeping Blade combo if one is lined up
			var t: Unit = ctx.best_enemy_in_range(range_m() * 0.92)
			if t != null:
				var d := G.flat_dist(p, t.global_position)
				return ctx.aim_at(ctx.predict(t, cast_time + d / 12.0), self)
			if ctx.enemies.is_empty() and stack_until - now() < 1.2:
				for mn in ctx.enemy_minions:
					if G.flat_dist(p, mn.global_position) < 8.0:
						return make_target(mn.global_position, null)
			return skip()
		var t2: Unit = ctx.best_enemy_in_range(range_m() * 0.95)
		if t2 != null:
			return ctx.aim_at(ctx.predict(t2, cast_time), self)
		# stack Steel Tempest on minions (free, no cost)
		if ctx.mode != "retreat":
			var best = null
			var bd := INF
			for mn in ctx.enemy_minions:
				var d2 := G.flat_dist(p, mn.global_position)
				if d2 < range_m() * 0.9 and d2 < bd:
					bd = d2
					best = mn
			if best != null:
				return make_target(best.global_position, null)
		return skip()


# ===================================================================== W
class WindWall extends YAbility:
	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.LINE
		ind_width = 120.0
		ind_length = 400.0
		cast_range = 400.0
		cast_time = 0.0
		anim = "spell2"
		anim_lock = 0.35

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var dir: Vector3 = t.dir
		var perp := Vector3(-dir.z, 0.0, dir.x)
		var width := dv("Width", 320.0) * G.U
		var life := dv("WallLife", 4.0)
		var origin: Vector3 = o.global_position
		var d0 := 1.0
		var d1 := 4.0
		var c0: Vector3 = origin + dir * d0
		var bl: Dictionary = m.add_blocker(o.team, c0 - perp * width * 0.5, c0 + perp * width * 0.5, life)
		# visual: three gently curved panels of flowing wind
		var n := VfxNode.new()
		n.lifetime = life + 0.1
		m.add_fx(n, c0)
		n.basis = Basis(perp, Vector3.UP, -dir)
		var mat := ShaderMaterial.new()
		mat.shader = Fx.shader("wall", Fx.WALL_CODE)
		mat.set_shader_parameter("color", WIND)
		mat.set_shader_parameter("energy", 2.0)
		mat.set_shader_parameter("fade", 0.0)
		var seg := width / 3.0
		for i in 3:
			var q := MeshInstance3D.new()
			var qm := QuadMesh.new()
			qm.size = Vector2(seg + 0.15, 2.9)
			q.mesh = qm
			q.material_override = mat
			q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var side := float(i - 1)
			q.position = Vector3(side * seg, 1.45, absf(side) * seg * 0.22)
			q.rotation.y = -side * deg_to_rad(24.0)
			n.add_child(q)
		var e := Vfx.emitter(WIND_W, 60, 0.9, 0.22, {"vmin": 1.5, "vmax": 3.0, "dir": Vector3(1, 0.15, 0), "spread": 15.0, "local": true})
		var pm: ParticleProcessMaterial = e.process_material
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(width * 0.5, 1.2, 0.15)
		e.position.y = 1.3
		n.add_child(e)
		var glow := Vfx.light(WIND, 2.0, width)
		glow.position.y = 1.2
		n.add_child(glow)
		var tw := n.create_tween()
		tw.tween_method(func(v): mat.set_shader_parameter("fade", v), 0.0, 1.0, 0.15)
		tw.tween_interval(maxf(0.0, life - 0.55))
		tw.tween_method(func(v): mat.set_shader_parameter("fade", v), 1.0, 0.0, 0.4)
		Fx.gust(m, c0 + Vector3(0, 1.0, 0), WIND_W, 30, 5.0, 0.3)
		# drift forward quickly, then hold
		var st := {"t": 0.0}
		m.add_ticker(life, func(dt):
			st.t += dt
			var k: float = clampf(st.t / 0.45, 0.0, 1.0)
			k = 1.0 - (1.0 - k) * (1.0 - k)
			var cp: Vector3 = origin + dir * lerpf(d0, d1, k)
			bl.a = cp - perp * width * 0.5
			bl.b = cp + perp * width * 0.5
			if is_instance_valid(n):
				n.global_position = Vector3(cp.x, m.nav.height_at(cp) if m.nav != null else cp.y, cp.z)
			return true)
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var threat := 0.0
		var aim := Vector3.ZERO
		for mi in o.match_ref.missiles:
			if not is_instance_valid(mi) or not mi.alive or mi.team == o.team or not mi.blockable:
				continue
			var mp: Vector3 = mi.global_position
			var d := G.flat_dist(mp, p)
			if d > 9.0 or d < 1.3:
				continue
			var w := 0.0
			if mi.mode == Missile.Mode.HOMING or mi.mode == Missile.Mode.FOLLOW:
				var tg = mi.target
				if tg == o:
					w = 2.5
				elif tg != null and is_instance_valid(tg) and tg.kind == G.Kind.CHAMPION and tg.team == o.team and G.flat_dist(tg.global_position, p) < 3.0:
					w = 1.5
				if mi.is_attack and w > 0.0:
					var src = mi.source
					w = 0.0 if src == null or not is_instance_valid(src) or src.kind != G.Kind.CHAMPION else (0.7 if o.hp_ratio() < 0.45 else 0.3)
			elif mi.mode == Missile.Mode.LINEAR:
				var to_me := G.flat_dir(mp, p)
				var lateral: float = (G.flat(p - mp) - mi.dir * G.flat(p - mp).dot(mi.dir)).length()
				if mi.dir.dot(to_me) > 0.5 and lateral < 1.8:
					w = 3.0
			elif mi.mode == Missile.Mode.ARC:
				if G.flat_dist(mi.target_pos, p) < 3.0:
					w = 2.0
			if w > 0.0:
				threat += w
				aim += G.flat_dir(p, mp) * w
		if threat >= 2.0 and aim.length() > 0.01:
			var dir := aim.normalized()
			return make_target(p + dir * 4.0, null)
		return skip()


# ===================================================================== E
class SweepingBlade extends YAbility:
	var marked := {}
	var stacks := 0
	var stack_until := -1.0
	var dashing := false
	var prune_t := 0.0

	func _init() -> void:
		target_type = Target.UNIT
		target_side = Side.ENEMY
		indicator = Ind.NONE
		cast_range = 475.0
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0

	func is_dash() -> bool:
		return true

	func valid_unit_target(u) -> bool:
		if not super.valid_unit_target(u):
			return false
		return now() >= float(marked.get(u, -1.0))

	func damage() -> float:
		var base := dv("BaseDamage") + dv("ADRatio", 0.2) * bonus_ad() + dv("APRatio", 0.6) * ap()
		return base * (1.0 + 0.25 * stacks)

	func on_tick(dt: float) -> void:
		if stacks > 0 and now() >= stack_until:
			stacks = 0
		if dashing and owner.dash.is_empty():
			dashing = false
		prune_t -= dt
		if prune_t <= 0.0:
			prune_t = 2.0
			var tnow := now()
			for k in marked.keys():
				if not is_instance_valid(k) or float(marked[k]) <= tnow:
					marked.erase(k)

	func endpoint(u) -> Vector3:
		var p: Vector3 = owner.global_position
		return p + G.flat_dir(p, u.global_position) * cast_range * G.U

	func execute(t: Dictionary) -> void:
		var o = owner
		var u = t.unit
		if u == null or not is_instance_valid(u) or u.dead:
			return
		var m = o.match_ref
		var p: Vector3 = o.global_position
		var dest := endpoint(u)
		var speed_u: float = dv("BaseDashSpeed", 750.0) + 0.6 * o.stats.move_speed
		var dur: float = cast_range / speed_u
		hit(u, damage(), G.DmgType.MAGIC, {"tag": "yasuo_e"})
		Vfx.hit_spark(m, u.global_position + Vector3(0, 1.0, 0), WIND_W, 0.8)
		stacks = mini(int(dv("MaxStacks", 4.0)), stacks + 1)
		stack_until = now() + dv("StackDuration", 5.0)
		marked[u] = now() + dv("PerTargetCooldown", 10.0)
		dashing = true
		var self_ref := self
		o.start_dash(dest, {"speed": speed_u * G.U, "on_arrive": func(_x): self_ref._arrive()})
		o.play_anim("spell3", 1.0, 0.03, dur + 0.1)
		o.anim_lock = dur + 0.05
		var trail := VfxNode.new()
		trail.lifetime = dur + 0.05
		o.add_child(trail)
		trail.position.y = 1.0
		var e := Vfx.emitter(WIND, 50, 0.35, 0.35, {"vmin": 0.0, "vmax": 0.5, "radius": 0.35})
		trail.add_child(e)
		trail.trails.append(e)
		var e2 := Vfx.emitter(WIND_W, 30, 0.25, 0.15, {"vmin": 0.5, "vmax": 1.5, "radius": 0.5, "tex": Vfx.spark_texture()})
		trail.add_child(e2)
		trail.trails.append(e2)
		var h := Vector3(0, 1.0, 0)
		Fx.slash(m, p + h, dest + h, Color(0.6, 0.85, 1.0, 0.5), 0.18, dur + 0.1)
		notify_cast(t)

	func _arrive() -> void:
		dashing = false
		var q = owner.abilities[0]
		if q != null and q.eq_pending:
			q.do_eq()

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var q = o.abilities[0]
		var q_up: bool = q != null and q.level > 0 and q.cd <= 0.35
		var cands := []
		for u in o.match_ref.enemies_in_radius(o.team, p, range_m() + 0.6):
			if valid_unit_target(u):
				cands.append(u)
		if cands.is_empty():
			return skip()
		var f = ctx.focus
		if ctx.mode == "retreat":
			if ctx.enemies.is_empty():
				return skip()
			var best = null
			var best_s := -INF
			var home: Vector3 = o.spawn_point
			for u in cands:
				var ep := endpoint(u)
				if ctx._under_enemy_turret(ep):
					continue
				var nearest := INF
				for e in ctx.enemies:
					nearest = minf(nearest, G.flat_dist(ep, e.global_position))
				var s: float = nearest - G.flat_dist(ep, home) * 0.15
				if s > best_s:
					best_s = s
					best = u
			if best != null and best_s > 3.0:
				return {"unit": best, "pos": best.global_position}
			return skip()
		if ctx.mode == "fight" and f != null and is_instance_valid(f) and not f.dead:
			var df := G.flat_dist(p, f.global_position)
			var melee: float = o.attack_range_m() + o.radius + f.radius
			var best2 = null
			var best_d := INF
			for u in cands:
				var ep2 := endpoint(u)
				if ctx._under_enemy_turret(ep2) and f.hp_ratio() > 0.3:
					continue
				var nd := G.flat_dist(ep2, f.global_position)
				# E->Q combo: the dash must end inside the Steel Tempest circle around the focus
				if q_up and nd <= EQ_RADIUS * G.U + f.radius - 0.2:
					return {"unit": u, "pos": u.global_position}
				if nd < best_d:
					best_d = nd
					best2 = u
			if best2 != null and df > melee + 0.5 and best_d < df - 1.0:
				return {"unit": best2, "pos": best2.global_position}
			return skip()
		# lane: last-hit minions with the dash when it's safe
		if ctx.enemies.is_empty():
			for u in cands:
				if u.kind != G.Kind.MINION:
					continue
				var est: float = damage() * Combat.resist_multiplier(u.stats.mr, o, false)
				if u.hp < est and not ctx._under_enemy_turret(endpoint(u)):
					return {"unit": u, "pos": u.global_position}
		return skip()


# ===================================================================== R
class LastBreath extends YAbility:
	func _init() -> void:
		target_type = Target.UNIT
		target_side = Side.ENEMY
		target_champions_only = true
		indicator = Ind.RANGE
		cast_range = 1400.0
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0

	func is_dash() -> bool:
		return true

	func valid_unit_target(u) -> bool:
		return super.valid_unit_target(u) and airborne(u)

	## Picks the airborne enemy champion nearest the cursor.
	func make_target(world_pos: Vector3, hovered = null) -> Dictionary:
		var t := {"pos": world_pos, "dir": G.flat_dir(owner.global_position, world_pos), "unit": null}
		if valid_unit_target(hovered):
			t.unit = hovered
		else:
			var best = null
			var bd := INF
			for e in owner.match_ref.enemies_in_radius(owner.team, owner.global_position, range_m() + 1.0, true):
				if valid_unit_target(e):
					var d := G.flat_dist(world_pos, e.global_position)
					if d < bd:
						bd = d
						best = e
			t.unit = best
		if t.unit != null:
			t.pos = t.unit.global_position
		return t

	func damage() -> float:
		return dv("RBaseDamage") + 1.5 * bonus_ad()

	func execute(t: Dictionary) -> void:
		var o = owner
		var u = t.unit
		if u == null or not is_instance_valid(u) or u.dead:
			return
		var m = o.match_ref
		var from: Vector3 = o.global_position
		var center: Vector3 = u.global_position
		var targets := []
		for e in m.enemies_in_radius(o.team, center, dv("RRadius", 400.0) * G.U, true):
			if airborne(e):
				targets.append(e)
		if not (u in targets):
			targets.append(u)
		var dest: Vector3 = center + G.flat_dir(center, from) * (u.radius + o.radius * 0.6)
		if m.nav != null and not m.nav.is_walkable(dest):
			dest = m.nav.nearest_walkable(dest)
		o.teleport(dest)
		o.face_toward(center, 100.0)
		var hold := dv("RKnockupDuration", 1.0)
		for e in targets:
			_suspend(e, hold)
		o.mana = o.stats.max_mana
		o.abilities[0].set_stacks(0)
		K.buff(o, "yasuo_r", dv("RBuffDuration", 15.0), {}, o, {"name": "Last Breath", "icon": icon})
		o.start_dash(dest, {"duration": 0.75, "height": 1.7})
		o.play_anim("spell4", 1.0, 0.03, 0.95)
		o.anim_lock = 0.95
		# teleport streak + pressure dome
		var h := Vector3(0, 1.2, 0)
		Vfx.beam(m, from + h, dest + h, WIND, 0.4, 0.25)
		Fx.gust(m, from + h, WIND_W, 24, 4.0, 0.3)
		Vfx.ring(m, center, DEEP, dv("RRadius", 400.0) * G.U, 0.5, 0.06, 0.25)
		var dome := Vfx.ground_circle(m, center, dv("RRadius", 400.0) * G.U, Color(0.3, 0.55, 1.0, 0.6), hold + 0.1, 0.22)
		dome.get_child(0).material_override.set_shader_parameter("rotate_speed", 3.0)
		dome.get_child(0).material_override.set_shader_parameter("segments", 12.0)
		for e in targets:
			Fx.whirl(m, e.global_position, 1.2, 4.0, WIND, hold)
		# a flurry of slashes, then the finishing blow
		var self_ref := self
		var dmg := damage()
		for i in 7:
			m.after(0.06 + i * 0.06, func():
				for e in targets:
					if is_instance_valid(e) and not e.dead:
						var cp: Vector3 = e.global_position + Vector3(0, 2.1, 0)
						var a := G.rng.randf() * TAU
						var off := Vector3(cos(a), G.rng.randf_range(-0.6, 0.6), sin(a)) * 1.6
						Fx.slash(m, cp - off, cp + off, WIND_W if i % 2 == 0 else WIND, 0.12, 0.12))
		m.after(0.52, func():
			for e in targets:
				if is_instance_valid(e) and not e.dead:
					self_ref.hit(e, dmg, G.DmgType.PHYSICAL, {"tag": "yasuo_r"})
					var ep: Vector3 = e.global_position + Vector3(0, 2.0, 0)
					Vfx.burst(m, ep, WIND_W, 1.6, {"sparks": 30})
					Fx.slash(m, ep + Vector3(-1.8, 1.0, 0), ep + Vector3(1.8, -1.0, 0), Color(1, 1, 1), 0.22, 0.25)
					Fx.slash(m, ep + Vector3(-1.8, -1.0, 0), ep + Vector3(1.8, 1.0, 0), WIND, 0.22, 0.25)
			Vfx.ring(m, center, WIND_W, 4.5, 0.4, 0.08, 0.0)
			if m.camera_rig != null:
				m.camera_rig.shake(0.4 if (o == G.player or targets.has(G.player)) else 0.12))
		notify_cast(t)

	func _suspend(e, hold: float) -> void:
		e.remove_buffs_by_id("airborne")
		e.remove_buffs_by_id("knockback")
		e.remove_buffs_by_id("pull")
		if not e.dash.is_empty() and e.dash.get("forced", false):
			e.dash = {}
			e.airborne_height = 0.0
		var b := SuspendBuff.new("airborne", 0.6)
		b.cc = Buff.CC.AIRBORNE
		b.is_debuff = true
		b.display_name = "Airborne"
		b.hold = maxf(0.1, hold - 0.3)
		e.add_buff(b, owner)

	## Bots: fire Last Breath right after our own knock-up lands (Q3 -> R).
	func bot_follow_up() -> void:
		var o = owner
		if not o.is_bot or level <= 0 or o.controller == null or not (o.controller is BotBrain):
			return
		var self_ref := self
		o.match_ref.after(G.rng.randf_range(0.12, 0.3), func():
			if not is_instance_valid(o) or o.dead or self_ref.cast_block_reason() != "":
				return
			var t: Dictionary = self_ref.ai_consider(o.controller)
			if not t.get("skip", false) and not t.is_empty():
				self_ref.try_cast(t))

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var best = null
		var best_s := -INF
		var dmg := damage()
		var cands: Array = o.match_ref.enemies_in_radius(o.team, p, range_m() + 0.5, true)
		for e in cands:
			if not airborne(e) or not valid_unit_target(e):
				continue
			var n := 0
			for e2 in cands:
				if airborne(e2) and G.flat_dist(e.global_position, e2.global_position) <= dv("RRadius", 400.0) * G.U:
					n += 1
			var est: float = dmg * Combat.resist_multiplier(e.stats.armor, o, true)
			var killable: bool = est >= e.hp + e.total_shield()
			var allies_near: int = 0
			for a in ctx.allies:
				if G.flat_dist(a.global_position, e.global_position) < 8.0:
					allies_near += 1
			if ctx._under_enemy_turret(e.global_position) and not killable and o.hp_ratio() < 0.6:
				continue
			if o.hp_ratio() < 0.25 and not killable and n < 2:
				continue
			var s: float = n * 2.0 + (1.0 - e.hp_ratio()) * 2.0 + (4.0 if killable else 0.0) + allies_near * 0.5
			if s > best_s:
				best_s = s
				best = e
		if best != null and best_s >= 1.5:
			return {"unit": best, "pos": best.global_position, "dir": G.flat_dir(p, best.global_position)}
		return skip()


## Last Breath's buff: critical strikes ignore 60% of the target's bonus armor.
class RPenHook extends Effect:
	var r

	func _init(p_r) -> void:
		r = p_r
		id = "yasuo_r_pen"
		hidden = true

	func on_pre_damage_dealt(info) -> void:
		if not info.is_crit or info.type != G.DmgType.PHYSICAL or not owner.has_buff("yasuo_r"):
			return
		if not (info.is_attack or info.tag == "yasuo_q"):
			return
		var tg = info.target
		if tg == null or not is_instance_valid(tg):
			return
		var armor: float = tg.stats.armor
		var bonus: float = maxf(0.0, tg.stats.bonus_armor)
		var full := Combat.resist_multiplier(armor, owner, true)
		var reduced := Combat.resist_multiplier(armor - bonus * r.dv("RPercentArmorPen", 60.0) / 100.0, owner, true)
		if full > 0.0:
			info.mult *= reduced / full
