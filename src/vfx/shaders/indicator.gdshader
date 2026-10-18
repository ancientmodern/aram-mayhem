shader_type spatial;
// Ground targeting indicators: circle, line (rect), cone, range ring. Alpha blended.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, depth_test_disabled;

uniform vec4 color : source_color = vec4(0.35, 0.75, 1.0, 0.5);
uniform int shape = 0;           // 0 circle, 1 rect (UV.y along length), 2 cone, 3 ring
uniform float cone_half = 0.4;   // radians
uniform float edge = 0.04;
uniform float fill_alpha = 0.18;
uniform float pulse = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float a = 0.0;
	float t = 0.5 + 0.5 * sin(TIME * 6.0);
	if (shape == 0) {
		float r = length(p);
		float rim = smoothstep(1.0 - edge * 2.0, 1.0 - edge, r) * (1.0 - smoothstep(1.0 - edge * 0.3, 1.0, r));
		a = (r < 1.0 ? fill_alpha : 0.0) + rim;
	} else if (shape == 1) {
		float ex = 1.0 - smoothstep(1.0 - edge * 3.0, 1.0, abs(p.x));
		float side = smoothstep(1.0 - edge * 4.0, 1.0 - edge, abs(p.x)) * ex;
		float tip = smoothstep(1.0 - edge * 2.0, 1.0, UV.y) * ex;
		float flow = fract(UV.y * 6.0 - TIME * 2.0);
		a = ex * (fill_alpha + flow * 0.08) + side * 0.9 + tip * 0.6;
	} else if (shape == 2) {
		vec2 q = vec2(p.x, (UV.y));
		float r = length(vec2(UV.x * 2.0 - 1.0, UV.y * 2.0));
		float ang = abs(atan(UV.x * 2.0 - 1.0, UV.y * 2.0));
		float inside = step(ang, cone_half) * step(r, 2.0);
		float rim = inside * (smoothstep(cone_half - edge, cone_half, ang) + smoothstep(1.92, 2.0, r));
		a = inside * fill_alpha + rim;
	} else {
		float r = length(p);
		a = smoothstep(1.0 - edge * 1.5, 1.0 - edge * 0.5, r) * (1.0 - smoothstep(1.0 - edge * 0.2, 1.0, r));
	}
	ALBEDO = color.rgb;
	ALPHA = clamp(a, 0.0, 1.0) * color.a * (1.0 + pulse * t * 0.3);
}
