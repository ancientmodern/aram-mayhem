class_name CursorMarker
extends Node3D
## [juice] League's right-click / attack-move click markers, rebuilt from the Cursor_Moveto particle system
## (Global.wad: Shared/Particles/Cursor_Moveto - 4 shadow chevrons, a ripple ring and the four-arrow
## movement_indicator4 mesh, 0.4 s total). Rendered as plain meshes driven by an instance-uniform `age`, so a click
## costs six draw calls and no particle simulation; a pool of slots allows League-style overlapping markers when
## clicks come in fast (each click starts its own marker, nothing is cut short).
##
## Colours: green for move (League's color-movetogreen / movement_indicator textures). League ships no separate
## red particle, so attack markers are the same meshes with the red/green channels swapped.

enum Kind { MOVE, ATTACK }

const POOL := 8
const LIFE := 0.4
const RING_LIFE := 0.2
const GROUND_LIFT := 0.035
const P := "res://assets/vfx/assets/shared/particles/"
const SH := "res://src/fx_moments/shaders/"

class Slot:
	var root: Node3D
	var arrows: MeshInstance3D
	var ring: MeshInstance3D
	var shadows: Array[MeshInstance3D] = []
	var age := -1.0
	var kind := 0

var _slots: Array[Slot] = []
var _next := 0
var _mats := {}                 ## "arrows0"/"arrows1"/"ring0"/"ring1"/"shadow"
var _match = null
var last_pos := Vector3.INF
var last_time := -10.0


## Fire a marker at `pos` (world, ground). `attack` = red marker.
static func spawn(m, pos: Vector3, attack: bool = false) -> void:
	if m == null:
		return
	var hub: CursorMarker = m.get_meta("juice_cursor") if m.has_meta("juice_cursor") else null
	if hub == null or not is_instance_valid(hub):
		hub = CursorMarker.new()
		hub._match = m
		hub.name = "CursorMarkers"
		m.set_meta("juice_cursor", hub)
		m.add_child(hub)
	hub._fire(pos, Kind.ATTACK if attack else Kind.MOVE)


func _ready() -> void:
	_build_materials()
	var arrows_mesh: Mesh = load(P + "movement_indicator4.obj")
	var shadow_mesh: Mesh = load(P + "cursor_moveto.obj")
	var ring_mesh: Mesh = load(P + "shockwavetrail001.obj")
	for i in POOL:
		var s := Slot.new()
		s.root = Node3D.new()
		s.root.visible = false
		add_child(s.root)
		s.arrows = _mi(arrows_mesh, _mats["arrows0"])
		s.ring = _mi(ring_mesh, _mats["ring0"])
		s.root.add_child(s.arrows)
		s.root.add_child(s.ring)
		for k in 4:
			var sh := _mi(shadow_mesh, _mats["shadow"])
			sh.rotation.y = k * PI * 0.5
			s.root.add_child(sh)
			s.shadows.append(sh)
		_slots.append(s)
	set_process(false)


func _mi(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	mi.extra_cull_margin = 3.0          # vertices are displaced in the shader
	return mi


func _build_materials() -> void:
	var arrows_shader: Shader = load(SH + "cursor_arrows.gdshader")
	var ring_shader: Shader = load(SH + "cursor_ring.gdshader")
	var shadow_shader: Shader = load(SH + "cursor_shadow.gdshader")
	var tex_arrow: Texture2D = load(P + "movement_indicator.png")
	var tex_line: Texture2D = load(P + "line03.png")
	var tex_ramp: Texture2D = load(P + "color-movetogreen.png")
	for k in 2:
		var am := ShaderMaterial.new()
		am.shader = arrows_shader
		am.set_shader_parameter("tex", tex_arrow)
		am.set_shader_parameter("swap_rg", k == 1)
		am.render_priority = 2
		_mats["arrows%d" % k] = am
		var rm := ShaderMaterial.new()
		rm.shader = ring_shader
		rm.set_shader_parameter("line_tex", tex_line)
		rm.set_shader_parameter("color_ramp", tex_ramp)
		rm.set_shader_parameter("swap_rg", k == 1)
		rm.render_priority = 1
		_mats["ring%d" % k] = rm
	var sm := ShaderMaterial.new()
	sm.shader = shadow_shader
	sm.render_priority = 0
	_mats["shadow"] = sm


func _fire(pos: Vector3, kind: int) -> void:
	var s := _slots[_next]
	# prefer a free slot; otherwise recycle the oldest marker
	var best := -1.0
	for i in POOL:
		var sl := _slots[(_next + i) % POOL]
		if sl.age < 0.0:
			s = sl
			best = -2.0
			break
		if sl.age > best:
			best = sl.age
			s = sl
	_next = (_slots.find(s) + 1) % POOL
	s.age = 0.0
	s.kind = kind
	var y := pos.y
	if _match != null and _match.nav != null:
		y = _match.nav.height_at(pos)
	s.root.global_position = Vector3(pos.x, y + GROUND_LIFT, pos.z)
	s.root.visible = true
	s.arrows.material_override = _mats["arrows%d" % kind]
	s.ring.material_override = _mats["ring%d" % kind]
	_set_age(s, 0.0)
	last_pos = pos
	last_time = Time.get_ticks_msec() * 0.001
	set_process(true)


func _set_age(s: Slot, a: float) -> void:
	s.arrows.set_instance_shader_parameter("age", a)
	s.ring.set_instance_shader_parameter("age", a)
	for sh in s.shadows:
		sh.set_instance_shader_parameter("age", a)


func _process(dt: float) -> void:
	var any := false
	for s in _slots:
		if s.age < 0.0:
			continue
		s.age += dt
		if s.age >= LIFE:
			s.age = -1.0
			s.root.visible = false
			continue
		any = true
		_set_age(s, s.age)
	if not any:
		set_process(false)
