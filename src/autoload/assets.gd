class_name Assets
extends RefCounted
## Asset loading: models (converted from League files), icons, fonts, shaders.

const CHAMP_SHADER := preload("res://src/vfx/shaders/champion.gdshader")
const INK_SHADER := preload("res://src/vfx/shaders/champion_ink.gdshader")
const INK_OUTLINE := false   ## League has no character outline pass (docs/LEAGUE_SHADERS.md)

static var _scene_cache := {}
static var _mat_cache := {}
static var _tex_cache := {}
static var _font_cache := {}
static var _sidecar_cache := {}


static func champion_model_path(alias: String, skin: int) -> String:
	var low := alias.to_lower()
	var name := low if skin == 0 else "%s_skin%d" % [low, skin]
	return "res://assets/champions/%s/%s.glb" % [low, name]


static func unit_model_path(unit_name: String, skin: int) -> String:
	var low := unit_name.to_lower()
	var name := low if skin == 0 else "%s_skin%d" % [low, skin]
	return "res://assets/units/%s/%s.glb" % [low, name]


static func _load_scene(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path]
	var ps: PackedScene = null
	if ResourceLoader.exists(path):
		ps = load(path)
	_scene_cache[path] = ps
	return ps


static func sidecar(path: String) -> Dictionary:
	var sp := path.get_basename() + ".anims.json"
	if _sidecar_cache.has(sp):
		return _sidecar_cache[sp]
	var d := {}
	if FileAccess.file_exists(sp):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(sp))
		if parsed is Dictionary:
			d = parsed
	_sidecar_cache[sp] = d
	return d


static func champion_model(alias: String, skin: int) -> Node3D:
	var path := champion_model_path(alias, skin)
	if not ResourceLoader.exists(path):
		path = champion_model_path(alias, 0)
	return _instance_model(path, 1.0)


static func unit_model(unit_name: String, skin: int) -> Node3D:
	return _instance_model(unit_model_path(unit_name, skin), 0.0)


static func _instance_model(path: String, self_illum: float) -> Node3D:
	var ps := _load_scene(path)
	if ps == null:
		return null
	var inst: Node3D = ps.instantiate()
	var meta := sidecar(path)
	var holder := Node3D.new()
	holder.name = "Model"
	holder.add_child(inst)
	var sc: float = float(meta.get("skin_scale", 1.0))
	if sc <= 0.0:
		sc = 1.0
	inst.scale = Vector3.ONE * sc
	holder.set_meta("anim_aliases", meta.get("aliases", {}))
	_apply_materials(inst, self_illum)
	_setup_anim_player(inst)
	return holder


static func _apply_materials(n: Node, self_illum: float) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.name.begins_with("HIDDEN__") or String(mi.name).contains("Rubble"):
			mi.visible = false
		if mi.mesh != null:
			for i in mi.mesh.get_surface_count():
				var src := mi.mesh.surface_get_material(i)
				# turret rubble submeshes are placement-specific in League (hidden on the Abyss)
				if src != null and src.resource_name.contains("Rubble"):
					mi.set_surface_override_material(i, _hidden_material())
					continue
				mi.set_surface_override_material(i, _champion_material(src, self_illum))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in n.get_children():
		_apply_materials(c, self_illum)


static var _hidden_mat: Material = null


static func _hidden_material() -> Material:
	if _hidden_mat == null:
		var sm := StandardMaterial3D.new()
		sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		sm.albedo_color = Color(0, 0, 0, 0)
		sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_hidden_mat = sm
	return _hidden_mat


