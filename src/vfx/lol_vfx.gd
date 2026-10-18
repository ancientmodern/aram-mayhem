class_name LolVfx
extends Node3D
## League particle system instance, built from data/vfx/<champion>.json (tools/lol/extract_vfx.py).
## Each League emitter becomes a GPUParticles3D (quads / oriented quads / meshes) or a LolTrail ribbon.
## Static API:
##   LolVfx.has(name)                  -> bool
##   LolVfx.spawn(m, name, pos, opts)  -> LolVfx node (world space) or null
##   LolVfx.attach(parent, name, opts) -> LolVfx node following `parent`
## opts: dir (Vector3 facing), scale (float), loop (bool: keep emitting until stop()), height (float)

const S := 0.01          ## League units -> meters
const QUAD_SCALE := 2.0  ## League quad size is a half-extent

static var _db := {}             ## system name -> definition
static var _loaded := {}         ## file -> true
static var _shaders := {}
static var _mats := {}
static var _pmats := {}
static var _meshes := {}
static var _ramps := {}
static var _resolve := {}

var def := {}
var _t := 0.0
var _dur := 2.0
var _loop := false
var _stopped := false
var _free_at := -1.0
var _timers: Array = []          ## [time, callable]
var follow: Node3D = null
var follow_offset := Vector3.ZERO


# ===================================================================== database
static func load_set(file: String) -> void:
	if _loaded.has(file):
		return
	_loaded[file] = true
	var path := "res://data/vfx/%s.json" % file.to_lower()
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		for k in d:
			_db[k] = d[k]


static func has(name: String) -> bool:
	return _db.has(name)


static func clear_cache() -> void:
	_db.clear()
	_loaded.clear()
	_mats.clear()
	_pmats.clear()
	_resolve.clear()
	_meshes.clear()
	_ramps.clear()


## Unparented instance (e.g. a missile visual); emitters are built when it enters the tree.
static func make(name: String, opts: Dictionary = {}) -> LolVfx:
	if not _db.has(name):
		return null
	var n := LolVfx.new()
	n.def = _db[name]
	n.name = name
	n._opts = opts
	return n


static func spawn(m, name: String, pos: Vector3, opts: Dictionary = {}) -> LolVfx:
	if m == null:
		return null
	var n := make(name, opts)
	if n == null:
		return null
	m.fx_root.add_child(n)
	n.global_position = pos + Vector3(0, float(opts.get("height", 0.0)), 0)
	n._apply_dir()
	return n


static func attach(parent: Node3D, name: String, opts: Dictionary = {}) -> LolVfx:
	if parent == null:
		return null
	var n := make(name, opts)
	if n == null:
		return null
	parent.add_child(n)
	n.position = Vector3(0, float(opts.get("height", 0.0)), 0)
	n._apply_dir()
	return n


## Champion effect by key ("BA_mis", "BA_tar", "Q_cas", "Q_mis", "Q_tar" ...): the kit's vfx_map() override,
## else League's naming convention "<Alias>_Base_<key>" (case-insensitive, a few common variants).
static func champ_fx(c, key: String) -> String:
	if c == null or not ("alias" in c):
		return ""
	var alias: String = c.alias
	load_set(alias)
	if c.kit != null and c.kit.has_method("vfx_map"):
		var mp: Dictionary = c.kit.vfx_map()
		if mp.has(key):
			return mp[key]
	var cache_key := alias + "|" + key
	if _resolve.has(cache_key):
		return _resolve[cache_key]
	var found := ""
	var variants := [key]
	if key.ends_with("_tar"):
		variants += [key.replace("_tar", "_hit"), key.replace("_tar", "_Tar"), key.replace("_tar", "_hit_tar")]
	elif key.ends_with("_cas"):
		variants += [key.replace("_cas", "_Cas"), key.replace("_cas", "_cast")]
	elif key.ends_with("_mis"):
		variants += [key.replace("_mis", "_Mis"), key.replace("_mis", "_Missile")]
	for v in variants:
		var want := ("%s_Base_%s" % [alias, v]).to_lower()
		for nm in _db:
			if String(nm).to_lower() == want:
				found = nm
				break
		if found != "":
			break
	_resolve[cache_key] = found
	return found


