class_name RexBoss
extends Node3D
## The Episode 2 boss model, from the show's frame: an upright green dinosaur with a banded
## pale-yellow belly, a toothy snarl, small clawed arms, dark spikes down the back and a thick
## tail curling up at the tip. Nose points to -Z; the head is about 36 units up (scale it up in game).
## The model only for now: it breathes and sways its tail in _process.

const GREEN := Color(0.4, 0.6, 0.27)
const BELLY := Color(0.74, 0.82, 0.44)
const BELLY_BAND := Color(0.6, 0.72, 0.32)
const SPIKE := Color(0.18, 0.27, 0.24)

var _body: Node3D
var _tail: Array[Node3D] = []
var _t := 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	_body = Node3D.new()
	add_child(_body)
	var green := MeshKit.toon(GREEN, 0.05, 0.75)
	var dark_green := MeshKit.toon(GREEN.darkened(0.2), 0.05, 0.75)
	var belly := MeshKit.toon(BELLY, 0.05, 0.75)
	var band := MeshKit.toon(BELLY_BAND, 0.05, 0.75)
	var spike := MeshKit.toon(SPIKE, 0.2, 0.55)
	var white := MeshKit.toon(Color(0.96, 0.95, 0.88), 0.0, 0.6)
	var claw := MeshKit.toon(Color(0.78, 0.74, 0.55), 0.0, 0.6)
	var eye := MeshKit.glow(Color(1.0, 0.86, 0.15))
	var ink := MeshKit.toon(Color(0.08, 0.05, 0.06), 0.0, 0.9)
	var mouth := MeshKit.toon(Color(0.5, 0.1, 0.12), 0.0, 0.9)
	# Legs: big thighs, shins and clawed feet.
	for sx in [-1.0, 1.0]:
		MeshKit.part(_body, MeshKit.sphere(1.0, 14), green, Vector3(4.3 * sx, 11.5, 1.0), Vector3.ZERO, Vector3(3.8, 6.5, 5.0))
		MeshKit.part(_body, MeshKit.cyl(1.9, 2.8, 6.5, 12), dark_green, Vector3(4.6 * sx, 4.6, 0.2), Vector3(0.12, 0, 0))
		MeshKit.part(_body, MeshKit.box(Vector3(3.8, 1.4, 6.2)), dark_green, Vector3(4.6 * sx, 0.9, -1.2))
		for k in 3:
			MeshKit.part(_body, MeshKit.cyl(0.0, 0.55, 1.9, 6), claw, Vector3((4.6 + (k - 1) * 1.2) * sx, 0.75, -4.7), Vector3(-PI / 2 - 0.15, 0, 0))
	# Torso with the pale belly and its darker bands.
	MeshKit.part(_body, MeshKit.sphere(1.0, 18), green, Vector3(0, 19.0, 1.0), Vector3.ZERO, Vector3(7.6, 10.5, 7.2))
	MeshKit.part(_body, MeshKit.sphere(1.0, 16), belly, Vector3(0, 18.5, -2.2), Vector3.ZERO, Vector3(5.8, 9.6, 5.2))
	for k in 7:
		var y := 11.6 + k * 2.4
		var w := 5.4 * sqrt(maxf(0.1, 1.0 - pow((y - 18.5) / 9.6, 2.0)))
		MeshKit.part(_body, MeshKit.box(Vector3(w * 2.0, 0.34, 0.5)), band, Vector3(0, y, -2.2 - 5.2 * sqrt(maxf(0.0, 1.0 - pow((y - 18.5) / 9.6, 2.0))) * 0.98))
	# Neck, head, snout, eyes, horns and teeth.
	MeshKit.part(_body, MeshKit.sphere(1.0, 14), green, Vector3(0, 27.0, -1.6), Vector3.ZERO, Vector3(4.2, 5.0, 4.4))
	MeshKit.part(_body, MeshKit.sphere(1.0, 16), green, Vector3(0, 31.2, -3.8), Vector3.ZERO, Vector3(4.6, 3.8, 5.0))
	MeshKit.part(_body, MeshKit.sphere(1.0, 14), green, Vector3(0, 29.9, -8.2), Vector3.ZERO, Vector3(3.5, 2.5, 4.7))
	MeshKit.part(_body, MeshKit.sphere(1.0, 12), belly, Vector3(0, 28.0, -7.2), Vector3.ZERO, Vector3(3.0, 1.2, 4.4)) # lower jaw
	MeshKit.part(_body, MeshKit.box(Vector3(5.6, 0.5, 8.0)), mouth, Vector3(0, 28.9, -7.6)) # open mouth
	for sx in [-1.0, 1.0]:
		MeshKit.part(_body, MeshKit.sphere(0.85, 10), eye, Vector3(2.55 * sx, 32.4, -6.0))
		MeshKit.part(_body, MeshKit.box(Vector3(0.25, 1.3, 0.25)), ink, Vector3(2.65 * sx, 32.4, -6.0))
		MeshKit.part(_body, MeshKit.cyl(0.0, 0.85, 2.6, 6), green, Vector3(2.3 * sx, 34.4, -4.4), Vector3(0.2, 0, -0.35 * sx)) # brow horns
		for k in 5: # teeth, upper and lower
			var z := -5.8 - k * 1.3
			MeshKit.part(_body, MeshKit.cyl(0.0, 0.34, 1.0, 5), white, Vector3(1.7 * sx, 28.9, z), Vector3(PI, 0, 0))
			MeshKit.part(_body, MeshKit.cyl(0.0, 0.3, 0.9, 5), white, Vector3(1.55 * sx, 28.1, z + 0.5))
	MeshKit.part(_body, MeshKit.cyl(0.0, 0.5, 1.5, 6), green, Vector3(0, 31.6, -11.0), Vector3(-0.2, 0, 0)) # nose horn
	# Small clawed arms.
	for sx in [-1.0, 1.0]:
		MeshKit.part(_body, MeshKit.cyl(0.8, 1.2, 4.2, 8), green, Vector3(5.6 * sx, 20.4, -5.4), Vector3(-1.1, 0, 0.35 * sx))
		for k in 3:
			MeshKit.part(_body, MeshKit.cyl(0.0, 0.28, 1.0, 5), claw, Vector3((5.9 + (k - 1) * 0.5) * sx, 18.9, -7.7), Vector3(-1.8, 0, 0))
	# Dark spikes down the neck and back, shrinking toward the tail.
	var spine := [[-3.0, 34.0, 2.6], [-1.0, 31.4, 3.0], [0.8, 28.6, 3.3], [2.4, 25.0, 3.6], [3.8, 21.0, 3.6], [4.6, 17.0, 3.3], [5.2, 13.5, 2.9], [6.4, 11.0, 2.4]]
	for sp in spine:
		MeshKit.part(_body, MeshKit.cyl(0.0, 0.9, float(sp[2]), 5), spike, Vector3(0, float(sp[1]) + float(sp[2]) * 0.2, float(sp[0]) + 3.2), Vector3(0.45, 0, 0))
	# The tail: thick segments narrowing and curling up at the tip.
	var seg_pos := [Vector3(0, 11.0, 7.0), Vector3(0, 9.4, 11.5), Vector3(0, 8.4, 15.6), Vector3(0, 8.6, 19.2), Vector3(0, 10.2, 22.0)]
	var seg_r := [3.6, 2.8, 2.1, 1.5, 0.9]
	var prev: Node3D = _body
	for k in seg_pos.size():
		var n := Node3D.new()
		n.position = seg_pos[k]
		_body.add_child(n)
		MeshKit.part(n, MeshKit.sphere(1.0, 12), green, Vector3.ZERO, Vector3.ZERO, Vector3(seg_r[k], seg_r[k] * 0.9, 3.0 + seg_r[k] * 0.5))
		if k < 4:
			MeshKit.part(n, MeshKit.cyl(0.0, seg_r[k] * 0.28, seg_r[k] * 1.0, 5), spike, Vector3(0, seg_r[k] * 0.95, 0), Vector3(0.3, 0, 0))
		_tail.append(n)
		prev = n


func _process(delta: float) -> void:
	_t += delta
	_body.scale = Vector3(1.0, 1.0 + sin(_t * 1.6) * 0.012, 1.0) # breathing
	for i in _tail.size():
		_tail[i].rotation.y = sin(_t * 1.2 - i * 0.5) * 0.06 * float(i)
