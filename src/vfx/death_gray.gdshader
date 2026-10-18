shader_type canvas_item;
// [juice] League's dead-world look: full desaturation (Rec.601 luma, no colour cast), a hair more contrast and a
// slightly dimmer picture; a very light vignette keeps the eye on the corpse. `amount` is driven by
// Moments.drive_gray (0.55 s ease-in on death, 0.3 s ease-out on respawn).
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 g = vec3(l);
	g = (g - 0.5) * 1.07 + 0.5;
	g *= 0.9;
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.0, 0.9);
	float vig = smoothstep(0.38, 0.98, length(d));
	g *= 1.0 - 0.16 * vig;
	COLOR = vec4(mix(c, g, amount), 1.0);
}
