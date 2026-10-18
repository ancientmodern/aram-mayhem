class_name LolBeam
extends MeshInstance3D
## League beam primitive: a camera-facing strip from the effect's origin along its forward axis (-Z).

var width := 0.5
var length := 10.0
var life := 1.0
var color := Color.WHITE
var color_curve = null
var blend := 0
var texture: Texture2D = null
var _t := 0.0
var _running := false
var _im: ImmediateMesh


func _ready() -> void:
	_im = ImmediateMesh.new()
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := ShaderMaterial.new()
	mat.shader = LolVfx._shader(blend)
	mat.set_shader_parameter("tex", texture)
	mat.set_shader_parameter("billboard", 0)
	if blend == 1 or blend == 3 or blend == 5:
		mat.set_shader_parameter("linear_color", true)
	else:
		mat.set_shader_parameter("intensity", 0.85)
	mat.render_priority = 8
	material_override = mat


func start() -> void:
	_running = true
	_t = 0.0


func _process(dt: float) -> void:
	if not _running:
		return
	_t += dt
	var k := clampf(_t / maxf(life, 0.01), 0.0, 1.0)
	if k >= 1.0:
		visible = false
		_running = false
		return
	_rebuild(k)


func _rebuild(k: float) -> void:
	_im.clear_surfaces()
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var a := global_position
	var fwd := -global_basis.z.normalized()
	var b := a + fwd * length
	var to_cam := (cam.global_position - (a + b) * 0.5).normalized()
	var side := fwd.cross(to_cam).normalized() * width * 0.5
	var c := color
	if color_curve is Dictionary:
		c *= LolVfx._sample_color_curve(color_curve, k)
	var inv := global_transform.affine_inverse()
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	for p in [[a + side, Vector2(0, 0)], [a - side, Vector2(0, 1)], [b + side, Vector2(1, 0)], [b - side, Vector2(1, 1)]]:
		_im.surface_set_color(c)
		_im.surface_set_uv(p[1])
		_im.surface_add_vertex(inv * p[0])
	_im.surface_end()
