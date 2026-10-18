class_name MapProps
extends Node3D
## Howling Abyss animated level props, placed from League data: every GdsMapObject of type 10 ("LevelProp_*") in
## Map12 base.materials.bin (tools/lol/extract_map_layout.py -> data/map/map12_env.json): bridge chains, long
## chains, the eight bridge-lane statues, the banner under the mid bridge, the cutaway, shop props, the hermit's
## robot and the decorative cliff poros. Models: tools/lol/export_character.py -> assets/map/props/.
## Cost: ~30 small skinned meshes (300-2600 verts each, one draw call each, no shadows); only the props within
## VIS_R of the camera focus are visible and animate (AnimationPlayer.active), checked 4x per second.

const PROPS_DIR := "res://assets/map/props/"
const VIS_R := 40.0
## League placements far outside the playable area (e.g. the periphery bridge 80 m under the map) are never seen
## by the ARAM camera: skip them (Godot-space XZ bounds of the map plus a margin).
const AREA := Rect2(-20.0, -150.0, 170.0, 170.0)

var match_ref = null
var _props: Array = []    ## [{node: Node3D, ap: AnimationPlayer, pos: Vector3}]
var _check := 0.0


func setup(m) -> void:
	match_ref = m
	name = "MapProps"
	for r in MapBuilder.env_data().get("level_props", []):
		_place(r)


func _place(r: Dictionary) -> void:
	var x: Array = r.xform
	var pos := G.lol_pos(float(x[12]), float(x[13]), float(x[14]))
	if not AREA.has_point(Vector2(pos.x, pos.z)):
		return
	var ch: String = r.character
	var sk: int = int(r.get("skin", 0))
	var mdl: Node3D = null
	var path := PROPS_DIR + "%s_skin%d.glb" % [ch.to_lower(), sk]
	if ResourceLoader.exists(path):
		mdl = Assets._instance_model(path, 0.0)
	elif ResourceLoader.exists(Assets.unit_model_path(ch, sk)):
		mdl = Assets.unit_model(ch, sk)   # HA_AP_Poro is already exported for the gameplay poros
	if mdl == null:
		return
	mdl.name = String(r.name)
	add_child(mdl)
	# League row-major transform (rows = axis images, left-handed) -> Godot: F*M*F with F = diag(1, 1, -1)
	var bx := Vector3(x[0], x[1], -float(x[2]))
	var by := Vector3(x[4], x[5], -float(x[6]))
	var bz := Vector3(-float(x[8]), -float(x[9]), x[10])
	mdl.transform = Transform3D(Basis(bx, by, bz), pos)
	_no_shadows(mdl)
	var ap := Assets._find_anim(mdl)
	if ap != null:
		var clip := ""
		for an in ap.get_animation_list():
			if String(an).to_lower() == "idle1":
				clip = an
		if clip != "":
			ap.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
			ap.play(clip)
			ap.seek(G.rng.randf() * ap.get_animation(clip).length, true)   # props don't sway in lockstep
		ap.active = false
	mdl.visible = false
	_props.append({"node": mdl, "ap": ap, "pos": pos})


## The map receives no character shadows except from units; level props are scenery (League bakes them).
static func _no_shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_no_shadows(c)


func _process(dt: float) -> void:
	if match_ref == null:
		return
	_check -= dt
	if _check > 0.0:
		return
	_check = 0.25
	var rig = match_ref.camera_rig
	var f: Vector3 = rig.focus if rig != null else Vector3.ZERO
	for p in _props:
		var near := G.flat_dist(f, p.pos) < VIS_R
		var n: Node3D = p.node
		if n.visible != near:
			n.visible = near
			if p.ap != null:
				p.ap.active = near
