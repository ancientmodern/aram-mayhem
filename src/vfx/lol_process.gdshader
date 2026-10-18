shader_type particles;
// League emitter simulation: birth values with probability-table ranges, per-axis scale curves,
// rotation/spin, velocity + drag + acceleration, color curves (incl. lookup textures), flipbook frames.

uniform int shape_type = 0;            // 0 point, 1 sphere, 2 box, 3 cylinder
uniform float shape_radius = 0.0;
uniform vec3 shape_box = vec3(0.0);
uniform float shape_height = 0.0;
uniform vec3 shape_offset = vec3(0.0);

uniform float life_lo = 1.0;           // min / max lifetime ratio

uniform vec3 vel_base = vec3(0.0);
uniform vec3 vel_lo = vec3(1.0);
uniform vec3 vel_hi = vec3(1.0);
uniform vec3 drag = vec3(0.0);
uniform vec3 accel = vec3(0.0);

uniform vec3 scale_base = vec3(1.0);
uniform vec3 scale_lo = vec3(1.0);
uniform vec3 scale_hi = vec3(1.0);
uniform bool uniform_scale = false;
uniform bool has_scale_curve = false;
uniform sampler2D scale_curve : repeat_disable, filter_linear;

uniform vec3 rot_base = vec3(0.0);     // degrees (already arranged per orientation by LolVfx)
uniform vec3 rot_lo = vec3(1.0);       // random multipliers (League probability tables)
uniform vec3 rot_hi = vec3(1.0);
uniform int spin_axis = 2;             // axis the spin is added to (free quads / meshes)
uniform float spin_base = 0.0;         // degrees / second around the spin axis
uniform float spin_lo = 1.0;
uniform float spin_hi = 1.0;
uniform int orient = 0;                // 0 camera billboard, 1 free (arbitrary quad), 2 ground (Y up), 3 mesh, 4 velocity aligned

uniform vec4 color_base = vec4(1.0);
uniform vec4 color_lo = vec4(1.0);
uniform vec4 color_hi = vec4(1.0);
uniform bool has_color_curve = false;
uniform sampler2D color_curve : repeat_disable, filter_linear;

uniform float frames = 1.0;
uniform float fps = 0.0;
uniform bool rand_frame = false;
uniform float start_frame = 0.0;
uniform vec2 uv_off_lo = vec2(0.0);    // random birth uv offset range
uniform vec2 uv_off_hi = vec2(0.0);

float rnd(inout uint seed) {
	int k;
	int s = int(seed);
	if (s == 0) {
		s = 305420679;
	}
	k = s / 127773;
	s = 16807 * (s - k * 127773) - 2836 * k;
	if (s < 0) {
		s += 2147483647;
	}
	seed = uint(s);
	return float(seed % uint(65536)) / 65535.0;
}

uint hash(uint x) {
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = ((x >> uint(16)) ^ x) * uint(73244475);
	x = (x >> uint(16)) ^ x;
	return x;
}

uniform int rot_order = 0;             // euler order for free quads / meshes (calibration)

mat3 rot_euler(vec3 d) {
	vec3 r = radians(d);
	float cx = cos(r.x); float sx = sin(r.x);
	float cy = cos(r.y); float sy = sin(r.y);
	float cz = cos(r.z); float sz = sin(r.z);
	mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cx, sx), vec3(0.0, -sx, cx));
	mat3 ry = mat3(vec3(cy, 0.0, -sy), vec3(0.0, 1.0, 0.0), vec3(sy, 0.0, cy));
	mat3 rz = mat3(vec3(cz, sz, 0.0), vec3(-sz, cz, 0.0), vec3(0.0, 0.0, 1.0));
	if (rot_order == 1) { return rx * ry * rz; }
	if (rot_order == 2) { return rz * ry * rx; }
	if (rot_order == 3) { return rz * rx * ry; }
	if (rot_order == 4) { return ry * rz * rx; }
	if (rot_order == 5) { return rx * rz * ry; }
	return ry * rx * rz;
}

