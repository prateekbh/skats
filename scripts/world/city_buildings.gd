class_name CityBuildings
extends RefCounted
## Every building of Megakat City, generated from the plan (CityPlan).
##
## Each district gets its own street grid: strips of building plots separated by gaps (60-100 m in
## ordinary districts, 100-160 m where skyscrapers stand, wider avenues every few streets), laid out
## with a seeded RNG. A plot becomes one of a dozen building types made of "parts" (boxes,
## cylinders, gable roofs, cones). Parts are drawn as MultiMesh instances grouped by 2.5 km tile
## (so only tiles in view are drawn) and share one facade shader.
##
## Collision is a 20 m height grid: height_at() is a lookup, there are no physics bodies. A second
## grid says which building owns each cell, so missile hits can damage it (damage_at): the roof is
## knocked down, tiers snap and lean, the building moves into a MultiMesh of subdivided boxes that
## the shader bends into a crater, and rubble piles up. reset_damage() undoes it all.

const BuildingShader := preload("res://shaders/building.gdshader")

enum M { BOX, CYL, PRISM, CONE }
enum S { GLASS, DECO, BRICK, CONCRETE, INDUSTRIAL, HOUSE, ROOF, LOT, NEON, CIVIC, METAL, CONTAINER }
const ROUND := 20 # added to a style for a round (cylindrical) part
const TILE := 2500.0
const GRID := 20.0
const G := CityPlan.LAND
const FIXED := 1 # flag: landmark / dock structure, never damaged
const DMG_BOX_MAX := 320
const DMG_CYL_MAX := 48
const RUBBLE_MAX := 400

const GLASS_COLS := [Color(0.18, 0.34, 0.55), Color(0.12, 0.4, 0.5), Color(0.2, 0.25, 0.45), Color(0.3, 0.42, 0.52), Color(0.15, 0.2, 0.3), Color(0.25, 0.5, 0.55)]
const STONE_COLS := [Color(0.66, 0.58, 0.45), Color(0.58, 0.52, 0.42), Color(0.7, 0.64, 0.52), Color(0.5, 0.46, 0.4), Color(0.62, 0.5, 0.4)]
const BRICK_COLS := [Color(0.55, 0.27, 0.2), Color(0.5, 0.32, 0.24), Color(0.42, 0.24, 0.2), Color(0.6, 0.4, 0.3)]
const PASTEL := [Color(0.9, 0.82, 0.65), Color(0.85, 0.62, 0.55), Color(0.62, 0.78, 0.85), Color(0.7, 0.82, 0.65), Color(0.9, 0.75, 0.8), Color(0.88, 0.88, 0.8)]
const ROOF_COLS := [Color(0.6, 0.28, 0.2), Color(0.32, 0.34, 0.4), Color(0.45, 0.3, 0.25), Color(0.25, 0.3, 0.28)]
const INDUSTRIAL_COLS := [Color(0.55, 0.3, 0.2), Color(0.38, 0.42, 0.5), Color(0.3, 0.45, 0.4), Color(0.5, 0.48, 0.42)]
const CONTAINER_COLS := [Color(0.8, 0.2, 0.15), Color(0.15, 0.4, 0.7), Color(0.9, 0.7, 0.15), Color(0.2, 0.55, 0.3), Color(0.85, 0.85, 0.8), Color(0.5, 0.25, 0.15)]
const NEON_COLS := [Color(1.0, 0.2, 0.5), Color(0.2, 0.9, 1.0), Color(1.0, 0.85, 0.2), Color(1.0, 0.3, 0.2), Color(0.5, 1.0, 0.4)]

var plan: CityPlan
var root: Node3D
var rng := RandomNumberGenerator.new()

# collision grid
var gw := 0
var gh := 0
var hgrid := PackedFloat32Array()
var bid := PackedInt32Array()

# buildings
var b_cx := PackedFloat32Array()
var b_cz := PackedFloat32Array()
var b_h := PackedFloat32Array() # current roof height above ground
var b_kind := PackedInt32Array()
var b_p0 := PackedInt32Array()
var b_pn := PackedInt32Array()
var b_flags := PackedInt32Array()
var b_tier := PackedInt32Array() # part index of a narrower top section that can snap and lean, or -1

# parts
var p_kind := PackedInt32Array()
var p_xf: Array[Transform3D] = []
var p_col := PackedColorArray()
var p_cus := PackedColorArray()
var p_own := PackedInt32Array()
var p_tile := PackedInt32Array()
var p_inst := PackedInt32Array()
var p_rast := PackedByteArray()
var p_yaw := PackedFloat32Array()

## Overhead solids a pilot can fly under (bridge decks): {c: Vector2, half: Vector2, yaw, y0, y1}.
var slabs: Array[Dictionary] = []
var cache_spots: Array[Dictionary] = []
var counts := {}
## Every street lane of every district: {a, b, width, avenue, kind}. Tools fly and measure these.
var lanes: Array[Dictionary] = []

var _tile_mm := {}
var _mat: ShaderMaterial
var _dbox: MultiMesh
var _dcyl: MultiMesh
var _dbox_n := 0
var _dcyl_n := 0
var _p_slot := {} # part -> damaged-MultiMesh slot (box: slot, cylinder: 1000 + slot)
var _promoted := {}
var _saved := {} # part -> [Transform3D, Color, Color] before its first change
var _saved_h := {} # building -> height before damage
var _leaned := {}
var _rubble: MultiMesh
var _rubble_n := 0
var _tree_pts: Array[Vector4] = [] # x, y, z, scale
var _lamp_n := 0
var _cur := {} # the district being generated
var _gaps := PackedFloat32Array() # (centre, width, avenue) of each gap the last _strips() made


func _init(p: CityPlan) -> void:
	plan = p
	gw = int(ceil(plan.half.x * 2.0 / GRID))
	gh = int(ceil(plan.half.y * 2.0 / GRID))
	hgrid.resize(gw * gh)
	hgrid.fill(0.0)
	bid.resize(gw * gh)
	bid.fill(-1)


# --- generation ----------------------------------------------------------------------

func generate() -> void:
	var kinds: Dictionary = plan.data.get("kinds", {})
	for kname: String in kinds:
		var kid := CityPlan.KIND_NAMES.find(kname)
		if kid < 0 or plan.bbox[kid].size.x <= 0.0:
			continue
		counts[kname] = 0
		_district(kname, kid, kinds[kname])


