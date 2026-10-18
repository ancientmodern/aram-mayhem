shader_type spatial;
// League-style skinned-mesh shading (champions, minions, structures).
// League's skinned shader: hand-painted diffuse texture carrying most of the lighting, a soft
// directional term from the map light, a Fresnel term, emissive, and fog-of-war modulation; the
// characters cast blurred dynamic shadows onto the terrain but are not shadowed themselves
// (static shadows are baked into the map). Silhouettes get "inking" (see champion_ink.gdshader).
render_mode cull_back, depth_prepass_alpha, shadows_disabled, ambient_light_disabled;
#include "res://src/render/gamma.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_alpha_scissor = false;
uniform float alpha_scissor = 0.35;
// share of the texture shown unlit (League textures have lighting painted in); the scene's bluish
// ambient is ignored so the painted colours stay true, the rest is lit by the map's directional light
uniform float self_illum = 0.6;
// directional term: wrapped (half-lambert style) so the shadow side stays soft
uniform float light_wrap = 0.55;
uniform vec3 rim_color : source_color = vec3(0.78, 0.86, 1.0);
uniform float rim_strength = 0.10;
uniform float rim_power = 3.5;

// explicit indices: the ink next_pass shares the instance uniform buffer
instance uniform float flash : instance_index(0) = 0.0;
instance uniform vec4 tint : source_color, instance_index(1) = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float fade : instance_index(2) = 1.0;
instance uniform vec4 glow : source_color, instance_index(3) = vec4(0.0, 0.0, 0.0, 0.0);
instance uniform float stealth : instance_index(4) = 0.0;   // Unit applies it as GeometryInstance3D.transparency

varying vec3 v_world_n;
varying float v_hemi;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void vertex() {
	v_world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// sky/ground hemisphere: top of the model a touch brighter than the underside
	v_hemi = mix(0.86, 1.04, clamp(v_world_n.y * 0.5 + 0.5, 0.0, 1.0));
}

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (use_alpha_scissor && c.a < alpha_scissor) {
		discard;
	}
	// dissolve when fading out (scripted fades)
	float n = hash(floor(UV * 256.0));
	if (fade < 0.999 && n > fade) {
		discard;
	}
	vec3 base = c.rgb * tint.rgb;
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - ndv, rim_power);
	vec3 extra = rim_color * rim * rim_strength + vec3(1.0, 0.92, 0.85) * flash * 0.8
			+ glow.rgb * glow.a * (0.35 + rim * 1.5);
	if (gamma_out > 0.5) {
		// gamma pipeline: final = enc(base) * enc(self_illum * hemi + (1 - self_illum) * light), split between
		// emission and light() so it equals the linear result exactly (enc(a * b) = enc(a) * enc(b))
		vec3 eb = gamma_enc(base);
		ALBEDO = eb;
		vec3 bk = base * (self_illum * v_hemi + (1.0 - self_illum) * 0.8);
		EMISSION = eb * gamma_enc(vec3(self_illum * v_hemi)) + gamma_enc(bk + extra) - gamma_enc(bk);
	} else {
		ALBEDO = base * (1.0 - self_illum);
		EMISSION = base * self_illum * v_hemi + extra;
	}
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = clamp((ndl + light_wrap) / (1.0 + light_wrap), 0.0, 1.0);
	vec3 lw = LIGHT_COLOR * ATTENUATION * w;
	if (gamma_out > 0.5) {
		vec3 s0 = vec3(self_illum * v_hemi);
		DIFFUSE_LIGHT += gamma_enc(s0 + (1.0 - self_illum) * lw) - gamma_enc(s0);
	} else {
		DIFFUSE_LIGHT += lw;
	}
}
