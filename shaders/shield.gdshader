shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never, fog_disabled;
// Dark Kat's energy shield: a blue bubble with a bright rim, a faint hex lattice and a flash
// where a missile struck it.

uniform float pulse = 0.0;
uniform float alpha = 1.0;

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float lat = smoothstep(0.82, 1.0, abs(sin(UV.x * 52.0)) * abs(sin(UV.y * 30.0 + UV.x * 6.0)));
	float shimmer = 0.5 + 0.5 * sin(TIME * 2.4 + UV.y * 20.0);
	vec3 c = vec3(0.22, 0.55, 1.0) * (0.1 + rim * 1.5 + lat * (0.25 + 0.5 * rim) * (0.6 + 0.4 * shimmer));
	c += vec3(0.7, 0.9, 1.0) * pulse * (0.5 + rim);
	ALBEDO = c;
	ALPHA = clamp(0.25 + rim + lat * 0.4 + pulse, 0.0, 1.0) * alpha;
}
