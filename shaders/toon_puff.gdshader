shader_type spatial;
render_mode unshaded, cull_back;
// Cartoon fireball / smoke puff, drawn as a lumpy sphere with hard colour bands.
// One MultiMesh draws every puff; INSTANCE_CUSTOM = (age 0..1, seed, kind, 0).
// kind: 0 fire, 0.33 smoke, 0.66 dust, 1 trail smoke.

uniform vec3 sun_dir = vec3(-0.6, 0.45, 0.3);

varying float v_age;
varying float v_seed;
varying float v_kind;
varying float v_tint;
varying vec3 v_obj;
varying vec3 v_world_normal;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i + vec3(0, 0, 0)), hash(i + vec3(1, 0, 0)), f.x),
			mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x),
			mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	v_age = INSTANCE_CUSTOM.x;
	v_seed = INSTANCE_CUSTOM.y;
	v_kind = INSTANCE_CUSTOM.z;
	v_tint = INSTANCE_CUSTOM.w;
	// Lumpy silhouette: push vertices out by noise so no two puffs look alike.
	float n = noise(VERTEX * 2.2 + v_seed * 37.0);
	VERTEX += NORMAL * (n - 0.45) * 0.42;
	v_obj = VERTEX;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	// Break-up: the puff erodes into chunks as it ages.
	float erode = noise(v_obj * 3.1 + v_seed * 11.0);
	if (erode < smoothstep(0.45, 1.0, v_age) * 1.05) {
		discard;
	}
	float edge = 1.0 - max(dot(NORMAL, VIEW), 0.0); // view-space rim, inked edge
	float light = dot(v_world_normal, normalize(sun_dir));
	vec3 col;
	if (v_kind < 0.15) {
		// Fire: heat falls with age and towards the rim; hard bands.
		float heat = 1.15 - v_age * 1.5 - edge * 0.55 + (erode - 0.5) * 0.25;
		if (heat > 0.8) col = vec3(1.0, 0.97, 0.78);
		else if (heat > 0.55) col = vec3(1.0, 0.82, 0.22);
		else if (heat > 0.32) col = vec3(1.0, 0.46, 0.1);
		else if (heat > 0.12) col = vec3(0.78, 0.16, 0.07);
		else col = light > 0.1 ? vec3(0.32, 0.27, 0.28) : vec3(0.18, 0.15, 0.17);
	} else {
		vec3 lit_col = vec3(0.42, 0.39, 0.42);
		vec3 dark_col = vec3(0.22, 0.2, 0.23);
		if (v_kind > 0.5 && v_kind < 0.85) { lit_col = vec3(0.6, 0.5, 0.4); dark_col = vec3(0.38, 0.31, 0.26); }
		if (v_kind >= 0.85) {
			// Missile trails: 0 white smoke, 1 Octopus pink ink, 2 Scrambler blue haze.
			lit_col = vec3(0.86, 0.85, 0.86); dark_col = vec3(0.58, 0.57, 0.62);
			if (v_tint > 0.5 && v_tint < 1.5) { lit_col = vec3(0.95, 0.48, 0.78); dark_col = vec3(0.62, 0.2, 0.48); }
			if (v_tint >= 1.5) { lit_col = vec3(0.55, 0.8, 1.0); dark_col = vec3(0.25, 0.45, 0.85); }
		}
		col = light > 0.15 ? lit_col : dark_col;
	}
	// Ink rim for the cel look.
	if (edge > 0.82) {
		col *= 0.35;
	}
	ALBEDO = col;
}
