class_name City
extends Node3D
## Procedural Megakat City. Every building lives in one MultiMesh, and collision is a
## per-cell height field queried with height_at(), so no physics bodies are needed.

const N := 28
const CELL := 90.0
const HALF := N * CELL * 0.5
const SEED := 1993

const BuildingShader := preload("res://shaders/building.gdshader")
const GroundShader := preload("res://shaders/ground.gdshader")
const WaterShader := preload("res://shaders/water.gdshader")

## Landmarks the missions refer to.
var city_hall_pos := Vector3.ZERO
var enforcer_hq_pos := Vector3.ZERO
var salvage_yard_pos := Vector3(-1750.0, 0.0, 700.0)
## The two sliding doors of the hidden hangar hatch (opened by the intro sequence).
var hatch_doors: Array[Node3D] = []

# Per-cell building footprint (centre, half extents) and roof height. Height 0 = empty lot.
var _height := PackedFloat32Array()
var _cx := PackedFloat32Array()
var _cz := PackedFloat32Array()
var _hw := PackedFloat32Array()
var _hd := PackedFloat32Array()
var _instance := PackedInt32Array()
var _mm: MultiMesh
## Missile damage, kept until reset_damage() at the start of the next stage: the original
## building transforms and heights, each cell's setback tier and current block height, and the
## rubble piled on broken roofs.
var _xf0: Array[Transform3D] = []
var _seed0 := PackedFloat32Array()
var _color0: Array[Color] = []
var _height0 := PackedFloat32Array()
var _block_h := PackedFloat32Array()
var _tier := PackedInt32Array()
var _tier_broken := {}
var _rubble_mm: MultiMesh
var _rubble_n := 0
const RUBBLE_MAX := 400
## Damaged buildings move into their own MultiMesh: a finely subdivided box whose vertices
## building.gdshader bends (crater at the hit, a lean away from it, a jagged broken roof). Only
## hit buildings pay for the extra vertices; each one's original instance is hidden.
var _dmg_mm: MultiMesh
var _dmg_slot := {} # cell -> instance in _dmg_mm
const DAMAGED_MAX := 96


func _ready() -> void:
	var cells := N * N
	# Packed arrays are value types, so each one is resized directly.
	_height.resize(cells)
	_cx.resize(cells)
	_cz.resize(cells)
	_hw.resize(cells)
	_hd.resize(cells)
	_height.fill(0.0)
	_instance.resize(cells)
	_instance.fill(-1)
	_block_h.resize(cells)
	_block_h.fill(0.0)
	_tier.resize(cells)
	_tier.fill(-1)
	_build_ground()
	_build_buildings()
	_build_landmarks()
	_build_salvage_yard()
	_build_mountains()
	_height0 = _height.duplicate()


## Slides the hatch doors: 0 = closed, 1 = fully open.
func set_hatch(open_amount: float) -> void:
	for k in hatch_doors.size():
		var sx := -1.0 if k == 0 else 1.0
		hatch_doors[k].position.x = (10.0 + open_amount * 22.0) * sx


func cell_index(x: float, z: float) -> int:
	var i := int(floor((x + HALF) / CELL))
	var j := int(floor((z + HALF) / CELL))
	if i < 0 or j < 0 or i >= N or j >= N:
		return -1
	return i * N + j


func cell_center(i: int, j: int) -> Vector3:
	return Vector3(-HALF + (i + 0.5) * CELL, 0.0, -HALF + (j + 0.5) * CELL)


## Height of whatever solid surface is at (x, z): a roof, or 0 for the ground or water.
func height_at(x: float, z: float) -> float:
	var c := cell_index(x, z)
	if c < 0 or _height[c] <= 0.0:
		return 0.0
	if absf(x - _cx[c]) < _hw[c] and absf(z - _cz[c]) < _hd[c]:
		return _height[c]
	return 0.0


## Flattens the building in a cell to rubble. Returns true if something collapsed.
## Bosses that walk through the city use this.
func collapse_at(x: float, z: float) -> bool:
	var c := cell_index(x, z)
	if c < 0 or _instance[c] < 0 or _height[c] <= 8.0:
		return false
	var w := _hw[c] * 2.0
	var d := _hd[c] * 2.0
	_height[c] = 6.0
	_block_h[c] = 6.0
	_mm.set_instance_transform(_instance[c], Transform3D(Basis.from_scale(Vector3(w, 6.0, d)), Vector3(_cx[c], 3.0, _cz[c])))
	_mm.set_instance_color(_instance[c], Color(0.35, 0.3, 0.28))
	return true


