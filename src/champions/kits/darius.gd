extends ChampionKit
## Darius, the Hand of Noxus.

const RED := Color(1.0, 0.12, 0.06)
const BLOOD := Color(0.75, 0.02, 0.04)
const EMBER := Color(1.0, 0.42, 0.14)
const STEEL := Color(0.9, 0.88, 0.95)
const Q_INNER := 205.0     ## handle radius (units)
const Q_OUTER := 425.0     ## blade radius (units)
const Q_WINDUP := 0.75


func build_kit() -> void:
	c.attack_missile_speed = 0.0
	c.attack_color = RED
	c.role = "fighter"
	c.level_order = "QWEQQRQEQEREEWWRWW"
	var hemo := Hemorrhage.new()
	hemo.dvals = spell("DariusHemoMarker").get("data_values", {})
	c.passive = hemo
	c.add_effect(hemo)
	c.abilities[0] = init_ability(Decimate.new(), "Q")
	c.abilities[1] = init_ability(CripplingStrike.new(), "W")
	c.abilities[2] = init_ability(Apprehend.new(), "E")
	c.abilities[3] = init_ability(NoxianGuillotine.new(), "R")
	# the json cast times describe the internal sub-casts; these abilities drive their own timing
	for i in [0, 1, 3]:
		c.abilities[i].cast_time = 0.0
		c.abilities[i].anim = ""
	c.add_effect(WAttackHook.new(c.abilities[1]))
	c.add_effect(ApprehendPen.new(c.abilities[2]))
	c.add_effect(BotLeveler.new())



func ai_tuning() -> Dictionary:
	return {"aggression": 0.8}


# ===================================================================== shared visuals
class Fx:
	static var _shaders := {}

	const ARC_CODE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled%DEPTH%;
uniform vec4 color : source_color = vec4(1.0, 0.1, 0.05, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.85, 0.75, 1.0);
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
uniform vec4 color : source_color = vec4(1.0, 0.2, 0.05, 1.0);
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

	static func quad(w: float, h: float, mat: Material) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(w, h)
		mi.mesh = qm
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi

	static func box(size: Vector3, col: Color, energy: float) -> MeshInstance3D:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		var mat := Vfx.add_material(col, energy, false)
		mat.set_shader_parameter("use_mask", false)
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return mi

	## Spinning annulus trail (axe sweep) that turns `turns` times over `dur`.
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
		tw.tween_method(func(v): mat.set_shader_parameter("fade", v), 1.0, 0.0, 0.32)
		return n

	## Static wedge / annulus flash on the ground.
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

	## Radial ground cracks.
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

	## One-shot spray of particles (blood, embers, debris).
	static func spray(m, pos: Vector3, col: Color, amount: int, speed: float, size: float, gravity: float = -9.0, life: float = 0.6, dir: Vector3 = Vector3.UP, spread: float = 70.0) -> void:
		var n := VfxNode.new()
		n.lifetime = life + 0.2
		m.add_fx(n, pos)
		var e := Vfx.emitter(col, amount, life, size, {"one_shot": true, "explosive": 0.95, "vmin": speed * 0.4, "vmax": speed,
				"gravity": Vector3(0, gravity, 0), "dir": dir, "spread": spread, "radius": 0.15, "damping": 1.0})
		e.emitting = true
		n.add_child(e)

	## Glowing orb that flies from a point to a unit (e.g. blood drained back to Darius).
	static func fly_to(m, from: Vector3, to_unit, col: Color, dur: float, size: float = 0.35) -> void:
		var orb := Vfx.orb(col, size, false, true)
		orb.lifetime = dur + 0.1
		m.add_fx(orb, from)
		var st := {"t": 0.0}
		m.add_ticker(dur + 0.05, func(dt):
			if not is_instance_valid(orb):
				return false
			st.t += dt
			var k: float = clampf(st.t / dur, 0.0, 1.0)
			var target: Vector3 = from
			if is_instance_valid(to_unit):
				target = to_unit.global_position + Vector3(0, 1.1, 0)
			var p: Vector3 = from.lerp(target, k * k)
			p.y += sin(k * PI) * 1.2
			orb.global_position = p
			return k < 1.0)


# ===================================================================== helpers
## Bots never spend points after spawning (core gap): level abilities on their behalf.
class BotLeveler extends Effect:
	func _init() -> void:
		id = "kit_bot_leveler"
		hidden = true

	func on_tick(u, _dt: float) -> void:
		if u.is_bot and u.ability_points > 0:
			u.auto_level_abilities()