static func _champion_material(src: Material, self_illum: float) -> Material:
	var key := src
	if _mat_cache.has(key):
		return _mat_cache[key]
	var sm := ShaderMaterial.new()
	sm.shader = CHAMP_SHADER
	var tex: Texture2D = null
	var masked := false
	if src is BaseMaterial3D:
		var bm := src as BaseMaterial3D
		tex = bm.albedo_texture
		masked = bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR or bm.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA
	if tex != null:
		sm.set_shader_parameter("albedo_tex", tex)
	sm.set_shader_parameter("use_alpha_scissor", masked)
	sm.set_shader_parameter("self_illum", 0.6 if self_illum > 0.0 else 0.55)
	# League has no character outline pass (decompiled shader cache: only the hover outline exists); silhouette
	# darkness is painted into the textures. The inverted-hull ink stays available behind INK_OUTLINE.
	if not INK_OUTLINE:
		_mat_cache[key] = sm
		return sm
	var ink := ShaderMaterial.new()
	ink.shader = INK_SHADER
	if tex != null:
		ink.set_shader_parameter("albedo_tex", tex)
	ink.set_shader_parameter("use_alpha_scissor", masked)
	if self_illum <= 0.0:
		ink.set_shader_parameter("thickness", 0.0012)
	sm.next_pass = ink
	_mat_cache[key] = sm
	return sm


static func _setup_anim_player(root: Node) -> void:
	var ap := _find_anim(root)
	if ap == null:
		return
	ap.playback_default_blend_time = 0.12
	for lib_name in ap.get_animation_library_list():
		var lib := ap.get_animation_library(lib_name)
		for an in lib.get_animation_list():
			var a := lib.get_animation(an)
			var low := String(an).to_lower()
			if _is_loop_name(low):
				a.loop_mode = Animation.LOOP_LINEAR
	_ensure_reset(ap, root)


static func _is_loop_name(low: String) -> bool:
	for k in ["idle", "run", "dance", "channel", "_loop", "stunned", "knockup", "recall", "walk"]:
		if low.find(k) >= 0 and low.find("_in") < 0 and low.find("windup") < 0 and low.find("wndup") < 0 \
				and low.find("_out") < 0 and low.find("winddown") < 0 and low.find("leadout") < 0:
			return true
	return false


## Build a RESET animation holding the rest pose of every bone, so bones that a clip does not
## animate fall back to the rest pose (the converter omits tracks equal to the bind pose).
static func _ensure_reset(ap: AnimationPlayer, root: Node) -> void:
	var lib := ap.get_animation_library("")
	if lib == null or lib.has_animation("RESET"):
		return
	var skel := _find_skeleton(root)
	if skel == null:
		return
	var a := Animation.new()
	a.length = 0.001
	var path_prefix := String(ap.get_node(ap.root_node).get_path_to(skel))
	for b in skel.get_bone_count():
		var rest := skel.get_bone_rest(b)
		var bn := skel.get_bone_name(b)
		var np := NodePath(path_prefix + ":" + bn)
		var tp := a.add_track(Animation.TYPE_POSITION_3D)
		a.track_set_path(tp, np)
		a.position_track_insert_key(tp, 0.0, rest.origin)
		var tr := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(tr, np)
		a.rotation_track_insert_key(tr, 0.0, rest.basis.get_rotation_quaternion())
		var ts := a.add_track(Animation.TYPE_SCALE_3D)
		a.track_set_path(ts, np)
		a.scale_track_insert_key(ts, 0.0, rest.basis.get_scale())
	lib.add_animation("RESET", a)
	ap.deterministic = true


