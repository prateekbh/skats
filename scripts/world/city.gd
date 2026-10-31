class_name City
extends Node3D
## Megakat City: a 15 x 10 km world built from data/city_plan.json (see CityPlan, CityBuildings,
## CityLandmarks). Collision is a height lookup (height_at), so no physics bodies are needed.
##
## Public API the game uses: height_at, damage_at, reset_damage, set_hatch, hatch_doors, the
## landmark positions, world_half, launch_dir and cache_spots.

const GroundShader := preload("res://shaders/ground.gdshader")
const WaterShader := preload("res://shaders/water.gdshader")

var plan: CityPlan
var buildings: CityBuildings
var world_half := Vector2(7500.0, 5000.0)

## Landmarks the missions refer to (ground positions, y = 0).
var tower_pos := Vector3.ZERO
var city_hall_pos := Vector3.ZERO
var enforcer_hq_pos := Vector3.ZERO
var salvage_yard_pos := Vector3.ZERO
var downtown_pos := Vector3.ZERO
## Horizontal direction the TurboKat flies off the yard at (towards City Hall).
var launch_dir := Vector3.FORWARD
## The two sliding doors of the hidden hangar hatch (opened by the intro sequence).
var hatch_doors: Array[Node3D] = []
## Ground supply caches: {pos, kind, guarded}.
var cache_spots: Array[Dictionary] = []
var clock_hands: Array[Node3D] = [] # [hour pivots..., minute pivots...] rotated by _process
var build_ms := {}

var _clock_t := 0.0


func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	plan = CityPlan.new()
	plan.build(CityPlan.load_data("res://data/city_plan.json"))
	world_half = plan.half
	var lm: Dictionary = plan.data.landmarks
	tower_pos = _ground(CityPlan.pt(lm.tower))
	city_hall_pos = _ground(CityPlan.pt(lm.hall))
	enforcer_hq_pos = _ground(CityPlan.pt(lm.hq))
	salvage_yard_pos = _ground(CityPlan.pt(lm.yard))
	downtown_pos = _ground(CityPlan.pt(lm.downtown))
	launch_dir = Vector3(city_hall_pos.x - salvage_yard_pos.x, 0.0, city_hall_pos.z - salvage_yard_pos.z).normalized()
	build_ms["plan"] = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	_build_terrain()
	_build_water()
	build_ms["terrain"] = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	buildings = CityBuildings.new(plan)
	buildings.generate()
	build_ms["buildings"] = Time.get_ticks_msec() - t0
	t0 = Time.get_ticks_msec()
	CityLandmarks.build(self)
	_scatter_trees()
	_pick_caches()
	buildings.finalize(self)
	build_ms["landmarks+meshes"] = Time.get_ticks_msec() - t0


func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, 0.0, p.y)


func _process(delta: float) -> void:
	if clock_hands.is_empty():
		return
	# The City Hall clock runs 60x fast: a visible minute hand, an hour hand that creeps.
	_clock_t += delta * 60.0
	var minutes := fmod(_clock_t / 60.0 + 8.0, 60.0)
	var hours := fmod(_clock_t / 3600.0 + 10.0 + 8.0 / 60.0, 12.0)
	for k in clock_hands.size():
		var hand := clock_hands[k]
		hand.rotation.z = -(hours / 12.0 if k % 2 == 0 else minutes / 60.0) * TAU


# --- terrain -------------------------------------------------------------------------

func _build_terrain() -> void:
	var nx := plan.tnx
	var nz := plan.tnz
	var step := CityPlan.TERR_STEP
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	verts.resize(nx * nz)
	norms.resize(nx * nz)
	cols.resize(nx * nz)
	var noise := FastNoiseLite.new()
	noise.seed = 31
	noise.frequency = 0.004
	for j in nz:
		for i in nx:
			var n := j * nx + i
			var x := plan.torg.x + i * step
			var z := plan.torg.y + j * step
			var h := plan.terr[n]
			verts[n] = Vector3(x, h, z)
			var hl := plan.terr[j * nx + maxi(i - 1, 0)]
			var hr := plan.terr[j * nx + mini(i + 1, nx - 1)]
			var hu := plan.terr[maxi(j - 1, 0) * nx + i]
			var hd := plan.terr[mini(j + 1, nz - 1) * nx + i]
			var nrm := Vector3(hl - hr, 2.0 * step, hu - hd).normalized()
			norms[n] = nrm
			cols[n] = _ground_color(x, z, h, nrm.y, noise.get_noise_2d(x, z))
	var idx := PackedInt32Array()
	idx.resize((nx - 1) * (nz - 1) * 6)
	var k := 0
	for j in nz - 1:
		for i in nx - 1:
			var a := j * nx + i
			idx[k] = a
			idx[k + 1] = a + 1
			idx[k + 2] = a + nx + 1
			idx[k + 3] = a
			idx[k + 4] = a + nx + 1
			idx[k + 5] = a + nx
			k += 6
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mat := ShaderMaterial.new()
	mat.shader = GroundShader
	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _ground_color(x: float, z: float, h: float, ny: float, n: float) -> Color:
	var k := plan.kind_at(x, z)
	var urban := 1.0 if (k >= CityPlan.K.DOWNTOWN and k != CityPlan.K.PARK) else 0.0
	var grass := Color(0.2, 0.34, 0.15).lerp(Color(0.34, 0.38, 0.17), n * 0.5 + 0.5)
	if k == CityPlan.K.PARK:
		var park := Color(0.26, 0.46, 0.2).lerp(Color(0.32, 0.52, 0.22), n * 0.5 + 0.5)
		return Color(park.r, park.g, park.b, 0.0)
	if urban > 0.5:
		return Color(0.12, 0.12, 0.14, 1.0)
	var c := grass
	if h < 2.4:
		c = Color(0.72, 0.64, 0.44) if h > -3.0 else Color(0.35, 0.42, 0.32) # beach, wet shore
	elif ny < 0.82 or h > 170.0:
		c = Color(0.38, 0.35, 0.33).lerp(grass, clampf((ny - 0.7) * 4.0, 0.0, 0.5) if h < 170.0 else 0.0)
	if h > 560.0:
		c = c.lerp(Color(0.93, 0.94, 0.98), clampf((h - 560.0) / 120.0, 0.0, 1.0))
	return Color(c.r, c.g, c.b, 0.0)


