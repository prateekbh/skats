shader_type spatial;
// Megakat Bay: cheap animated swell made from summed sine waves (no textures needed). The swell
// calms with distance so it never aliases into a checkerboard near the horizon.

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	float calm = smoothstep(400.0, 2500.0, length(VERTEX));
	float w = sin(p.x * 0.031 + t * 0.9) * 0.5 + sin(p.y * 0.047 - t * 1.3) * 0.35 + sin((p.x + p.y) * 0.021 + t * 0.6) * 0.4;
	vec3 n = normalize(vec3(cos(p.x * 0.031 + t * 0.9) * 0.08 * (1.0 - calm), 1.0, cos(p.y * 0.047 - t * 1.3) * 0.08 * (1.0 - calm)));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	float shade = mix(w * 0.28 + 0.5, 0.5, calm);
	ALBEDO = mix(vec3(0.05, 0.28, 0.42), vec3(0.14, 0.52, 0.64), shade);
	METALLIC = 0.0;
	SPECULAR = 0.9;
	ROUGHNESS = mix(0.06, 0.25, calm);
}