## Base ability: `{"skip": true}` from ai_consider suppresses the generic bot fallback;
## nothing else can be cast during Decimate's wind-up.
class DAbility extends Ability:
	func try_cast(t: Dictionary) -> bool:
		if t.get("skip", false):
			return false
		return super.try_cast(t)

	func extra_block_reason() -> String:
		var ch: Dictionary = owner.channel
		if not ch.is_empty() and ch.ability != self and ch.ability is Decimate:
			return "casting"
		return ""

	func skip() -> Dictionary:
		return {"skip": true}

	func now() -> float:
		return owner.match_ref.time if owner.match_ref != null else 0.0


# ===================================================================== passive
class Hemorrhage extends Effect:
	var dvals := {}

	func _init() -> void:
		id = "darius_passive"
		display_name = "Hemorrhage"

	func val(n: String, d: float) -> float:
		return float(dvals.get(n, d))

	## Total bleed damage of one stack over its full duration.
	func per_stack_damage() -> float:
		var lv: float = owner.level
		return lerpf(13.0, 30.0, (lv - 1.0) / 17.0) + 0.3 * owner.stats.bonus_ad

	func might_ad() -> float:
		var lv: int = owner.level
		if lv < 10:
			return 30.0
		return 30.0 + (lv - 9) * 200.0 / 9.0

	func in_might() -> bool:
		return owner.has_buff("darius_might")

	func hud_counter() -> String:
		var b = owner.find_buff("darius_might")
		return str(int(ceil(b.remaining))) if b != null else ""

	func stacks_on(u) -> int:
		if u == null or not is_instance_valid(u):
			return 0
		var b = u.find_buff("darius_hemo", owner)
		return b.stacks if b != null else 0

	## Remaining bleed damage that will still tick on u.
	func pending_bleed(u) -> float:
		var b = u.find_buff("darius_hemo", owner)
		if b == null:
			return 0.0
		return per_stack_damage() * b.stacks * clampf(b.remaining / b.duration, 0.0, 1.0)

	func apply(u, n: int = 1) -> void:
		if u == null or not is_instance_valid(u) or u.dead:
			return
		if not (u.kind == G.Kind.CHAMPION or u.kind == G.Kind.MINION or u.kind == G.Kind.SUMMON):
			return
		if in_might():
			n = int(val("MaxStacks", 5.0))
		var b = u.find_buff("darius_hemo", owner)
		if b == null:
			var nb := HemoBuff.new("darius_hemo", val("BleedDuration", 5.0) + 0.02)
			nb.display_name = "Hemorrhage"
			nb.is_debuff = true
			nb.max_stacks = int(val("MaxStacks", 5.0))
			nb.tick_interval = 1.25
			nb.passive = self
			nb.stacks = 0
			b = u.add_buff(nb, owner)
			if b == null:
				return
		b.stacks = mini(b.max_stacks, b.stacks + n)
		b.remaining = b.duration
		b.update_fx()
		if b.stacks >= b.max_stacks and u.kind == G.Kind.CHAMPION:
			trigger_might()

	func trigger_might() -> void:
		var fresh := not in_might()
		K.buff(owner, "darius_might", val("BleedDuration", 5.0), {"ad": might_ad(), "size": 0.08}, owner,
				{"name": "Noxian Might", "icon": icon})
		var mb = owner.find_buff("darius_might")
		if not fresh or mb == null:
			return
		var m = owner.match_ref
		var n := VfxNode.new()
		owner.add_child(n)
		mb.vfx = n
		var e := Vfx.emitter(RED, 40, 0.8, 0.3, {"vmin": 0.6, "vmax": 1.8, "dir": Vector3.UP, "spread": 25.0, "radius": 0.55, "local": false})
		e.position.y = 0.6
		n.add_child(e)
		var glow := Vfx.sprite(RED, 2.6, 0.9)
		glow.position.y = 1.2
		n.add_child(glow)
		var l := Vfx.light(RED, 2.5, 4.0)
		l.position.y = 1.6
		n.add_child(l)
		Vfx.aura(owner, RED, 1.3, val("BleedDuration", 5.0), 0.08)
		Vfx.burst(m, owner.global_position + Vector3(0, 1.2, 0), RED, 1.6, {"sparks": 36})
		Fx.cracks(m, owner.global_position, 2.4, RED, 0.9, 7.0)
		if m.camera_rig != null and owner == G.player:
			m.camera_rig.shake(0.2)

	func on_attack_hit(target, info) -> void:
		if info == null or info.cancelled:
			return
		apply(target, 1)


