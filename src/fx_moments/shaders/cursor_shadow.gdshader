shader_type spatial;
// [juice] League Cursor_Moveto "cursor_shadow1..4": cursor_moveto.scb chevrons in solid black that slide inward
// (birth velocity -2 m/s, drag 3.5) and shrink to nothing over 0.4 s - they give the additive arrows contrast.
// The node places four copies 90 degrees apart (local -z = outward); the slide happens here.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform float life = 0.4;
uniform float radius0 = 0.5;
uniform float vel0 = 2.0;
uniform float drag = 3.5;
uniform float alpha = 0.3;
instance uniform float age = 0.0;
varying float v_u;

void vertex() {
	float u = clamp(age / life, 0.0, 1.0);
	v_u = u;
	// League scale0 curve (1,1,1) -> (0.7,0,0) on birth scale (1.5,1,2): width and height collapse, length keeps 0.7
	float sc = 1.0 - u;
	vec3 p = VERTEX * vec3(1.5 * sc, 0.4 * sc, 2.0 * mix(1.0, 0.7, u));
	float dist = (vel0 / drag) * (1.0 - exp(-drag * age));
	p.z -= radius0 - dist;
	VERTEX = p;
}

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = alpha * (1.0 - smoothstep(0.5, 1.0, v_u));
}
