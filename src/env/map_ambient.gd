class_name MapAmbient
extends Node3D
## Howling Abyss ambient life, all from League data:
##  - every environment particle placement of Map12 (base.materials.bin: braziers, wind-blown snow, snow sparkles,
##    gem glows, chimney smoke, abyss clouds, god rays) as LolVfx systems from data/vfx/map12.json
##    (tools/lol/extract_vfx.py --map), spawned/freed around the camera so only nearby systems cost anything
##  - poros at the map's PoroSpwan locators: idle, hop around, scurry away from champions
##  - brush interaction (League Wall_of_Grass): units spread the blades, brush around the player turns see-through

const PARTICLES_JSON := "res://data/map/map12_particles.json"
const SPAWN_R := 40.0
const FREE_R := 50.0
const SKIP_PREFIX := ["HA_Audio_Emitter", "HA_Order_Inhibitor", "HA_Chaos_Inhibitor",
		# wind-streak mesh systems: LolVfx currently draws their scrolling streak texture as flat bright wedges
		# (same symptom as the snow quads below); re-enable once the particle renderer handles them
		"HA_Env_bridgeWind", "HA_Env_hightWind", "HA_Env_lowWind", "HA_Env_highWind_belowBridge"]

var match_ref = null
var _placements: Array = []      ## [{system, xform: Transform3D, pos: Vector3, node: LolVfx|null}]
var _check := 0.0
var _poros: Array = []           ## [{node, home, anim, state, t, from, to}]


func setup(m) -> void:
	match_ref = m
	name = "MapAmbient"
	LolVfx.load_set("map12")
	_strip_snow_quads()
	_load_placements()
	_spawn_poros()


## The wind/snow systems' "Snow" quad emitters (texture env_mb_snow_flakes: opaque alpha, faint RGB) currently
## render as solid squares in LolVfx; until the particle renderer handles them, drop those emitters and let the
## camera-following snow (MapBuilder.build_snow) stand in. The wind streak meshes and sparkles stay.
func _strip_snow_quads() -> void:
	for nm in ["HA_Env_Snow_01", "HA_Env_hightWind_01", "HA_Env_lowWind_01"]:
		if not LolVfx._db.has(nm):
			continue
		var d: Dictionary = LolVfx._db[nm]
		var keep: Array = []
		for e in d.get("emitters", []):
			if not String(e.get("tex", "")).ends_with("env_mb_snow_flakes.png"):
				keep.append(e)
		d["emitters"] = keep


func _load_placements() -> void:
	if not FileAccess.file_exists(PARTICLES_JSON):
		return
	var skip_extra: Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ambskip="):   # debug: --ambskip=HA_Env_Snow,HA_Env_hightWind
			skip_extra = Array(a.substr(10).split(","))
	var arr = JSON.parse_string(FileAccess.get_file_as_string(PARTICLES_JSON))
	if not (arr is Array):
		return
	for r in arr:
		var sysname: String = r.system
		var skip := false
		for p in SKIP_PREFIX + skip_extra:
			if sysname.begins_with(p):
				skip = true
		if skip or not LolVfx.has(sysname) or LolVfx._db[sysname].get("emitters", []).is_empty():
			continue
		var x: Array = r.xform
		var pos := G.lol_pos(float(x[12]), float(x[13]), float(x[14]))
		if pos.y < -50.0:
			continue   # parked far below the map (disabled in League)
		# League row-major basis (left-handed) -> Godot: flip z of every axis and the z axis itself
		var bx := Vector3(x[0], x[1], -float(x[2]))
		var by := Vector3(x[4], x[5], -float(x[6]))
		var bz := -Vector3(x[8], x[9], -float(x[10]))
		_placements.append({"system": sysname, "xform": Transform3D(Basis(bx, by, bz), pos), "pos": pos, "node": null})


func _process(dt: float) -> void:
	if match_ref == null:
		return
	_check -= dt
	if _check <= 0.0:
		_check = 0.25
		_cull()
	_update_poros(dt)
	_update_brush()


func _focus() -> Vector3:
	var rig = match_ref.camera_rig
	return rig.focus if rig != null else Vector3.ZERO


func _cull() -> void:
	var f := _focus()
	for p in _placements:
		var d := G.flat_dist(f, p.pos)
		var n = p.node
		if n != null and not is_instance_valid(n):
			p.node = null
			n = null
		if n == null and d < SPAWN_R:
			var v := LolVfx.make(p.system, {"loop": true})
			if v != null:
				add_child(v)
				v.global_transform = p.xform
				p.node = v
		elif n != null and d > FREE_R:
			n.queue_free()
			p.node = null