class HemoBuff extends Buff:
	var passive = null
	var pips: Array = []

	func on_interval_tick(unit) -> void:
		var src = source
		if passive == null or src == null or not is_instance_valid(src) or unit.dead:
			return
		var dmg: float = passive.per_stack_damage() * stacks / 4.0
		Combat.deal(src, unit, dmg, G.DmgType.PHYSICAL, {"is_dot": true, "is_proc": true, "tag": "bleed"})
		if unit.match_ref != null and not unit.dead:
			Fx.spray(unit.match_ref, unit.global_position + Vector3(0, 1.0, 0), BLOOD, 6 + stacks * 2, 2.5, 0.16, -9.0, 0.5, Vector3.UP, 60.0)

	## Five orbiting blood-blades around the target, one lit per stack.
	func update_fx() -> void:
		var u = owner
		if u == null or not is_instance_valid(u):
			return
		if vfx == null or not is_instance_valid(vfx):
			var n := VfxNode.new()
			u.add_child(n)
			n.position.y = 1.05
			vfx = n
			pips.clear()
			for i in max_stacks:
				var s := Vfx.sprite(RED, 0.32, 2.2, Vfx.spark_texture())
				var a := TAU * i / float(max_stacks)
				s.position = Vector3(cos(a), 0.0, sin(a)) * maxf(0.75, u.radius * 1.15)
				n.add_child(s)
				pips.append(s)
			var drip := Vfx.emitter(BLOOD, 10, 0.7, 0.13, {"vmin": 0.0, "vmax": 0.3, "gravity": Vector3(0, -7, 0), "radius": 0.35})
			n.add_child(drip)
			var spin := n.create_tween().set_loops()
			spin.tween_property(n, "rotation:y", TAU, 2.4).from(0.0)
		var full := stacks >= max_stacks
		for i in pips.size():
			var s: MeshInstance3D = pips[i]
			s.visible = i < stacks
			s.scale = Vector3.ONE * (0.46 if full else 0.32)
			s.material_override.set_shader_parameter("energy", 3.2 if full else 2.0)