# ===================================================================== gameplay hooks
static var _hit_rl := {}


static func _slot_key(ab) -> String:
	if ab == null or not ("slot" in ab):
		return ""
	var s: int = ab.slot
	return "QWER"[s] if s >= 0 and s <= 3 else ""


static func _team_name(u) -> String:
	return "Order" if u.team == G.Team.ORDER else "Chaos"


## Missile visual for minion / turret basic attacks (shared League set) or null.
static func unit_attack_visual(src, tgt) -> LolVfx:
	load_set("shared")
	var nm := ""
	if src.kind == G.Kind.MINION:
		var tn := _team_name(src)
		match int(src.minion_type):
			Minion.Type.CASTER: nm = "SRU_%sMinionRanged_Base_BA_Mis" % tn
			Minion.Type.SIEGE: nm = "SRU_%sMinionSiege_Base_SRU_%s_CanM_BA1" % [tn, tn]
	elif src.kind == G.Kind.TURRET:
		if tgt != null and is_instance_valid(tgt) and tgt.kind == G.Kind.CHAMPION:
			nm = "Turret_Skin24_BA_Champ_%02d" % clampi(int(src.ramp) + 1, 1, 4)
		else:
			nm = "Turret_Skin24_BA"
	return make(nm, {"loop": true}) if nm != "" else null


## Basic attack impact on the target.
static func on_attack_hit(src, t, crit: bool) -> void:
	if src == null or t == null or not is_instance_valid(t):
		return
	if not (src is Champion):
		var nm2 := ""
		if src.kind == G.Kind.MINION:
			var tn := _team_name(src)
			match int(src.minion_type):
				Minion.Type.CASTER: nm2 = "SRU_%sMinionRanged_Base_BA_Tar" % tn
				Minion.Type.SIEGE: nm2 = "SRU_%sMinionSiege_Base_SRU_%s_CanM_Tar" % [tn, tn]
		elif src.kind == G.Kind.TURRET:
			if t.kind == G.Kind.CHAMPION:
				var shot: int = clampi(int(src.ramp), 1, 4)
				nm2 = "Turret_Skin24_BA_Tar_Champ" if shot <= 1 else "Turret_Skin24_BA_Tar_Champ_%02d" % shot
			else:
				nm2 = "Turret_Skin24_BA_Tar"
		if nm2 != "" and src.match_ref != null:
			load_set("shared")
			spawn(src.match_ref, nm2, t.global_position + Vector3(0, t.height * 0.5, 0))
		return
	if not (src is Champion):
		return
	var nm := champ_fx(src, "BA_crit_tar") if crit else ""
	if nm == "":
		nm = champ_fx(src, "BA_tar")
	if nm != "":
		spawn(src.match_ref, nm, t.global_position + Vector3(0, t.height * 0.5, 0), {"dir": G.flat_dir(src.global_position, t.global_position)})


## Ability cast flash on the caster.
static func on_cast(ab, t: Dictionary) -> void:
	var o = ab.owner
	var k := _slot_key(ab)
	if k == "" or not (o is Champion):
		return
	var nm := champ_fx(o, k + "_cas")
	if nm != "":
		var dir: Vector3 = t.get("dir", o.facing)
		attach(o, nm, {"dir": dir})


## Spell damage landing on a target (rate limited per ability and target).
static func on_spell_hit(src, ab, t) -> void:
	var k := _slot_key(ab)
	if k == "" or not (src is Champion) or t == null or not is_instance_valid(t):
		return
	var key := "%d|%s|%d" % [src.get_instance_id(), k, t.get_instance_id()]
	var now := Time.get_ticks_msec()
	if now - int(_hit_rl.get(key, -10000)) < 300:
		return
	_hit_rl[key] = now
	if _hit_rl.size() > 512:
		_hit_rl.clear()
	var nm := champ_fx(src, k + "_tar")
	if nm != "":
		spawn(src.match_ref, nm, t.global_position + Vector3(0, t.height * 0.5, 0), {"dir": G.flat_dir(src.global_position, t.global_position)})


