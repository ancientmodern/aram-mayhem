shader_type spatial;
// Howling Abyss environment: diffuse texture * baked lightmap (League "baked diffuse").
render_mode unshaded, cull_disabled;

uniform sampler2D diffuse_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lightmap_tex : source_color, filter_linear, repeat_disable;
uniform vec4 tint : source_color = vec4(0.5, 0.5, 0.5, 1.0);
uniform bool use_lightmap = true;
uniform float lightmap_strength = 4.59;
uniform float brightness = 1.0;
uniform float alpha_test = 0.0;
uniform float saturation = 1.06;

void fragment() {
	vec4 d = texture(diffuse_tex, UV);
	if (d.a < alpha_test) {
		discard;
	}
	vec3 lm = use_lightmap ? texture(lightmap_tex, UV2).rgb * lightmap_strength : vec3(1.0);
	vec3 col = d.rgb * lm * tint.rgb * 4.59 * brightness;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(l), col, saturation);
	ALBEDO = col;
}