# ===================================================================== Q
class Decimate extends DAbility:
	var tele: VfxNode = null

	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.CIRCLE
		ind_radius = Q_OUTER
		cast_range = 0.0
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return {"pos": owner.global_position, "dir": owner.facing, "unit": null}

	func blade_damage() -> float:
		return dv("BaseDamage") + dv("TotalADRatio", 100.0) / 100.0 * ad()

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		o.stop_moving()
		o.cancel_windup()
		o.play_anim("spell1_in", 1.0, 0.05, Q_WINDUP)
		o.anim_lock = Q_WINDUP + 0.05
		start_channel(Q_WINDUP, {})
		o.channel_disarm = true
		# telegraph: the blade ring fills while Darius hefts his axe
		tele = VfxNode.new()
		tele.lifetime = Q_WINDUP + 0.1
		o.add_child(tele)
		tele.position.y = 0.12
		var mat := Fx.arc_mat(Color(0.8, 0.05, 0.03, 0.6), RED, Q_INNER / Q_OUTER, true)
		mat.set_shader_parameter("tail", TAU + 0.1)
		mat.set_shader_parameter("flat_tail", 1.0)
		mat.set_shader_parameter("energy", 1.2)
		tele.add_child(Fx.plane(Q_OUTER * G.U * 2.0, mat))
		var tw := tele.create_tween()
		tw.tween_method(func(v): mat.set_shader_parameter("fade", v), 0.15, 0.55, Q_WINDUP)
		var axe_glow := Vfx.sprite(RED, 1.4, 2.0)
		axe_glow.position.y = 2.6
		tele.add_child(axe_glow)
		var tw2 := tele.create_tween()
		tw2.tween_property(axe_glow, "scale", Vector3.ONE * 0.4, Q_WINDUP).from(Vector3.ONE * 1.4)
		var embers := Vfx.emitter(EMBER, 24, 0.6, 0.16, {"vmin": 0.8, "vmax": 2.0, "dir": Vector3.UP, "spread": 20.0, "radius": 0.6, "local": true})
		embers.position.y = 1.0
		tele.add_child(embers)
		notify_cast(t)

	func channel_end(_ch: Dictionary, interrupted: bool) -> void:
		var o = owner
		o.channel_disarm = false
		if tele != null and is_instance_valid(tele):
			tele.detach_and_fade()
		tele = null
		if interrupted or o.dead:
			o.anim_lock = 0.0
			return
		_swing()

	func _swing() -> void:
		var o = owner
		var m = o.match_ref
		var p: Vector3 = o.global_position
		o.play_anim("spell1", 1.0, 0.03)
		o.anim_lock = 0.5
		var blade := blade_damage()
		var handle := blade * dv("InnerCircleDamagePercent", 35.0) / 100.0
		var hemo = o.passive
		var champs := 0
		for u in K.enemies_circle(self, p, Q_OUTER):
			var d := G.flat_dist(p, u.global_position)
			var tp: Vector3 = u.global_position + Vector3(0, 1.0, 0)
			if d > Q_INNER * G.U:
				var dmg := blade * (0.9 if u.kind == G.Kind.MINION else 1.0)
				var info := hit(u, dmg, G.DmgType.PHYSICAL, {"is_aoe": true, "tag": "q_blade"})
				if not info.killed:
					hemo.apply(u, 1)
				if u.kind == G.Kind.CHAMPION:
					champs += 1
					Fx.fly_to(m, tp, o, Color(1.0, 0.15, 0.1), 0.45, 0.42)
				Fx.spray(m, tp, BLOOD, 18, 5.0, 0.2, -10.0, 0.55, G.flat_dir(p, u.global_position) + Vector3(0, 0.6, 0), 35.0)
				Vfx.hit_spark(m, tp, RED, 0.9)
			else:
				hit(u, handle, G.DmgType.PHYSICAL, {"is_aoe": true, "tag": "q_handle"})
				Vfx.hit_spark(m, tp, STEEL, 0.5)
		if champs > 0:
			var pct := minf(dv("MissingHealPercent", 51.0), dv("MissingHealthHeal", 17.0) * champs) / 100.0
			Combat.heal(o, o, (o.stats.max_hp - o.hp) * pct)
			m.after(0.45, func():
				if is_instance_valid(o) and not o.dead:
					Vfx.rising(o, Color(1.0, 0.25, 0.2), 0.4, 26, 0.5))
		# the swing: crimson blade trail sweeping a full circle, dark handle flash inside
		var start := atan2(o.facing.z, o.facing.x)
		Fx.sweep(m, p, Q_OUTER * G.U, Q_INNER / Q_OUTER, RED, Color(1.0, 0.8, 0.7), start, 1.08, 0.24, 0.95)
		Fx.sweep(m, p, Q_OUTER * G.U * 1.02, 0.86, Color(1.0, 0.3, 0.15), Color(1, 1, 1), start - 0.4, 1.08, 0.26, 0.15, true)
		var inner_flash := Fx.wedge(m, p, Q_INNER * G.U, 0.0, Color(0.5, 0.05, 0.05), Color(0.6, 0.1, 0.1), 0.0, TAU + 0.1, 0.3)
		inner_flash.position.y += 0.02
		Vfx.ring(m, p, RED, Q_OUTER * G.U * 1.05, 0.35, 0.06, 0.0)
		var sp := VfxNode.new()
		sp.lifetime = 0.9
		m.add_fx(sp, p + Vector3(0, 0.9, 0))
		var e := Vfx.emitter(RED, 60, 0.5, 0.2, {"one_shot": true, "explosive": 0.9, "vmin": 2.0, "vmax": 5.0, "gravity": Vector3(0, -8, 0),
				"spread": 90.0, "dir": Vector3.UP, "tex": Vfx.spark_texture(), "damping": 2.0})
		var pm: ParticleProcessMaterial = e.process_material
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
		pm.emission_ring_axis = Vector3.UP
		pm.emission_ring_radius = Q_OUTER * G.U * 0.92
		pm.emission_ring_inner_radius = Q_OUTER * G.U * 0.75
		pm.emission_ring_height = 0.1
		e.emitting = true
		sp.add_child(e)
		if m.camera_rig != null and o == G.player:
			m.camera_rig.shake(0.12)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var blade_n := 0
		var inside := 0
		for e in ctx.enemies:
			var pp: Vector3 = ctx.predict(e, Q_WINDUP * 0.5)
			var d := G.flat_dist(p, pp)
			if d <= Q_OUTER * G.U + e.radius * 0.3:
				inside += 1
				if d > Q_INNER * G.U + 0.15:
					blade_n += 1
		if blade_n >= 1 or inside >= 2:
			return {"pos": p}
		if inside >= 1 and (o.hp_ratio() < 0.5 or ctx.mode == "fight" and o.stats.uses_mana and o.mana > o.stats.max_mana * 0.7):
			return {"pos": p}
		if ctx.enemies.is_empty() and o.mana > o.stats.max_mana * 0.55:
			var n := 0
			for mn in ctx.enemy_minions:
				var d2 := G.flat_dist(p, mn.global_position)
				if d2 <= Q_OUTER * G.U and d2 > Q_INNER * G.U * 0.7:
					n += 1
			if n >= 3:
				return {"pos": p}
		return skip()