void start() {
	uint seed = hash(NUMBER + uint(1) + RANDOM_SEED);
	CUSTOM = vec4(0.0);
	CUSTOM.w = mix(life_lo, 1.0, rnd(seed));
	// position
	vec3 p = shape_offset;
	if (shape_type == 1) {
		vec3 d = normalize(vec3(rnd(seed) * 2.0 - 1.0, rnd(seed) * 2.0 - 1.0, rnd(seed) * 2.0 - 1.0) + vec3(0.0001));
		p += d * shape_radius * pow(rnd(seed), 0.333);
	} else if (shape_type == 2) {
		p += (vec3(rnd(seed), rnd(seed), rnd(seed)) * 2.0 - 1.0) * shape_box;
	} else if (shape_type == 3) {
		float a = rnd(seed) * TAU;
		p += vec3(cos(a), 0.0, sin(a)) * shape_radius * sqrt(rnd(seed)) + vec3(0.0, rnd(seed) * shape_height, 0.0);
	}
	// scale
	vec3 rs = vec3(rnd(seed), rnd(seed), rnd(seed));
	if (uniform_scale) {
		rs = vec3(rs.x);
	}
	vec3 s = scale_base * mix(scale_lo, scale_hi, rs);
	if (uniform_scale) {
		s = vec3(s.x);
	}
	USERDATA1.xyz = s;
	// rotation (stored per axis in USERDATA3, spin in USERDATA1.w)
	vec3 rot = rot_base * mix(rot_lo, rot_hi, vec3(rnd(seed), rnd(seed), rnd(seed)));
	USERDATA3 = vec4(rot, 0.0);
	USERDATA1.w = spin_base * mix(spin_lo, spin_hi, rnd(seed));
	CUSTOM.x = radians(-rot.z);
	// velocity
	vec3 v = vel_base * mix(vel_lo, vel_hi, vec3(rnd(seed), rnd(seed), rnd(seed)));
	// color
	USERDATA2 = color_base * mix(color_lo, color_hi, vec4(rnd(seed), rnd(seed), rnd(seed), rnd(seed)));
	COLOR = USERDATA2;
	// flipbook
	CUSTOM.z = rand_frame ? floor(rnd(seed) * frames) : start_frame;
	USERDATA4 = vec4(mix(uv_off_lo, uv_off_hi, vec2(rnd(seed), rnd(seed))), 0.0, 0.0);
	TRANSFORM = EMISSION_TRANSFORM * mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(p, 1.0));
	VELOCITY = (EMISSION_TRANSFORM * vec4(v, 0.0)).xyz;
}

void process() {
	float life = CUSTOM.y;
	CUSTOM.y += DELTA / max(LIFETIME * CUSTOM.w, 0.001);
	if (CUSTOM.y >= 1.0) {
		ACTIVE = false;
	}
	life = clamp(CUSTOM.y, 0.0, 1.0);
	VELOCITY += accel * DELTA;
	VELOCITY -= VELOCITY * clamp(drag * DELTA, vec3(0.0), vec3(1.0));
	// scale over life
	vec3 s = USERDATA1.xyz;
	if (has_scale_curve) {
		vec3 k = texture(scale_curve, vec2(life, 0.5)).rgb;
		s *= uniform_scale ? vec3(k.x) : k;
	}
	// rotation / orientation
	USERDATA3.w += USERDATA1.w * DELTA;
	float spin = USERDATA3.w;
	vec3 rot = USERDATA3.xyz;
	mat3 b;
	if (orient == 0) {
		CUSTOM.x = radians(-(rot.z + spin));
		b = mat3(vec3(s.x, 0.0, 0.0), vec3(0.0, s.y, 0.0), vec3(0.0, 0.0, 1.0));
	} else if (orient == 2) {
		mat3 ry = rot_euler(vec3(0.0, -(rot.z + spin), 0.0));
		b = ry * mat3(vec3(s.x, 0.0, 0.0), vec3(0.0, 1.0, 0.0), vec3(0.0, 0.0, s.y));
	} else if (orient == 3) {
		vec3 rs = rot;
		rs[spin_axis] += spin;
		b = rot_euler(rs) * mat3(vec3(s.x, 0.0, 0.0), vec3(0.0, s.y, 0.0), vec3(0.0, 0.0, s.z));
	} else if (orient == 4) {
		vec3 y = length(VELOCITY) > 0.0001 ? normalize(VELOCITY) : vec3(0.0, 1.0, 0.0);
		vec3 x = normalize(cross(y, abs(y.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
		vec3 z = cross(x, y);
		b = mat3(x * s.x, y * s.y, z);
	} else {
		vec3 rs = rot;
		rs[spin_axis] += spin;
		b = rot_euler(rs) * mat3(vec3(s.x, 0.0, 0.0), vec3(0.0, s.y, 0.0), vec3(0.0, 0.0, max(s.z, 0.001)));
	}
	if (orient == 1 || orient == 2 || orient == 3) {
		b = mat3(EMISSION_TRANSFORM) * b;   // follow the effect's facing (cast direction)
	}
	TRANSFORM[0].xyz = b[0];
	TRANSFORM[1].xyz = b[1];
	TRANSFORM[2].xyz = b[2];
	// color
	vec4 c = USERDATA2;
	if (has_color_curve) {
		c *= texture(color_curve, vec2(life, 0.5));
	}
	COLOR = c;
	// flipbook
	if (frames > 1.0) {
		if (fps > 0.0) {
			CUSTOM.z += fps * DELTA;
		} else {
			CUSTOM.z = start_frame + floor(life * frames);
		}
	}
}
