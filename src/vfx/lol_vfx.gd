class_name LolVfx
extends Node3D
## League particle system instance, built from data/vfx/<champion>.json (tools/lol/extract_vfx.py).
## Each League emitter becomes a GPUParticles3D (quads / oriented quads / rays / meshes), a LolTrail ribbon,
## a LolBeam, an attached-mesh shell over the host unit, or child systems spawned per particle.
## Static API:
##   LolVfx.has(name)                  -> bool
##   LolVfx.spawn(m, name, pos, opts)  -> LolVfx node (world space) or null
##   LolVfx.attach(parent, name, opts) -> LolVfx node following `parent`
##   LolVfx.make(name, opts)           -> unparented instance (missile visuals)
## opts: dir (Vector3 facing), scale (float), loop (bool: keep emitting until stop()), height (float),
##       center (float: raise non-ground emitters), bone (String: non-ground emitters follow Unit.socket(bone)),
##       length (beams), max_life (s), face (bool, attach only), mis (Dictionary: missile flight heights)

const S := 0.01          ## League units -> meters
const QUAD_SCALE := 2.0  ## League quad size is a half-extent
const MAX_ONESHOT := 6.0 ## seconds a non-looping effect may live
static var ROT_ORDER := 4   ## euler order yzx: verified on Yasuo W wall + Q streak geometry
const MAX_FADE := 2.5    ## seconds particles may keep fading after stop()
const MAX_AMOUNT := 256  ## particle cap per emitter
const MAX_BURST := 64    ## cap for isSingleParticle bursts
const MAX_CHILDREN := 12 ## child systems per emitter
const DEFAULT_HIT_BONE := "C_BUFFBONE_GLB_CHEST_LOC"
const BUDGET_SOFT := 6000  ## live GPU particle slots before dense emitters are halved
const BUDGET_HARD := 12000 ## ... and thirded

static var _db := {}             ## system name -> definition
static var _spells := {}         ## alias (lower) -> {spell script name: placement meta}
static var _slots := {}          ## alias (lower) -> {"Q": spell name, ...}
static var _loaded := {}         ## file -> true
static var _shaders := {}
static var _mats := {}
static var _pmats := {}
static var _meshes := {}
static var _ramps := {}
static var _resolve := {}
static var live_particles := 0   ## budget: GPU particle slots currently allocated by LolVfx

var def := {}
var _t := 0.0
var _dur := 2.0
var _loop := false
var _stopped := false
var _free_at := -1.0
var _timers: Array = []          ## [time, callable]
var follow: Node3D = null:
	set(v):
		follow = v
		if v != null:
			_dynamic = true
var _face_unit = null            ## attached to a Unit: keep facing its direction
var follow_offset := Vector3.ZERO
var _anchor: Node3D = null       ## follows a bone socket; non-ground emitters live under it
var _socket: Node3D = null
var _host: Node3D = null         ## unit this effect is attached to (attached meshes, sockets)
var _rate_fx: Array = []         ## [GPUParticles3D, rate curve, emitter life, start time]
var _lingers: Array = []         ## [node, linger seconds, color curve or null]
var _carriers: Array = []        ## child-system carriers: {node, vel, acc, drag, age, life}
var _ameshes: Array = []         ## [MeshInstance3D, color curve, base color, life, start]
var _budget := 0
var _mis := {}                   ## missile flight: {"start_h", "end_h", "end_bone"}
var _mis_frame: Node3D = null    ## missile systems: League +Y = flight direction
var _ground_nodes: Array = []    ## missile ground-layer emitters kept on the terrain
const MIS_BASIS := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))   ## Y -> -Z (forward), Z -> Y
var _opts := {}


# ===================================================================== database
static func load_set(file: String) -> void:
	file = file.to_lower()
	if _loaded.has(file):
		return
	_loaded[file] = true
	var path := "res://data/vfx/%s.json" % file.to_lower()
	if not FileAccess.file_exists(path):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if d is Dictionary:
		var t0 := Time.get_ticks_usec()
		for k in d:
			if k == "_spells":
				_spells[file.to_lower()] = d[k]
			else:
				_db[k] = d[k]
				_prebuild(d[k])
		print("LolVfx: %s prebuilt %d systems in %.0f ms" % [file, d.size(), (Time.get_ticks_usec() - t0) / 1000.0])


## Build everything a system needs (materials, process materials + curve textures, meshes, template nodes,
## textures) at load time so an in-match spawn only duplicates templates and sets a few values.
static func _prebuild(sd) -> void:
	if not (sd is Dictionary):
		return
	# systems whose ground-layer emitters sit ~100 units below the origin were authored to spawn at missile
	# height (Lux E's zone lands where the 100-unit-high missile ends): spawn() lifts them back onto the ground
	var low := 0.0
	for e in sd.get("emitters", []):
		if _is_ground(e):
			var y := _v3(e.get("pos", [0, 0, 0])).y
			var sh = e.get("shape")
			if sh is Dictionary and sh.get("type", "") == "offset":
				y += _v3(sh.get("offset", [0, 0, 0])).y
			low = minf(low, y)
	if low < -0.3:
		sd["_lift"] = -low
	for e in sd.get("emitters", []):
		var prim: String = e.get("prim", "quad")
		if e.get("tex") == null:
			continue
		if prim == "amesh":
			_material(e, true)
		elif prim == "ctrail" or prim == "atrail":
			_trail_spec(e)
		elif prim == "beam":
			_tex(e.get("tex"))
		elif not (e.get("distort") is bool):
			var s0 := _particle_spec(e, false)
			var el: float = float(e.get("life", -1.0))
			if el > 0.0 and el < 0.12 and not e.get("single", false):
				_particle_spec(e, true)
			else:
				e["_spec1"] = s0


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
	_spells.clear()
	_slots.clear()
	_texc.clear()
	_warm.clear()


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
	n.global_position = pos + Vector3(0, float(opts.get("height", 0.0)) + float(n.def.get("_lift", 0.0)), 0)
	n._apply_dir()
	return n


static func attach(parent: Node3D, name: String, opts: Dictionary = {}) -> LolVfx:
	if parent == null:
		return null
	var n := make(name, opts)
	if n == null:
		return null
	n._host = parent
	if not opts.has("bone") and parent.has_method("socket"):
		# League attaches crowd-control indicators to the overhead buff bone
		if name.begins_with("LOC_"):
			n._opts = opts.duplicate()
			n._opts["bone"] = "C_BUFFBONE_GLB_OVERHEAD_LOC"
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


## League placement data (hit bone, missile bones / heights) for a champion's slot ("Q".."R", "BA", "CRIT").
static func spell_meta(c, slot: String) -> Dictionary:
	if c == null or not ("alias" in c):
		return {}
	var al: String = String(c.alias).to_lower()
	load_set(c.alias)
	var sp: Dictionary = _spells.get(al, {})
	if sp.is_empty():
		return {}
	var nm := ""
	if slot == "BA":
		nm = c.alias + "BasicAttack"
	elif slot == "CRIT":
		nm = c.alias + "CritAttack"
	else:
		if not _slots.has(al):
			_slots[al] = {}
			var path := "res://data/champions/%s_game.json" % al
			if FileAccess.file_exists(path):
				var d = JSON.parse_string(FileAccess.get_file_as_string(path))
				if d is Dictionary and d.get("spell_slots") is Dictionary:
					_slots[al] = d.spell_slots
		nm = _slots[al].get(slot, "")
	if nm == "":
		return {}
	var out: Dictionary = (sp.get(nm, {}) as Dictionary).duplicate()
	# the missile spec often lives on a helper spell ("EzrealQMis", "LuxLightBindingMis" ...)
	if not out.has("start_h") and not out.has("start_bone"):
		for k in sp:
			if String(k).begins_with(nm) and k != nm and (sp[k].has("start_h") or sp[k].has("start_bone")):
				for f in sp[k]:
					if not out.has(f):
						out[f] = sp[k][f]
				break
	return out


static func _hit_point(t, bone: String) -> Vector3:
	if t != null and is_instance_valid(t) and t.has_method("socket") and t.get("model") != null:
		var s: Node3D = t.socket(bone if bone != "" else DEFAULT_HIT_BONE)
		if s != null and s.is_inside_tree():
			var p := s.global_position
			if p.is_finite() and G.flat_dist(p, t.global_position) < 3.0 + float(t.radius):
				return p
	return t.global_position + Vector3(0, float(t.height) * 0.5, 0)


