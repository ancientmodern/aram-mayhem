shader_type spatial;
// Alpha-blended environment pieces (ice, cloth, grass) with baked lightmap.
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;

uniform sampler2D diffuse_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lightmap_tex : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform bool use_lightmap = true;
uniform float lightmap_strength = 4.59;
uniform float brightness = 1.0;
uniform bool grass = false;
uniform float wave_amp = 0.06;

void vertex() {
	if (grass) {
		float t = TIME * 1.6 + VERTEX.x * 0.35 + VERTEX.z * 0.27;
		VERTEX.x += sin(t) * wave_amp * clamp(UV.y < 0.5 ? 1.0 : 0.3, 0.0, 1.0);
		VERTEX.z += cos(t * 0.8) * wave_amp * 0.6;
	}
}

void fragment() {
	vec4 d = texture(diffuse_tex, UV);
	vec3 lm = use_lightmap ? texture(lightmap_tex, UV2).rgb * lightmap_strength : vec3(1.0);
	ALBEDO = d.rgb * lm * tint.rgb * 4.59 * brightness;
	ALPHA = d.a * tint.a;
}