func _build_water() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(60000, 60000)
	var wm := ShaderMaterial.new()
	wm.shader = WaterShader
	var mi := MeshInstance3D.new()
	mi.name = "Water"
	mi.mesh = plane
	mi.material_override = wm
	mi.position = Vector3(0, 0.0, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# --- trees and caches ----------------------------------------------------------------

func _scatter_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var park := plan.bbox[CityPlan.K.PARK]
	if park.size.x > 0.0:
		for n in 150:
			var c := Vector2(rng.randf_range(park.position.x, park.end.x), rng.randf_range(park.position.y, park.end.y))
			if plan.kind_at(c.x, c.y) != CityPlan.K.PARK or plan.terrain_h(c.x, c.y) < 0.5:
				continue
			var radius := rng.randf_range(30.0, 75.0)
			for t in rng.randi_range(14, 34):
				var a := rng.randf() * TAU
				var r := sqrt(rng.randf()) * radius
				var p := c + Vector2(cos(a), sin(a)) * r
				if plan.kind_at(p.x, p.y) == CityPlan.K.PARK and plan.terrain_h(p.x, p.y) > 0.5:
					buildings.add_tree(Vector3(p.x, plan.terrain_h(p.x, p.y), p.y), rng.randf_range(1.2, 1.9))
	var forest := FastNoiseLite.new()
	forest.seed = 99
	forest.frequency = 0.0011
	var x := -plan.half.x
	while x < plan.half.x:
		var z := -plan.half.y
		while z < plan.half.y:
			var p := Vector2(x + rng.randf_range(0.0, 140.0), z + rng.randf_range(0.0, 140.0))
			if plan.kind_at(p.x, p.y) == CityPlan.K.WILD and forest.get_noise_2d(p.x, p.y) > -0.05:
				var h := plan.terrain_h(p.x, p.y)
				if h > 1.5 and h < 230.0 and rng.randf() < 0.55:
					buildings.add_tree(Vector3(p.x, h, p.y), rng.randf_range(1.6, 2.6))
			z += 140.0
		x += 140.0


## Chooses the supply-cache spots from the plan's per-district counts: street plazas the
## generator left open, the ends of the piers, and meadows in the park.
func _pick_caches() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 555
	var want: Dictionary = plan.data.get("caches", {})
	var guard := float(want.get("guard_chance", 0.3))
	var by_kind := {}
	for s in buildings.cache_spots:
		var k: String = s.kind
		if not by_kind.has(k):
			by_kind[k] = []
		by_kind[k].append(s.pos)
	for kname: String in want:
		if kname == "guard_chance":
			continue
		var pool: Array = by_kind.get(kname, [])
		if kname == "park":
			var park := plan.bbox[CityPlan.K.PARK]
			for tries in 200:
				var p := Vector2(rng.randf_range(park.position.x, park.end.x), rng.randf_range(park.position.y, park.end.y))
				if plan.kind_at(p.x, p.y) == CityPlan.K.PARK and plan.terrain_h(p.x, p.y) > 0.5:
					pool.append(Vector3(p.x, CityPlan.LAND, p.y))
		if kname == "industrial":
			for pp in pier_ends():
				pool.append(pp)
		pool.shuffle()
		for n in mini(int(want[kname]), pool.size()):
			cache_spots.append({"pos": pool[n], "kind": kname, "guarded": rng.randf() < guard})


func pier_ends() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var piers: Dictionary = plan.data.get("piers", {})
	var dir := deg_to_rad(float(piers.get("dir", 127)))
	for p: Array in piers.get("list", []):
		var start := CityPlan.pt(p)
		var end := start + Vector2(cos(dir), sin(dir)) * (float(p[2]) - 25.0)
		out.append(Vector3(end.x, 3.2, end.y))
	return out


# --- game-facing API -----------------------------------------------------------------

## Height of whatever solid surface is at (x, z): a roof, the terrain, or 0 for water.
func height_at(x: float, z: float) -> float:
	return buildings.height_at(x, z)


## A missile struck a building at `p`; see CityBuildings.damage_at.
func damage_at(p: Vector3, power := 1.0) -> Vector3:
	return buildings.damage_at(p, power)


func reset_damage() -> void:
	buildings.reset_damage()


## Slides the hatch doors: 0 = closed, 1 = fully open.
func set_hatch(open_amount: float) -> void:
	for k in hatch_doors.size():
		var sx := -1.0 if k == 0 else 1.0
		hatch_doors[k].position.x = 10.0 * sx + sx * 22.0 * open_amount