# ===================================================================== gameplay hooks
static var _hit_rl := {}


static func _slot_key(ab) -> String:
	if ab == null or not ("slot" in ab):
		return ""
	var s: int = ab.slot
	return "QWER"[s] if s >= 0 and s <= 3 else ""


static func _team_name(u) -> String:
	return "Order" if u.team == G.Team.ORDER else "Chaos"


## Howling Abyss turrets: Order uses Turret skin 24 (blue), Chaos skin 25 (red) - data/characters/turret/skins.
## Systems: <skin>_BA (vs minions), _BA_Champ_01..04 (escalating vs champions), _BA_Cas_Champ_01..04 (muzzle),
## _BA_Tar / _BA_Tar_Champ / _BA_Tar_Champ_02..04 (hits), _BA_LaserSight_beam (opts length), _Idle.
static func turret_skin(t) -> String:
	return "Turret_Skin24" if t == null or t.team == G.Team.ORDER else "Turret_Skin25"


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
			nm = "%s_BA_Champ_%02d" % [turret_skin(src), clampi(int(src.ramp) + 1, 1, 4)]
		else:
			nm = "%s_BA" % turret_skin(src)
	return make(nm, {"loop": true, "mis": {"end_bone": DEFAULT_HIT_BONE}}) if nm != "" else null


## Basic attack impact on the target (at the target's hit bone).
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
				nm2 = ("%s_BA_Tar_Champ" % turret_skin(src)) if shot <= 1 else "%s_BA_Tar_Champ_%02d" % [turret_skin(src), shot]
			else:
				nm2 = "%s_BA_Tar" % turret_skin(src)
		if nm2 != "" and src.match_ref != null:
			load_set("shared")
			_spawn_hit(src.match_ref, nm2, src, t, DEFAULT_HIT_BONE)
		return
	var nm := champ_fx(src, "BA_crit_tar") if crit else ""
	if nm == "":
		nm = champ_fx(src, "BA_tar")
	if nm != "":
		var meta := spell_meta(src, "CRIT" if crit else "BA")
		_spawn_hit(src.match_ref, nm, src, t, String(meta.get("hit_bone", DEFAULT_HIT_BONE)))


## Hit effects are authored around the hit bone: non-ground emitters at the bone, ground emitters at the feet.
static func _spawn_hit(m, nm: String, src, t, bone: String) -> void:
	if m == null:
		return
	var hp := _hit_point(t, bone)
	var feet: Vector3 = t.global_position
	spawn(m, nm, feet, {"dir": G.flat_dir(src.global_position, feet), "center": maxf(hp.y - feet.y, 0.0)})


## Ability cast flash on the caster (non-ground emitters at the spell's cast bone when League names one).
static func on_cast(ab, t: Dictionary) -> void:
	var o = ab.owner
	var k := _slot_key(ab)
	if k == "" or not (o is Champion):
		return
	var nm := champ_fx(o, k + "_cas")
	if nm != "":
		var dir: Vector3 = t.get("dir", o.facing)
		var opts := {"dir": dir, "center": o.height * 0.35, "max_life": 3.0}
		var meta := spell_meta(o, k)
		if meta.has("start_bone") and o.has_method("socket"):
			opts["bone"] = meta.start_bone
		attach(o, nm, opts)


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
		var meta := spell_meta(src, k)
		_spawn_hit(src.match_ref, nm, src, t, String(meta.get("hit_bone", DEFAULT_HIT_BONE)))


## Spell missile visual (replaces the kit's placeholder visual) or null.
static func missile_visual(mi) -> LolVfx:
	if mi == null or mi.ability == null or mi.custom.get("keep_visual", false):
		return null
	var o = mi.ability.owner
	var k := _slot_key(mi.ability)
	if k == "" or not (o is Champion):
		return null
	var nm := champ_fx(o, k + "_mis")
	if nm == "":
		return null
	var meta := spell_meta(o, k)
	return make(nm, {"loop": true, "mis": meta})


## League flight height of a champion's basic-attack missile (for match.gd's attack missiles).
static func attack_missile_meta(src, crit: bool) -> Dictionary:
	var m := spell_meta(src, "CRIT" if crit else "BA")
	if m.is_empty() and crit:
		m = spell_meta(src, "BA")
	return m


# ===================================================================== central updater
## One hub node drives every LolVfx: instances never run their own _process. Each frame the hub ticks only the
## "dynamic" instances (following a unit / bone / missile, rate curves, carriers, shells, lingering fades); the
## others sleep until their next timer or free time. Looping world effects (map ambient, structures) far from
## the camera stop emitting and hide until the camera comes back.
static var _hub: Node = null
static var _now := 0.0
static var _live: Array = []
static var _cull_t := 0.0
static var _warm: Array = []        ## materials to draw once (pipeline compile) before their first real use
const CULL_DIST := 32.0             ## m from the camera's ground focus


class Hub extends Node:
	var _warm_nodes: Array = []
	var _warm_frames := 0

	func _process(dt: float) -> void:
		var t0 := Prof.t0()
		LolVfx._hub_tick(dt)
		Prof.add("vfx.update", t0)
		if not LolVfx._warm.is_empty() or not _warm_nodes.is_empty():
			_warmup()

	## Draw every new particle material once, tiny and in front of the camera, so Godot compiles its
	## pipelines during loading instead of stalling on the first cast.
	func _warmup() -> void:
		if not _warm_nodes.is_empty():
			_warm_frames += 1
			if _warm_frames >= 3:
				for n in _warm_nodes:
					if is_instance_valid(n):
						n.queue_free()
				_warm_nodes.clear()
			return
		var vp := get_viewport()
		var cam := vp.get_camera_3d() if vp != null else null
		if cam == null:
			return
		var seen := {}
		var quad := QuadMesh.new()
		quad.size = Vector2(0.002, 0.002)
		for w in LolVfx._warm:
			var mat: Material = w[0]
			var pm: Material = w[1]
			# pipelines are per shader variant, not per material: one draw per variant is enough
			var sh: Shader = (mat as ShaderMaterial).shader if mat is ShaderMaterial else null
			var key = sh.get_rid() if sh != null else mat.get_rid()
			if seen.has(key):
				continue
			seen[key] = true
			var p := GPUParticles3D.new()
			p.amount = 1
			p.lifetime = 0.2
			p.process_material = pm
			p.draw_pass_1 = quad
			p.material_override = mat
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cam.add_child(p)
			p.position = Vector3(0, 0, -1.0)
			_warm_nodes.append(p)
		LolVfx._warm.clear()
		_warm_frames = 0


static func _ensure_hub() -> void:
	if _hub != null and is_instance_valid(_hub):
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	_hub = Hub.new()
	_hub.name = "LolVfxHub"
	_hub.process_mode = Node.PROCESS_MODE_ALWAYS
	tree.root.add_child.call_deferred(_hub)


static func _hub_tick(dt: float) -> void:
	_now += dt
	var i := 0
	while i < _live.size():
		var n = _live[i]
		if not is_instance_valid(n) or n._dead:
			_live[i] = _live[_live.size() - 1]
			_live.pop_back()
			continue
		if (n._dynamic or _now >= n._wake) and n.is_inside_tree():
			n._tick()
		i += 1
	_cull_t += dt
	if _cull_t >= 0.25:
		_cull_t = 0.0
		_cull_pass()


## Loop world effects (no unit / missile host) beyond CULL_DIST of the camera focus pause emitting and hide.
static func _cull_pass() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var cam: Camera3D = tree.root.get_viewport().get_camera_3d() if tree != null else null
	if cam == null:
		return
	var cp := cam.global_position
	var fw := -cam.global_basis.z
	var focus := cp
	if fw.y < -0.05:
		focus = cp + fw * ((cp.y - 0.0) / -fw.y)
	for n in _live:
		if not is_instance_valid(n) or not n._loop or n._host != null or not n._mis.is_empty() or not n.is_inside_tree():
			continue
		var p: Vector3 = n.global_position
		var far := Vector2(p.x - focus.x, p.z - focus.z).length() > CULL_DIST
		if far != n._culled:
			n._set_culled(far)


func _set_culled(c: bool) -> void:
	_culled = c
	for e in _emitter_nodes():
		if e is GPUParticles3D:
			e.visible = not c
			if not _stopped:
				e.emitting = not c and e.get_meta("started", false)
		elif e is LolTrail:
			e.visible = not c


