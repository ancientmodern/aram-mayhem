shader_type spatial;
// League-style skinned-mesh shading (champions, minions, structures).
// League's skinned shader: hand-painted diffuse texture carrying most of the lighting, a soft
// directional term from the map light, a Fresnel term, emissive, and fog-of-war modulation; the
// characters cast blurred dynamic shadows onto the terrain but are not shadowed themselves
// (static shadows are baked into the map). Silhouettes get "inking" (see champion_ink.gdshader).
render_mode cull_back, depth_prepass_alpha, shadows_disabled, ambient_light_disabled;

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

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void vertex() {
	v_world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
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
	ALBEDO = base * (1.0 - self_illum);
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = pow(1.0 - ndv, rim_power);
	// sky/ground hemisphere: top of the model a touch brighter than the underside
	float hemi = mix(0.86, 1.04, clamp(v_world_n.y * 0.5 + 0.5, 0.0, 1.0));
	EMISSION = base * self_illum * hemi + rim_color * rim * rim_strength
			+ vec3(1.0, 0.92, 0.85) * flash * 0.8
			+ glow.rgb * glow.a * (0.35 + rim * 1.5);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = clamp((ndl + light_wrap) / (1.0 + light_wrap), 0.0, 1.0);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * w;
}
