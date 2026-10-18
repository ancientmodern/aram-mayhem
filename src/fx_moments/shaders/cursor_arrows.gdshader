shader_type spatial;
// [juice] League Cursor_Moveto "cursor" emitter: movement_indicator4.scb (four arrows, tips meeting at the click
// point) with movement_indicator.tex, League blendMode 1 (alpha blend), 0.4 s. The arrows converge on the point while fading.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
#include "res://src/render/gamma.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap, repeat_disable;
uniform float life = 0.4;
uniform float start_scale = 2.0;
uniform float end_scale = 1.05;
uniform vec3 tint = vec3(1.0);
uniform bool swap_rg = false;
instance uniform float age = 0.0;

void vertex() {
	float u = clamp(age / life, 0.0, 1.0);
	float e = 1.0 - pow(1.0 - u, 3.0);
	float s = mix(start_scale, end_scale, e);
	VERTEX = vec3(VERTEX.x * s, VERTEX.y * s * mix(1.0, 0.55, e), VERTEX.z * s);
}

void fragment() {
	// the .obj stores League's D3D UVs (v down); Godot's importer flips v, so undo it
	vec4 t = texture(tex, vec2(UV.x, 1.0 - UV.y));
	float u = clamp(age / life, 0.0, 1.0);
	float fade = 1.0 - smoothstep(0.3, 1.0, u);
	float pop = 1.0 + 0.8 * (1.0 - smoothstep(0.0, 0.25, u));   // League's arrows flash in brighter
	vec3 c = swap_rg ? vec3(t.g, t.r * 0.3, t.b * 0.2) : t.rgb;
	ALBEDO = to_out(min(c * tint * pop, vec3(1.0)));
	ALPHA = t.a * fade;
}
