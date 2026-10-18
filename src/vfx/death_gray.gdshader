shader_type canvas_item;
// League-style grey world while the player is dead.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 g = vec3(l) * vec3(0.92, 0.95, 1.0) * 0.85;
	COLOR = vec4(mix(c, g, amount), 1.0);
}