# ===================================================================== instance
var _born := 0.0
var _last := 0.0
var _wake := INF
var _dynamic := false
var _dead := false
var _culled := false


func _ready() -> void:
	var t0 := Prof.t0()
	set_process(false)
	_ensure_hub()
	_born = _now
	_last = _now
	_setup(_opts)
	_live.append(self)
	_refresh()
	Prof.add("vfx.spawn", t0)
	if _log_spawns:
		print("VFXLOG t=%.2f %s host=%s pos=%s" % [Time.get_ticks_msec() / 1000.0, name, _host.name if _host != null else "-", global_position.snapped(Vector3.ONE * 0.1)])


static var _log_spawns: bool = "--vfxlog" in OS.get_cmdline_user_args()


## Recompute whether this instance needs a tick every frame or can sleep until its next timer / free time.
func _refresh() -> void:
	_dynamic = _face_unit != null or follow != null or _anchor != null or not _mis.is_empty() \
			or not _ground_nodes.is_empty() or not _rate_fx.is_empty() or not _carriers.is_empty() \
			or not _ameshes.is_empty() or (_stopped and not _lingers.is_empty())
	var w := INF
	for tm in _timers:
		w = minf(w, _born + float(tm[0]))
	if _free_at >= 0.0:
		w = minf(w, _born + _free_at)
	_wake = w


## Leaving the tree is not the end (detach_and_fade reparents missile visuals); only deletion is.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_dead = true
		live_particles -= _budget
		_budget = 0
		for a in _ameshes:
			if is_instance_valid(a[0]):
				a[0].queue_free()
		_ameshes.clear()


func _apply_dir() -> void:
	var dir: Vector3 = _opts.get("dir", Vector3.ZERO)
	if dir.length_squared() > 0.001:
		var d := Vector3(dir.x, 0, dir.z).normalized()
		global_basis = Basis.looking_at(d, Vector3.UP) * Basis.from_scale(scale)


func _setup(opts: Dictionary) -> void:
	_dur = float(def.get("dur", 2.0))
	_loop = bool(opts.get("loop", false))
	_mis = opts.get("mis", {}) if opts.get("mis") is Dictionary else {}
	var par = get_parent()
	if _mis.is_empty() and par is Missile and par.is_attack and par.source is Champion:
		# champion basic attacks (match.gd): League start height / hit bone of the attack spell
		_mis = attack_missile_meta(par.source, false)
		if _mis.is_empty():
			_mis = {"end_bone": DEFAULT_HIT_BONE}
	if _host == null and get_parent() is Unit:
		_host = get_parent()
	var sc: float = float(opts.get("scale", 1.0))
	if absf(sc - 1.0) > 0.001:
		scale = Vector3.ONE * sc
	var bone: String = String(opts.get("bone", ""))
	if bone != "" and _host != null and is_instance_valid(_host) and _host.has_method("socket"):
		_socket = _host.socket(bone)
		if _socket != null:
			_anchor = Node3D.new()
			_anchor.name = "BoneAnchor"
			add_child(_anchor)
			_update_anchor()
	if opts.get("missile", false) or par is Missile or opts.has("mis"):
		# League orients missile systems with +Y along the flight direction (Ezreal Q's 3 m "ground_glow" quad,
		# trailing cones with -Y velocity, Y-elongated leading glows); isLocalOrientation=false emitters stay upright
		_mis_frame = Node3D.new()
		_mis_frame.name = "MissileFrame"
		_mis_frame.basis = MIS_BASIS
		add_child(_mis_frame)
	_building = true
	for e in def.get("emitters", []):
		_build_emitter(e)
	_building = false
	if not _loop:
		# League durations include long, fully faded tails; cap so finished effects leave the tree
		_free_at = minf(_dur, float(opts.get("max_life", MAX_ONESHOT))) + 0.2


func _update_anchor() -> void:
	if _anchor == null:
		return
	if _socket != null and is_instance_valid(_socket) and _socket.is_inside_tree():
		var p := _socket.global_position
		if p.is_finite():
			_anchor.global_position = p
			return
	_anchor.position = Vector3(0, float(_opts.get("center", 0.0)), 0)


func _tick() -> void:
	var dt := _now - _last
	_last = _now
	_t = _now - _born
	var i := 0
	while i < _timers.size():
		var tm: Array = _timers[i]
		if _t >= tm[0]:
			_timers.remove_at(i)
			if tm.size() > 2:
				_node_event(tm[1], tm[2])
			else:
				(tm[1] as Callable).call()
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
	if _anchor != null:
		_update_anchor()
	if not _mis.is_empty():
		_track_missile()
	if not _ground_nodes.is_empty():
		_ground_snap()
	for r in _rate_fx:
		var p: GPUParticles3D = r[0]
		if is_instance_valid(p):
			var k := clampf((_t - float(r[3])) / maxf(float(r[2]), 0.01), 0.0, 1.0)
			var ec: Array = r[1]
			var fi := k * (ec.size() - 1)
			var v := lerpf(float(ec[int(fi)]), float(ec[mini(int(fi) + 1, ec.size() - 1)]), fi - floorf(fi))
			p.amount_ratio = clampf(v / maxf(float(r[4]), 0.001), 0.0, 1.0)
	if not _carriers.is_empty():
		_tick_carriers(dt)
	if not _ameshes.is_empty():
		_tick_ameshes()
	if _stopped and not _lingers.is_empty():
		_tick_lingers()
	if _free_at >= 0.0 and _t >= _free_at:
		_dead = true
		queue_free()
		return
	_refresh()


var _building := false


## Emitter start (kind 0) / stop (kind 1) without allocating a closure per emitter.
func _after_node(t: float, n: Node, kind: int) -> void:
	if t <= 0.0:
		_node_event(n, kind)
	else:
		_timers.append([(_now - _born) + t, n, kind])
		if not _building:
			_refresh()


func _node_event(n, kind: int) -> void:
	if not is_instance_valid(n):
		return
	if kind == 0:
		if _stopped:
			return
		n.set_meta("started", true)
		if _culled:
			return
		n.restart()
		n.emitting = true
	else:
		n.emitting = false


func _after(t: float, fn: Callable) -> void:
	if t <= 0.0:
		fn.call()
	else:
		_timers.append([(_now - _born) + t, fn])
		if not _building:
			_refresh()


## Stop emitting; the node frees itself once live particles have faded (League particleLinger).
var _stop_t := 0.0


func stop() -> void:
	if _stopped:
		return
	_stopped = true
	_t = _now - _born
	_stop_t = _t
	var longest := 0.0
	for c in _emitter_nodes():
		if c is GPUParticles3D:
			c.emitting = false
			# League particleLinger: how long live particles survive their system; without it they end now
			# (a short fade instead of a pop), with it they keep simulating, infinite ones fade by lingerColor
			var lg: float = float(c.get_meta("linger", 0.0))
			var life: float = c.lifetime * float(c.get_meta("life_scale", 1.0))
			if c.has_meta("infinite"):
				var d := lg if lg > 0.0 else 0.12
				_lingers.append([c, d, c.get_meta("linger_color") if c.has_meta("linger_color") else null])
				longest = maxf(longest, d)
			elif lg <= 0.0:
				_lingers.append([c, 0.12, null])
				longest = maxf(longest, 0.12)
			elif lg < life:
				_lingers.append([c, lg, "tail"])
				longest = maxf(longest, lg)
			else:
				longest = maxf(longest, life)
		elif c is LolTrail:
			c.emitting = false
			longest = maxf(longest, c.life)
	for a in _ameshes:
		longest = maxf(longest, 0.3)
	for cr in _carriers:
		if is_instance_valid(cr.node) and cr.node is LolVfx:
			cr.node.stop()
	_free_at = (_now - _born) + minf(longest, MAX_FADE) + 0.1
	_refresh()


func _emitter_nodes() -> Array:
	var out: Array = []
	for c in get_children():
		out.append(c)
	for holder in [_anchor, _mis_frame]:
		if holder != null:
			for c in holder.get_children():
				out.append(c)
	return out


func _tick_lingers() -> void:
	for l in _lingers:
		var n = l[0]
		if not is_instance_valid(n):
			continue
		var k := clampf((_t - _stop_t) / maxf(float(l[1]), 0.01), 0.0, 1.0)
		var a := 1.0 - k
		if l[2] is Dictionary:
			a = _sample_color_curve(l[2], k).a
		elif l[2] is String:
			a = clampf((1.0 - k) / 0.3, 0.0, 1.0)   # keep simulating, fade over the last 30%
		n.set_instance_shader_parameter("fade", a)


