shader_type spatial;
// Howling Abyss environment: diffuse texture * baked lightmap (League "baked diffuse").
// The baked colour is the final colour; the only dynamic lighting is the sun's shadow map (units and structures
// cast soft shadows onto the ground like League) plus a small additive share of nearby VFX point lights.
// Ambient and specular are disabled so the lightmap colours stay exactly as baked.
render_mode cull_disabled, ambient_light_disabled, specular_disabled;
#include "res://src/render/gamma.gdshaderinc"
#include "res://src/render/fow.gdshaderinc"   // [fow]

// [env-look] sampled RAW (no source_color): League samples every texture without sRGB decode and filters
// (bilinear / trilinear / anisotropic) on the stored gamma values. With source_color the GPU decoded to linear,
// filtered there and gamma_enc re-encoded: same texel values but averaged in the wrong space (lighter edges and
// minified detail). The legacy linear path decodes by hand.
uniform sampler2D diffuse_tex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D lightmap_tex : filter_linear, repeat_disable;
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
// League's exact DefaultEnv_Flat (decompiled, docs/LEAGUE_SHADERS.md section 4), gamma pipeline only:
//   c = overlay(diffuse, TintColor) * (lightmap.rgb * 2 + sunColor * max(N.L, 0) * min(pcf5, lightmap.a))
// lightmap alpha = baked sun-shadow mask; the live shadow only removes the sun term, never the baked light
uniform bool league_exact = true;
uniform vec3 sun_color = vec3(0.365, 0.384, 0.392);   // Map12 MapSunProperties.sunColor (gamma, raw)
uniform float lightmap_color_scale = 2.0;             // Map12 MapSunProperties.lightMapColorScale
varying vec3 v_bake;
varying float v_sunmask;
// [env-look] debug views for src/debug/env_look_probe.gd (exact path only): 1 = overlay(diffuse, tint) only,
// 2 = baked light (lightmap.rgb * scale) * 0.5, 3 = live sun term only, 4 = lightmap alpha (sun mask)
uniform int debug_view = 0;
// [env-look] CALIBRATION, NOT League math: a per-channel gain fitted to captured League frames (docs/ENV_LOOK.md).
// Everything above is exact (shader cache formula, bit-exact textures, output chain proven exact), yet on matched map
// surfaces of reference frames 1, 2 and 5 League is cooler: R x0.91, G x1.05, B x1.15 (luminance x1.02; equal in
// sun-lit and baked-shadow cells, so not the sun term). The capture path was checked on flat UI (shop icons: neutral,
// +9/255 black lift, removed before fitting); the source of the shift (CPU constant, patch re-bake, stream) is unknown.
// gain * (D * L) == (gain * D) * L, so applying it to the albedo is exact. false = the pure League formula.
uniform bool calibrate = true;
const vec3 CALIB_GAIN = vec3(0.911, 1.049, 1.151);

bool exact() {
	return league_exact && use_lightmap && gamma_out > 0.5;
}

vec3 overlay(vec3 a, vec3 t) {
	return mix(2.0 * a * t, 1.0 - 2.0 * (1.0 - a) * (1.0 - t), step(vec3(0.5), a));
}

void fragment() {
	vec4 d = texture(diffuse_tex, UV);
	if (d.a < alpha_test) {
		discard;
	}
	if (exact()) {
		vec4 lmt = texture(lightmap_tex, UV2);
		v_bake = lmt.rgb * lightmap_color_scale;
		v_sunmask = lmt.a;
		ALBEDO = overlay(d.rgb, gamma_enc(tint.rgb)) * brightness;
		if (calibrate && debug_view == 0) {
			ALBEDO *= CALIB_GAIN;
		}
		if (debug_view > 1) {
			ALBEDO = vec3(1.0);
		}
	} else {
		vec3 lm = use_lightmap ? gamma_dec(texture(lightmap_tex, UV2).rgb) * lightmap_strength : vec3(1.0);
		vec3 col = gamma_dec(d.rgb) * lm * tint.rgb * 4.59 * brightness;
		float l = dot(col, vec3(0.299, 0.587, 0.114));
		col = mix(vec3(l), col, saturation);
		vec3 g = pow(max(col, vec3(0.0)), vec3(1.0 / 2.2));
		g = max(mix(vec3(0.5), g * grade_gain * grade_tint, grade_contrast), vec3(0.0));
		ALBEDO = to_out(pow(g, vec3(2.2)));
	}
	// [fow] DefaultEnv_Flat: c = lerp(FOW.rgb, c, k). The final colour is albedo * light + emission, so scaling the
	// albedo by k and adding the fog colour as emission is the same lerp, whatever lights (sun, point) are summed.
	vec4 fw = fow_map((INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	float fk = fow_env_k(fw, (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).y);
	ALBEDO *= fk;
	EMISSION += fow_out(fw.rgb) * (1.0 - fk);
}

void light() {
	if (exact()) {
		if (LIGHT_IS_DIRECTIONAL) {
			vec3 sun = sun_color * max(dot(NORMAL, LIGHT), 0.0) * min(ATTENUATION, v_sunmask);
			if (debug_view == 0) {
				DIFFUSE_LIGHT += v_bake + sun;
			} else if (debug_view == 1) {
				DIFFUSE_LIGHT += vec3(1.0);
			} else if (debug_view == 2) {
				DIFFUSE_LIGHT += v_bake * 0.5;
			} else if (debug_view == 3) {
				DIFFUSE_LIGHT += sun;
			} else {
				DIFFUSE_LIGHT += vec3(v_sunmask);
			}
		}
	} else if (LIGHT_IS_DIRECTIONAL) {
		// ATTENUATION carries the shadow term; the light's colour/angle are already baked into the lightmap
		DIFFUSE_LIGHT += to_out(mix(shadow_color, vec3(1.0), ATTENUATION));
	} else {
		DIFFUSE_LIGHT += to_out(LIGHT_COLOR * ATTENUATION * max(dot(NORMAL, LIGHT), 0.0) * point_light_share);
	}
}
