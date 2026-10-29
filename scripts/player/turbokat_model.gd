class_name TurboKatModel
extends RefCounted
## The TurboKat. Nose points to -Z (Godot forward).
##
## By default this uses the imported airframe in assets/turbokat/ (CC-BY model by RabbitXGT /
## Captain_Ahab_62, painted region by region by tools/convert_turbokat.py). It has two wing
## poses, open and swept, which the jet swaps between with airspeed, as in the show.
## If those files are missing, a procedural airframe is built instead (the _build_* functions).
##
## Paint scheme, taken from the show's hangar shot: glossy black airframe, red cockpit pod
## with royal-blue glass, red panels, royal-blue wingtip panels and nose tip, red engine pods.
## All colours live in the constants below.

const BLACK := Color(0.07, 0.07, 0.1)
const FACET := Color(0.11, 0.11, 0.14)
const RED := Color(0.85, 0.12, 0.09)
const BLUE := Color(0.2, 0.3, 0.85)
const GLASS := Color(0.28, 0.42, 0.95)
const WHITE := Color(0.88, 0.88, 0.9)
const STEEL := Color(0.35, 0.36, 0.4)

const INK := 0.045 # outline thickness

const MODEL_SWEPT := "res://assets/turbokat/turbokat_swept.glb"
const MODEL_OPEN := "res://assets/turbokat/turbokat_open.glb"
## Engine nozzle centres on the imported airframe (printed by tools/convert_turbokat.py).
const NOZZLES: Array[Vector3] = [Vector3(-2.3, -0.34, 11.0), Vector3(2.3, -0.34, 11.0)]
const NOZZLE_RADIUS := 0.85


## Returns {"root", "burners": Array[Node3D], "wingtips": Array[Vector3], "missiles": Array[Node3D], "fans": Array[Node3D]}.
static func build(parent: Node3D) -> Dictionary:
	var root := Node3D.new()
	root.name = "TurboKat"
	parent.add_child(root)
	if ResourceLoader.exists(MODEL_SWEPT) and ResourceLoader.exists(MODEL_OPEN):
		return _build_imported(root)

	var black := _paint(BLACK, 0.55, 0.35, 0.55)
	var facet := _paint(FACET, 0.5, 0.4, 0.45)
	var red := _paint(RED, 0.25, 0.4, 0.25)
	var blue := _paint(BLUE, 0.2, 0.4, 0.2)
	var white := _paint(WHITE, 0.3, 0.35, 0.1)
	var steel := _paint(STEEL, 0.7, 0.3, 0.1)
	var dark := MeshKit.toon(Color(0.02, 0.02, 0.03), 0.6, 0.4)
	var glass := MeshKit.glass(GLASS)
	glass.emission_energy_multiplier = 0.55
	MeshKit.outlined(glass, INK)

	_build_fuselage(root, black, facet)
	_build_cockpit(root, red, glass)
	_build_wings(root, black, red, blue)
	_build_blades(root, black, blue)
	_build_tails(root, black, blue, red)
	var engines := _build_engines(root, red, white, steel, dark)
	var missiles := _build_hardpoints(root, steel, white, red)

	# Gun ports in the nose chines.
	for sx in [-1.0, 1.0]:
		MeshKit.part(root, MeshKit.cyl(0.13, 0.13, 1.2, 8), dark, Vector3(0.85 * sx, -0.05, -8.6), Vector3(-PI / 2, 0, 0))
	# Nav lights: red to port (left, -X), green to starboard.
	MeshKit.part(root, MeshKit.sphere(0.22, 6), MeshKit.glow(Color(1, 0.1, 0.1)), Vector3(-9.45, -0.05, 9.3))
	MeshKit.part(root, MeshKit.sphere(0.22, 6), MeshKit.glow(Color(0.1, 1, 0.3)), Vector3(9.45, -0.05, 9.3))

	return {
		"root": root,
		"burners": engines.burners,
		"fans": engines.fans,
		"missiles": missiles,
		"wingtips": [Vector3(-9.5, -0.05, 9.4), Vector3(9.5, -0.05, 9.4)],
	}


const CelShader := preload("res://shaders/cel.gdshader")


