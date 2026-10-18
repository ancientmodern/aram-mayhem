class_name MapBuilder
extends RefCounted
## Builds the Howling Abyss: terrain mesh, environment, layout (structures, lane, relics).

const MAP_GLB := "res://assets/map/howling_abyss.glb"
const MATERIALS_JSON := "res://data/map/map_materials.json"
const LAYOUT_JSON := "res://data/map/howling_abyss_layout.json"
const LIT_SHADER := preload("res://src/vfx/shaders/map_lightmap.gdshader")
const BLEND_SHADER := preload("res://src/vfx/shaders/map_blend.gdshader")


static func load_layout() -> Dictionary:
	if not FileAccess.file_exists(LAYOUT_JSON):
		return {}
	return JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_JSON))


static func lol(p: Array) -> Vector3:
	return G.lol_pos(float(p[0]), float(p[1]), float(p[2]))


static func build_terrain(parent: Node3D) -> Node3D:
	var root := Node3D.new()
	root.name = "Terrain"
	parent.add_child(root)
	if not ResourceLoader.exists(MAP_GLB):
		var plane := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(200, 200)
		plane.mesh = pm
		plane.position = Vector3(64, -1.8, -64)
		root.add_child(plane)
		return root
	var scene: Node3D = (load(MAP_GLB) as PackedScene).instantiate()
	root.add_child(scene)
	var mats: Array = JSON.parse_string(FileAccess.get_file_as_string(MATERIALS_JSON))
	var by_name := {}
	for m in mats:
		by_name[m.gltf_name] = m
	_apply(scene, by_name)
	return root


## Render layer of the baked map geometry: the sun reaches it (for unit shadows), the champion fill light
## does not (its lighting is already baked into the lightmaps).
const MAP_LAYER := 2
const ENV_JSON := "res://data/map/map12_env.json"
static var _env_cache: Dictionary = {}


## data/map/map12_env.json (tools/lol/extract_map_layout.py): Map12 Base MapSunProperties + LevelProp placements.
static func env_data() -> Dictionary:
	if _env_cache.is_empty() and FileAccess.file_exists(ENV_JSON):
		var d = JSON.parse_string(FileAccess.get_file_as_string(ENV_JSON))
		if d is Dictionary:
			_env_cache = d
	return _env_cache


## Direction the sunlight travels (Godot space). League's MapSunProperties.sunDirection points *toward* the sun
## (-0.38, 0.707, 0.05 on the Abyss: high, from the Order/left side); negate it and flip z into Godot space.
static func sun_dir() -> Vector3:
	var sd = env_data().get("sun", {}).get("sunDirection")
	if sd is Array and sd.size() == 3:
		return Vector3(-float(sd[0]), -float(sd[1]), float(sd[2])).normalized()
	return Vector3(0.38, -0.707, 0.05).normalized()
static var grass_material: ShaderMaterial = null   ## shared League "Wall_of_Grass" material (brush)


static func _apply(n: Node, by_name: Dictionary) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.layers = MAP_LAYER
		for i in mi.mesh.get_surface_count():
			var src := mi.mesh.surface_get_material(i)
			var nm := src.resource_name if src != null else ""
			var info: Dictionary = by_name.get(nm, {})
			mi.set_surface_override_material(i, _make_material(info))
	for c in n.get_children():
		_apply(c, by_name)


static func _make_material(info: Dictionary) -> Material:
	var blend: bool = info.get("blend", false)
	if info.get("grass", false) and grass_material != null:
		return grass_material
	var sm := ShaderMaterial.new()
	sm.shader = BLEND_SHADER if blend else LIT_SHADER
	var dp = info.get("diffuse")
	if dp != null and dp != "":
		var t := Assets.tex("res://" + str(dp))
		if t != null:
			sm.set_shader_parameter("diffuse_tex", t)
	var lp = info.get("lightmap")
	var use_lm: bool = lp != null and lp != "" and not info.get("no_lightmap", false)
	sm.set_shader_parameter("use_lightmap", use_lm)
	if use_lm:
		var lt := Assets.tex("res://" + str(lp))
		if lt != null:
			sm.set_shader_parameter("lightmap_tex", lt)
		else:
			sm.set_shader_parameter("use_lightmap", false)
	var tint: Array = info.get("tint", [0.5, 0.5, 0.5, 1.0])
	if not use_lm:
		# unlit materials (e.g. brush) carry their brightness in the tint
		sm.set_shader_parameter("tint", Color(tint[0], tint[1], tint[2], tint[3]))
	else:
		sm.set_shader_parameter("tint", Color(tint[0], tint[1], tint[2], tint[3]))
	if blend:
		sm.set_shader_parameter("grass", info.get("grass", false))
		if info.get("grass", false):
			sm.render_priority = 1
			# [env3] the unshaded blade texture * 4.59 tint blew the ice-coral out to white (QA P1-16); League's brush is
			# a desaturated pale blue that sits below the floor highlights
			sm.set_shader_parameter("brightness", 0.5)
			grass_material = sm
	elif float(info.get("alpha_test", 0.0)) > 0.0:
		sm.set_shader_parameter("alpha_test", maxf(0.1, float(info.alpha_test)))
	return sm