func _strips(lo: float, hi: float, strip: Array, gap: Array, every: int, avenue: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	_gaps = PackedFloat32Array()
	var cur := lo + rng.randf_range(0.0, float(gap[1]))
	var n := 0
	while true:
		n += 1
		var is_avenue := n % every == 0
		var g := rng.randf_range(float(avenue[0]), float(avenue[1])) if is_avenue else rng.randf_range(float(gap[0]), float(gap[1]))
		var a := cur + g
		var b := a + rng.randf_range(float(strip[0]), float(strip[1]))
		if a > hi:
			break
		_gaps.append((cur + a) * 0.5)
		_gaps.append(g)
		_gaps.append(1.0 if is_avenue else 0.0)
		out.append(a)
		out.append(b)
		cur = b
	return out


## Records the stretches of a street lane (a -> b) that lie inside the district as test lanes.
func _add_lanes(a: Vector2, b: Vector2, kid: int, width: float, avenue: bool, kname: String) -> void:
	var length := a.distance_to(b)
	var steps := int(length / 40.0)
	var run_start := -1
	for i in range(steps + 2):
		var p := a.lerp(b, minf(float(i) / maxf(steps, 1), 1.0))
		var inside := i <= steps and plan.kind_at(p.x, p.y) == kid
		if inside and run_start < 0:
			run_start = i
		if (not inside or i == steps) and run_start >= 0:
			var end_i := i if inside else i - 1
			if (end_i - run_start) * 40.0 >= 400.0:
				lanes.append({"a": a.lerp(b, float(run_start) / maxf(steps, 1)), "b": a.lerp(b, float(end_i) / maxf(steps, 1)), "width": width, "avenue": avenue, "kind": kname})
			run_start = -1


func _rect_ok(kid: int, cx: float, cz: float, hw: float, hd: float, margin: float) -> bool:
	for x in [cx - hw - margin, cx, cx + hw + margin]:
		for z in [cz - hd - margin, cz, cz + hd + margin]:
			if plan.kind_at(x, z) != kid:
				return false
	return true


func _pick(mix: Dictionary) -> String:
	var total := 0.0
	for k in mix:
		total += float(mix[k])
	var r := rng.randf() * total
	for k in mix:
		r -= float(mix[k])
		if r <= 0.0:
			return str(k)
	return str(mix.keys()[0])


func _lot_color(kname: String) -> Color:
	match kname:
		"residential", "suburb":
			return Color(0.28, 0.46, 0.2).lerp(Color(0.34, 0.5, 0.24), rng.randf())
		"industrial":
			return Color(0.3, 0.3, 0.29)
		"salvage":
			return Color(0.3, 0.24, 0.17)
		"civic":
			return Color(0.5, 0.48, 0.43)
	return Color(0.52, 0.52, 0.55)


func _district(kname: String, kid: int, p: Dictionary) -> void:
	rng.seed = int(plan.data.get("seed", 1993)) * 31 + kid
	_cur = p
	var bb := plan.bbox[kid]
	var strip: Array = p.strip
	var gap: Array = p.gap
	var xs := _strips(bb.position.x, bb.end.x, strip, gap, int(p.avenue_every), p.avenue)
	var xg := _gaps.duplicate()
	# Blocks can be longer one way than the other, like Manhattan's: strip_z is the depth.
	var zs := _strips(bb.position.y, bb.end.y, p.get("strip_z", strip), gap, int(p.avenue_every), p.avenue)
	var zg := _gaps.duplicate()
	for i in xg.size() / 3:
		_add_lanes(Vector2(xg[i * 3], bb.position.y), Vector2(xg[i * 3], bb.end.y), kid, xg[i * 3 + 1], xg[i * 3 + 2] > 0.5, kname)
	for i in zg.size() / 3:
		_add_lanes(Vector2(bb.position.x, zg[i * 3]), Vector2(bb.end.x, zg[i * 3]), kid, zg[i * 3 + 1], zg[i * 3 + 2] > 0.5, kname)
	var margin := float(gap[0]) * 0.5
	var hr: Array = p.h
	var centers: Array[Vector2] = []
	for n in int(p.get("clusters", 1)):
		for tries in 30:
			var c := Vector2(rng.randf_range(bb.position.x, bb.end.x), rng.randf_range(bb.position.y, bb.end.y))
			if plan.kind_at(c.x, c.y) == kid:
				centers.append(c)
				break
	var cr := float(p.get("cluster_r", 700.0))
	var mix: Dictionary = p.mix
	var tower := CityPlan.pt(plan.data.landmarks.tower)
	var skip := {}
	var nx := xs.size() / 2
	var nz := zs.size() / 2
	for ix in nx:
		for iz in nz:
			if skip.has(ix * 4096 + iz):
				continue
			var cx := (xs[ix * 2] + xs[ix * 2 + 1]) * 0.5
			var cz := (zs[iz * 2] + zs[iz * 2 + 1]) * 0.5
			var hw := (xs[ix * 2 + 1] - xs[ix * 2]) * 0.5
			var hd := (zs[iz * 2 + 1] - zs[iz * 2]) * 0.5
			if not _rect_ok(kid, cx, cz, hw, hd, margin):
				continue
			if rng.randf() < float(p.get("big_plaza", 0.0)):
				# A 2x2 block left open: a plaza 300-400 m across for combat and chases.
				for d in [[1, 0], [0, 1], [1, 1]]:
					skip[(ix + d[0]) * 4096 + iz + d[1]] = true
					if ix + d[0] < nx and iz + d[1] < nz:
						var ncx := (xs[(ix + d[0]) * 2] + xs[(ix + d[0]) * 2 + 1]) * 0.5
						var ncz := (zs[(iz + d[1]) * 2] + zs[(iz + d[1]) * 2 + 1]) * 0.5
						if _rect_ok(kid, ncx, ncz, (xs[(ix + d[0]) * 2 + 1] - xs[(ix + d[0]) * 2]) * 0.5, (zs[(iz + d[1]) * 2 + 1] - zs[(iz + d[1]) * 2]) * 0.5, margin):
							_pad(ncx, ncz, (xs[(ix + d[0]) * 2 + 1] - xs[(ix + d[0]) * 2]) * 0.5, (zs[(iz + d[1]) * 2 + 1] - zs[(iz + d[1]) * 2]) * 0.5, Color(0.58, 0.54, 0.46))
				_pad(cx, cz, hw, hd, Color(0.58, 0.54, 0.46))
				_cache_spot(kname, Vector3(cx, G, cz))
				continue
			if rng.randf() < float(p.get("plaza", 0.0)):
				_pad(cx, cz, hw, hd, Color(0.58, 0.54, 0.46) if kname != "salvage" else Color(0.3, 0.24, 0.17))
				_cache_spot(kname, Vector3(cx, G, cz))
				continue
			var infl := 0.0
			for c in centers:
				infl = maxf(infl, exp(-pow(Vector2(cx, cz).distance_to(c) / cr, 2.0)))
			var h := maxf(lerpf(float(hr[0]), float(hr[1]), pow(infl, 1.3)) * rng.randf_range(0.55, 1.0), float(hr[0]))
			if (kname == "downtown" or kname == "commercial") and Vector2(cx, cz).distance_to(tower) < 450.0:
				h = minf(h, float(hr[1]) * 0.4) # keep the MegaKat Tower's silhouette dominant
			_pad(cx, cz, hw, hd, _lot_color(kname))
			_lamp(cx - hw, cz + hd)
			var arch := _pick(mix)
			var slack_x := rng.randf_range(10.0, 26.0)
			var slack_z := rng.randf_range(10.0, 26.0)
			var bw := maxf(hw * 2.0 - slack_x, 24.0)
			var bd := maxf(hd * 2.0 - slack_z, 24.0)
			var bx := cx + rng.randf_range(-1.0, 1.0) * slack_x * 0.3
			var bz := cz + rng.randf_range(-1.0, 1.0) * slack_z * 0.3
			_cell_building(arch, kname, kid, bx, bz, bw, bd, h)
			counts[kname] = int(counts[kname]) + 1


func _cell_building(arch: String, kname: String, kid: int, cx: float, cz: float, w: float, d: float, h: float) -> void:
	match arch:
		"glass": _glass(cx, cz, w, d, h, kid)
		"deco": _deco(cx, cz, w, d, h, kid)
		"podium": _podium(cx, cz, w, d, h, kid)
		"twin": _twin(cx, cz, w, d, h, kid)
		"round": _round(cx, cz, w, d, h, kid)
		"slab": _slab(cx, cz, w, d, minf(h, 70.0), kid)
		"civic": _civic(cx, cz, w, d, h, kid)
		"tenement": _tenement(cx, cz, w, d, h, kid)
		"warehouse": _warehouse(cx, cz, w, d, kid)
		"factory": _factory(cx, cz, w, d, h, kid)
		"containers": _containers(cx, cz, w, d, kid)
		"houses": _houses(cx, cz, w, d, kid)
		_: _slab(cx, cz, w, d, minf(h, 40.0), kid)


# --- parts ---------------------------------------------------------------------------

func begin(cx: float, cz: float, kid: int, flags := 0) -> int:
	var id := b_cx.size()
	b_cx.append(cx)
	b_cz.append(cz)
	b_h.append(0.0)
	b_kind.append(kid)
	b_p0.append(p_kind.size())
	b_pn.append(0)
	b_flags.append(flags)
	b_tier.append(-1)
	return id


func end(id: int) -> void:
	b_pn[id] = p_kind.size() - b_p0[id]
	var top := 0.0
	for i in b_pn[id]:
		var pi := b_p0[id] + i
		if p_rast[pi] == 1:
			_raster_part(pi, id)
			top = maxf(top, p_xf[pi].origin.y + p_xf[pi].basis.get_scale().y * 0.5)
	b_h[id] = top - G


## One part. y0 is its base; `rast` false for thin props that don't collide.
func part(id: int, mk: int, cx: float, y0: float, cz: float, w: float, h: float, d: float, style: int, color: Color, is_round := false, yaw := 0.0, rast := true) -> int:
	var xf := Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(w, h, d)), Vector3(cx, y0 + h * 0.5, cz))
	var pi := p_kind.size()
	p_kind.append(mk)
	p_xf.append(xf)
	p_col.append(color)
	p_cus.append(Color(float(style + (ROUND if is_round else 0)) + rng.randf() * 0.98, 0.0, 0.0, 0.0))
	p_own.append(id)
	var tx := clampi(int(floor((cx + plan.half.x) / TILE)), 0, int(ceil(plan.half.x * 2.0 / TILE)) - 1)
	var tz := clampi(int(floor((cz + plan.half.y) / TILE)), 0, int(ceil(plan.half.y * 2.0 / TILE)) - 1)
	p_tile.append(tz * 16 + tx)
	p_inst.append(-1)
	p_rast.append(1 if (rast and mk != M.CONE) else 0)
	p_yaw.append(yaw)
	return pi