## Cel-shaded material for the imported airframe.
static func _cel(c: Color, shadow: Color, gloss: float, rim: float, glow := 0.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CelShader
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("shadow_tint", shadow)
	m.set_shader_parameter("gloss_strength", gloss)
	m.set_shader_parameter("rim_strength", rim)
	if glow > 0.0:
		m.set_shader_parameter("emission_color", c)
		m.set_shader_parameter("emission_energy", glow)
	return m


## Black inverted-hull ink line, grown along the outline mesh's fully smoothed normals.
static func _ink(thickness: float) -> StandardMaterial3D:
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color(0.0, 0.0, 0.0)
	ink.cull_mode = BaseMaterial3D.CULL_FRONT
	ink.grow = true
	ink.grow_amount = thickness
	return ink


static func _paint(c: Color, metallic: float, roughness: float, rim: float) -> StandardMaterial3D:
	var m := MeshKit.toon(c, metallic, roughness)
	# A cool rim light keeps the black airframe readable against a dark dusk sky.
	m.rim_enabled = true
	m.rim = rim
	m.rim_tint = 0.2
	MeshKit.outlined(m, INK)
	return m


## Hexagonal-ish cross-section: flat chines, raised dorsal ridge, flat belly.
static func _section(w: float, top: float, bottom: float, ridge := 0.0, y0 := 0.0) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(w, y0), Vector2(w * 0.6, y0 + top), Vector2(0, y0 + top + ridge),
		Vector2(-w * 0.6, y0 + top), Vector2(-w, y0), Vector2(-w * 0.62, y0 - bottom),
		Vector2(w * 0.62, y0 - bottom),
	])


static func _build_fuselage(root: Node3D, black: Material, facet: Material) -> void:
	# [z, half width, top, bottom, ridge]
	var stations := [
		[-13.2, 0.05, 0.04, 0.04, 0.0],
		[-10.8, 0.7, 0.32, 0.28, 0.08],
		[-7.6, 1.3, 0.66, 0.48, 0.14],
		[-4.0, 1.8, 0.92, 0.62, 0.2],
		[0.0, 2.05, 1.02, 0.72, 0.24],
		[4.0, 2.15, 0.95, 0.78, 0.2],
		[7.4, 1.95, 0.75, 0.74, 0.1],
		[9.0, 1.55, 0.52, 0.58, 0.0],
	]
	var secs := []
	var zs := []
	for s in stations:
		secs.append(_section(s[1], s[2], s[3], s[4]))
		zs.append(s[0])
	MeshKit.part(root, MeshKit.loft(secs, zs), black)
	# Dorsal spine behind the cockpit: a slightly lighter facet for panel definition.
	var spine := []
	var spine_z := []
	for s in [[-1.0, 0.5, 0.15, 0.05, 1.18], [3.0, 0.62, 0.2, 0.05, 1.12], [7.0, 0.45, 0.1, 0.05, 0.82]]:
		spine.append(_section(s[1], s[2], s[3], 0.08, s[4]))
		spine_z.append(s[0])
	MeshKit.part(root, MeshKit.loft(spine, spine_z), facet)
	# Angular side intakes under the chines.
	var intake := PackedVector2Array([Vector2(0, -2.8), Vector2(0.9, -1.6), Vector2(0.9, 2.6), Vector2(0, 2.6)])
	for sx in [-1.0, 1.0]:
		var it := MeshKit.part(root, MeshKit.slab(intake, 0.9), facet, Vector3(1.55 * sx, -0.45, -1.2))
		it.scale.x = sx


static func _build_cockpit(root: Node3D, red: Material, glass: Material) -> void:
	# [z, half width, top, y0]: the pod sits on the forward fuselage ridge.
	var stations := [
		[-11.8, 0.06, 0.04, 0.26],
		[-9.6, 0.52, 0.46, 0.42],
		[-7.0, 0.88, 0.98, 0.68],
		[-4.2, 0.98, 1.12, 0.9],
		[-1.6, 0.86, 0.8, 1.02],
		[0.6, 0.34, 0.2, 1.1],
	]
	var secs := []
	var zs := []
	for s in stations:
		secs.append(_section(s[1], s[2], 0.2, 0.06, s[3]))
		zs.append(s[0])
	MeshKit.part(root, MeshKit.loft(secs, zs), red)
	# Window band: a narrower loft just proud of the pod's top facets.
	var gsecs := []
	var gzs := []
	for s in [[-9.2, 0.38, 0.5, 0.47], [-7.0, 0.72, 1.0, 0.7], [-4.2, 0.8, 1.14, 0.92], [-2.3, 0.68, 0.94, 1.0]]:
		gsecs.append(_section(s[1], s[2], 0.05, 0.07, s[3]))
		gzs.append(s[0])
	MeshKit.part(root, MeshKit.loft(gsecs, gzs), glass)
	# Red canopy frames split the glass into panels: windshield bar, a bar between the seats,
	# and a centre spine (T-Bone flies up front, Razor runs weapons behind him).
	MeshKit.part(root, MeshKit.box(Vector3(1.6, 0.18, 0.3)), red, Vector3(0, 1.74, -7.4), Vector3(0.2, 0, 0))
	MeshKit.part(root, MeshKit.box(Vector3(1.8, 0.18, 0.32)), red, Vector3(0, 2.08, -4.8))
	MeshKit.part(root, MeshKit.box(Vector3(0.16, 0.12, 6.6)), red, Vector3(0, 2.05, -5.4), Vector3(-0.06, 0, 0))


