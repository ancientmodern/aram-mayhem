shader_type spatial;
// Ground targeting indicators drawn with League's own targeter textures (assets/spells/textures/*.tex,
// extracted to assets/ui/world/ind_*.png by tools/lol/extract_world_ui.py). The textures are additive
// (black = transparent), exactly how League blends them.
//   shape 0  circle AoE     (aoe.tex, full quad)
//   shape 1  line skillshot (locallinemissilebase.tex stretched + locallinemissiletarget.tex tip; UV.y = 1 at the far end)
//   shape 2  cone           (conicrangeindicator.tex re-mapped in polar space to any cone angle)
//   shape 3  range ring     (circularrangeindicator.tex, full quad)
//   shape 4  procedural thin ring (turret range): crisp line of `ring_px` screen pixels at the quad edge
//
// [world-ui] Rendered as a screen-space GROUND DECAL, like League's targeters: each pixel reads the scene depth,
// reconstructs the world point behind it and projects it (straight down) into the indicator's local frame.
// Points that sit above the terrain (units, props - compared against the nav-grid height map from
// GroundDecal.apply) are left untouched, so characters stand on top of the indicator; sloped ground is followed
// exactly and nothing z-fights, because no geometry is placed at ground height.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, depth_test_disabled, fog_disabled, shadows_disabled;
#include "res://src/render/gamma.gdshaderinc"

uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 1.0;
uniform int shape = 0;
uniform float cone_half = 0.4;        // radians (shape 2)
uniform float tip_frac = 0.2;         // tip length / total length (shape 1)
uniform float ring_px = 2.0;          // shape 4 line width in screen pixels
uniform float ring_glow = 0.35;       // shape 4 soft inner glow strength
uniform sampler2D tex_main : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D tex_tip : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D height_tex : filter_linear, repeat_disable;   // nav-grid terrain height (metres)
uniform bool has_height = false;
uniform vec2 height_origin = vec2(0.0);   // world XZ of the height map's corner
uniform vec2 height_size = vec2(1.0);     // world XZ extent of the height map
uniform float above_tol = 0.22;           // metres above the terrain that still count as ground
uniform float cover = 1.25;               // the drawn quad is this much larger than the decal (slopes)

// conicrangeindicator.tex: apex at (0.5, 0.998), edge half-angle ~27.5 deg, arc radius ~0.985 (measured)
const float CONE_TEX_HALF = 0.48;
const float CONE_TEX_R = 0.985;

varying vec2 mesh_uv;

void vertex() {
	VERTEX.xz *= cover;
	mesh_uv = VERTEX.xz + 0.5;
}

float lod_for(vec2 tsize) {
	vec2 dx = dFdx(mesh_uv) * tsize;
	vec2 dy = dFdy(mesh_uv) * tsize;
	return max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
}

void fragment() {
	// world point behind this pixel
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 vp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vec3 wp = (INV_VIEW_MATRIX * vec4(vp.xyz / vp.w, 1.0)).xyz;
	vec3 lp = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	vec2 uv = lp.xz + 0.5;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		discard;
	}
	float ground = has_height ? textureLod(height_tex, (wp.xz - height_origin) / height_size, 0.0).r : MODEL_MATRIX[3].y;
	float above = wp.y - ground;
	float m = 1.0 - smoothstep(above_tol * 0.55, above_tol, above);
	if (m <= 0.0) {
		discard;
	}
	vec3 c = vec3(0.0);
	if (shape == 0 || shape == 3) {
		c = textureLod(tex_main, uv, lod_for(vec2(textureSize(tex_main, 0)))).rgb;
	} else if (shape == 1) {
		float y = uv.y;
		if (y > 1.0 - tip_frac) {
			float ty = (y - (1.0 - tip_frac)) / max(tip_frac, 1e-4);
			c = textureLod(tex_tip, vec2(uv.x, 1.0 - ty), lod_for(vec2(textureSize(tex_tip, 0)) * vec2(1.0, 1.0 / max(tip_frac, 1e-4)))).rgb;
		} else {
			float by = y / max(1.0 - tip_frac, 1e-4);
			c = textureLod(tex_main, vec2(uv.x, 1.0 - by), lod_for(vec2(textureSize(tex_main, 0)))).rgb;
		}
	} else if (shape == 2) {
		// quad: width = 2*length, apex at UV (0.5, 0), forward = +UV.y
		vec2 q = vec2((uv.x - 0.5) * 2.0, uv.y);
		float r = length(q);
		float a = atan(q.x, q.y);
		if (abs(a) <= cone_half && r <= 1.0) {
			float ta = a / cone_half * CONE_TEX_HALF;
			vec2 tuv = vec2(0.5, 0.998) + r * CONE_TEX_R * vec2(sin(ta), -cos(ta));
			c = textureLod(tex_main, tuv, lod_for(vec2(textureSize(tex_main, 0)))).rgb;
		}
	} else {
		vec2 p = uv * 2.0 - 1.0;
		float r = length(p);
		// pixel footprint from the smooth quad UV (the reprojected UV jumps at unit silhouettes)
		vec2 fw = fwidth(mesh_uv);
		float px = 2.0 * max(fw.x, fw.y);
		float w = ring_px * px;
		float line = 1.0 - smoothstep(w * 0.5, w * 0.5 + px, abs(r - (1.0 - w)));
		float glow = ring_glow * smoothstep(1.0 - w * 6.0, 1.0 - w, r) * step(r, 1.0);
		c = vec3(line + glow * 0.5);
	}
	ALBEDO = to_out(c * color.rgb * energy);
	ALPHA = color.a * m;
}
