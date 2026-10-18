class_name GroundDecal
extends RefCounted
## [world-ui] Shared terrain height map for the ground-decal indicator shader (src/vfx/shaders/indicator.gdshader):
## the nav grid's per-cell terrain height uploaded once as an RF texture, so the shader can tell ground pixels
## (painted) from units standing on it (left alone).

static var _tex: ImageTexture = null
static var _nav_id := 0
static var _origin := Vector2.ZERO
static var _size := Vector2.ONE


static func _ensure() -> bool:
	var m = G.match
	if m == null or m.get("nav") == null:
		return false
	var nav: NavGrid = m.nav
	if nav.w == 0 or nav.heights.size() != nav.w * nav.h:
		return false
	if _tex != null and _nav_id == nav.get_instance_id():
		return true
	var img := Image.create_from_data(nav.w, nav.h, false, Image.FORMAT_RF, nav.heights.to_byte_array())
	_tex = ImageTexture.create_from_image(img)
	_nav_id = nav.get_instance_id()
	_origin = nav.origin
	_size = Vector2(nav.w, nav.h) * nav.cell
	return true


static func apply(mat: ShaderMaterial) -> void:
	if not _ensure():
		mat.set_shader_parameter("has_height", false)
		return
	mat.set_shader_parameter("height_tex", _tex)
	mat.set_shader_parameter("height_origin", _origin)
	mat.set_shader_parameter("height_size", _size)
	mat.set_shader_parameter("has_height", true)