## Missile visual protocol (Missile.finish calls this): keep the effect where it ended and fade out.
func detach_and_fade() -> void:
	var gp := global_transform
	var root = G.match.fx_root if G.match != null else null
	_mis = {}
	if root != null and get_parent() != root:
		get_parent().remove_child(self)
		root.add_child(self)
		global_transform = gp
	stop()


## League missiles fly at the spell's start height (default 100 units) and home onto the target's hit bone.
func _track_missile() -> void:
	var mi = get_parent()
	if mi == null or not ("mode" in mi) or not ("start" in mi):
		return
	var m = G.match
	var ground := 0.0
	if m != null and m.nav != null:
		ground = m.nav.height_at(mi.global_position)
	if not _mis.has("start_h"):
		# no League height on the spell (Jinx R): keep the launch height (start bone / kit spawn point),
		# not a default 100 units that buries the rocket mesh authored ~100 units below the system origin
		var sy: float = mi.start.y
		var src = mi.get("source")
		if _mis.has("start_bone") and src != null and is_instance_valid(src) and src.has_method("socket"):
			var so: Node3D = src.socket(String(_mis.start_bone))
			if so != null and so.is_inside_tree():
				sy = maxf(sy, so.global_position.y)
		var g0 := 0.0
		if m != null and m.nav != null:
			g0 = m.nav.height_at(mi.start)
		_mis = _mis.duplicate()
		_mis["start_h"] = maxf(sy - g0, 1.0)
	var h0: float = float(_mis.get("start_h", 1.0))
	var y := ground + h0
	if int(mi.mode) == Missile.Mode.HOMING and mi.target != null and is_instance_valid(mi.target):
		var tp := _hit_point(mi.target, String(_mis.get("end_bone", _mis.get("hit_bone", DEFAULT_HIT_BONE))))
		var start_y: float = mi.start.y
		var rem := G.flat_dist(mi.global_position, tp)
		var done: float = float(mi.traveled)
		var k := done / maxf(done + rem, 0.01)
		y = lerpf(start_y, tp.y, k)
	elif int(mi.mode) != Missile.Mode.LINEAR:
		return
	var gp := global_position
	global_position = Vector3(gp.x, y, gp.z)


## Ground-layer emitters of a flying missile stay on the terrain under it.
func _ground_snap() -> void:
	var m = G.match
	for n in _ground_nodes:
		if is_instance_valid(n) and n.is_inside_tree():
			var gp: Vector3 = n.global_position
			var y := 0.0
			if m != null and m.nav != null:
				y = m.nav.height_at(gp)
			n.global_position = Vector3(gp.x, y + 0.03, gp.z)


# ===================================================================== emitter builders
func _parent_for(e: Dictionary) -> Node3D:
	if _mis_frame != null and e.get("lorient", true) and not _is_ground(e):
		return _mis_frame
	if _anchor != null and not _is_ground(e):
		return _anchor
	return self


static func _is_ground(e: Dictionary) -> bool:
	return e.get("ground", false) or e.get("prim", "") == "proj"


## Emitter offset in its parent: missile ground / upright emitters still place their offset in the missile frame.
func _place_offset(e: Dictionary, n: Node3D) -> Vector3:
	var off := _v3(e.get("pos", [0, 0, 0]))
	if _mis_frame != null and n.get_parent() != _mis_frame:
		off = MIS_BASIS * off
		if _is_ground(e):
			off.y = 0.0
	return off


func _build_emitter(e: Dictionary) -> void:
	var prim: String = e.get("prim", "quad")
	if e.has("children"):
		_build_children(e)
	if prim == "amesh":
		_build_amesh(e)
		return
	if e.get("tex") == null:
		return
	var dist = e.get("distort")
	if dist is bool and dist:
		return   # old-format data without the normal map
	if prim == "ctrail" or prim == "atrail":
		_build_trail(e)
		return
	if prim == "beam":
		_build_beam(e)
		return
	var spec := _particle_spec(e, _loop)
	if spec.is_empty():
		return
	var p := _new_particles(spec)
	# global particle budget (10-champion teamfights): thin out dense emitters when many effects are live
	if live_particles > BUDGET_SOFT and p.amount > 8:
		p.amount = maxi(8, p.amount / (3 if live_particles > BUDGET_HARD else 2))
	_parent_for(e).add_child(p)
	p.position = _place_offset(e, p)
	if not _is_ground(e) and _anchor == null and _mis_frame == null:
		p.position.y += float(_opts.get("center", 0.0))
	if _is_ground(e) and _mis_frame != null:
		_ground_nodes.append(p)
	_budget += p.amount
	live_particles += p.amount
	var delay: float = spec.delay
	_after_node(delay, p, 0)
	if spec.rate_ec != null:
		_rate_fx.append([p, spec.rate_ec, spec.elife if spec.elife > 0.0 else 1.0, delay, spec.rate])
	if spec.timed and not _loop:
		_after_node(delay + spec.elife, p, 1)


## Fresh GPUParticles3D from a spec (property sets are ~10x cheaper than Node.duplicate()).
static func _new_particles(sp: Dictionary) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = sp.amount
	p.lifetime = sp.lifetime
	p.one_shot = sp.one_shot
	if sp.one_shot:
		p.explosiveness = 1.0
	p.local_coords = sp.local
	p.draw_order = GPUParticles3D.DRAW_ORDER_INDEX
	p.visibility_aabb = VIS_AABB
	p.process_material = sp.pm
	p.draw_pass_1 = sp.mesh
	p.material_override = sp.mat
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.set_meta("life_scale", sp.life_scale)
	p.set_meta("linger", sp.linger)
	if sp.linger_color != null:
		p.set_meta("linger_color", sp.linger_color)
	if sp.infinite:
		p.set_meta("infinite", true)
	return p


const VIS_AABB := AABB(Vector3(-15, -15, -15), Vector3(30, 30, 30))


## Everything about a particle emitter that does not depend on the instance, built once per emitter (and loop
## flag) at load time; spawning only creates the node and sets these values.
static func _particle_spec(e: Dictionary, loop: bool) -> Dictionary:
	var ck := "_spec1" if loop else "_spec0"
	var cached = e.get(ck)
	if cached is Dictionary:
		return cached
	var out := {}
	var single: bool = e.get("single", false)
	var plife: Array = e.get("plife", [1.0, 1.0])
	var infinite: bool = float(plife[1]) < 0.0
	var life_max: float = 3600.0 if infinite else maxf(float(plife[1]), 0.05)
	var rate: float = maxf(float(e.get("rate", 1.0)), 0.0)
	var elife: float = float(e.get("life", -1.0))
	var life_scale := 1.0
	var amount := 1
	var lifetime := life_max
	var one_shot := false
	if infinite:
		single = true
	if single:
		# isSingleParticle: one burst of `rate` particles
		amount = clampi(int(round(rate)) if rate >= 1.0 else 1, 1, MAX_BURST)
		one_shot = true
	else:
		if rate <= 0.0:
			e[ck] = out
			return out
		amount = clampi(int(ceil(rate * life_max)), 1, MAX_AMOUNT)
		# Godot emits amount / lifetime per second: stretch the cycle so the rate is exact, particles die early
		lifetime = maxf(amount / rate, life_max)
		life_scale = life_max / lifetime
		if elife > 0.0 and elife < 0.12 and not loop:
			# a very short emitter with a high rate is really a burst
			one_shot = true
			amount = clampi(int(ceil(rate * maxf(elife, 0.05))), 1, MAX_AMOUNT)
			lifetime = life_max
			life_scale = 1.0
	out.amount = amount
	out.lifetime = lifetime
	out.one_shot = one_shot
	out.life_scale = life_scale
	out.infinite = infinite
	out.local = bool(e.get("local", false))
	out.linger = float(e.get("linger", 0.0))
	out.linger_color = e.get("linger_color")
	out.pm = _process_material(e, single, life_scale, one_shot and not single)
	out.mesh = _mesh_for(e)
	out.mat = _material(e)
	out.delay = float(e.get("delay", 0.0))
	out.elife = elife
	out.rate = rate
	out.rate_ec = e.rate_ec if (e.get("rate_ec") is Array and not single and not one_shot) else null
	out.timed = not single and elife > 0.0 and not one_shot
	e[ck] = out
	_warm.append([out.mat, out.pm])
	return out


