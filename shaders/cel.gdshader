shader_type spatial;
// Cartoon cel shading for the TurboKat: hard-edged light bands, a crisp glossy highlight
// (the white glints on the black hull in the show) and a rim light so dark paint still
// reads against a dusk sky. Highlights and rim go to SPECULAR_LIGHT so black albedo can't
// swallow them.

uniform vec4 albedo : source_color = vec4(1.0);
// Colour multiplier in the shadow band (a cool tint reads better than plain grey).
uniform vec4 shadow_tint : source_color = vec4(0.42, 0.42, 0.58, 1.0);
// Where the bright band starts (0..1 on N·L) and how soft the band edges are.
uniform float highlight_band = 0.55;
uniform float band_softness = 0.03;
// Glossy highlight: shininess and the cut-off that turns it into a hard cartoon shape.
uniform float gloss = 48.0;
uniform float gloss_cutoff = 0.55;
uniform float gloss_strength = 0.9;
// Rim light.
uniform vec4 rim_color : source_color = vec4(0.55, 0.65, 1.0, 1.0);
uniform float rim_width = 0.84;
uniform float rim_strength = 0.35;
// Self-lit parts (canopy glass).
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;

void fragment() {
	ALBEDO = albedo.rgb;
	EMISSION = emission_color.rgb * emission_energy;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = smoothstep(-band_softness, band_softness, ndl) * ATTENUATION;
	float bright = smoothstep(highlight_band - band_softness, highlight_band + band_softness, ndl) * ATTENUATION;
	vec3 tone = mix(shadow_tint.rgb, vec3(1.0), lit * 0.55 + bright * 0.45);
	DIFFUSE_LIGHT += tone * LIGHT_COLOR / PI;

	vec3 h = normalize(LIGHT + VIEW);
	float spec = pow(max(dot(NORMAL, h), 0.0), gloss);
	SPECULAR_LIGHT += step(gloss_cutoff, spec) * lit * gloss_strength * LIGHT_COLOR / PI;

	float fresnel = 1.0 - max(dot(NORMAL, VIEW), 0.0);
	float rim = smoothstep(rim_width - 0.02, rim_width + 0.02, fresnel) * (0.25 + 0.75 * lit);
	SPECULAR_LIGHT += rim * rim_color.rgb * rim_strength * LIGHT_COLOR / PI;
}