## A missile struck a building at `p` (on its surface). Hits near the top knock the roof down and
## pile rubble on it, or snap the setback tier on a tower so it leans over; hits lower down blast
## a burning hole in the wall. Every hit leaves scorching (drawn by building.gdshader) and returns
## where the smoke column should rise, or Vector3.INF if there was no building there.
func damage_at(p: Vector3, power := 1.0) -> Vector3:
	var c := cell_index(p.x, p.z)
	if c < 0 or _instance[c] < 0:
		return Vector3.INF
	if absf(p.x - _cx[c]) > _hw[c] + 3.0 or absf(p.z - _cz[c]) > _hd[c] + 3.0:
		return Vector3.INF
	var tier := _tier[c]
	var bh := _block_h[c]
	var smoke := p
	# The main block, moved into the deformable MultiMesh on its first hit (if there's room).
	var bmm := _mm
	var inst := _instance[c]
	if not _dmg_slot.has(c) and _dmg_slot.size() < DAMAGED_MAX:
		var k := _dmg_slot.size()
		_dmg_slot[c] = k
		_dmg_mm.set_instance_transform(k, _mm.get_instance_transform(inst))
		_dmg_mm.set_instance_color(k, _mm.get_instance_color(inst))
		_dmg_mm.set_instance_custom_data(k, _mm.get_instance_custom_data(inst))
		_dmg_mm.visible_instance_count = _dmg_slot.size()
		_mm.set_instance_transform(inst, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(_cx[c], -50.0, _cz[c])))
	if _dmg_slot.has(c):
		bmm = _dmg_mm
		inst = _dmg_slot[c]
	var scorched_mm := bmm
	var scorched := inst
	if tier >= 0 and p.y > bh - 4.0:
		scorched_mm = _mm
		scorched = tier
		if not _tier_broken.has(c):
			# The tier snaps at its base and leans over, sagging into the roof.
			_tier_broken[c] = true
			var xf := _mm.get_instance_transform(tier)
			var th := xf.basis.get_scale().y
			var axis := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			var rot := Basis(axis, deg_to_rad(randf_range(9.0, 16.0)))
			var base := Vector3(xf.origin.x, bh - 3.0, xf.origin.z)
			_mm.set_instance_transform(tier, Transform3D(rot * xf.basis, base + rot * Vector3(0, th * 0.5, 0)))
			_height[c] = bh + th * 0.9
		_add_rubble(c, bh, 3)
		smoke = Vector3(p.x, maxf(p.y, bh), p.z)
	elif p.y > bh - 22.0 * power or bh < 45.0:
		# Roof hit: knock the top floors off.
		var chunk := minf(randf_range(10.0, 20.0) * power, bh - 12.0)
		if chunk > 2.0:
			bh -= chunk
			_block_h[c] = bh
			var xf := bmm.get_instance_transform(inst)
			var sc := xf.basis.get_scale()
			bmm.set_instance_transform(inst, Transform3D(Basis.from_scale(Vector3(sc.x, bh, sc.z)), Vector3(xf.origin.x, bh * 0.5, xf.origin.z)))
			_height[c] -= chunk
			if tier >= 0:
				var txf := _mm.get_instance_transform(tier)
				txf.origin.y -= chunk
				_mm.set_instance_transform(tier, txf)
		_add_rubble(c, bh, 5)
		var col := bmm.get_instance_color(inst)
		col.a = 0.0 # broken roof: building.gdshader chars the top floors and breaks the roofline
		bmm.set_instance_color(inst, col)
		smoke = Vector3(clampf(p.x, _cx[c] - _hw[c], _cx[c] + _hw[c]), bh, clampf(p.z, _cz[c] - _hd[c], _cz[c] + _hd[c]))
	var cx := _cx[c]
	var cz := _cz[c]
	var seed: float = scorched_mm.get_instance_custom_data(scorched).r
	scorched_mm.set_instance_custom_data(scorched, Color(seed, maxf(smoke.y, 1.0),
		clampf((smoke.x - cx) / _hw[c], -1.2, 1.2), clampf((smoke.z - cz) / _hd[c], -1.2, 1.2)))
	return smoke


