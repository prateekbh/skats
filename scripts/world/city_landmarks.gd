class_name CityLandmarks
extends RefCounted
## The hand-built places of Megakat City, from the environment handoff (proportions are the
## handoff's proposed values; the 300-storey MegaKat Tower is the one canonical anchor):
## MegaKat Tower (~1,200 m), City Hall with a working clock (~250 m), Enforcer Headquarters
## (~300 m), Jake & Chance's Garage in the salvage yard (the hidden hangar below), the docks
## (piers, gantry cranes, ships, container stacks), three bridges, the dam, a lighthouse and a
## park pavilion. Geometry is generated; check silhouettes against series frames before polishing.

const S := CityBuildings.S
const M := CityBuildings.M
const G := CityPlan.LAND

var city: City
var b: CityBuildings
var gold: StandardMaterial3D


static func build(c: City) -> void:
	var lm := CityLandmarks.new()
	lm.city = c
	lm.b = c.buildings
	lm.gold = MeshKit.toon(Color(0.95, 0.72, 0.25), 0.7, 0.3)
	lm.gold.emission_enabled = true
	lm.gold.emission = Color(0.9, 0.6, 0.15)
	lm.gold.emission_energy_multiplier = 0.35
	lm._tower(c.tower_pos)
	lm._city_hall(c.city_hall_pos)
	lm._enforcer_hq(c.enforcer_hq_pos)
	lm._yard(c.salvage_yard_pos)
	lm._docks()
	lm._bridges()
	lm._extras()


# --- helpers -------------------------------------------------------------------------