static func _build_wings(root: Node3D, black: Material, red: Material, blue: Material) -> void:
	# Big swept delta with a jagged, saw-toothed trailing edge.
	var wing := PackedVector2Array([
		Vector2(1.6, -5.2), Vector2(8.9, 6.1), Vector2(9.6, 9.7), Vector2(7.4, 8.0),
		Vector2(5.6, 9.2), Vector2(3.6, 7.6), Vector2(1.6, 8.4),
	])
	var lead_a := Vector2(1.9, -4.4)
	var lead_b := Vector2(8.9, 6.4)
	var sweep := atan2(lead_b.x - lead_a.x, lead_b.y - lead_a.y)
	for sx in [-1.0, 1.0]:
		var side := Node3D.new()
		side.scale.x = sx # mirror the right wing to make the left
		side.position.y = -0.1
		root.add_child(side)
		MeshKit.part(side, MeshKit.slab(wing, 0.36), black)
		# Lavender leading-edge stripe, slightly thicker than the wing so it shows top and bottom.
		MeshKit.part(side, MeshKit.slab(_strip(lead_a, lead_b, 0.55, Vector2(5, 4)), 0.42), blue)
		# Rear tip accent.
		MeshKit.part(side, MeshKit.slab(PackedVector2Array([Vector2(8.6, 7.4), Vector2(9.6, 9.7), Vector2(8.9, 9.2), Vector2(8.2, 7.9)]), 0.42), blue)
		# Red slit panels along the sweep.
		for k in 3:
			var p := Vector3(3.3 + k * 1.15, 0.2, 1.3 + k * 1.6)
			MeshKit.part(side, MeshKit.box(Vector3(0.32, 0.05, 1.5)), red, p, Vector3(0, sweep, 0))


## A thin parallelogram along edge a→b, offset toward `inside`.
static func _strip(a: Vector2, b: Vector2, width: float, inside: Vector2) -> PackedVector2Array:
	var d := (b - a).normalized()
	var n := Vector2(-d.y, d.x)
	if n.dot(inside - a) < 0.0:
		n = -n
	return PackedVector2Array([a, b, b + n * width, a + n * width])


## Hooked forward blades flanking the cockpit.
static func _build_blades(root: Node3D, black: Material, blue: Material) -> void:
	# Drawn as (height, z): rakes forward and up to a hook.
	var blade := PackedVector2Array([Vector2(0, -3.4), Vector2(0, 0.6), Vector2(1.5, -0.4), Vector2(2.3, -4.8), Vector2(1.6, -4.0)])
	for sx in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(1.25 * sx, 0.55, -4.0)
		pivot.rotation = Vector3(0, 0, PI / 2 - 0.75 * sx)
		root.add_child(pivot)
		MeshKit.part(pivot, MeshKit.slab(blade, 0.2), black)
		MeshKit.part(pivot, MeshKit.slab(_strip(Vector2(1.6, -4.0), Vector2(2.3, -4.8), 0.25, Vector2(0, -2)), 0.24), blue)