# ===================================================================== W
class CripplingStrike extends DAbility:
	var empowered_until := -1.0
	var saved_attack: Array = []
	var saved_crit: Array = []
	var fx: VfxNode = null

	func _init() -> void:
		target_type = Target.NONE
		indicator = Ind.NONE
		cast_time = 0.0
		cast_range = 0.0
		anim = ""
		anim_lock = 0.0
		resets_attack = true

	func make_target(_world_pos: Vector3, _hovered = null) -> Dictionary:
		return {"pos": owner.global_position, "dir": owner.facing, "unit": null}

	func execute(t: Dictionary) -> void:
		var o = owner
		if not is_empowered():
			var clip: String = o._raw_clip("spell2")
			if clip != "":
				saved_attack = o.anim_map.get("attack", []).duplicate()
				saved_crit = o.anim_map.get("crit", []).duplicate()
				o.anim_map["attack"] = [clip]
				o.anim_map["crit"] = [clip]
		empowered_until = now() + 4.0
		if fx != null and is_instance_valid(fx):
			fx.queue_free()
		fx = VfxNode.new()
		fx.lifetime = 4.0
		o.add_child(fx)
		fx.position.y = 1.4
		var core := Vfx.sprite(RED, 1.1, 1.6)
		fx.add_child(core)
		var e := Vfx.emitter(EMBER, 26, 0.45, 0.18, {"vmin": 0.3, "vmax": 1.2, "radius": 0.5, "dir": Vector3.UP, "spread": 50.0})
		fx.add_child(e)
		var tw := fx.create_tween().set_loops()
		tw.tween_property(core, "scale", Vector3.ONE * 1.5, 0.25)
		tw.tween_property(core, "scale", Vector3.ONE * 1.0, 0.25)
		Vfx.rising(o, RED, 0.25, 16, 0.5)
		notify_cast(t)

	func is_empowered() -> bool:
		return empowered_until > 0.0 and now() < empowered_until

	func consume() -> void:
		var o = owner
		empowered_until = -1.0
		if not saved_attack.is_empty():
			o.anim_map["attack"] = saved_attack
			o.anim_map["crit"] = saved_crit if not saved_crit.is_empty() else saved_attack
			saved_attack = []
			saved_crit = []
		if fx != null and is_instance_valid(fx):
			fx.detach_and_fade()
		fx = null

	func on_tick(_dt: float) -> void:
		if empowered_until > 0.0 and now() >= empowered_until:
			consume()

	func damage_estimate() -> float:
		return dv("ADRatio", 1.4) * ad()

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		if is_empowered():
			return skip()
		var f = ctx.focus
		if ctx.mode == "fight" and f != null and is_instance_valid(f) and o.in_attack_range(f, 0.4):
			if o.windup_timer < 0.0 and o.attack_timer > 0.12:
				return {"pos": o.global_position}
			if f.hp_ratio() < 0.2:
				return {"pos": o.global_position}
		if ctx.mode == "retreat":
			return skip()
		if ctx.enemies.is_empty() and o.mana > o.stats.max_mana * 0.4 and o.attack_target != null and is_instance_valid(o.attack_target):
			var mn = o.attack_target
			if mn.kind == G.Kind.MINION and o.in_attack_range(mn, 0.2):
				var est: float = damage_estimate() * Combat.resist_multiplier(mn.stats.armor, o, true)
				if mn.hp < est and mn.hp > o.stats.ad * Combat.resist_multiplier(mn.stats.armor, o, true):
					return {"pos": o.global_position}
		return skip()


