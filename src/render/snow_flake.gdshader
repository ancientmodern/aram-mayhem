shader_type spatial;
// [look2] Camera snow flakes drawn like League's HA_Env_Snow_01 "Snow" emitter (Map12 MapAmbient systems): texture
// env_mb_snow_flakes (opaque alpha, RGB max 33/36/41 of 255) blended additively (blendMode 0, premultiplied) on gamma
// values, brightness over life from color-bellramp. So a flake adds at most ~40/255: very faint, as in live frames.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
#include "res://src/render/gamma.gdshaderinc"

uniform sampler2D flakes : filter_linear_mipmap, repeat_disable;   // raw values (League samples without sRGB decode)
uniform sampler2D ramp : filter_linear, repeat_disable;
varying float v_life;

void vertex() {
	// GPUParticles billboard (same as BaseMaterial3D BILLBOARD_PARTICLES)
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(MAIN_CAM_INV_VIEW_MATRIX[0], MAIN_CAM_INV_VIEW_MATRIX[1],
			MAIN_CAM_INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
			vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_life = INSTANCE_CUSTOM.y;   // ParticleProcessMaterial: age / lifetime
}

void fragment() {
	vec3 c = texture(flakes, UV).rgb * texture(ramp, vec2(clamp(v_life, 0.0, 1.0), 0.5)).rgb;
	ALBEDO = gamma_out > 0.5 ? c : gamma_dec(c);
}
