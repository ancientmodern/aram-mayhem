shader_type spatial;
// [juice] League Cursor_Moveto "circle": shockwavetrail001.scb annulus (r 0.08 m inner 0.014, scaled x15) with
// line03.tex scrolling radially (-4 uv/s) and color-movetogreen.tex over life, 0.2 s additive. Reads as a fast
// ground ripple: one thin bright line sweeping out across the annulus while the colour fades bright -> dark green.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;
#include "res://src/render/gamma.gdshaderinc"

uniform sampler2D line_tex : source_color, filter_linear, repeat_enable;
uniform sampler2D color_ramp : source_color, filter_linear, repeat_disable;
uniform float life = 0.2;
uniform float mesh_r = 0.08;
uniform vec3 tint = vec3(1.0);
uniform bool swap_rg = false;
instance uniform float age = 0.0;
varying float v_r;

void vertex() {
	v_r = length(VERTEX.xz) / mesh_r;       // 0.17 inner .. 1.0 outer
	VERTEX = VERTEX * 15.0;
}

void fragment() {
	float u = clamp(age / life, 0.0, 1.0);
	float rn = clamp((v_r - 0.17) / 0.83, 0.0, 1.0);
	// the line texture's bright row (v = 0.5) travels outward at League's 4 uv/s over the annulus' 0.5 v span
	float v = 0.112 + rn * 0.5;
	float line = texture(line_tex, vec2(0.5, v + 4.0 * age)).r;
	vec3 ramp = texture(color_ramp, vec2(clamp(u, 0.02, 0.98), 0.5)).rgb;
	vec3 c = swap_rg ? ramp.grb : ramp.rgb;
	float edge = smoothstep(0.0, 0.08, rn) * (1.0 - smoothstep(0.85, 1.0, rn));
	ALBEDO = to_out(c * tint * line * edge * 1.6 * (1.0 - u));
	ALPHA = 1.0;
}