class WAttackHook extends Effect:
	var w

	func _init(p_w) -> void:
		w = p_w
		id = "darius_w_hook"
		hidden = true

	func on_pre_damage_dealt(info) -> void:
		if info.is_attack and info.target != null and w.is_empowered() and info.tag != "darius_w":
			info.amount = owner.stats.ad * w.dv("ADRatio", 1.4) * (owner.stats.crit_damage if info.is_crit else 1.0)
			info.tag = "darius_w"

	func on_attack_hit(target, info) -> void:
		if info == null or info.tag != "darius_w":
			return
		var o = owner
		var m = o.match_ref
		w.consume()
		if is_instance_valid(target) and not target.dead:
			K.slow(target, w.dv("SlowPercent", 90.0) / 100.0, w.dv("SlowDuration", 1.0), o, false, "darius_w_slow")
		var tp: Vector3 = target.global_position + Vector3(0, 1.0, 0)
		Vfx.burst(m, tp, RED, 1.1, {"sparks": 26, "ring": false})
		Fx.spray(m, tp, BLOOD, 20, 4.5, 0.2, -10.0, 0.55, G.flat_dir(o.global_position, target.global_position) + Vector3(0, 0.5, 0), 40.0)
		Fx.cracks(m, target.global_position, 1.4, RED, 0.6, 6.0)
		if info.killed:
			if o.stats.uses_mana:
				o.mana = minf(o.stats.max_mana, o.mana + w.cost())
			w.reduce_cooldown_pct(w.dv("PercentCDRefund", 50.0) / 100.0)
			Vfx.rising(o, Color(0.5, 0.6, 1.0), 0.3, 14, 0.4)


# ===================================================================== E
class Apprehend extends DAbility:
	func _init() -> void:
		target_type = Target.DIRECTION
		indicator = Ind.CONE
		ind_angle = 50.0
		cast_time = 0.25
		anim = "spell3"
		anim_lock = 0.55

	func execute(t: Dictionary) -> void:
		var o = owner
		var m = o.match_ref
		var origin: Vector3 = o.global_position
		var dir: Vector3 = t.dir
		var length := cast_range
		var hits := K.enemies_cone(self, origin, dir, length, ind_angle)
		var ang := atan2(dir.z, dir.x)
		Fx.wedge(m, origin, length * G.U, 0.12, Color(0.85, 0.08, 0.05), Color(1.0, 0.5, 0.3), ang, deg_to_rad(ind_angle), 0.4)
		# axe sweep along the cone edge, pulling inward
		Fx.sweep(m, origin, length * G.U, 0.8, RED, Color(1, 0.85, 0.8), ang - deg_to_rad(ind_angle) * 0.5, deg_to_rad(ind_angle) / TAU, 0.22, 1.0)
		for u in hits:
			var up: Vector3 = u.global_position
			var dist := G.flat_dist(origin, up)
			var keep: float = o.radius + u.radius + 0.25
			Vfx.beam(m, origin + Vector3(0, 1.1, 0), up + Vector3(0, 1.0, 0), Color(0.9, 0.12, 0.08), 0.16, 0.28)
			if u.has_cc_immunity():
				continue
			if dist > keep:
				u.pull_to(origin + G.flat_dir(origin, up) * keep, 0.28, o)
			K.slow(u, dv("SlowPercent", 40.0) / 100.0, dv("SlowDuration", 1.0) + 0.28, o, false, "darius_e_slow")
			var hook := VfxNode.new()
			hook.lifetime = 0.45
			hook.follow = u
			hook.follow_offset = Vector3(0, 1.1, 0)
			m.add_fx(hook, up + Vector3(0, 1.1, 0))
			hook.add_child(Vfx.sprite(RED, 1.0, 2.6, Vfx.spark_texture()))
			hook.add_child(Vfx.sprite(EMBER, 0.6, 2.0))
			Vfx.hit_spark(m, up + Vector3(0, 1.0, 0), RED, 0.8)
		notify_cast(t)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		if ctx.mode == "retreat" and o.hp_ratio() < 0.3:
			return skip()
		var best: Unit = null
		var best_s := -INF
		for e in ctx.enemies:
			if e.has_cc_immunity():
				continue
			var d := G.flat_dist(p, e.global_position)
			if d > range_m() + e.radius * 0.4 - 0.2:
				continue
			if d < o.attack_range_m() + o.radius + e.radius + 0.9:
				continue
			var away: float = e.velocity.dot(G.flat_dir(p, e.global_position))
			var s: float = (1.0 - e.hp_ratio()) * 3.0 + (2.0 if e == ctx.focus else 0.0) + (1.5 if away > 1.0 else 0.0) + (0.8 if e.stats.attack_range > 300.0 else 0.0)
			if ctx.mode != "fight" and e.hp_ratio() > 0.6 and o.hp_ratio() < 0.5:
				continue
			if s > best_s:
				best_s = s
				best = e
		if best != null and (ctx.mode == "fight" or best.hp_ratio() < 0.5 or o.hp_ratio() > 0.6):
			return ctx.aim_at(ctx.predict(best, cast_time), self)
		return skip()


