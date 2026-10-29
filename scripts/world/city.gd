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

# Per-cell building footprint (centre, half extents) and roof height. Height 0 = empty lot.
var _height := PackedFloat32Array()
var _cx := PackedFloat32Array()
var _cz := PackedFloat32Array()
var _hw := PackedFloat32Array()
var _hd := PackedFloat32Array()
var _instance := PackedInt32Array()
var _mm: MultiMesh


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
	_build_ground()
	_build_buildings()
	_build_landmarks()
	_build_salvage_yard()
	_build_mountains()


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
	_mm.set_instance_transform(_instance[c], Transform3D(Basis.from_scale(Vector3(w, 6.0, d)), Vector3(_cx[c], 3.0, _cz[c])))
	_mm.set_instance_color(_instance[c], Color(0.35, 0.3, 0.28))
	return true


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
			if h > 140.0:
				var th := rng.randf_range(25.0, 70.0)
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
	MeshKit.part(yard, MeshKit.box(Vector3(40, 1.0, 40)), MeshKit.toon(Color(0.12, 0.12, 0.14)), Vector3(0, 0.9, 0))
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