static func _find_anim(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var r := _find_anim(c)
		if r != null:
			return r
	return null


static func _find_skeleton(n: Node) -> Skeleton3D:
	if n is Skeleton3D:
		return n
	for c in n.get_children():
		var r := _find_skeleton(c)
		if r != null:
			return r
	return null


static func find_skeleton(n: Node) -> Skeleton3D:
	return _find_skeleton(n)


static var _stride_cache := {}
static var _extra_libs := {}


## Drop non-finite keys: some League compressed transition clips decode to NaN on a few frames,
## which makes the mixer blend NaN quaternions ("end quaternion must be normalized").
static func _sanitize_animation(a: Animation) -> void:
	for t in range(a.get_track_count() - 1, -1, -1):
		var ty := a.track_get_type(t)
		if ty != Animation.TYPE_ROTATION_3D and ty != Animation.TYPE_POSITION_3D and ty != Animation.TYPE_SCALE_3D:
			continue
		for k in range(a.track_get_key_count(t) - 1, -1, -1):
			var v = a.track_get_key_value(t, k)
			var ok := true
			if v is Quaternion:
				ok = is_finite(v.x) and is_finite(v.y) and is_finite(v.z) and is_finite(v.w) and v.length() > 0.5
			elif v is Vector3:
				ok = v.is_finite()
			if not ok:
				a.track_remove_key(t, k)
		if a.track_get_key_count(t) == 0:
			a.remove_track(t)


## Merge the companion clip library (League transition / unnamed graph clips that the main .glb
## omits; tools/lol/extract_anim_clips.py) into the model's AnimationPlayer as library "x".
static func merge_extra_clips(ap: AnimationPlayer, alias: String) -> void:
	if alias == "" or ap.has_animation_library("x"):
		return
	var key := alias.to_lower()
	if not _extra_libs.has(key):
		var lib: AnimationLibrary = null
		var ps := _load_scene("res://data/anim/clips/%s.glb" % key)
		if ps != null:
			var inst := ps.instantiate()
			var xap := _find_anim(inst)
			if xap != null and xap.has_animation_library(""):
				lib = xap.get_animation_library("").duplicate()
				if lib.has_animation("RESET"):
					lib.remove_animation("RESET")
				for an in lib.get_animation_list():
					_sanitize_animation(lib.get_animation(an))
			inst.free()
		_extra_libs[key] = lib
	var l: AnimationLibrary = _extra_libs[key]
	if l != null:
		ap.add_animation_library("x", l)


## Skeleton-space ground speed (m/s at playback speed 1) of every run-like clip, measured from the
## planted foot (League foot buff bones): during stance the foot moves backwards at the authored
## ground speed, so playback = move_speed / stride gives zero foot sliding. Cached per model file.
## Foot pairs are tried in order (buff bone, foot, ankle) until one actually steps (the super minion's
## buff bones are static but its L_Foot / R_Foot walk); wheeled units (siege minion) use the wheel
## spin bone: ground speed = angular speed * wheel radius (hub height above the ground).
static func run_strides(ap: AnimationPlayer, skel: Skeleton3D) -> Dictionary:
	var key := ""
	if ap.owner != null:
		key = ap.owner.scene_file_path
	if key == "":
		key = str(ap.get_animation_list())
	if _stride_cache.has(key):
		return _stride_cache[key]
	var out := {}
	var by_norm := {}
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i).to_lower().replace("_", "")
		by_norm[n] = i
	var clips: Array = []
	for an in ap.get_animation_list():
		var low := String(an).to_lower()
		if not (low.contains("run") or low.contains("walk") or low.contains("haste")) or low.contains("_in") 				or low.contains("_out") or low.contains("toidle") or low.contains("torun"):
			continue
		var a := ap.get_animation(an)
		if a != null and a.length >= 0.2:
			clips.append(String(an))
	var was_active := ap.active
	ap.active = true
	for pair in [["lbuffboneglbfootloc", "rbuffboneglbfootloc"], ["lfoot", "rfoot"], ["lankle", "rankle"]]:
		if not (by_norm.has(pair[0]) and by_norm.has(pair[1])):
			continue
		for an in clips:
			var st := _foot_stride(ap, skel, an, [by_norm[pair[0]], by_norm[pair[1]]])
			if st > 0.0:
				out[an] = st
		if not out.is_empty():
			break
	if out.is_empty():
		var wheels: Array = []
		for n in by_norm:
			if String(n).contains("wheelspin"):
				wheels.append(by_norm[n])
		if wheels.is_empty():
			for n in by_norm:
				if String(n).contains("wheel"):
					wheels.append(by_norm[n])
		var ground_y := 0.0
		if by_norm.has("buffboneglbgroundloc"):
			ground_y = skel.get_bone_global_rest(by_norm["buffboneglbgroundloc"]).origin.y
		for an in clips:
			var best := 0.0
			for w in wheels:
				best = maxf(best, _wheel_stride(ap, skel, an, w, ground_y))
			if best > 0.0:
				out[an] = best
	ap.stop()
	ap.active = was_active
	_stride_cache[key] = out
	return out


