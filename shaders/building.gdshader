shader_type spatial;
// Megakat City facades. One shader draws every building part (MultiMesh instances of a unit box,
// cylinder, gable prism or cone) and the hand-built landmarks.
//
// Per instance:  COLOR.rgb = wall colour, COLOR.a < 0.5 = broken roof (top floors charred)
//                INSTANCE_CUSTOM.r = style + seed (style 0..11, +20 for a round part)
//                .g/.b/.a = damage: impact height and its offset from the centre (City.damage_at)
// Landmarks (single MeshInstance3D) set use_uniforms and the u_* values instead.
//
// Windows, brick courses and panels are laid out in the part's own metres, so they stay the same
// size whatever a part is scaled to, follow its rotation, and don't swim when it is bent.

uniform bool deform = false; // damaged-building MultiMeshes: bend the (subdivided) mesh
uniform bool use_uniforms = false;
uniform float u_style = 0.0;
uniform vec4 u_color : source_color = vec4(0.7, 0.7, 0.7, 1.0);
uniform float u_seed = 0.3;
uniform float u_height = 40.0;

varying vec3 world_pos;
varying vec3 lp; // position in the part's own metres, centred
varying vec3 ln; // local normal
varying float v_style;
varying float seed;
varying vec3 base_col;
varying float part_h;
varying vec3 impact;
varying float damaged;
varying float top;
varying float roof_burnt;
varying float dent;
varying vec3 half_ext; // half size of the part (metres), for corner details

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void vertex() {
	vec3 scl = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	vec4 cus = INSTANCE_CUSTOM;
	vec4 col = COLOR;
	if (use_uniforms) {
		scl = vec3(1.0);
		cus = vec4(u_style + u_seed, 0.0, 0.0, 0.0);
		col = u_color;
	}
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	lp = VERTEX * scl;
	half_ext = use_uniforms ? vec3(1.0e4) : scl * 0.5;
	ln = NORMAL;
	v_style = floor(cus.x + 0.001);
	seed = fract(cus.x + 0.001);
	base_col = col.rgb;
	part_h = use_uniforms ? u_height : scl.y;
	dent = 0.0;
	damaged = step(0.5, cus.y);
	top = MODEL_MATRIX[3].y + scl.y * 0.5;
	roof_burnt = 1.0 - step(0.5, col.a);
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec2 half_size = scl.xz * 0.5;
	impact = vec3(centre.x + cus.z * half_size.x, cus.y, centre.z + cus.w * half_size.y);
	if (deform) {
		// Bend the (subdivided) box. Every offset is a function of position only, so vertices
		// shared by two faces move together and the building stays closed. world_pos keeps the
		// undeformed position, so windows and scorch stay put on the bent walls.
		vec3 d = vec3(0.0);
		float k = clamp((world_pos.y - (centre.y - scl.y * 0.5)) / scl.y, 0.0, 1.0);
		float n = hash(floor(world_pos.xz * 0.25 + 0.5) + floor(world_pos.y * 0.2 + 0.5) * 3.1 + seed * 17.0);
		if (damaged > 0.5) {
			float r = 0.45 * min(scl.x, scl.z) + 8.0;
			float f = clamp(1.0 - length(world_pos - impact) / r, 0.0, 1.0);
			f = f * f * (3.0 - 2.0 * f);
			vec2 inward = centre.xz - impact.xz;
			inward = length(inward) > 0.01 ? normalize(inward) : vec2(0.0);
			d.xz += inward * f * r * (0.35 + 0.3 * n);
			d.y -= f * 4.0 * n;
			dent = f;
			d.xz += inward * min(scl.y, 160.0) * 0.045 * k * k;
		}
		if (roof_burnt > 0.5) {
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
		q.y *= 0.8;
		float d = length(q) + jag * 6.0;
		s = max(s, step(d, 24.0) + step(d, 9.0));
	}
	return s;
}

// Window light colours: each building leans warm, white or cool; a few windows glow orange or blue (TV).
vec3 lightc(vec2 id, float b) {
	float r = hash(id * 1.31 + vec2(seed * 7.0, 2.0));
	vec3 base = b < 0.35 ? vec3(1.0, 0.76, 0.42) : (b < 0.7 ? vec3(1.0, 0.96, 0.88) : vec3(0.62, 0.82, 1.0));
	vec3 alt = r < 0.9 ? vec3(1.0, 0.55, 0.22) : vec3(0.5, 0.62, 1.0);
	return mix(base, alt, step(0.78, r));
}

void fragment() {
	int st = int(v_style);
	bool round_s = st >= 20;
	if (round_s) {
		st -= 20;
	}
	// Coordinates on the wall: u along it, v up from the part's base (metres).
	float u;
	if (round_s) {
		u = atan(lp.z, lp.x) * max(length(lp.xz), 0.5);
	} else {
		vec2 nh = ln.xz;
		float nl = length(nh);
		vec2 nd = nl > 0.001 ? nh / nl : vec2(1.0, 0.0);
		u = lp.x * -nd.y + lp.z * nd.x;
	}
	float v = lp.y + part_h * 0.5;
	bool top_face = ln.y > 0.7;
	if (st == 13) {
		// Fire escape: rails, landings and a stair stripe; everything else is see-through.
		float rail = step(0.95, abs(u));
		float landing = step(fract(v / 3.1), 0.09);
		float stair = step(abs(fract((v - u * 1.1) / 3.1) - 0.5), 0.035) * step(abs(u), 0.95) * step(0.09, fract(v / 3.1));
		if (max(rail, max(landing, stair)) < 0.5 || top_face) {
			discard;
		}
	}
	// Per-building character from the seed: an accent colour (awnings, trim) and a window-light bias.
	float gy = world_pos.y - 0.7; // height above the street
	float acc_h = hash(vec2(seed * 91.7, 3.1));
	vec3 accent = clamp(vec3(0.5) + 0.5 * cos(6.2831 * (vec3(0.0, 0.33, 0.67) + acc_h)), 0.0, 1.0);
	accent = mix(vec3(0.55), accent, 0.7);
	float bias = hash(vec2(seed * 17.3, 9.1));
	// Panels of slightly different tone across the facade.
	vec3 wall = base_col * (0.9 + 0.2 * hash(floor(vec2(u, v) / 7.0) + vec2(seed * 13.0, 5.0)));
	vec3 warm = vec3(1.0, 0.76, 0.42);
	vec3 cool = vec3(0.55, 0.8, 1.0);
	vec3 alb = wall;
	vec3 emi = vec3(0.0);
	float rough = 0.85;
	float metal = 0.0;
	float burnt = scorch(world_pos);
	float winm = 0.0; // 1 inside a window
	vec2 wf = vec2(0.5); // position in the window cell
	vec4 wb = vec4(0.0); // window rectangle in the cell: x0, x1, y0, y1

	if (st == 7) {
		// Lot pad: paving with expansion joints, lawn for green pads.
		vec2 g = fract(world_pos.xz / 9.0);
		float joint = step(g.x, 0.025) + step(g.y, 0.025);
		bool green = wall.g > wall.r * 1.15;
		alb = top_face ? (green ? wall * (0.9 + 0.2 * hash(floor(world_pos.xz / 14.0))) : wall * (1.0 - 0.22 * min(joint, 1.0))) : wall * 0.5;
	} else if (st == 12) {
		// Stone trim: plinths and cornices, faint block joints.
		alb = wall * (0.94 + 0.1 * hash(floor(vec2(u, v) / 1.6)));
		alb *= 1.0 - 0.12 * step(fract(v / 1.6), 0.06);
		if (!top_face) {
			alb *= 0.8 + 0.2 * smoothstep(0.0, 1.0, v / max(part_h, 0.5));
		}
		rough = 0.8;
	} else if (st == 8) {
		alb = wall * 0.25;
		emi = wall * 2.4;
	} else if (st == 6) {
		// Gable roof: courses of tiles.
		float course = step(0.88, fract(v / 0.7));
		alb = wall * (1.0 - 0.3 * course) * (0.92 + 0.16 * hash(vec2(floor(v / 0.7), floor(u / 0.9))));
		rough = 0.9;
	} else if (top_face) {
		// Flat roofs: gravel and dark membrane, with the odd vent.
		float patch = hash(floor(world_pos.xz / 6.0));
		alb = wall * (0.22 + 0.1 * patch);
		rough = 0.95;
	} else if (st == 0) {
		// Glass curtain wall: ribbons of glass between mullions, sunset reflections.
		vec2 cell = vec2(u / 3.2, v / 3.9);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float win = step(0.07, f.x) * step(f.x, 0.93) * step(0.1, f.y) * step(f.y, 0.9);
		winm = win; wf = f; wb = vec4(0.07, 0.93, 0.1, 0.9);
		float on = step(0.7, hash(id + seed * 113.0));
		vec3 glass = mix(wall * 0.85, vec3(0.3, 0.46, 0.7), 0.3);
		float refl = smoothstep(0.35, 1.0, sin(v * 0.035 + u * 0.012 + seed * 20.0));
		glass += vec3(0.32, 0.16, 0.1) * refl * 0.7 + vec3(0.1, 0.18, 0.28) * smoothstep(0.0, 1.0, v / max(part_h, 1.0)) * 0.5;
		alb = mix(wall * 0.35, glass, win);
		emi = lightc(id, bias) * win * on * step(4.8, v) * 1.05;
		metal = win * 0.5;
		rough = mix(0.8, 0.12, win);
	} else if (st == 1) {
		// Art-deco stone: tall piers with narrow windows and cornice bands.
		vec2 cell = vec2(u / 4.6, v / 4.2);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float win = step(0.3, f.x) * step(f.x, 0.7) * step(0.18, f.y) * step(f.y, 0.82) * step(4.8, v);
		winm = win; wf = f; wb = vec4(0.3, 0.7, 0.18, 0.82) * step(4.8, v);
		float on = step(0.68, hash(id + seed * 113.0));
		float band = step(fract(v / 21.0), 0.035);
		vec3 stone = wall * (1.0 - 0.18 * band - 0.1 * step(f.x, 0.08));
		alb = mix(stone, vec3(0.05, 0.06, 0.09), win);
		emi = lightc(id, bias) * win * on * 1.2;
		rough = mix(0.85, 0.2, win);
	} else if (st == 2) {
		// Brick: courses of bricks, punched windows with sills.
		float row = floor(v / 0.26);
		float brick = step(fract(v / 0.26), 0.12) + step(fract((u + mod(row, 2.0) * 0.28) / 0.56), 0.06);
		vec2 cell = vec2(u / 3.4, v / 3.1);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float win = step(0.28, f.x) * step(f.x, 0.72) * step(0.22, f.y) * step(f.y, 0.78) * step(3.2, v);
		winm = win; wf = f; wb = vec4(0.28, 0.72, 0.22, 0.78) * step(3.2, v);
		float sill = step(0.18, f.y) * step(f.y, 0.22) * step(0.26, f.x) * step(f.x, 0.74) * step(3.2, v);
		float on = step(0.65, hash(id + seed * 113.0));
		vec3 b = wall * (1.0 - 0.28 * min(brick, 1.0)) * (0.9 + 0.2 * hash(vec2(row, floor(u / 0.56))));
		alb = mix(b, vec3(0.05, 0.06, 0.09), win);
		alb = mix(alb, vec3(0.7, 0.66, 0.6), sill);
		emi = lightc(id, bias) * win * on * 1.15;
	} else if (st == 3) {
		// Concrete slab: long ribbon windows.
		vec2 cell = vec2(u / 4.0, v / 3.6);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float win = step(0.3, f.y) * step(f.y, 0.72) * step(0.04, f.x) * step(4.0, v);
		winm = win; wf = f; wb = vec4(0.04, 1.0, 0.3, 0.72) * step(4.0, v);
		float on = step(0.68, hash(id + seed * 113.0));
		alb = mix(wall * (0.92 + 0.12 * hash(floor(vec2(u, v) / 3.0))), vec3(0.05, 0.07, 0.1), win);
		emi = lightc(id, bias) * win * on * 1.1;
	} else if (st == 4) {
		// Industrial: corrugated cladding, high strip windows, grime near the ground.
		float rib = 0.86 + 0.14 * sin(u * 9.0);
		float strip = step(part_h - 6.5, v) * step(v, part_h - 3.0);
		float grime = 1.0 - 0.35 * (1.0 - smoothstep(0.0, 7.0, v));
		alb = mix(wall * rib * grime, vec3(0.08, 0.1, 0.12), strip * step(0.15, fract(u / 6.0)));
		emi = warm * strip * step(0.15, fract(u / 6.0)) * step(0.7, hash(vec2(floor(u / 6.0), seed * 40.0))) * 1.2;
		rough = 0.7;
		metal = 0.2;
	} else if (st == 5) {
		// House: pastel walls, small shuttered windows.
		vec2 cell = vec2(u / 4.2, v / 3.3);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float win = step(0.3, f.x) * step(f.x, 0.7) * step(0.3, f.y) * step(f.y, 0.72) * step(0.5, hash(id + seed * 31.0));
		winm = win; wf = f; wb = vec4(0.3, 0.7, 0.3, 0.72);
		float shutter = step(0.16, f.x) * step(f.x, 0.84) * step(0.28, f.y) * step(f.y, 0.74) * (1.0 - win);
		alb = mix(wall, vec3(0.06, 0.07, 0.1), win);
		alb = mix(alb, wall * 0.55, shutter * step(0.5, abs(f.x - 0.5) * 2.0 + 0.3));
		emi = lightc(id, bias) * win * step(0.55, hash(id + seed * 113.0)) * 1.4;
	} else if (st == 9) {
		// Civic limestone: tall window slots and heavy cornices.
		vec2 cell = vec2(u / 5.4, v / 5.2);
		vec2 id = floor(cell);
		vec2 f = fract(cell);
		float win = step(0.34, f.x) * step(f.x, 0.66) * step(0.12, f.y) * step(f.y, 0.82) * step(5.0, v);
		winm = win; wf = f; wb = vec4(0.34, 0.66, 0.12, 0.82) * step(5.0, v);
		float cornice = step(fract(v / 20.8), 0.05);
		vec3 stone = wall * (1.0 - 0.2 * cornice) * (0.94 + 0.12 * hash(floor(vec2(u, v) / 2.5)));
		alb = mix(stone, vec3(0.06, 0.07, 0.1), win);
		emi = lightc(id, bias) * win * step(0.4, hash(id + seed * 113.0)) * 1.8;
		rough = mix(0.9, 0.2, win);
	} else if (st == 10) {
		// Painted metal: cranes, tanks, chimneys.
		alb = wall * (0.82 + 0.18 * hash(vec2(floor(u * 1.5), floor(v * 0.4))));
		metal = 0.35;
		rough = 0.55;
	} else if (st == 11) {
		// Shipping container: ribbed sides, dark corner posts.
		float ribs = 0.8 + 0.2 * sin(u * 15.0);
		float post = step(fract(u / 12.2), 0.02) + step(0.98, fract(u / 12.2));
		alb = wall * ribs * (1.0 - 0.5 * min(post, 1.0));
		metal = 0.2;
		rough = 0.6;
	}

	if (!top_face && !round_s && wb.y > 0.0 && st != 0 && st != 2) {
		// Stone sills under the windows.
		float sill = step(wb.z - 0.07, wf.y) * step(wf.y, wb.z) * step(wb.x - 0.04, wf.x) * step(wf.x, wb.y + 0.04) * (1.0 - winm);
		alb = mix(alb, wall * 1.3 + 0.05, sill);
	}
	if (!top_face && winm > 0.5 && st != 0) {
		// Recessed windows: a frame, a shadow under the lintel and down one jamb.
		vec2 wn = vec2((wf.x - wb.x) / max(wb.y - wb.x, 0.01), (wf.y - wb.z) / max(wb.w - wb.z, 0.01));
		float frame = 1.0 - step(0.07, wn.x) * step(wn.x, 0.93) * step(0.06, wn.y) * step(wn.y, 0.94);
		float lint = smoothstep(0.7, 1.0, wn.y);
		float shade = 1.0 - 0.55 * lint - 0.25 * smoothstep(0.85, 1.0, wn.x);
		alb *= shade;
		emi *= 1.0 - 0.5 * lint;
		alb = mix(alb, st == 2 ? wall * 0.5 : vec3(0.72, 0.69, 0.63), frame * 0.75);
		emi *= 1.0 - frame;
	}
	if (!top_face && !round_s && abs(ln.y) < 0.05 && min(abs(ln.x), abs(ln.z)) < 0.05) {
		// Corners: alternating long and short quoin stones, or a dark steel fin on glass towers.
		float ed = abs(ln.x) > abs(ln.z) ? half_ext.z - abs(lp.z) : half_ext.x - abs(lp.x);
		if (st == 0) {
			float fin = step(ed, 0.8);
			alb = mix(alb, wall * 0.28, fin);
			emi *= 1.0 - fin;
			metal = max(metal, fin * 0.6);
		} else if (st == 1 || st == 2 || st == 3 || st == 9) {
			float row = floor(v / 1.5);
			float q = step(ed, mod(row, 2.0) < 0.5 ? 1.7 : 0.9) * step(2.5, v);
			alb = mix(alb, wall * 1.22 + 0.04, q);
			alb *= 1.0 - 0.18 * q * step(fract(v / 1.5), 0.07);
			emi *= 1.0 - q;
		}
	}
	if (!top_face && (st == 0 || st == 1 || st == 2 || st == 3 || st == 9)) {
		// Weathering: grime near the street, rain streaks, a lighter parapet under the roof edge.
		float streak = hash(vec2(floor(u * 1.7), seed * 31.0));
		float dirt = mix(0.6, 1.0, smoothstep(0.0, 16.0, gy));
		float rain = 1.0 - 0.18 * step(0.55, streak) * (1.0 - clamp(v / max(part_h, 1.0), 0.0, 1.0));
		alb *= dirt * rain;
		alb = mix(alb, wall * 1.2, 0.55 * step(part_h - 1.4, v));
		if (st != 0) {
			alb *= 1.0 - 0.3 * step(part_h - 3.4, v) * step(v, part_h - 1.4); // shadow under the parapet
		}
		// Ground-floor shops: lit glass, a coloured striped awning above.
		if (gy < 5.4) {
			float sf = fract(u / 6.0);
			float shop = step(0.8, gy) * step(gy, 4.1) * step(0.06, sf) * step(sf, 0.94);
			float awn = step(4.1, gy) * step(gy, 5.1);
			vec3 awn_c = mix(accent, accent * 0.5, step(0.5, fract(u / 1.3)));
			alb = mix(alb, vec3(0.05, 0.06, 0.08), shop);
			emi = mix(emi, lightc(vec2(floor(u / 6.0), 5.0), bias) * 1.2, shop);
			alb = mix(alb, awn_c, awn);
			emi = mix(emi, vec3(0.0), awn);
		}
	}
	if (burnt > 1.5) {
		// The hole: charred black with glowing embers in the cracks.
		float ember = step(0.62, hash(floor(world_pos.xz * 0.9) + floor(world_pos.y * 0.9) * 7.0));
		float flicker = 0.65 + 0.35 * sin(TIME * 9.0 + hash(floor(world_pos.xy * 0.5)) * 6.28);
		alb = vec3(0.02);
		emi = vec3(1.0, 0.38, 0.08) * ember * flicker * 2.2;
		rough = 1.0;
		metal = 0.0;
	} else if (burnt > 0.5) {
		// Scorched: soot-black walls, blown-out windows, a few still glowing.
		float flicker = 0.65 + 0.35 * sin(TIME * 9.0 + hash(floor(world_pos.xy * 0.5)) * 6.28);
		alb = mix(alb * 0.18, vec3(0.03), 0.4);
		emi = emi * step(0.75, hash(floor(vec2(u, v) / 3.0) + seed)) * vec3(1.0, 0.45, 0.12) * flicker;
		metal = 0.0;
	}
	// Far away the window grid would shimmer: fade it to its average tone (and the glints out).
	float far = smoothstep(450.0, 2000.0, length(VERTEX)) * (top_face ? 0.0 : 1.0);
	alb = mix(alb, wall * 0.66 + vec3(0.03, 0.035, 0.05), far * 0.8);
	emi *= 1.0 - far * 0.85;
	if (st == 13) {
		alb = vec3(0.05, 0.05, 0.06);
		metal = 0.3;
		rough = 0.6;
	}
	// Sun side warm, shade side cool (the sun sits low in the west).
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float facing = dot(wn, normalize(vec3(-0.837, 0.5, -0.224)));
	alb *= mix(vec3(0.8, 0.88, 1.08), vec3(1.12, 1.02, 0.88), clamp(facing * 0.6 + 0.5, 0.0, 1.0));
	ALBEDO = alb * (1.0 - dent * 0.6) * (top_face || st == 7 || st == 8 ? 1.0 : 1.18);
	EMISSION = emi * 0.5; // daylight: lit windows are a glint, not a glow
	ROUGHNESS = rough;
	METALLIC = metal;
}
