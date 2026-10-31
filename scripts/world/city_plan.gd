class_name CityPlan
extends RefCounted
## Megakat City as data: data/city_plan.json describes the world (water, districts, landmarks,
## mountain ridges, piers, supply caches) in a few dozen lines. Coordinates in the file are
## [x, z] in kilometres (x east, z south, north is -z); sizes are in metres.
##
## This class paints the plan onto a 50 m raster (which district or water is where), blurs it
## into land/urban factors, and builds the terrain height grid (sea floor, shores, hills,
## mountain ridges, wetlands). CityBuildings lays out streets and buildings on top of it, and
## `--citymap` / `--citycheck` (CityTools) draw and measure the result.

enum K { WILD, SEA, WATER, DOWNTOWN, COMMERCIAL, CIVIC, RESIDENTIAL, SUBURB, INDUSTRIAL, SALVAGE, PARK, CLEAR }
const KIND_NAMES := ["wild", "sea", "water", "downtown", "commercial", "civic", "residential", "suburb", "industrial", "salvage", "park", "clear"]

const CELL := 50.0 # plan raster resolution, metres
const TERR_STEP := 75.0 # terrain grid spacing, metres
const TERR_MARGIN := Vector2(1500.0, 1500.0) # terrain extends this far past the playable world
const SEA_FLOOR := -14.0
const LAND := 0.7 # flat land height; the water plane sits at 0

var data: Dictionary
var half := Vector2(7500.0, 5000.0)
var rw := 0
var rh := 0
var kind := PackedByteArray()
var landf := PackedFloat32Array() # 0 water .. 1 land, blurred
var urbf := PackedFloat32Array() # 0 wild .. 1 built-up / park, blurred
var bbox: Array[Rect2] = [] # per district kind, in metres (empty Rect2 if none)
var terr := PackedFloat32Array()
var tnx := 0
var tnz := 0
var torg := Vector2.ZERO

var _noise := FastNoiseLite.new()
var _pond_noise := FastNoiseLite.new()
var _ridges: Array[Dictionary] = []
var _wet: Array[Rect2] = []


static func load_data(path: String) -> Dictionary:
	var res := load(path) as JSON
	return res.data if res else {}


func build(d: Dictionary) -> void:
	data = d
	var w: Array = d.get("world", [15.0, 10.0])
	half = Vector2(float(w[0]), float(w[1])) * 500.0
	rw = int(round(half.x * 2.0 / CELL))
	rh = int(round(half.y * 2.0 / CELL))
	kind.resize(rw * rh)
	kind.fill(K.WILD)
	for dd: Dictionary in d.get("districts", []):
		_fill_poly(_poly(dd.poly), KIND_NAMES.find(str(dd.kind)))
	for c: Dictionary in d.get("clear", []):
		var cc := pt(c.c)
		var hf: Array = c.half
		_fill_poly(PackedVector2Array([cc + Vector2(-float(hf[0]), -float(hf[1])), cc + Vector2(float(hf[0]), -float(hf[1])),
			cc + Vector2(float(hf[0]), float(hf[1])), cc + Vector2(-float(hf[0]), float(hf[1]))]), K.CLEAR)
	for s in d.get("sea", []):
		_fill_poly(_poly(s), K.SEA)
	for l: Dictionary in d.get("lakes", []):
		_fill_ellipse(pt(l.c), _r(l.r), K.WATER)
	for r: Dictionary in d.get("rivers", []):
		var pts := _poly(r.pts)
		for i in pts.size() - 1:
			_fill_capsule(pts[i], pts[i + 1], float(r.w), K.WATER)
	for i: Dictionary in d.get("islands", []):
		_fill_ellipse(pt(i.c), _r(i.r), K.WILD)
	_find_bboxes()
	_ridges.clear()
	for r: Dictionary in d.get("ridges", []):
		_ridges.append({"a": pt(r.a), "b": pt(r.b), "w": float(r.w), "h": float(r.h)})
	_wet.clear()
	for w2: Array in d.get("wetlands", []):
		_wet.append(Rect2(Vector2(float(w2[0]), float(w2[1])) * 1000.0, Vector2(float(w2[2]) - float(w2[0]), float(w2[3]) - float(w2[1])) * 1000.0))
	_noise.seed = int(d.get("seed", 1993))
	_noise.frequency = 0.0009
	_noise.fractal_octaves = 3
	_pond_noise.seed = int(d.get("seed", 1993)) + 7
	_pond_noise.frequency = 0.0035
	_build_factors()
	_build_terrain()


## [x, z] in km -> metres.
static func pt(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1])) * 1000.0