## Planted-foot ground speed of one clip (0 = the bones do not step).
static func _foot_stride(ap: AnimationPlayer, skel: Skeleton3D, an: String, feet: Array) -> float:
	var a := ap.get_animation(an)
	var n_s := 60
	ap.play(an, 0.0, 1.0)
	var tracks := []
	for f in feet:
		tracks.append([])
	for i in n_s + 1:
		var t := a.length * float(i) / float(n_s)
		ap.seek(minf(t, a.length - 0.0001), true)
		for k in feet.size():
			tracks[k].append(skel.get_bone_global_pose(feet[k]).origin)
	var speeds: Array = []
	var dt := a.length / float(n_s)
	for tr in tracks:
		var ymin := INF
		var ymax := -INF
		for p in tr:
			ymin = minf(ymin, p.y)
			ymax = maxf(ymax, p.y)
		if ymax - ymin < 0.04:
			continue   # foot bone does not lift (legless minions, static buff bone)
		var thr := ymin + (ymax - ymin) * 0.12
		for i in range(1, tr.size()):
			if tr[i].y <= thr and tr[i - 1].y <= thr:
				var d := Vector2(tr[i].x - tr[i - 1].x, tr[i].z - tr[i - 1].z).length()
				speeds.append(d / dt)
	if speeds.size() < 4:
		return 0.0
	speeds.sort()
	var med := float(speeds[speeds.size() / 2])
	return med if med > 0.8 and med < 12.0 else 0.0


## Rolling ground speed of a wheel spin bone over one clip (0 = it does not spin).
static func _wheel_stride(ap: AnimationPlayer, skel: Skeleton3D, an: String, bone: int, ground_y: float) -> float:
	var a := ap.get_animation(an)
	var n_s := 60
	ap.play(an, 0.0, 1.0)
	var ang := 0.0
	var prev := Quaternion.IDENTITY
	var hub := 0.0
	for i in n_s + 1:
		ap.seek(minf(a.length * float(i) / float(n_s), a.length - 0.0001), true)
		var q := skel.get_bone_pose_rotation(bone)
		if i > 0:
			ang += prev.angle_to(q)
		prev = q
		hub += skel.get_bone_global_pose(bone).origin.y - ground_y
	var r := hub / float(n_s + 1)
	var spd := ang / a.length * r
	return spd if r > 0.05 and spd > 0.3 and spd < 12.0 else 0.0


## [motion3] Weapon-hold calibration (see core/weapon_hold.gd): for each weapon bone, the hand it rests in
## at idle, its hand-local rest transform, and the stray-distance thresholds measured on the ordinary
## clips. Cached per model file. weapon_names = lower-case bone names.
static var _wh_cache := {}


