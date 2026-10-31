class_name CityTools
extends RefCounted
## Cheap ways to look at and measure the city without screenshots or many tokens:
##   --citymap=<png>   a top-down map (12.5 m per pixel): terrain, districts, every building
##                     footprint coloured by height, landmarks and supply caches
##   --citycheck       a text report: district areas against the handoff's targets, building
##                     counts, build times, street-gap statistics and flight-space connectivity
## Both run headless (no display needed). `--flytest` (in Main) then flies the real TurboKat
## controller along the street lanes to confirm the clearances in practice.

const S := 12.5 # metres per map pixel

## The handoff's area targets in km2 (water and rivers take land away from these in our 15 x 10 km).
const TARGETS := {"downtown+commercial": 45.0, "civic": 10.0, "residential+suburb": 20.0, "industrial": 15.0, "salvage": 8.0, "park": 12.0, "wild": 40.0}


static func citymap(city: City, path: String) -> void:
	var plan := city.plan
	var w := int(plan.half.x * 2.0 / S)
	var h := int(plan.half.y * 2.0 / S)
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.12, 0.2))
	var step := CityPlan.TERR_STEP
	var cell := int(ceil(step / S)) + 1
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.004
	for j in plan.tnz - 1:
		for i in plan.tnx - 1:
			var x := plan.torg.x + i * step
			var z := plan.torg.y + j * step
			var hh := plan.terr[j * plan.tnx + i]
			var col: Color
			if hh < 0.0:
				col = Color(0.05, 0.14, 0.26).lerp(Color(0.1, 0.3, 0.45), clampf(1.0 + hh / 14.0, 0.0, 1.0))
			else:
				var base := city._ground_color(x, z, hh, 1.0, noise.get_noise_2d(x, z))
				col = Color(0.18, 0.18, 0.2) if base.a > 0.5 else base
				var hl := plan.terr[j * plan.tnx + maxi(i - 1, 0)]
				var hr := plan.terr[j * plan.tnx + mini(i + 1, plan.tnx - 1)]
				col = col * clampf(0.82 + (hl - hr) * 0.004, 0.55, 1.3)
			var px := int((x + plan.half.x) / S)
			var pz := int((z + plan.half.y) / S)
			img.fill_rect(Rect2i(px, pz, cell, cell).intersection(Rect2i(0, 0, w, h)), col)
	var b := city.buildings
	for id in b.b_cx.size():
		var fixed := (b.b_flags[id] & CityBuildings.FIXED) != 0
		var top: float = b.b_h[id]
		var col := Color(0.6, 0.55, 0.48)
		if top > 150.0:
			col = Color(0.92, 0.97, 1.0)
		elif top > 60.0:
			col = Color(0.45, 0.62, 0.85)
		elif top > 20.0:
			col = Color(0.75, 0.68, 0.5)
		if fixed:
			col = Color(0.95, 0.75, 0.2)
		for i in b.b_pn[id]:
			var pi: int = b.b_p0[id] + i
			if b.p_rast[pi] != 1:
				continue
			var xf := b.p_xf[pi]
			var sc := xf.basis.get_scale()
			var yaw := b.p_yaw[pi]
			var hx := (absf(cos(yaw)) * sc.x + absf(sin(yaw)) * sc.z) * 0.5
			var hz := (absf(sin(yaw)) * sc.x + absf(cos(yaw)) * sc.z) * 0.5
			var r := Rect2i(int((xf.origin.x - hx + plan.half.x) / S), int((xf.origin.z - hz + plan.half.y) / S), maxi(int(hx * 2.0 / S), 1), maxi(int(hz * 2.0 / S), 1))
			img.fill_rect(r.intersection(Rect2i(0, 0, w, h)), col)
	# Landmarks: coloured crosses; supply caches: magenta dots.
	for m in [[city.tower_pos, Color(1, 0.2, 0.2)], [city.city_hall_pos, Color(1, 1, 0.2)], [city.enforcer_hq_pos, Color(0.3, 0.6, 1)], [city.salvage_yard_pos, Color(1, 0.55, 0.1)]]:
		_cross(img, m[0], m[1], plan)
	for sp in city.cache_spots:
		var p: Vector3 = sp.pos
		img.fill_rect(Rect2i(int((p.x + plan.half.x) / S) - 2, int((p.z + plan.half.y) / S) - 2, 5, 5).intersection(Rect2i(0, 0, w, h)), Color(1, 0.2, 0.9))
	img.save_png(path)
	print("[citymap] wrote ", path, " (", w, "x", h, ", ", S, " m/px)")


