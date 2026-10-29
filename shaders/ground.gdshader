shader_type spatial;
// Street grid drawn procedurally in world space: asphalt roads, lane dashes, sidewalks,
// and scrubland outside the city limits.

uniform float cell_size = 90.0;
uniform float city_half = 1260.0;
uniform float road_half_width = 13.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float in_city = step(abs(p.x), city_half) * step(abs(p.y), city_half);
	vec2 g = mod(p + city_half, cell_size);
	vec2 d = min(g, cell_size - g);
	float near = min(d.x, d.y);
	float road = step(near, road_half_width);
	float along = d.x < d.y ? p.y : p.x;
	float dash = step(near, 0.45) * step(0.5, fract(along / 14.0));
	vec3 scrub = vec3(0.17, 0.19, 0.13) + 0.03 * sin(p.x * 0.01) * sin(p.y * 0.013);
	vec3 asphalt = vec3(0.1, 0.1, 0.12);
	vec3 sidewalk = vec3(0.21, 0.2, 0.22);
	vec3 col = mix(sidewalk, asphalt, road);
	col = mix(col, vec3(0.95, 0.75, 0.2), dash);
	ALBEDO = mix(scrub, col, in_city);
	ROUGHNESS = 0.95;
}