static func weapon_hold_calibrate(ap: AnimationPlayer, skel: Skeleton3D, weapon_names: Array) -> Array:
	var key := ""
	if ap.owner != null:
		key = ap.owner.scene_file_path
	if key == "":
		key = str(ap.get_animation_list())
	if _wh_cache.has(key):
		return _wh_cache[key]
	var out: Array = []
	var weps: Array = []
	var hands: Array = []
	for i in skel.get_bone_count():
		var n := skel.get_bone_name(i).to_lower()
		if n in weapon_names:
			weps.append(i)
		elif n.contains("hand") and not n.contains("buffbone") and not n.contains("finger") and not n.contains("thumb") 				and not n.contains("parenting") and not n.contains("snap"):
			hands.append(i)
	if weps.is_empty() or hands.is_empty():
		_wh_cache[key] = out
		return out
	var good: Array = []
	var idle := ""
	for an in ap.get_animation_list():
		var low := String(an).to_lower()
		if low.contains("_in") or low.contains("_out") or low.contains("to_") or low.contains("_to") or low.contains("wndup") 				or low.contains("windup") or low.contains("spell"):
			continue
		# idle1 / run / attack / crit are the reference "held" clips (idle2..4 fidgets stray like the casts do)
		if low.begins_with("idle") and idle != "" and low != "idle1":
			continue
		if low.begins_with("idle") or low.begins_with("run") or low.begins_with("attack") or low.begins_with("crit") 				or low.begins_with("walk"):
			good.append(String(an))
			if idle == "" and low.begins_with("idle"):
				idle = String(an)
	if idle == "":
		_wh_cache[key] = out
		return out
	var was_active := ap.active
	ap.active = true
	# hand + hand-local rest transform of each weapon at idle
	ap.play(idle, 0.0, 1.0)
	ap.seek(0.0, true)
	var best_h := {}
	var nominal := {}
	for w in weps:
		var gw := skel.get_bone_global_pose(w)
		var bh := -1
		var bd := INF
		for h in hands:
			var dd := (skel.get_bone_global_pose(h).origin - gw.origin).length()
			if dd < bd:
				bd = dd
				bh = h
		best_h[w] = bh
		nominal[w] = skel.get_bone_global_pose(bh).affine_inverse() * gw
	var maxd := {}
	for w in weps:
		maxd[w] = 0.0
	for an in good:
		var a := ap.get_animation(an)
		ap.play(an, 0.0, 1.0)
		for i in 21:
			ap.seek(minf(a.length * float(i) / 20.0, a.length - 0.0001), true)
			for w in weps:
				var wo := skel.get_bone_global_pose(w).origin
				var d := INF
				for h in hands:   # the weapon may swap hands: distance to the nearest hand
					d = minf(d, (skel.get_bone_global_pose(h).origin - wo).length())
				maxd[w] = maxf(maxd[w], d)
	ap.stop()
	ap.active = was_active
	for w in weps:
		var t1: float = maxd[w] * 1.15 + 0.05
		out.append({"w": w, "h": best_h[w], "hands": hands, "n": nominal[w], "t1": t1, "t2": t1 + maxf(0.2, t1 * 0.25)})
	_wh_cache[key] = out
	return out


## Map logical animation names to available clips.
static func build_anim_map(ap: AnimationPlayer, overrides: Dictionary, aliases: Dictionary = {}) -> Dictionary:
	var out := {}
	if ap == null:
		return out
	var names: Array = []
	for an in ap.get_animation_list():
		if an != "RESET":
			names.append(String(an))
	var lowmap := {}
	for n in names:
		lowmap[_strip_prefix(n.to_lower())] = n
	var model_root := ap.get_parent()
	while model_root != null and not model_root.has_meta("anim_aliases"):
		model_root = model_root.get_parent()
	var al: Dictionary = aliases.duplicate()
	if model_root != null:
		al.merge(model_root.get_meta("anim_aliases"))

	var pick := func(cands: Array) -> Array:
		var res := []
		for c in cands:
			if lowmap.has(c):
				res.append(lowmap[c])
		return res

	out["idle"] = pick.call(["idle1", "idle1_base", "idle_base", "idle", "idle2", "idle1_in", "minigun_idle1", "idle2_base", "idle_1"])
	if out.idle.size() > 1:
		out.idle = [out.idle[0]]
	out["run"] = pick.call(["run", "run_base", "run1", "run2", "minigun_run", "run_fast", "run_haste", "walk"])
	if out.run.size() > 1:
		out.run = [out.run[0]]
	out["run_fast"] = pick.call(["run_haste", "run_fast", "run_fast_loop"])
	out["attack"] = pick.call(["attack1", "attack2", "attack3", "attack4", "attack1_base", "attack2_base", "attack3_base", "minigun_attack1", "minigun_attack2"])
	out["crit"] = pick.call(["crit", "crit_base", "crit2"])
	out["death"] = pick.call(["death", "death_base", "minigun_death"])
	for i in range(1, 5):
		var k := "spell%d" % i
		out[k] = pick.call([k, k + "_base", k + "a", k + "_0", k + "_cast", k + "_in"])
		if out[k].size() > 1:
			out[k] = [out[k][0]]
	out["dance"] = pick.call(["dance_loop", "dance", "dance_base", "dance_in"])
	out["taunt"] = pick.call(["taunt", "taunt_base", "taunt_in"])
	out["laugh"] = pick.call(["laugh", "laugh_base", "laugh_in", "laugh_loop"])
	out["joke"] = pick.call(["joke", "joke_loop", "joke_in"])
	out["recall"] = pick.call(["recall", "recall_loop", "recall_base"])
	out["channel"] = pick.call(["channel", "channel_loop"])
	out["stunned"] = pick.call(["stunned", "stun", "stunned_base"])
	out["knockup"] = pick.call(["knockup", "knockup_loop", "airborne"])
	out["respawn"] = pick.call(["respawn", "respawn_base"])
	out["spawn"] = pick.call(["spawn"])
	# aliases from the exporter (e.g. spell1 -> attack2)
	for logical in ["spell1", "spell2", "spell3", "spell4", "crit", "dance", "idle", "run", "death", "taunt", "laugh", "joke", "channel"]:
		if out.get(logical, []).is_empty():
			var key: String = logical if logical != "idle" else "idle1"
			if al.has(key) and lowmap.has(_strip_prefix(String(al[key]))):
				out[logical] = [lowmap[_strip_prefix(String(al[key]))]]
	if out.idle.is_empty() and not names.is_empty():
		out.idle = [names[0]]
	if out.crit.is_empty():
		out.crit = out.attack.duplicate()
	for i in range(1, 5):
		var k := "spell%d" % i
		if out[k].is_empty():
			out[k] = out.attack.slice(0, 1) if not out.attack.is_empty() else []
	for k in overrides:
		var arr: Array = []
		for n in overrides[k]:
			var low := _strip_prefix(String(n).to_lower())
			if lowmap.has(low):
				arr.append(lowmap[low])
		if not arr.is_empty():
			out[k] = arr
	return out


