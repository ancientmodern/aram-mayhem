shader_type canvas_item;
// [fow] League fog-of-war visibility update (one pass of fogofwar/fade.ps + the circle raster League does on the CPU).
// Renders the player's team visibility v into a 256x256 half-float target covering the 12877.5-unit map:
//   target  = max over sight sources of a soft disc (sight range), cut by the brush rule used by Match._seen_by
//             (a cell in a brush is only seen from inside that brush or within 1.5 m) and by terrain occlusion
//   v(t+dt) = v + clamp(target - v, -hide, +reveal)         asymmetric reveal / hide speeds
// The result ping-pongs between two viewports (prev = the other viewport's texture). See src/render/fow_map.gd.
render_mode blend_disabled;

uniform sampler2D prev : filter_nearest, repeat_disable;
uniform sampler2D nav : filter_nearest, repeat_disable;   // R = walkable (255), G = brush id * 50
uniform vec4 nav_rect = vec4(0.0, 0.0, 1.0, 1.0);          // origin x, origin z, 1 / size x, 1 / size z (meters)
uniform vec4 src[64];                                      // x, z, sight range, brush id
uniform int src_count = 0;
uniform float extent = 128.775;
uniform vec2 step_rate = vec2(0.2, 0.06);                  // reveal / hide per update
uniform float reset = 0.0;                                 // 1 = snap to the target (first frames)
uniform float occlusion = 1.0;
const float WALL_BLOCK_MIN = 1.2;                          // meters of non-walkable ray length that start to hide a cell
const float WALL_BLOCK_MAX = 2.2;
const float EDGE_SOFT = 0.9;                               // half-width of the disc edge, meters
const float BRUSH_RANGE = 1.5;                             // Match._seen_by: same-brush rule exempts d <= 1.5 m

vec4 nav_at(vec2 xz) {
	vec2 uv = (xz - nav_rect.xy) * nav_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return vec4(0.0);
	}
	return textureLod(nav, uv, 0.0);
}

void fragment() {
	vec2 p = vec2(UV.x, -UV.y) * extent;
	float cell_brush = floor(nav_at(p).g * 255.0 / 50.0 + 0.5);
	float t = 0.0;
	for (int i = 0; i < src_count; i++) {
		vec4 s = src[i];
		vec2 dv = p - s.xy;
		float d = length(dv);
		if (d > s.z + EDGE_SOFT) {
			continue;
		}
		float cov = 1.0 - smoothstep(s.z - EDGE_SOFT, s.z + EDGE_SOFT, d);
		if (cell_brush > 0.5 && abs(cell_brush - s.w) > 0.5) {
			cov *= 1.0 - smoothstep(BRUSH_RANGE - 0.3, BRUSH_RANGE + 0.5, d);
		}
		if (occlusion > 0.5 && cov > t && d > BRUSH_RANGE) {
			// terrain occlusion: walk the ray, accumulate the length spent on non-walkable ground
			float blocked = 0.0;
			float seg = d / 16.0;
			for (int k = 1; k < 16; k++) {
				blocked += (1.0 - nav_at(s.xy + dv * (float(k) / 16.0)).r) * seg;
			}
			cov *= 1.0 - smoothstep(WALL_BLOCK_MIN, WALL_BLOCK_MAX, blocked);
		}
		t = max(t, cov);
	}
	float v = texture(prev, UV).r;
	v = reset > 0.5 ? t : v + clamp(t - v, -step_rate.y, step_rate.x);
	COLOR = vec4(v, 0.0, 0.0, 1.0);
}