## Broken slabs of concrete heaped on a damaged roof, some tipped over the edge.
func _add_rubble(c: int, roof: float, count: int) -> void:
	for k in count:
		var size := Vector3(randf_range(7.0, 16.0), randf_range(2.5, 6.0), randf_range(6.0, 14.0))
		var at := Vector3(_cx[c] + randf_range(-0.8, 0.8) * _hw[c], roof + size.y * 0.3, _cz[c] + randf_range(-0.8, 0.8) * _hd[c])
		var rot := Basis.from_euler(Vector3(randf_range(-0.6, 0.6), randf() * TAU, randf_range(-0.6, 0.6)))
		var i := _rubble_n % RUBBLE_MAX
		_rubble_mm.set_instance_transform(i, Transform3D(rot * Basis.from_scale(size), at))
		var g := randf_range(0.3, 0.48)
		_rubble_mm.set_instance_color(i, Color(g, g * 0.95, g * 0.9))
		_rubble_n += 1
	_rubble_mm.visible_instance_count = mini(_rubble_n, RUBBLE_MAX)


## Undoes all missile damage (called when a stage starts).
func reset_damage() -> void:
	for k in _xf0.size():
		_mm.set_instance_transform(k, _xf0[k])
		_mm.set_instance_custom_data(k, Color(_seed0[k], 0, 0, 0))
		_mm.set_instance_color(k, _color0[k])
	_height = _height0.duplicate()
	for c in _instance.size():
		if _instance[c] >= 0:
			_block_h[c] = _xf0[_instance[c]].basis.get_scale().y
	_tier_broken.clear()
	_dmg_slot.clear()
	_dmg_mm.visible_instance_count = 0
	_rubble_n = 0
	_rubble_mm.visible_instance_count = 0


func _set_cell(c: int, center: Vector3, w: float, d: float, h: float) -> void:
	_cx[c] = center.x
	_cz[c] = center.z
	_hw[c] = w * 0.5
	_hd[c] = d * 0.5
	_height[c] = h


func _build_ground() -> void:
	var ground := PlaneMesh.new()
	ground.size = Vector2(14000, 14000)
	var gm := ShaderMaterial.new()
	gm.shader = GroundShader
	gm.set_shader_parameter("cell_size", CELL)
	gm.set_shader_parameter("city_half", HALF)
	MeshKit.part(self, ground, gm)

	# Megakat Bay to the east.
	var water := PlaneMesh.new()
	water.size = Vector2(6000, 14000)
	var wm := ShaderMaterial.new()
	wm.shader = WaterShader
	MeshKit.part(self, water, wm, Vector3(HALF + 180.0 + 3000.0, 0.4, 0.0))