static func _r(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _poly(a: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in a:
		out.append(pt(p))
	return out


# --- raster --------------------------------------------------------------------------

func kind_at(x: float, z: float) -> int:
	var i := int(floor((x + half.x) / CELL))
	var j := int(floor((z + half.y) / CELL))
	if i < 0 or j < 0 or i >= rw or j >= rh:
		return K.SEA
	return kind[j * rw + i]


func is_water_kind(k: int) -> bool:
	return k == K.SEA or k == K.WATER


func _fill_poly(pts: PackedVector2Array, k: int) -> void:
	if pts.size() < 3 or k < 0:
		return
	var minz := INF
	var maxz := -INF
	for p in pts:
		minz = minf(minz, p.y)
		maxz = maxf(maxz, p.y)
	var j0 := clampi(int(floor((minz + half.y) / CELL)), 0, rh - 1)
	var j1 := clampi(int(floor((maxz + half.y) / CELL)), 0, rh - 1)
	for j in range(j0, j1 + 1):
		var z := -half.y + (j + 0.5) * CELL
		var xs: Array[float] = []
		for a in pts.size():
			var p := pts[a]
			var q := pts[(a + 1) % pts.size()]
			if (p.y <= z and q.y > z) or (q.y <= z and p.y > z):
				xs.append(p.x + (z - p.y) / (q.y - p.y) * (q.x - p.x))
		xs.sort()
		for n in range(0, xs.size() - 1, 2):
			var i0 := clampi(int(ceil((xs[n] + half.x) / CELL - 0.5)), 0, rw)
			var i1 := clampi(int(floor((xs[n + 1] + half.x) / CELL - 0.5)), -1, rw - 1)
			for i in range(i0, i1 + 1):
				kind[j * rw + i] = k


func _fill_ellipse(c: Vector2, r: Vector2, k: int) -> void:
	var i0 := clampi(int(floor((c.x - r.x + half.x) / CELL)), 0, rw - 1)
	var i1 := clampi(int(floor((c.x + r.x + half.x) / CELL)), 0, rw - 1)
	var j0 := clampi(int(floor((c.y - r.y + half.y) / CELL)), 0, rh - 1)
	var j1 := clampi(int(floor((c.y + r.y + half.y) / CELL)), 0, rh - 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := Vector2(-half.x + (i + 0.5) * CELL, -half.y + (j + 0.5) * CELL) - c
			if (p.x * p.x) / (r.x * r.x) + (p.y * p.y) / (r.y * r.y) <= 1.0:
				kind[j * rw + i] = k


func _fill_capsule(a: Vector2, b: Vector2, width: float, k: int) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(width, width)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(width, width)
	var i0 := clampi(int(floor((lo.x + half.x) / CELL)), 0, rw - 1)
	var i1 := clampi(int(floor((hi.x + half.x) / CELL)), 0, rw - 1)
	var j0 := clampi(int(floor((lo.y + half.y) / CELL)), 0, rh - 1)
	var j1 := clampi(int(floor((hi.y + half.y) / CELL)), 0, rh - 1)
	var ab := b - a
	var len2 := maxf(ab.length_squared(), 0.001)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var p := Vector2(-half.x + (i + 0.5) * CELL, -half.y + (j + 0.5) * CELL)
			var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
			if p.distance_to(a + ab * t) <= width * 0.5:
				kind[j * rw + i] = k


func _find_bboxes() -> void:
	var lo: Array[Vector2] = []
	var hi: Array[Vector2] = []
	for k in KIND_NAMES.size():
		lo.append(Vector2(INF, INF))
		hi.append(Vector2(-INF, -INF))
	for j in rh:
		var z := -half.y + (j + 0.5) * CELL
		for i in rw:
			var k := kind[j * rw + i]
			var x := -half.x + (i + 0.5) * CELL
			lo[k] = Vector2(minf(lo[k].x, x), minf(lo[k].y, z))
			hi[k] = Vector2(maxf(hi[k].x, x), maxf(hi[k].y, z))
	bbox.clear()
	for k in KIND_NAMES.size():
		bbox.append(Rect2(lo[k], hi[k] - lo[k]) if lo[k].x < INF else Rect2())


func area_km2(k: int) -> float:
	var n := 0
	for v in kind:
		if v == k:
			n += 1
	return n * CELL * CELL / 1.0e6


# --- land / urban factors and terrain -------------------------------------------------

func _blur(src: PackedFloat32Array, radius: int) -> PackedFloat32Array:
	var tmp := PackedFloat32Array()
	tmp.resize(rw * rh)
	var out := PackedFloat32Array()
	out.resize(rw * rh)
	var n := float(radius * 2 + 1)
	for j in rh:
		var acc := 0.0
		for i in range(-radius, radius + 1):
			acc += src[j * rw + clampi(i, 0, rw - 1)]
		for i in rw:
			tmp[j * rw + i] = acc / n
			acc += src[j * rw + clampi(i + radius + 1, 0, rw - 1)] - src[j * rw + clampi(i - radius, 0, rw - 1)]
	for i in rw:
		var acc := 0.0
		for j in range(-radius, radius + 1):
			acc += tmp[clampi(j, 0, rh - 1) * rw + i]
		for j in rh:
			out[j * rw + i] = acc / n
			acc += tmp[clampi(j + radius + 1, 0, rh - 1) * rw + i] - tmp[clampi(j - radius, 0, rh - 1) * rw + i]
	return out


func _build_factors() -> void:
	var l := PackedFloat32Array()
	l.resize(rw * rh)
	var u := PackedFloat32Array()
	u.resize(rw * rh)
	for n in rw * rh:
		var k := kind[n]
		l[n] = 0.0 if (k == K.SEA or k == K.WATER) else 1.0
		u[n] = 1.0 if (k >= K.DOWNTOWN) else 0.0
	landf = _blur(_blur(l, 3), 2)
	urbf = _blur(_blur(u, 5), 3)


func _sample(arr: PackedFloat32Array, x: float, z: float) -> float:
	var fx := (x + half.x) / CELL - 0.5
	var fz := (z + half.y) / CELL - 0.5
	fx = clampf(fx, 0.0, rw - 1.001) # past the playable edge the raster's edge values continue
	fz = clampf(fz, 0.0, rh - 1.001)
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * rw + ix
	return lerpf(lerpf(arr[i], arr[i + 1], tx), lerpf(arr[i + rw], arr[i + rw + 1], tx), tz)


func _ridge_height(x: float, z: float) -> float:
	var best := 0.0
	var p := Vector2(x, z)
	for r in _ridges:
		var a: Vector2 = r.a
		var ab: Vector2 = r.b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1.0), 0.0, 1.0)
		var d := p.distance_to(a + ab * t)
		var w: float = r.w
		if d < w:
			var shape := 1.0 - smoothstep(0.2 * w, w, d)
			var rough := 0.7 + 0.6 * (_noise.get_noise_2d(x * 1.7 + 311.0, z * 1.7) * 0.5 + 0.5)
			best = maxf(best, float(r.h) * shape * rough)
	return best


func _build_terrain() -> void:
	torg = -(half + TERR_MARGIN)
	tnx = int(ceil((half.x + TERR_MARGIN.x) * 2.0 / TERR_STEP)) + 1
	tnz = int(ceil((half.y + TERR_MARGIN.y) * 2.0 / TERR_STEP)) + 1
	terr.resize(tnx * tnz)
	for j in tnz:
		var z := torg.y + j * TERR_STEP
		for i in tnx:
			var x := torg.x + i * TERR_STEP
			# Land carries on past the playable edge for a while (room for mountains), then sinks into the sea.
			var outside := maxf(maxf(absf(x) - half.x, absf(z) - half.y), 0.0)
			var lf := _sample(landf, x, z) * (1.0 - smoothstep(0.0, 1300.0, outside))
			var h := lerpf(SEA_FLOOR, LAND, smoothstep(0.38, 0.62, lf))
			if lf > 0.5:
				var uf := _sample(urbf, x, z)
				var relief := (_noise.get_noise_2d(x, z) * 0.5 + 0.5) * 38.0
				relief = maxf(relief, _ridge_height(x, z))
				# No hills or ridges near the districts: the city sits on flat ground.
				h += relief * smoothstep(0.65, 0.95, lf) * (1.0 - smoothstep(0.0, 0.1, uf))
				for w in _wet:
					if w.has_point(Vector2(x, z)) and lf > 0.85:
						var pond := _pond_noise.get_noise_2d(x, z)
						h = lerpf(h, -3.0, smoothstep(0.1, 0.3, pond) * (1.0 - clampf(h / 30.0, 0.0, 1.0)))
			terr[j * tnx + i] = h


## Terrain height at (x, z), bilinear; below zero it is sea / lake / river bed.
func terrain_h(x: float, z: float) -> float:
	var fx := (x - torg.x) / TERR_STEP
	var fz := (z - torg.y) / TERR_STEP
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	if ix < 0 or iz < 0 or ix >= tnx - 1 or iz >= tnz - 1:
		return SEA_FLOOR
	var tx := fx - ix
	var tz := fz - iz
	var i := iz * tnx + ix
	return lerpf(lerpf(terr[i], terr[i + 1], tx), lerpf(terr[i + tnx], terr[i + tnx + 1], tx), tz)