static func _build_tails(root: Node3D, black: Material, blue: Material, red: Material) -> void:
	var fin := PackedVector2Array([Vector2(0, 3.0), Vector2(0, 8.7), Vector2(4.6, 10.1), Vector2(4.5, 8.6), Vector2(2.2, 6.4)])
	for sx in [-1.0, 1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(1.75 * sx, 0.75, 0.0)
		pivot.rotation = Vector3(0, 0, PI / 2 - 0.38 * sx) # canted outward
		root.add_child(pivot)
		MeshKit.part(pivot, MeshKit.slab(fin, 0.24), black)
		MeshKit.part(pivot, MeshKit.slab(_strip(Vector2(0, 3.0), Vector2(2.2, 6.4), 0.4, Vector2(0, 8)), 0.28), blue)
		MeshKit.part(pivot, MeshKit.slab(_strip(Vector2(2.2, 6.4), Vector2(4.5, 8.6), 0.4, Vector2(0, 8)), 0.28), blue)
		MeshKit.part(pivot, MeshKit.box(Vector3(0.5, 0.3, 1.2)), red, Vector3(3.2, 0, 8.6))


## Twin rear turbofans. Returns {"burners": [...], "fans": [...]}.
static func _build_engines(root: Node3D, red: Material, white: Material, steel: Material, dark: Material) -> Dictionary:
	var burners: Array[Node3D] = []
	var fans: Array[Node3D] = []
	var flame := MeshKit.glow(Color(1.0, 0.5, 0.18, 0.85), true)
	var core := MeshKit.glow(Color(0.65, 0.85, 1.0, 0.9), true)
	var fwd := Vector3(-PI / 2, 0, 0)
	for sx in [-1.0, 1.0]:
		var e := Node3D.new()
		e.position = Vector3(2.65 * sx, -0.65, 7.0)
		root.add_child(e)
		# Red housing with a raised lip at each end.
		MeshKit.part(e, MeshKit.cyl(1.45, 1.55, 4.0, 22), red, Vector3.ZERO, fwd)
		var lip := TorusMesh.new()
		lip.inner_radius = 1.25
		lip.outer_radius = 1.68
		lip.rings = 20
		lip.ring_segments = 8
		MeshKit.part(e, lip, red, Vector3(0, 0, 2.0), Vector3(PI / 2, 0, 0))
		MeshKit.part(e, lip, red, Vector3(0, 0, -2.0), Vector3(PI / 2, 0, 0))
		# White turbine ring and the dark fan face inside it.
		var ring := TorusMesh.new()
		ring.inner_radius = 0.86
		ring.outer_radius = 1.26
		ring.rings = 20
		ring.ring_segments = 6
		MeshKit.part(e, ring, white, Vector3(0, 0, 1.95), Vector3(PI / 2, 0, 0))
		MeshKit.part(e, MeshKit.cyl(0.95, 0.95, 0.1, 16), dark, Vector3(0, 0, 1.8), fwd)
		var fan := Node3D.new()
		fan.position = Vector3(0, 0, 1.88)
		e.add_child(fan)
		for k in 9:
			var a := TAU * k / 9.0
			MeshKit.part(fan, MeshKit.box(Vector3(0.16, 0.85, 0.04)), steel, Vector3(-sin(a) * 0.45, cos(a) * 0.45, 0), Vector3(0, 0.35, a))
		MeshKit.part(fan, MeshKit.cyl(0.0, 0.26, 0.4, 10), steel, Vector3(0, 0, 0.15), Vector3(PI / 2, 0, 0))
		fans.append(fan)
		# Afterburner on a pivot so it scales from the nozzle.
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 0, 2.1)
		e.add_child(pivot)
		MeshKit.part(pivot, MeshKit.cyl(0.0, 0.85, 5.5, 12), flame, Vector3(0, 0, 2.5), Vector3(PI / 2, 0, 0))
		MeshKit.part(pivot, MeshKit.cyl(0.0, 0.38, 2.6, 10), core, Vector3(0, 0, 1.3), Vector3(PI / 2, 0, 0))
		burners.append(pivot)
	return {"burners": burners, "fans": fans}


## Two missiles under each wing. They hide as the magazine empties and reappear on reload.
static func _build_hardpoints(root: Node3D, steel: Material, white: Material, red: Material) -> Array[Node3D]:
	var missiles: Array[Node3D] = []
	for x in [4.0, 5.9]:
		for sx in [-1.0, 1.0]:
			MeshKit.part(root, MeshKit.box(Vector3(0.18, 0.35, 1.6)), steel, Vector3(x * sx, -0.42, 3.4 + x * 0.3))
			var m := Node3D.new()
			m.position = Vector3(x * sx, -0.78, 3.4 + x * 0.3)
			root.add_child(m)
			MeshKit.part(m, MeshKit.cyl(0.2, 0.2, 2.8, 8), white, Vector3.ZERO, Vector3(-PI / 2, 0, 0))
			MeshKit.part(m, MeshKit.cyl(0.0, 0.2, 0.6, 8), red, Vector3(0, 0, -1.7), Vector3(-PI / 2, 0, 0))
			MeshKit.part(m, MeshKit.box(Vector3(0.75, 0.05, 0.35)), red, Vector3(0, 0, 1.2))
			MeshKit.part(m, MeshKit.box(Vector3(0.05, 0.75, 0.35)), red, Vector3(0, 0, 1.2))
			missiles.append(m)
	return missiles