static func _strip_prefix(low: String) -> String:
	var re := RegEx.create_from_string("^(\\d{4}_)")
	return re.sub(low, "")


static func placeholder_model(team: int, h: float, r: float = 0.45) -> Node3D:
	var root := Node3D.new()
	root.name = "Model"
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	mi.mesh = cm
	mi.position.y = h * 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = G.COLOR_ALLY if team == G.Team.ORDER else G.COLOR_ENEMY
	mi.material_override = mat
	root.add_child(mi)
	return root


# ------------------------------------------------------------------ textures / icons
static func tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path)
	_tex_cache[path] = t
	return t


static func ability_icon(alias: String, key: String) -> Texture2D:
	return tex("res://assets/champions/%s/ui/%s.png" % [alias.to_lower(), key])


static func champion_square(alias: String) -> Texture2D:
	return tex("res://assets/champions/%s/ui/square.png" % alias.to_lower())


static func champion_art(alias: String, skin: int, kind: String) -> Texture2D:
	var t := tex("res://assets/champions/%s/ui/skins/%d_%s.jpg" % [alias.to_lower(), skin, kind])
	if t == null and skin != 0:
		t = tex("res://assets/champions/%s/ui/skins/0_%s.jpg" % [alias.to_lower(), kind])
	return t


static func augment_icon(aug_id: String) -> Texture2D:
	var t := tex("res://assets/ui/augments_large/%s.png" % aug_id.to_lower())
	if t == null:
		t = tex("res://assets/ui/augments/%s.png" % aug_id.to_lower())
	return t


static func item_icon(item_id: int) -> Texture2D:
	return tex("res://assets/ui/items/%d.png" % item_id)


static func summoner_icon(name: String) -> Texture2D:
	return tex("res://assets/ui/summoners/%s.png" % name)


# ------------------------------------------------------------------ fonts
static func font(family: String = "beaufort", weight: String = "Bold") -> Font:
	var key := family + weight
	if _font_cache.has(key):
		return _font_cache[key]
	var path := ""
	if family == "beaufort":
		path = "res://assets/fonts/Beaufort_for_LOL_%s.otf" % weight
	else:
		path = "res://assets/fonts/Spiegel_%s.otf" % weight
	var f: Font = null
	if ResourceLoader.exists(path):
		f = load(path)
	if f == null:
		f = ThemeDB.fallback_font
	_font_cache[key] = f
	return f
