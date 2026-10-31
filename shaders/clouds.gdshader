shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;
// A single huge plane of drifting cumulus high above the city: cheap value-noise fbm, lit white on
// top with a blue-grey underside, fading out toward the horizon so it never shows an edge.

varying vec3 wp;

void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float h2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vn(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h2(i), h2(i + vec2(1, 0)), f.x), mix(h2(i + vec2(0, 1)), h2(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float s = 0.0;
	for (int i = 0; i < 4; i++) {
		s += a * vn(p);
		p = p * 2.03 + vec2(17.0, 9.0);
		a *= 0.5;
	}
	return s;
}

void fragment() {
	vec2 p = wp.xz * 0.00055 + vec2(TIME * 0.004, TIME * 0.0015);
	float n = fbm(p);
	float c = smoothstep(0.5, 0.74, n);
	float dist = length(wp.xz - CAMERA_POSITION_WORLD.xz);
	float fade = 1.0 - smoothstep(9000.0, 26000.0, dist);
	float lit = smoothstep(0.5, 0.8, fbm(p + vec2(0.06, 0.03)));
	vec3 col = mix(vec3(0.62, 0.7, 0.84), vec3(1.0, 0.97, 0.92), clamp(1.0 - (lit - c) * 2.0 + 0.2, 0.0, 1.0) * (CAMERA_POSITION_WORLD.y < wp.y ? 0.75 : 1.0));
	ALBEDO = col;
	ALPHA = c * fade * 0.92;
}
