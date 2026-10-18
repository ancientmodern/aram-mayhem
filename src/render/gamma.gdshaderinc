// League colour pipeline (see src/render/gamma_decode_effect.gd): with gamma_out = 1 shaders write
// gamma-encoded colour so transparent effects blend in gamma space like League; the compositor effect
// decodes the buffer after the transparent pass.
global uniform float gamma_out;

vec3 gamma_enc(vec3 l) {
	l = max(l, vec3(0.0));
	return mix(l * 12.92, 1.055 * pow(l, vec3(1.0 / 2.4)) - 0.055, step(vec3(0.0031308), l));
}

// linear colour -> what this shader must write
vec3 to_out(vec3 l) {
	return gamma_out > 0.5 ? gamma_enc(l) : l;
}

vec3 gamma_dec(vec3 g) {
	g = max(g, vec3(0.0));
	return mix(g / 12.92, pow((g + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), g));
}
