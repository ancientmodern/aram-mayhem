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
const MAX_ONESHOT := 6.0 ## seconds a non-looping effect may live
static var ROT_ORDER := 4   ## euler order yzx: verified on Yasuo W wall + Q streak geometry
const MAX_FADE := 2.5    ## seconds particles may keep fading after stop()

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
var _face_unit = null            ## attached to a Unit: keep facing its direction
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
	if parent is Unit and opts.get("face", true) and not opts.has("dir"):
		n._face_unit = parent
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
			spawn(src.match_ref, nm2, t.global_position, {"center": t.height * 0.5})
		return
	if not (src is Champion):
		return
	var nm := champ_fx(src, "BA_crit_tar") if crit else ""
	if nm == "":
		nm = champ_fx(src, "BA_tar")
	if nm != "":
		spawn(src.match_ref, nm, t.global_position, {"dir": G.flat_dir(src.global_position, t.global_position), "center": t.height * 0.5})


## Ability cast flash on the caster.
static func on_cast(ab, t: Dictionary) -> void:
	var o = ab.owner
	var k := _slot_key(ab)
	if k == "" or not (o is Champion):
		return
	var nm := champ_fx(o, k + "_cas")
	if nm != "":
		var dir: Vector3 = t.get("dir", o.facing)
		attach(o, nm, {"dir": dir, "center": o.height * 0.35})


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
		spawn(src.match_ref, nm, t.global_position, {"dir": G.flat_dir(src.global_position, t.global_position), "center": t.height * 0.5})


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
		# League durations include long, fully faded tails; cap so finished effects leave the tree
		_free_at = minf(_dur, float(opts.get("max_life", MAX_ONESHOT))) + 0.2


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
	if _face_unit != null:
		if is_instance_valid(_face_unit):
			var f: Vector3 = _face_unit.facing
			if f.length_squared() > 0.001:
				global_basis = Basis.looking_at(Vector3(f.x, 0, f.z).normalized(), Vector3.UP) * Basis.from_scale(scale)
		else:
			_face_unit = null
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
	_free_at = _t + minf(longest, MAX_FADE) + 0.1


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
	if prim == "beam":
		_build_beam(e)
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
	if not e.get("ground", false):
		p.position.y += float(_opts.get("center", 0.0))
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


func _build_beam(e: Dictionary) -> void:
	var length: float = float(_opts.get("length", 0.0))
	if length <= 0.01:
		return
	var b := LolBeam.new()
	var bs: Array = e.get("bscale", [10, 0, 0])
	b.width = absf(float(bs[0])) * S * QUAD_SCALE
	b.length = length
	b.color = _col(e.get("bcolor", [1, 1, 1, 1]))
	b.color_curve = e.get("color")
	var plife: Array = e.get("plife", [1.0, 1.0])
	var elife: float = float(e.get("life", -1.0))
	b.life = float(plife[1]) if float(plife[1]) > 0.0 else (elife if elife > 0.0 else 1.0)
	b.blend = int(e.get("blend", 0))
	b.texture = _tex(e.get("tex"))
	b.position = _v3(e.get("pos", [0, 0, 0]))
	b.visible = false
	add_child(b)
	_after(float(e.get("delay", 0.0)), func():
		if is_instance_valid(b) and not _stopped:
			b.visible = true
			b.start())


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


# ----------------------------------------------------------------- orientation / meshes
## 0 camera billboard, 1 free quad, 2 ground decal, 3 mesh, 4 velocity aligned billboard
static func _orient(e: Dictionary) -> int:
	var prim: String = e.get("prim", "quad")
	if prim == "mesh":
		return 3
	if e.get("ground", false):
		return 2
	if prim == "aquad":
		return 1
	if e.get("dir", false):
		return 4
	return 0


static func _mesh_for(e: Dictionary) -> Mesh:
	var o := _orient(e)
	var key := "m|%d|%s" % [o, e.get("mesh", "")]
	if _meshes.has(key):
		return _meshes[key]
	var mesh: Mesh
	if o == 3:
		var src = load(e.mesh) if ResourceLoader.exists(e.mesh) else null
		mesh = src if src is Mesh else QuadMesh.new()
	else:
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		if o == 2:
			q.orientation = PlaneMesh.FACE_Y
		mesh = q
	_meshes[key] = mesh
	return mesh


