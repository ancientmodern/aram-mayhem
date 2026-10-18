// [fow] League fog of war (docs/LEAGUE_SHADERS.md section 5, fogofwar/applyoverlayandcolor).
// Include AFTER res://src/render/gamma.gdshaderinc (uses gamma_out / gamma_dec). All values are gamma-space.
//   fow_vis   : R = blurred visibility v of the player's team, one texel per 0.5 m over the 12877.5-unit map extent,
//               written by src/render/fow_map.gd (Godot (x, z) = League (x, -z) * 0.01).
//   FOW.rgb = lerp(overlay.rgb, edgeColor, saturate(v * EDGE_Z));   FOW.a = lerp(overlay.a, 1, v)
// Map12 Base overlay (assets/maps/info/map12/fogofwaroverlay.tex) is a flat (0.051, 0.125, 0.216, 0.40) texture, so
// the animated UV of the overlay has nothing to scroll.
global uniform sampler2D fow_vis : filter_linear, repeat_disable;
global uniform float fow_on;   // 0 = no fog of war (menus, tests, spectator)

const float FOW_EXTENT = 128.775;                    // meters covered by fow_vis (League 12877.525 units)
const vec4 FOW_OVERLAY = vec4(0.051, 0.125, 0.216, 0.40);
const vec3 FOW_EDGE_COLOR = vec3(0.20, 0.07, 0.06);
const float FOW_EDGE_Z = 1.0;                        // FOW_EDGE_CONTROL.z (CPU value, not in the shader cache)
// FOW_HEIGHT_FADE (CPU): geometry this far above the playfield (floor y ~ -2) ignores the fog, like League's tall
// terrain. Not recoverable from the shader cache; kept high so only far scenery is affected.
const vec2 FOW_HEIGHT_FADE = vec2(1.0 / 14.0, -1.0);   // saturate(world_y * x + y)

vec4 fow_map(vec3 w) {
	if (fow_on < 0.5) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	float v = textureLod(fow_vis, vec2(w.x, -w.z) / FOW_EXTENT, 0.0).r;
	return vec4(mix(FOW_OVERLAY.rgb, FOW_EDGE_COLOR, clamp(v * FOW_EDGE_Z, 0.0, 1.0)), mix(FOW_OVERLAY.a, 1.0, clamp(v, 0.0, 1.0)));
}

// what the shader must write for a gamma-space colour
vec3 fow_out(vec3 g) {
	return gamma_out > 0.5 ? g : gamma_dec(g);
}

// environment k: fow.a + fowH * (1 - fow.a); c = lerp(fow.rgb, c, k)
float fow_env_k(vec4 f, float world_y) {
	float h = clamp(world_y * FOW_HEIGHT_FADE.x + FOW_HEIGHT_FADE.y, 0.0, 1.0);
	return f.a + h * (1.0 - f.a);
}

// quad particles: rgb *= FOW.a
float fow_particle_mul(vec3 w) {
	return fow_map(w).a;
}
