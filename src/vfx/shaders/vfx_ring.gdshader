shader_type spatial;
// Procedural ring / disc on a flat quad (shockwaves, AoE telegraphs, auras).
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, depth_test_disabled;
#include "res://src/render/gamma.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0, 0.5, 0.1, 1.0);
uniform float energy = 2.0;
uniform float progress = 0.0;      // 0..1 radial expansion
uniform float thickness = 0.12;
uniform float fill = 0.0;          // inner disc opacity
uniform float fade = 1.0;
uniform float rotate_speed = 0.0;
uniform float segments = 0.0;      // >0: dashed ring
uniform float soft = 0.05;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x) + TIME * rotate_speed;
	float edge = mix(0.2, 1.0, progress);
	float ring = smoothstep(edge - thickness - soft, edge - thickness, r) * (1.0 - smoothstep(edge - soft, edge, r));
	if (segments > 0.0) {
		ring *= step(0.35, fract(ang / 6.28318 * segments));
	}
	float disc = (1.0 - smoothstep(edge - soft, edge, r)) * fill * (0.5 + 0.5 * r / max(edge, 0.001));
	float a = clamp(ring + disc, 0.0, 1.0) * fade * color.a;
	ALBEDO = to_out(color.rgb * energy);
	ALPHA = a;
}