# ----------------------------------------------------------------- curve textures
## rows: Array of Color (float RGBA) sampled uniformly over particle life
static func _float_tex(rows: Array) -> ImageTexture:
	var n := rows.size()
	var img := Image.create(maxi(n, 1), 1, false, Image.FORMAT_RGBAF)
	for i in n:
		img.set_pixel(i, 0, rows[i])
	return ImageTexture.create_from_image(img)


static func _curve_vec(cur: Dictionary, u: float):
	var times: Array = cur.t
	var vals: Array = cur.v
	if u <= float(times[0]):
		return vals[0]
	for i in range(1, times.size()):
		if u <= float(times[i]):
			var k := (u - float(times[i - 1])) / maxf(float(times[i]) - float(times[i - 1]), 0.0001)
			var a = vals[i - 1]
			var b = vals[i]
			if a is Array:
				var out := []
				for j in a.size():
					out.append(lerpf(float(a[j]), float(b[j]), k))
				return out
			return lerpf(float(a), float(b), k)
	return vals[vals.size() - 1]


static func _scale_tex(e: Dictionary) -> ImageTexture:
	var sc = e.get("scale")
	if not (sc is Dictionary) or not sc.has("t"):
		return null
	var rows := []
	for i in 32:
		var v = _curve_vec(sc, i / 31.0)
		if v is Array:
			var vx := float(v[0])
			var vy := float(v[1]) if v.size() > 1 else vx
			var vz := float(v[2]) if v.size() > 2 else vx
			rows.append(Color(vx, vy, vz, 1.0))
		else:
			rows.append(Color(float(v), float(v), float(v), 1.0))
	return _float_tex(rows)


static func _color_tex(e: Dictionary) -> ImageTexture:
	var cur = e.get("color")
	var ctex = e.get("ctex")
	if cur == null and ctex == null:
		return null
	var ctype: Array = e.get("ctype", [0, 0])
	var img: Image = null
	if ctex != null:
		var t := _tex(ctex)
		if t != null:
			img = t.get_image()
			if img != null and img.is_compressed():
				img.decompress()
	var rows := []
	for i in 32:
		var u := i / 31.0
		var col := Color.WHITE
		if cur is Dictionary:
			col = _sample_color_curve(cur, u)
		if img != null:
			var w := img.get_width()
			var h := img.get_height()
			# lookup texture: X follows particle life (type 0/3), Y follows life only for type 3
			var px := w / 2
			var py := h / 2
			if int(ctype[1]) == 3 and int(ctype[0]) != 3:
				py = clampi(int(u * (h - 1)), 0, h - 1)
			else:
				px = clampi(int(u * (w - 1)), 0, w - 1)
				if int(ctype[1]) == 3:
					py = clampi(int(u * (h - 1)), 0, h - 1)
			col *= img.get_pixel(px, py)
		rows.append(col)
	return _float_tex(rows)


static func _uv_tex(e: Dictionary) -> ImageTexture:
	var a = e.get("uvint")
	var b = e.get("uv2int")
	if a == null and b == null:
		return null
	var rows := []
	for i in 16:
		var ra: Array = a[i] if a is Array and i < a.size() else [0.0, 0.0]
		var rb: Array = b[i] if b is Array and i < b.size() else [0.0, 0.0]
		rows.append(Color(float(ra[0]), float(ra[1]), float(rb[0]), float(rb[1])))
	return _float_tex(rows)


static func _ero_tex(e: Dictionary) -> ImageTexture:
	var c = e.get("ero_curve")
	if not (c is Array):
		return null
	var rows := []
	for v in c:
		rows.append(Color(float(v), 0, 0, 1))
	return _float_tex(rows)