## Spell missile visual (replaces the kit's placeholder visual) or null.
static func missile_visual(mi) -> LolVfx:
	if mi == null or mi.ability == null or mi.custom.get("keep_visual", false):
		return null
	var o = mi.ability.owner
	var k := _slot_key(mi.ability)
	if k == "" or not (o is Champion):
		return null
	var nm := champ_fx(o, k + "_mis")
	return make(nm, {"loop": true}) if nm != "" else null


# ===================================================================== instance
var _opts := {}


func _ready() -> void:
	_setup(_opts)


func _apply_dir() -> void:
	var dir: Vector3 = _opts.get("dir", Vector3.ZERO)
	if dir.length_squared() > 0.001:
		var d := Vector3(dir.x, 0, dir.z).normalized()
		global_basis = Basis.looking_at(d, Vector3.UP) * Basis.from_scale(scale)


func _setup(opts: Dictionary) -> void:
	_dur = float(def.get("dur", 2.0))
	_loop = bool(opts.get("loop", false))
	var sc: float = float(opts.get("scale", 1.0))
	if absf(sc - 1.0) > 0.001:
		scale = Vector3.ONE * sc
	for e in def.get("emitters", []):
		_build_emitter(e)
	if not _loop:
		_free_at = _dur + 0.2


func _process(dt: float) -> void:
	_t += dt
	var i := 0
	while i < _timers.size():
		if _t >= _timers[i][0]:
			var fn: Callable = _timers[i][1]
			_timers.remove_at(i)
			fn.call()
		else:
			i += 1
	if follow != null:
		if is_instance_valid(follow):
			global_position = follow.global_position + follow_offset
		else:
			follow = null
			stop()
	if _free_at >= 0.0 and _t >= _free_at:
		queue_free()


func _after(t: float, fn: Callable) -> void:
	if t <= 0.0:
		fn.call()
	else:
		_timers.append([_t + t, fn])


## Stop emitting; the node frees itself once live particles have faded.
func stop() -> void:
	if _stopped:
		return
	_stopped = true
	var longest := 0.0
	for c in get_children():
		if c is GPUParticles3D:
			c.emitting = false
			if c.has_meta("infinite"):
				c.visible = false   # persistent particles end with their emitter
			else:
				longest = maxf(longest, c.lifetime)
		elif c is LolTrail:
			c.emitting = false
			longest = maxf(longest, c.life)
	_free_at = _t + longest + 0.1


## Missile visual protocol (Missile.finish calls this): keep the effect where it ended and fade out.
func detach_and_fade() -> void:
	var gp := global_transform
	var root = G.match.fx_root if G.match != null else null
	if root != null and get_parent() != root:
		get_parent().remove_child(self)
		root.add_child(self)
		global_transform = gp
	stop()


# ===================================================================== emitter builders
func _build_emitter(e: Dictionary) -> void:
	var prim: String = e.get("prim", "quad")
	if prim == "amesh" or e.get("tex") == null or e.get("distort", false):
		return
	if prim == "ctrail" or prim == "atrail":
		_build_trail(e)
		return
	var p := GPUParticles3D.new()
	var single: bool = e.get("single", false)
	var plife: Array = e.get("plife", [1.0, 1.0])
	var infinite: bool = float(plife[1]) < 0.0
	var life_max: float = 3600.0 if infinite else maxf(float(plife[1]), 0.05)
	p.lifetime = life_max
	if infinite:
		p.set_meta("infinite", true)
		single = true
	var rate: float = float(e.get("rate", 1.0))
	var elife: float = float(e.get("life", -1.0))
	if single:
		p.amount = 1
		p.one_shot = true
		p.explosiveness = 1.0
	else:
		p.amount = clampi(int(ceil(rate * life_max)) + 1, 1, 400)
		# a short-lived emitter with a high rate is really a burst
		if elife > 0.0 and elife < 0.12:
			p.one_shot = true
			p.explosiveness = 1.0
			p.amount = clampi(int(ceil(rate * maxf(elife, 0.05))) + 1, 1, 400)
	p.local_coords = bool(e.get("local", false))
	p.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	p.position = _v3(e.get("pos", [0, 0, 0]))
	p.visibility_aabb = AABB(Vector3(-15, -15, -15), Vector3(30, 30, 30))
	p.process_material = _process_material(e)
	p.draw_pass_1 = _mesh_for(e)
	p.material_override = _material(e)
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	var delay: float = float(e.get("delay", 0.0))
	_after(delay, func():
		if is_instance_valid(p) and not _stopped:
			p.restart()
			p.emitting = true)
	if not single and elife > 0.0 and not _loop and not p.one_shot:
		_after(delay + elife, func():
			if is_instance_valid(p):
				p.emitting = false)