static func _cross(img: Image, p: Vector3, col: Color, plan: CityPlan) -> void:
	var cx := int((p.x + plan.half.x) / S)
	var cz := int((p.z + plan.half.y) / S)
	for d in range(-9, 10):
		for t in range(-1, 2):
			for pt in [Vector2i(cx + d, cz + t), Vector2i(cx + t, cz + d)]:
				if pt.x >= 0 and pt.y >= 0 and pt.x < img.get_width() and pt.y < img.get_height():
					img.set_pixelv(pt, col)


static func citycheck(city: City) -> void:
	var plan := city.plan
	var b := city.buildings
	print("[citycheck] ---- Megakat City report ----")
	print("[citycheck] world %.0f x %.0f km, build times (ms): %s" % [plan.half.x * 0.002, plan.half.y * 0.002, str(city.build_ms)])
	var area := {}
	for k in CityPlan.KIND_NAMES.size():
		area[CityPlan.KIND_NAMES[k]] = plan.area_km2(k)
	var land := 0.0
	for k in area:
		if k != "sea" and k != "water":
			land += area[k]
	print("[citycheck] water %.1f km2 (sea %.1f), land %.1f km2" % [area.sea + area.water, area.sea, land])
	var got := {"downtown+commercial": area.downtown + area.commercial, "civic": area.civic, "residential+suburb": area.residential + area.suburb,
		"industrial": area.industrial, "salvage": area.salvage, "park": area.park, "wild": area.wild}
	for k in TARGETS:
		print("[citycheck]   %-20s %5.1f km2   (handoff target %4.0f, scaled to our land %4.1f)" % [k, got[k], TARGETS[k], TARGETS[k] * land / 110.0])
	print("[citycheck] buildings %d, parts %d, caches %d, lanes %d; plots per district %s" % [b.b_cx.size(), b.p_kind.size(), city.cache_spots.size(), b.lanes.size(), str(b.counts)])
	var sloped := 0
	for id in b.b_cx.size():
		if b.b_flags[id] & CityBuildings.FIXED == 0 and absf(plan.terrain_h(b.b_cx[id], b.b_cz[id]) - CityPlan.LAND) > 2.0:
			sloped += 1
	print("[citycheck] buildings not on flat ground (more than 2 m off): %d of %d" % [sloped, b.b_cx.size()])
	_gap_stats(city, 60.0)
	_gap_stats(city, 150.0)
	for alt in [40.0, 100.0, 200.0]:
		_connectivity(city, alt)