func _pad(cx: float, cz: float, hw: float, hd: float, color: Color) -> void:
	part(-1, M.BOX, cx, G - 0.2, cz, hw * 2.0, 0.55, hd * 2.0, S.LOT, color, false, 0.0, false)


func _lamp(x: float, z: float) -> void:
	part(-1, M.BOX, x, G + 7.0, z, 1.6, 1.0, 1.6, S.NEON, Color(1.0, 0.72, 0.35), false, 0.0, false)
	_lamp_n += 1


func _raster_part(pi: int, own: int) -> void:
	var xf := p_xf[pi]
	var sc := xf.basis.get_scale()
	var top := xf.origin.y + sc.y * 0.5
	raster_box(xf.origin.x, xf.origin.z, sc.x, sc.z, top, p_yaw[pi], own, p_kind[pi] == M.CYL)


## Writes a footprint (oriented rectangle or circle) into the collision grid.
func raster_box(cx: float, cz: float, sx: float, sz: float, top: float, yaw: float, own: int, circle := false) -> void:
	var cy := cos(yaw)
	var sy := sin(yaw)
	var hx := (absf(cy) * sx + absf(sy) * sz) * 0.5 + 6.0
	var hz := (absf(sy) * sx + absf(cy) * sz) * 0.5 + 6.0
	var i0 := clampi(int(floor((cx - hx + plan.half.x) / GRID)), 0, gw - 1)
	var i1 := clampi(int(floor((cx + hx + plan.half.x) / GRID)), 0, gw - 1)
	var j0 := clampi(int(floor((cz - hz + plan.half.y) / GRID)), 0, gh - 1)
	var j1 := clampi(int(floor((cz + hz + plan.half.y) / GRID)), 0, gh - 1)
	var r := sx * 0.5 + 4.0
	for j in range(j0, j1 + 1):
		var wz := -plan.half.y + (j + 0.5) * GRID
		for i in range(i0, i1 + 1):
			var wx := -plan.half.x + (i + 0.5) * GRID
			var dx := wx - cx
			var dz := wz - cz
			var inside := false
			if circle:
				inside = dx * dx + dz * dz <= r * r
			else:
				inside = absf(cy * dx - sy * dz) <= sx * 0.5 + 4.0 and absf(sy * dx + cy * dz) <= sz * 0.5 + 4.0
			if inside:
				var n := j * gw + i
				if top > hgrid[n]:
					hgrid[n] = top
				if own >= 0:
					bid[n] = own


## A landmark footprint with no parts of its own (the landmark builds its own meshes).
func add_fixed(cx: float, cz: float, sx: float, sz: float, top: float, yaw := 0.0, circle := false) -> int:
	var id := begin(cx, cz, CityPlan.K.CLEAR, FIXED)
	b_h[id] = top - G
	raster_box(cx, cz, sx, sz, top, yaw, id, circle)
	return id