static func _trail_spec(e: Dictionary) -> Dictionary:
	var c = e.get("_tspec")
	if c is Dictionary:
		return c
	var sp := {}
	var plife: Array = e.get("plife", [0.3, 0.3])
	sp.life = maxf(float(plife[1]), 0.05)
	var bs: Array = e.get("bscale", [10, 0, 0])
	sp.width = absf(float(bs[0])) * S * QUAD_SCALE
	sp.width_curve = _curve_x(e.get("scale"))
	sp.color = _col(e.get("bcolor", [1, 1, 1, 1]))
	sp.birth_colors = e.get("bcolor_ec")
	sp.color_curve = e.get("color")
	sp.blend = int(e.get("blend", 4))
	sp.texture = _tex(e.get("tex"))
	sp.tex2 = _tex(e.get("tex2"))
	var tr: Dictionary = e.get("trail", {})
	sp.tiling = float(tr.get("tiling", 0.0))
	sp.tiling_ec = tr.get("tiling_ec")
	sp.mode = int(tr.get("mode", 0))
	sp.uv_scroll = _v2(e.get("emuv"), Vector2.ZERO)
	sp.arbitrary = e.get("prim", "") == "atrail"
	sp.emit_life = float(e.get("life", -1.0))
	var off := _v3(e.get("pos", [0, 0, 0]))
	var sh = e.get("shape")
	if sh is Dictionary and sh.get("type", "") == "offset":
		off += _v3(sh.get("offset", [0, 0, 0]))
	sp.offset = off
	sp.mat = LolTrail.mat_for(sp.texture, sp.tex2, sp.blend)
	e["_tspec"] = sp
	return sp