## Free runs between solid cells along every row and column of the collision grid, inside the
## built-up districts, at flight level `alt`: the street widths a pilot actually sees.
static func _gap_stats(city: City, alt: float) -> void:
	var plan := city.plan
	var b := city.buildings
	var widths: Array[float] = []
	for pass_i in 2:
		var outer := b.gh if pass_i == 0 else b.gw
		var inner := b.gw if pass_i == 0 else b.gh
		for o in outer:
			var run := 0
			var started := false
			var inside := true
			for n in inner:
				var i := n if pass_i == 0 else o
				var j := o if pass_i == 0 else n
				var x := -plan.half.x + (i + 0.5) * CityBuildings.GRID
				var z := -plan.half.y + (j + 0.5) * CityBuildings.GRID
				var solid := b.hgrid[j * b.gw + i] > alt
				if solid:
					if started and inside and run > 0 and run * CityBuildings.GRID <= 400.0:
						widths.append(run * CityBuildings.GRID)
					started = true
					run = 0
					inside = true
				else:
					run += 1
					var k := plan.kind_at(x, z)
					if k < CityPlan.K.DOWNTOWN or k == CityPlan.K.PARK:
						inside = false
	widths.sort()
	if widths.is_empty():
		print("[citycheck] street gaps at %.0f m: none found" % alt)
		return
	var under_45 := 0
	var under_60 := 0
	for w in widths:
		if w < 45.0:
			under_45 += 1
		if w < 60.0:
			under_60 += 1
	print("[citycheck] street gaps at %3.0f m flight level: %d runs, 10th pct %.0f m, median %.0f m, 90th pct %.0f m; %.1f%% under 60 m, %.1f%% under 45 m (grid is 20 m, so +-20 m)" % [
		alt, widths.size(), widths[widths.size() / 10], widths[widths.size() / 2], widths[widths.size() * 9 / 10],
		100.0 * under_60 / widths.size(), 100.0 * under_45 / widths.size()])


## Flood-fills the free airspace at `alt` on a 40 m grid: is it one connected space?
static func _connectivity(city: City, alt: float) -> void:
	var plan := city.plan
	var step := 40.0
	var nx := int(plan.half.x * 2.0 / step)
	var nz := int(plan.half.y * 2.0 / step)
	var free := PackedByteArray()
	free.resize(nx * nz)
	var label := PackedInt32Array()
	label.resize(nx * nz)
	label.fill(-1)
	var n_free := 0
	for j in nz:
		for i in nx:
			var x := -plan.half.x + (i + 0.5) * step
			var z := -plan.half.y + (j + 0.5) * step
			if city.height_at(x, z) < alt:
				free[j * nx + i] = 1
				n_free += 1
	var sizes: Array[int] = []
	var queue := PackedInt32Array()
	for start in nx * nz:
		if free[start] == 0 or label[start] >= 0:
			continue
		var comp := sizes.size()
		var count := 0
		queue.clear()
		queue.append(start)
		label[start] = comp
		var head := 0
		while head < queue.size():
			var cur := queue[head]
			head += 1
			count += 1
			var ci := cur % nx
			var cj := cur / nx
			for d in [[1, 0], [-1, 0], [0, 1], [0, -1]]:
				var ni: int = ci + d[0]
				var nj: int = cj + d[1]
				if ni >= 0 and nj >= 0 and ni < nx and nj < nz:
					var nn := nj * nx + ni
					if free[nn] == 1 and label[nn] < 0:
						label[nn] = comp
						queue.append(nn)
		sizes.append(count)
	var biggest := 0
	var big_n := 0
	for c in sizes.size():
		if sizes[c] > biggest:
			biggest = sizes[c]
			big_n = c
	var enclosed := 0
	for s in sizes:
		if s < 40: # tiny pockets: courtyards and gaps a plane can't use
			enclosed += s
	# Urban airspace that is not in the main network.
	var stranded := 0
	for j in nz:
		for i in nx:
			var n := j * nx + i
			if free[n] == 1 and label[n] != big_n:
				var k := plan.kind_at(-plan.half.x + (i + 0.5) * step, -plan.half.y + (j + 0.5) * step)
				if k >= CityPlan.K.DOWNTOWN and k != CityPlan.K.PARK:
					stranded += 1
	print("[citycheck] airspace at %3.0f m: %d regions, main network %.1f%% of free space; %d urban cells (%.1f km2) cut off from it, %d cells in tiny pockets" % [
		alt, sizes.size(), 100.0 * biggest / maxf(n_free, 1), stranded, stranded * step * step / 1.0e6, enclosed])