# ----------------------------------------------------------------- materials
static func _shader(blend: int) -> Shader:
	# League blendMode (from texture statistics over all champions): 0 (default) / 2 / 4 = additive,
	# 1 = alpha blend, 3 = multiply, 5 = premultiplied alpha
	var mode := "blend_add"
	match blend:
		1, 3: mode = "blend_mix"
		5: mode = "blend_premul_alpha"
	if _shaders.has(mode):
		return _shaders[mode]
	var hint := "" if mode == "blend_add" else "source_color,"
	var code := FileAccess.get_file_as_string("res://src/vfx/lol_particle.gdshader.txt").replace("__BLEND__", mode).replace("__TEXHINT__", hint)
	var sh := Shader.new()
	sh.code = code
	_shaders[mode] = sh
	return sh


static func _v2(a, d: Vector2) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return d


static func _material(e: Dictionary) -> ShaderMaterial:
	var key := "mat|" + JSON.stringify([e.get("tex"), e.get("blend"), _orient(e), e.get("texdiv"), e.get("frames"), e.get("alpha_ref"),
			e.get("uvscale"), e.get("uvrate"), e.get("uvint"), e.get("tex2"), e.get("uv2scale"), e.get("uv2rate"), e.get("uv2int"),
			e.get("ero_tex"), e.get("ero_curve"), e.get("ero_ch"), e.get("soft"), e.get("pass"), e.get("plife")])
	if _mats.has(key):
		return _mats[key]
	var o := _orient(e)
	var mat := ShaderMaterial.new()
	var blend := int(e.get("blend", 0))
	mat.shader = _shader(blend)
	if blend == 1 or blend == 3 or blend == 5:
		mat.set_shader_parameter("linear_color", true)
	else:
		mat.set_shader_parameter("intensity", 0.85)   # stacked gamma-emulated additive layers blow out otherwise
	mat.set_shader_parameter("tex", _tex(e.get("tex")))
	mat.set_shader_parameter("billboard", 1 if o == 0 else (2 if o == 4 else 0))
	var div: Array = e.get("texdiv", [1, 1])
	var frames := int(e.get("frames", 0))
	if frames <= 0:
		frames = int(div[0]) * int(div[1])
	mat.set_shader_parameter("texdiv", Vector2(maxf(1, float(div[0])), maxf(1, float(div[1]))))
	mat.set_shader_parameter("total_frames", float(frames))
	mat.set_shader_parameter("alpha_ref", float(e.get("alpha_ref", 0)) / 255.0)
	mat.set_shader_parameter("uv_scale", _v2(e.get("uvscale"), Vector2.ONE))
	mat.set_shader_parameter("uv_rate", _v2(e.get("uvrate"), Vector2.ZERO))
	var plife: Array = e.get("plife", [1.0, 1.0])
	mat.set_shader_parameter("life_max", maxf(float(plife[1]), 0.05))
	var t2 := _tex(e.get("tex2"))
	if t2 != null:
		mat.set_shader_parameter("tex2", t2)
		mat.set_shader_parameter("has_tex2", true)
		mat.set_shader_parameter("uv2_scale", _v2(e.get("uv2scale"), Vector2.ONE))
		mat.set_shader_parameter("uv2_rate", _v2(e.get("uv2rate"), Vector2.ZERO))
	var uvt := _uv_tex(e)
	if uvt != null:
		mat.set_shader_parameter("uv_curve", uvt)
		mat.set_shader_parameter("has_uv_curve", true)
	var et := _tex(e.get("ero_tex"))
	var ec := _ero_tex(e)
	if et != null and ec != null:
		mat.set_shader_parameter("ero_tex", et)
		mat.set_shader_parameter("ero_curve", ec)
		mat.set_shader_parameter("has_erosion", true)
		var ch: Array = e.get("ero_ch", [1, 0, 0, 0])
		mat.set_shader_parameter("ero_channel", Vector4(float(ch[0]), float(ch[1]), float(ch[2]), float(ch[3])))
		mat.set_shader_parameter("ero_feather", float(e.get("ero_feather", 0.1)))
	if e.get("soft", false) and o != 2:
		mat.set_shader_parameter("soft_dist", 0.35)
	mat.render_priority = clampi(int(e.get("pass", 0)) / 2, -60, 60)
	_mats[key] = mat
	return mat