func _build_trail(e: Dictionary) -> void:
	var t := LolTrail.new()
	var plife: Array = e.get("plife", [0.3, 0.3])
	t.life = maxf(float(plife[1]), 0.05)
	var bs: Array = e.get("bscale", [10, 0, 0])
	t.width = absf(float(bs[0])) * S * QUAD_SCALE
	t.color = _col(e.get("bcolor", [1, 1, 1, 1]))
	t.color_curve = e.get("color")
	t.blend = int(e.get("blend", 4))
	t.texture = _tex(e.get("tex"))
	t.offset = _v3(e.get("pos", [0, 0, 0]))
	add_child(t)
	var elife: float = float(e.get("life", -1.0))
	if elife > 0.0 and not _loop:
		_after(float(e.get("delay", 0.0)) + elife, func():
			if is_instance_valid(t):
				t.emitting = false)


static func _v3(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


static func _col(a) -> Color:
	if a is Array and a.size() >= 4:
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	return Color.WHITE


static func _tex(path) -> Texture2D:
	if path == null or not (path is String) or not ResourceLoader.exists(path):
		return null
	return Assets.tex(path)


# ----------------------------------------------------------------- meshes
static func _mesh_for(e: Dictionary) -> Mesh:
	var prim: String = e.get("prim", "quad")
	var bs: Array = e.get("bscale", [1, 1, 1])
	var bx := float(bs[0])
	var by := float(bs[1]) if bs.size() > 1 else bx
	var bz := float(bs[2]) if bs.size() > 2 else bx
	var rot: Array = e.get("brot", [0, 0, 0])
	var key := "%s|%s|%s|%s|%s|%s" % [prim, e.get("mesh", ""), str(bs), str(rot), e.get("ground", false), e.get("uniform", false)]
	if _meshes.has(key):
		return _meshes[key]
	var mesh: Mesh
	if prim == "mesh":
		var src = load(e.mesh) if ResourceLoader.exists(e.mesh) else null
		if src is Mesh:
			var sx := absf(bx) if bx != 0.0 else 1.0
			var sy := absf(by) if by != 0.0 else sx
			var sz := absf(bz) if bz != 0.0 else sx
			if e.get("uniform", false):
				sy = sx
				sz = sx
			var basis := Basis.from_euler(Vector3(deg_to_rad(float(rot[0])), deg_to_rad(float(rot[1])), deg_to_rad(-float(rot[2])))).scaled(Vector3(sx, sy, sz))
			mesh = _transformed(src, Transform3D(basis, Vector3.ZERO))
		else:
			mesh = QuadMesh.new()
	else:
		var q := QuadMesh.new()
		var w := absf(bx) * S * QUAD_SCALE
		var h := w
		if prim == "aquad" and not e.get("uniform", false) and by > 0.01:
			h = absf(by) * S * QUAD_SCALE
		q.size = Vector2(maxf(w, 0.01), maxf(h, 0.01))
		if e.get("ground", false):
			q.orientation = PlaneMesh.FACE_Y
		mesh = q
		if prim == "aquad" and not e.get("ground", false) and (absf(float(rot[0])) > 0.1 or absf(float(rot[1])) > 0.1):
			var b := Basis.from_euler(Vector3(deg_to_rad(float(rot[0])), deg_to_rad(float(rot[1])), 0.0))
			mesh = _transformed(q, Transform3D(b, Vector3.ZERO))
	_meshes[key] = mesh
	return mesh


static func _transformed(src: Mesh, xf: Transform3D) -> Mesh:
	var st := SurfaceTool.new()
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		st.clear()
		st.create_from(src, s)
		var arr := st.commit_to_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i] = xf * verts[i]
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = null
		arr[Mesh.ARRAY_TANGENT] = null
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return out