class ApprehendPen extends Effect:
	var e_ab

	func _init(p_e) -> void:
		e_ab = p_e
		id = "darius_e_pen"
		hidden = true

	func get_stat_mods() -> Dictionary:
		if e_ab == null or e_ab.level <= 0:
			return {}
		return {"armor_pen%": e_ab.dv("PassivePercentArmorPen", 20.0) / 100.0}


# ===================================================================== R
class NoxianGuillotine extends DAbility:
	var free_until := -1.0
	var saved_cd := 0.0

	func _init() -> void:
		target_type = Target.UNIT
		target_side = Side.ENEMY
		target_champions_only = true
		indicator = Ind.NONE
		cast_range = 460.0
		cast_time = 0.0
		anim = ""
		anim_lock = 0.0

	func is_dash() -> bool:
		return true

	func is_free() -> bool:
		return free_until > 0.0 and now() < free_until

	func cost() -> float:
		return 0.0 if is_free() else super.cost()

	func damage_vs(u) -> float:
		var st: int = owner.passive.stacks_on(u)
		var base := dv("RBaseDamage") + 0.75 * bonus_ad()
		return base * (1.0 + minf(5.0, float(st)) * dv("RDamagePercentPerHemoStack", 0.2))

	func on_tick(_dt: float) -> void:
		if free_until > 0.0 and now() >= free_until:
			free_until = -1.0
			cd = maxf(0.0, saved_cd - dv("RRecastDuration", 20.0))
			cd_total = maxf(cd, 0.01)

	func execute(t: Dictionary) -> void:
		var o = owner
		var u = t.unit
		if u == null or not is_instance_valid(u) or u.dead:
			return
		free_until = -1.0
		var m = o.match_ref
		var self_ref := self
		var from: Vector3 = o.global_position
		var leap := 0.45
		var off: float = u.radius + o.radius * 0.4
		var dest: Vector3 = u.global_position - G.flat_dir(from, u.global_position) * off
		o.play_anim("spell4", 1.0, 0.03, 0.95)
		o.anim_lock = 0.95
		o.start_dash(dest, {"duration": leap, "height": 2.4,
			"on_tick": func(unit, _k):
				if is_instance_valid(u) and not u.dead and not unit.dash.is_empty():
					unit.dash.to = u.global_position - G.flat_dir(from, u.global_position) * off
					unit.face_toward(u.global_position, 100.0),
			"on_arrive": func(_unit): self_ref._impact(u)})
		# leap trail
		var trail := VfxNode.new()
		trail.lifetime = leap + 0.05
		o.add_child(trail)
		trail.position.y = 1.2
		var te := Vfx.emitter(RED, 60, 0.4, 0.4, {"vmin": 0.0, "vmax": 0.4, "radius": 0.4})
		trail.add_child(te)
		trail.trails.append(te)
		trail.add_child(Vfx.sprite(RED, 1.8, 1.2))
		_guillotine(u, leap)
		notify_cast(t)

	## A spectral axe descends over the victim, synced with the dunk.
	func _guillotine(u, leap: float) -> void:
		var m = owner.match_ref
		var n := VfxNode.new()
		n.lifetime = leap + 0.15
		n.follow = u
		n.follow_offset = Vector3(0, 6.0, 0)
		m.add_fx(n, u.global_position + Vector3(0, 6.0, 0))
		# grip at the node origin, axe head 3 m up the haft; it chops clockwise down onto the target
		n.follow_offset = Vector3(0, 3.1, 0)
		var axe := Node3D.new()
		n.add_child(axe)
		var haft := Fx.box(Vector3(0.16, 3.3, 0.16), Color(0.9, 0.15, 0.1), 2.2)
		haft.position.y = 1.65
		axe.add_child(haft)
		var bmat := Fx.arc_mat(Color(1.0, 0.1, 0.05), Color(1.0, 0.85, 0.7), 0.45, false)
		bmat.set_shader_parameter("head", deg_to_rad(75.0))
		bmat.set_shader_parameter("tail", deg_to_rad(150.0))
		bmat.set_shader_parameter("flat_tail", 1.0)
		bmat.set_shader_parameter("energy", 3.0)
		var blade := Fx.plane(2.6, bmat)
		blade.rotation.x = PI * 0.5
		blade.position = Vector3(-0.55, 2.9, 0.0)
		axe.add_child(blade)
		var l := Vfx.light(RED, 4.0, 6.0)
		l.position.y = 2.8
		axe.add_child(l)
		axe.rotation.z = 0.5
		var tw := n.create_tween()
		tw.tween_property(axe, "rotation:z", -PI, leap).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
		# ground mark under the victim
		var mark := Fx.wedge(m, u.global_position, 1.6, 0.0, Color(0.7, 0.04, 0.04), RED, 0.0, TAU + 0.1, leap + 0.1)
		mark.follow = u

	func _impact(u) -> void:
		var o = owner
		var m = o.match_ref
		var p: Vector3 = o.global_position
		var tp: Vector3 = p
		var info: DamageInfo = null
		if u != null and is_instance_valid(u) and not u.dead:
			tp = u.global_position
			info = hit(u, damage_vs(u), G.DmgType.TRUE, {"tag": "r"})
			if info != null and not info.killed and not info.cancelled:
				o.passive.apply(u, 1)
		var big: bool = o == G.player or (u != null and is_instance_valid(u) and u == G.player)
		Vfx.burst(m, tp + Vector3(0, 0.8, 0), RED, 2.6, {"sparks": 60})
		Fx.cracks(m, tp, 3.6, RED, 1.4, 11.0)
		Fx.spray(m, tp + Vector3(0, 1.0, 0), BLOOD, 50, 7.0, 0.26, -12.0, 0.8, Vector3.UP, 85.0)
		Vfx.ring(m, tp, RED, 4.2, 0.5, 0.08, 0.12)
		Vfx.ring(m, tp, EMBER, 2.6, 0.35, 0.12, 0.0)
		Vfx.beam(m, tp + Vector3(0, 6.0, 0), tp, Color(1.0, 0.2, 0.1), 0.6, 0.3)
		if m.camera_rig != null:
			m.camera_rig.shake(0.5 if big else 0.18)
		if info != null and info.killed:
			_on_execute_kill(tp)

	func _on_execute_kill(tp: Vector3) -> void:
		var o = owner
		var m = o.match_ref
		o.passive.trigger_might()
		if level >= 3:
			cd = 0.0
		else:
			saved_cd = cd
			cd = 0.0
			free_until = now() + dv("RRecastDuration", 20.0)
		var sig := Vfx.ring(m, tp, RED, 5.5, 0.8, 0.05, 0.0)
		sig.get_child(0).material_override.set_shader_parameter("segments", 10.0)
		Vfx.rising(o, RED, 0.6, 40, 0.6)
		m.fx_text(o, "Guillotine reset!", RED)

	func ai_consider(ctx) -> Dictionary:
		var o = owner
		var p: Vector3 = o.global_position
		var best = null
		var best_hp := INF
		for e in ctx.enemies:
			if not valid_unit_target(e):
				continue
			var d := G.flat_dist(p, e.global_position)
			if d > range_m() + o.radius + e.radius + 0.4:
				continue
			var dmg := damage_vs(e)
			var eff: float = e.hp + e.total_shield()
			var ok := dmg >= eff
			if not ok and dmg + o.passive.pending_bleed(e) * 0.6 >= eff and o.passive.stacks_on(e) >= 3:
				ok = true
			if ok and e.hp < best_hp:
				best_hp = e.hp
				best = e
		if best != null:
			return {"unit": best, "pos": best.global_position, "dir": G.flat_dir(p, best.global_position)}
		return skip()
