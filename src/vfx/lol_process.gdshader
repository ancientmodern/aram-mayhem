shader_type particles;
// League emitter simulation (VfxEmitterDefinitionData), driven by LolVfx:
//  - birth values: base x probability-table quantile (rand_lut) x emitter-time curve (birth_lut)
//  - emission shapes: sphere / box / cylinder (flag 1 = radial velocity frame), legacy offset + rotation angles
//  - motion: velocity, drag, world + local acceleration, orbital velocity, noise / attraction fields
//  - over life: per-axis scale curve, color curve (incl. lookup textures), rotation + spin, flipbooks

uniform int shape_type = 0;            // 0 point, 1 sphere, 2 box, 3 cylinder
uniform float shape_radius = 0.0;
uniform vec3 shape_box = vec3(0.0);
uniform float shape_height = 0.0;
uniform bool shape_radial = false;     // velocity is expressed in the frame of the emission point's azimuth
uniform vec3 shape_offset = vec3(0.0);
uniform int emit_rots = 0;             // legacy emitRotationAngles count (angles come from rand_lut row 7)
uniform vec3 emit_axis0 = vec3(0.0, 1.0, 0.0);
uniform vec3 emit_axis1 = vec3(0.0, 1.0, 0.0);

// rows of rand_lut (32 quantiles each): 0 life, 1 scale, 2 velocity, 3 rotation, 4 spin, 5 color, 6 offset,
// 7 emit angles (deg), 8 orbit, 9 drag
uniform sampler2D rand_lut : repeat_disable, filter_nearest;
uniform bool has_rand = false;
// rows of birth_lut (16 samples over the emitter's life): 0 color, 1 scale (final units), 2 velocity
uniform sampler2D birth_lut : repeat_disable, filter_linear;
uniform bool has_birth_color = false;
uniform bool has_birth_scale = false;
uniform bool has_birth_vel = false;
uniform bool birth_live = false;       // single-particle emitters: birth values follow the emitter's age
uniform float emit_life = 1.0;         // emitter lifetime (s) for birth curves
uniform float emit_rate = 0.0;         // particles / s (emitter time of a particle = NUMBER / rate)

uniform float life_scale = 1.0;        // particle life = LIFETIME * life_scale * random quantile

uniform vec3 vel_base = vec3(0.0);
uniform vec3 drag = vec3(0.0);
uniform vec3 accel = vec3(0.0);        // world space
uniform vec3 laccel = vec3(0.0);       // emitter space
uniform vec3 orbit = vec3(0.0);        // radians / s around the emitter axes
uniform vec4 noise = vec4(0.0);        // xyz axis weights, w = velocity delta (m/s)
uniform float noise_freq = 1.0;
uniform vec4 attract = vec4(0.0);      // xyz position (emitter space), w = acceleration (m/s^2)
uniform float field_drag = 0.0;

uniform vec3 scale_base = vec3(1.0);
uniform bool uniform_scale = false;
uniform bool has_scale_curve = false;
uniform sampler2D scale_curve : repeat_disable, filter_linear;
uniform vec2 dir_stretch = vec2(0.0);  // isDirectionOriented: x = League directionVelocityScale (per m/s), y = min

uniform vec3 rot_base = vec3(0.0);     // degrees (already arranged per orientation by LolVfx)
uniform int spin_axis = 2;             // axis the spin is added to (free quads / meshes)
uniform float spin_base = 0.0;         // degrees / second around the spin axis
uniform int orient = 0;                // 0 camera billboard, 1 free (arbitrary quad), 2 ground (Y up), 3 mesh,
                                       // 4 velocity aligned billboard, 5 ray (camera facing, along birth direction)

uniform vec4 color_base = vec4(1.0);
uniform bool has_color_curve = false;
uniform sampler2D color_curve : repeat_disable, filter_linear;

uniform float frames = 1.0;
uniform float fps = 0.0;
uniform bool rand_frame = false;
uniform float start_frame = 0.0;
uniform vec2 uv_off_lo = vec2(0.0);    // random birth uv offset range
uniform vec2 uv_off_hi = vec2(0.0);
uniform bool uv_off_pack = false;     // no flipbook: CUSTOM.z carries the birth uv offset (8+8 bits) to the material
uniform int rot_order = 4;             // euler order for free quads / meshes (calibration)

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

vec4 q(int row, float r) {
	if (!has_rand) {
		return vec4(1.0);
	}
	return texelFetch(rand_lut, ivec2(clamp(int(r * 32.0), 0, 31), row), 0);
}

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

mat3 axis_angle(vec3 axis, float a) {
	vec3 n = normalize(axis);
	float c = cos(a);
	float s = sin(a);
	float t = 1.0 - c;
	return mat3(vec3(t * n.x * n.x + c, t * n.x * n.y + s * n.z, t * n.x * n.z - s * n.y),
			vec3(t * n.x * n.y - s * n.z, t * n.y * n.y + c, t * n.y * n.z + s * n.x),
			vec3(t * n.x * n.z + s * n.y, t * n.y * n.z - s * n.x, t * n.z * n.z + c));
}