# ===================================================================== brush
func _update_brush() -> void:
	var gm: ShaderMaterial = MapBuilder.grass_material
	if gm == null:
		return
	var f := _focus()
	var cands: Array = []
	for u in match_ref.units:
		if u.dead or u.kind == G.Kind.TURRET or u.kind == G.Kind.INHIBITOR or u.kind == G.Kind.NEXUS:
			continue
		var d := G.flat_dist(f, u.global_position)
		if d < 30.0:
			cands.append([d, u])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	var arr: Array = []
	for i in 12:
		if i < cands.size():
			var p: Vector3 = cands[i][1].global_position
			arr.append(Vector4(p.x, p.y, p.z, 1.0))
		else:
			arr.append(Vector4(0, 0, 0, 0))
	gm.set_shader_parameter("pushers", arr)
	var pl = G.player
	var st := Vector4.ZERO
	if pl != null and is_instance_valid(pl) and not pl.dead and match_ref.nav != null \
			and match_ref.nav.brush_id(pl.global_position) != 0:
		var pp: Vector3 = pl.global_position
		st = Vector4(pp.x, pp.y, pp.z, 1.0)
	gm.set_shader_parameter("see_through", st)


# ===================================================================== poros
func _spawn_poros() -> void:
	var layout: Dictionary = match_ref.layout
	var nav: NavGrid = match_ref.nav
	for r in layout.get("other", []):
		if not str(r.name).begins_with("PoroSpwan"):
			continue
		var home := G.lol_pos(float(r.pos[0]), float(r.pos[1]), float(r.pos[2]))
		if nav != null:
			home.y = nav.height_at(home)
		var mdl := Assets.unit_model("HA_AP_Poro", 0)
		if mdl == null:
			return
		add_child(mdl)
		mdl.global_position = home
		mdl.rotation.y = G.rng.randf() * TAU
		var ap := Assets._find_anim(mdl)
		var po := {"node": mdl, "home": home, "ap": ap, "state": "idle", "t": G.rng.randf_range(1.0, 6.0),
				"from": home, "to": home, "dur": 1.0}
		_poro_anim(po, "idle1")
		_poros.append(po)


func _poro_anim(po: Dictionary, nm: String) -> void:
	var ap: AnimationPlayer = po.ap
	if ap == null:
		return
	for an in ap.get_animation_list():
		if String(an).to_lower() == nm:
			if ap.current_animation != an:
				ap.play(an, 0.15)
			return


func _update_poros(dt: float) -> void:
	if _poros.is_empty():
		return
	var f := _focus()
	var nav: NavGrid = match_ref.nav
	for po in _poros:
		var n: Node3D = po.node
		var near := G.flat_dist(f, n.global_position) < 45.0
		n.visible = near
		if not near:
			continue
		po.t -= dt
		if po.state == "hop":
			var k: float = clampf(1.0 - po.t / po.dur, 0.0, 1.0)
			var p: Vector3 = po.from.lerp(po.to, k)
			if nav != null:
				p.y = nav.height_at(p)
			n.global_position = p
			if po.t <= 0.0:
				po.state = "idle"
				po.t = G.rng.randf_range(2.5, 7.0)
				_poro_anim(po, "idle1")
			continue
		# scurry away from a nearby champion, otherwise hop around home now and then
		var threat: Vector3 = Vector3.INF
		for c in match_ref.champions:
			if not c.dead and G.flat_dist(c.global_position, n.global_position) < 3.0:
				threat = c.global_position
				break
		if threat != Vector3.INF or po.t <= 0.0:
			var dir: Vector3
			if threat != Vector3.INF:
				dir = G.flat_dir(threat, n.global_position)
			else:
				var ang := G.rng.randf() * TAU
				dir = Vector3(cos(ang), 0, sin(ang))
				var back: Vector3 = po.home - n.global_position
				if Vector3(back.x, 0, back.z).length() > 2.0:
					dir = G.flat_dir(n.global_position, po.home)
			var dist := G.rng.randf_range(1.0, 2.2)
			var to: Vector3 = n.global_position + dir * dist
			if nav != null and not nav.is_walkable(to):
				to = n.global_position - dir * dist * 0.5
			po.from = n.global_position
			po.to = to
			po.dur = dist / 2.6
			po.t = po.dur
			po.state = "hop"
			n.look_at(Vector3(to.x, n.global_position.y, to.z), Vector3.UP, true)
			_poro_anim(po, "run")