static var _proc_shader: Shader = null


static func _vec3_or(a, d: Vector3) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return d


static func _process_material(e: Dictionary) -> ShaderMaterial:
	var key := JSON.stringify(e)
	if _pmats.has(key):
		return _pmats[key]
	if _proc_shader == null:
		_proc_shader = load("res://src/vfx/lol_process.gdshader")
	var pm := ShaderMaterial.new()
	pm.shader = _proc_shader
	var o := _orient(e)
	var prim: String = e.get("prim", "quad")
	pm.set_shader_parameter("orient", o)
	pm.set_shader_parameter("rot_order", ROT_ORDER)
	var plife: Array = e.get("plife", [1.0, 1.0])
	pm.set_shader_parameter("life_lo", clampf(float(plife[0]) / maxf(float(plife[1]), 0.001), 0.0, 1.0))
	# emission shape
	var sh = e.get("shape")
	if sh is Dictionary:
		match str(sh.get("type", "")):
			"sphere":
				pm.set_shader_parameter("shape_type", 1)
				pm.set_shader_parameter("shape_radius", float(sh.radius))
			"box":
				var sz: Array = sh.get("size", [0, 0, 0])
				pm.set_shader_parameter("shape_type", 2)
				pm.set_shader_parameter("shape_box", Vector3(float(sz[0]), float(sz[1]), float(sz[2])) * 0.5)
			"cyl":
				pm.set_shader_parameter("shape_type", 3)
				pm.set_shader_parameter("shape_radius", float(sh.radius))
				pm.set_shader_parameter("shape_height", float(sh.get("height", 0.0)))
			"offset":
				pm.set_shader_parameter("shape_offset", _v3(sh.get("offset", [0, 0, 0])))
	# velocity / forces
	pm.set_shader_parameter("vel_base", _v3(e.get("bvel", [0, 0, 0])))
	var vr = e.get("bvel_rand")
	if vr is Array:
		pm.set_shader_parameter("vel_lo", _vec3_or(vr[0], Vector3.ONE))
		pm.set_shader_parameter("vel_hi", _vec3_or(vr[1], Vector3.ONE))
	pm.set_shader_parameter("drag", _vec3_or(e.get("drag"), Vector3.ZERO).abs())
	pm.set_shader_parameter("accel", _v3(e.get("accel", [0, 0, 0])))
	# scale: meters for quads (League quads are half-extents), multipliers for meshes
	var bs: Array = e.get("bscale", [1, 1, 1])
	var bx := absf(float(bs[0]))
	var by := absf(float(bs[1])) if bs.size() > 1 else bx
	var bz := absf(float(bs[2])) if bs.size() > 2 else bx
	var uni: bool = e.get("uniform", false)
	var base := Vector3.ONE
	if o == 3:
		base = Vector3(bx, by if by > 0.0001 and not uni else bx, bz if bz > 0.0001 and not uni else bx)
	elif o == 0:
		base = Vector3(bx, bx, 1.0) * S * QUAD_SCALE
	else:
		var hy := by if (by > 0.01 and not uni and prim == "aquad") else bx
		base = Vector3(bx * S * QUAD_SCALE, hy * S * QUAD_SCALE, 1.0)
	pm.set_shader_parameter("scale_base", base)
	pm.set_shader_parameter("uniform_scale", uni or o == 0)
	var br = e.get("bscale_rand")
	if br is Array:
		pm.set_shader_parameter("scale_lo", _vec3_or(br[0], Vector3.ONE))
		pm.set_shader_parameter("scale_hi", _vec3_or(br[1], Vector3.ONE))
	var stex := _scale_tex(e)
	if stex != null:
		pm.set_shader_parameter("scale_curve", stex)
		pm.set_shader_parameter("has_scale_curve", true)
	# rotation: League stores the billboard roll in X; meshes / free quads use full euler (mirrored for the z flip)
	var rot := _vec3_or(e.get("brot"), Vector3.ZERO)
	var rr = e.get("brot_rand")
	var rlo := _vec3_or(rr[0], Vector3.ONE) if rr is Array else Vector3.ONE
	var rhi := _vec3_or(rr[1], Vector3.ONE) if rr is Array else Vector3.ONE
	var rv := _vec3_or(e.get("rotvel"), Vector3.ZERO)
	var rvr = e.get("rotvel_rand")
	var vlo := _vec3_or(rvr[0], Vector3.ONE) if rvr is Array else Vector3.ONE
	var vhi := _vec3_or(rvr[1], Vector3.ONE) if rvr is Array else Vector3.ONE
	var spin_i := 0
	if absf(rv.y) >= absf(rv.x) and absf(rv.y) >= absf(rv.z):
		spin_i = 1
	elif absf(rv.z) > absf(rv.x):
		spin_i = 2
	if o == 0 or o == 4:
		pm.set_shader_parameter("rot_base", Vector3(0, 0, rot.x))
		pm.set_shader_parameter("rot_lo", Vector3(1, 1, rlo.x))
		pm.set_shader_parameter("rot_hi", Vector3(1, 1, rhi.x))
		pm.set_shader_parameter("spin_base", rv.x)
		pm.set_shader_parameter("spin_lo", vlo.x)
		pm.set_shader_parameter("spin_hi", vhi.x)
	elif o == 2:
		var k := 0 if prim == "quad" else 2
		pm.set_shader_parameter("rot_base", Vector3(0, 0, rot[k]))
		pm.set_shader_parameter("rot_lo", Vector3(1, 1, rlo[k]))
		pm.set_shader_parameter("rot_hi", Vector3(1, 1, rhi[k]))
		pm.set_shader_parameter("spin_base", rv[spin_i])
		pm.set_shader_parameter("spin_lo", vlo[spin_i])
		pm.set_shader_parameter("spin_hi", vhi[spin_i])
	else:
		pm.set_shader_parameter("rot_base", Vector3(-rot.x, -rot.y, rot.z))
		pm.set_shader_parameter("rot_lo", rlo)
		pm.set_shader_parameter("rot_hi", rhi)
		pm.set_shader_parameter("spin_axis", spin_i)
		pm.set_shader_parameter("spin_base", rv[spin_i] * (-1.0 if spin_i < 2 else 1.0))
		pm.set_shader_parameter("spin_lo", vlo[spin_i])
		pm.set_shader_parameter("spin_hi", vhi[spin_i])
	# color
	pm.set_shader_parameter("color_base", _col(e.get("bcolor", [1, 1, 1, 1])))
	var cr = e.get("bcolor_rand")
	if cr is Array and cr[0].size() >= 4:
		pm.set_shader_parameter("color_lo", Color(float(cr[0][0]), float(cr[0][1]), float(cr[0][2]), float(cr[0][3])))
		pm.set_shader_parameter("color_hi", Color(float(cr[1][0]), float(cr[1][1]), float(cr[1][2]), float(cr[1][3])))
	var ct := _color_tex(e)
	if ct != null:
		pm.set_shader_parameter("color_curve", ct)
		pm.set_shader_parameter("has_color_curve", true)
	# flipbook / uv offset
	var div: Array = e.get("texdiv", [1, 1])
	var frames := int(e.get("frames", 0))
	if frames <= 0:
		frames = int(div[0]) * int(div[1])
	pm.set_shader_parameter("frames", float(frames))
	pm.set_shader_parameter("fps", float(e.get("fps", 0.0)))
	pm.set_shader_parameter("rand_frame", bool(e.get("rand_frame", false)))
	pm.set_shader_parameter("start_frame", float(e.get("start_frame", 0)))
	var uo = e.get("uvoff")
	if uo is Array and uo.size() == 2:
		pm.set_shader_parameter("uv_off_lo", _v2(uo[0], Vector2.ZERO))
		pm.set_shader_parameter("uv_off_hi", _v2(uo[1], Vector2.ZERO))
	_pmats[key] = pm
	return pm


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