float emitter_t(float age, uint num) {
	// normalized emitter time used to sample birth curves (NUMBER is only visible in the stage functions)
	if (birth_live) {
		return clamp(age / max(emit_life, 0.001), 0.0, 1.0);
	}
	if (emit_rate <= 0.0) {
		return 0.0;
	}
	return clamp(float(num) / emit_rate / max(emit_life, 0.001), 0.0, 1.0);
}

void start() {
	uint seed = hash(NUMBER + uint(1) + RANDOM_SEED);
	CUSTOM = vec4(0.0);
	CUSTOM.w = q(0, rnd(seed)).x * life_scale;
	float et = emitter_t(0.0, NUMBER);
	// ---- emission position (emitter space)
	vec3 p = shape_offset * q(6, rnd(seed)).xyz;
	float az = 0.0;
	if (shape_type == 1) {
		vec3 d = normalize(vec3(rnd(seed) * 2.0 - 1.0, rnd(seed) * 2.0 - 1.0, rnd(seed) * 2.0 - 1.0) + vec3(0.0001));
		p += d * shape_radius * pow(rnd(seed), 0.333);
		az = atan(d.z, d.x);
	} else if (shape_type == 2) {
		p += (vec3(rnd(seed), rnd(seed), rnd(seed)) * 2.0 - 1.0) * shape_box;
	} else if (shape_type == 3) {
		az = rnd(seed) * TAU;
		p += vec3(cos(az), 0.0, sin(az)) * shape_radius * sqrt(rnd(seed)) + vec3(0.0, rnd(seed) * shape_height, 0.0);
	} else if (shape_radial) {
		az = rnd(seed) * TAU;
	}
	// ---- velocity (emitter space)
	vec3 v = (has_birth_vel ? texture(birth_lut, vec2(et, 2.5 / 3.0)).xyz : vel_base) * q(2, rnd(seed)).xyz;
	if (shape_radial && (shape_type == 1 || shape_type == 3)) {
		// x = outward, z = tangential around the emitter's up axis
		float ca = cos(az);
		float sa = sin(az);
		v = vec3(v.x * ca - v.z * sa, v.y, v.x * sa + v.z * ca);
	}
	if (emit_rots > 0) {
		vec4 ang = q(7, rnd(seed));
		mat3 r0 = axis_angle(emit_axis0, radians(ang.x));
		p = r0 * p;
		v = r0 * v;
		if (emit_rots > 1) {
			mat3 r1 = axis_angle(emit_axis1, radians(ang.y));
			p = r1 * p;
			v = r1 * v;
		}
	}
	// ---- scale
	float rs = rnd(seed);
	vec3 sq = q(1, uniform_scale ? rs : rnd(seed)).xyz;
	if (uniform_scale) {
		sq = vec3(q(1, rs).x);
	}
	vec3 sb = has_birth_scale ? texture(birth_lut, vec2(et, 1.5 / 3.0)).xyz : scale_base;
	vec3 s = sb * sq;
	if (uniform_scale) {
		s = vec3(s.x);
	}
	USERDATA1.xyz = s;
	// ---- rotation (stored per axis in USERDATA3, spin in USERDATA1.w)
	vec3 rot = rot_base * q(3, rnd(seed)).xyz;
	USERDATA3 = vec4(rot, 0.0);
	USERDATA1.w = spin_base * q(4, rnd(seed)).x;
	CUSTOM.x = radians(-rot.z);
	// ---- color
	vec4 cb = has_birth_color ? texture(birth_lut, vec2(et, 0.5 / 3.0)) : vec4(1.0);
	USERDATA2 = color_base * cb * q(5, rnd(seed));
	COLOR = USERDATA2;
	// ---- flipbook / uv offset
	CUSTOM.z = rand_frame ? floor(rnd(seed) * frames) : start_frame;
	USERDATA4 = vec4(mix(uv_off_lo, uv_off_hi, vec2(rnd(seed), rnd(seed))), 0.0, 0.0);
	if (uv_off_pack) {
		vec2 o = fract(USERDATA4.xy);
		CUSTOM.z = floor(o.x * 255.0) * 256.0 + floor(o.y * 255.0);
	}
	// ---- orbit / drag / origin
	mat3 eb = mat3(EMISSION_TRANSFORM);
	USERDATA5 = vec4(EMISSION_TRANSFORM[3].xyz, rnd(seed) * 100.0);   // origin + noise phase
	USERDATA6 = vec4(eb * (orbit * q(8, rnd(seed)).xyz), 0.0);
	TRANSFORM = EMISSION_TRANSFORM * mat4(vec4(1.0, 0.0, 0.0, 0.0), vec4(0.0, 1.0, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(p, 1.0));
	VELOCITY = eb * v;
	if (orient == 5) {
		// ray: direction from the birth rotation (yaw/pitch of +Z), stored in USERDATA4.zw (yaw, pitch)
		vec3 d = rot_euler(rot) * vec3(0.0, 0.0, -1.0);
		d = normalize(eb * d);
		USERDATA4.z = atan(d.x, d.z);
		USERDATA4.w = asin(clamp(d.y, -1.0, 1.0));
	}
}

void process() {
	CUSTOM.y += DELTA / max(LIFETIME * CUSTOM.w, 0.001);
	if (CUSTOM.y >= 1.0) {
		ACTIVE = false;
	}
	float life = clamp(CUSTOM.y, 0.0, 1.0);
	float age = CUSTOM.y * LIFETIME * CUSTOM.w;
	mat3 eb = mat3(EMISSION_TRANSFORM);
	// ---- forces
	vec3 a = accel + eb * laccel;
	vec3 origin = USERDATA5.xyz;
	if (attract.w != 0.0) {
		vec3 to = (EMISSION_TRANSFORM * vec4(attract.xyz, 1.0)).xyz - TRANSFORM[3].xyz;
		a += normalize(to + vec3(0.0001)) * attract.w;
	}
	if (noise.w > 0.0) {
		float ph = USERDATA5.w + TIME * noise_freq * 6.2831;
		vec3 n = vec3(sin(ph), sin(ph * 1.37 + 1.3), sin(ph * 0.71 + 2.9)) * noise.xyz;
		a += n * noise.w * noise_freq * 2.0;
	}
	VELOCITY += a * DELTA;
	vec3 dg = drag * q(9, fract(USERDATA5.w * 0.618)).xyz + vec3(field_drag);
	VELOCITY -= VELOCITY * clamp(dg * DELTA, vec3(0.0), vec3(1.0));
	if (dot(USERDATA6.xyz, USERDATA6.xyz) > 0.000001) {
		float w = length(USERDATA6.xyz);
		mat3 r = axis_angle(USERDATA6.xyz, w * DELTA);
		TRANSFORM[3].xyz = origin + r * (TRANSFORM[3].xyz - origin);
		VELOCITY = r * VELOCITY;
	}
	// ---- scale over life
	vec3 s = USERDATA1.xyz;
	if (birth_live && has_birth_scale) {
		vec3 sb = texture(birth_lut, vec2(emitter_t(age, uint(0)), 1.5 / 3.0)).xyz;
		s = sb * (s / max(scale_base, vec3(0.00001)));
	}
	if (has_scale_curve) {
		vec3 k = texture(scale_curve, vec2(life, 0.5)).rgb;
		s *= uniform_scale ? vec3(k.x) : k;
	}
	// ---- rotation / orientation
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
		float st = 1.0;
		if (dir_stretch.x > 0.0) {
			st = max(dir_stretch.y, length(VELOCITY) * 100.0 * dir_stretch.x);
		}
		b = mat3(x * s.x, y * s.y * st, z);
	} else if (orient == 5) {
		// ray: Y axis along the stored direction; the material turns it to face the camera around that axis
		float yaw = USERDATA4.z;
		float pit = USERDATA4.w;
		vec3 y = vec3(sin(yaw) * cos(pit), sin(pit), cos(yaw) * cos(pit));
		vec3 x = normalize(cross(y, abs(y.y) < 0.99 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
		vec3 z = cross(x, y);
		float len = max(s.z, s.y);
		b = mat3(x * s.x, y * len, z);
	} else {
		vec3 rs = rot;
		rs[spin_axis] += spin;
		b = rot_euler(rs) * mat3(vec3(s.x, 0.0, 0.0), vec3(0.0, s.y, 0.0), vec3(0.0, 0.0, max(s.z, 0.001)));
	}
	if (orient == 1 || orient == 2 || orient == 3) {
		b = eb * b;   // follow the effect's facing (cast direction)
	}
	TRANSFORM[0].xyz = b[0];
	TRANSFORM[1].xyz = b[1];
	TRANSFORM[2].xyz = b[2];
	// ---- color
	vec4 c = USERDATA2;
	if (birth_live && has_birth_color) {
		c = color_base * texture(birth_lut, vec2(emitter_t(age, uint(0)), 0.5 / 3.0));
	}
	if (has_color_curve) {
		c *= texture(color_curve, vec2(life, 0.5));
	}
	COLOR = c;
	// ---- flipbook
	if (frames > 1.0) {
		if (fps > 0.0) {
			CUSTOM.z += fps * DELTA;
		} else {
			CUSTOM.z = start_frame + floor(life * frames);
		}
	}
}
