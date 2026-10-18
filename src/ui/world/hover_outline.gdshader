shader_type spatial;
// League hover outline: a crisp coloured silhouette (red = enemy, blue = ally) around the hovered unit.
// Inverted hull applied as `material_overlay` (champion.gdshader is untouched). The hull is extruded in
// clip space along the projected normal so the line is a constant `width_px` on screen at any zoom, and is
// pushed slightly away from the camera so only the silhouette survives the depth test (no interior lines).
render_mode unshaded, cull_front, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

uniform vec4 outline_color : source_color = vec4(1.0, 0.2, 0.15, 1.0);
uniform float width_px = 2.5;
uniform float depth_push = 0.25;   // metres

void vertex() {
	vec4 vpos = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vpos.xyz += normalize(vpos.xyz) * depth_push;
	vec4 clip = PROJECTION_MATRIX * vpos;
	vec3 vn = normalize(MODELVIEW_NORMAL_MATRIX * NORMAL);
	vec2 cn = (PROJECTION_MATRIX * vec4(vn, 0.0)).xy;
	float l = length(cn);
	if (l > 1e-5) {
		cn /= l;
		clip.xy += cn * width_px * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