func _build_trail(e: Dictionary) -> void:
	var sp := _trail_spec(e)
	var t := LolTrail.new()
	t.life = sp.life
	t.width = sp.width
	t.width_curve = sp.width_curve
	t.color = sp.color
	t.birth_colors = sp.birth_colors
	t.color_curve = sp.color_curve
	t.blend = sp.blend
	t.texture = sp.texture
	t.tex2 = sp.tex2
	t.tiling = sp.tiling
	t.tiling_ec = sp.tiling_ec
	t.mode = sp.mode
	t.uv_scroll = sp.uv_scroll
	t.arbitrary = sp.arbitrary
	t.emit_life = sp.emit_life
	t.material_override = sp.mat
	t.offset = sp.offset
	if _anchor == null and _mis_frame == null and not _is_ground(e):
		t.offset.y += float(_opts.get("center", 0.0)) / maxf(scale.y, 0.001)
	_parent_for(e).add_child(t)
	var delay := float(e.get("delay", 0.0))
	if delay > 0.0:
		t.emitting = false
		_after(delay, func():
			if is_instance_valid(t) and not _stopped:
				t.emitting = true)
	var elife: float = float(e.get("life", -1.0))
	if elife > 0.0 and not _loop:
		_after(delay + elife, func():
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


## Child systems spawned for each particle of this emitter (VfxChildParticleSetDefinitionData).
func _build_children(e: Dictionary) -> void:
	var names: Array = e.get("children", [])
	if names.is_empty():
		return
	var single: bool = e.get("single", false)
	var rate: float = float(e.get("rate", 1.0))
	var count := clampi(int(round(rate)) if single else int(ceil(rate * maxf(float(e.get("life", 1.0)), 0.1))), 1, MAX_CHILDREN)
	var plife: Array = e.get("plife", [1.0, 1.0])
	var life: float = float(plife[1]) if float(plife[1]) > 0.0 else -1.0
	var vel := _v3(e.get("bvel", [0, 0, 0]))
	var vq = e.get("bvel_q")
	var acc := _v3(e.get("accel", [0, 0, 0]))
	var drag := _v3(e.get("drag", [0, 0, 0]))
	var interval := 0.0 if single else 1.0 / maxf(rate, 0.01)
	var delay := float(e.get("delay", 0.0))
	for i in count:
		var nm: String = names[i % names.size()]
		var at := delay + interval * i
		_after(at, func():
			if _stopped or not is_inside_tree():
				return
			var carrier := Node3D.new()
			carrier.position = _v3(e.get("pos", [0, 0, 0]))
			if not _is_ground(e) and _anchor == null:
				carrier.position.y += float(_opts.get("center", 0.0))
			_parent_for(e).add_child(carrier)
			var v := vel
			if vq is Array and not vq.is_empty():
				var row: Array = vq[randi() % vq.size()]
				v = Vector3(vel.x * float(row[0]), vel.y * float(row[1] if row.size() > 1 else 1.0), vel.z * float(row[2] if row.size() > 2 else 1.0))
			var child := LolVfx.make(nm, {"loop": _loop or life < 0.0, "max_life": life if life > 0.0 else MAX_ONESHOT})
			if child == null:
				carrier.queue_free()
				return
			child._host = _host
			carrier.add_child(child)
			_carriers.append({"node": child, "carrier": carrier, "vel": v, "acc": acc, "drag": drag, "age": 0.0, "life": life}))


func _tick_carriers(dt: float) -> void:
	var i := 0
	while i < _carriers.size():
		var c: Dictionary = _carriers[i]
		var car = c.carrier
		if not is_instance_valid(car):
			_carriers.remove_at(i)
			continue
		c.age += dt
		var v: Vector3 = c.vel
		v += c.acc * dt
		v -= v * (c.drag * dt).clamp(Vector3.ZERO, Vector3.ONE)
		c.vel = v
		if v.length_squared() > 0.0:
			car.position += v * dt
		if c.life > 0.0 and c.age >= c.life and is_instance_valid(c.node) and not c.get("stopped", false):
			c["stopped"] = true
			c.node.stop()
		i += 1


## VfxPrimitiveAttachedMesh: a shell of the host unit's skinned mesh drawn with this emitter's material.
func _build_amesh(e: Dictionary) -> void:
	if _host == null or not is_instance_valid(_host) or e.get("tex") == null:
		return
	var model = _host.get("model")
	if not (model is Node3D):
		return
	var mat := _material(e, true)
	var plife: Array = e.get("plife", [1.0, 1.0])
	var life: float = float(plife[1])
	var delay := float(e.get("delay", 0.0))
	var src: Array = []
	_collect_skinned(model, src)
	if src.is_empty():
		return
	_after(delay, func():
		if _stopped:
			return
		for mi in src:
			if not is_instance_valid(mi):
				continue
			var sh := MeshInstance3D.new()
			sh.mesh = mi.mesh
			sh.skin = mi.skin
			sh.material_override = mat
			sh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mi.get_parent().add_child(sh)
			sh.transform = mi.transform
			sh.skeleton = sh.get_path_to(mi.get_node(mi.skeleton)) if mi.skeleton != NodePath() and mi.has_node(mi.skeleton) else NodePath()
			_ameshes.append([sh, e.get("color"), _col(e.get("bcolor", [1, 1, 1, 1])), life, _t]))


static func _collect_skinned(n: Node, out: Array) -> void:
	if n is MeshInstance3D and n.visible and n.mesh != null:
		out.append(n)
	for c in n.get_children():
		if not (c is LolVfx):
			_collect_skinned(c, out)


func _tick_ameshes() -> void:
	var i := 0
	while i < _ameshes.size():
		var a: Array = _ameshes[i]
		var sh = a[0]
		if not is_instance_valid(sh):
			_ameshes.remove_at(i)
			continue
		var life: float = float(a[3])
		var age := _t - float(a[4])
		var k := clampf(age / life, 0.0, 1.0) if life > 0.0 else 0.0
		var c: Color = a[2]
		if a[1] is Dictionary:
			c *= _sample_color_curve(a[1], k)
		if _stopped:
			c.a *= clampf(1.0 - (_t - _stop_t) / 0.3, 0.0, 1.0)
		sh.set_instance_shader_parameter("tint", c)
		if (life > 0.0 and age >= life) or (_stopped and _t - _stop_t > 0.3):
			sh.queue_free()
			_ameshes.remove_at(i)
			continue
		i += 1


static func _v3(a) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


static func _col(a) -> Color:
	if a is Array and a.size() >= 4:
		return Color(float(a[0]), float(a[1]), float(a[2]), float(a[3]))
	return Color.WHITE


static var _texc := {}


static func _tex(path) -> Texture2D:
	if path == null or not (path is String):
		return null
	if _texc.has(path):
		return _texc[path]
	var t: Texture2D = Assets.tex(path) if ResourceLoader.exists(path) else null
	_texc[path] = t
	return t


static func _curve_x(cur) -> Array:
	## 16 samples of the X component of an over-life curve, or [] when constant
	if not (cur is Dictionary) or not cur.has("t"):
		return []
	var out: Array = []
	for i in 16:
		var v = _curve_vec(cur, i / 15.0)
		out.append(float(v[0]) if v is Array else float(v))
	return out


# ----------------------------------------------------------------- orientation / meshes
## 0 camera billboard, 1 free quad, 2 ground decal, 3 mesh, 4 velocity aligned billboard, 5 ray
static func _orient(e: Dictionary) -> int:
	var prim: String = e.get("prim", "quad")
	if prim == "mesh":
		return 3
	if e.get("ground", false) or prim == "proj":
		return 2   # ground layer / planar projection onto the terrain
	if prim == "aquad":
		return 1
	if prim == "ray":
		return 5
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
		mesh = _vmesh(String(e.mesh))
		if mesh == null:
			var src = load(e.mesh) if ResourceLoader.exists(e.mesh) else null
			mesh = src if src is Mesh else QuadMesh.new()
	else:
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		if o == 2:
			q.orientation = PlaneMesh.FACE_Y
		elif o == 5:
			q.center_offset = Vector3(0, 0.5, 0)   # rays start at the particle and extend along its axis
		mesh = q
	_meshes[key] = mesh
	return mesh


## Particle mesh with League vertex colors (incl. alpha) from the extractor's <mesh>.vmesh.json sidecar.
static func _vmesh(obj_path: String) -> Mesh:
	var jp := obj_path.get_basename() + ".vmesh.json"
	if not FileAccess.file_exists(jp):
		return null
	var d = JSON.parse_string(FileAccess.get_file_as_string(jp))
	if not (d is Dictionary) or not (d.get("v") is Array):
		return null
	var v: Array = d.v
	var nrm: Array = d.get("n", [])
	var uv: Array = d.get("uv", [])
	var col = d.get("c")
	var n := v.size() / 3
	var pv := PackedVector3Array()
	var pn := PackedVector3Array()
	var pu := PackedVector2Array()
	var pc := PackedColorArray()
	pv.resize(n)
	pn.resize(n)
	pu.resize(n)
	for i in n:
		pv[i] = Vector3(v[i * 3], v[i * 3 + 1], v[i * 3 + 2])
		if nrm.size() >= (i + 1) * 3:
			pn[i] = Vector3(nrm[i * 3], nrm[i * 3 + 1], nrm[i * 3 + 2])
		if uv.size() >= (i + 1) * 2:
			pu[i] = Vector2(uv[i * 2], uv[i * 2 + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pv
	arrays[Mesh.ARRAY_NORMAL] = pn
	arrays[Mesh.ARRAY_TEX_UV] = pu
	if col is Array and col.size() >= n * 4:
		pc.resize(n)
		for i in n:
			pc[i] = Color(col[i * 4], col[i * 4 + 1], col[i * 4 + 2], col[i * 4 + 3])
		arrays[Mesh.ARRAY_COLOR] = pc
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return am


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
	var csc := _v2(e.get("cscale"), Vector2.ONE)
	var cof := _v2(e.get("coff"), Vector2.ZERO)
	var img: Image = null
	if ctex != null:
		var t := _tex(ctex)
		if t != null:
			img = t.get_image()
			if img != null and img.is_compressed():
				img = img.duplicate()
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
			var ux := clampf(u * csc.x + cof.x, 0.0, 1.0)
			var uy := clampf(u * csc.y + cof.y, 0.0, 1.0)
			var px := w / 2
			var py := h / 2
			if int(ctype[1]) == 3 and int(ctype[0]) != 3:
				py = clampi(int(uy * (h - 1)), 0, h - 1)
			else:
				px = clampi(int(ux * (w - 1)), 0, w - 1)
				if int(ctype[1]) == 3:
					py = clampi(int(uy * (h - 1)), 0, h - 1)
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
static func _shader(blend: int, distort := false, bias := false, solid := false) -> Shader:
	# League blendMode (from texture statistics over all champions): 0 (default) / 2 / 4 = additive,
	# 1 = alpha blend, 3 = solid (opaque meshes: rocks, rockets, relic icons), 5 = premultiplied alpha
	var mode := "blend_add"
	match blend:
		1, 3: mode = "blend_mix"
		5: mode = "blend_premul_alpha"
	if distort:
		mode = "blend_mix"
	var key := mode + ("|d" if distort else "") + ("|b" if bias else "") + ("|s" if solid else "")
	if _shaders.has(key):
		return _shaders[key]
	var hint := "" if mode == "blend_add" else "source_color,"
	var modes := "unshaded, cull_disabled, depth_draw_always" if solid else "unshaded, cull_disabled, depth_draw_never"
	var defs := ("#define DISTORT\n" if distort else "") + ("#define DEPTH_BIAS\n" if bias else "") + ("#define SOLID\n" if solid else "")
	var code := FileAccess.get_file_as_string("res://src/vfx/lol_particle.gdshader.txt").replace("__BLEND__", mode).replace("__TEXHINT__", hint).replace("__DEFINES__", defs).replace("__MODES__", modes)
	var sh := Shader.new()
	sh.code = code
	_shaders[key] = sh
	return sh


static func _v2(a, d: Vector2) -> Vector2:
	if a is Array and a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return d


static func _material(e: Dictionary, amesh := false) -> ShaderMaterial:
	var ek := "_mata" if amesh else "_mat"
	var em = e.get(ek)
	if em is ShaderMaterial:
		return em
	var key := "mat|%s|%s" % [amesh, JSON.stringify([e.get("tex"), e.get("blend"), _orient(e), e.get("texdiv"), e.get("frames"),
			e.get("alpha_ref"), e.get("uvscale"), e.get("uvrate"), e.get("uvint"), e.get("tex2"), e.get("uv2scale"), e.get("uv2rate"),
			e.get("uv2int"), e.get("ero_tex"), e.get("ero_curve"), e.get("ero_ch"), e.get("soft"), e.get("pass"), e.get("plife"),
			e.get("uvrot"), e.get("uvrotrate"), e.get("uvclamp"), e.get("uv2rot"), e.get("uv2off"), e.get("uv2clamp"), e.get("flip"),
			e.get("fresnel"), e.get("falloff"), e.get("dbias"), e.get("distort"), e.get("ground"), e.get("soft_in"), e.get("uvmode"), e.get("palette"), e.get("uvoff")])]
	if _mats.has(key):
		e[ek] = _mats[key]
		return _mats[key]
	var o := _orient(e)
	var mat := ShaderMaterial.new()
	var blend := int(e.get("blend", 0))
	var dist = e.get("distort")
	var is_dist: bool = dist is Dictionary
	# depth bias: League depthBiasFactors (slope, constant in League units) and ground-layer decals
	var db = e.get("dbias")
	var bias := 0.0
	if db is Array and db.size() == 2:
		bias = -float(db[1]) * S
	if o == 2:
		bias = maxf(bias, 0.15)
	if amesh:
		bias = 0.02
	bias = clampf(bias, 0.0, 1.0)
	mat.shader = _shader(blend, is_dist, bias > 0.0, blend == 3 and o == 3 and not amesh)
	if blend == 1 or blend == 3 or blend == 5:
		mat.set_shader_parameter("linear_color", true)
	else:
		mat.set_shader_parameter("intensity", 0.85)   # stacked gamma-emulated additive layers blow out otherwise
	if is_dist:
		mat.set_shader_parameter("tex", _tex(e.get("tex")))
		mat.set_shader_parameter("normal_tex", _tex(dist.get("normal")))
		mat.set_shader_parameter("distort_strength", float(dist.get("strength", 0.1)))
	else:
		mat.set_shader_parameter("tex", _tex(e.get("tex")))
	mat.set_shader_parameter("billboard", 0 if amesh else (1 if o == 0 else (2 if o == 4 or o == 5 else 0)))
	var div: Array = e.get("texdiv", [1, 1])
	var frames := int(e.get("frames", 0))
	if frames <= 0:
		frames = int(div[0]) * int(div[1])
	mat.set_shader_parameter("texdiv", Vector2(maxf(1, float(div[0])), maxf(1, float(div[1]))))
	mat.set_shader_parameter("total_frames", float(frames))
	mat.set_shader_parameter("alpha_ref", float(e.get("alpha_ref", 0)) / 255.0)
	mat.set_shader_parameter("uv_scale", _v2(e.get("uvscale"), Vector2.ONE))
	mat.set_shader_parameter("uv_rate", _v2(e.get("uvrate"), Vector2.ZERO))
	mat.set_shader_parameter("uv_rot", float(e.get("uvrot", 0.0)))
	mat.set_shader_parameter("uv_rot_rate", float(e.get("uvrotrate", 0.0)))
	mat.set_shader_parameter("uv_clamp", bool(e.get("uvclamp", false)))
	# uvMode 2 is not an alpha lock: locking alpha froze Annie Q's scrolling flame mesh into a flat oval
	mat.set_shader_parameter("alpha_lock", false)
	var uo2 = e.get("uvoff")
	if uo2 is Array and uo2.size() == 2 and frames <= 1 and (_v2(uo2[0], Vector2.ZERO) != Vector2.ZERO or _v2(uo2[1], Vector2.ZERO) != Vector2.ZERO):
		mat.set_shader_parameter("uv_off_pack", true)
	var pal = e.get("palette")
	if pal is Dictionary and _tex(pal.get("tex")) != null:
		mat.set_shader_parameter("palette_tex", _tex(pal.get("tex")))
		mat.set_shader_parameter("has_palette", true)
		var cnt := maxf(float(pal.get("count", 1)), 1.0)
		mat.set_shader_parameter("palette_v", (clampf(float(pal.get("row", 0.0)), 0.0, cnt - 1.0) + 0.5) / cnt)
	var fl: Array = e.get("flip", [false, false])
	mat.set_shader_parameter("uv_flip", Vector2(1.0 if fl[0] else 0.0, 1.0 if fl[1] else 0.0))
	var plife: Array = e.get("plife", [1.0, 1.0])
	mat.set_shader_parameter("life_max", maxf(float(plife[1]), 0.05))
	var t2 := _tex(e.get("tex2"))
	if t2 != null:
		mat.set_shader_parameter("tex2", t2)
		mat.set_shader_parameter("has_tex2", true)
		mat.set_shader_parameter("uv2_scale", _v2(e.get("uv2scale"), Vector2.ONE))
		mat.set_shader_parameter("uv2_rate", _v2(e.get("uv2rate"), Vector2.ZERO))
		mat.set_shader_parameter("uv2_off", _v2(e.get("uv2off"), Vector2.ZERO))
		mat.set_shader_parameter("uv2_rot", float(e.get("uv2rot", 0.0)))
		mat.set_shader_parameter("uv2_clamp", bool(e.get("uv2clamp", false)))
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
	if e.get("soft", false) and o != 2 and not amesh:
		mat.set_shader_parameter("soft_dist", clampf(float(e.get("soft_in", 0.35)), 0.1, 1.0))
	var fr = e.get("fresnel")
	if fr is Dictionary and (o == 3 or amesh):
		var fc := _col(fr.get("color", [0, 0, 0, 0]))
		if fc.r + fc.g + fc.b > 0.01 or (amesh and blend == 1):
			mat.set_shader_parameter("fresnel_color", fc)
			# League "fresnel" is the rim width: 0.15 = thin rim, 1 = broad
			mat.set_shader_parameter("fresnel_pow", clampf(1.0 / maxf(float(fr.get("f", 0.2)), 0.05) * 0.5, 0.8, 8.0))
			# alpha-blended attached-mesh shells are rim lights, not opaque silhouettes (Annie stun, Ahri Q/W)
			mat.set_shader_parameter("rim_alpha", amesh and blend == 1)
	var ft := _tex(e.get("falloff"))
	if ft != null and (o == 3 or amesh):
		mat.set_shader_parameter("falloff_tex", ft)
		mat.set_shader_parameter("has_falloff", true)
	if amesh:
		mat.set_shader_parameter("normal_push", 0.012)
		if not (blend == 1 or blend == 3 or blend == 5):
			mat.set_shader_parameter("tex_mask", true)
	mat.set_shader_parameter("depth_bias", bias)
	mat.render_priority = clampi(int(e.get("pass", 0)) / 2, -60, 60)
	_mats[key] = mat
	e[ek] = mat
	return mat


static var _proc_shader: Shader = null


static func _vec3_or(a, d: Vector3) -> Vector3:
	if a is Array and a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return d


## League birth scale -> particle scale (meters for quads: League quads are half-extents; multipliers for meshes)
static func _scale_base(e: Dictionary, bs) -> Vector3:
	if not (bs is Array):
		bs = [float(bs), float(bs), float(bs)]
	var o := _orient(e)
	var prim: String = e.get("prim", "quad")
	var bx := absf(float(bs[0]))
	var by := absf(float(bs[1])) if bs.size() > 1 else bx
	var bz := absf(float(bs[2])) if bs.size() > 2 else bx
	var uni: bool = e.get("uniform", false)
	if o == 3:
		return Vector3(bx, by if by > 0.0001 and not uni else bx, bz if bz > 0.0001 and not uni else bx)
	if o == 0:
		return Vector3(bx, bx, 1.0) * S * QUAD_SCALE
	if o == 5:
		# rays: x = width, y / z = length (League units)
		return Vector3(bx * S * QUAD_SCALE, by * S, bz * S)
	var hy := by if (by > 0.01 and not uni and prim == "aquad") else bx
	return Vector3(bx * S * QUAD_SCALE, hy * S * QUAD_SCALE, 1.0)


## Probability-table quantiles -> 32 x 10 lookup (see lol_process.gdshader for the rows).
static func _rand_tex(e: Dictionary) -> ImageTexture:
	var o := _orient(e)
	var rows := {}
	var any := false
	var pq = e.get("plife_q")
	if pq is Array:
		var r0 := []
		for v in pq:
			r0.append(Color(float(v), 1, 1, 1))
		rows[0] = r0
	var uni: bool = e.get("uniform", false) or o == 0
	var maps := {1: "bscale_q", 2: "bvel_q", 5: "bcolor_q", 8: "orbit_q", 9: "drag_q"}
	for row in maps:
		var qv = e.get(maps[row])
		if not (qv is Array):
			continue
		var r := []
		for v in qv:
			var a: Array = v
			var c := Color(float(a[0]), float(a[1]) if a.size() > 1 else 1.0, float(a[2]) if a.size() > 2 else 1.0,
					float(a[3]) if a.size() > 3 else 1.0)
			if row == 1:
				if o == 0 or uni:
					c = Color(c.r, c.r, 1.0, 1.0)
				elif o != 3:
					c = Color(c.r, c.g if e.get("prim", "") == "aquad" else c.r, 1.0, 1.0)
			r.append(c)
		rows[row] = r
	var rq = e.get("brot_q")
	if rq is Array:
		var r3 := []
		for v in rq:
			var a3: Array = v
			if o == 0 or o == 4:
				r3.append(Color(1, 1, float(a3[0]), 1))
			elif o == 2:
				var k := 0 if e.get("prim", "quad") == "quad" else 2
				r3.append(Color(1, 1, float(a3[k]), 1))
			else:
				r3.append(Color(float(a3[0]), float(a3[1]), float(a3[2]), 1))
		rows[3] = r3
	var vq = e.get("rotvel_q")
	if vq is Array:
		var rv := _vec3_or(e.get("rotvel"), Vector3.ZERO)
		var si := _spin_axis(rv)
		if o == 0 or o == 4:
			si = 0
		var r4 := []
		for v in vq:
			r4.append(Color(float(v[si]), 1, 1, 1))
		rows[4] = r4
	var sh = e.get("shape")
	if sh is Dictionary:
		var oq = sh.get("offset_q")
		if oq is Array:
			var r6 := []
			for v in oq:
				r6.append(Color(float(v[0]), float(v[1]), float(v[2]), 1))
			rows[6] = r6
		var rots = sh.get("rots")
		if rots is Array and not rots.is_empty():
			var r7 := []
			for i in 32:
				var a0: float = float(rots[0].q[i])
				var a1: float = float(rots[1].q[i]) if rots.size() > 1 else 0.0
				r7.append(Color(a0, a1, 0, 1))
			# decorrelate the two angles: second axis uses a shuffled index
			if rots.size() > 1:
				var shuffled := []
				for i in 32:
					shuffled.append(Color(r7[i].r, float(rots[1].q[(i * 13 + 7) % 32]), 0, 1))
				r7 = shuffled
			rows[7] = r7
	if rows.is_empty():
		return null
	var img := Image.create(32, 10, false, Image.FORMAT_RGBAF)
	img.fill(Color(1, 1, 1, 1))
	for row in rows:
		var r: Array = rows[row]
		for i in mini(32, r.size()):
			img.set_pixel(i, row, r[i])
	return ImageTexture.create_from_image(img)


static func _spin_axis(rv: Vector3) -> int:
	if absf(rv.y) >= absf(rv.x) and absf(rv.y) >= absf(rv.z):
		return 1
	elif absf(rv.z) > absf(rv.x):
		return 2
	return 0


## Emitter-time birth curves (16 samples): row 0 color, 1 scale (final units), 2 velocity.
static func _birth_tex(e: Dictionary) -> ImageTexture:
	var bc = e.get("bcolor_ec")
	var bs = e.get("bscale_ec")
	var bv = e.get("bvel_ec")
	if not (bc is Array) and not (bs is Array) and not (bv is Array):
		return null
	var img := Image.create(16, 3, false, Image.FORMAT_RGBAF)
	img.fill(Color(1, 1, 1, 1))
	for i in 16:
		if bc is Array and i < bc.size():
			img.set_pixel(i, 0, _col(bc[i]))
		if bs is Array and i < bs.size():
			var s := _scale_base(e, bs[i])
			img.set_pixel(i, 1, Color(s.x, s.y, s.z, 1))
		if bv is Array and i < bv.size():
			var v := _v3(bv[i])
			img.set_pixel(i, 2, Color(v.x, v.y, v.z, 1))
	return ImageTexture.create_from_image(img)


static func _process_material(e: Dictionary, single: bool, life_scale: float, burst: bool) -> ShaderMaterial:
	# cached by the caller (_particle_spec stores it on the emitter)
	if _proc_shader == null:
		_proc_shader = load("res://src/vfx/lol_process.gdshader")
	var pm := ShaderMaterial.new()
	pm.shader = _proc_shader
	var o := _orient(e)
	var prim: String = e.get("prim", "quad")
	pm.set_shader_parameter("orient", o)
	pm.set_shader_parameter("rot_order", ROT_ORDER)
	pm.set_shader_parameter("life_scale", life_scale)
	# random tables / birth curves
	var rt := _rand_tex(e)
	if rt != null:
		pm.set_shader_parameter("rand_lut", rt)
		pm.set_shader_parameter("has_rand", true)
	var bt := _birth_tex(e)
	if bt != null:
		pm.set_shader_parameter("birth_lut", bt)
		pm.set_shader_parameter("has_birth_color", e.get("bcolor_ec") is Array)
		pm.set_shader_parameter("has_birth_scale", e.get("bscale_ec") is Array)
		pm.set_shader_parameter("has_birth_vel", e.get("bvel_ec") is Array)
		var elife: float = float(e.get("life", -1.0))
		pm.set_shader_parameter("emit_life", elife if elife > 0.0 else 1.0)
		pm.set_shader_parameter("birth_live", single)
		pm.set_shader_parameter("emit_rate", 0.0 if (single or burst or elife <= 0.0) else float(e.get("rate", 0.0)))
	# emission shape
	var sh = e.get("shape")
	if sh is Dictionary:
		var fl := int(sh.get("flags", 0))
		match str(sh.get("type", "")):
			"sphere":
				pm.set_shader_parameter("shape_type", 1)
				pm.set_shader_parameter("shape_radius", float(sh.get("radius", 0.0)))
				pm.set_shader_parameter("shape_radial", fl & 1 != 0)
			"box":
				var sz: Array = sh.get("size", [0, 0, 0])
				pm.set_shader_parameter("shape_type", 2)
				pm.set_shader_parameter("shape_box", Vector3(float(sz[0]), float(sz[1]), float(sz[2])) * 0.5)
			"cyl":
				pm.set_shader_parameter("shape_type", 3)
				pm.set_shader_parameter("shape_radius", float(sh.get("radius", 0.0)))
				pm.set_shader_parameter("shape_height", float(sh.get("height", 0.0)))
				pm.set_shader_parameter("shape_radial", fl & 1 != 0)
			"offset":
				pm.set_shader_parameter("shape_offset", _v3(sh.get("offset", [0, 0, 0])))
				var rots = sh.get("rots")
				if rots is Array and not rots.is_empty():
					pm.set_shader_parameter("emit_rots", rots.size())
					pm.set_shader_parameter("emit_axis0", _v3(rots[0].axis))
					if rots.size() > 1:
						pm.set_shader_parameter("emit_axis1", _v3(rots[1].axis))
	# velocity / forces
	pm.set_shader_parameter("vel_base", _v3(e.get("bvel", [0, 0, 0])))
	pm.set_shader_parameter("drag", _vec3_or(e.get("drag"), Vector3.ZERO).abs())
	var fields: Dictionary = e.get("fields", {})
	var acc := _v3(e.get("accel", [0, 0, 0])) + _v3(fields.get("accel", [0, 0, 0]))
	pm.set_shader_parameter("accel", acc)
	pm.set_shader_parameter("laccel", _v3(e.get("laccel", [0, 0, 0])))
	var ob := _v3(e.get("orbit", [0, 0, 0]))
	pm.set_shader_parameter("orbit", Vector3(-ob.x, -ob.y, ob.z))   # angular velocity under the z mirror
	if fields.has("noise"):
		var nz: Dictionary = fields.noise
		var ax := _v3(nz.get("axis", [1, 1, 1])).abs()
		pm.set_shader_parameter("noise", Vector4(ax.x, ax.y, ax.z, float(nz.get("delta", 0.0))))
		pm.set_shader_parameter("noise_freq", float(nz.get("freq", 1.0)))
	if fields.has("attract"):
		var at: Dictionary = fields.attract
		var ap := _v3(at.get("pos", [0, 0, 0]))
		pm.set_shader_parameter("attract", Vector4(ap.x, ap.y, ap.z, float(at.get("accel", 0.0))))
	if fields.has("drag"):
		pm.set_shader_parameter("field_drag", float(fields.drag))
	if e.has("dvs"):
		pm.set_shader_parameter("dir_stretch", Vector2(float(e.dvs), float(e.get("dvmin", 0.0))))
	# scale
	var bs: Array = e.get("bscale", [1, 1, 1])
	pm.set_shader_parameter("scale_base", _scale_base(e, bs))
	var uni: bool = e.get("uniform", false)
	pm.set_shader_parameter("uniform_scale", uni or o == 0)
	var stex := _scale_tex(e)
	if stex != null:
		pm.set_shader_parameter("scale_curve", stex)
		pm.set_shader_parameter("has_scale_curve", true)
	# rotation: League stores the billboard roll in X; meshes / free quads use full euler (mirrored for the z flip)
	var rot := _vec3_or(e.get("brot"), Vector3.ZERO)
	var rv := _vec3_or(e.get("rotvel"), Vector3.ZERO)
	var spin_i := _spin_axis(rv)
	if o == 0 or o == 4:
		pm.set_shader_parameter("rot_base", Vector3(0, 0, rot.x))
		pm.set_shader_parameter("spin_base", rv.x)
	elif o == 2:
		var k := 0 if prim == "quad" else 2
		pm.set_shader_parameter("rot_base", Vector3(0, 0, rot[k]))
		pm.set_shader_parameter("spin_base", rv[spin_i])
	else:
		pm.set_shader_parameter("rot_base", Vector3(-rot.x, -rot.y, rot.z))
		pm.set_shader_parameter("spin_axis", spin_i)
		pm.set_shader_parameter("spin_base", rv[spin_i] * (-1.0 if spin_i < 2 else 1.0))
	# color
	var bc := _col(e.get("bcolor", [1, 1, 1, 1]))
	if e.get("bcolor_ec") is Array:
		bc = Color.WHITE
	pm.set_shader_parameter("color_base", bc)
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
	if uo is Array and uo.size() == 2 and frames <= 1 and (_v2(uo[0], Vector2.ZERO) != Vector2.ZERO or _v2(uo[1], Vector2.ZERO) != Vector2.ZERO):
		pm.set_shader_parameter("uv_off_lo", _v2(uo[0], Vector2.ZERO))
		pm.set_shader_parameter("uv_off_hi", _v2(uo[1], Vector2.ZERO))
		pm.set_shader_parameter("uv_off_pack", true)
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
