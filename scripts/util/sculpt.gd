class_name Sculpt
extends RefCounted
## Smooth, cartoon-inked shapes for creatures (built in code, no art files).
##
## tube() sweeps an elliptical cross-section along a Catmull-Rom spline, with the radii easing
## smoothly between control points, so a whole body, neck or tail is one seamless surface with
## smooth normals. A paint callback colours each vertex (a pale belly, stripes...), and the
## cel() material shades it in hard light bands with a black ink outline, like the show's cels.
## inked_slab() gives thin flat parts (wings, crests) an outline too.

const CelShader := preload("res://shaders/cel.gdshader")


## A cel-shaded material that uses vertex colours, with an inverted-hull ink outline `ink` units thick.
static func cel(shadow := Color(0.6, 0.5, 0.62), ink := 0.05, gloss := 0.25, rim := 0.18) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = CelShader
	m.set_shader_parameter("use_vertex_color", true)
	m.set_shader_parameter("shadow_tint", shadow)
	m.set_shader_parameter("gloss_strength", gloss)
	m.set_shader_parameter("gloss", 24.0)
	m.set_shader_parameter("rim_strength", rim)
	m.set_shader_parameter("rim_color", Color(1.0, 0.95, 0.85))
	m.set_shader_parameter("highlight_band", 0.45)
	if ink > 0.0:
		var line := StandardMaterial3D.new()
		line.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		line.albedo_color = Color(0.04, 0.03, 0.05)
		line.cull_mode = BaseMaterial3D.CULL_FRONT
		line.grow = true
		line.grow_amount = ink
		m.next_pass = line
	return m


## Points along the spline: [{pos, tan, up, side, rx, ry, s (arc length)}], `n` samples.
## `radii` are Vector2(rx, ry) per control point: rx across (side), ry along `up` (the dorsal side).
## `up0` is the dorsal direction at the first point; it is carried along without twisting.
static func frames(pts: Array, radii: Array, n: int, up0 := Vector3.UP) -> Array:
	var out: Array = []
	var prev_up := up0
	var s := 0.0
	var last := Vector3.ZERO
	for i in n:
		var t := float(i) / float(n - 1) * float(pts.size() - 1)
		var k := mini(int(floor(t)), pts.size() - 2)
		var f := t - float(k)
		var pos := _cr(pts, k, f)
		var tan := (_cr(pts, k, minf(f + 0.01, 1.0)) - _cr(pts, k, maxf(f - 0.01, 0.0))).normalized()
		var r: Vector2 = _cr2(radii, k, f)
		var up := (prev_up - tan * prev_up.dot(tan))
		up = up.normalized() if up.length_squared() > 0.0001 else tan.cross(Vector3.RIGHT).normalized()
		var side := tan.cross(up).normalized()
		if i > 0:
			s += pos.distance_to(last)
		last = pos
		prev_up = up
		out.append({"pos": pos, "tan": tan, "up": up, "side": side, "rx": maxf(r.x, 0.0), "ry": maxf(r.y, 0.0), "s": s})
	return out