func _cache_spot(kname: String, pos: Vector3) -> void:
	cache_spots.append({"pos": pos, "kind": kname})


func _tree(pos: Vector3, s: float) -> void:
	_tree_pts.append(Vector4(pos.x, pos.y, pos.z, s))


func add_tree(pos: Vector3, s: float) -> void:
	_tree(pos, s)


# --- building types -------------------------------------------------------------------

func _roof_extras(id: int, cx: float, cz: float, w: float, d: float, topy: float, h: float, kid: int) -> void:
	if rng.randf() < 0.4:
		var ah := clampf(h * 0.18, 12.0, 70.0)
		part(id, M.BOX, cx + rng.randf_range(-0.2, 0.2) * w, topy, cz + rng.randf_range(-0.2, 0.2) * d, 1.8, ah, 1.8, S.METAL, Color(0.6, 0.6, 0.65), false, 0.0, false)
		if h > 150.0:
			part(id, M.BOX, cx, topy + ah, cz, 2.6, 2.6, 2.6, S.NEON, Color(1.0, 0.15, 0.1), false, 0.0, false)
	for n in rng.randi_range(1, 3):
		part(id, M.BOX, cx + rng.randf_range(-0.3, 0.3) * w, topy, cz + rng.randf_range(-0.3, 0.3) * d, rng.randf_range(5, 10), rng.randf_range(2, 5), rng.randf_range(5, 10), S.METAL, Color(0.55, 0.56, 0.58), false, 0.0, false)
	if (kid == CityPlan.K.DOWNTOWN or kid == CityPlan.K.COMMERCIAL) and rng.randf() < 0.22:
		var nc: Color = NEON_COLS[rng.randi() % NEON_COLS.size()]
		if rng.randf() < 0.5:
			part(id, M.BOX, cx, topy + 2.0, cz + d * 0.3, minf(w * 0.55, 40.0), 7.0, 1.2, S.NEON, nc, false, 0.0, false)
		else:
			part(id, M.BOX, cx + w * 0.5 + 0.6, G + minf(h * 0.6, 60.0), cz, 1.2, minf(h * 0.3, 30.0), 5.0, S.NEON, nc, false, 0.0, false)


func _glass(cx: float, cz: float, w: float, d: float, h: float, kid: int) -> void:
	var id := begin(cx, cz, kid)
	var col: Color = GLASS_COLS[rng.randi() % GLASS_COLS.size()]
	part(id, M.BOX, cx, G, cz, w, h, d, S.GLASS, col)
	var topy := G + h
	if h > 110.0:
		part(id, M.BOX, cx, topy, cz, w * 0.6, h * 0.06, d * 0.6, S.GLASS, col.darkened(0.25))
		topy += h * 0.06
	_roof_extras(id, cx, cz, w, d, topy, h, kid)
	end(id)


func _deco(cx: float, cz: float, w: float, d: float, h: float, kid: int) -> void:
	var id := begin(cx, cz, kid)
	var col: Color = STONE_COLS[rng.randi() % STONE_COLS.size()]
	part(id, M.BOX, cx, G, cz, w, h * 0.5, d, S.DECO, col)
	part(id, M.BOX, cx, G + h * 0.5, cz, w * 0.78, h * 0.3, d * 0.78, S.DECO, col)
	var tier := part(id, M.BOX, cx, G + h * 0.8, cz, w * 0.52, h * 0.2, d * 0.52, S.DECO, col.lightened(0.05))
	part(id, M.CONE, cx, G + h, cz, w * 0.14, h * 0.14, d * 0.14, S.METAL, Color(0.85, 0.65, 0.25), false, 0.0, false)
	_roof_extras(id, cx, cz, w * 0.5, d * 0.5, G + h, h, kid)
	end(id)
	b_tier[id] = tier


func _podium(cx: float, cz: float, w: float, d: float, h: float, kid: int) -> void:
	var id := begin(cx, cz, kid)
	var hp := rng.randf_range(22.0, 44.0)
	var stone: Color = STONE_COLS[rng.randi() % STONE_COLS.size()]
	part(id, M.BOX, cx, G, cz, w, hp, d, S.CONCRETE if rng.randf() < 0.5 else S.DECO, stone)
	var tw := w * rng.randf_range(0.5, 0.62)
	var td := d * rng.randf_range(0.5, 0.62)
	var tx := cx + rng.randf_range(-0.15, 0.15) * w
	var tz := cz + rng.randf_range(-0.15, 0.15) * d
	var col: Color = GLASS_COLS[rng.randi() % GLASS_COLS.size()]
	var tier := part(id, M.BOX, tx, G + hp, tz, tw, maxf(h - hp, 30.0), td, S.GLASS, col)
	_roof_extras(id, tx, tz, tw, td, G + maxf(h, hp + 30.0), h, kid)
	end(id)
	b_tier[id] = tier


func _twin(cx: float, cz: float, w: float, d: float, h: float, kid: int) -> void:
	var id := begin(cx, cz, kid)
	var col: Color = GLASS_COLS[rng.randi() % GLASS_COLS.size()]
	var tw := w * 0.36
	part(id, M.BOX, cx - w * 0.3, G, cz, tw, h, d * 0.7, S.GLASS, col)
	part(id, M.BOX, cx + w * 0.3, G, cz, tw, h * 0.9, d * 0.7, S.GLASS, col.lightened(0.05))
	part(id, M.BOX, cx, G + h * 0.62, cz, w * 0.3, 7.0, d * 0.35, S.GLASS, col.darkened(0.2))
	_roof_extras(id, cx - w * 0.3, cz, tw, d * 0.7, G + h, h, kid)
	end(id)


func _round(cx: float, cz: float, w: float, d: float, h: float, kid: int) -> void:
	var id := begin(cx, cz, kid)
	var r := minf(w, d) * 0.42
	var col: Color = GLASS_COLS[rng.randi() % GLASS_COLS.size()]
	part(id, M.CYL, cx, G, cz, r * 2.0, h, r * 2.0, S.GLASS, col, true)
	part(id, M.CYL, cx, G + h, cz, r * 1.7, 6.0, r * 1.7, S.METAL, col.lightened(0.15), false)
	_roof_extras(id, cx, cz, r, r, G + h + 6.0, h, kid)
	end(id)


func _slab(cx: float, cz: float, w: float, d: float, h: float, kid: int) -> void:
	var id := begin(cx, cz, kid)
	var greys := [Color(0.62, 0.62, 0.64), Color(0.7, 0.68, 0.64), Color(0.55, 0.58, 0.62)]
	part(id, M.BOX, cx, G, cz, w, h, d, S.CONCRETE, greys[rng.randi() % greys.size()])
	_roof_extras(id, cx, cz, w, d, G + h, h, kid)
	end(id)


