class_name LolTrail
extends MeshInstance3D
## League trail ribbon (VfxPrimitiveCameraTrail / VfxPrimitiveArbitraryTrail) following its parent.
## Each trail point lives `life` seconds. Width follows the emitter's scale curve over point age, color is
## birthColor (sampled at the emitter's age when the point is born) x color curve over point age, and the
## texture tiles along the trail every `tiling` meters (mBirthTilingSize, mode 1) or stretches over the
## trail's age (mode 0). emitterUvScrollRate scrolls the texture along the ribbon.

var life := 0.3            ## seconds a trail point lives
var width := 0.2           ## meters (full width)
var width_curve: Array = []   ## 16 samples of the width multiplier over point age
var color := Color.WHITE
var birth_colors = null    ## emitter-time birth colors (16 samples) or null
var color_curve = null     ## {"t": [...], "v": [[r,g,b,a]...]} over point age
var blend := 4
var texture: Texture2D = null
var tex2: Texture2D = null
var tiling := 0.0          ## meters per texture repeat (0 = stretch over age)
var tiling_ec = null       ## tiling over emitter life (16 samples) or null
var mode := 0
var uv_scroll := Vector2.ZERO
var arbitrary := false     ## ribbon in the emitter's plane instead of facing the camera
var emit_life := -1.0
var emitting := true:
	set(v):
		emitting = v
		if v and is_inside_tree():
			set_process(true)
var offset := Vector3.ZERO ## local offset from the parent
var _pts: Array = []       ## [world position, birth time, u, birth color, side axis]
var _t := 0.0
var _dist := 0.0
var _im: ImmediateMesh
static var _mats := {}
const MIN_STEP := 0.05
const MAX_POINTS := 96


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_im = ImmediateMesh.new()
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if material_override == null:
		material_override = _material()


func _material() -> ShaderMaterial:
	return mat_for(texture, tex2, blend)


static func mat_for(texture: Texture2D, tex2: Texture2D, blend: int) -> ShaderMaterial:
	var key := "%s|%s|%d" % [texture.resource_path if texture != null else "", tex2.resource_path if tex2 != null else "", blend]
	if _mats.has(key):
		return _mats[key]
	var mat := ShaderMaterial.new()
	mat.shader = LolVfx._shader(blend)
	mat.set_shader_parameter("tex", texture)
	mat.set_shader_parameter("billboard", 0)
	if tex2 != null:
		mat.set_shader_parameter("tex2", tex2)
		mat.set_shader_parameter("has_tex2", true)
	if blend == 1 or blend == 3 or blend == 5:
		mat.set_shader_parameter("linear_color", true)
	else:
		mat.set_shader_parameter("intensity", 0.85)
	mat.render_priority = 5
	_mats[key] = mat
	return mat


func _sample16(arr, k: float):
	var n: int = arr.size()
	var fi := clampf(k, 0.0, 1.0) * (n - 1)
	var i := int(fi)
	var a = arr[i]
	var b = arr[mini(i + 1, n - 1)]
	var f := fi - i
	if a is Array:
		return Color(lerpf(a[0], b[0], f), lerpf(a[1], b[1], f), lerpf(a[2], b[2], f), lerpf(a[3], b[3], f))
	return lerpf(float(a), float(b), f)


func _process(dt: float) -> void:
	_t += dt
	var parent := get_parent() as Node3D
	if emitting and parent != null and parent.is_inside_tree():
		var p: Vector3 = parent.global_transform * offset
		var ek := clampf(_t / emit_life, 0.0, 1.0) if emit_life > 0.0 else 0.0
		var bc := color
		if birth_colors is Array and not birth_colors.is_empty():
			bc = color * _sample16(birth_colors, ek)
		var til := tiling
		if tiling_ec is Array and not tiling_ec.is_empty():
			til = float(_sample16(tiling_ec, ek))
		var side_axis: Vector3 = parent.global_basis.x.normalized()
		if _pts.is_empty():
			_pts.append([p, _t, 0.0, bc, side_axis])
		else:
			var last: Array = _pts[_pts.size() - 1]
			var step: float = (p - last[0]).length()
			if step > MIN_STEP:
				_dist += step
				_pts.append([p, _t, _dist / til if til > 0.001 else 0.0, bc, side_axis])
				if _pts.size() > MAX_POINTS:
					_pts.pop_front()
			else:
				# the head follows the emitter between samples
				last[0] = p
				last[3] = bc
	while not _pts.is_empty() and _t - float(_pts[0][1]) > life:
		_pts.pop_front()
	_rebuild()
	if not emitting and _pts.is_empty():
		set_process(false)   # finished: no per-frame cost until the owner frees it


func _rebuild() -> void:
	_im.clear_surfaces()
	var n := _pts.size()
	if n < 2:
		return
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam != null else Vector3(0, 30, 0)
	var scroll := uv_scroll.x * _t
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(n - 1, -1, -1):
		var p: Vector3 = _pts[i][0]
		var a := clampf((_t - float(_pts[i][1])) / life, 0.0, 1.0)
		var prev: Vector3 = _pts[maxi(i - 1, 0)][0]
		var nxt: Vector3 = _pts[mini(i + 1, n - 1)][0]
		var tangent := (nxt - prev)
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.RIGHT
		var w := width
		if not width_curve.is_empty():
			w *= float(_sample16(width_curve, a))
		var side: Vector3
		if arbitrary:
			side = (_pts[i][4] as Vector3) * w * 0.5
		else:
			side = tangent.cross(cam_pos - p).normalized() * w * 0.5
		var c: Color = _pts[i][3]
		if color_curve is Dictionary:
			c *= LolVfx._sample_color_curve(color_curve, a)
		else:
			c.a *= 1.0 - a
		# the oldest point always fades out so the tail never ends in a hard edge
		if i == 0:
			c.a = 0.0
		var u: float
		if tiling > 0.0 or tiling_ec != null:
			u = float(_pts[i][2]) - scroll   # texture anchored to the trail points (world), tiled by distance
		else:
			u = a + scroll
		_im.surface_set_color(c)
		_im.surface_set_uv(Vector2(u, 0.0))
		_im.surface_add_vertex(p + side)
		_im.surface_set_color(c)
		_im.surface_set_uv(Vector2(u, 1.0))
		_im.surface_add_vertex(p - side)
	_im.surface_end()