static func build_environment(parent: Node3D) -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.045, 0.08)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.68, 0.82)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = false   # [env3] lead A/B: League has no global bloom; effects stay crisp
	env.glow_intensity = 0.35
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.4
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.set_glow_level(1, 0.6)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 0.9)
	env.set_glow_level(4, 0.5)
	env.fog_enabled = true
	env.fog_light_color = Color(0.32, 0.4, 0.55)
	env.fog_density = 0.0016
	env.fog_height = -6.0
	env.fog_height_density = 0.06
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.0
	env.adjustment_saturation = 1.0
	# League colour pipeline: shaders write gamma colour so effects blend in gamma space like League, the
	# compositor effect decodes after the transparent pass (src/render/gamma_decode_effect.gd). --linear = old path
	var gamma := not OS.get_cmdline_user_args().has("--linear")
	RenderingServer.global_shader_parameter_set("gamma_out", 1.0 if gamma else 0.0)
	if gamma:
		var comp := Compositor.new()
		comp.compositor_effects = [GammaDecodeEffect.new()]
		we.compositor = comp
		# colour properties are decoded to linear by the renderer; pre-encode so the buffer holds gamma values
		env.background_color = env.background_color.linear_to_srgb()
		env.fog_light_color = env.fog_light_color.linear_to_srgb()
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_color = Color(1.0, 0.95, 0.88)
	sun.light_energy = 1.1
	# League's sun (Map12 MapSunProperties.sunDirection): high and from the left, unit shadows fall to the right
	sun.transform = Transform3D(Basis.looking_at(sun_dir(), Vector3.UP), Vector3.ZERO)
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.85
	sun.shadow_blur = 2.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_max_distance = 42.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_split_1 = 0.45
	sun.directional_shadow_blend_splits = true
	parent.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.name = "Fill"
	fill.light_color = Color(0.55, 0.65, 1.0)
	fill.light_energy = 0.35
	fill.rotation_degrees = Vector3(-30, 150, 0)
	fill.light_cull_mask = 0xFFFFF & ~MAP_LAYER   # the map's lighting is baked
	parent.add_child(fill)


## Falling snow that follows the camera.
static func build_snow(parent: Node3D) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = "Snow"
	p.amount = 900
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 50, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 1, 22)
	pm.direction = Vector3(0.25, -1, 0.1)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 2.8
	pm.gravity = Vector3(0, -0.3, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 3.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.045, 0.045)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.92, 0.95, 1.0, 0.45)
	mat.albedo_texture = Vfx.soft_circle_texture()
	quad.material = mat
	p.draw_pass_1 = quad
	parent.add_child(p)
	if OS.get_cmdline_user_args().has("--nosnowstandin"):
		p.emitting = false   # debug: judge League's own snow systems (MapAmbient) alone
		p.visible = false
	return p


## Lane waypoints from Order base to Chaos base (world space).
static func lane_points(layout: Dictionary) -> Array:
	var pts := []
	for r in layout.get("nav", []):
		var nm := str(r.name)
		var idx := int(nm.replace("__NAV_C0", "").replace("__NAV_C", ""))
		pts.append([idx, lol(r.pos)])
	pts.sort_custom(func(a, b): return a[0] < b[0])
	return pts.map(func(x): return x[1])


## Structure records with team, tier and world position.
static func structures(layout: Dictionary) -> Array:
	var out := []
	for r in layout.get("structures", []):
		var strs: Array = r.strings
		var rec := ""
		for s in strs:
			if str(s).find("CharacterRecords") >= 0:
				rec = str(s)
		var pos := lol(r.pos)
		var team := G.Team.ORDER if float(r.pos[0]) + float(r.pos[2]) < 13000.0 else G.Team.CHAOS
		var kind := ""
		if rec.find("Shrine") >= 0:
			kind = "fountain"
		elif rec.find("HA_Outer") >= 0:
			kind = "outer"
		elif rec.find("HA_Inhibitor") >= 0:
			kind = "inhib_turret"
		elif rec.find("Turret/CharacterRecords/HA_Nexus") >= 0:
			kind = "nexus_turret"
		elif rec.find("Inhibitor/CharacterRecords") >= 0:
			kind = "inhibitor"
		elif rec.find("Nexus/CharacterRecords") >= 0:
			kind = "nexus"
		var fwd: Array = r.get("fwd", [0, 0, 1])
		out.append({"kind": kind, "team": team, "pos": pos, "yaw": atan2(-float(fwd[0]), float(fwd[2]))})
	return out


static func spawn_points(layout: Dictionary) -> Array:
	var sp := [Vector3.ZERO, Vector3.ZERO]
	for r in layout.get("spawns", []):
		if str(r.name).find("T1") >= 0:
			sp[0] = lol(r.pos)
		else:
			sp[1] = lol(r.pos)
	return sp


static func relic_points(layout: Dictionary) -> Array:
	var out := []
	var seen := {}
	for r in layout.get("relics", []):
		var has_rec := false
		for s in r.strings:
			if str(s).find("HA_AP_HealthRelic/CharacterRecords") >= 0:
				has_rec = true
		if not has_rec:
			continue
		var key := "%d_%d" % [int(r.pos[0]), int(r.pos[2])]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(lol(r.pos))
	return out


static func props(layout: Dictionary) -> Array:
	var out := []
	for r in layout.get("props", []):
		var rec := ""
		for s in r.strings:
			if str(s).find("CharacterRecords") >= 0:
				rec = str(s)
		if rec == "":
			continue
		var name := rec.split("/")[1]
		var fwd: Array = r.get("fwd", [0, 0, 1])
		out.append({"name": name, "pos": lol(r.pos), "yaw": atan2(-float(fwd[0]), float(fwd[2]))})
	return out
