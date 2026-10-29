shader_type spatial;
// Megakat Bay: cheap animated swell made from summed sine waves (no textures needed).

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float t = TIME;
	float w = sin(p.x * 0.031 + t * 0.9) * 0.5 + sin(p.y * 0.047 - t * 1.3) * 0.35 + sin((p.x + p.y) * 0.021 + t * 0.6) * 0.4;
	vec3 n = normalize(vec3(cos(p.x * 0.031 + t * 0.9) * 0.08, 1.0, cos(p.y * 0.047 - t * 1.3) * 0.08));
	NORMAL = (VIEW_MATRIX * vec4(n, 0.0)).xyz;
	ALBEDO = mix(vec3(0.04, 0.12, 0.2), vec3(0.08, 0.22, 0.32), w * 0.5 + 0.5);
	METALLIC = 0.3;
	ROUGHNESS = 0.12;
}
