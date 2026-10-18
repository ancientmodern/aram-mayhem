class_name Vfx
extends RefCounted
## Procedural visual-effects factory (orbs, trails, bursts, rings, beams, auras).

const ADD_SHADER := preload("res://src/vfx/shaders/vfx_add.gdshader")
const RING_SHADER := preload("res://src/vfx/shaders/vfx_ring.gdshader")
const IND_SHADER := preload("res://src/vfx/shaders/indicator.gdshader")

static var _soft_tex: Texture2D = null
static var _spark_tex: Texture2D = null
static var _ring_tex: Texture2D = null
static var _quad: QuadMesh = null


static func soft_circle_texture() -> Texture2D:
	if _soft_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.65))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 128
		gt.height = 128
		_soft_tex = gt
	return _soft_tex


static func spark_texture() -> Texture2D:
	if _spark_tex == null:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		for y in 64:
			for x in 64:
				var dx := (x - 31.5) / 31.5
				var dy := (y - 31.5) / 31.5
				var a := maxf(0.0, 1.0 - absf(dx) * 6.0) * maxf(0.0, 1.0 - absf(dy)) + maxf(0.0, 1.0 - absf(dy) * 6.0) * maxf(0.0, 1.0 - absf(dx)) * 0.6
				a += maxf(0.0, 1.0 - sqrt(dx * dx + dy * dy) * 2.2) * 0.6
				a = clampf(a, 0.0, 1.0)
				img.set_pixel(x, y, Color(a, a, a, a))
		_spark_tex = ImageTexture.create_from_image(img)
	return _spark_tex


static func quad() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
		_quad.size = Vector2(1, 1)
	return _quad


static func add_material(color: Color, energy: float = 2.0, billboard: bool = true, tex: Texture2D = null) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = ADD_SHADER
	m.set_shader_parameter("color", color)
	m.set_shader_parameter("energy", energy)
	m.set_shader_parameter("billboard", billboard)
	m.set_shader_parameter("mask_tex", tex if tex != null else soft_circle_texture())
	m.set_shader_parameter("use_mask", true)
	return m


static func particle_material_billboard(color: Color, energy: float, tex: Texture2D = null) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy, color.a)
	m.albedo_texture = tex if tex != null else soft_circle_texture()
	m.no_depth_test = false
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	return m


static func _fade_ramp(c: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(c.r, c.g, c.b, 0))
	g.add_point(0.15, Color(1, 1, 1, 1))
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


# ===================================================================== building blocks
## Glowing billboard sprite.
static func sprite(color: Color, size: float, energy: float = 2.0, tex: Texture2D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = quad()
	mi.material_override = add_material(color, energy, true, tex)
	mi.scale = Vector3.ONE * size
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## World-space particle trail/emitter.
static func emitter(color: Color, amount: int, lifetime: float, size: float, opts: Dictionary = {}) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.local_coords = opts.get("local", false)
	p.one_shot = opts.get("one_shot", false)
	p.explosiveness = opts.get("explosive", 0.0)
	p.visibility_aabb = AABB(Vector3(-20, -20, -20), Vector3(40, 40, 40))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = opts.get("radius", 0.05)
	pm.direction = opts.get("dir", Vector3(0, 1, 0))
	pm.spread = opts.get("spread", 180.0)
	pm.initial_velocity_min = opts.get("vmin", 0.2)
	pm.initial_velocity_max = opts.get("vmax", 1.0)
	pm.gravity = opts.get("gravity", Vector3.ZERO)
	pm.damping_min = opts.get("damping", 0.0)
	pm.damping_max = opts.get("damping", 0.0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1))
	sc.add_point(Vector2(1, opts.get("end_scale", 0.0)))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.color_ramp = _fade_ramp(color)
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = particle_material_billboard(color, opts.get("energy", 2.5), opts.get("tex", null))
	p.draw_pass_1 = q
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return p


