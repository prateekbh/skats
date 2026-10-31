shader_type spatial;
render_mode cull_disabled;
// Terrain for the whole of Megakat's world. City.gd bakes each vertex colour from the plan
// (grass, parks, sand, rock, snow); COLOR.a marks built-up ground, drawn as dark asphalt so the
// streets read between the paved lots of the buildings.

varying vec3 world_pos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float n = vnoise(p * 0.02) * 0.6 + vnoise(p * 0.11) * 0.3 + vnoise(p * 0.7) * 0.1;
	vec3 natural = COLOR.rgb * (0.82 + 0.34 * n);
	vec3 asphalt = vec3(0.14, 0.14, 0.16) + 0.04 * vnoise(p * 0.35);
	ALBEDO = mix(natural, asphalt, COLOR.a);
	ROUGHNESS = 0.95;
}
