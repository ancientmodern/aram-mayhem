shader_type spatial;
// Additive glowing sprite/mesh used for orbs, sparks and particles.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.6, 0.2, 1.0);
uniform float energy = 2.0;
uniform sampler2D mask_tex : source_color, filter_linear;
uniform bool use_mask = true;
uniform bool billboard = false;
uniform float core = 0.35;

void vertex() {
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
		MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
				vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
				vec4(0.0, 0.0, 0.0, 1.0));
	}
}

void fragment() {
	float a = 1.0;
	if (use_mask) {
		vec4 mt = texture(mask_tex, UV);
		a = mt.a * max(mt.r, 0.0);
	} else {
		float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		a = pow(ndv, 1.5);
	}
	vec4 vc = COLOR;
	vec3 c = mix(color.rgb, vec3(1.0), smoothstep(1.0 - core, 1.0, a) * 0.8);
	float alpha = a * color.a * vc.a;
	ALBEDO = c * energy * vc.rgb * alpha;
	ALPHA = alpha;
}