func _wall(style: int, color: Color, height: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CityBuildings.BuildingShader
	m.set_shader_parameter("use_uniforms", true)
	m.set_shader_parameter("u_style", float(style))
	m.set_shader_parameter("u_color", color)
	m.set_shader_parameter("u_seed", 0.37)
	m.set_shader_parameter("u_height", height)
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshKit.part(parent, MeshKit.box(size), mat, pos, rot)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A square frustum (four-sided, faces aligned to the axes): widths in metres at bottom and top.
func _frustum(parent: Node3D, bottom_w: float, top_w: float, h: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshKit.part(parent, MeshKit.cyl(top_w * 0.70711, bottom_w * 0.70711, h, 4), mat, pos, Vector3(0, PI * 0.25, 0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _node(pos: Vector3, name: String) -> Node3D:
	var n := Node3D.new()
	n.name = name
	n.position = pos
	city.add_child(n)
	return n


# --- MegaKat Tower ---------------------------------------------------------------------

func _tower(at: Vector3) -> void:
	var root := _node(at, "MegaKatTower")
	var glass := _wall(S.GLASS, Color(0.1, 0.2, 0.5), 1050.0)
	var sections := [[120.0, 102.0, 0.0, 420.0], [102.0, 82.0, 420.0, 840.0], [82.0, 62.0, 840.0, 1050.0]]
	for s in sections:
		var h: float = s[3] - s[2]
		_frustum(root, s[0], s[1], h, Vector3(0, G + s[2] + h * 0.5, 0), glass)
		_box(root, Vector3(s[1] * 1.07, 7.0, s[1] * 1.07), Vector3(0, G + s[3], 0), gold)
		b.add_fixed(at.x, at.z, s[0], s[0], G + s[3])
	# The crown: a gold frustum with four fins around a tall spire.
	_frustum(root, 62.0, 30.0, 80.0, Vector3(0, G + 1090.0, 0), gold)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_box(root, Vector3(5.0, 80.0, 5.0), Vector3(sx * 26.0, G + 1125.0, sz * 26.0), gold)
	MeshKit.part(root, MeshKit.cyl(0.6, 4.0, 110.0, 4), gold, Vector3(0, G + 1185.0, 0), Vector3(0, PI * 0.25, 0))
	MeshKit.part(root, MeshKit.sphere(3.0, 8), MeshKit.glow(Color(1.0, 0.15, 0.1)), Vector3(0, G + 1243.0, 0))
	b.add_fixed(at.x, at.z, 34.0, 34.0, G + 1240.0)


# --- City Hall -------------------------------------------------------------------------

func _clock_texture() -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var c := Vector2(n * 0.5, n * 0.5)
	var dark := Color(0.12, 0.1, 0.08)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var col := Color(0, 0, 0, 0)
			if d < 124.0:
				col = dark if d > 112.0 else Color(0.97, 0.94, 0.84)
			img.set_pixel(x, y, col)
	for k in 12:
		var a := TAU * k / 12.0
		var p := c + Vector2(sin(a), -cos(a)) * 96.0
		var r := 7 if k % 3 == 0 else 4
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				img.set_pixel(clampi(int(p.x) + dx, 0, n - 1), clampi(int(p.y) + dy, 0, n - 1), dark)
	return ImageTexture.create_from_image(img)


func _city_hall(at: Vector3) -> void:
	var root := _node(at, "CityHall")
	var stone := _wall(S.CIVIC, Color(0.76, 0.68, 0.54), 120.0)
	var copper := MeshKit.toon(Color(0.28, 0.5, 0.44), 0.4, 0.5)
	# Podium, wings and the stepped centre block.
	_box(root, Vector3(120, 30, 78), Vector3(0, G + 15, 0), stone)
	b.add_fixed(at.x, at.z, 120.0, 78.0, G + 30.0)
	for sx: float in [-1.0, 1.0]:
		_box(root, Vector3(30, 64, 50), Vector3(sx * 50.0, G + 62, -6), stone)
		_box(root, Vector3(20, 18, 36), Vector3(sx * 50.0, G + 103, -6), stone)
		b.add_fixed(at.x + sx * 50.0, at.z - 6.0, 30.0, 50.0, G + 112.0)
	_box(root, Vector3(86, 56, 56), Vector3(0, G + 58, -4), stone)
	_box(root, Vector3(62, 30, 44), Vector3(0, G + 101, -4), stone)
	b.add_fixed(at.x, at.z - 4.0, 86.0, 56.0, G + 116.0)
	# Clock tower, copper cap and finial.
	_box(root, Vector3(34, 100, 34), Vector3(0, G + 166, -4), stone)
	_frustum(root, 34.0, 4.0, 30.0, Vector3(0, G + 231, -4), copper)
	MeshKit.part(root, MeshKit.cyl(0.4, 1.2, 20.0, 6), gold, Vector3(0, G + 256, -4))
	b.add_fixed(at.x, at.z - 4.0, 34.0, 34.0, G + 262.0)
	# Entrance: steps and a colonnade.
	_box(root, Vector3(64, 3, 10), Vector3(0, G + 1.5, 44), stone)
	for i in 8:
		_box(root, Vector3(3, 26, 3), Vector3(-28.0 + i * 8.0, G + 16, 41), stone)
	_box(root, Vector3(70, 4, 8), Vector3(0, G + 31, 41), stone)
	# Four clock faces with moving hands.
	var tex := _clock_texture()
	var face_mat := StandardMaterial3D.new()
	face_mat.albedo_texture = tex
	face_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var hand_mat := MeshKit.toon(Color(0.08, 0.07, 0.06), 0.0, 0.8)
	for f in 4:
		var face := Node3D.new()
		root.add_child(face)
		face.position = Vector3(0, G + 190, -4)
		face.rotation.y = f * PI * 0.5
		var quad := QuadMesh.new()
		quad.size = Vector2(26, 26)
		var qi := MeshInstance3D.new()
		qi.mesh = quad
		qi.material_override = face_mat
		qi.position = Vector3(0, 0, 17.4)
		qi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		face.add_child(qi)
		MeshKit.part(face, MeshKit.box(Vector3(29, 29, 1.0)), gold, Vector3(0, 0, 17.0))
		for hand in [[1.6, 7.5, 0.4], [1.0, 10.5, 0.8]]:
			var pivot := Node3D.new()
			pivot.position = Vector3(0, 0, 17.5 + hand[2])
			face.add_child(pivot)
			MeshKit.part(pivot, MeshKit.box(Vector3(hand[0], hand[1], 0.4)), hand_mat, Vector3(0, hand[1] * 0.4, 0))
			city.clock_hands.append(pivot)


# --- Enforcer Headquarters -------------------------------------------------------------

func _shield_texture() -> ImageTexture:
	var w := 128
	var h := 160
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var blue := Color(0.1, 0.22, 0.6)
	var edge := Color(0.95, 0.72, 0.25)
	for y in h:
		for x in w:
			var u := (x + 0.5 - w * 0.5) / (w * 0.5)
			var v := (y + 0.5) / h
			var half := 1.0 if v < 0.55 else sqrt(maxf(0.0, 1.0 - pow((v - 0.55) / 0.45, 2.0)))
			var col := Color(0, 0, 0, 0)
			if absf(u) <= half and v < 1.0:
				col = edge if (absf(u) > half - 0.12 or v < 0.06 or (v > 0.98)) else blue
				var q := Vector2(u, (v - 0.45) * 1.25)
				var a := atan2(q.y, q.x)
				if q.length() <= 0.34 * (0.45 + 0.55 * absf(cos(2.5 * a))):
					col = edge
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


func _enforcer_hq(at: Vector3) -> void:
	var root := _node(at, "EnforcerHQ")
	var stone := _wall(S.CIVIC, Color(0.5, 0.46, 0.41), 100.0)
	var slate := MeshKit.toon(Color(0.22, 0.26, 0.32), 0.3, 0.6)
	_box(root, Vector3(130, 60, 110), Vector3(0, G + 30, 0), stone)
	b.add_fixed(at.x, at.z, 130.0, 110.0, G + 60.0)
	_box(root, Vector3(112, 36, 94), Vector3(0, G + 78, 0), stone)
	b.add_fixed(at.x, at.z, 112.0, 94.0, G + 96.0)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := Vector3(sx * 50.0, 0.0, sz * 38.0)
			_box(root, Vector3(24, 150, 24), Vector3(p.x, G + 75, p.z), stone)
			_frustum(root, 26.0, 2.0, 28.0, Vector3(p.x, G + 164, p.z), slate)
			b.add_fixed(at.x + p.x, at.z + p.z, 24.0, 24.0, G + 178.0)
	_box(root, Vector3(66, 80, 58), Vector3(0, G + 136, 0), stone)
	_box(root, Vector3(46, 54, 40), Vector3(0, G + 203, 0), stone)
	_frustum(root, 30.0, 14.0, 26.0, Vector3(0, G + 243, 0), slate)
	MeshKit.part(root, MeshKit.cyl(0.5, 4.0, 40.0, 4), slate, Vector3(0, G + 276, 0), Vector3(0, PI * 0.25, 0))
	b.add_fixed(at.x, at.z, 66.0, 58.0, G + 176.0)
	b.add_fixed(at.x, at.z, 46.0, 40.0, G + 230.0)
	b.add_fixed(at.x, at.z, 26.0, 26.0, G + 296.0)
	for y in [60.0, 96.0, 176.0]:
		_box(root, Vector3(70, 3, 62), Vector3(0, G + y, 0), gold)
	# The shield emblem on the face that looks towards downtown (+x).
	var em := StandardMaterial3D.new()
	em.albedo_texture = _shield_texture()
	em.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	em.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	var quad := QuadMesh.new()
	quad.size = Vector2(34, 42)
	var qi := MeshInstance3D.new()
	qi.mesh = quad
	qi.material_override = em
	qi.position = Vector3(33.6, G + 128, 0)
	qi.rotation.y = PI * 0.5
	qi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(qi)


# --- salvage yard: Jake & Chance's Garage and the hidden hangar ---------------------------

func _yard(at: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(city.plan.data.get("seed", 1993)) + 1
	var rust := [Color(0.45, 0.27, 0.16), Color(0.35, 0.33, 0.3), Color(0.5, 0.42, 0.2), Color(0.28, 0.3, 0.36)]
	var yard := Node3D.new()
	yard.name = "SalvageYard"
	yard.position = Vector3(at.x, G, at.z)
	city.add_child(yard)
	MeshKit.part(yard, MeshKit.box(Vector3(260, 0.6, 220)), MeshKit.toon(Color(0.24, 0.2, 0.16), 0.0, 1.0), Vector3(0, 0.3, 0))
	for n in 70:
		var p := Vector3(rng.randf_range(-120, 120), 0, rng.randf_range(-100, 100))
		if absf(p.x) < 28 and absf(p.z) < 28:
			continue # keep the hangar hatch clear
		if p.x > 40.0 and p.x < 90.0 and p.z > 15.0 and p.z < 55.0:
			continue # and the garage
		var s := Vector3(rng.randf_range(4, 9), rng.randf_range(2, 4), rng.randf_range(8, 14))
		p.y = s.y * 0.5 + rng.randf_range(0.0, 6.0)
		MeshKit.part(yard, MeshKit.box(s), MeshKit.toon(rust[n % rust.size()], 0.3, 0.8), p, Vector3(rng.randf_range(-0.3, 0.3), rng.randf(), rng.randf_range(-0.3, 0.3)))
	# Hangar hatch with hazard edge.
	MeshKit.part(yard, MeshKit.box(Vector3(46, 0.8, 46)), MeshKit.toon(Color(0.95, 0.75, 0.1)), Vector3(0, 0.7, 0))
	# The shaft below shows as a black pit once the doors slide apart.
	MeshKit.part(yard, MeshKit.box(Vector3(40, 0.1, 40)), MeshKit.glow(Color(0.01, 0.01, 0.015)), Vector3(0, 1.16, 0))
	for sx: float in [-1.0, 1.0]:
		var door := MeshKit.part(yard, MeshKit.box(Vector3(20, 1.0, 40)), MeshKit.toon(Color(0.12, 0.12, 0.14)), Vector3(10.0 * sx, 1.4, 0))
		MeshKit.part(door, MeshKit.box(Vector3(2.0, 0.1, 40)), MeshKit.toon(Color(0.95, 0.75, 0.1)), Vector3(-9.0 * sx, 0.52, 0))
		city.hatch_doors.append(door)
	# The tow-truck crane.
	MeshKit.part(yard, MeshKit.box(Vector3(3, 60, 3)), MeshKit.toon(Color(0.8, 0.55, 0.1)), Vector3(70, 30, -60))
	MeshKit.part(yard, MeshKit.box(Vector3(60, 3, 3)), MeshKit.toon(Color(0.8, 0.55, 0.1)), Vector3(48, 60, -60))
	# Jake & Chance's Garage: a modest two-storey auto shop, garage door below, apartment and an
	# improvised balcony above (about 15 m wide, 10 m high).
	var garage := Node3D.new()
	garage.position = Vector3(64, 0, 34)
	yard.add_child(garage)
	var stucco := _wall(S.HOUSE, Color(0.82, 0.66, 0.42), 10.0)
	_box(garage, Vector3(16, 10, 12), Vector3(0, 5, 0), stucco)
	_box(garage, Vector3(17, 0.8, 13), Vector3(0, 10.4, 0), MeshKit.toon(Color(0.4, 0.26, 0.2), 0.0, 0.9))
	_box(garage, Vector3(8.5, 4.2, 0.4), Vector3(-2.5, 2.2, 6.1), MeshKit.toon(Color(0.12, 0.12, 0.14), 0.3, 0.6))
	_box(garage, Vector3(7.0, 1.4, 0.4), Vector3(-2.5, 5.4, 6.2), MeshKit.glow(Color(0.9, 0.2, 0.15)))
	_box(garage, Vector3(8.0, 0.4, 2.8), Vector3(3.0, 5.1, 7.4), MeshKit.toon(Color(0.45, 0.3, 0.2), 0.0, 0.9))
	for i in 5:
		_box(garage, Vector3(0.25, 1.2, 0.25), Vector3(-0.6 + i * 1.9, 5.8, 8.7), MeshKit.toon(Color(0.35, 0.3, 0.28), 0.5, 0.6))
	_box(garage, Vector3(2.2, 2.2, 0.4), Vector3(3.5, 7.6, 6.1), MeshKit.glow(Color(1.0, 0.8, 0.45)))
	b.add_fixed(at.x + 64.0, at.z + 34.0, 17.0, 13.0, G + 11.0)


# --- docks ---------------------------------------------------------------------------

func _docks() -> void:
	var piers: Dictionary = city.plan.data.get("piers", {})
	var dir := deg_to_rad(float(piers.get("dir", 127)))
	var dv := Vector2(cos(dir), sin(dir))
	var lateral := Vector2(-sin(dir), cos(dir))
	var pw := float(piers.get("w", 70))
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var concrete := Color(0.48, 0.47, 0.44)
	var crane_cols := [Color(0.85, 0.55, 0.1), Color(0.75, 0.2, 0.15), Color(0.2, 0.45, 0.7)]
	var n := 0
	for p: Array in piers.get("list", []):
		var start := CityPlan.pt(p)
		var length := float(p[2])
		var mid := start + dv * length * 0.5
		var id := b.begin(mid.x, mid.y, CityPlan.K.INDUSTRIAL, CityBuildings.FIXED)
		b.part(id, M.BOX, mid.x, 0.0, mid.y, length, 3.0, pw, S.LOT, concrete, false, -dir)
		# Gantry cranes straddling the pier.
		for t: float in [0.45, 0.75]:
			var c := start + dv * length * t
			var col: Color = crane_cols[rng.randi() % crane_cols.size()]
			for side: float in [-1.0, 1.0]:
				var leg := c + lateral * side * 26.0
				b.part(id, M.BOX, leg.x, 3.0, leg.y, 3.5, 46.0, 3.5, S.METAL, col, false, -dir)
			b.part(id, M.BOX, c.x, 49.0, c.y, 6.0, 5.0, 60.0, S.METAL, col, false, -dir, false)
			var boom := c + dv * 26.0
			b.part(id, M.BOX, boom.x, 56.0, boom.y, 46.0, 3.0, 4.0, S.METAL, col.lightened(0.1), false, -dir, false)
			b.part(id, M.BOX, c.x, 44.0, c.y, 5.0, 4.0, 5.0, S.METAL, Color(0.3, 0.3, 0.32), false, -dir, false)
		# A block of containers at the landward end of the pier.
		var yard_c := start + dv * 60.0
		b.raster_box(yard_c.x, yard_c.y, 34.0, 56.0, G + 9.0, -dir, id)
		for ix in 2:
			for iz in 4:
				var q := yard_c + dv * (-8.0 + ix * 16.0) + lateral * (-24.0 + iz * 16.0)
				var stack := rng.randi_range(1, 3)
				var ccol: Color = CityBuildings.CONTAINER_COLS[rng.randi() % CityBuildings.CONTAINER_COLS.size()]
				for s in stack:
					b.part(id, M.BOX, q.x, 3.0 + s * 2.7, q.y, 12.2, 2.6, 2.6, S.CONTAINER, ccol, false, -dir, false)
		b.end(id)
		# A ship berthed alongside every other pier.
		if n % 2 == 0:
			var sc := start + dv * length * 0.6 + lateral * (pw * 0.5 + 18.0)
			var sid := b.begin(sc.x, sc.y, CityPlan.K.INDUSTRIAL, CityBuildings.FIXED)
			b.part(sid, M.BOX, sc.x, -3.0, sc.y, 130.0, 15.0, 24.0, S.METAL, Color(0.14, 0.17, 0.24), false, -dir)
			b.part(sid, M.BOX, sc.x, 11.5, sc.y, 130.0, 2.0, 25.0, S.METAL, Color(0.75, 0.2, 0.15), false, -dir, false)
			var sup := sc - dv * 46.0
			b.part(sid, M.BOX, sup.x, 12.0, sup.y, 24.0, 18.0, 20.0, S.CONCRETE, Color(0.85, 0.85, 0.82), false, -dir)
			b.part(sid, M.CYL, sup.x, 30.0, sup.y, 7.0, 10.0, 7.0, S.METAL, Color(0.8, 0.25, 0.15), false, -dir, false)
			b.end(sid)
		n += 1


# --- bridges, dam, lighthouse, pavilion -----------------------------------------------

func _bridges() -> void:
	var orange := Color(0.82, 0.36, 0.14)
	for br: Array in city.plan.data.get("bridges", []):
		var a := CityPlan.pt([br[0], br[1]])
		var e := CityPlan.pt([br[2], br[3]])
		var span := e - a
		var length := span.length()
		var yaw := -atan2(span.y, span.x)
		var mid := (a + e) * 0.5
		var id := b.begin(mid.x, mid.y, CityPlan.K.CLEAR, CityBuildings.FIXED)
		# The deck is not solid in the collision grid, so the river stays a flight corridor.
		b.part(id, M.BOX, mid.x, 34.0, mid.y, length, 3.5, 36.0, S.METAL, orange, false, yaw, false)
		var dir := span / length
		var lat := Vector2(-dir.y, dir.x)
		for rail: float in [-1.0, 1.0]:
			var rp := mid + lat * rail * 17.5
			b.part(id, M.BOX, rp.x, 37.5, rp.y, length, 1.6, 0.8, S.METAL, orange.darkened(0.2), false, yaw, false)
		for t: float in [0.25, 0.75]:
			var pp := a + span * t
			for side: float in [-1.0, 1.0]:
				var tp := pp + lat * side * 15.0
				b.part(id, M.BOX, tp.x, 0.0, tp.y, 7.0, 112.0, 7.0, S.METAL, orange, false, yaw)
			b.part(id, M.BOX, pp.x, 100.0, pp.y, 9.0, 8.0, 40.0, S.METAL, orange, false, yaw, false)
		b.end(id)


func _extras() -> void:
	var lm: Dictionary = city.plan.data.landmarks
	# The dam across the north end of the east river.
	var dam: Dictionary = lm.dam
	var dc := CityPlan.pt(dam.c)
	var len := float(dam.len)
	var id := b.begin(dc.x, dc.y, CityPlan.K.CLEAR, CityBuildings.FIXED)
	b.part(id, M.BOX, dc.x, -6.0, dc.y, len, 56.0, 40.0, S.CONCRETE, Color(0.62, 0.62, 0.6))
	b.part(id, M.BOX, dc.x, 50.0, dc.y, len, 2.0, 46.0, S.METAL, Color(0.5, 0.5, 0.52), false, 0.0, false)
	b.end(id)
	# Lighthouse on its island.
	var lp := CityPlan.pt(lm.lighthouse)
	id = b.begin(lp.x, lp.y, CityPlan.K.CLEAR, CityBuildings.FIXED)
	b.part(id, M.CYL, lp.x, G, lp.y, 11.0, 40.0, 11.0, S.CONCRETE, Color(0.9, 0.88, 0.84), true)
	b.part(id, M.CYL, lp.x, G + 40.0, lp.y, 15.0, 3.0, 15.0, S.METAL, Color(0.75, 0.2, 0.15), false)
	b.part(id, M.CYL, lp.x, G + 43.0, lp.y, 8.0, 6.0, 8.0, S.NEON, Color(1.0, 0.9, 0.5), false, 0.0, false)
	b.part(id, M.CONE, lp.x, G + 49.0, lp.y, 11.0, 8.0, 11.0, S.METAL, Color(0.75, 0.2, 0.15), false, 0.0, false)
	b.end(id)
	# The park pavilion: a stone drum under a glass dome.
	var pp := CityPlan.pt(lm.pavilion)
	var pav := _node(Vector3(pp.x, G, pp.y), "ParkPavilion")
	MeshKit.part(pav, MeshKit.cyl(15.0, 16.0, 12.0, 20), MeshKit.toon(Color(0.78, 0.72, 0.6), 0.0, 0.8), Vector3(0, 6.0, 0))
	var dome := MeshKit.part(pav, MeshKit.sphere(15.0, 20), MeshKit.glass(Color(0.4, 0.7, 0.8)), Vector3(0, 12.0, 0))
	dome.scale = Vector3(1.0, 0.8, 1.0)
	b.add_fixed(pp.x, pp.y, 32.0, 32.0, G + 24.0, 0.0, true)
