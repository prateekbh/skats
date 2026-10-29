shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled;
// Camera-facing cartoon flashes on a quad: impact stars and shockwave rings.
// One MultiMesh per shape; INSTANCE_CUSTOM = (age 0..1, seed, intensity, 0).

uniform int shape = 0; // 0 = star, 1 = ring
uniform vec4 core_color : source_color = vec4(1.0, 0.98, 0.85, 1.0);
uniform vec4 edge_color : source_color = vec4(1.0, 0.6, 0.15, 1.0);

varying float v_age;
varying float v_seed;
varying float v_int;

void vertex() {
	v_age = INSTANCE_CUSTOM.x;
	v_seed = INSTANCE_CUSTOM.y;
	v_int = INSTANCE_CUSTOM.z;
	// Billboard while keeping the instance's scale.
	float s = length(MODEL_MATRIX[0].xyz);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s, INV_VIEW_MATRIX[1] * s, INV_VIEW_MATRIX[2] * s, MODEL_MATRIX[3]);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x) + v_seed * 6.2831;
	float alpha = 0.0;
	vec3 col = core_color.rgb;
	if (shape == 0) {
		// Spiky star: radius modulated by a sharp cosine; shrinks as it ages.
		float spikes = 4.0 + floor(v_seed * 3.0) * 2.0;
		float star = 0.28 + 0.62 * pow(abs(cos(a * spikes * 0.5)), 6.0);
		star *= 1.0 - v_age * 0.6;
		alpha = step(r, star);
		col = mix(core_color.rgb, edge_color.rgb, smoothstep(star * 0.35, star, r));
	} else {
		// Expanding ring that thins out.
		float width = mix(0.22, 0.03, v_age);
		alpha = step(abs(r - 0.82), width * 0.5);
		col = mix(core_color.rgb, edge_color.rgb, v_age);
	}
	alpha *= (1.0 - v_age) * v_int;
	if (alpha <= 0.01) {
		discard;
	}
	ALBEDO = col * alpha;
}
