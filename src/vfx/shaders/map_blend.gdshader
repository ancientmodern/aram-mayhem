shader_type spatial;
// Alpha-blended environment pieces (ice, cloth, grass) with baked lightmap.
// Grass follows League's Wall_of_Grass material (Map12 base.materials.bin): WaveFrequency 1.5,
// WaveAmplitude 8 units, units spread the blades within MinDistance 150 + DistControlFactor 200 units
// (SpreadStrength 1.5), and brush around the local player turns see-through (SeeThroughAlphaMin 0.25).
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
#include "res://src/render/gamma.gdshaderinc"

uniform sampler2D diffuse_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lightmap_tex : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform bool use_lightmap = true;
uniform float lightmap_strength = 4.59;
uniform float brightness = 1.0;
uniform bool grass = false;
uniform float wave_freq = 1.5;
uniform float wave_amp = 0.08;          // meters (League 8 units)
uniform float min_distance = 1.5;       // meters: full spread inside this distance
uniform float dist_control = 2.0;       // meters: spread fades out over this band
uniform float spread_strength = 1.5;
uniform float spread_max = 0.45;        // meters: cap on the push
uniform vec4 pushers[12];               // xyz = unit position, w = 1 when active
uniform vec4 see_through = vec4(0.0);   // xyz = local player position, w = 1 while the player is in brush
uniform float see_alpha_min = 0.25;
uniform float see_radius = 2.6;         // meters around the player that turn see-through

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	if (grass) {
		// blade tips (top of the card texture) move, roots stay planted
		float tip = clamp(1.0 - UV.y, 0.0, 1.0);
		float t = TIME * wave_freq * 2.0 + world_pos.x * 0.35 + world_pos.z * 0.27;
		vec3 off = vec3(sin(t), 0.0, cos(t * 0.8) * 0.6) * wave_amp * tip;
		for (int i = 0; i < 12; i++) {
			if (pushers[i].w < 0.5) {
				continue;
			}
			vec2 d = world_pos.xz - pushers[i].xz;
			float dist = length(d);
			float k = 1.0 - smoothstep(min_distance, min_distance + dist_control, dist);
			if (k > 0.0 && dist > 0.001) {
				off.xz += normalize(d) * k * spread_strength * 0.25 * tip;
				off.y -= k * 0.12 * tip;
			}
		}
		off.xz = clamp(off.xz, vec2(-spread_max), vec2(spread_max));
		world_pos += off;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(world_pos, 1.0)).xyz;
	}
}

void fragment() {
	vec4 d = texture(diffuse_tex, UV);
	vec3 lm = use_lightmap ? texture(lightmap_tex, UV2).rgb * lightmap_strength : vec3(1.0);
	ALBEDO = to_out(d.rgb * lm * tint.rgb * 4.59 * brightness);
	float a = d.a * tint.a;
	if (grass && see_through.w > 0.5) {
		float dist = length(world_pos.xz - see_through.xz);
		a *= mix(see_alpha_min, 1.0, smoothstep(see_radius * 0.6, see_radius, dist));
	}
	ALPHA = a;
}
