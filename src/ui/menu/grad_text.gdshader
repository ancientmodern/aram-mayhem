shader_type canvas_item;
// League-style gold header gradient for big display text (titles, champion names, VICTORY/DEFEAT).
// Applied to a Label: white glyphs take the vertical top->mid->bottom gradient, black outline/shadow stay black.
// y0/y1 = vertical gradient extent in the label's local pixels, shine = horizontal sweep position (0..1, <0 = off).

uniform vec4 top : source_color = vec4(0.992, 0.969, 0.898, 1.0);
uniform vec4 mid : source_color = vec4(0.941, 0.902, 0.824, 1.0);
uniform vec4 bottom : source_color = vec4(0.784, 0.667, 0.431, 1.0);
uniform float mid_at = 0.5;
uniform float y0 = 0.0;
uniform float y1 = 100.0;
uniform float x0 = 0.0;
uniform float x1 = 100.0;
uniform float shine = -1.0;
uniform float shine_width = 0.12;

varying vec2 lp;

void vertex() {
	lp = VERTEX;
}

void fragment() {
	float t = clamp((lp.y - y0) / max(y1 - y0, 1.0), 0.0, 1.0);
	vec3 g = t < mid_at ? mix(top.rgb, mid.rgb, t / max(mid_at, 0.001)) : mix(mid.rgb, bottom.rgb, (t - mid_at) / max(1.0 - mid_at, 0.001));
	float lum = max(COLOR.r, max(COLOR.g, COLOR.b));
	vec3 c = COLOR.rgb * g;
	if (shine >= 0.0) {
		float sx = (lp.x - x0) / max(x1 - x0, 1.0);
		float band = smoothstep(shine_width, 0.0, abs(sx - shine));
		c += vec3(band * 0.55) * step(0.05, lum);
	}
	COLOR = vec4(c, COLOR.a);
}