func _civic(cx: float, cz: float, w: float, d: float, h: float, kid: int) -> void:
	var id := begin(cx, cz, kid)
	var col: Color = STONE_COLS[rng.randi() % STONE_COLS.size()].lightened(0.1)
	part(id, M.BOX, cx, G, cz, w, h * 0.65, d, S.CIVIC, col)
	var tier := part(id, M.BOX, cx, G + h * 0.65, cz, w * 0.7, h * 0.35, d * 0.7, S.CIVIC, col)
	part(id, M.CONE, cx, G + h, cz, w * 0.6, h * 0.25, d * 0.6, S.ROOF, Color(0.3, 0.45, 0.4), false, 0.0, false)
	end(id)
	b_tier[id] = tier


func _tenement(cx: float, cz: float, w: float, d: float, h: float, kid: int) -> void:
	var id := begin(cx, cz, kid)
	var col: Color = BRICK_COLS[rng.randi() % BRICK_COLS.size()]
	var bw := w * rng.randf_range(0.6, 0.85)
	var bd := d * rng.randf_range(0.6, 0.85)
	part(id, M.BOX, cx, G, cz, bw, h, bd, S.BRICK, col)
	part(id, M.CYL, cx + bw * 0.2, G + h, cz, 6.0, 7.0, 6.0, S.METAL, Color(0.45, 0.32, 0.22), false, 0.0, false)
	part(id, M.BOX, cx - bw * 0.25, G + h, cz, 4.0, 3.0, 5.0, S.METAL, Color(0.5, 0.5, 0.52), false, 0.0, false)
	end(id)


func _gable(id: int, cx: float, cz: float, w: float, d: float, y0: float, rh: float, col: Color) -> void:
	# The prism's ridge runs along its local z; turn it to run along the longer side.
	var along := maxf(w, d)
	var across := minf(w, d)
	part(id, M.PRISM, cx, y0, cz, across * 1.04, rh, along * 1.02, S.ROOF, col, false, PI * 0.5 if w >= d else 0.0)


func _warehouse(cx: float, cz: float, w: float, d: float, kid: int) -> void:
	var id := begin(cx, cz, kid)
	var col: Color = INDUSTRIAL_COLS[rng.randi() % INDUSTRIAL_COLS.size()]
	var hh := rng.randf_range(10.0, 20.0)
	part(id, M.BOX, cx, G, cz, w, hh, d, S.INDUSTRIAL, col)
	_gable(id, cx, cz, w, d, G + hh, rng.randf_range(4.0, 7.0), col.darkened(0.25))
	end(id)


func _factory(cx: float, cz: float, w: float, d: float, h: float, kid: int) -> void:
	var id := begin(cx, cz, kid)
	var brick: Color = BRICK_COLS[rng.randi() % BRICK_COLS.size()]
	part(id, M.BOX, cx, G, cz, w * 0.7, h * 0.6, d * 0.7, S.BRICK, brick)
	part(id, M.BOX, cx + w * 0.15, G, cz - d * 0.1, w * 0.35, h, d * 0.4, S.INDUSTRIAL, Color(0.45, 0.45, 0.48))
	for n in rng.randi_range(1, 3):
		part(id, M.CYL, cx - w * 0.3 + n * 12.0, G, cz + d * 0.25, 5.0, rng.randf_range(40.0, 75.0), 5.0, S.METAL, Color(0.5, 0.26, 0.2))
	part(id, M.CYL, cx + w * 0.3, G, cz + d * 0.3, 14.0, 16.0, 14.0, S.METAL, Color(0.6, 0.62, 0.64))
	end(id)


func _containers(cx: float, cz: float, w: float, d: float, kid: int) -> void:
	var id := begin(cx, cz, kid)
	raster_box(cx, cz, w * 0.9, d * 0.9, G + 9.0, 0.0, id)
	var nx := maxi(int(w * 0.9 / 15.0), 1)
	var nz := maxi(int(d * 0.9 / 4.0), 1)
	for ix in nx:
		for iz in nz:
			if rng.randf() < 0.18:
				continue
			var stack := rng.randi_range(1, 3)
			var col: Color = CONTAINER_COLS[rng.randi() % CONTAINER_COLS.size()]
			for s in stack:
				part(id, M.BOX, cx - w * 0.45 + (ix + 0.5) * 15.0, G + s * 2.7, cz - d * 0.45 + (iz + 0.5) * 4.0, 12.2, 2.6, 2.6, S.CONTAINER, col, false, 0.0, false)
	end(id)


func _houses(cx: float, cz: float, w: float, d: float, kid: int) -> void:
	var plot: Array = _cur.get("plot", [44, 42])
	var nx := clampi(int(w / float(plot[0])), 1, 5)
	var nz := clampi(int(d / float(plot[1])), 1, 5)
	for ix in nx:
		for iz in nz:
			if rng.randf() < 0.05:
				continue
			var px := cx - w * 0.5 + (ix + 0.5) * w / nx + rng.randf_range(-3.0, 3.0)
			var pz := cz - d * 0.5 + (iz + 0.5) * d / nz + rng.randf_range(-3.0, 3.0)
			var hw := minf(w / nx - 7.0, rng.randf_range(13.0, 22.0))
			var hd := minf(d / nz - 7.0, rng.randf_range(10.0, 16.0))
			var hh := rng.randf_range(5.5, 9.0) if rng.randf() < 0.6 else rng.randf_range(9.0, 13.5) # some two-and-a-half storeys
			var id := begin(px, pz, kid)
			part(id, M.BOX, px, G, pz, hw, hh, hd, S.HOUSE, PASTEL[rng.randi() % PASTEL.size()])
			_gable(id, px, pz, hw, hd, G + hh, rng.randf_range(2.5, 4.5), ROOF_COLS[rng.randi() % ROOF_COLS.size()])
			if rng.randf() < 0.3:
				part(id, M.BOX, px + hw * 0.25, G + hh, pz, 1.6, 5.0, 1.6, S.BRICK, Color(0.5, 0.3, 0.25), false, 0.0, false)
			end(id)
			if rng.randf() < 0.55:
				_tree(Vector3(px + hw * 0.5 + 5.0, G, pz + hd * 0.5 + 4.0), rng.randf_range(0.8, 1.2))
	if rng.randf() < 0.2 and nx % 2 == 0 and nz % 2 == 0:
		_cache_spot("residential", Vector3(cx, G, cz)) # the block centre is free only between plots


# --- meshes and the multimeshes -------------------------------------------------------

func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, col: Color) -> void:
	# Godot's front faces wind clockwise: flip a triangle whose right-hand normal points outward.
	var flip := (b - a).cross(c - a).dot(n) > 0.0
	var vs := [a, c, b] if flip else [a, b, c]
	for v in vs:
		st.set_normal(n)
		st.set_color(col)
		st.add_vertex(v)


