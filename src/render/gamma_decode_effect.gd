class_name GammaDecodeEffect
extends CompositorEffect
## League colour pipeline. League renders in gamma (display) space: textures are sampled raw and particles
## blend (alpha and additive) on gamma values. Godot blends in linear space, which makes smoke and additive
## effects pale and washed out. With the global shader parameter `gamma_out` = 1 every 3D shader writes
## gamma-encoded colour, so the transparent pass blends exactly like League; this effect then decodes the
## buffer back to linear right after the transparent pass so Godot's tonemap / sRGB output returns the same
## gamma values. Opaque surfaces look identical either way (encode(a * b) == encode(a) * encode(b)).

const GLSL := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;
void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	ivec2 s = imageSize(color_image);
	if (p.x >= s.x || p.y >= s.y) {
		return;
	}
	vec4 c = imageLoad(color_image, p);
	vec3 x = max(c.rgb, vec3(0.0));
	vec3 lin = mix(x / 12.92, pow((x + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), x));
	imageStore(color_image, p, vec4(lin, c.a));
}
"""

var _rd: RenderingDevice
var _shader := RID()
var _pipeline := RID()


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	_rd = RenderingServer.get_rendering_device()
	if _rd != null:
		RenderingServer.call_on_render_thread(_build)


func _build() -> void:
	var src := RDShaderSource.new()
	src.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	src.source_compute = GLSL
	var spirv := _rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		push_error("GammaDecodeEffect: " + spirv.compile_error_compute)
		return
	_shader = _rd.shader_create_from_spirv(spirv)
	if _shader.is_valid():
		_pipeline = _rd.compute_pipeline_create(_shader)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null and _shader.is_valid():
		_rd.free_rid(_shader)   # frees the pipeline too


func _render_callback(_type: int, render_data: RenderData) -> void:
	if _rd == null or not _pipeline.is_valid():
		return
	var sb := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if sb == null:
		return
	var size := sb.get_internal_size()
	if size.x == 0 or size.y == 0:
		return
	for view in sb.get_view_count():
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		u.binding = 0
		u.add_id(sb.get_color_layer(view))
		var uset := UniformSetCacheRD.get_cache(_shader, 0, [u])
		var cl := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
		_rd.compute_list_bind_uniform_set(cl, uset, 0)
		_rd.compute_list_dispatch(cl, (size.x + 7) / 8, (size.y + 7) / 8, 1)
		_rd.compute_list_end()
