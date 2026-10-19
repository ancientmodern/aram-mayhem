shader_type canvas_item;
// [hud-ref] League's dead-world look, exactly the gamma/ps_gamma DEATH_EFFECT branch (docs/LEAGUE_SHADERS.md section 6):
//   g = lerp(c, 0.8 * lum601(c) + 0.2 * c, F)        (a partial desaturation that keeps 20% of the colour)
//   out = lerp(lerp(c, TINT.rgb, TINT.a), g, F)       (TINT.a is 0 in play, so out = g)
// No darkening, contrast change or vignette (the old version added all three and looked far too dark / flat).
// F = `amount` is driven by Moments.drive_gray (0.55 s ease-in on death, 0.3 s ease-out on respawn); the screen texture is
// sampled in the engine's output (gamma) space, the space League runs the formula in.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec3 c = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 g = mix(c, vec3(0.8 * l) + 0.2 * c, amount);
	COLOR = vec4(g, 1.0);
}
