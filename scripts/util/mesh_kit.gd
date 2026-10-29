class_name MeshKit
extends RefCounted
## Helpers for building cel-shaded models out of primitives in code.

static var _soft_dot: Texture2D


## Cel-shaded material (toon diffuse + toon specular).
static func toon(color: Color, metallic := 0.2, roughness := 0.55) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
	m.specular_mode = BaseMaterial3D.SPECULAR_TOON
	return m


## Unshaded glowing material; additive when `add` is true.
static func glow(color: Color, add := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if add:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## Glass with a faint emissive tint.
static func glass(color: Color) -> StandardMaterial3D:
	var m := toon(color, 0.6, 0.1)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.35
	return m


static func part(parent: Node3D, mesh: Mesh, material: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


## Cylinder along Y. Use rot.x = -PI/2 to point the top toward -Z (forward).
static func cyl(top: float, bottom: float, height: float, segments := 12) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func sphere(radius: float, segments := 14) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = maxi(segments / 2, 4)
	return m


## A flat polygon (given in the XZ plane as Vector2(x, z)) extruded along Y.
## Used for wings, fins and canards.
static func slab(points: PackedVector2Array, thickness: float) -> ArrayMesh:
	var tris := Geometry2D.triangulate_polygon(points)
	var h := thickness * 0.5
	var centroid := Vector2.ZERO
	for p in points:
		centroid += p
	centroid /= points.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0, tris.size(), 3):
		var a := points[tris[i]]
		var b := points[tris[i + 1]]
		var c := points[tris[i + 2]]
		_tri(st, Vector3(a.x, h, a.y), Vector3(b.x, h, b.y), Vector3(c.x, h, c.y), Vector3.UP)
		_tri(st, Vector3(a.x, -h, a.y), Vector3(b.x, -h, b.y), Vector3(c.x, -h, c.y), Vector3.DOWN)
	for i in points.size():
		var p0 := points[i]
		var p1 := points[(i + 1) % points.size()]
		var e := p1 - p0
		var n2 := Vector2(e.y, -e.x).normalized()
		if n2.dot((p0 + p1) * 0.5 - centroid) < 0.0:
			n2 = -n2
		var n := Vector3(n2.x, 0.0, n2.y)
		var v00 := Vector3(p0.x, -h, p0.y)
		var v01 := Vector3(p0.x, h, p0.y)
		var v10 := Vector3(p1.x, -h, p1.y)
		var v11 := Vector3(p1.x, h, p1.y)
		_tri(st, v00, v01, v11, n)
		_tri(st, v00, v11, v10, n)
	return st.commit()


## Lofts closed cross-sections into a faceted, flat-shaded hull.
## `sections` are polygons of Vector2(x, y) with equal point counts, placed at the matching `zs`.
## Ends are capped. This gives the hard-edged look of a cartoon stealth jet.
static func loft(sections: Array, zs: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in sections.size() - 1:
		var a: PackedVector2Array = sections[k]
		var b: PackedVector2Array = sections[k + 1]
		var za: float = zs[k]
		var zb: float = zs[k + 1]
		var axis := Vector3(0.0, (_avg_y(a) + _avg_y(b)) * 0.5, (za + zb) * 0.5)
		for i in a.size():
			var j := (i + 1) % a.size()
			var p0 := Vector3(a[i].x, a[i].y, za)
			var p1 := Vector3(a[j].x, a[j].y, za)
			var q0 := Vector3(b[i].x, b[i].y, zb)
			var q1 := Vector3(b[j].x, b[j].y, zb)
			# Cross of the diagonals stays valid even when one edge collapses to a point.
			var n := (q1 - p0).cross(q0 - p1)
			if n.length_squared() < 0.0000001:
				continue
			n = n.normalized()
			if n.dot((p0 + p1 + q0 + q1) * 0.25 - axis) < 0.0:
				n = -n
			_tri(st, p0, p1, q1, n)
			_tri(st, p0, q1, q0, n)
	_cap(st, sections[0], zs[0], Vector3.FORWARD)
	_cap(st, sections[sections.size() - 1], zs[zs.size() - 1], Vector3.BACK)
	return st.commit()


static func _avg_y(poly: PackedVector2Array) -> float:
	var y := 0.0
	for p in poly:
		y += p.y
	return y / poly.size()


static func _cap(st: SurfaceTool, poly: PackedVector2Array, z: float, normal: Vector3) -> void:
	var tris := Geometry2D.triangulate_polygon(poly)
	for i in range(0, tris.size(), 3):
		var a := poly[tris[i]]
		var b := poly[tris[i + 1]]
		var c := poly[tris[i + 2]]
		_tri(st, Vector3(a.x, a.y, z), Vector3(b.x, b.y, z), Vector3(c.x, c.y, z), normal)


## Adds a black inverted-hull outline pass to a material (cartoon ink lines).
static func outlined(m: BaseMaterial3D, thickness := 0.05) -> BaseMaterial3D:
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color(0.0, 0.0, 0.0)
	ink.cull_mode = BaseMaterial3D.CULL_FRONT
	ink.grow = true
	ink.grow_amount = thickness
	m.next_pass = ink
	return m


## Adds a triangle wound so its front face matches `normal` (Godot treats clockwise as front).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	if (b - a).cross(c - a).dot(normal) > 0.0:
		var tmp := b
		b = c
		c = tmp
	for v in [a, b, c]:
		st.set_normal(normal)
		st.add_vertex(v)


## Soft round sprite used by every particle effect.
static func soft_dot() -> Texture2D:
	if _soft_dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 64
		t.height = 64
		_soft_dot = t
	return _soft_dot


## Billboard particle material. `additive` for fire and sparks, alpha blend for smoke.
static func particle_material(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = soft_dot()
	m.disable_receive_shadows = true
	return m