static func light(color: Color, energy: float, rng: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = false
	return l


# ===================================================================== composite effects
## Projectile visual: hot core + halo + trail (+ optional light).
static func orb(color: Color, size: float = 0.35, with_light: bool = false, trail: bool = true) -> VfxNode:
	var n := VfxNode.new()
	n.add_child(sprite(color.lerp(Color.WHITE, 0.6), size * 0.55, 3.0))
	n.add_child(sprite(color, size * 1.6, 1.6))
	if trail:
		var e := emitter(color, 40, 0.35, size * 0.9, {"vmin": 0.0, "vmax": 0.3, "radius": size * 0.25})
		n.add_child(e)
		n.trails.append(e)
	if with_light:
		n.add_child(light(color, 2.0, size * 10.0))
	return n


static func attack_missile(src, crit: bool) -> VfxNode:
	var col: Color = src.get("attack_color") if src.get("attack_color") != null else (Color(0.4, 0.75, 1.0) if src.team == G.Team.ORDER else Color(1.0, 0.45, 0.35))
	if src.kind == G.Kind.TURRET:
		var t := orb(col.lerp(Color.WHITE, 0.2), 0.75, true)
		return t
	if src.kind == G.Kind.MINION:
		return orb(col, 0.25, false)
	var o := orb(col, 0.32 if not crit else 0.5, false)
	return o


## Explosion: flash, sparks, expanding ring.
static func burst(m, pos: Vector3, color: Color, radius: float = 1.5, opts: Dictionary = {}) -> void:
	var n := VfxNode.new()
	n.lifetime = 1.2
	m.add_fx(n, pos)
	var flash := sprite(color.lerp(Color.WHITE, 0.5), radius * 1.4, 3.0)
	n.add_child(flash)
	var tw := n.create_tween()
	tw.tween_property(flash, "scale", Vector3.ONE * radius * 2.4, 0.25).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_method(func(v): flash.material_override.set_shader_parameter("energy", v), 3.0, 0.0, 0.3)
	var sp := emitter(color, int(opts.get("sparks", 28)), 0.6, radius * 0.25,
			{"one_shot": true, "explosive": 1.0, "vmin": radius * 2.0, "vmax": radius * 4.5, "damping": radius * 4.0,
			 "gravity": Vector3(0, -4, 0), "tex": spark_texture()})
	sp.emitting = true
	n.add_child(sp)
	if opts.get("ring", true):
		ring(m, pos, color, radius, 0.45)
	if opts.get("light", true):
		var l := light(color, 4.0, radius * 4.0)
		l.position.y = 0.8
		n.add_child(l)
		var tw2 := n.create_tween()
		tw2.tween_property(l, "light_energy", 0.0, 0.4)


## Expanding ground ring (shockwave).
static func ring(m, pos: Vector3, color: Color, radius: float, duration: float = 0.5, thickness: float = 0.1, fill: float = 0.15) -> VfxNode:
	var n := VfxNode.new()
	n.lifetime = duration + 0.05
	m.add_fx(n, pos + Vector3(0, 0.08, 0))
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("thickness", thickness)
	mat.set_shader_parameter("fill", fill)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	var tw := n.create_tween()
	tw.tween_method(func(v): mat.set_shader_parameter("progress", v), 0.0, 1.0, duration).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_method(func(v): mat.set_shader_parameter("fade", v), 1.0, 0.0, duration).set_ease(Tween.EASE_IN)
	return n


## Static ground circle (telegraph / zone). Returns the node; caller frees or sets lifetime.
static func ground_circle(m, pos: Vector3, radius: float, color: Color, lifetime: float = 1.0, fill: float = 0.25) -> VfxNode:
	var n := VfxNode.new()
	n.lifetime = lifetime
	m.add_fx(n, pos + Vector3(0, 0.06, 0))
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("progress", 1.0)
	mat.set_shader_parameter("thickness", 0.06)
	mat.set_shader_parameter("fill", fill)
	mat.set_shader_parameter("energy", 1.6)
	mi.material_override = mat
	n.add_child(mi)
	n.set_meta("mat", mat)
	var tw := n.create_tween()
	tw.tween_interval(maxf(0.0, lifetime - 0.25))
	tw.tween_method(func(v): mat.set_shader_parameter("fade", v), 1.0, 0.0, 0.25)
	return n


## Beam between two points (laser, chain).
static func beam(m, from: Vector3, to: Vector3, color: Color, width: float, duration: float) -> VfxNode:
	var n := VfxNode.new()
	n.lifetime = duration + 0.05
	m.add_fx(n, (from + to) * 0.5)
	var len := from.distance_to(to)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = width * 0.5
	cm.bottom_radius = width * 0.5
	cm.height = len
	cm.radial_segments = 12
	cm.rings = 1
	mi.mesh = cm
	var mat := ShaderMaterial.new()
	mat.shader = ADD_SHADER
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("energy", 3.0)
	mat.set_shader_parameter("use_mask", false)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(mi)
	var core := MeshInstance3D.new()
	var cm2 := CylinderMesh.new()
	cm2.top_radius = width * 0.18
	cm2.bottom_radius = width * 0.18
	cm2.height = len
	core.mesh = cm2
	var mat2 := mat.duplicate()
	mat2.set_shader_parameter("color", Color(1, 1, 1, 1))
	mat2.set_shader_parameter("energy", 4.0)
	core.material_override = mat2
	n.add_child(core)
	var dir := (to - from).normalized()
	if absf(dir.dot(Vector3.UP)) > 0.99:
		n.look_at(n.global_position + Vector3.FORWARD, dir)
	else:
		n.basis = Basis(dir.cross(Vector3.UP).normalized(), dir, dir.cross(dir.cross(Vector3.UP)).normalized() * -1.0).orthonormalized()
		n.basis = _basis_y_along(dir)
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3(0.05, 1.0, 0.05), duration).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	return n


static func _basis_y_along(dir: Vector3) -> Basis:
	var y := dir.normalized()
	var ref := Vector3.UP if absf(y.dot(Vector3.UP)) < 0.95 else Vector3.RIGHT
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	return Basis(x, y, z)