func _prism_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var w := Color.WHITE
	var nl := Vector3(-1.0, 1.0, 0.0).normalized()
	var nr := Vector3(1.0, 1.0, 0.0).normalized()
	var a0 := Vector3(-0.5, -0.5, -0.5)
	var a1 := Vector3(-0.5, -0.5, 0.5)
	var b0 := Vector3(0.5, -0.5, -0.5)
	var b1 := Vector3(0.5, -0.5, 0.5)
	var r0 := Vector3(0.0, 0.5, -0.5)
	var r1 := Vector3(0.0, 0.5, 0.5)
	_tri(st, a0, r0, r1, nl, w)
	_tri(st, a0, r1, a1, nl, w)
	_tri(st, b1, r1, r0, nr, w)
	_tri(st, b1, r0, b0, nr, w)
	_tri(st, a1, r1, b1, Vector3.BACK, w)
	_tri(st, b0, r0, a0, Vector3.FORWARD, w)
	_tri(st, a0, a1, b1, Vector3.DOWN, w)
	_tri(st, a0, b1, b0, Vector3.DOWN, w)
	return st.commit()


func _tree_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := Color(0.35, 0.24, 0.15)
	var leaf := Color(1.0, 1.0, 1.0)
	var n := 6
	# Trunk: a thin hexagonal prism.
	for k in n:
		var a0 := TAU * k / n
		var a1 := TAU * (k + 1) / n
		var p0 := Vector3(cos(a0) * 0.35, 0.0, sin(a0) * 0.35)
		var p1 := Vector3(cos(a1) * 0.35, 0.0, sin(a1) * 0.35)
		var nn := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
		_tri(st, p0, p1, p1 + Vector3(0, 2.4, 0), nn, trunk)
		_tri(st, p0, p1 + Vector3(0, 2.4, 0), p0 + Vector3(0, 2.4, 0), nn, trunk)
	# Two stacked leaf cones.
	for cone in [[1.6, 2.4, 4.6], [4.0, 1.7, 3.8]]:
		var y0: float = cone[0]
		var r: float = cone[1]
		var hgt: float = cone[2]
		for k in n:
			var a0 := TAU * k / n
			var a1 := TAU * (k + 1) / n
			var p0 := Vector3(cos(a0) * r, y0, sin(a0) * r)
			var p1 := Vector3(cos(a1) * r, y0, sin(a1) * r)
			var apex := Vector3(0, y0 + hgt, 0)
			var nn := Vector3(cos((a0 + a1) * 0.5) * hgt, r, sin((a0 + a1) * 0.5) * hgt).normalized()
			_tri(st, p0, p1, apex, nn, leaf)
	return st.commit()


func _unit_mesh(mk: int) -> Mesh:
	match mk:
		M.CYL:
			return MeshKit.cyl(0.5, 0.5, 1.0, 16)
		M.PRISM:
			return _prism_mesh()
		M.CONE:
			return MeshKit.cyl(0.0, 0.5, 1.0, 8)
	return MeshKit.box(Vector3.ONE)


func finalize(parent: Node3D) -> void:
	root = Node3D.new()
	root.name = "Buildings"
	parent.add_child(root)
	_mat = ShaderMaterial.new()
	_mat.shader = BuildingShader
	var groups := {}
	for pi in p_kind.size():
		var key := p_tile[pi] * 8 + p_kind[pi]
		if not groups.has(key):
			groups[key] = []
		groups[key].append(pi)
	var meshes := {}
	for key: int in groups:
		var mk := key % 8
		if not meshes.has(mk):
			meshes[mk] = _unit_mesh(mk)
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = meshes[mk]
		mm.instance_count = list.size()
		for k in list.size():
			var pi: int = list[k]
			mm.set_instance_transform(k, p_xf[pi])
			mm.set_instance_color(k, p_col[pi])
			mm.set_instance_custom_data(k, p_cus[pi])
			p_inst[pi] = k
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = _mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
		_tile_mm[key] = mm
	_build_damage_mms()
	_build_trees()


func _build_damage_mms() -> void:
	var dmat := _mat.duplicate() as ShaderMaterial
	dmat.set_shader_parameter("deform", true)
	var dense := BoxMesh.new()
	dense.subdivide_width = 8
	dense.subdivide_depth = 8
	dense.subdivide_height = 16
	_dbox = _damage_mm(dense, DMG_BOX_MAX, dmat)
	var dcyl := CylinderMesh.new()
	dcyl.top_radius = 0.5
	dcyl.bottom_radius = 0.5
	dcyl.height = 1.0
	dcyl.radial_segments = 20
	dcyl.rings = 14
	_dcyl = _damage_mm(dcyl, DMG_CYL_MAX, dmat)
	_rubble = MultiMesh.new()
	_rubble.transform_format = MultiMesh.TRANSFORM_3D
	_rubble.use_colors = true
	_rubble.mesh = MeshKit.box(Vector3.ONE)
	_rubble.instance_count = RUBBLE_MAX
	_rubble.visible_instance_count = 0
	var rmi := MultiMeshInstance3D.new()
	rmi.multimesh = _rubble
	var rm := MeshKit.toon(Color.WHITE, 0.0, 0.9)
	rm.vertex_color_use_as_albedo = true
	rmi.material_override = rm
	rmi.custom_aabb = AABB(Vector3(-plan.half.x, -10, -plan.half.y), Vector3(plan.half.x * 2.0, 1500, plan.half.y * 2.0))
	root.add_child(rmi)


func _damage_mm(mesh: Mesh, cap: int, mat: ShaderMaterial) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.custom_aabb = AABB(Vector3(-plan.half.x, -10, -plan.half.y), Vector3(plan.half.x * 2.0, 1500, plan.half.y * 2.0))
	root.add_child(mmi)
	return mm


func _build_trees() -> void:
	var tmesh := _tree_mesh()
	var tmat := StandardMaterial3D.new()
	tmat.vertex_color_use_as_albedo = true
	tmat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	tmat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	tmat.roughness = 1.0
	var tiles := {}
	for i in _tree_pts.size():
		var p := _tree_pts[i]
		var key := clampi(int(floor((p.z + plan.half.y) / TILE)), 0, 3) * 16 + clampi(int(floor((p.x + plan.half.x) / TILE)), 0, 5)
		if not tiles.has(key):
			tiles[key] = []
		tiles[key].append(i)
	var trng := RandomNumberGenerator.new()
	trng.seed = 77
	for key: int in tiles:
		var list: Array = tiles[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = tmesh
		mm.instance_count = list.size()
		for k in list.size():
			var p := _tree_pts[list[k]]
			var basis := Basis(Vector3.UP, trng.randf() * TAU) * Basis.from_scale(Vector3.ONE * p.w * trng.randf_range(1.0, 1.7))
			mm.set_instance_transform(k, Transform3D(basis, Vector3(p.x, p.y, p.z)))
			mm.set_instance_color(k, Color(0.2, 0.42, 0.16).lerp(Color(0.36, 0.5, 0.18), trng.randf()))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = tmat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)


