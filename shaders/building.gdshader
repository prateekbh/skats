shader_type spatial;
// Megakat City towers. Windows are laid out in world space, so they stay the same size
// whatever height a building is scaled to. INSTANCE_CUSTOM.r seeds which windows are lit.

varying vec3 world_pos;
varying vec3 world_normal;
varying float seed;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	seed = INSTANCE_CUSTOM.r;
}

void fragment() {
	vec3 wall = COLOR.rgb * 0.32;
	if (world_normal.y > 0.5) {
		ALBEDO = vec3(0.08, 0.085, 0.11);
		ROUGHNESS = 0.95;
	} else {
		float u = abs(world_normal.x) > 0.5 ? world_pos.z : world_pos.x;
		vec2 cell = vec2(u / 4.2, world_pos.y / 4.8);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float win = step(0.2, f.x) * step(f.x, 0.8) * step(0.22, f.y) * step(f.y, 0.78);
		win *= step(4.8, world_pos.y);
		float on = step(0.52, hash(id + seed * 113.0));
		vec3 warm = vec3(1.0, 0.76, 0.42);
		vec3 cool = vec3(0.55, 0.8, 1.0);
		vec3 lit = mix(warm, cool, step(0.78, hash(id * 1.7 + seed * 31.0)));
		ALBEDO = mix(wall, vec3(0.04, 0.05, 0.08), win);
		EMISSION = lit * win * on * 1.7;
		ROUGHNESS = mix(0.85, 0.15, win);
	}
}