## Small impact spark at a point.
static func hit_spark(m, pos: Vector3, color: Color, size: float = 0.6) -> void:
	var n := VfxNode.new()
	n.lifetime = 0.5
	m.add_fx(n, pos)
	var s := sprite(color.lerp(Color.WHITE, 0.4), size, 3.0, spark_texture())
	n.add_child(s)
	s.rotation.z = G.rng.randf() * TAU
	var tw := n.create_tween()
	tw.tween_property(s, "scale", Vector3.ONE * size * 1.8, 0.15)
	tw.parallel().tween_method(func(v): s.material_override.set_shader_parameter("energy", v), 3.0, 0.0, 0.2)
	var e := emitter(color, 10, 0.35, size * 0.25, {"one_shot": true, "explosive": 1.0, "vmin": 2.0, "vmax": 5.0, "damping": 8.0, "tex": spark_texture()})
	e.emitting = true
	n.add_child(e)


## Aura attached to a unit for a duration (buff visuals).
static func aura(unit: Node3D, color: Color, radius: float, duration: float, height: float = 0.05) -> VfxNode:
	var n := VfxNode.new()
	n.lifetime = duration
	unit.add_child(n)
	n.position = Vector3(0, height, 0)
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(radius * 2.0, radius * 2.0)
	mi.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = RING_SHADER
	mat.set_shader_parameter("color", color)
	mat.set_shader_parameter("progress", 1.0)
	mat.set_shader_parameter("thickness", 0.15)
	mat.set_shader_parameter("fill", 0.2)
	mat.set_shader_parameter("energy", 1.5)
	mat.set_shader_parameter("rotate_speed", 1.5)
	mat.set_shader_parameter("segments", 8.0)
	mi.material_override = mat
	n.add_child(mi)
	return n


## Rising particles on a unit (heals, level up, buffs).
static func rising(unit: Node3D, color: Color, duration: float = 1.0, amount: int = 30, radius: float = 0.6) -> VfxNode:
	var n := VfxNode.new()
	n.lifetime = duration + 1.0
	unit.add_child(n)
	var e := emitter(color, amount, 1.0, 0.22, {"one_shot": false, "vmin": 1.0, "vmax": 2.5, "dir": Vector3.UP, "spread": 10.0,
			"radius": radius, "local": true})
	n.add_child(e)
	n.trails.append(e)
	var tw := n.create_tween()
	tw.tween_interval(duration)
	tw.tween_callback(func(): e.emitting = false)
	return n


## Swirling stars over the head (stun).
static func stun_stars(unit: Node3D, duration: float) -> VfxNode:
	var n := VfxNode.new()
	n.lifetime = duration
	unit.add_child(n)
	n.position = Vector3(0, unit.get("height") * 1.05 if unit.get("height") != null else 2.0, 0)
	for i in 3:
		var s := sprite(Color(1.0, 0.9, 0.3), 0.28, 2.5, spark_texture())
		n.add_child(s)
		s.position = Vector3(cos(i * TAU / 3.0), 0, sin(i * TAU / 3.0)) * 0.45
	var tw := n.create_tween().set_loops()
	tw.tween_property(n, "rotation:y", TAU, 0.9).from(0.0)
	return n


## Shield bubble around a unit.
static func shield_bubble(unit: Node3D, color: Color, duration: float, radius: float = 1.0) -> VfxNode:
	var n := VfxNode.new()
	n.lifetime = duration
	unit.add_child(n)
	n.position = Vector3(0, radius * 0.9, 0)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	mi.mesh = sm
	var mat := ShaderMaterial.new()
	mat.shader = ADD_SHADER
	mat.set_shader_parameter("color", Color(color.r, color.g, color.b, 0.6))
	mat.set_shader_parameter("energy", 1.2)
	mat.set_shader_parameter("use_mask", false)
	mi.material_override = mat
	n.add_child(mi)
	mi.scale = Vector3.ONE * 0.6
	var tw := n.create_tween()
	tw.tween_property(mi, "scale", Vector3.ONE, 0.2).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	return n


## Ground targeting indicator mesh (used by PlayerController).
static func indicator_mesh(shape: int, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1, 1)
	mi.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = IND_SHADER
	mat.set_shader_parameter("shape", shape)
	mat.set_shader_parameter("color", color)
	# League targeter textures (tools/lol/extract_world_ui.py -> assets/ui/world/ind_*.png)
	var main_tex: String = ["aoe", "locallinemissilebase", "conicrangeindicator", "circularrangeindicator", ""][clampi(shape, 0, 4)]
	if main_tex != "":
		mat.set_shader_parameter("tex_main", load("res://assets/ui/world/ind_%s.png" % main_tex))
	if shape == 1:
		mat.set_shader_parameter("tex_tip", load("res://assets/ui/world/ind_locallinemissiletarget.png"))
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
