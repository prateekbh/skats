shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;
// The Pastmaster's time vortex, from the show's frame: pale blue cloud bands spiralling around a
// dark spiral centre, with jagged magenta lightning flickering inside. Drawn on a camera-facing
// quad, so it always looks like a flat swirling disc.

uniform float open = 1.0; // 0 closed .. 1 fully open (grows from the centre)
uniform float spin = 0.45;
uniform float flash = 0.0; // extra brightness pulse

float h(float n) { return fract(sin(n * 127.1) * 43758.5453); }

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = h(i.x + i.y * 57.0);
	float b = h(i.x + 1.0 + i.y * 57.0);
	float c = h(i.x + (i.y + 1.0) * 57.0);
	float d = h(i.x + 1.0 + (i.y + 1.0) * 57.0);
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	// Billboard: face the camera, keep the model's scale.
	vec3 scl = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	mat4 m = mat4(INV_VIEW_MATRIX[0] * scl.x, INV_VIEW_MATRIX[1] * scl.y, INV_VIEW_MATRIX[2] * scl.z, MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * m;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0 / max(open, 0.05);
	float r = length(p);
	float a = atan(p.y, p.x);
	float t = TIME * spin;
	// Spiral coordinate: bands wind inward and turn with time.
	float s = a * 2.0 + log(max(r, 0.02)) * 5.0 - t * 6.2831;
	float band = smoothstep(0.1, 0.5, sin(s * 1.5) * 0.5 + 0.5);
	// Outer cloud ring: lumpy white-blue bands.
	float lump = vnoise(vec2(s * 1.3, r * 6.0 + t * 3.0));
	float ring = smoothstep(0.52, 0.62, r) * (1.0 - smoothstep(0.86, 1.0, r + lump * 0.1 - 0.05));
	float cloud = ring * smoothstep(0.25, 0.65, band * 0.7 + lump * 0.6);
	vec3 cloud_col = mix(vec3(0.35, 0.5, 0.85), vec3(0.88, 0.95, 1.0), band);
	// Dark spiral centre.
	float core = 1.0 - smoothstep(0.5, 0.6, r);
	float stripes = smoothstep(0.35, 0.65, sin(s * 3.0 + 1.5) * 0.5 + 0.5);
	vec3 core_col = mix(vec3(0.02, 0.05, 0.16), vec3(0.1, 0.2, 0.42), stripes);
	// Lightning: a few jagged bolts that re-roll about 8 times a second.
	float tick = floor(TIME * 8.0);
	float bolt = 0.0;
	for (int k = 0; k < 3; k++) {
		float seed = tick * 3.0 + float(k);
		float ang = h(seed) * 6.2831;
		vec2 dir = vec2(cos(ang), sin(ang));
		vec2 perp = vec2(-dir.y, dir.x);
		float along = dot(p, dir);
		float wob = (vnoise(vec2(along * 7.0, seed)) - 0.5) * 0.3 + (vnoise(vec2(along * 19.0, seed + 9.0)) - 0.5) * 0.08;
		float d = abs(dot(p, perp) - wob);
		float alive = step(0.35, h(seed + 4.0)) * step(abs(along - 0.1), 0.6);
		bolt += alive * (smoothstep(0.035, 0.0, d) + 0.35 * smoothstep(0.11, 0.0, d));
	}
	bolt *= core;
	vec3 col = core_col * core + cloud_col * cloud;
	col = mix(col, vec3(1.0, 0.35, 0.9), clamp(bolt, 0.0, 1.0));
	col += vec3(0.5, 0.6, 1.0) * flash * (core * 0.6 + cloud);
	float alpha = clamp(core + cloud, 0.0, 1.0) * (1.0 - smoothstep(0.96, 1.0, r)) * clamp(open * 1.5, 0.0, 1.0);
	ALBEDO = col;
	ALPHA = alpha;
}
