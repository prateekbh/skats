shader_type spatial;
render_mode diffuse_toon, specular_toon, cull_disabled;
// One piece of a target cut apart by the Slicer / Buzz-Saw: the model is drawn only between two
// parallel cut planes (in the model root's space). Back faces seen through the open cut and a
// thin seam along it glow molten orange, cooling as `heat` falls.

uniform vec4 albedo : source_color = vec4(1.0);
uniform float metal = 0.2;
uniform float rough = 0.55;
uniform bool glow = false;
uniform mat4 part_xform; // part -> model root
uniform vec3 cut_n = vec3(1.0, 0.0, 0.0);
uniform float cut_lo = -1000.0;
uniform float cut_hi = 1000.0;
uniform float heat = 1.0;

varying vec3 root_pos;

void vertex() {
	root_pos = (part_xform * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float d = dot(root_pos, cut_n);
	if (d < cut_lo || d > cut_hi) {
		discard;
	}
	float seam = min(d - cut_lo, cut_hi - d);
	vec3 hot = mix(vec3(0.9, 0.18, 0.05), vec3(1.0, 0.75, 0.35), heat);
	if (!FRONT_FACING) {
		ALBEDO = vec3(0.04);
		EMISSION = hot * (0.4 + 2.6 * heat);
	} else {
		ALBEDO = albedo.rgb;
		METALLIC = metal;
		ROUGHNESS = rough;
		if (seam < 0.16) {
			EMISSION = hot * 3.0 * heat;
		}
		if (glow) {
			EMISSION += albedo.rgb * 1.5;
		}
	}
}