# ----------------------------------------------------------------- materials
static func _shader(blend: int) -> Shader:
	# League blendMode (from texture statistics over all champions): 0 (default) / 2 / 4 = additive,
	# 1 = alpha blend, 3 = multiply, 5 = premultiplied alpha
	var mode := "blend_add"
	match blend:
		1: mode = "blend_mix"
		3: mode = "blend_mul"
		5: mode = "blend_premul_alpha"
	if _shaders.has(mode):
		return _shaders[mode]
	var code := FileAccess.get_file_as_string("res://src/vfx/lol_particle.gdshader.txt").replace("__BLEND__", mode)
	var sh := Shader.new()
	sh.code = code
	_shaders[mode] = sh
	return sh


static func _material(e: Dictionary) -> ShaderMaterial:
	var prim: String = e.get("prim", "quad")
	var bb := 1
	if prim == "mesh" or prim == "aquad":
		bb = 0
	if e.get("ground", false):
		bb = 3
	if e.get("dir", false) and prim in ["quad", "ray"]:
		bb = 2
	var div: Array = e.get("texdiv", [1, 1])
	var frames := int(e.get("frames", 0))
	if frames <= 0:
		frames = int(div[0]) * int(div[1])
	var key := "%s|%d|%d|%s|%d|%d|%s" % [e.get("tex"), int(e.get("blend", 1)), bb, str(div), frames, int(e.get("alpha_ref", 0)), str(e.get("uvscroll")), ]
	key += "|%d" % int(e.get("pass", 0))
	if _mats.has(key):
		return _mats[key]
	var mat := ShaderMaterial.new()
	mat.shader = _shader(int(e.get("blend", 1)))
	mat.set_shader_parameter("tex", _tex(e.get("tex")))
	mat.set_shader_parameter("billboard", bb)
	mat.set_shader_parameter("texdiv", Vector2(maxf(1, float(div[0])), maxf(1, float(div[1]))))
	mat.set_shader_parameter("total_frames", float(frames))
	mat.set_shader_parameter("alpha_ref", float(e.get("alpha_ref", 0)) / 255.0)
	var us = e.get("uvscroll")
	if us is Array and us.size() >= 2:
		mat.set_shader_parameter("uv_scroll", Vector2(float(us[0]), float(us[1])))
	mat.render_priority = clampi(int(e.get("pass", 0)) / 2, -60, 60)
	_mats[key] = mat
	return mat


