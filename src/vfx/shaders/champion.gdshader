shader_type spatial;
// League skinned-mesh shading (champions, minions, structures): a 1:1 port of League's legacy
// hlsl/skinnedmesh/lit_uber (decompiled, docs/LEAGUE_SHADERS.md section 3):
//   ambient = Valve-style ambient cube from the map light grid at the unit's position, per vertex
//   L = saturate(LIGHTGRID_SCALE.y * SELF_ILLUMINATION + (1 - em) * ambient * LIGHTGRID_SCALE.x + em)
//   c = saturate(diffuse * L)            (gamma values; no sun, no rim, no specular, no self-shadowing)
// The characters still cast blurred shadows onto the terrain (the map shader receives them).
render_mode unshaded, cull_back, depth_prepass_alpha, shadows_disabled;
#include "res://src/render/gamma.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_alpha_scissor = false;
// League discards only fully transparent texels (clip(d.a == 0)); a small threshold avoids filtered fringes
uniform float alpha_scissor = 0.02;
// unused by League's shader (kept so existing material setup code still applies cleanly)
uniform float self_illum = 0.0;
// Map12 light grid (tools/lol/extract_lightgrid.py): 6 faces side by side, raw gamma BGRA -> RGB
global uniform sampler2D lightgrid : filter_linear, repeat_disable;
global uniform float lightgrid_on;
// LIGHTGRID_SCALE.x: the grid is stored at half intensity (MapBakeProperties.lightGridCharacterFullBrightIntensity
// = 0.5), so the CPU most likely passes 1 / 0.5 = 2 (docs/LEAGUE_SHADERS.md, open item)
uniform float lightgrid_scale = 2.0;
// League's raw grid x 2 leaves camera-facing sides at ~0.2 (far darker than live League), so part of L must come
// from a constant term the CPU supplies (SELF_ILLUMINATION / MapLightingV2.MinimumEnvironmentColorContribution).
// Fitted floor until a reference capture pins it down (docs/LEAGUE_SHADERS.md open items).
uniform float ambient_floor = 0.55;
uniform float grid_gain = 0.8;   // x lightgrid_scale
const float GRID_EXTENT = 12877.525;   // League units covered by the 256 x 256 grid

// explicit indices: the ink next_pass shares the instance uniform buffer
instance uniform float flash : instance_index(0) = 0.0;
instance uniform vec4 tint : source_color, instance_index(1) = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float fade : instance_index(2) = 1.0;
instance uniform vec4 glow : source_color, instance_index(3) = vec4(0.0, 0.0, 0.0, 0.0);
instance uniform float stealth : instance_index(4) = 0.0;   // Unit applies it as GeometryInstance3D.transparency

varying vec3 v_amb;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

vec3 grid_face(vec2 uv, float face) {
	vec2 c = clamp(uv, vec2(0.5 / 256.0), vec2(1.0 - 0.5 / 256.0));
	return textureLod(lightgrid, vec2((face + c.x) / 6.0, c.y), 0.0).rgb;
}

void vertex() {
	// Godot (x, y, z) = League (x, y, -z) * 0.01
	vec3 o = NODE_POSITION_WORLD;
	vec2 uv = vec2(o.x, -o.z) * 100.0 / GRID_EXTENT;
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	n.z = -n.z;
	vec3 n2 = n * n;
	v_amb = n2.x * grid_face(uv, n.x < 0.0 ? 1.0 : 0.0)
			+ n2.y * grid_face(uv, n.y < 0.0 ? 3.0 : 2.0)
			+ n2.z * grid_face(uv, n.z < 0.0 ? 5.0 : 4.0);
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (c.a < (use_alpha_scissor ? alpha_scissor : 0.004)) {
		discard;
	}
	// dissolve when fading out (scripted fades)
	float n = hash(floor(UV * 256.0));
	if (fade < 0.999 && n > fade) {
		discard;
	}
	vec3 d = gamma_enc(c.rgb * tint.rgb);
	// no grid (tests without a map): mid-lane grey ambient
	vec3 amb = lightgrid_on > 0.5 ? v_amb : vec3(0.21);
	// hit flash = League SELF_ILLUMINATION: raises L toward full-bright texture, never past it
	vec3 L = clamp(vec3(flash + ambient_floor) + amb * lightgrid_scale * grid_gain, 0.0, 1.0);
	vec3 col = clamp(d * L, 0.0, 1.0);
	// our own highlight (player selection glow), not a League shader term
	col += glow.rgb * glow.a * 0.35;
	ALBEDO = gamma_out > 0.5 ? col : gamma_dec(col);
}