func _build_buildings() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var hall_c := (N / 2) * N + (N / 2)
	var hq_c := (N / 2 - 4) * N + (N / 2 + 3)
	var xforms: Array[Transform3D] = []
	var colors: Array[Color] = []
	var seeds: Array[float] = []
	var cell_for: Array[int] = []
	var beacons: Array[Vector3] = []

	for i in N:
		for j in N:
			var c := i * N + j
			if c == hall_c or c == hq_c:
				continue
			var center := cell_center(i, j)
			var r := Vector2(center.x, center.z).length() / HALF
			if rng.randf() < 0.08 + r * 0.1:
				continue # park / empty lot
			var w := rng.randf_range(38.0, 62.0)
			var d := rng.randf_range(38.0, 62.0)
			var h := lerpf(250.0, 28.0, clampf(r, 0.0, 1.0)) * rng.randf_range(0.35, 1.0) + 14.0
			_set_cell(c, center, w, d, h)
			_instance[c] = xforms.size()
			xforms.append(Transform3D(Basis.from_scale(Vector3(w, h, d)), center + Vector3(0, h * 0.5, 0)))
			colors.append(Color.from_hsv(rng.randf_range(0.55, 0.72), rng.randf_range(0.05, 0.3), rng.randf_range(0.5, 0.95)))
			seeds.append(rng.randf())
			cell_for.append(c)
			# Setback tier on tall towers, for a stepped art-deco skyline.
			_block_h[c] = h
			if h > 140.0:
				var th := rng.randf_range(25.0, 70.0)
				_tier[c] = xforms.size()
				xforms.append(Transform3D(Basis.from_scale(Vector3(w * 0.6, th, d * 0.6)), center + Vector3(0, h + th * 0.5, 0)))
				colors.append(colors[colors.size() - 1])
				seeds.append(rng.randf())
				cell_for.append(-1)
				_height[c] = h + th # conservative collision: whole footprint at full height
				beacons.append(center + Vector3(0, h + th + 2.0, 0))

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = true
	_mm.mesh = MeshKit.box(Vector3.ONE)
	_mm.instance_count = xforms.size()
	for k in xforms.size():
		_mm.set_instance_transform(k, xforms[k])
		_mm.set_instance_color(k, colors[k])
		_mm.set_instance_custom_data(k, Color(seeds[k], 0, 0, 0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = _mm
	var bm := ShaderMaterial.new()
	bm.shader = BuildingShader
	mmi.material_override = bm
	add_child(mmi)
	_xf0 = xforms.duplicate()
	_seed0 = PackedFloat32Array(seeds)
	_color0 = colors.duplicate()

	_dmg_mm = MultiMesh.new()
	_dmg_mm.transform_format = MultiMesh.TRANSFORM_3D
	_dmg_mm.use_colors = true
	_dmg_mm.use_custom_data = true
	var dense := BoxMesh.new()
	dense.subdivide_width = 8
	dense.subdivide_depth = 8
	dense.subdivide_height = 16
	_dmg_mm.mesh = dense
	_dmg_mm.instance_count = DAMAGED_MAX
	_dmg_mm.visible_instance_count = 0
	var dmi := MultiMeshInstance3D.new()
	dmi.multimesh = _dmg_mm
	var dm := bm.duplicate() as ShaderMaterial
	dm.set_shader_parameter("deform", true)
	dmi.material_override = dm
	dmi.custom_aabb = AABB(Vector3(-HALF, -10, -HALF), Vector3(HALF * 2.0, 600, HALF * 2.0))
	add_child(dmi)

	_rubble_mm = MultiMesh.new()
	_rubble_mm.transform_format = MultiMesh.TRANSFORM_3D
	_rubble_mm.use_colors = true
	_rubble_mm.mesh = MeshKit.box(Vector3.ONE)
	_rubble_mm.instance_count = RUBBLE_MAX
	_rubble_mm.visible_instance_count = 0
	var rmi := MultiMeshInstance3D.new()
	rmi.multimesh = _rubble_mm
	var rm := MeshKit.toon(Color.WHITE, 0.0, 0.9)
	rm.vertex_color_use_as_albedo = true
	rmi.material_override = rm
	rmi.custom_aabb = AABB(Vector3(-HALF, -10, -HALF), Vector3(HALF * 2.0, 600, HALF * 2.0))
	add_child(rmi)

	_build_point_lights(beacons)


## Street lamps along every road plus red aviation beacons on the tallest towers.
func _build_point_lights(beacons: Array[Vector3]) -> void:
	var lamps: Array[Vector3] = []
	var k := 0.0
	while k <= N:
		var line := -HALF + k * CELL
		var s := -HALF
		while s <= HALF:
			lamps.append(Vector3(line + 11.0, 6.0, s))
			lamps.append(Vector3(s, 6.0, line - 11.0))
			s += 45.0
		k += 1.0
	_point_cloud(lamps, MeshKit.box(Vector3(1.6, 1.0, 1.6)), MeshKit.glow(Color(1.0, 0.72, 0.35)))
	_point_cloud(beacons, MeshKit.sphere(1.8, 6), MeshKit.glow(Color(1.0, 0.15, 0.1)))


func _point_cloud(points: Array[Vector3], mesh: Mesh, mat: Material) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = points.size()
	for i in points.size():
		mm.set_instance_transform(i, Transform3D(Basis(), points[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)


func _build_landmarks() -> void:
	# City Hall: domed civic tower in the centre of downtown.
	var hall_c := (N / 2) * N + (N / 2)
	city_hall_pos = cell_center(N / 2, N / 2)
	var stone := MeshKit.toon(Color(0.78, 0.74, 0.66), 0.0, 0.8)
	var gold := MeshKit.toon(Color(0.95, 0.72, 0.25), 0.7, 0.3)
	MeshKit.part(self, MeshKit.box(Vector3(64, 40, 64)), stone, city_hall_pos + Vector3(0, 20, 0))
	MeshKit.part(self, MeshKit.cyl(18, 22, 120, 16), stone, city_hall_pos + Vector3(0, 100, 0))
	MeshKit.part(self, MeshKit.sphere(19, 16), gold, city_hall_pos + Vector3(0, 160, 0))
	MeshKit.part(self, MeshKit.cyl(0.5, 2.5, 40, 6), gold, city_hall_pos + Vector3(0, 195, 0))
	_set_cell(hall_c, city_hall_pos, 64, 64, 178)

	# Enforcer HQ: a hard-edged tower with a rooftop helipad.
	var hq_c := (N / 2 - 4) * N + (N / 2 + 3)
	enforcer_hq_pos = cell_center(N / 2 - 4, N / 2 + 3)
	var steel := MeshKit.toon(Color(0.32, 0.36, 0.44), 0.5, 0.4)
	var stripe := MeshKit.glow(Color(0.3, 0.6, 1.0))
	MeshKit.part(self, MeshKit.box(Vector3(56, 230, 56)), steel, enforcer_hq_pos + Vector3(0, 115, 0))
	for y in [60.0, 120.0, 180.0]:
		MeshKit.part(self, MeshKit.box(Vector3(57, 2, 57)), stripe, enforcer_hq_pos + Vector3(0, y, 0))
	MeshKit.part(self, MeshKit.cyl(22, 22, 3, 20), MeshKit.toon(Color(0.2, 0.2, 0.22)), enforcer_hq_pos + Vector3(0, 232, 0))
	_set_cell(hq_c, enforcer_hq_pos, 56, 56, 234)


## The salvage yard: junk piles over the TurboKat's hidden hangar.
func _build_salvage_yard() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 1
	var rust := [Color(0.45, 0.27, 0.16), Color(0.35, 0.33, 0.3), Color(0.5, 0.42, 0.2), Color(0.28, 0.3, 0.36)]
	var yard := Node3D.new()
	yard.position = salvage_yard_pos
	add_child(yard)
	MeshKit.part(yard, MeshKit.box(Vector3(260, 0.6, 220)), MeshKit.toon(Color(0.24, 0.2, 0.16), 0.0, 1.0), Vector3(0, 0.3, 0))
	for n in 70:
		var p := Vector3(rng.randf_range(-120, 120), 0, rng.randf_range(-100, 100))
		if absf(p.x) < 28 and absf(p.z) < 28:
			continue # keep the hangar hatch clear
		var s := Vector3(rng.randf_range(4, 9), rng.randf_range(2, 4), rng.randf_range(8, 14))
		p.y = s.y * 0.5 + rng.randf_range(0.0, 6.0)
		MeshKit.part(yard, MeshKit.box(s), MeshKit.toon(rust[n % rust.size()], 0.3, 0.8), p, Vector3(rng.randf_range(-0.3, 0.3), rng.randf(), rng.randf_range(-0.3, 0.3)))
	# Hangar hatch with hazard edge.
	MeshKit.part(yard, MeshKit.box(Vector3(46, 0.8, 46)), MeshKit.toon(Color(0.95, 0.75, 0.1)), Vector3(0, 0.7, 0))
	# The shaft below shows as a black pit once the doors slide apart.
	MeshKit.part(yard, MeshKit.box(Vector3(40, 0.1, 40)), MeshKit.glow(Color(0.01, 0.01, 0.015)), Vector3(0, 1.16, 0))
	for sx in [-1.0, 1.0]:
		var door := MeshKit.part(yard, MeshKit.box(Vector3(20, 1.0, 40)), MeshKit.toon(Color(0.12, 0.12, 0.14)), Vector3(10.0 * sx, 1.4, 0))
		MeshKit.part(door, MeshKit.box(Vector3(2.0, 0.1, 40)), MeshKit.toon(Color(0.95, 0.75, 0.1)), Vector3(-9.0 * sx, 0.52, 0))
		hatch_doors.append(door)
	# The tow-truck crane.
	MeshKit.part(yard, MeshKit.box(Vector3(3, 60, 3)), MeshKit.toon(Color(0.8, 0.55, 0.1)), Vector3(70, 30, -60))
	MeshKit.part(yard, MeshKit.box(Vector3(60, 3, 3)), MeshKit.toon(Color(0.8, 0.55, 0.1)), Vector3(48, 60, -60))


func _build_mountains() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 2
	var rock := MeshKit.toon(Color(0.2, 0.17, 0.27), 0.0, 1.0)
	var snow := MeshKit.toon(Color(0.75, 0.7, 0.8), 0.0, 1.0)
	for n in 46:
		var a := TAU * n / 46.0 + rng.randf_range(-0.05, 0.05)
		if cos(a) > 0.55:
			continue # leave the bay side open
		var r := rng.randf_range(4300, 5200)
		var h := rng.randf_range(350, 900)
		var base := rng.randf_range(350, 700)
		var pos := Vector3(cos(a) * r, h * 0.5, sin(a) * r)
		MeshKit.part(self, MeshKit.cyl(0.0, base, h, 6), rock, pos, Vector3(0, rng.randf() * TAU, 0))
		if h > 650:
			MeshKit.part(self, MeshKit.cyl(0.0, base * 0.22, h * 0.22, 6), snow, pos + Vector3(0, h * 0.39 + 1.0, 0))