## Builds the imported airframe: both wing poses, cel-shaded paint, turbines and afterburners.
static func _build_imported(root: Node3D) -> Dictionary:
	# Cel-shaded paint per region (shaders/cel.gdshader). Glossy black gets the strongest
	# highlight and rim so the airframe reads like the show's inked cels.
	var palette := {
		"body": _cel(BLACK, Color(0.55, 0.55, 0.75), 0.85, 0.28),
		"cockpit": _cel(RED, Color(0.55, 0.3, 0.45), 0.7, 0.25),
		"engine": _cel(RED, Color(0.55, 0.3, 0.45), 0.7, 0.25),
		"stripe": _cel(BLUE, Color(0.5, 0.5, 0.75), 0.7, 0.3),
		"nozzle": _cel(Color(0.03, 0.03, 0.04), Color(0.6, 0.6, 0.7), 0.3, 0.1),
		"glass": _cel(GLASS, Color(0.5, 0.55, 0.85), 1.2, 0.4, 0.35),
		"outline": _ink(INK * 1.4),
	}

	var swept := _load_airframe(MODEL_SWEPT, palette)
	var open := _load_airframe(MODEL_OPEN, palette)
	root.add_child(swept)
	root.add_child(open)
	swept.visible = false

	var white := _paint(WHITE, 0.3, 0.35, 0.1)
	var steel := _paint(STEEL, 0.7, 0.3, 0.1)
	var burners: Array[Node3D] = []
	var fans: Array[Node3D] = []
	for p in NOZZLES:
		var e := _engine_face(root, p, NOZZLE_RADIUS, white, steel)
		burners.append(e.burner)
		fans.append(e.fan)

	# Nav lights on the open-wing tips (port red, starboard green).
	MeshKit.part(open, MeshKit.sphere(0.2, 6), MeshKit.glow(Color(1, 0.1, 0.1)), Vector3(-11.4, 0.1, 5.4))
	MeshKit.part(open, MeshKit.sphere(0.2, 6), MeshKit.glow(Color(0.1, 1, 0.3)), Vector3(11.4, 0.1, 5.4))

	return {
		"root": root,
		"burners": burners,
		"fans": fans,
		"missiles": [],
		"wings": {"open": open, "swept": swept},
		"wingtips": [Vector3(-7.8, 0.1, 7.6), Vector3(7.8, 0.1, 7.6)],
	}


## Instantiates one wing pose and swaps each region's material for the palette entry of the same name.
static func _load_airframe(path: String, palette: Dictionary) -> Node3D:
	var node := (load(path) as PackedScene).instantiate() as Node3D
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var mesh := (mi as MeshInstance3D).mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i)
			var key := mat.resource_name if mat else ""
			if not palette.has(key):
				key = str(mi.name).to_lower()
			if palette.has(key):
				(mi as MeshInstance3D).set_surface_override_material(i, palette[key])
	return node


## White turbine ring, spinning fan and afterburner flame set into an engine nozzle.
static func _engine_face(root: Node3D, pos: Vector3, r: float, white: Material, steel: Material) -> Dictionary:
	var e := Node3D.new()
	e.position = pos
	root.add_child(e)
	var ring := TorusMesh.new()
	ring.inner_radius = r * 0.72
	ring.outer_radius = r * 1.02
	ring.rings = 20
	ring.ring_segments = 6
	MeshKit.part(e, ring, white, Vector3(0, 0, -0.05), Vector3(PI / 2, 0, 0))
	MeshKit.part(e, MeshKit.cyl(r * 0.75, r * 0.75, 0.08, 16), MeshKit.toon(Color(0.02, 0.02, 0.03)), Vector3(0, 0, -0.25), Vector3(PI / 2, 0, 0))
	var fan := Node3D.new()
	fan.position = Vector3(0, 0, -0.15)
	e.add_child(fan)
	for k in 9:
		var a := TAU * k / 9.0
		MeshKit.part(fan, MeshKit.box(Vector3(0.12, r * 0.7, 0.03)), steel, Vector3(-sin(a), cos(a), 0) * r * 0.38, Vector3(0, 0.35, a))
	MeshKit.part(fan, MeshKit.cyl(0.0, r * 0.22, 0.35, 10), steel, Vector3(0, 0, 0.12), Vector3(PI / 2, 0, 0))
	var burner := Node3D.new()
	burner.position = Vector3(0, 0, 0.05)
	e.add_child(burner)
	MeshKit.part(burner, MeshKit.cyl(0.0, r * 0.8, 5.5, 12), MeshKit.glow(Color(1.0, 0.5, 0.18, 0.85), true), Vector3(0, 0, 2.75), Vector3(PI / 2, 0, 0))
	MeshKit.part(burner, MeshKit.cyl(0.0, r * 0.42, 2.6, 10), MeshKit.glow(Color(0.65, 0.85, 1.0, 0.9), true), Vector3(0, 0, 1.3), Vector3(PI / 2, 0, 0))
	return {"burner": burner, "fan": fan}