static func _process_material(e: Dictionary) -> ParticleProcessMaterial:
	var key := JSON.stringify(e)
	if _pmats.has(key):
		return _pmats[key]
	var pm := ParticleProcessMaterial.new()
	pm.gravity = _v3(e.get("accel", [0, 0, 0]))
	var plife: Array = e.get("plife", [1.0, 1.0])
	pm.lifetime_randomness = clampf(1.0 - float(plife[0]) / maxf(float(plife[1]), 0.001), 0.0, 1.0)
	# emission shape
	var sh = e.get("shape")
	if sh is Dictionary:
		match str(sh.get("type", "")):
			"sphere":
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
				pm.emission_sphere_radius = maxf(float(sh.radius), 0.001)
			"box":
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
				var sz: Array = sh.get("size", [0, 0, 0])
				pm.emission_box_extents = Vector3(float(sz[0]), float(sz[1]), float(sz[2])) * 0.5
			"cyl":
				pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
				pm.emission_ring_radius = maxf(float(sh.radius), 0.001)
				pm.emission_ring_inner_radius = 0.0
				pm.emission_ring_height = float(sh.get("height", 0.0))
				pm.emission_ring_axis = Vector3.UP
			"offset":
				pm.emission_shape_offset = _v3(sh.get("offset", [0, 0, 0]))
	# velocity
	var bv := _v3(e.get("bvel", [0, 0, 0]))
	var speed := bv.length()
	if speed > 0.0001:
		pm.direction = bv / speed
		var r = e.get("bvel_rand")
		var lo := 1.0
		var hi := 1.0
		var spread := 0.0
		if r is Array:
			var a := Vector3(float(r[0][0]), float(r[0][1]), float(r[0][2]))
			var b := Vector3(float(r[1][0]), float(r[1][1]), float(r[1][2]))
			var va := bv * a
			var vb := bv * b
			lo = minf(va.length(), vb.length()) / speed
			hi = maxf(va.length(), vb.length()) / speed
			if va.length() > 0.0001 and vb.length() > 0.0001:
				spread = rad_to_deg(va.angle_to(vb)) * 0.5
			if a.x < 0.0 or a.y < 0.0 or a.z < 0.0:
				spread = maxf(spread, 90.0)
		pm.spread = clampf(spread, 0.0, 180.0)
		pm.initial_velocity_min = speed * lo
		pm.initial_velocity_max = speed * hi
	else:
		pm.initial_velocity_min = 0.0
		pm.initial_velocity_max = 0.0
		pm.spread = 0.0
	var drag: Array = e.get("drag", [0, 0, 0])
	if drag is Array and drag.size() >= 3:
		var dm := maxf(absf(float(drag[0])), maxf(absf(float(drag[1])), absf(float(drag[2]))))
		if dm > 0.0:
			pm.damping_min = dm * maxf(speed, 0.5)
			pm.damping_max = pm.damping_min
	# rotation (camera quads spin around the view axis, meshes / ground quads around Y)
	var rot: Array = e.get("brot", [0, 0, 0])
	var rv: Array = e.get("rotvel", [0, 0, 0])
	var prim: String = e.get("prim", "quad")
	var spin_axis_y: bool = prim == "mesh" or e.get("ground", false)
	var ang := float(rot[2]) if not spin_axis_y else float(rot[1]) if prim == "mesh" else float(rot[2])
	var rr = e.get("brot_rand")
	var amin := ang
	var amax := ang
	if rr is Array:
		var k := 2 if not spin_axis_y or prim != "mesh" else 1
		amin = ang * float(rr[0][k]) if absf(ang) > 0.01 else float(rr[0][k])
		amax = ang * float(rr[1][k]) if absf(ang) > 0.01 else float(rr[1][k])
		if absf(ang) < 0.01 and absf(amin) <= 1.01 and absf(amax) <= 1.01:
			amin = 0.0
			amax = 360.0
	if prim != "mesh":
		pm.angle_min = -minf(amin, amax)
		pm.angle_max = -maxf(amin, amax)
	var spin := float(rv[1]) if spin_axis_y and prim == "mesh" else float(rv[2])
	var rvr = e.get("rotvel_rand")
	var smin := spin
	var smax := spin
	if rvr is Array:
		var k2 := 1 if spin_axis_y and prim == "mesh" else 2
		smin = spin * float(rvr[0][k2])
		smax = spin * float(rvr[1][k2])
	pm.angular_velocity_min = -maxf(smin, smax)
	pm.angular_velocity_max = -minf(smin, smax)
	if spin_axis_y:
		pm.particle_flag_rotate_y = true
	if e.get("dir", false):
		pm.particle_flag_align_y = true
	# scale
	var br = e.get("bscale_rand")
	if br is Array:
		pm.scale_min = float(br[0][0])
		pm.scale_max = float(br[1][0])
	var sc = e.get("scale")
	if sc is Dictionary and sc.has("t"):
		pm.scale_curve = _scale_curve(sc)
	# color: birth color x over-life curve x lookup texture
	var bc := _col(e.get("bcolor", [1, 1, 1, 1]))
	pm.color = bc
	var cr = e.get("bcolor_rand")
	if cr is Array:
		var g := Gradient.new()
		g.set_color(0, Color(float(cr[0][0]), float(cr[0][1]), float(cr[0][2]), float(cr[0][3])))
		g.set_color(1, Color(float(cr[1][0]), float(cr[1][1]), float(cr[1][2]), float(cr[1][3])))
		var gt := GradientTexture1D.new()
		gt.gradient = g
		pm.color_initial_ramp = gt
	var ramp := _color_ramp(e)
	if ramp != null:
		pm.color_ramp = ramp
	# flipbook
	var div: Array = e.get("texdiv", [1, 1])
	var frames := int(e.get("frames", 0))
	if frames <= 0:
		frames = int(div[0]) * int(div[1])
	if frames > 1:
		var fps := float(e.get("fps", 0.0))
		var spd := 1.0 if fps <= 0.0 else fps * float(plife[1]) / float(frames)
		pm.anim_speed_min = spd
		pm.anim_speed_max = spd
		if e.get("rand_frame", false):
			pm.anim_offset_max = 1.0
		elif int(e.get("start_frame", 0)) > 0:
			pm.anim_offset_min = float(e.start_frame) / float(frames)
			pm.anim_offset_max = pm.anim_offset_min
	_pmats[key] = pm
	return pm


