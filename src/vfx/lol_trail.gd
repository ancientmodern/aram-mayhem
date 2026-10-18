class_name LolTrail
extends MeshInstance3D
## Camera-facing ribbon that follows its parent (League camera/arbitrary trails behind missiles).

var life := 0.3            ## seconds a trail point lives
var width := 0.2           ## meters
var color := Color.WHITE
var color_curve = null     ## {"t": [...], "v": [[r,g,b,a]...]} over point age
var blend := 4
var texture: Texture2D = null
var emitting := true
var offset := Vector3.ZERO ## local offset from the parent
var _pts: Array = []       ## [world position, birth time]
var _t := 0.0
var _im: ImmediateMesh
static var _mats := {}


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_im = ImmediateMesh.new()
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material_override = _material()


func _material() -> ShaderMaterial:
	var key := "%s|%d" % [texture.resource_path if texture != null else "", blend]
	if _mats.has(key):
		return _mats[key]
	var mat := ShaderMaterial.new()
	mat.shader = LolVfx._shader(blend)
	mat.set_shader_parameter("tex", texture)
	mat.set_shader_parameter("billboard", 0)
	mat.render_priority = 5
	_mats[key] = mat
	return mat


func _process(dt: float) -> void:
	_t += dt
	var parent := get_parent() as Node3D
	if emitting and parent != null:
		var p: Vector3 = parent.global_transform * offset
		if _pts.is_empty() or (p - _pts[_pts.size() - 1][0]).length() > 0.04:
			_pts.append([p, _t])
		elif not _pts.is_empty():
			_pts[_pts.size() - 1][0] = p
	while not _pts.is_empty() and _t - float(_pts[0][1]) > life:
		_pts.pop_front()
	_rebuild()


func _rebuild() -> void:
	_im.clear_surfaces()
	var n := _pts.size()
	if n < 2:
		return
	var cam := get_viewport().get_camera_3d()
	var cam_pos := cam.global_position if cam != null else Vector3(0, 30, 0)
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for i in range(n - 1, -1, -1):
		var p: Vector3 = _pts[i][0]
		var a := clampf((_t - float(_pts[i][1])) / life, 0.0, 1.0)
		var prev: Vector3 = _pts[maxi(i - 1, 0)][0]
		var nxt: Vector3 = _pts[mini(i + 1, n - 1)][0]
		var tangent := (nxt - prev)
		if tangent.length_squared() < 0.000001:
			tangent = Vector3.RIGHT
		var side := tangent.cross(cam_pos - p).normalized() * width * 0.5
		var c := color
		if color_curve is Dictionary:
			c *= LolVfx._sample_color_curve(color_curve, a)
		else:
			c.a *= 1.0 - a
		_im.surface_set_color(c)
		_im.surface_set_uv(Vector2(a, 0.0))
		_im.surface_add_vertex(p + side)
		_im.surface_set_color(c)
		_im.surface_set_uv(Vector2(a, 1.0))
		_im.surface_add_vertex(p - side)
	_im.surface_end()
