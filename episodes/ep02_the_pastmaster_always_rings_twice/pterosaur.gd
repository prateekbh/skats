class_name Pterosaur
extends Node3D
## A pterosaur, from the show's reference frames: slim tan body with a cream belly, a long
## crested head, a short pointed tail and big cream wings on a bent tan arm. Nose points to -Z.
## `big` makes the larger kind (wave 2). The wings flap in _process.

const TAN := Color(0.86, 0.62, 0.34)
const CREAM := Color(0.93, 0.88, 0.72)
const DARK_TAN := Color(0.7, 0.46, 0.22)

var big := false
var flap_speed := 5.0
var _wings: Array[Node3D] = []
var _phase := randf() * TAU


func _ready() -> void:
	_build()


func _build() -> void:
	var root := Node3D.new()
	add_child(root)
	root.scale = Vector3.ONE * (2.2 if big else 1.0)
	var tan := MeshKit.toon(TAN, 0.1, 0.65)
	var cream := MeshKit.toon(CREAM, 0.05, 0.7)
	var dark := MeshKit.toon(DARK_TAN, 0.1, 0.65)
	var ink := MeshKit.toon(Color(0.08, 0.06, 0.05), 0.0, 0.8)
	# Body and belly.
	MeshKit.part(root, MeshKit.sphere(1.0, 14), tan, Vector3(0, 0.1, 0.4), Vector3.ZERO, Vector3(0.95, 0.8, 2.9))
	MeshKit.part(root, MeshKit.sphere(1.0, 12), cream, Vector3(0, -0.3, 0.3), Vector3.ZERO, Vector3(0.8, 0.5, 2.6))
	# Neck rising to the head, the long beak and the backward crest.
	MeshKit.part(root, MeshKit.cyl(0.32, 0.55, 2.4, 10), tan, Vector3(0, 0.8, -2.5), Vector3(-1.05, 0, 0))
	MeshKit.part(root, MeshKit.sphere(0.55, 10), tan, Vector3(0, 1.75, -3.6), Vector3.ZERO, Vector3(0.85, 0.8, 1.3))
	MeshKit.part(root, MeshKit.cyl(0.04, 0.34, 3.4, 8), tan, Vector3(0, 1.62, -5.5), Vector3(-PI / 2 + 0.06, 0, 0))
	MeshKit.part(root, MeshKit.cyl(0.03, 0.22, 3.0, 8), cream, Vector3(0, 1.32, -5.3), Vector3(-PI / 2 + 0.06, 0, 0))
	var crest := PackedVector2Array([Vector2(0, -0.2), Vector2(0.55, 0.6), Vector2(0.45, 2.3), Vector2(0.08, 1.2)])
	MeshKit.part(root, MeshKit.slab(crest, 0.12), dark, Vector3(1.95, 0.0, -3.4), Vector3(0, 0, PI / 2)) # crest: a thin vertical plate
	for sx in [-1.0, 1.0]:
		MeshKit.part(root, MeshKit.sphere(0.1, 6), ink, Vector3(0.38 * sx, 1.9, -4.0)) # eyes
	# Tail with a small vane, and the clawed feet trailing under the body.
	MeshKit.part(root, MeshKit.cyl(0.03, 0.2, 3.2, 8), tan, Vector3(0, 0.0, 3.9), Vector3(PI / 2, 0, 0))
	var vane := PackedVector2Array([Vector2(0, 0), Vector2(0.45, 0.6), Vector2(0, 1.2), Vector2(-0.45, 0.6)])
	MeshKit.part(root, MeshKit.slab(vane, 0.08), dark, Vector3(0, 0.0, 5.4))
	for sx in [-0.5, 0.5]:
		MeshKit.part(root, MeshKit.cyl(0.06, 0.12, 1.3, 6), dark, Vector3(sx, -0.55, 2.4), Vector3(PI / 2 - 0.4, 0, 0))
		for k in 3:
			MeshKit.part(root, MeshKit.cyl(0.0, 0.05, 0.4, 5), ink, Vector3(sx + (k - 1) * 0.12, -0.7, 3.2), Vector3(PI / 2 - 0.8, 0, 0))
	# Wings: a cream membrane on a bent tan arm, pivoting at the shoulder so they can flap.
	var membrane := PackedVector2Array([Vector2(0, -1.0), Vector2(4.5, -2.0), Vector2(10.0, 1.0), Vector2(9.5, 1.6), Vector2(6.5, 1.2), Vector2(3.5, 2.2), Vector2(0.4, 2.6)])
	var arm := PackedVector2Array([Vector2(0, -1.0), Vector2(4.5, -2.0), Vector2(10.0, 1.0), Vector2(9.7, 1.4), Vector2(4.4, -1.5), Vector2(0, -0.4)])
	for sx in [1.0, -1.0]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.5 * sx, 0.45, -0.6)
		root.add_child(pivot)
		MeshKit.part(pivot, MeshKit.slab(_side(membrane, sx), 0.1), cream, Vector3(0, -0.02, 0))
		MeshKit.part(pivot, MeshKit.slab(_side(arm, sx), 0.2), tan, Vector3(0, 0.05, 0))
		_wings.append(pivot)


## The right-hand polygon as is, or mirrored (x negated, order reversed to keep the winding) for the left wing.
func _side(poly: PackedVector2Array, sx: float) -> PackedVector2Array:
	if sx > 0.0:
		return poly
	var out := PackedVector2Array()
	for i in range(poly.size() - 1, -1, -1):
		out.append(Vector2(-poly[i].x, poly[i].y))
	return out


func _process(delta: float) -> void:
	_phase += delta * flap_speed
	var a := sin(_phase) * 0.42 + 0.12 # flap up and down, wings held a little above level
	for i in _wings.size():
		_wings[i].rotation.z = a * (1.0 if i == 0 else -1.0)
