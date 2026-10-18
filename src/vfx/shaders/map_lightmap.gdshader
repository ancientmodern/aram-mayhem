shader_type spatial;
// Howling Abyss environment: diffuse texture * baked lightmap (League "baked diffuse").
// The baked colour is the final colour; the only dynamic lighting is the sun's shadow map (units and structures
// cast soft shadows onto the ground like League) plus a small additive share of nearby VFX point lights.
// Ambient and specular are disabled so the lightmap colours stay exactly as baked.
render_mode cull_disabled, ambient_light_disabled, specular_disabled;
#include "res://src/render/gamma.gdshaderinc"

uniform sampler2D diffuse_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lightmap_tex : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform bool use_lightmap = true;
uniform float lightmap_strength = 4.59;
uniform float brightness = 1.0;
uniform float alpha_test = 0.0;
uniform float saturation = 0.97;
// colour multiplied into the ground where the sun is shadowed (League unit shadows are soft and cool)
uniform vec3 shadow_color : source_color = vec3(0.50, 0.54, 0.66);
uniform float point_light_share = 0.35;
// display-space grade fitted to League Howling Abyss frames (luminance percentiles of 1080p gameplay
// captures: p5 26, p25 47, p50 74, p75 99 vs ours 32/52/66/85 before the grade)
uniform float grade_gain = 1.2;
uniform float grade_contrast = 1.14;
uniform vec3 grade_tint = vec3(1.03, 1.0, 0.93);   // League frames are less blue (mean B/R 1.64 vs our 1.89)

void fragment() {
	vec4 d = texture(diffuse_tex, UV);
	if (d.a < alpha_test) {
		discard;
	}
	vec3 lm = use_lightmap ? texture(lightmap_tex, UV2).rgb * lightmap_strength : vec3(1.0);
	vec3 col = d.rgb * lm * tint.rgb * 4.59 * brightness;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, saturation);
	vec3 g = pow(max(col, vec3(0.0)), vec3(1.0 / 2.2));
	g = max(mix(vec3(0.5), g * grade_gain * grade_tint, grade_contrast), vec3(0.0));
	ALBEDO = to_out(pow(g, vec3(2.2)));
}

void light() {
	if (LIGHT_IS_DIRECTIONAL) {
		// ATTENUATION carries the shadow term; the light's colour/angle are already baked into the lightmap
		DIFFUSE_LIGHT += to_out(mix(shadow_color, vec3(1.0), ATTENUATION));
	} else {
		DIFFUSE_LIGHT += to_out(LIGHT_COLOR * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0) * point_light_share);
	}
}