static func _scale_curve(sc: Dictionary) -> Texture2D:
	var times: Array = sc.t
	var vals: Array = sc.v
	var c := Curve.new()
	c.max_value = 64.0
	for i in times.size():
		var v = vals[i]
		var s := float(v[0]) if v is Array else float(v)
		c.add_point(Vector2(clampf(float(times[i]), 0.0, 1.0), clampf(s, 0.0, 64.0)))
	var ct := CurveTexture.new()
	ct.curve = c
	return ct


static func _color_ramp(e: Dictionary) -> GradientTexture1D:
	var cur = e.get("color")
	var ctex = e.get("ctex")
	var ctype: Array = e.get("ctype", [0, 0])
	if cur == null and ctex == null:
		return null
	var key := "%s|%s|%s" % [JSON.stringify(cur), ctex, str(ctype)]
	if _ramps.has(key):
		return _ramps[key]
	var g := Gradient.new()
	var img: Image = null
	if ctex != null:
		var t := _tex(ctex)
		if t != null:
			img = t.get_image()
			if img != null and img.is_compressed():
				img.decompress()
	var n := 16
	var cols := PackedColorArray()
	var offs := PackedFloat32Array()
	for i in n:
		var u := float(i) / float(n - 1)
		var col := Color.WHITE
		if cur is Dictionary:
			col = _sample_color_curve(cur, u)
		if img != null:
			var w := img.get_width()
			var h := img.get_height()
			var tc := Color.WHITE
			if int(ctype[1]) == 3:
				tc = img.get_pixel(w / 2, clampi(int(u * (h - 1)), 0, h - 1))
			elif int(ctype[0]) == 3:
				tc = img.get_pixel(clampi(int(u * (w - 1)), 0, w - 1), h / 2)
			else:
				tc = img.get_pixel(w / 2, h / 2)
			col *= tc
		cols.append(col)
		offs.append(u)
	g.offsets = offs
	g.colors = cols
	var gt := GradientTexture1D.new()
	gt.gradient = g
	gt.width = 64
	_ramps[key] = gt
	return gt


static func _sample_color_curve(cur: Dictionary, u: float) -> Color:
	var times: Array = cur.t
	var vals: Array = cur.v
	if times.is_empty():
		return Color.WHITE
	if u <= float(times[0]):
		return _col(vals[0])
	for i in range(1, times.size()):
		if u <= float(times[i]):
			var t0 := float(times[i - 1])
			var t1 := float(times[i])
			var k := (u - t0) / maxf(t1 - t0, 0.0001)
			return _col(vals[i - 1]).lerp(_col(vals[i]), k)
	return _col(vals[vals.size() - 1])