## A smooth tube along `pts` (Vector3) with `radii` (Vector2 per point). `paint(s, ang, fr)`
## returns the colour of each vertex: s = arc length, ang = angle round the section (PI/2 is the
## dorsal side, -PI/2 the belly). Open ends with a non-zero radius are capped.
static func tube(pts: Array, radii: Array, paint: Callable, rings := 40, segs := 18, up0 := Vector3.UP) -> ArrayMesh:
	var fr := frames(pts, radii, rings, up0)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring_pts: Array = []
	var ring_nrm: Array = []
	var ring_col: Array = []
	for f in fr:
		var ps := PackedVector3Array()
		var ns := PackedVector3Array()
		var cs := PackedColorArray()
		var rx: float = maxf(f.rx, 0.001)
		var ry: float = maxf(f.ry, 0.001)
		for j in segs:
			var a := TAU * float(j) / float(segs)
			ps.append(f.pos + f.side * cos(a) * f.rx + f.up * sin(a) * f.ry)
			ns.append((f.side * cos(a) / rx + f.up * sin(a) / ry).normalized())
			cs.append(paint.call(f.s, wrapf(a, -PI, PI), f))
		ring_pts.append(ps)
		ring_nrm.append(ns)
		ring_col.append(cs)
	for i in fr.size() - 1:
		for j in segs:
			var j2 := (j + 1) % segs
			_quad(st, ring_pts[i][j], ring_pts[i][j2], ring_pts[i + 1][j2], ring_pts[i + 1][j],
				ring_nrm[i][j], ring_nrm[i][j2], ring_nrm[i + 1][j2], ring_nrm[i + 1][j],
				ring_col[i][j], ring_col[i][j2], ring_col[i + 1][j2], ring_col[i + 1][j])
	for end in [0, fr.size() - 1]:
		var f: Dictionary = fr[end]
		if f.rx < 0.01 and f.ry < 0.01:
			continue
		var n: Vector3 = -f.tan if end == 0 else f.tan
		for j in segs:
			var j2 := (j + 1) % segs
			_tri(st, f.pos, ring_pts[end][j], ring_pts[end][j2], n, n, n, ring_col[end][j], ring_col[end][j], ring_col[end][j2])
	return st.commit()


## A flat part (wing membrane, crest, fin) with an ink rim: the coloured slab plus a slightly larger,
## thinner black slab behind it that only shows at the edges. Returns the coloured MeshInstance.
static func inked_slab(parent: Node3D, poly: PackedVector2Array, thickness: float, mat: Material, ink: float, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshKit.part(parent, MeshKit.slab(poly, thickness), mat, pos, rot)
	var grown := Geometry2D.offset_polygon(poly, ink, Geometry2D.JOIN_ROUND)
	if not grown.is_empty():
		var line := StandardMaterial3D.new()
		line.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		line.albedo_color = Color(0.04, 0.03, 0.05)
		MeshKit.part(parent, MeshKit.slab(grown[0], thickness * 0.55), line, pos, rot)
	return mi


static func _cr(p: Array, k: int, f: float) -> Vector3:
	var p0: Vector3 = p[maxi(k - 1, 0)]
	var p1: Vector3 = p[k]
	var p2: Vector3 = p[mini(k + 1, p.size() - 1)]
	var p3: Vector3 = p[mini(k + 2, p.size() - 1)]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f * f + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f * f * f)


static func _cr2(p: Array, k: int, f: float) -> Vector2:
	var a: Vector2 = p[maxi(k - 1, 0)]
	var b: Vector2 = p[k]
	var c: Vector2 = p[mini(k + 1, p.size() - 1)]
	var d: Vector2 = p[mini(k + 2, p.size() - 1)]
	var r := 0.5 * ((2.0 * b) + (-a + c) * f + (2.0 * a - 5.0 * b + 4.0 * c - d) * f * f + (-a + 3.0 * b - 3.0 * c + d) * f * f * f)
	return Vector2(maxf(r.x, 0.0), maxf(r.y, 0.0))


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, na: Vector3, nb: Vector3, nc: Vector3, nd: Vector3, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	_tri(st, a, b, c, na, nb, nc, ca, cb, cc)
	_tri(st, a, c, d, na, nc, nd, ca, cc, cd)


## Adds a triangle with per-vertex normals and colours, wound so its front faces along the normals
## (Godot treats clockwise as front).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, na: Vector3, nb: Vector3, nc: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	var face := (b - a).cross(c - a)
	if face.length_squared() < 1e-12:
		return
	var flip := face.dot(na + nb + nc) > 0.0
	var vs := [[a, na, ca], [c, nc, cc], [b, nb, cb]] if flip else [[a, na, ca], [b, nb, cb], [c, nc, cc]]
	for v in vs:
		st.set_normal(v[1])
		st.set_color(v[2])
		st.add_vertex(v[0])
