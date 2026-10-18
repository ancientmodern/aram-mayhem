shader_type spatial;
// Ground targeting indicators drawn with League's own targeter textures (assets/spells/textures/*.tex,
// extracted to assets/ui/world/ind_*.png by tools/lol/extract_world_ui.py). The textures are additive
// (black = transparent), exactly how League blends them.
//   shape 0  circle AoE     (aoe.tex, full quad)
//   shape 1  line skillshot (locallinemissilebase.tex stretched + locallinemissiletarget.tex tip; UV.y = 1 at the far end)
//   shape 2  cone           (conicrangeindicator.tex re-mapped in polar space to any cone angle)
//   shape 3  range ring     (circularrangeindicator.tex, full quad)
//   shape 4  procedural thin ring (turret range): crisp line of `ring_px` screen pixels at the quad edge
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, depth_test_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 1.0;
uniform int shape = 0;
uniform float cone_half = 0.4;        // radians (shape 2)
uniform float tip_frac = 0.2;         // tip length / total length (shape 1)
uniform float ring_px = 2.0;          // shape 4 line width in screen pixels
uniform float ring_glow = 0.35;       // shape 4 soft inner glow strength
uniform sampler2D tex_main : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D tex_tip : source_color, filter_linear_mipmap, repeat_disable;

// conicrangeindicator.tex: apex at (0.5, 0.998), edge half-angle ~27.5 deg, arc radius ~0.985 (measured)
const float CONE_TEX_HALF = 0.48;
const float CONE_TEX_R = 0.985;

void fragment() {
	vec3 c = vec3(0.0);
	if (shape == 0 || shape == 3) {
		c = texture(tex_main, UV).rgb;
	} else if (shape == 1) {
		float y = UV.y;
		if (y > 1.0 - tip_frac) {
			float ty = (y - (1.0 - tip_frac)) / max(tip_frac, 1e-4);
			c = texture(tex_tip, vec2(UV.x, 1.0 - ty)).rgb;
		} else {
			float by = y / max(1.0 - tip_frac, 1e-4);
			c = texture(tex_main, vec2(UV.x, 1.0 - by)).rgb;
		}
	} else if (shape == 2) {
		// quad: width = 2*length, apex at UV (0.5, 0), forward = +UV.y
		vec2 q = vec2((UV.x - 0.5) * 2.0, UV.y);
		float r = length(q);
		float a = atan(q.x, q.y);
		if (abs(a) <= cone_half && r <= 1.0) {
			float ta = a / cone_half * CONE_TEX_HALF;
			vec2 tuv = vec2(0.5, 0.998) + r * CONE_TEX_R * vec2(sin(ta), -cos(ta));
			c = texture(tex_main, tuv).rgb;
		}
	} else {
		vec2 p = UV * 2.0 - 1.0;
		float r = length(p);
		float px = fwidth(r);
		float w = ring_px * px;
		float line = 1.0 - smoothstep(w * 0.5, w * 0.5 + px, abs(r - (1.0 - w)));
		float glow = ring_glow * smoothstep(1.0 - w * 6.0, 1.0 - w, r) * step(r, 1.0);
		c = vec3(line + glow * 0.5);
	}
	ALBEDO = c * color.rgb * energy;
	ALPHA = color.a;
}