# --- queries -------------------------------------------------------------------------

func height_at(x: float, z: float) -> float:
	var h := plan.terrain_h(x, z)
	if h < 0.0:
		h = 0.0
	var gx := int((x + plan.half.x) / GRID)
	var gz := int((z + plan.half.y) / GRID)
	if x >= -plan.half.x and z >= -plan.half.y and gx < gw and gz < gh:
		h = maxf(h, hgrid[gz * gw + gx])
	return h


func add_slab(cx: float, cz: float, sx: float, sz: float, yaw: float, y0: float, y1: float) -> void:
	slabs.append({"c": Vector2(cx, cz), "half": Vector2(sx, sz) * 0.5, "cos": cos(yaw), "sin": sin(yaw), "y0": y0, "y1": y1})


## True if `p` is inside a bridge deck (the height grid can't hold a solid with space beneath it).
func overhang_hit(p: Vector3) -> bool:
	for sl: Dictionary in slabs:
		if p.y < float(sl.y0) or p.y > float(sl.y1):
			continue
		var c: Vector2 = sl.c
		var hs: Vector2 = sl.half
		var dx: float = p.x - c.x
		var dz: float = p.z - c.y
		if absf(float(sl.cos) * dx - float(sl.sin) * dz) <= hs.x and absf(float(sl.sin) * dx + float(sl.cos) * dz) <= hs.y:
			return true
	return false


func building_at(x: float, z: float) -> int:
	var gx := int(floor((x + plan.half.x) / GRID))
	var gz := int(floor((z + plan.half.y) / GRID))
	for dz in [0, -1, 1]:
		for dx in [0, -1, 1]:
			var i: int = gx + dx
			var j: int = gz + dz
			if i >= 0 and j >= 0 and i < gw and j < gh and bid[j * gw + i] >= 0:
				return bid[j * gw + i]
	return -1


## The tallest damageable building within `radius` of `near` that is at least `min_h` tall.
func find_building(near: Vector3, radius: float, min_h: float) -> int:
	var best := -1
	for b in b_cx.size():
		if (b_flags[b] & FIXED) != 0 or b_h[b] < min_h:
			continue
		if Vector2(b_cx[b] - near.x, b_cz[b] - near.z).length() < radius and (best < 0 or b_h[b] > b_h[best]):
			best = b
	return best


# --- damage ---------------------------------------------------------------------------

func _tile_set(pi: int, xf: Transform3D, col: Color, cus: Color) -> void:
	var mm: MultiMesh = _tile_mm[p_tile[pi] * 8 + p_kind[pi]]
	mm.set_instance_transform(p_inst[pi], xf)
	mm.set_instance_color(p_inst[pi], col)
	mm.set_instance_custom_data(p_inst[pi], cus)


func _hide_original(pi: int) -> void:
	_save(pi)
	var mm: MultiMesh = _tile_mm[p_tile[pi] * 8 + p_kind[pi]]
	mm.set_instance_transform(p_inst[pi], Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -200, 0)))


func _save(pi: int) -> void:
	if not _saved.has(pi):
		_saved[pi] = [p_xf[pi], p_col[pi], p_cus[pi]]


## Writes a part's current transform / colours to wherever it is drawn now.
func _set_part(pi: int, xf: Transform3D, col: Color, cus: Color) -> void:
	_save(pi)
	p_xf[pi] = xf
	p_col[pi] = col
	p_cus[pi] = cus
	if _p_slot.has(pi):
		var slot: int = _p_slot[pi]
		var mm := _dcyl if slot >= 1000 else _dbox
		var s := slot - 1000 if slot >= 1000 else slot
		mm.set_instance_transform(s, xf)
		mm.set_instance_color(s, col)
		mm.set_instance_custom_data(s, cus)
	else:
		_tile_set(pi, xf, col, cus)


## Moves a building's boxes and cylinders into the bendable MultiMeshes (its roof props are
## blown away). If those are full the building is still scorched and loses its roof.
func _promote(b: int) -> void:
	if _promoted.has(b):
		return
	_promoted[b] = true
	for i in b_pn[b]:
		var pi := b_p0[b] + i
		var mk := p_kind[pi]
		if mk == M.PRISM or mk == M.CONE:
			_hide_original(pi)
		elif p_rast[pi] == 0:
			continue # props (antennas, signs, AC units) stay put unless the roof under them goes
		elif mk == M.BOX and _dbox_n < DMG_BOX_MAX:
			_save(pi)
			_p_slot[pi] = _dbox_n
			_dbox_n += 1
			_dbox.set_instance_transform(_p_slot[pi], p_xf[pi])
			_dbox.set_instance_color(_p_slot[pi], p_col[pi])
			_dbox.set_instance_custom_data(_p_slot[pi], p_cus[pi])
			_hide_original(pi)
		elif mk == M.CYL and _dcyl_n < DMG_CYL_MAX:
			_save(pi)
			_p_slot[pi] = 1000 + _dcyl_n
			_dcyl_n += 1
			_dcyl.set_instance_transform(_dcyl_n - 1, p_xf[pi])
			_dcyl.set_instance_color(_dcyl_n - 1, p_col[pi])
			_dcyl.set_instance_custom_data(_dcyl_n - 1, p_cus[pi])
			_hide_original(pi)
	_dbox.visible_instance_count = _dbox_n
	_dcyl.visible_instance_count = _dcyl_n


