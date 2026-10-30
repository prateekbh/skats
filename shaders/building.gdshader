shader_type spatial;
// Megakat City towers. Windows are laid out in world space, so they stay the same size
// whatever height a building is scaled to. INSTANCE_CUSTOM.r seeds which windows are lit.
// Missile damage (City.damage_at): INSTANCE_CUSTOM.g is the impact height (0 = undamaged) and
// .b / .a its offset from the centre in half-widths; around it the wall is scorched black with
// a burnt-out hole and flickering embers. With `deform` the box itself is bent (see vertex()).
// COLOR.a < 0.5 marks a broken roof: the top floors
// are charred too, independently of the wall hit.

varying vec3 world_pos;
varying vec3 world_normal;
varying float seed;
varying vec3 impact;
varying float damaged;
varying float top;
varying float roof_burnt;
varying float dent;
uniform bool deform = false; // set on the damaged-buildings MultiMesh only

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	seed = INSTANCE_CUSTOM.r;
	dent = 0.0;
	damaged = step(0.5, INSTANCE_CUSTOM.g);
	vec3 scl = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	top = MODEL_MATRIX[3].y + scl.y * 0.5;
	roof_burnt = 1.0 - step(0.5, COLOR.a);
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec2 half_size = scl.xz * 0.5;
	impact = vec3(centre.x + INSTANCE_CUSTOM.b * half_size.x, INSTANCE_CUSTOM.g, centre.z + INSTANCE_CUSTOM.a * half_size.y);
	if (deform) {
		// Bend the (subdivided) box. Every offset is a function of position only, so vertices
		// shared by two faces move together and the building stays closed. world_pos keeps the
		// undeformed position, so windows and scorch stay put on the bent walls.
		vec3 d = vec3(0.0);
		float k = clamp((world_pos.y - (centre.y - scl.y * 0.5)) / scl.y, 0.0, 1.0);
		float n = hash(floor(world_pos.xz * 0.25 + 0.5) + floor(world_pos.y * 0.2 + 0.5) * 3.1 + seed * 17.0);
		if (damaged > 0.5) {
			// Crater punched in around the hit.
			float r = 0.45 * min(scl.x, scl.z) + 8.0;
			float f = clamp(1.0 - length(world_pos - impact) / r, 0.0, 1.0);
			f = f * f * (3.0 - 2.0 * f);
			vec2 inward = centre.xz - impact.xz;
			inward = length(inward) > 0.01 ? normalize(inward) : vec2(0.0);
			d.xz += inward * f * r * (0.35 + 0.3 * n);
			d.y -= f * 4.0 * n;
			dent = f;
			// The whole tower leans away from the blow, more towards the top.
			d.xz += inward * scl.y * 0.045 * k * k;
		}
		if (roof_burnt > 0.5) {
			// Broken roofline: the top floors sag into a jagged edge.
			float j = hash(floor(world_pos.xz * 0.2 + 0.5) + seed * 5.0);
			d.y -= smoothstep(0.88, 1.0, k) * (4.0 + j * 14.0);
		}
		VERTEX += d / scl;
	}
}

// 0 = clean, 1 = scorched, 2 = burnt-out hole, with jagged edges.
float scorch(vec3 p) {
	float jag = hash(floor(p.xz * 0.35) + floor(p.y * 0.3)) - 0.5;
	float s = 0.0;
	if (roof_burnt > 0.5) {
		s = step(top - 16.0 + jag * 8.0, p.y); // charred top floors
	}
	if (damaged > 0.5) {
		vec3 q = p - impact;
		q.y *= 0.8; // scorch climbs the wall a little
		float d = length(q) + jag * 6.0;
		s = max(s, step(d, 24.0) + step(d, 9.0));
	}
	return s;
}

void fragment() {
	vec3 wall = COLOR.rgb * 0.32;
	float burnt = scorch(world_pos);
	float flicker = 0.65 + 0.35 * sin(TIME * 9.0 + hash(floor(world_pos.xy * 0.5)) * 6.28);
	if (burnt > 1.5) {
		// The hole: charred black with glowing embers in the cracks.
		float ember = step(0.62, hash(floor(world_pos.xz * 0.9) + floor(world_pos.y * 0.9) * 7.0));
		ALBEDO = vec3(0.02);
		EMISSION = vec3(1.0, 0.38, 0.08) * ember * flicker * 2.2;
		ROUGHNESS = 1.0;
	} else if (world_normal.y > 0.5) {
		ALBEDO = burnt > 0.5 ? vec3(0.03) : vec3(0.08, 0.085, 0.11);
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
		if (burnt > 0.5) {
			// Scorched: soot-black wall, windows blown out, a few still glowing with fire.
			wall = vec3(0.035, 0.03, 0.03);
			lit = vec3(1.0, 0.45, 0.12) * flicker;
			on *= step(0.75, hash(id * 2.3 + seed));
		}
		ALBEDO = mix(wall, vec3(0.04, 0.05, 0.08), win) * (1.0 - dent * 0.6); // shadowed crater
		EMISSION = lit * win * on * 1.7;
		ROUGHNESS = mix(0.85, 0.15, win);
	}
}
