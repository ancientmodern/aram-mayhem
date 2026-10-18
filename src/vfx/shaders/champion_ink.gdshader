shader_type spatial;
// League "inking": skinned meshes get a thin dark silhouette line (League runs a Sobel filter over
// a scaled-depth buffer; an inverted hull gives the same look cheaply). Used as next_pass of the
// character material. Thickness is kept roughly constant in screen space.
render_mode cull_front, unshaded, shadows_disabled, depth_draw_opaque;
#include "res://src/render/gamma.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform bool use_alpha_scissor = false;
uniform float alpha_scissor = 0.35;
uniform float thickness = 0.0016;     // fraction of view distance
uniform vec3 ink_color : source_color = vec3(0.035, 0.03, 0.045);
uniform float ink_tex_mix = 0.25;     // tint the line slightly with the surface colour

instance uniform float ink : instance_index(5) = 1.0;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float dist = length(CAMERA_POSITION_WORLD - wp);
	float sc = max(length(MODEL_MATRIX[0].xyz), 0.0001);
	VERTEX += normalize(NORMAL) * (dist * thickness * ink / sc);
}

void fragment() {
	if (ink < 0.01) {
		discard;
	}
	vec4 c = texture(albedo_tex, UV);
	if (use_alpha_scissor && c.a < alpha_scissor) {
		discard;
	}
	ALBEDO = to_out(mix(ink_color, c.rgb * 0.25, ink_tex_mix));
}
