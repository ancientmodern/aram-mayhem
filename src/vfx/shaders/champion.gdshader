shader_type spatial;
// League-style character shading: mostly self-illuminated hand-painted texture,
// soft wrap lighting, rim light, hit flash and fade (per-instance uniforms).
render_mode cull_back, depth_prepass_alpha;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_alpha_scissor = false;
uniform float alpha_scissor = 0.35;
uniform float self_illum = 0.55;
uniform vec3 rim_color : source_color = vec3(0.55, 0.65, 0.9);
uniform float rim_strength = 0.18;

instance uniform float flash = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float fade = 1.0;
instance uniform vec4 glow : source_color = vec4(0.0, 0.0, 0.0, 0.0);
instance uniform float stealth = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec4 c = texture(albedo_tex, UV);
	if (use_alpha_scissor && c.a < alpha_scissor) {
		discard;
	}
	// dissolve when fading out (death / stealth)
	float n = hash(floor(UV * 256.0));
	if (fade < 0.999 && n > fade) {
		discard;
	}
	vec3 base = c.rgb * tint.rgb;
	ALBEDO = base * (1.0 - self_illum);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - ndv, 3.0);
	EMISSION = base * self_illum + rim_color * rim * rim_strength + vec3(1.0, 0.92, 0.85) * flash * 0.8
			+ glow.rgb * glow.a * (0.35 + rim * 1.5);
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
	if (stealth > 0.0) {
		ALPHA = 1.0 - stealth * 0.7;
	}
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float wrap = clamp(ndl * 0.6 + 0.4, 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * wrap;
}