func _reraster(b: int) -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in b_pn[b]:
		var pi := b_p0[b] + i
		var o := p_xf[pi].origin
		var e := p_xf[pi].basis.get_scale() * 0.5
		var r := maxf(e.x, e.z) * 1.5 + 12.0
		lo = Vector2(minf(lo.x, o.x - r), minf(lo.y, o.z - r))
		hi = Vector2(maxf(hi.x, o.x + r), maxf(hi.y, o.z + r))
	var i0 := clampi(int(floor((lo.x + plan.half.x) / GRID)), 0, gw - 1)
	var i1 := clampi(int(floor((hi.x + plan.half.x) / GRID)), 0, gw - 1)
	var j0 := clampi(int(floor((lo.y + plan.half.y) / GRID)), 0, gh - 1)
	var j1 := clampi(int(floor((hi.y + plan.half.y) / GRID)), 0, gh - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			if bid[j * gw + i] == b:
				hgrid[j * gw + i] = 0.0
				bid[j * gw + i] = -1
	var top := 0.0
	for i in b_pn[b]:
		var pi := b_p0[b] + i
		if p_rast[pi] == 1:
			_raster_part(pi, b)
			top = maxf(top, p_xf[pi].origin.y + p_xf[pi].basis.get_scale().y * 0.5)
	b_h[b] = top - G


## A missile struck a building at `p`. Hits near the top knock the roof down and pile rubble on it,
## or snap a narrower top section so it leans over; hits lower down blast a burning hole in the
## wall. Returns where the smoke column should rise, or Vector3.INF if no damageable building is there.
func damage_at(p: Vector3, power := 1.0) -> Vector3:
	var b := building_at(p.x, p.z)
	if b < 0 or (b_flags[b] & FIXED) != 0:
		return Vector3.INF
	_promote(b)
	if not _saved_h.has(b):
		_saved_h[b] = b_h[b]
	var p0 := b_p0[b]
	var hit_pi := -1
	var hit_d := INF
	var top_pi := -1
	var top_y := -INF
	for i in b_pn[b]:
		var pi := p0 + i
		if p_rast[pi] != 1:
			continue
		var xf := p_xf[pi]
		var sc := xf.basis.get_scale()
		var ty := xf.origin.y + sc.y * 0.5
		if ty > top_y:
			top_y = ty
			top_pi = pi
		var rel := (p - xf.origin).abs() / (sc * 0.5)
		var d := maxf(rel.x, maxf(rel.y, rel.z))
		if d < hit_d:
			hit_d = d
			hit_pi = pi
	if hit_pi < 0:
		return Vector3.INF
	var smoke := p
	var tier := b_tier[b]
	var roof_hit := false
	if tier >= 0 and not _leaned.has(b) and p.y > p_xf[tier].origin.y - p_xf[tier].basis.get_scale().y * 0.5 - 4.0:
		# The top section snaps at its base and leans over, sagging into the roof.
		_leaned[b] = true
		var xf := p_xf[tier]
		var sc := xf.basis.get_scale()
		var axis := Vector3(rng.randf_range(-1.0, 1.0), 0.0, rng.randf_range(-1.0, 1.0)).normalized()
		var rot := Basis(axis, deg_to_rad(rng.randf_range(9.0, 16.0)))
		var base := Vector3(xf.origin.x, xf.origin.y - sc.y * 0.5 - 3.0, xf.origin.z)
		var col := p_col[tier]
		col.a = 0.0
		_set_part(tier, Transform3D(rot * xf.basis, base + rot * Vector3(0, sc.y * 0.5, 0)), col, p_cus[tier])
		smoke = Vector3(p.x, maxf(p.y, base.y), p.z)
		roof_hit = true
		_add_rubble(xf.origin.x, xf.origin.z, sc.x * 0.5, sc.z * 0.5, base.y + 2.0, 3)
	elif p.y > top_y - 22.0 * power or b_h[b] < 45.0:
		var xf := p_xf[top_pi]
		var sc := xf.basis.get_scale()
		var chunk := minf(rng.randf_range(10.0, 20.0) * power, sc.y - 12.0)
		var col := p_col[top_pi]
		col.a = 0.0 # broken roof: the shader chars the top floors and breaks the roofline
		if chunk > 2.0:
			var nxf := Transform3D(xf.basis * Basis.from_scale(Vector3(1.0, (sc.y - chunk) / sc.y, 1.0)), xf.origin - Vector3(0, chunk * 0.5, 0))
			_set_part(top_pi, nxf, col, p_cus[top_pi])
			top_y -= chunk
			# Props standing on that roof go with it.
			for i in b_pn[b]:
				var pi := p0 + i
				if p_rast[pi] == 0 and p_xf[pi].origin.y > top_y + 0.5 and p_kind[pi] != M.PRISM and p_kind[pi] != M.CONE:
					_hide_part(pi)
		else:
			_set_part(top_pi, xf, col, p_cus[top_pi])
		var e := p_xf[top_pi].basis.get_scale() * 0.5
		var o := p_xf[top_pi].origin
		smoke = Vector3(clampf(p.x, o.x - e.x, o.x + e.x), top_y, clampf(p.z, o.z - e.z, o.z + e.z))
		roof_hit = true
		_add_rubble(o.x, o.z, e.x, e.z, top_y, 5)
	# Scorch around the impact, on the part that was struck.
	var hxf := p_xf[hit_pi]
	var he := hxf.basis.get_scale() * 0.5
	var cus := p_cus[hit_pi]
	_set_part(hit_pi, hxf, p_col[hit_pi], Color(cus.r, maxf(smoke.y, 1.0), clampf((smoke.x - hxf.origin.x) / he.x, -1.2, 1.2), clampf((smoke.z - hxf.origin.z) / he.z, -1.2, 1.2)))
	_reraster(b)
	return smoke


func _hide_part(pi: int) -> void:
	_save(pi)
	_tile_set(pi, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0, -200, 0)), p_col[pi], p_cus[pi])


func _add_rubble(cx: float, cz: float, hw: float, hd: float, roof: float, count: int) -> void:
	for k in count:
		var size := Vector3(rng.randf_range(5.0, 12.0), rng.randf_range(2.5, 5.0), rng.randf_range(5.0, 11.0))
		var at := Vector3(cx + rng.randf_range(-0.8, 0.8) * hw, roof + size.y * 0.3, cz + rng.randf_range(-0.8, 0.8) * hd)
		var rot := Basis.from_euler(Vector3(rng.randf_range(-0.6, 0.6), rng.randf() * TAU, rng.randf_range(-0.6, 0.6)))
		var i := _rubble_n % RUBBLE_MAX
		_rubble.set_instance_transform(i, Transform3D(rot * Basis.from_scale(size), at))
		var g := rng.randf_range(0.3, 0.48)
		_rubble.set_instance_color(i, Color(g, g * 0.95, g * 0.9))
		_rubble_n += 1
	_rubble.visible_instance_count = mini(_rubble_n, RUBBLE_MAX)


## Undoes all missile damage (called when a stage starts).
func reset_damage() -> void:
	for pi: int in _saved:
		var s: Array = _saved[pi]
		p_xf[pi] = s[0]
		p_col[pi] = s[1]
		p_cus[pi] = s[2]
		_tile_set(pi, s[0], s[1], s[2])
	for b: int in _saved_h:
		b_h[b] = _saved_h[b]
		_reraster(b)
	_saved.clear()
	_saved_h.clear()
	_p_slot.clear()
	_promoted.clear()
	_leaned.clear()
	_dbox_n = 0
	_dcyl_n = 0
	_dbox.visible_instance_count = 0
	_dcyl.visible_instance_count = 0
	_rubble_n = 0
	_rubble.visible_instance_count = 0
